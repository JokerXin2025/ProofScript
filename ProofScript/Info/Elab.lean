import ProofScript.Utils.Sundry
import ProofScript.Info.State

open Lean Elab Command


namespace ProofScript.Info

private def spellingSuggestion (schema : InfoSchema Record) (key : String) : Option String :=
  let candidates := schema.fields.filter (!·.handle.isExtra) |>.map fun field =>
    (field.name, field.name.editDistance key)
  let closest := candidates.qsort (fun a b => a.2 < b.2) |>.toList.head?
  closest.filter (fun (name, distance) => distance ≤ (if min name.length key.length < 4 then 1 else 2))
    |>.map (·.1)

/-- Parses a full command before its caller may commit anything to the environment. -/
def parsePatch (schema : InfoSchema Record) (fields : Array InputField) : CommandElabM Patch := do
  if let .error error := schema.validateDefinition then throwError error.render
  let file ← getFileName
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
          let operation ← if isReset entry.value then pure UpdateOperation.reset
            else UpdateOperation.set <$> parseExtraValue entry.value
          result := result.push { key, operation, source := Foundation.SourceLocation.ofSyntax file entry.ref }
      else
        let key := FieldKey.builtin field.name
        if assigned.contains key then throwErrorAt input.ref m!"duplicate field `{field.name}`"
        assigned := assigned.push key
        let operation ← if isReset input.value then pure UpdateOperation.reset
          else UpdateOperation.set <$> field.parse input.value
        result := result.push { key, operation, source := Foundation.SourceLocation.ofSyntax file input.ref }
    else
      unless schema.extraField?.isSome do throwErrorAt input.ref m!"unknown field `{input.key}`"
      let key := FieldKey.extra input.key
      if assigned.contains key then throwErrorAt input.ref m!"duplicate extension key `{input.key}`"
      assigned := assigned.push key
      let operation ← if isReset input.value then pure UpdateOperation.reset
        else UpdateOperation.set <$> parseExtraValue input.value
      if let some suggestion := spellingSuggestion schema input.key then
        logWarningAt input.ref m!"unknown field `{input.key}` was stored in extra; did you mean `{suggestion}`? Use explicit extra to suppress this hint"
      result := result.push { key, operation, source := Foundation.SourceLocation.ofSyntax file input.ref }
  return result

/-- Installs one validated transaction after a domain has made its context decisions. -/
def commitInfoCommand [InfoSchema Record] (spec : InfoSpec Record) (target : Name ⊕ String) (patch : Patch)
    (ref : Syntax) (initialization : Option Patch := none)
    (bindings : Array ContextBinding := #[]) : CommandElabM Unit := do
  let source := Foundation.SourceLocation.ofSyntax (← getFileName) ref
  match commitInfo spec (← getEnv) target patch source initialization bindings with
  | .error error => throwErrorAt ref error.render
  | .ok env => setEnv env

/-- Parsing, initialization, and context selection succeed before any environment mutation. -/
def elaborateInfo [InfoSchema Record] (spec : InfoSpec Record) (target : Name ⊕ String) (fields : Array InputField)
    (ref : Syntax) (initialization : Option Patch := none)
    (bindings : Array ContextBinding := #[]) : CommandElabM Unit := do
  let patch ← parsePatch (inferInstance : InfoSchema Record) fields
  commitInfoCommand spec target patch ref initialization bindings

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

instance (priority := low) [InfoSchema Record] : InfoCodec Record :=
  schemaCodec inferInstance

end ProofScript.Info
