import Lean

open Lean
open Parser.Tactic (rcasesPatMed)


namespace ProofScript


open Lean Elab Tactic in
/-- Get the expression of current goal -/
def GetGoal : TacticM Expr := do
  let goal ← getMainGoal
  let goal_expr ← goal.getType
  return ← instantiateMVars goal_expr

partial def toRoman (n : Nat) :=
  if n >= 1000 then "M" ++ toRoman (n - 1000)
  else if n >= 900 then "CM" ++ toRoman (n - 900)
  else if n >= 500 then "D" ++ toRoman (n - 500)
  else if n >= 400 then "CD" ++ toRoman (n - 400)
  else if n >= 100 then "C" ++ toRoman (n - 100)
  else if n >= 90 then "XC" ++ toRoman (n - 90)
  else if n >= 50 then "L" ++ toRoman (n - 50)
  else if n >= 40 then "XL" ++ toRoman (n - 40)
  else if n >= 10 then "X" ++ toRoman (n - 10)
  else if n >= 9 then "IX" ++ toRoman (n - 9)
  else if n >= 5 then "V" ++ toRoman (n - 5)
  else if n >= 4 then "IV" ++ toRoman (n - 4)
  else if n >= 1 then "I" ++ toRoman (n - 1)
  else ""


end ProofScript


/-
# Copied From `Batteries`

Copyright (c) 2021 Mario Carneiro. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Mario Carneiro
-/

macro "by_contra_core" : tactic => `(tactic|
  first
  | guard_target = Not _
    change _ → False
  | refine @Decidable.byContradiction _ _ ?_
  | refine @Classical.byContradiction _ ?_
)

syntax (name := byContra) "by_contra" (ppSpace colGt rcasesPatMed)? (" : " term)? : tactic

macro_rules
| `(tactic| by_contra $[$pat?]? $[: $ty?]?) => do
  let pat ← pat?.getDM `(rcasesPatMed| $(mkIdent `this):ident)
  `(tactic| (by_contra_core; rintro ($pat:rcasesPatMed) $[: $ty?]?))
