import ProofScript.Script.Command
import ProofScript.Info.Commands
import Mathlib.Tactic.DefEqTransformations

open Lean.Parser.Tactic (location)


script_macro «betaReduce» (clear := [loc])
"beta_reduce" loc:(location)? => `(tactic| beta_reduce $[$loc]?)

script_info «betaReduce» {
  template := [{
    lang := zh, tag := "β-规约",
    content := ""
  }, {
    lang := en, tag := "β-reduce",
    content := ""
  }]
}
