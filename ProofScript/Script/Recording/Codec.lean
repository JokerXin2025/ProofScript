import ProofScript.Script.Recording.Capture
import ProofScript.Utils.Json
import ProofScript.Script.Recording.Shape

namespace ProofScript.Recording

open Lean Elab Tactic Meta

/-- Snapshot the selected goal's type as an ordinary optional expression value.
    No remaining goal is represented by `null`, independently of capture failure. -/
def goalSnapshot (goal : Option MVarId := none) : CaptureM RecordedData := do
  let goal ← match goal with
    | some goal => pure (some goal)
    | none => pure (← getUnsolvedGoals).head?
  match goal with
  | none => return .plain Json.null
  | some goal => CaptureM.withGoalContext goal do
    snapshotExpression (← goal.getType)

/-- Elaborate and fully export before restoring the temporary elaboration state. -/
def expression (raw : Syntax) : CaptureM RecordedData := CaptureM.withMainContext do
  snapshotExpression (← elabTerm raw none)

/-- Explicit name-only interpretation of an identifier, without term elaboration. -/
def identifierName (value : TSyntax `ident) : CaptureM RecordedData :=
  return .plain (Json.str value.getId.toString)

/-- Explicit source-syntax interpretation for categories with no semantic codec. -/
def syntaxText (value : Syntax) : CaptureM RecordedData :=
  return .plain (Json.str (value.reprint.getD (reprStr value)))

/-- Only expression-capable inputs may use this codec. -/
def expressionType (raw : Syntax) : CaptureM RecordedData := CaptureM.withMainContext do
  snapshotExpression (← inferType (← elabTerm raw none))

/-- Extensible parameter dispatch. Category instances compose into containers below. -/
class RecordParam (shape : ParamShape) where
  schema : ParamSchema
  capture : ParamInput shape → CaptureM RecordedData

instance (shape : ParamShape) [RecordParam shape] : RecordParam (.array shape) where
  schema := .array (RecordParam.schema shape)
  capture values := do
    return .array (← values.mapM RecordParam.capture)

instance (shape : ParamShape) [RecordParam shape] : RecordParam (.optional shape) where
  schema := .optional (RecordParam.schema shape)
  capture
    | none => pure (.plain Json.null)
    | some value => RecordParam.capture value

/-- Typeclass selection happens at the generated call site; a later plan can erase the
    heterogeneous inputs into closures without doing runtime category-string dispatch. -/
def captureParam (shape : ParamShape) [RecordParam shape]
    (value : ParamInput shape) : TacticM (Except String RecordedValue) := do
  try
    return .ok (← CaptureM.run (RecordParam.capture value))
  catch ex =>
    return .error (← ex.toMessageData.toString)

end ProofScript.Recording
