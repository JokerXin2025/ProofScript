import ProofScript.Output.Export
import ProofScript.Output.Dependencies

open Lean System

unsafe def main (args : List String) : IO UInt32 := do
  match args with
  | root :: modules =>
    if modules.isEmpty then throw <| IO.userError "usage: proofscript-export OUTPUT_ROOT MODULE..."
    initSearchPath (← findSysroot)
    enableInitializersExecution
    let parseEnv ← mkEmptyEnvironment
    let owners ← modules.toArray.mapM fun text =>
      match ProofScript.Output.printedName parseEnv text with
      | .ok value => pure value | .error message => throw <| IO.userError message
    let imports := owners.map fun module => { module : Import }
    let env ← importModules imports {} (trustLevel := 0) (loadExts := true)
    ProofScript.Output.exportModules env owners root
    return 0
  | _ => throw <| IO.userError "usage: proofscript-export OUTPUT_ROOT MODULE..."
