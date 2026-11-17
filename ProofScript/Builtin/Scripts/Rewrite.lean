import ProofScript.Script.Command
import ProofScript.Info.Script.Commands

open Lean.Parser.Tactic (optConfig rwRuleSeq location)


script_macro «rewrite»
"rewrite" config:optConfig rules:rwRuleSeq loc:(location)? => `(tactic|
  rewrite $config:optConfig $rules $[$loc]?
)

script_recorder «rewrite» auto (clear := [config, rules, loc])

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

script_recorder «rw» auto (clear := [config, rules, loc])

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

script_recorder «rwPos» auto (clear := [h, loc])

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

script_recorder «rwNeg» auto (clear := [h, loc])

script_info «rwNeg» {
  templates := [{
    lang := zh, tag := "明确目标",
    content := ""
  }, {
    lang := en, tag := "",
    content := ""
  }]
}
