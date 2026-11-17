import ProofScript.Script.Command
import ProofScript.Info.Script.Commands


/-- Describe the proof in natural language. -/
script_macro «admit»
"admit" reason:str => `(tactic| sorry)

script_recorder «admit» auto (clear := [reason])

script_info «admit» {
  renderer := «admit»
}

macro "admit" reason:str : term => `(term| script admit $reason)
