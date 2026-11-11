import ProofScript.Script.Command
import ProofScript.Info.Commands


script_macro «congr»
"congr" num:(ppSpace num)? => `(tactic| congr $[$num]?)

script_recorder «congr» auto (clear := [num])

script_info «congr» {
  template := [{
    lang := zh, tag := "同余性",
    content := ""
  }, {
    lang := en, tag := "congr",
    content := ""
  }]
}
