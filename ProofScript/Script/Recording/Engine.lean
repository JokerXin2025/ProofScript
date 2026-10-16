import ProofScript.Script.Recording.Plan
import ProofScript.Core.References

namespace ProofScript.Recording

open Lean Elab Tactic

/-- Import snapshots only after successful isolated capture. -/
partial def commitValue : RecordedValue → TacticM Json
  | .scalar json => pure json
  | .expression snapshot => mergeExprJsonSnapshot snapshot.json snapshot.table
  | .array values => return Json.arr (← values.mapM commitValue)
  | .object fields => return Json.mkObj (← fields.mapM fun (name, value) => do
      return (name, ← commitValue value))
  | .optional none => pure (json% null)
  | .optional (some value) => commitValue value

/-- Roll back all Lean recording and execution state on failure, including record headers,
    expression exports, references, goals, and strategy bookkeeping. External IO is excluded. -/
def withRollback (action : TacticM α) : TacticM α := do
  let saved ← Tactic.saveState
  try
    action
  catch ex =>
    saved.restore
    throw ex

/-- Options for a direct capture; plan captures pass their declared policies. -/
structure CaptureOptions where
  goal : Option MVarId := none
  onFailure : FailurePolicy := .required
  collectReferences : Bool := true

/-- Focus a capture on an explicit goal, or the current goal when available. -/
def withCaptureGoal (goal : Option MVarId) (action : TacticM α) : TacticM α := do
  let goals ← getGoals
  match goal.or goals.head? with
  | none => action
  | some goal =>
    try
      setGoals (goal :: goals.erase goal)
      goal.withContext action
    finally
      setGoals goals

/-- Return a self-contained value, restoring temporary elaboration even on success. -/
def captureValue (field : String) (capture : TacticM RecordedValue)
    (failure : FailurePolicy := .required) : TacticM RecordedValue := do
  match ← tryCapture capture with
  | .success value => return value
  | .failed message =>
    if failure == .required then
      throwError "failed to record parameter `{field}`: {message}"
    return .scalar (json% null)

/-- Commit expression tables and enabled references as one recoverable operation. -/
def commitCapturedValue (value : RecordedValue) (collectReferences : Bool := true) : TacticM Json :=
  withRollback do
    if collectReferences && (← referencesEnabled) then
      for name in value.references do
        addTheoremRef name
    commitValue value

end ProofScript.Recording
