import ProofScript.Foundation.Name
import ProofScript.Info.Resolve
import ProofScript.Info.Elab

namespace ProofScript.Info

open Lean Elab Command

/-- All declaration-based domains use Lean's namespace, alias and overload resolution. -/
def resolveDeclaration (id : TSyntax `ident) : CommandElabM Name := do
  let declaration ← Lean.resolveGlobalConstNoOverload id.raw
  unless (← getEnv).contains declaration do
    throwErrorAt id m!"unknown declaration `{id.getId}`"
  return declaration

/-- Declaration references preserve name components on the wire and resolve through Lean at input. -/
structure DeclarationRef where
  name : Name
  deriving Inhabited, Repr, BEq

open scoped Foundation in
instance : InfoCodec DeclarationRef where
  parse stx := do
    let `(term| $id:ident) := stx | throwErrorAt stx "expected a declaration identifier"
    return ⟨← resolveDeclaration id⟩
  toJson reference := Lean.toJson reference.name
  decode value := (DeclarationRef.mk <$> fromJson? value).mapError fun message => { message }
  jsonSchema := Foundation.qualifiedNameSchema

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

end ProofScript.Info
