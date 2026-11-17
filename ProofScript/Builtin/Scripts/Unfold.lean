import ProofScript.Script.Command
import ProofScript.Info.Script.Commands

open Lean.Parser.Tactic (location)


script_macro «unfold»
"unfold" defs:(ppSpace colGt ident)+ loc:(location)? => `(tactic|
  unfold $defs* $[$loc]?
)

script_recorder «unfold» auto (clear := [defs, loc])

script_info «unfold» {
  templates := [{
    lang := zh, tag := "展开定义",
    content := ""
  }, {
    lang := en, tag := "unfold",
    content := ""
  }]
}
