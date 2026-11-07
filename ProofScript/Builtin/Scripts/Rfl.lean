import ProofScript.Script.Command
import ProofScript.Info.Commands


script_macro «rfl»
"rfl" => `(tactic| rfl)

script_info «rfl» {
  template := [{
    lang := zh, tag := "自反性",
    content := ""
  }, {
    lang := en, tag := "refl",
    content := ""
  }]
}

script_macro «rfl'»
"rfl'" => `(tactic| rfl')

script_macro «eqRefl»
"eq_refl" => `(tactic| eq_refl)

script_macro «applyRfl»
"apply_rfl" => `(tactic| apply_rfl)

script_macro «acRfl»
"ac_rfl" => `(tactic| ac_rfl)
