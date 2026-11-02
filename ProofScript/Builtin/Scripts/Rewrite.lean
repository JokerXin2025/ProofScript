import ProofScript.Script.Command
import ProofScript.Info.Commands

open Lean.Parser.Tactic (optConfig rwRuleSeq location)


script_macro «rewrite» (clear := [config, rules, loc])
"rewrite" config:optConfig rules:rwRuleSeq loc:(location)? => `(tactic|
  rewrite $config:optConfig $rules $[$loc]?
)

script_info «rewrite» {
  template := [{
    lang := "zh", tag := "代换",
    content := ""
  }, {
    lang := "en", tag := "subst",
    content := ""
  }]
}

script_macro «rw» (clear := [config, rules, loc])
"rw" config:optConfig rules:rwRuleSeq loc:(location)? => `(tactic|
  rw $config:optConfig $rules $[$loc]?
)

script_info «rw» {
  template := [{
    lang := "zh", tag := "代换",
    content := ""
  }, {
    lang := "en", tag := "subst",
    content := ""
  }]
}

#guard_msgs (drop info) in
#check if_pos
macro "rw_pos" h:term loc:(location)? : tactic => `(tactic|
  rw [if_pos $h] $[$loc]?
)

script_macro «rwPos»  (clear := [h, loc])
"rw_pos" h:term loc:(location)? => `(tactic| rw_pos $h $[$loc]?)

script_info «rwPos» {
  template := [{
    lang := "zh", tag := "明确目标",
    content := ""
  }, {
    lang := "en", tag := "",
    content := ""
  }]
}

#guard_msgs (drop info) in
#check if_neg
macro "rw_neg" h:term loc:(location)? : tactic => `(tactic|
  rw [if_neg $h] $[$loc]?
)

script_macro «rwNeg»  (clear := [h, loc])
"rw_neg" h:term loc:(location)? => `(tactic| rw_neg $h $[$loc]?)

script_info «rwNeg» {
  template := [{
    lang := "zh", tag := "明确目标",
    content := ""
  }, {
    lang := "en", tag := "",
    content := ""
  }]
}
