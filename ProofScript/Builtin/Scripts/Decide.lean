import ProofScript.Script.Command
import ProofScript.Info.Commands

open Lean.Parser.Tactic (optConfig)


script_macro «decide» (clear := [config])
"decide" config:optConfig => `(tactic| decide $config)

script_info «decide» {
  template := [{
    lang := zh, tag := "判定",
    content := ""
  }, {
    lang := en, tag := "decide",
    content := ""
  }]
}

script_macro «nativeDecide» (clear := [config])
"native_decide" config:optConfig => `(tactic| native_decide $config)
