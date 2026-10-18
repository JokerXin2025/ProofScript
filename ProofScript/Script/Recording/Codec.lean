import ProofScript.Script.Recording.Value

namespace ProofScript.Recording

open Lean Elab Tactic Meta

/-- Capture in the current tactic context without committing elaboration, environment,
    messages, goals, or metavariable assignments. The returned value must be self-contained. -/
def isolatedCapture (action : TacticM RecordedValue) : TacticM RecordedValue := do
  let saved ← Tactic.saveState
  try
    Term.withoutErrToSorry <| withoutRecover action
  finally
    saved.restore

/-- Capture errors are reported separately from an absent optional argument. -/
def tryCapture (action : TacticM RecordedValue) : TacticM (Except String RecordedValue) := do
  try
    return .ok (← isolatedCapture action)
  catch ex =>
    return .error (← ex.toMessageData.toString)

/-- Snapshot an already elaborated expression while its metavariables and local context exist. -/
def snapshotExpression (expr : Expr) : TacticM RecordedValue := do
  withExprJsonExport do
    let expr ← instantiateMVars expr
    let json ← Expr2JSON expr
    let table ← getExprJsonTable
    return .expression { json, table, references := Expr.getUsedConstants expr }

/-- Snapshot the selected goal's type as an ordinary optional expression value.
    No remaining goal is represented by `null`, independently of capture failure. -/
def goalSnapshot (goal : Option MVarId := none) : TacticM RecordedValue := do
  let goal ← match goal with
    | some goal => pure (some goal)
    | none => pure (← getUnsolvedGoals).head?
  match goal with
  | none => return .optional none
  | some goal => goal.withContext do
    return .optional (some (← snapshotExpression (← goal.getType)))

/-- Elaborate and fully export before restoring the temporary elaboration state. -/
def expression (raw : Syntax) : TacticM RecordedValue := withMainContext do
  snapshotExpression (← elabTerm raw none)

/-- Explicit name-only interpretation of an identifier, without term elaboration. -/
def identifierName (value : TSyntax `ident) : TacticM RecordedValue :=
  return .scalar (Json.str value.getId.toString)

/-- Explicit source-syntax interpretation for categories with no semantic codec. -/
def syntaxText (value : Syntax) : TacticM RecordedValue :=
  return .scalar (Json.str (value.reprint.getD (reprStr value)))

/-- Only expression-capable inputs may use this codec. -/
def expressionType (raw : Syntax) : TacticM RecordedValue := withMainContext do
  snapshotExpression (← inferType (← elabTerm raw none))

/-- Extensible parameter dispatch. Category instances compose into containers below. -/
class RecordParam (shape : ParamShape) where
  schema : ParamSchema
  capture : ParamInput shape → TacticM RecordedValue

instance (shape : ParamShape) [RecordParam shape] : RecordParam (.array shape) where
  schema := .array (RecordParam.schema shape)
  capture values := do
    return .array (← values.mapM RecordParam.capture)

instance (shape : ParamShape) [RecordParam shape] : RecordParam (.optional shape) where
  schema := .optional (RecordParam.schema shape)
  capture
    | none => pure (.optional none)
    | some value => return .optional (some (← RecordParam.capture value))

/-- Typeclass selection happens at the generated call site; a later plan can erase the
    heterogeneous inputs into closures without doing runtime category-string dispatch. -/
def captureParam (shape : ParamShape) [RecordParam shape]
    (value : ParamInput shape) : TacticM (Except String RecordedValue) :=
  tryCapture (RecordParam.capture value)

end ProofScript.Recording
