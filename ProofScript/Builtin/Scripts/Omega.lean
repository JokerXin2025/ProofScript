import ProofScript.Script.Command
import ProofScript.Info.Script.Commands

open Lean.Parser.Tactic (optConfig)
open ProofScript


script_macro «omega»
"omega" config:optConfig => `(tactic| omega $config)

script_recorder «omega» => do
  with_rollback do
    record_goal "$goal_before"
    record_context "$context_before"
    record_value "config" (captureConfig config)
  execute
  record_goal "$goal_after"
  record_context "$context_after"

script_info «omega» {
  templates := [{
    lang := zh, tag := "整数算术",
    content := ""
  }, {
    lang := en, tag := "omega",
    content := ""
  }]
}

script_macro «bvOmega»
"bv_omega" => `(tactic| bv_omega)
