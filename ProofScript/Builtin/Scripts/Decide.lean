import ProofScript.Script.Command
import ProofScript.Info.Script.Commands

open Lean.Parser.Tactic (optConfig)
open ProofScript


script_macro «decide»
"decide" config:optConfig => `(tactic| decide $config)

script_recorder «decide» => do
  with_rollback do
    record_goal "$goal_before"
    record_context "$context_before"
    record_value "config" (captureConfig config)
  execute
  record_goal "$goal_after"
  record_context "$context_after"

script_info «decide» {
  templates := [{
    lang := zh, tag := "判定",
    content := ""
  }, {
    lang := en, tag := "decide",
    content := ""
  }]
}

script_macro «nativeDecide»
"native_decide" config:optConfig => `(tactic| native_decide $config)

script_recorder «nativeDecide» => do
  with_rollback do
    record_goal "$goal_before"
    record_context "$context_before"
    record_value "config" (captureConfig config)
  execute
  record_goal "$goal_after"
  record_context "$context_after"
