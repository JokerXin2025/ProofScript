/-
    ProofScript.Core.Codec
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import ProofScript.Utils.Core

open Lean Elab Parser.Term


namespace ProofScript

syntax infoField := ident " := " term
syntax infoFields := "{" sepBy(infoField, ", ") "}"

/-- Lower priority preserves ordinary Lean structure terms. -/
syntax (name := infoObject) (priority := low) "{" sepBy(infoField, ", ") "}" : term

def fieldKeyName (ref : Syntax) : String :=
  ref.getId.eraseMacroScopes.toString

def readObject (stx : TSyntax `term) : CoreM (Array Syntax) := do
  if let `(term| {}) := stx then return #[]
  if let `(term| { $[$fields:infoField],* }) := stx then
    return fields.map (·.raw)
  let `(term| { $[$fields:structInstField],* }) := stx
    | throwErrorAt stx "expected a field object"
  return fields.map (·.raw)

def objectFieldRef (field : Syntax) : Syntax :=
  if let `(infoField| $key:ident := $_:term) := (⟨field⟩ : TSyntax ``infoField) then
    key.raw
  else if let `(structInstField| $key:ident := $_:term) := (⟨field⟩ : TSyntax ``structInstField) then
    key.raw
  else field

def objectFieldName (field : Syntax) : String := fieldKeyName (objectFieldRef field)

def objectFieldValue (field : Syntax) : CoreM (TSyntax `term) := do
  if let `(infoField| $_:ident := $value:term) := (⟨field⟩ : TSyntax ``infoField) then
    return value
  if let `(structInstField| $_:ident := $value:term) := (⟨field⟩ : TSyntax ``structInstField) then
    return value
  throwErrorAt field "expected field := value"

def infoFieldError (name error : String) : String := s!"{name}: {error}"

def infoIndexError (index : Nat) (error : String) : String := s!"[{index}]: {error}"

def infoTargetError [ToString Kind] (kind : Kind) (target error : String) : String :=
  s!"{kind} `{target}`: {error}"

/-- Parse a configuration term and record editor annotations for its contents.
`annotate` does not validate or evaluate the term: incomplete input is ignored,
while cancellation and resource failures propagate. Wire serialization is separate. -/
class InfoCodec (α : Type) where
  decode : TSyntax `term → CoreM α
  annotate : TSyntax `term → CoreM Unit := fun _ => pure ()

section
variable {α β : Type}

/-- Accept a string literal. -/
instance : InfoCodec String where
  decode
  | `(term| $text:str) => pure text.getString
  | stx => throwErrorAt stx "expected a string literal"

/-- Accept a Boolean literal. -/
instance : InfoCodec Bool where
  decode
  | `(term| true) => pure true
  | `(term| false) => pure false
  | stx => throwErrorAt stx "expected `true` or `false`"

/-- Accept a natural number literal. -/
instance : InfoCodec Nat where
  decode
  | `(term| $number:num) => pure number.getNat
  | stx => throwErrorAt stx "expected a natural number literal"

/-- Accept an integer literal. -/
instance : InfoCodec Int where
  decode
  | `(term| $number:num) => pure <| Int.ofNat number.getNat
  | `(term| - $number:num) => pure <| -Int.ofNat number.getNat
  | stx => throwErrorAt stx "expected an integer literal"

/-- Consume leading minus nodes iteratively; each step descends one syntax node. -/
private def stripJsonNumberSigns (stx : TSyntax `term) : TSyntax `term × Bool := Id.run do
  let mut current := stx
  let mut negative := false
  while let `(term| - $value:term) := current do
    current := value
    negative := !negative
  return (current, negative)

/-- Parse a JSON numeric literal, including signed and scientific notation. -/
def parseJsonNumberLiteral (stx : TSyntax `term) : CoreM JsonNumber := do
  let (value, negative) := stripJsonNumberSigns stx
  let number ← match value with
    | `(term| $number:num) => pure <| JsonNumber.fromNat number.getNat
    | _ =>
      if value.raw.isOfKind scientificLitKind then
        let text := value.raw[0].getAtomVal.replace "_" ""
        match Json.parse text with
        | .ok (.num number) => pure number
        | _ => throwErrorAt value "invalid numeric literal"
      else throwErrorAt value "expected a numeric literal"
  return if negative then -number else number

/-- Pending work for a depth-first JSON decode. The value stack holds completed children. -/
private inductive JsonDecodeTask where
| visit (stx : TSyntax `term)
| negate (stx : TSyntax `term)
| array (size : Nat)
| objectFields (fields : List Syntax) (names : List String)

/-- Parse JSON literals directly; no elaboration or evaluation of arbitrary Lean code. -/
def parseExtraValue (stx : TSyntax `term) : CoreM Json := do
  let mut tasks : List JsonDecodeTask := [.visit stx]
  let mut values : List Json := []
  while let task :: rest := tasks do
    tasks := rest
    match task with
    | .visit stx =>
        match stx with
        | `(term| $text:str) =>
            values := .str text.getString :: values
        | `(term| $_:num) =>
            values := .num (← parseJsonNumberLiteral stx) :: values
        | `(term| true) =>
            values := json% true :: values
        | `(term| false) =>
            values := json% false :: values
        | `(term| null) =>
            values := json% null :: values
        | `(term| none) =>
            values := json% null :: values
        | `(term| - $value:term) =>
            tasks := .visit value :: .negate stx :: tasks
        | `(term| [$[$items:term],*]) =>
            tasks := items.toList.map JsonDecodeTask.visit ++ .array items.size :: tasks
        | _ =>
          if stx.raw.isOfKind ``infoObject || stx.raw.isOfKind ``Parser.Term.structInst then
            tasks := .objectFields (← readObject stx).toList [] :: tasks
          else if stx.raw.isOfKind scientificLitKind then
            values := .num (← parseJsonNumberLiteral stx) :: values
          else
            throwErrorAt stx "expected a JSON literal (string, number, boolean, null, array or object)"
    | .negate stx =>
        match values with
        | .num number :: rest => values := .num (-number) :: rest
        | _ => throwErrorAt stx "expected a numeric literal after '-'"
    | .array size =>
        let (entries, rest) := values.splitAt size
        values := .arr entries.reverse.toArray :: rest
    | .objectFields fields names =>
        match fields with
        | field :: remaining =>
            let name := objectFieldName field
            if names.contains name then
              throwErrorAt (objectFieldRef field) m!"duplicate extension key `{name}`"
            tasks := .visit (← objectFieldValue field) :: .objectFields remaining (name :: names) :: tasks
        | [] =>
          let (entries, rest) := values.splitAt names.length
          values := Json.mkObj ((names.zip entries).reverse) :: rest
  match values with
  | [value] => return value
  | _ => throwErrorAt stx "expected a JSON literal (string, number, boolean, null, array or object)"

/-- Parse a JSON literal without evaluating Lean terms. -/
instance : InfoCodec Json where
  decode := parseExtraValue

/-- Resolved Lean declaration name used as an alias target. -/
structure DeclarationRef where
  name : Name
deriving BEq

instance : ToJson DeclarationRef := ⟨fun reference => toJson reference.name⟩

instance : InfoCodec DeclarationRef where
  decode
  | `(term| $id:ident) => DeclarationRef.mk <$> resolveDeclaration id
  | stx => throwErrorAt stx "expected a declaration identifier"
  annotate stx := do
    if let `(term| $id:ident) := stx then
      -- Retain editor references without validating or consuming metadata.
      -- Ignore ordinary resolution errors, but propagate runtime failures.
      unless (← getInfoState).enabled do return
      let messages := (← get).messages
      try
        discard <| resolveDeclaration id
      catch error =>
        if error.isRuntime then throw error
        match error with
        | .error .. => pure ()
        | .internal .. => throw error
      modify fun state => { state with messages }

/-- Parse `none` or `some value`, annotating the value inside `some`. -/
instance [InfoCodec α] : InfoCodec (Option α) where
  decode
  | `(term| none) => pure none
  | `(term| some $value:term) => some <$> InfoCodec.decode value
  | stx => throwErrorAt stx "expected none or some value"
  annotate
  | `(term| some $value:term) => InfoCodec.annotate (α := α) value
  | _ => pure ()

/-- Optional input that also accepts a bare value, unlike `Option α`. -/
structure OptionalInput (α : Type) where
  value : Option α := none
deriving BEq, Inhabited

instance [ToJson α] : ToJson (OptionalInput α) where
  toJson input := toJson input.value

instance [InfoCodec α] : InfoCodec (OptionalInput α) where
  decode stx := do
    let value ← match stx with
      | `(term| none) | `(term| some $_:term) => InfoCodec.decode (α := Option α) stx
      | _ => some <$> InfoCodec.decode (α := α) stx
    return ⟨value⟩
  annotate stx := do
    match stx with
    | `(term| none) | `(term| some $_:term) => InfoCodec.annotate (α := Option α) stx
    | _ => InfoCodec.annotate (α := α) stx

/-- Parse a list literal into an array, annotating each element. -/
instance [InfoCodec α] : InfoCodec (Array α) where
  decode
  | `(term| [$[$items:term],*]) => items.mapM InfoCodec.decode
  | stx => throwErrorAt stx "expected a list literal"
  annotate
  | `(term| [$[$items:term],*]) => items.forM (InfoCodec.annotate (α := α))
  | _ => pure ()

/-- Parse a list literal into a list using the array codec. -/
instance [InfoCodec α] : InfoCodec (List α) where
  decode stx := Array.toList <$> InfoCodec.decode stx
  annotate := InfoCodec.annotate (α := Array α)

/-- Parse an enumeration identifier from the accepted spelling/value pairs. -/
private def parseEnumCases (cases : Array (String × α)) (stx : TSyntax `term) : CoreM α := do
  let `(term| $id:ident) := stx
  | throwErrorAt stx "expected an enum identifier"
  let name := id.getId.eraseMacroScopes.toString
  let some entry := cases.find? (·.1 == name)
  | throwErrorAt stx m!"invalid value `{name}`; expected {String.intercalate ", " (cases.toList.map (·.1))}"
  return entry.2

end

open Command in
/-- Derive `InfoCodec` for a parameterless inductive with nullary constructors. -/
def parseEnum (declNames : Array Name) : CommandElabM Bool := do
  let env ← getEnv
  if declNames.any (fun name => (getStructureInfo? env name).isSome) then
    return false
  for declName in declNames do
    let .inductInfo info ← getConstInfo declName
      | throwError m!"InfoCodec can only be derived for inductive types: {declName}"
    unless info.numParams == 0 && info.numIndices == 0 do
      throwError m!"InfoCodec requires a parameterless enum: {declName}"
    let mut entries : Array (TSyntax `term) := #[]
    for ctor in info.ctors do
      let ctorInfo ← getConstInfoCtor ctor
      unless ctorInfo.numFields == 0 do
        throwError m!"InfoCodec requires nullary constructors: {ctor}"
      entries := entries.push <| ← `(( $(quote ctor.getString!), $(mkCIdent ctor) ))
    elabCommand <| ← `(command|
      instance : InfoCodec $(mkCIdent declName) where
        decode := parseEnumCases #[ $[$entries],* ]
    )
  return true

initialize
  Lean.Elab.registerDerivingHandler ``InfoCodec parseEnum

end ProofScript
