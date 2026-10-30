/-
    ProofScript.Utils.Tactic
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import Lean


namespace Lean.Elab.Tactic
variable {α : Type}

/-- Get the expression of first goal. -/
def getMainGoalExpr : TacticM Expr := do
  let goal ← getMainGoal
  return ← instantiateMVars <|← goal.getType

/-- Like `getMainGoalExpr`, but return its _weak head normal form_. -/
def getMainGoalExpr' : TacticM Expr := do
  let goal ← getMainGoal
  return ← Meta.whnf <|← instantiateMVars <|← goal.getType

/-- Keep changes on success; restore saved tactic state and rethrow on exception.
IO effects cannot be rolled back by this function. -/
def withRollback (action : TacticM α) : TacticM α := do
  let saved ← Tactic.saveState
  try
    action
  catch ex =>
    saved.restore
    throw ex

/-- Run an action without retaining tactic, elaboration, or InfoTree changes.
Unlike `withoutModifyingState`, this also restores the elaboration info tree when
the action succeeds. -/
def withoutModifyingState' (action : TacticM α) : TacticM α := do
  let saved ← Tactic.saveState
  try
    action
  finally
    saved.restore (restoreInfo := true)

/-- Resolve a goal label by exact-match first and suffix-match second. If several
goals match, the first goal in the list is selected. -/
def resolveGoal? (goals : List MVarId) (tag : Name) : TacticM (Option MVarId) := do
  let tag := tag.eraseMacroScopes
  let tagged ← goals.mapM fun goal =>
    return (goal, (← goal.getTag).eraseMacroScopes)
  let matched := tagged.filter (·.2 == tag)
  match matched.map (·.1) with
  | goal :: _ => return some goal
  | [] =>
      let suffix := tagged.filter fun (_, goalTag) =>
        tag.components.isSuffixOf goalTag.components
      match suffix.map (·.1) with
      | goal :: _ => return some goal
      | [] => return none

/-- Like `resolveGoal?`, but fails when no visible goal matches it. -/
def resolveGoal! (goals : List MVarId) (label : Name) : TacticM MVarId := do
  let some goal ← resolveGoal? goals label
  | throwError "Label `{label}` has no matching goal"
  return goal

end Lean.Elab.Tactic
