import ProofScript.Script.Command
import ProofScript.Info.Script.Commands

open Lean.Parser.Tactic (optConfig)


script_macro «decide»
"decide" config:optConfig => `(tactic| decide $config)

script_recorder «decide» auto (clear := [config])

script_info «decide» {
  templates := [{
    lang := zh, tag := "判定",
    content := ""
  }, {
    lang := en, tag := "decide",
    content := ""
  }]
}

script_macro «nativeDecide»
"native_decide" config:optConfig => `(tactic| native_decide $config)

script_recorder «nativeDecide» auto (clear := [config])
