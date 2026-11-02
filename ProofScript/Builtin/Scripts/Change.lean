import ProofScript.Script.Command
import ProofScript.Info.Commands

open Lean.Parser.Tactic (location)


script_macro «change» (clear := [eq, loc])
"change" eq:term loc:(location)? => `(tactic| change $eq $[$loc]?)

script_info «change» {
  template := [{
    lang := "zh", tag := "改写",
    content := "待证目标即 ${eq_before}"
  }, {
    lang := "en", tag := "",
    content := ""
  }]
}
