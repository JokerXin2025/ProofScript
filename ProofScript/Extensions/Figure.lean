import ProofScript.Page.Component.Core

open Lean Elab Command
open ProofScript


private structure FigureComponent where
  metadata : ComponentMetadata
  path : String
  extension : String
deriving Inhabited, Repr, ToJson, FromJson

page_component "figure" metadata:componentMeta path:str => do
  addComponentMetadataInfo metadata.raw
  when_page_build do
    match parseComponentMetadata metadata.raw with
    | .ok metadata =>
        let pathValue := path.getString
        let filePath := System.FilePath.mk pathValue
        if filePath.isAbsolute then
          throwErrorAt path.raw "#page figure requires a relative resource path"
        let some extension := filePath.extension
        | throwErrorAt path.raw "#page figure resource path must include a file extension"
        let value : FigureComponent := {
          metadata := metadata
          path := pathValue
          extension := extension
        }
        addPageComponent path.raw "figure" (toJson value) <|
          match metadata.label with
          | some label => #[("figure", label)]
          | none => #[]
    | .error message => throwErrorAt metadata.raw message
