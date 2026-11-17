import ProofScript.Info.Freeze
import ProofScript.Output.Dependencies
import ProofScript.Utils.FileSystem

open Lean System

/-- Freeze every configured target in the joint import view of a completed library. -/
unsafe def main (args : List String) : IO UInt32 := do
  let output :: moduleTexts := args
    | throw <| IO.userError "usage: proofscript-library-info OUTPUT MODULE..."
  if moduleTexts.isEmpty then
    throw <| IO.userError "library Info export requires modules"
  initSearchPath (← findSysroot)
  enableInitializersExecution
  let parser ← mkEmptyEnvironment
  let modules ← moduleTexts.toArray.mapM fun text =>
    match ProofScript.printedName parser text with
    | .ok name => pure name
    | .error message => throw <| IO.userError message
  if modules.toList.eraseDups.length != modules.size then
    throw <| IO.userError "duplicate library Info module"
  let imports := modules.map fun module => { module : Import }
  let env ← importModules imports {} (trustLevel := 0) (loadExts := true)
  -- The synthetic root imports all library modules, without introducing any
  -- writes of its own. This retains the real dependency relationships between
  -- branches when resolving conflicting writes.
  let env := env.setMainModule `ProofScript.LibraryInfoSnapshot
  let root := env.mainModule
  let mut requests : ProofScript.InfoRequests := {}
  for module in modules do
    for change in ProofScript.moduleExtensionEntries ProofScript.typedInfoChangeExt env module do
      match change with
      | .decl target _ | .resetDecl target =>
        if !requests.decls.contains target then
          requests := { requests with decls := requests.decls.push target }
      | .script target _ | .resetScript target =>
        if !requests.scripts.contains target then
          requests := { requests with scripts := requests.scripts.push target }
  let frozen ← match ProofScript.freezeRequestedInfo env root requests with
    | .ok value => pure value
    | .error message => throw <| IO.userError message
  let path := FilePath.mk output
  path.ensureParentDir
  IO.FS.writeFile path (Json.mkObj [("records", toJson frozen.toRecords)]).pretty
  return 0
