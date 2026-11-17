import ProofScript.Script.Command
import ProofScript.Info.Script.Commands

open Lean.Parser.Tactic (location)


script_macro «symm»
"symm" loc:(location)? => `(tactic| symm $[$loc]?)

script_recorder «symm» auto (clear := [loc])

script_info «symm» {
  templates := [{
    lang := zh, tag := "对称性",
    content := ""
  }, {
    lang := en, tag := "symm",
    content := ""
  }]
}

script_macro «symmSaturate»
"symm_saturate" => `(tactic| symm_saturate)
