import ProofScript.Script.Command
import ProofScript.Info.Script.Commands
import ProofScript.Page.Component.Core

open Lean ProofScript

script_macro «svg» (kind := metadata)
"svg" metadata:componentMeta code:str => `(tactic| skip)

script_recorder «svg» => do
  let metadata ←
    match parseComponentMetadata metadata.raw with
    | .ok value => pure value
    | .error message => throwErrorAt metadata message
  record_value "metadata" (toJson metadata)
  record_value "code" code.getString
  execute

script_info «svg» {
  renderer := «svg»
}
