import ProofScript.Output.Module
import ProofScript.Output.Dependencies

open Lean System

/-- Export one completed page-mode module without loading or invoking PS4HTML. -/
unsafe def main (args : List String) : IO UInt32 := do
  let [descriptor, output, publisher, framework, ownerText] := args
    | throw <| IO.userError
        "usage: proofscript-module-export DESCRIPTOR OUTPUT_ROOT PUBLISHER PROOFSCRIPT_ROOT MODULE"
  initSearchPath (← findSysroot)
  enableInitializersExecution
  let owner ← match ProofScript.printedName (← mkEmptyEnvironment) ownerText with
    | .ok value => pure value
    | .error message => throw <| IO.userError message
  let some manifestFile ← IO.getEnv "PROOF_SCRIPT_BUILD_MANIFEST"
    | throw <| IO.userError "module export requires a Lake build manifest"
  let session ← match Json.parse (← IO.FS.readFile manifestFile) with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let registry ← ProofScript.ProjectRegistry.fromSession session #[owner]
  let env ← importModules #[{ module := owner }] {} (trustLevel := 0) (loadExts := true)
  let moduleEntries : Array Json ← match session.getObjValAs? (Array Json) "modules" with
    | .ok value => pure value
    | .error message => throw <| IO.userError message
  let some moduleEntry := moduleEntries.find? fun entry =>
    (entry.getObjValAs? String "name").toOption == some ownerText
    | throw <| IO.userError s!"missing module source for {owner}"
  let source ← match moduleEntry.getObjValAs? String "source" with
    | .ok path => pure path
    | .error message => throw <| IO.userError message
  let value ← ProofScript.moduleDescriptor env registry owner source
  let expected ← match session.getObjValAs? String "moduleManifest" with
    | .ok value => pure value
    | .error message => throw <| IO.userError message
  unless (value.getObjValAs? String "manifest").toOption == some expected do
    throw <| IO.userError "Lake and Lean disagree on the encoded module path"
  let descriptorPath := FilePath.mk descriptor
  descriptorPath.ensureParentDir
  IO.FS.writeFile descriptorPath value.pretty
  let python := (← IO.getEnv "PROOF_SCRIPT_PYTHON").getD "python3"
  let process ← IO.Process.output {
    cmd := python,
    args := #[publisher, descriptor, output, (← IO.currentDir).toString, framework, manifestFile]
  }
  unless process.exitCode == 0 do
    throw <| IO.userError s!"ProofScript module publication failed: {process.stderr}\n{process.stdout}"
  return 0
