import ProofScript.Foundation.Source

namespace ProofScript.Info

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

inductive PathPart where
  | field (name : String)
  | index (value : Nat)
  deriving Inhabited, Repr, BEq

abbrev FieldPath := Array PathPart

def renderPath (path : FieldPath) : String :=
  path.foldl (init := "") fun text part => match part with
    | .field name => if text.isEmpty then name else text ++ "." ++ name
    | .index index => text ++ s!"[{index}]"

structure RelatedSource where
  owner : Name
  sequence : Nat
  source : Foundation.SourceLocation
  deriving Inhabited, Repr, BEq

structure Diagnostic where
  message : String
  path : FieldPath := #[]
  source : Option Foundation.SourceLocation := none
  kind : Option String := none
  target : Option String := none
  relatedPaths : Array FieldPath := #[]
  related : Array RelatedSource := #[]
  deriving Inhabited, Repr

def Diagnostic.atField (name : String) (error : Diagnostic) : Diagnostic :=
  { error with path := #[.field name] ++ error.path }

def Diagnostic.atIndex (index : Nat) (error : Diagnostic) : Diagnostic :=
  { error with path := #[.index index] ++ error.path }

def Diagnostic.render (error : Diagnostic) : String :=
  let text := if error.path.isEmpty then error.message else s!"{renderPath error.path}: {error.message}"
  let text := match error.kind, error.target with
    | some kind, some target => s!"{kind} `{target}`: {text}"
    | _, _ => text
  if error.related.isEmpty then text else
    text ++ "\n" ++ String.intercalate "\n" (error.related.toList.map fun origin =>
      s!"  {origin.owner} #{origin.sequence}: {origin.source.file}:{origin.source.start}-{origin.source.stop}")

instance : ToString Diagnostic := ⟨Diagnostic.render⟩

end ProofScript.Info
