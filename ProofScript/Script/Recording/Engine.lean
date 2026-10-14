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
  | .optional none => pure Json.null
  | .optional (some value) => commitValue value

def captureFields (plan : RecordingPlan) (before : Bool)
    (contextGoal : ContextSelector → TacticM (Option Lean.MVarId) := fun role => do
      if role == .main then return (← getGoals).head?
      return none) : TacticM (List (String × Json)) := do
  if let .error message := plan.validate then
    throwError "{message}"
  let mut fields := []
  for parameter in plan.parameters do
    let selected := match parameter.timing with
      | .once | .before => before
      | .after => !before
      | .both => true
    if selected then
      let key := if parameter.timing == .both then
        parameter.name ++ (if before then "_before" else "_after")
        else parameter.name
      let result ← tryCapture do
        let goal? ← contextGoal parameter.context
        if goal?.isNone && parameter.context != .main then
          throwError "recording context {repr parameter.context} has no goal"
        if let some goal := goal? then
          let goals ← getGoals
          try
            setGoals (goal :: goals.erase goal)
            parameter.capture
          finally
            setGoals goals
        else
          parameter.capture
      let value ← match result with
        | .success value => do
          if parameter.collectReferences && (← referencesEnabled) then
            for name in value.references do
              addTheoremRef name
          commitValue value
        | .failed message =>
          if parameter.onFailure == .required then
            throwError "failed to record parameter `{parameter.name}`: {message}"
          pure Json.null
      fields := fields ++ [(key, value)]
  return fields

/-- Roll back all Lean recording and execution state on failure, including record headers,
    expression exports, references, goals, and strategy bookkeeping. External IO is excluded. -/
def withRollback (action : TacticM α) : TacticM α := do
  let saved ← Tactic.saveState
  try
    action
  catch ex =>
    saved.restore
    throw ex

/-- Execute a normal step between the two capture phases. The consumer controls where
    fields are committed (e.g. JsonBox); strategy steps can call captureFields around
    their own branch-resolution logic. -/
def runPlan (plan : RecordingPlan) (execute : TacticM Unit)
    (commit : List (String × Json) → TacticM Unit) : TacticM Unit := withRollback do
  commit (← captureFields plan true)
  execute
  commit (← captureFields plan false)

end ProofScript.Recording
