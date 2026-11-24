import ProofScript.Script.Command
import ProofScript.Info.Script.Commands

open Lean.Parser.Tactic (location)
open ProofScript


script_macro «change»
"change " eq:term loc:(location)? => `(tactic| change $eq $[$loc]?)

script_recorder «change» => do
  with_rollback do
    record_goal "$goal_before"
    record_context "$context_before"
    record_param "eq_before" eq
    record_value "locations" (← captureLocation (loc.map (·.raw)))
  execute
  record_goal "$goal_after"
  record_context "$context_after"

script_info «change» {
  templates := [{
    lang := zh, tag := "改写",
    content := "待证目标即 ${eq_before}"
  }, {
    lang := en, tag := "",
    content := ""
  }]
}
