import ProofScript.Script.Command
import ProofScript.Info.Script.Commands


script_macro «exfalso»
"exfalso" => `(tactic| exfalso)

script_info «exfalso» {
  templates := [{
    lang := zh, tag := "归假",
    content := "矛盾蕴涵任何目标"
  }, {
    lang := en, tag := "exfalso",
    content := ""
  }]
}
