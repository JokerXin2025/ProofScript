import ProofScript.Script.Command
import ProofScript.Info.Commands


script_macro «assumption»
"assumption" => `(tactic| assumption)

script_info «assumption» {
  template := [{
    lang := zh, tag := "已知",
    content := "目标已经作为假设给出"
  }, {
    lang := en, tag := "given",
    content := "The goal is already given as an assumption"
  }]
}
