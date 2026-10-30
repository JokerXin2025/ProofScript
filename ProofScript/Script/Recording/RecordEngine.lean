import ProofScript.Script.Recording.Data
import ProofScript.Utils.Tactic

namespace ProofScript

open Lean Elab Tactic

/-! Return a self-contained value, restoring temporary elaboration even on success. -/
def recordValueFrom (field : String) (action : TacticM RecordedValue) : TacticM RecordedValue := do
  try
    withoutModifyingState' <| Term.withoutErrToSorry <| withoutRecover action
  catch ex =>
    let message ← ex.toMessageData.toString
    throwError "failed to record parameter `{field}`: {message}"

/-- Focus an explicitly selected goal for readers that call `withMainContext`.
    Used only inside the state isolation supplied by `recordValueFrom`. -/
private def recordInGoal (context : RecordContext) (action : TacticM RecordedValue) :
    TacticM RecordedValue := do
  match context with
  | none => action
  | some goal =>
    let goals ← getGoals
    if goals.head? != context then
      setGoals (goal :: goals.erase goal)
    goal.withContext action

/-- Convert a value with an optional selected goal, restoring temporary goal
    selection and elaboration state even when the conversion fails. -/
def recordValueFromContext [RecordValue α] (field : String) (value : α)
    (context : RecordContext := none) : TacticM RecordedValue :=
  recordValueFrom field (recordInGoal context (RecordValue.record value context))

end ProofScript
