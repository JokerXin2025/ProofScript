import ProofScript.Script.Command
import ProofScript.Info.Script.Commands

open Lean.Parser.Tactic (location)
open ProofScript


script_macro «unfold»
"unfold" defs:(ppSpace colGt ident)+ loc:(location)? => `(tactic|
  unfold $defs* $[$loc]?
)

script_recorder «unfold» => do
  with_rollback do
    record_goal "$goal_before"
    record_context "$context_before"
    record_param "defs_before" defs
    record_value "locations" (← captureLocation (loc.map (·.raw)))
  execute
  record_goal "$goal_after"
  record_context "$context_after"

script_info «unfold» {
  templates := [{
    lang := zh, tag := "展开定义",
    content := ""
  }, {
    lang := en, tag := "unfold",
    content := ""
  }]
}
