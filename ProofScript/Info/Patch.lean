import ProofScript.Info.Schema

namespace ProofScript.Info

open Lean

/-- Builtin and extension identities remain distinct even if a future schema adds the same name. -/
inductive FieldKey where
  | builtin (name : String)
  | extra (name : String)
  deriving Inhabited, Repr, BEq, ToJson, FromJson

inductive UpdateOperation where
  | set (value : Json)
  | reset
  deriving Inhabited, ToJson, FromJson

structure Assignment where
  key : FieldKey
  operation : UpdateOperation
  source : Foundation.SourceLocation
  deriving Inhabited, ToJson, FromJson

abbrev Patch := Array Assignment

/-- Context initialization uses generated typed handles instead of spelling field names. -/
def FieldHandle.assignment [InfoCodec Value] (handle : FieldHandle Record Value) (value : Value)
    (source : Foundation.SourceLocation) : Assignment :=
  { key := .builtin handle.name, operation := .set (toJson value), source }

def FieldSpec.mergeJson (field : FieldSpec Record) (previous : Option Json) (update : Json) :
    Except Diagnostic Json := do
  let _ : ToJson field.Value := field.codec.toToJson
  let fresh ← field.decode update
  match field.handle.merge with
  | .replace => return toJson fresh
  | .keyed split join =>
    let old ← match previous.or field.defaultJson with
      | some value => field.decode value >>= split
      | none => pure #[]
    let changes ← split fresh
    let mut result := old
    for (key, value) in changes do
      if let some index := result.findIdx? (·.1 == key) then
        result := result.set! index (key, value)
      else result := result.push (key, value)
    let value ← join result
    field.checkValue value
    return toJson value

/-- Apply one local patch without demanding completeness or cross-field validity. -/
def applyPatch (schema : InfoSchema Record) (previous : Json) (patch : Patch) : Except Diagnostic Json := do
  let mut object ← previous.getObj?.mapError fun message => { message }
  for assignment in patch do
    match assignment.key with
    | .builtin name =>
      let some field := schema.fields.find? (fun field => field.name == name && !field.handle.isExtra)
        | throw { message := s!"unknown builtin field `{name}`", source := some assignment.source }
      match assignment.operation with
      | .reset => object := object.erase name
      | .set value =>
        let value ← (field.mergeJson (object.get? name) value).mapError fun error =>
          { (Diagnostic.atField name error) with source := some assignment.source }
        object := object.insert name value
    | .extra key =>
      let some field := schema.extraField?
        | throw { message := "this schema does not support extension fields", source := some assignment.source }
      let mut extra ← match (object.get? field.name).or field.defaultJson with
        | some value => value.getObj?.mapError fun message => { message }
        | none => pure {}
      match assignment.operation with
      | .reset => extra := extra.erase key
      | .set value => extra := extra.insert key value
      object := object.insert field.name (.obj extra)
  return .obj object

end ProofScript.Info
