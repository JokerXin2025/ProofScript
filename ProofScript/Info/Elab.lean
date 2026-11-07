import ProofScript.Utils.Sundry
import ProofScript.Info.State

open Lean Elab Command


namespace ProofScript

/-- Read only the object syntax needed by editor annotations. Syntax errors here are
reported by the subsequent field parser; cancellation and resource failures propagate.
-/
def readInfoObject? (stx : TSyntax `term) : CommandElabM (Option (Array InputField)) := do
  try
    return some (← readObject stx)
  catch error =>
    if error.isRuntime then throw error
    match error with
    | .error .. => return none
    | .internal .. => throw error

/-- Model fields and their nested codecs contribute editor semantics independently of decoding.
Unknown fields and literal extension values do not acquire Lean declaration identities.
-/
def annotateInfoFields (schema : InfoSchema Record) (fields : Array InputField) : CommandElabM Unit := do
  unless (← getInfoState).enabled do return
  let env ← getEnv
  for input in fields do
    let key := if input.ref.isOfKind ``infoKey then input.ref[0] else input.ref
    if key.isIdent then
      addCompletionInfo <| .fieldId key key.getId {} schema.id
    if let some field := schema.findField? input.key then
      if let some projection := getProjFnForField? env schema.id (.mkSimple field.name) then
        addConstInfo key projection
      field.codec.annotate input.value

def annotateInfoObject (schema : InfoSchema Record) (stx : TSyntax `term) : CommandElabM Unit := do
  unless (← getInfoState).enabled do return
  if let some fields ← readInfoObject? stx then
    annotateInfoFields schema fields

private def spellingSuggestion (schema : InfoSchema Record) (key : String) : Option String :=
  let candidates := schema.fields.filter (!·.handle.isExtra) |>.map fun field =>
    (field.name, field.name.editDistance key)
  let closest := candidates.qsort (fun a b => a.2 < b.2) |>.toList.head?
  closest.filter (fun (name, distance) => distance ≤ (if min name.length key.length < 4 then 1 else 2))
    |>.map (·.1)

/-- Parses a full command before its caller may commit anything to the environment. -/
def parsePatch (schema : InfoSchema Record) (fields : Array InputField) : CommandElabM Patch := do
  if let .error error := schema.validateDefinition then throwError error.render
  let mut assigned : Array FieldKey := #[]
  let mut result : Patch := #[]
  for input in fields do
    if let some field := schema.findField? input.key then
      if field.handle.isExtra then
        let containerKey := FieldKey.builtin field.name
        if assigned.contains containerKey then throwErrorAt input.ref m!"duplicate field `{field.name}`"
        assigned := assigned.push containerKey
        let entries ← readObject input.value
        for entry in entries do
          let key := FieldKey.extra entry.key
          if assigned.contains key then throwErrorAt entry.ref m!"duplicate extension key `{entry.key}`"
          assigned := assigned.push key
          let value ← parseExtraValue entry.value
          result := result.push { key, value }
      else
        let key := FieldKey.builtin field.name
        if assigned.contains key then throwErrorAt input.ref m!"duplicate field `{field.name}`"
        assigned := assigned.push key
        let value ← field.parse input.value
        result := result.push { key, value }
    else
      unless schema.extraField?.isSome do throwErrorAt input.ref m!"unknown field `{input.key}`"
      let key := FieldKey.extra input.key
      if assigned.contains key then throwErrorAt input.ref m!"duplicate extension key `{input.key}`"
      assigned := assigned.push key
      let value ← parseExtraValue input.value
      if let some suggestion := spellingSuggestion schema input.key then
        logWarningAt input.ref m!"unknown field `{input.key}` was stored in extra; did you mean `{suggestion}`? Use explicit extra to suppress this hint"
      result := result.push { key, value }
  return result

/-- Installs one validated transaction after a domain has made its context decisions. -/
def commitInfoCommand [InfoSchema Record] (spec : InfoSpec Record) (target : Name ⊕ String) (patch : Patch)
    (ref : Syntax)
    (bindings : Array ContextBinding := #[]) : CommandElabM Unit := do
  match commitInfo spec (← getEnv) target patch bindings with
  | .error error => throwErrorAt ref error.render
  | .ok env => setEnv env

/-- Record a single whole-target reset. -/
def resetInfo [InfoSchema Record] (spec : InfoSpec Record) (target : Name ⊕ String)
    (ref : Syntax) : CommandElabM Unit := do
  match commitInfo spec (← getEnv) target #[] #[] true with
  | .error error => throwErrorAt ref error.render
  | .ok env => setEnv env

/-- Parsing and context selection succeed before any environment mutation. -/
def elaborateInfo [InfoSchema Record] (spec : InfoSpec Record) (target : Name ⊕ String) (fields : Array InputField)
    (ref : Syntax)
    (bindings : Array ContextBinding := #[]) : CommandElabM Unit := do
  let patch ← parsePatch (inferInstance : InfoSchema Record) fields
  commitInfoCommand spec target patch ref bindings

/-- Nested records use the same field parser, but require a complete typed value. -/
@[implicit_reducible] def schemaCodec (schema : InfoSchema Record) : InfoCodec Record where
  parse stx := do
    let patch ← parsePatch schema (← readObject stx)
    match applyPatch schema (json% {}) patch >>= schema.decode with
    | .ok value => return value
    | .error error => throwErrorAt stx error.render
  toJson := schema.encode
  decode := schema.decode
  jsonSchema := schema.jsonSchema
  annotate := annotateInfoObject schema

instance (priority := low) [InfoSchema Record] : InfoCodec Record :=
  schemaCodec inferInstance

end ProofScript
