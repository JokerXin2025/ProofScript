import ProofScript.Info.Codec
import ProofScript.Foundation.Name

namespace ProofScript.Info

open Lean Elab Command

instance : Coe Name (Name ⊕ String) := ⟨Sum.inl⟩
instance : Coe String (Name ⊕ String) := ⟨Sum.inr⟩
instance : Inhabited (Name ⊕ String) := ⟨.inl .anonymous⟩

instance : ToString (Name ⊕ String) := ⟨fun target => target.elim toString id⟩

/-- A keyed field supplies both its conflict units and a typed reconstruction. -/
inductive MergePolicy (α : Type) where
  | replace
  | keyed (split : α → Except Diagnostic (Array (String × Json)))
      (join : Array (String × Json) → Except Diagnostic α)

def keyedArray [InfoCodec α] (key : α → String) : MergePolicy (Array α) :=
  .keyed (fun values => do
    let mut result := #[]
    for value in values do
      let name := key value
      if name.isEmpty then throw { message := "merge key must not be empty" }
      if result.any (·.1 == name) then throw { message := s!"duplicate merge key `{name}`" }
      result := result.push (name, toJson value)
    return result) (fun values => values.mapM fun (_, value) => InfoCodec.decode value)

/-- Generated handles retain the field's value type for special-rule overrides. -/
structure FieldHandle (Record Value : Type) where
  name : String
  get : Record → Value
  set : Record → Value → Record
  defaultValue : Option Value := none
  aliases : Array String := #[]
  merge : MergePolicy Value := .replace
  validate : Value → Except String Unit := fun _ => pure ()
  isExtra : Bool := false

structure FieldSpec (Record : Type) where
  Value : Type
  codec : InfoCodec Value
  handle : FieldHandle Record Value

def FieldHandle.toSpec [InfoCodec Value] (handle : FieldHandle Record Value) : FieldSpec Record :=
  ⟨Value, inferInstance, handle⟩

def FieldSpec.name (field : FieldSpec Record) : String := field.handle.name

def FieldSpec.matches (field : FieldSpec Record) (name : String) : Bool :=
  field.name == name || field.handle.aliases.contains name

def FieldSpec.checkValue (field : FieldSpec Record) (value : field.Value) : Except Diagnostic Unit := do
  (field.handle.validate value).mapError fun message => { message }
  if let .keyed split _ := field.handle.merge then
    discard <| split value

