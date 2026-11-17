import ProofScript.Core.Codec

namespace ProofScript

open Lean Elab Command

/-- Validate the complete object before decoding any field values. -/
def validateObjectFields (stx : TSyntax `term) (fields : Array Syntax)
    (allowed required : Array String) : CoreM Unit := do
  let mut seen : Array String := #[]
  for field in fields do
    let name := objectFieldName field
    unless allowed.contains name do
      throwErrorAt (objectFieldRef field) m!"unknown field `{name}`"
    if seen.contains name then
      throwErrorAt (objectFieldRef field) m!"duplicate field `{name}`"
    seen := seen.push name
  for name in required do
    unless fields.any (objectFieldName · == name) do
      throwErrorAt stx (infoFieldError name "missing required field")

private def parseObjectField [InfoCodec α] (fields : Array Syntax) (name : String)
    (fallback : Option α) : CoreM α := do
  match fields.find? (objectFieldName · == name) with
  | some field =>
    let value ← objectFieldValue field
    try
      InfoCodec.decode value
    catch error =>
      if error.isRuntime then throw error
      match error with
      | .error ref message =>
        if ref == value.raw then
          throwErrorAt value (infoFieldError name (← message.toString))
        else throw error
      | .internal .. => throw error
  | none => match fallback with
    | some value => return value
    | none => throwError (infoFieldError name "missing required field")

/-- Syntax errors are handled by the field parser; cancellation and resource failures propagate. -/
def readObjectForAnnotations? (stx : TSyntax `term) : CoreM (Option (Array Syntax)) := do
  try
    return some (← readObject stx)
  catch error =>
    if error.isRuntime then throw error
    match error with
    | .error .. => return none
    | .internal .. => throw error

/-- Editor semantics are independent from successful object parsing and validation. -/
def annotateField (record : Name) (name : String) (ref : Syntax)
    (value : TSyntax `term) (annotate : TSyntax `term → CoreM Unit) : CoreM Unit := do
  unless (← getInfoState).enabled do return
  let env ← getEnv
  if ref.isIdent then addCompletionInfo <| .fieldId ref ref.getId {} record
  if let some projection := getProjFnForField? env record (.mkSimple name) then
    addConstInfo ref projection
  annotate value

def annotateObjectFields (record : Name)
    (annotate : String → TSyntax `term → CoreM Unit)
    (stx : TSyntax `term) : CoreM Unit := do
  unless (← getInfoState).enabled do return
  let some fields ← readObjectForAnnotations? stx | return
  for field in fields do
    let name := objectFieldName field
    annotateField record name (objectFieldRef field) (← objectFieldValue field) (annotate name)

open Meta Elab Term in
/-- Generate an object decoder using each field's InfoCodec and declared default. -/
elab "decodeObjectFields% " record:ident : term => do
  let name ← resolveGlobalConstNoOverload record
  let env ← getEnv
  let some info := getStructureInfo? env name
    | throwErrorAt record "expected a structure name"
  let ctorName := (← getConstInfoInduct name).ctors.head!
  let ctor ← getConstInfoCtor ctorName
  unless ctor.numParams == 0 && info.parentInfo.isEmpty do
    throwErrorAt record "object decoders currently require a structure without parameters or parents"
  let input ← mkFreshUserName `input
  let fields ← mkFreshUserName `fields
  let input := mkIdent input
  let fields := mkIdent fields
  let mut bindings : Array (TSyntax `ident × TSyntax `term) := #[]
  let mut values : Array (Name × TSyntax `ident) := #[]
  let mut required : Array (TSyntax `term) := #[]
  for field in info.fieldNames do
    let key := Syntax.mkStrLit field.toString
    let fallback ← match getEffectiveDefaultFnForField? env name field with
      | none =>
        required := required.push key
        `(term| none)
      | some defaultFn =>
        let defaultInfo ← getConstInfo defaultFn
        let args ← forallTelescope defaultInfo.type fun args _ => args.mapM fun arg => do
          let argName := (← arg.fvarId!.getDecl).userName
          let some (_, value) := values.find? (·.1 == argName)
            | throwErrorAt record m!"unsupported default dependency `{argName}` for field `{field}`"
          return (value : TSyntax `term)
        -- Default declarations are elaborator metadata. Embed their value rather
        -- than leaving a reference to them in executable decoder code.
        let fn ← exprToSyntax (← instantiateValueLevelParams defaultInfo
          (← mkFreshLevelMVarsFor defaultInfo))
        `(term| some ($fn $args*))
    let value := mkIdent (← mkFreshUserName field)
    bindings := bindings.push (value, ← `(term| parseObjectField $fields $key $fallback))
    values := values.push (field, value)
  let ctorId := mkIdent ctorName
  let args := values.map fun (_, value) => (value : TSyntax `term)
  let mut steps : Array (TSyntax ``Parser.Term.doSeqItem) := #[]
  for (value, parse) in bindings do
    steps := steps.push (← `(Lean.Parser.Term.doSeqItem| let $value ← ($parse)))
  let allowed := info.fieldNames.map fun field => Syntax.mkStrLit field.toString
  let generated ← `(term| fun $input => do
    let $fields ← readObject $input
    validateObjectFields $input $fields #[$allowed,*] #[$required,*]
    $steps:doSeqItem*
    return $ctorId $args*)
  elabTerm generated none

open Meta Elab Term in
/-- Annotate each present field using its projection's result type. -/
elab "annotateObjectFields% " record:ident : term => do
  let name ← resolveGlobalConstNoOverload record
  let env ← getEnv
  let some info := getStructureInfo? env name
    | throwErrorAt record "expected a structure name"
  let ctorName := (← getConstInfoInduct name).ctors.head!
  let ctor ← getConstInfoCtor ctorName
  unless ctor.numParams == 0 && info.parentInfo.isEmpty do
    throwErrorAt record "object annotations currently require a structure without parameters or parents"
  let fieldName := mkIdent (← mkFreshUserName `fieldName)
  let mut annotate ← `(term| fun _ => pure ())
  for field in info.fieldNames.reverse do
    let some proj := getProjFnForField? env name field
      | throwErrorAt record m!"no projection for field `{field}`"
    let type ← forallTelescope (← getConstInfo proj).type fun _ result => do
      if result.hasFVar then
        throwErrorAt record m!"dependent field type for `{field}` is not supported"
      exprToSyntax result
    let key := Syntax.mkStrLit field.toString
    annotate ← `(term| if $fieldName == $key then
      InfoCodec.annotate (α := $type) else $annotate)
  let generated ← `(term| annotateObjectFields $(quote name) (fun $fieldName => $annotate))
  elabTerm generated none

open Elab Command in
/-- Derive object codecs for parameterless, non-inherited structures. -/
def deriveObjectInfoCodec (names : Array Name) : CommandElabM Bool := do
  let env ← getEnv
  unless names.all (fun name => (getStructureInfo? env name).isSome) do
    return false
  for name in names do
    let some info := getStructureInfo? env name
      | unreachable!
    let ctorName := (← getConstInfoInduct name).ctors.head!
    let ctor ← getConstInfoCtor ctorName
    unless ctor.numParams == 0 && info.parentInfo.isEmpty do
      throwError m!"InfoCodec requires a structure without parameters or parents: {name}"
  for name in names do
    let id := mkCIdent name
    elabCommand <| ← `(command|
      instance : InfoCodec $id where
        decode := decodeObjectFields% $id
        annotate := annotateObjectFields% $id)
  return true

initialize
  registerDerivingHandler ``InfoCodec deriveObjectInfoCodec

end ProofScript
