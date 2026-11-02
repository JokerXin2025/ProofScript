import ProofScript.Script.Command
import ProofScript.Info.Commands

open Lean.Parser.Tactic (location)


script_macro «unfold» (clear := [defs, loc])
"unfold" defs:(ppSpace colGt ident)+ loc:(location)? => `(tactic|
  unfold $defs* $[$loc]?
)

script_info «unfold» {
  template := [{
    lang := "zh", tag := "展开定义",
    content := ""
  }, {
    lang := "en", tag := "unfold",
    content := ""
  }]
}
