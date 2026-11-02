import ProofScript.Script.Command
import ProofScript.Info.Commands


script_macro «contradiction»
"contradiction" => `(tactic| contradiction)

script_info «contradiction» {
  template := [{
    lang := "zh", tag := "矛盾",
    content := ""
  }, {
    lang := "en", tag := "contra",
    content := ""
  }]
}
