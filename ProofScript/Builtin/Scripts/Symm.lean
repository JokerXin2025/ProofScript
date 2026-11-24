import ProofScript.Script.Command
import ProofScript.Info.Script.Commands

open Lean.Parser.Tactic (location)
open ProofScript


script_macro «symm»
"symm" loc:(location)? => `(tactic| symm $[$loc]?)

script_recorder «symm» => do
  with_rollback do
    record_goal "$goal_before"
    record_context "$context_before"
    record_value "locations" (← captureLocation (loc.map (·.raw)))
  execute
  record_goal "$goal_after"
  record_context "$context_after"

script_info «symm» {
  templates := [{
    lang := zh, tag := "对称性",
    content := ""
  }, {
    lang := en, tag := "symm",
    content := ""
  }]
}

script_macro «symmSaturate»
"symm_saturate" => `(tactic| symm_saturate)
