import ProofScript.Script.Command
import ProofScript.Info.Commands


/-- Describe the proof in natural language. -/
script_macro «admit» (clear := [reason])
"admit" reason:str => `(tactic| sorry)

script_info «admit» {
  renderer := «admit»
}

macro "admit" reason:str : term => `(term| script admit $reason)
