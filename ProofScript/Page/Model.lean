import ProofScript.Foundation.Source
import ProofScript.Core.References

open Lean


namespace ProofScript

abbrev ReferenceKind := String

structure Component where
  source : SourceLocation
  kind : String
  value : Json
  /-- Declaration identity for theorem components; omitted from the exported JSON. -/
  declaration : Option Name := none
  /-- Reference metadata is resolved in the page owner's final module view. -/
  references : Array RefInfo := #[]
  snapshotId : Option String := none
deriving Inhabited

instance : ToJson Component where
  toJson component := Json.mkObj <|
    [("source", toJson component.source),
      ("data", Json.mkObj [(component.kind, json% { value: $(component.value) })])] ++
      component.snapshotId.toList.map fun id => ("snapshotId", toJson id)

structure Page where
  module : Name
  source : String
  components : Array Component
deriving Inhabited, ToJson

end ProofScript
