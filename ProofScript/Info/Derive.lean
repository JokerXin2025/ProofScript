import ProofScript.Info.Elab

namespace ProofScript.Info

open Lean Elab Command Meta Parser.Term

/-- First version intentionally excludes parameters, inheritance and dependent fields/defaults. -/
private def deriveSchema (declName : Name) : CommandElabM Unit := do
  let env ← getEnv
  let info ← getConstInfoInduct declName
  unless isStructure env declName do
    throwError "InfoSchema can only be derived for an ordinary structure"
  unless info.numParams == 0 && info.numIndices == 0 && !info.isRec &&
      (getStructureParentInfo env declName).isEmpty do
    throwError "InfoSchema currently requires a non-recursive structure without parameters or parents"
  let constructor ← getConstInfoCtor info.ctors.head!
  liftTermElabM <| forallTelescopeReducing constructor.type fun values _ => do
    for value in values do
      if (← inferType value).hasFVar then
        throwError "InfoSchema does not support dependent field types"
  let fields := getStructureFields env declName
  let type := mkIdent declName
  let mut handles : Array (TSyntax `term) := #[]
  for field in fields do
    let name := field.getString!
    let projection := (getProjFnForField? env declName field).get!
    let (isExtra, valueType) ← liftTermElabM <|
      forallTelescopeReducing (← getConstInfo projection).type fun _ result => do
        return ((← whnf result).isConstOf ``ExtraFields, ← PrettyPrinter.delab result)
    if (name == "extra") != isExtra then
      throwError "the reserved field `extra` must have type ExtraFields, and ExtraFields must be named `extra`"
    let defaultValue ← match getDefaultFnForField? env declName field with
      | none => `(none)
      | some defaultFn =>
        let defaultInfo ← getConstInfo defaultFn
        if defaultInfo.type.isForall then
          throwError "InfoSchema does not support a default depending on earlier fields: `{field}`"
        let some value := defaultInfo.value?
          | throwError "InfoSchema requires a transparent default for `{field}`"
        -- Copy the independent value, not a reference to Lean's generated default helper.
        let defaultTerm ← liftTermElabM do PrettyPrinter.delab (← reduce value)
        `(some $defaultTerm)
    let handleName := declName ++ `infoFields ++ field
    let handle := mkIdent handleName
    let declarationId := mkIdent (`_root_ ++ handleName)
    let fieldId := mkIdent field
    let fieldLval ← `(structInstLVal| $fieldId:ident)
    let command ← `(command|
      def $declarationId : FieldHandle $type $valueType := {
        name := $(quote name),
        get := fun record => record.$fieldId,
        set := fun record value => { record with $fieldLval:structInstLVal := value },
        defaultValue := $defaultValue,
        isExtra := $(quote isExtra) })
    elabCommand command
    handles := handles.push (← `(($handle).toSpec))
  let fieldIds := fields.map mkIdent
  let fieldLvals ← fieldIds.mapM fun field => `(structInstLVal| $field:ident)
  let getters ← fields.mapM fun field => `(decodeField object $(quote field.getString!))
  let decoder ← `(fun object => do
    $[let $fieldIds:ident ← $getters:term]*
    return { $[$fieldLvals:structInstLVal := $fieldIds:ident],* })
  let command ← `(command|
    instance : InfoSchema $type where
      schema := {
        id := $(quote declName),
        fields := #[$[$handles:term],*],
        decodeValues := $decoder })
  elabCommand command

initialize registerDerivingHandler ``InfoSchema fun names => do
  if names.isEmpty || !(← names.allM fun name => return isStructure (← getEnv) name) then
    return false
  for name in names do deriveSchema name
  return true

end ProofScript.Info
