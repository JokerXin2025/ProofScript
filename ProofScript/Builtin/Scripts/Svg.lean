import ProofScript.Script.Command
import ProofScript.Info.Commands


script_macro «svg» (kind := metadata, clear := [code])
"svg" code:str => `(tactic| skip)

script_info «svg» {
  renderer := «diagram»
}
