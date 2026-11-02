import ProofScript.Script.Command
import ProofScript.Info.Commands


script_macro «left»
"left" => `(tactic| focus
  first
  | guard_target =~ (_ ∨ _)
  | fail "`left` can only be used with target connected by `∨`"
  left
)

script_info «left» {
  template := [{
    lang := "zh", tag := "明确目标",
    content := ""
  }, {
    lang := "en", tag := "",
    content := ""
  }]
}

script_macro «right»
"right" => `(tactic| focus
  first
  | guard_target =~ (_ ∨ _)
  | fail "`right` can only be used with target connected by `∨`"
  right
)

script_info «right» {
  template := [{
    lang := "zh", tag := "明确目标",
    content := ""
  }, {
    lang := "en", tag := "",
    content := ""
  }]
}
