import ProofScript.Script.Command
import ProofScript.Info.Script.Commands
import ProofScript.Page.Component.Core

open Lean ProofScript

script_macro «svg» (kind := metadata)
"svg" metadata:componentMeta code:str => `(tactic| skip)

script_recorder «svg» => do
  with_rollback do
    let metadata ←
      match parseComponentMetadata metadata.raw with
      | .ok value => pure value
      | .error message => throwErrorAt metadata message
    record_value "metadata_title" metadata.title
    record_value "metadata_label" metadata.label
    record_value "metadata_extra_names" (metadata.extra.map Prod.fst)
    record_value "metadata_extra_values" (metadata.extra.map Prod.snd)
    record_value "code" code.getString
  execute

script_info «svg» {
  renderer := «svg»
}
