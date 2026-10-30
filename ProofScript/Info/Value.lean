import ProofScript.Utils.JsonPath
import ProofScript.Foundation.Source

namespace ProofScript

open Lean

abbrev ExtraValue := Json

/-- A separate namespace for extension keys; builtin fields never read from this object. -/
structure ExtraFields where
  values : Std.TreeMap.Raw String ExtraValue := {}
  deriving Inhabited

def ExtraFields.find? (fields : ExtraFields) (key : String) : Option ExtraValue :=
  fields.values.get? key

def ExtraFields.set (fields : ExtraFields) (key : String) (value : ExtraValue) : ExtraFields :=
  { values := fields.values.insert key value }

def ExtraFields.erase (fields : ExtraFields) (key : String) : ExtraFields :=
  { values := fields.values.erase key }

def ExtraFields.toJson (fields : ExtraFields) : Json := .obj fields.values

def ExtraFields.fromJson (value : Json) : Except String ExtraFields := do
  let object ← value.getObj?
  return { values := object }

instance : ToJson ExtraFields := ⟨ExtraFields.toJson⟩
instance : FromJson ExtraFields := ⟨ExtraFields.fromJson⟩

structure RelatedSource where
  owner : Name
  sequence : Nat
  source : SourceLocation
  deriving Inhabited, Repr, BEq, ToJson

structure Diagnostic where
  message : String
  path : JsonPath := #[]
  source : Option SourceLocation := none
  kind : Option String := none
  target : Option String := none
  relatedPaths : Array JsonPath := #[]
  related : Array RelatedSource := #[]
  deriving Inhabited, Repr

def Diagnostic.atField (name : String) (error : Diagnostic) : Diagnostic :=
  { error with path := #[.key name] ++ error.path }

def Diagnostic.atIndex (index : Nat) (error : Diagnostic) : Diagnostic :=
  { error with path := #[.index index] ++ error.path }

def Diagnostic.render (error : Diagnostic) : String :=
  let text := if error.path.isEmpty then error.message else s!"{JsonPath.render error.path}: {error.message}"
  let text := match error.kind, error.target with
    | some kind, some target => s!"{kind} `{target}`: {text}"
    | _, _ => text
  if error.related.isEmpty then text else
    text ++ "\n" ++ String.intercalate "\n" (error.related.toList.map fun origin =>
      s!"  {origin.owner} #{origin.sequence}: {origin.source.file}:{origin.source.start}-{origin.source.stop}")

instance : ToString Diagnostic := ⟨Diagnostic.render⟩

end ProofScript
