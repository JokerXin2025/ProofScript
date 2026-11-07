import ProofScript.Output.Export
import ProofScript.Output.Dependencies
import ProofScript.Output.ProjectRegistry

open Lean System

unsafe def main (args : List String) : IO UInt32 := do
  match args with
  | root :: modules =>
    if modules.isEmpty then throw <| IO.userError "usage: proofscript-export OUTPUT_ROOT MODULE..."
    initSearchPath (← findSysroot)
    enableInitializersExecution
    let parseEnv ← mkEmptyEnvironment
    let owners ← modules.toArray.mapM fun text =>
      match ProofScript.printedName parseEnv text with
      | .ok value => pure value | .error message => throw <| IO.userError message
    let some sessionPath ← IO.getEnv "PROOF_SCRIPT_BUILD_MANIFEST"
      | throw <| IO.userError "ProofScript exporter requires a build manifest"
    let session ← match Json.parse (← IO.FS.readFile sessionPath) with
      | .ok value => pure value
      | .error message => throw <| IO.userError s!"invalid ProofScript build manifest: {message}"
    let registry ← ProofScript.ProjectRegistry.fromSession session owners
    -- Only the selected module is exported. Import the metadata-bearing modules
    -- that Lake built alongside it to resolve the library-wide project record.
    let available ← registry.libraryOleas.filterM fun (_, path) => path.pathExists
    let imports := (owners ++ available.map (·.1)).foldl (fun selected module =>
      if selected.contains module then selected else selected.push module) (#[] : Array Name)
      |>.map fun module => { module : Import }
    let env ← importModules imports {} (trustLevel := 0) (loadExts := true)
    let projectInfo ← match registry.metadata env with
      | .ok value => pure value
      | .error error => throw <| IO.userError error.render
    ProofScript.exportModules env owners root registry projectInfo
    return 0
  | _ => throw <| IO.userError "usage: proofscript-export OUTPUT_ROOT MODULE..."
