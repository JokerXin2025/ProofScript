import ProofScript.Script.Recording.Plan

namespace ProofScript.Recording

open Lean Elab Tactic

/-- Options for a direct capture; parameter captures pass their declared policies. -/
structure CaptureOptions where
  goal : Option MVarId := none
  onFailure : FailurePolicy := .required
  collectReferences : Bool := true

/-- Focus a capture on an explicit goal, or the current goal when available. -/
def withCaptureGoal (goal : Option MVarId) (action : CaptureM α) : CaptureM α := do
  let goals ← getGoals
  match goal.or goals.head? with
  | none => action
  | some goal =>
    try
      setGoals (goal :: goals.erase goal)
      CaptureM.withGoalContext goal action
    finally
      setGoals goals

/-- Return a self-contained value, restoring temporary elaboration even on success. -/
def captureValue (field : String) (capture : CaptureM RecordedData)
    (failure : FailurePolicy := .required) : TacticM RecordedValue := do
  try
    CaptureM.run capture
  catch ex =>
    let message ← ex.toMessageData.toString
    if failure == .required then
      throwError "failed to record parameter `{field}`: {message}"
    return { data := .plain Json.null }

end ProofScript.Recording
