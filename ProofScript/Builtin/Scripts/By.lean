import ProofScript.Script.Command
import ProofScript.Info.Commands


script_macro «by»
"by " tac:tactic decr:(str)? => `(tactic| $tac)

script_recorder «by» => do
  record_value "decr_before" (decr.map (·.getString) |>.getD "")
  execute

script_info «by» {
  template := [{
    lang := zh, tag := "未知",
    content := "${decr_before}"
  }, {
    lang := en, tag := "unknown",
    content := "${decr_before}"
  }]
}
