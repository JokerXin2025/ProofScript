/-
    ProofScript.Script.Model
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import Lean

namespace ProofScript

open Lean

/-- A theorem parameter is not a recorder field: its expressions are encoded
    directly into the proof owner's expression graph. -/
structure RecordedTheoremParameter where
  variableExpr : Expr
  typeExpr : Expr
  isInstance : Bool

structure RecordedTheoremStatement where
  parameters : Array RecordedTheoremParameter
  conditions : Array Expr
  conclusion : Expr

end ProofScript
