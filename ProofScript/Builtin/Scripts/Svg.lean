import ProofScript.Script.Command
import ProofScript.Info.Commands


script_macro «svg» (kind := metadata)
"svg" code:str => `(tactic| skip)

script_recorder «svg» auto (clear := [code])

script_info «svg» {
  renderer := «diagram»
}
