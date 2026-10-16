import ProofScript.Foundation.Source

open Lean


namespace ProofScript


abbrev ReferenceKind := String

structure ComponentData where
  kind : String
  value : Json
  /-- Declaration identity for theorem components; omitted from the exported JSON. -/
  declaration : Option Name := none
  /-- Reference identities are retained until the page's configuration boundary. -/
  references : Array Name := #[]
deriving Inhabited

instance : ToJson ComponentData where
  toJson data := Json.mkObj [(data.kind, json% { value: $(data.value) })]

structure Component where
  source : Foundation.SourceLocation
  data : ComponentData
deriving Inhabited, ToJson

structure Page where
  module : Name
  source : String
  components : Array Component
deriving Inhabited

instance : ToJson Page where
  toJson page := json% {
    module: $(page.module.toString),
    source: $(page.source),
    components: $(page.components)
  }


end ProofScript
