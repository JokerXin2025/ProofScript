import ProofScript.Script.Command
import ProofScript.Info.Script.Commands


script_macro «by»
"by " tac:tactic decr:(str)? => `(tactic| $tac)

script_recorder «by» => do
  record_value "decr_before" (decr.map (·.getString) |>.getD "")
  execute

script_info «by» {
  templates := [{
    lang := zh, tag := "未知",
    content := "${decr_before}"
  }, {
    lang := en, tag := "unknown",
    content := "${decr_before}"
  }]
}
