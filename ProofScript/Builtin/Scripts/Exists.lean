import ProofScript.Script.Command
import ProofScript.Info.Script.Commands


script_macro «exists»
"exists " data:term => `(tactic| focus
  first
  | guard_target =~ (∃ _, _)
  | fail "`exists` can only be used with `∃` target"
  refine ⟨$data, ?_⟩
  try trivial
)

script_recorder «exists» auto (clear := [data])

script_info «exists» {
  templates := [{
    lang := zh, tag := "选取对象",
    content := ""
  }, {
    lang := en, tag := "choose",
    content := ""
  }]
}

script_macro «existsWith»
"exists " data:term "with" cond:term => `(tactic| focus
  first
  | guard_target =~ (∃ _, _ ∧ _)
  | fail "`exists` can only be used with `∃` target"
  refine ⟨$data, $cond, ?_⟩
  try trivial
)

script_recorder «existsWith» auto (clear := [data, cond])

script_info «existsWith» {
  templates := [{
    lang := zh, tag := "选取对象",
    content := ""
  }, {
    lang := en, tag := "choose",
    content := ""
  }]
}
