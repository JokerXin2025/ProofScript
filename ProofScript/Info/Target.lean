import ProofScript.Utils.Json
import ProofScript.Info.JsonSchemas
import ProofScript.Info.Resolve
import ProofScript.Info.Elab

namespace ProofScript

open Lean Elab Command

/-- All declaration-based domains use Lean's namespace, alias and overload resolution. -/
def resolveDeclaration (id : TSyntax `ident) : CommandElabM Name := do
  addCompletionInfo <| .id id.raw id.getId (danglingDot := false) {} none
  let declaration ← Lean.resolveGlobalConstNoOverload id.raw
  unless (← getEnv).contains declaration do
    throwErrorAt id m!"unknown declaration `{id.getId}`"
  addConstInfo id.raw declaration
  return declaration

/-- Verification builds retain editor references without validating or consuming metadata.
Only ordinary resolution errors are optional; cancellation and resource failures must propagate.
-/
def addDeclarationReferenceInfo (id : TSyntax `ident) : CommandElabM Unit := do
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

/-- Schema keys denote the actual model projections, even when their values are skipped.
This reads syntax only: it does not run codecs, validation, or metadata transactions.
-/
def addInfoFieldInfos (schema : InfoSchema Record) (fields : TSyntax ``infoFields) : CommandElabM Unit := do
  unless (← getInfoState).enabled do return
  annotateInfoFields schema (← readFields fields)

/-- Declaration references preserve name components on the wire and resolve through Lean at input. -/
structure DeclarationRef where
  name : Name
  deriving Inhabited, Repr, BEq

open scoped InfoJson in
instance : InfoCodec DeclarationRef where
  parse stx := do
    let `(term| $id:ident) := stx | throwErrorAt stx "expected a declaration identifier"
    return ⟨← resolveDeclaration id⟩
  toJson reference := Lean.toJson reference.name
  decode value := (DeclarationRef.mk <$> fromJson? value).mapError fun message => { message }
  jsonSchema := InfoJson.qualifiedNameSchema
  annotate stx := do
    if let `(term| $id:ident) := stx then
      addDeclarationReferenceInfo id

/-- A configured record is required even when all its schema fields have defaults. -/
def resolveConfiguredInfo [InfoSchema Record] (spec : InfoSpec Record) (env : Environment) (query : Query) (target : Name) :
    Except Diagnostic (ResolvedInfo Record) := do
  let view ← resolvePartial spec env query target
  unless view.created do
    throw { message := s!"{spec.kind} metadata is not configured", kind := some spec.kind, target := some target.toString }
  consumeView spec view

/-- A literal key is one Name component, including any dots in the original text. -/
def updateLiteralInfo [InfoSchema Record] (spec : InfoSpec Record) (target : TSyntax `str)
    (fields : Array InputField) (ref : Syntax) : CommandElabM Unit := do
  if target.getString.isEmpty then throwErrorAt target s!"{spec.kind} key must not be empty"
  elaborateInfo spec (Name.mkSimple target.getString) fields ref

def updateDeclarationInfo [InfoSchema Record] (spec : InfoSpec Record) (target : TSyntax `ident)
    (fields : Array InputField) (ref : Syntax) : CommandElabM Unit := do
  elaborateInfo spec (← resolveDeclaration target) fields ref

end ProofScript
