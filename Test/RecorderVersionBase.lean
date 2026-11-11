import ProofScript.Script.Command

open Lean ProofScript Elab Tactic

script_elab importedRecorder "imported_recorder" => do
  evalTactic (← `(tactic| trivial))

script_recorder importedRecorder (label := "base") => do
  execute
  record_value "base" true
