import ProofScript.Script.Command
import ProofScript.Info.Commands

open Lean.Parser.Tactic (location)


script_macro «change»
"change " eq:term loc:(location)? => `(tactic| change $eq $[$loc]?)

script_recorder «change» auto (clear := [eq, loc])

script_info «change» {
  template := [{
    lang := zh, tag := "改写",
    content := "待证目标即 ${eq_before}"
  }, {
    lang := en, tag := "",
    content := ""
  }]
}
