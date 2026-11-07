import ProofScript.Script.Command
import ProofScript.Info.Commands


script_macro «exists» (clear := [data])
"exists " data:term => `(tactic| focus
  first
  | guard_target =~ (∃ _, _)
  | fail "`exists` can only be used with `∃` target"
  refine ⟨$data, ?_⟩
  try trivial
)

script_info «exists» {
  template := [{
    lang := zh, tag := "选取对象",
    content := ""
  }, {
    lang := en, tag := "choose",
    content := ""
  }]
}

script_macro «existsWith»  (clear := [data, cond])
"exists " data:term "with" cond:term => `(tactic| focus
  first
  | guard_target =~ (∃ _, _ ∧ _)
  | fail "`exists` can only be used with `∃` target"
  refine ⟨$data, $cond, ?_⟩
  try trivial
)

script_info «existsWith» {
  template := [{
    lang := zh, tag := "选取对象",
    content := ""
  }, {
    lang := en, tag := "choose",
    content := ""
  }]
}
