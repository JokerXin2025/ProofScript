import ProofScript.Script.Command
import ProofScript.Info.Commands

open Lean.Parser.Tactic (location)


script_macro «symm» (clear := [loc])
"symm" loc:(location)? => `(tactic| symm $[$loc]?)

script_info «symm» {
  template := [{
    lang := "zh", tag := "对称性",
    content := ""
  }, {
    lang := "en", tag := "symm",
    content := ""
  }]
}

script_macro «symmSaturate»
"symm_saturate" => `(tactic| symm_saturate)
