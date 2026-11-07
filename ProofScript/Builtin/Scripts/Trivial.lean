import ProofScript.Script.Command
import ProofScript.Info.Commands


script_macro «trivial»
"trivial" => `(tactic| trivial)

script_info «trivial» {
  template := [{
    lang := zh, tag := "显然",
    content := "显然该命题成立"
  }, {
    lang := en, tag := "trivial",
    content := ""
  }]
}