def FieldSpec.parse (field : FieldSpec Record) (stx : TSyntax `term) : CommandElabM Json := do
  let _ : ToJson field.Value := field.codec.toToJson
  let value ← field.codec.parse stx
  if let .error error := field.checkValue value then
    throwErrorAt stx (Diagnostic.atField field.name error).render
  return toJson value

def FieldSpec.decode (field : FieldSpec Record) (value : Json) : Except Diagnostic field.Value := do
  let value ← field.codec.decode value
  field.checkValue value
  return value

def FieldSpec.defaultJson (field : FieldSpec Record) : Option Json :=
  let _ : ToJson field.Value := field.codec.toToJson
  field.handle.defaultValue.map toJson

def FieldSpec.jsonSchema (field : FieldSpec Record) : Json :=
  match field.defaultJson with
  | some value => field.codec.jsonSchema.setObjVal! "default" value
  | none => field.codec.jsonSchema

structure Schema (Record : Type) where
  id : Name
  version : String := "1.0.0"
  fields : Array (FieldSpec Record)
  /-- Receives an object with every field provided, including defaults. -/
  decodeValues : Json → Except Diagnostic Record
  validateRecord : Record → Except Diagnostic Unit := fun _ => pure ()

class InfoSchema (Record : Type) where
  schema : Schema Record

/-- Consumers may defer completeness; parsing a patch never constructs a record. -/
structure InfoSpec (Record : Type) where
  kind : String
  schema : Schema Record
  dependencies : Record → Array (String × (Name ⊕ String)) := fun _ => #[]

def Schema.findField? (schema : Schema Record) (name : String) : Option (FieldSpec Record) :=
  schema.fields.find? (·.matches name)

def Schema.extraField? (schema : Schema Record) : Option (FieldSpec Record) :=
  schema.fields.find? (·.handle.isExtra)

def Schema.validateDefinition (schema : Schema Record) : Except Diagnostic Unit := do
  let mut names : Array String := #[]
  let mut extraFound := false
  for field in schema.fields do
    if field.handle.isExtra then
      if extraFound || field.name != "extra" then
        throw { message := "schema must have at most one extension field named `extra`" }
      extraFound := true
    else if field.name == "extra" then
      throw { message := "`extra` is reserved for ExtraFields" }
    for name in #[field.name] ++ field.handle.aliases do
      if name.isEmpty || names.contains name || (name == "extra" && !field.handle.isExtra) then
        throw { message := s!"duplicate or reserved schema field name `{name}`" }
      names := names.push name
    if let some value := field.handle.defaultValue then
      let _ : ToJson field.Value := field.codec.toToJson
      discard <| (field.decode (toJson value)).mapError (Diagnostic.atField field.name)

def Schema.encode (schema : Schema Record) (record : Record) : Json :=
  Json.mkObj (schema.fields.toList.map fun (field : FieldSpec Record) =>
    let _ : ToJson field.Value := field.codec.toToJson
    (field.name, toJson (field.handle.get record)))

/-- Wire decoding accepts only schema field names; extension keys belong inside extra. -/
def Schema.decode (schema : Schema Record) (value : Json) : Except Diagnostic Record := do
  schema.validateDefinition
  let object ← value.getObj?.mapError fun message => { message }
  for (name, _) in object.toList do
    unless schema.fields.any (·.name == name) do
      throw { message := s!"unknown field `{name}`" }
  let mut values : List (String × Json) := []
  for field in schema.fields do
    let _ : ToJson field.Value := field.codec.toToJson
    let value ← match object.get? field.name, field.defaultJson with
      | some value, _ => pure value
      | none, some value => pure value
      | none, none => throw { message := "missing required field", path := #[.field field.name] }
    let checked ← (field.decode value).mapError (Diagnostic.atField field.name)
    values := values ++ [(field.name, toJson checked)]
  let record ← schema.decodeValues (Json.mkObj values)
  schema.validateRecord record
  return record

def Schema.jsonSchema (schema : Schema Record) := json% {
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  title: $(schema.id.toString),
  type: "object",
  properties: $(Json.mkObj (schema.fields.toList.map fun field => (field.name, field.jsonSchema))),
  required: $((schema.fields.filter (·.handle.defaultValue.isNone)).map (·.name)),
  additionalProperties: false
}

def decodeField [InfoCodec Value] (object : Json) (name : String) : Except Diagnostic Value := do
  let value ← (object.getObjVal? name).mapError fun message =>
    { message, path := #[.field name] }
  (InfoCodec.decode value).mapError (Diagnostic.atField name)

/-- An override is constructed from a generated handle, without repeating field metadata. -/
structure FieldOverride (Record : Type) where
  field : FieldSpec Record

def FieldHandle.withCodec (handle : FieldHandle Record Value)
    (codec : InfoCodec Value) : FieldOverride Record :=
  ⟨⟨Value, codec, handle⟩⟩

def FieldHandle.withMerge [InfoCodec Value] (handle : FieldHandle Record Value)
    (merge : MergePolicy Value) : FieldOverride Record :=
  ⟨{ handle with merge }.toSpec⟩

def FieldHandle.withValidation [InfoCodec Value] (handle : FieldHandle Record Value)
    (validate : Value → Except String Unit) : FieldOverride Record :=
  ⟨{ handle with validate }.toSpec⟩

def FieldHandle.withAliases [InfoCodec Value] (handle : FieldHandle Record Value)
    (aliases : Array String) : FieldOverride Record :=
  ⟨{ handle with aliases }.toSpec⟩

structure SchemaOverrides (Record : Type) where
  fields : Array (FieldOverride Record) := #[]
  validateRecord : Record → Except Diagnostic Unit := fun _ => pure ()

def Schema.withOverrides (schema : Schema Record) (overrides : SchemaOverrides Record) :
    Except Diagnostic (Schema Record) := do
  let mut fields := schema.fields
  let mut assigned : Array String := #[]
  for override in overrides.fields do
    let field := override.field
    let some index := fields.findIdx? (·.name == field.name)
      | throw { message := s!"override for unknown field `{field.name}`" }
    if assigned.contains field.name then
      throw { message := s!"duplicate override for `{field.name}`; combine its typed rules in one handle" }
    assigned := assigned.push field.name
    fields := fields.set! index field
  let result := { schema with fields, validateRecord := fun value => do
    schema.validateRecord value
    overrides.validateRecord value }
  match result.validateDefinition with
  | .error error => throw error
  | .ok () => return result

/-- Static domain declarations use checked overrides; invalid declarations are programmer errors. -/
def Schema.withOverrides! (schema : Schema Record) (overrides : SchemaOverrides Record) : Schema Record :=
  match schema.withOverrides overrides with
  | .ok result => result
  | .error error =>
    let _ : Inhabited (Schema Record) := ⟨schema⟩
    panic! error.render

end ProofScript.Info
