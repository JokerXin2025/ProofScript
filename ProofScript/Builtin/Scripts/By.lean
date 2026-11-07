import ProofScript.Script.Command
import ProofScript.Info.Commands


script_macro «by» (clear := [tac, decr])
"by " tac:tactic decr:(str)? => `(tactic| $tac)

script_info «by» {
  template := [{
    lang := zh, tag := "未知",
    content := "${decr_before}"
  }, {
    lang := en, tag := "unknown",
    content := "${decr_before}"
  }]
}
