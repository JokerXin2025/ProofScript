import ProofScript.Script.Command
import ProofScript.Info.Script.Commands


script_macro «congr»
"congr" num:(ppSpace num)? => `(tactic| congr $[$num]?)

script_recorder «congr» auto (clear := [num])

script_info «congr» {
  templates := [{
    lang := zh, tag := "同余性",
    content := ""
  }, {
    lang := en, tag := "congr",
    content := ""
  }]
}
