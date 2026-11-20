import Test.SharedDeclInfo
import ProofScript

/-!
  Frontend automatic beta-reduction gallery. Build with
  `lake build +Test.PageBetaReduction:ps4html`, then switch the
  "Automatic beta reduction" display option on and off to compare the
  expressions. The equalities are kernel-checked; no proof recorder is needed.
-/

set_option pageBuild true

open ProofScript

namespace PageBetaReduction

-- A single redex, followed by an ordinary fvar application that must remain.
#page theorem identity (x : Nat) (f : Nat → Nat) :
    (fun y : Nat => y) x = x ∧ f x = f x := by
  simp

-- Flattened applications consume one argument per lambda; a nested redex in
-- the argument also needs reducing before the outer substitution.
#page theorem multiple_arguments (x y : Nat) :
    (fun a b : Nat => a + b) x y = x + y ∧
      (fun a : Nat => a + 1) ((fun b : Nat => b) x) = x + 1 := by
  simp

-- Substitute by binder identity, not by the printed name: the inner binder
-- shadows the outer one, while the argument remains a free variable.
#page theorem shadowed_binder (x : Nat) :
    ((fun a : Nat => (fun a : Nat => a) a) x) = x := by
  simp

-- A partially applied lambda remains visible after the first beta step.
#page theorem partial_application (x y : Nat) :
    ((fun a b : Nat => a + b) x) y = x + y := by
  simp

end PageBetaReduction
