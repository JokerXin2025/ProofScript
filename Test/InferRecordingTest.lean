import ProofScript

@theorem test_infer_export (P Q R : Prop) (hPQ : P → Q) (hQR : Q → R) : P → R := script
  intro hp
  infer
    P => Q := hPQ hp
    => R := hQR ?_

-- Each tactic proof sees the preceding conclusion, not an outer `this`.
set_option linter.unusedVariables false in
theorem test_infer_by (P Q R : Prop) (hp : P)
    (hPQ : P → Q) (hQR : Q → R) (this : False → False) : R :=
  infer
    P => Q := by
      apply hPQ
      exact hp
    => Q ∧ Q := by
      refine And.intro ?_ ?_
      · exact this
      · exact this
    => Q := And.left ?_
    => R := (by
      apply hQR
      exact this)

@theorem test_recorded_infer_by (P Q R : Prop) (hp : P)
    (hPQ : P → Q) (hQR : Q → R) : Q ∧ R := script
  infer
    P => Q := by exact hPQ hp
    => Q ∧ Q := by
      refine And.intro ?_ ?_
      · exact this
      · exact this
    => Q := And.left ?_
    => R := by exact hQR this
  split_and
  | left => trivial
  | right => trivial

set_option linter.unusedVariables false in
example (P Q R : Prop) (hp : P) (hPQ : P → Q) (hQR : Q → R) : True := by
  fail_if_success
    have : R := (infer
      P => Q := hPQ hp
      => R := hQR (hPQ hp))
  fail_if_success
    have : Q ∧ Q := (infer
      P => Q := hPQ hp
      => Q ∧ Q := And.intro ?_ ?_)
  fail_if_success
    have : True := (infer
      P => True := by trivial)
  fail_if_success
    have : R := (infer
      P => Q := hPQ hp
      => R := by exact hQR (show P from this))
  trivial

example (P Q R : Prop) (hp : P) (hPQ : P → Q) (hQR : Q → R)
    (this : Nat) : Nat := by
  have _hr : R := infer
    P => Q := hPQ hp
    => R := by exact hQR this
  -- The alias inside the inference proof does not replace the outer binding.
  exact this

@theorem test_recorded_infer_named (P Q R : Prop) (hp : P)
    (hPQ : P → Q) (hQR : Q → R) : Q ∧ R := script
  infer
    P ⇒ hQ : Q := by exact hPQ hp
    ⇒ hR : R := hQR ?_
    ⇒ Q ∧ R := by exact And.intro hQ this
    ⇒ R := And.right ?_
  split_and
  | left => exact hQ
  | right => exact hR

-- Captures happen before execution: the first proof is available, whereas later
-- proofs using the previous result are represented by the recorder's hole marker.
open Lean Elab Command ProofScript in
run_cmd do
  for (decl, expectedSize, closesGoal) in [
      (`test_infer_export, 2, true), (`test_recorded_infer_by, 4, false),
      (`test_recorded_infer_named, 4, false)] do
    let document ← ofExcept <| Json.parse
      (← IO.FS.readFile (proofOutputPath (← getEnv).mainModule decl))
    let expressions ← ofExcept (document.getObjVal? "expressions")
    let checkExpression (value : Json) : CommandElabM Unit := do
      let reference ← ofExcept (value.getObjValAs? String "$ref")
      let expression ← ofExcept (expressions.getObjVal? reference)
      unless (expression.getObjValAs? String "kind").isOk do
        throwError "infer exported an invalid expression reference {reference}"
    let steps ← ofExcept (document.getObjValAs? (Array Json) "proof")
    let some step := steps.find? fun step =>
        (step.getObjValAs? String "_ruleId").toOption ==
          some "ProofScript.Script.Basic.infer"
      | throwError "missing recorded infer for {decl}"
    checkExpression (← ofExcept (step.getObjVal? "goal_before"))
    checkExpression (← ofExcept (step.getObjVal? "init"))
    let after ← ofExcept (step.getObjVal? "goal_after")
    if closesGoal then
      unless after == Json.null do throwError "completed infer retained a goal"
    else
      checkExpression after
    let chain ← ofExcept (step.getObjValAs? (Array Json) "chain")
    unless chain.size == expectedSize do throwError "infer lost a chain step"
    for i in [:chain.size] do
      let entry := chain[i]!
      checkExpression (← ofExcept (entry.getObjVal? "rhs"))
      let proof ← ofExcept (entry.getObjVal? "proof")
      if i == 0 then
        checkExpression proof
      else
        unless proof == (json% { kind: "hole" }) do
          throwError "infer lost a proof hole requiring a preceding result"

@theorem test_recorded_infer_shallower_continuation (P Q R : Prop) (hp : P)
    (hPQ : P → Q) (hQR : Q → R) : Q ∧ R := script
  infer
      P ⇒ hQ : Q := hPQ hp
    ⇒ hR : R := hQR ?_
  split_and
  | left => exact hQ
  | right => exact hR
