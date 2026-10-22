import ProofScript.Info.Syntax
import ProofScript.Info.JsonSchemas

open Lean Elab.Command Parser.Term


namespace ProofScript.Info
variable {α : Type}

/-- Configuration syntax and structured decoding, with standard JSON serialization.
Independent of tactic capture codecs. -/
class InfoCodec (α : Type) extends ToJson α where
  parse : TSyntax `term → CommandElabM α
  decode : Json → Except Diagnostic α
  jsonSchema : Json
  /-- Record editor semantics without parsing, validating, or evaluating the value.
  Malformed or incomplete input must be ignored; cancellation and resource failures propagate.
  -/
  annotate : TSyntax `term → CommandElabM Unit := fun _ => pure ()

def decodeJson [FromJson α] (value : Json) : Except Diagnostic α :=
  (fromJson? value).mapError fun message => { message }

instance : InfoCodec String where
  parse stx := do
    let `(term| $text:str) := stx
    | throwErrorAt stx "expected a string literal"
    return text.getString
  decode := decodeJson
  jsonSchema := InfoJson.stringSchema

instance : InfoCodec Bool where
  parse
  | `(term| true) => pure true
  | `(term| false) => pure false
  | stx => throwErrorAt stx "expected true or false"
  decode := decodeJson
  jsonSchema := InfoJson.boolSchema

instance : InfoCodec Nat where
  parse stx := do
    let `(term| $number:num) := stx
    | throwErrorAt stx "expected a natural number literal"
    return number.getNat
  decode := decodeJson
  jsonSchema := InfoJson.natSchema

instance : InfoCodec Int where
  parse
  | `(term| $number:num) => pure (Int.ofNat number.getNat)
  | `(term| - $number:num) => pure (-Int.ofNat number.getNat)
  | stx => throwErrorAt stx "expected an integer literal"
  decode := decodeJson
  jsonSchema := InfoJson.intSchema

instance : InfoCodec JsonNumber where
  parse stx := do
    let .num value ← parseExtraValue stx
    | throwErrorAt stx "expected a numeric literal"
    return value
  decode value := value.getNum?.mapError fun message => { message }
  jsonSchema := InfoJson.numberSchema

instance : InfoCodec ExtraValue where
  parse := parseExtraValue
  decode := pure
  jsonSchema := json% {}

instance : InfoCodec ExtraFields where
  parse stx := do
    match ExtraFields.fromJson (← parseExtraValue stx) with
    | .ok fields => return fields
    | .error message => throwErrorAt stx message
  decode value := ExtraFields.fromJson value |>.mapError fun message => { message }
  jsonSchema := json% { type: "object", additionalProperties: {} }

instance [InfoCodec α] : InfoCodec (Option α) where
  parse
  | `(term| none) => pure none
  | `(term| some $value:term) => some <$> InfoCodec.parse value
  | stx => throwErrorAt stx "expected none or some value"
  decode
  | .null => pure none
  | value => some <$> InfoCodec.decode value
  jsonSchema := InfoJson.nullableSchema (InfoCodec.jsonSchema α)
  annotate
  | `(term| some $value:term) => InfoCodec.annotate (α := α) value
  | _ => pure ()

/-- Fields with conditional defaults retain absence but accept the ordinary bare input syntax. -/
@[implicit_reducible] def optionalInputCodec [InfoCodec α] : InfoCodec (Option α) :=
  let ordinary : InfoCodec (Option α) := inferInstance
  { ordinary with
    parse := fun stx => do
      match stx with
      | `(term| none) | `(term| some $_:term) => ordinary.parse stx
      | _ => some <$> InfoCodec.parse stx
    annotate := fun stx => do
      match stx with
      | `(term| none) | `(term| some $_:term) => ordinary.annotate stx
      | _ => InfoCodec.annotate (α := α) stx }

instance [InfoCodec α] : InfoCodec (Array α) where
  parse stx := do
    let `(term| [$[$items:term],*]) := stx
    | throwErrorAt stx "expected a list literal"
    items.mapM InfoCodec.parse
  decode value := do
    let items ← value.getArr?.mapError fun message => { message }
    items.mapIdxM fun index item =>
      (InfoCodec.decode item).mapError (Diagnostic.atIndex index)
  jsonSchema := InfoJson.arraySchema (InfoCodec.jsonSchema α)
  annotate
  | `(term| [$[$items:term],*]) => items.forM (InfoCodec.annotate (α := α))
  | _ => pure ()

instance [InfoCodec α] : InfoCodec (List α) where
  parse stx := Array.toList <$> InfoCodec.parse stx
  decode value := Array.toList <$> InfoCodec.decode value
  jsonSchema := InfoCodec.jsonSchema (Array α)
  annotate := InfoCodec.annotate (α := Array α)

/-- Domain enumerations declare their syntax and wire representation together. -/
@[implicit_reducible] def enumCodec [BEq α] (cases : Array (String × α)) : InfoCodec α where
  parse stx := do
    let `(term| $id:ident) := stx
    | throwErrorAt stx "expected an enum identifier"
    let name := id.getId.eraseMacroScopes.toString
    let some entry := cases.find? (·.1 == name)
    | throwErrorAt stx m!"invalid value `{name}`; expected {String.intercalate ", " (cases.toList.map (·.1))}"
    return entry.2
  toJson value := toJson ((cases.find? (·.2 == value)).map (·.1) |>.getD "")
  decode value := do
    let name ← decodeJson value
    let some entry := cases.find? (·.1 == name)
    | throw { message := s!"invalid enum value `{name}`" }
    return entry.2
  jsonSchema := json% { type: "string", enum: $(cases.map (·.1)) }

/-- Newtypes retain their domain check in both syntax parsing and protocol decoding. -/
@[implicit_reducible] def checkedCodec [InfoCodec α] (wrap : α → Except String β) (unwrap : β → α) : InfoCodec β where
  parse stx := do
    match wrap (← InfoCodec.parse stx) with
    | .ok result => return result
    | .error message => throwErrorAt stx message
  toJson value := toJson (unwrap value)
  decode value := do
    let value ← InfoCodec.decode value
    (wrap value).mapError fun message => { message }
  jsonSchema := InfoCodec.jsonSchema α
  annotate := InfoCodec.annotate (α := α)

/-- Standard JSON consumers share the domain decoder; Info internals retain structured errors.
Keep this adapter after the primitive codecs so their `decodeJson` uses Lean's decoders. -/
instance (priority := low) [InfoCodec α] : FromJson α where
  fromJson? value := (InfoCodec.decode value).mapError Diagnostic.render

end ProofScript.Info
