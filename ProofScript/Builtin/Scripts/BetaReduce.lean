import ProofScript.Script.Command
import ProofScript.Info.Script.Commands
import Mathlib.Tactic.DefEqTransformations

open Lean.Parser.Tactic (location)
open ProofScript


script_macro «betaReduce»
"beta_reduce" loc:(location)? => `(tactic| beta_reduce $[$loc]?)

script_recorder «betaReduce» => do
  with_rollback do
    record_goal "$goal_before"
    record_context "$context_before"
    record_value "locations" (← captureLocation (loc.map (·.raw)))
  execute
  record_goal "$goal_after"
  record_context "$context_after"

script_info «betaReduce» {
  templates := [{
    lang := zh, tag := "β-规约",
    content := ""
  }, {
    lang := en, tag := "β-reduce",
    content := ""
  }]
}
