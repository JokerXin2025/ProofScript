import ProofScript.Script.Command
import ProofScript.Info.Script.Commands

open Lean.Parser.Tactic (optConfig rwRuleSeq location)
open ProofScript


script_macro «rewrite»
"rewrite" config:optConfig rules:rwRuleSeq loc:(location)? => `(tactic|
  rewrite $config:optConfig $rules $[$loc]?
)

script_recorder «rewrite» => do
  with_rollback do
    record_goal "$goal_before"
    record_context "$context_before"
    record_value "config" (captureConfig config)
    record_value "rules" (← captureRewriteRules ⟨rules.raw⟩)
    record_value "locations" (← captureLocation (loc.map (·.raw)))
  execute
  record_goal "$goal_after"
  record_context "$context_after"

script_info «rewrite» {
  templates := [{
    lang := zh, tag := "代换",
    content := ""
  }, {
    lang := en, tag := "subst",
    content := ""
  }]
}

script_macro «rw»
"rw " config:optConfig rules:rwRuleSeq loc:(location)? => `(tactic|
  rw $config:optConfig $rules $[$loc]?
)

script_recorder «rw» => do
  with_rollback do
    record_goal "$goal_before"
    record_context "$context_before"
    record_value "config" (captureConfig config)
    record_value "rules" (← captureRewriteRules ⟨rules.raw⟩)
    record_value "locations" (← captureLocation (loc.map (·.raw)))
  execute
  record_goal "$goal_after"
  record_context "$context_after"

script_info «rw» {
  templates := [{
    lang := zh, tag := "代换",
    content := ""
  }, {
    lang := en, tag := "subst",
    content := ""
  }]
}

#guard_msgs (drop info) in
#check if_pos
macro "rw_pos " h:term loc:(location)? : tactic => `(tactic|
  rw [if_pos $h] $[$loc]?
)

script_macro «rwPos»
"rw_pos " h:term loc:(location)? => `(tactic| rw_pos $h $[$loc]?)

script_recorder «rwPos» => do
  with_rollback do
    record_goal "$goal_before"
    record_context "$context_before"
    record_param "h_before" h
    record_value "locations" (← captureLocation (loc.map (·.raw)))
  execute
  record_goal "$goal_after"
  record_context "$context_after"

script_info «rwPos» {
  templates := [{
    lang := zh, tag := "明确目标",
    content := ""
  }, {
    lang := en, tag := "",
    content := ""
  }]
}

#guard_msgs (drop info) in
#check if_neg
macro "rw_neg " h:term loc:(location)? : tactic => `(tactic|
  rw [if_neg $h] $[$loc]?
)

script_macro «rwNeg»
"rw_neg " h:term loc:(location)? => `(tactic| rw_neg $h $[$loc]?)

script_recorder «rwNeg» => do
  with_rollback do
    record_goal "$goal_before"
    record_context "$context_before"
    record_param "h_before" h
    record_value "locations" (← captureLocation (loc.map (·.raw)))
  execute
  record_goal "$goal_after"
  record_context "$context_after"

script_info «rwNeg» {
  templates := [{
    lang := zh, tag := "明确目标",
    content := ""
  }, {
    lang := en, tag := "",
    content := ""
  }]
}
