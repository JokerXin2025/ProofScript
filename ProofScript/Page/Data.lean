import Lean

open Lean


namespace ProofScript


structure SourceLocation where
  file : String
  start : Nat
  stop : Nat
deriving Inhabited, Repr, ToJson, FromJson

abbrev ReferenceKind := String

structure ComponentData where
  kind : String
  value : Json
  /-- Declaration identity for theorem components; omitted from the exported JSON. -/
  declaration : Option Name := none
deriving Inhabited

instance : ToJson ComponentData where
  toJson data := Json.mkObj [(data.kind, Json.mkObj [("value", data.value)])]

structure Component where
  source : SourceLocation
  data : ComponentData
deriving Inhabited, ToJson

structure Page where
  module : Name
  source : String
  components : Array Component
deriving Inhabited

instance : ToJson Page where
  toJson page := Json.mkObj [
    ("module", Json.str page.module.toString),
    ("source", Json.str page.source),
    ("components", toJson page.components)
  ]


end ProofScript
