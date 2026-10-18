import ProofScript.Foundation.Source
import ProofScript.Info.State

open Lean


namespace ProofScript

abbrev ReferenceKind := String

structure Component where
  source : Foundation.SourceLocation
  kind : String
  value : Json
  /-- Declaration identity for theorem components; omitted from the exported JSON. -/
  declaration : Option Name := none
  /-- Reference identities are resolved at this component's creation boundary. -/
  references : Array Name := #[]
  /-- Internal position in the current module's metadata transaction stream. -/
  boundary : Info.Boundary := .endOfModule
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
