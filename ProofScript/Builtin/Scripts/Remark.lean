import ProofScript.Script.Command
import ProofScript.Info.Commands


script_macro «remark» (kind := metadata, clear := [text])
"remark" text:str => `(tactic| skip)

script_info «remark» {
  renderer := «remark»
}
