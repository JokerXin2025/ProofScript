import ProofScript.Script.Command
import ProofScript.Info.Script.Commands


script_macro «remark» (kind := metadata)
"remark" text:str => `(tactic| skip)

script_recorder «remark» auto (clear := [text])

script_info «remark» {
  renderer := «remark»
}
