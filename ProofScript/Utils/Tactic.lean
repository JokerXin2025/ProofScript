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

end Lean.Elab.Tactic
