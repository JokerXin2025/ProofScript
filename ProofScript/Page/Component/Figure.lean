import ProofScript.Page.Component.Core

open Lean Elab Command
open ProofScript


private structure FigureComponent where
  metadata : ComponentMetadata
  path : String
  extension : String
deriving Inhabited, Repr, ToJson, FromJson

private def addFigureComponent (metadataStx : Syntax) (pathStx : TSyntax `str)
    : CommandElabM Unit := do
  let metadata ←
    match parseComponentMetadata metadataStx with
    | .ok metadata => pure metadata
    | .error message => throwErrorAt metadataStx message
  let path := pathStx.getString
  let filePath := System.FilePath.mk path
  if filePath.isAbsolute then
    throwErrorAt pathStx "@figure requires a relative resource path"
  let some extension := filePath.extension
  | throwErrorAt pathStx "@figure resource path must include a file extension"
  let labels := match metadata.label with
                | some label => #[("figure", label)]
                | none => #[]
  let value : FigureComponent := ⟨metadata, path, extension⟩
  addPageComponent pathStx.raw "figure" (toJson value) labels

elab "@""figure" metadata:componentMeta path:str : command => do
  addComponentMetadataInfo metadata.raw
  whenPageBuild <| addFigureComponent metadata.raw path
