import ProofScript.Script.Command
import ProofScript.Info.Commands

open Lean.Parser.Tactic (optConfig)


script_macro «omega» (clear := [config])
"omega" config:optConfig => `(tactic| omega $config)

script_info «omega» {
  template := [{
    lang := "zh", tag := "整数算术",
    content := ""
  }, {
    lang := "en", tag := "omega",
    content := ""
  }]
}

script_macro «bvOmega»
"bv_omega" => `(tactic| bv_omega)
