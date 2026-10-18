import ProofScript

set_option linter.defProp false

-- 测试：不带 @theorem 的 calc
theorem test_calc_no_export (a b c : Nat) (hab : a = b) (hbc : b = c) : a = c := script
  calc
    a = b := hab
    _ = c := hbc

-- 测试：@theorem + calc 录制
@theorem test_calc_with_export (a b c d : Nat)
    (hab : a = b) (hbc : b = c) (hcd : c = d) : a = d := script
  calc
    a = b := hab
    _ = c := hbc
    _ = d := hcd

-- 测试：calc 中使用 ?_
@theorem test_calc_with_hole (a b c : Nat) (hab : a = b) (hbc : b = c) : a = c := script
  calc
    a = b := hab
    _ = c := ?_
  assumption

-- The recorder executes instrumented calc syntax, then captures its elaborated
-- relations and proofs while the invocation's proof collection is still open.
open Lean Elab Command ProofScript in
run_cmd do
  for (decl, expectedSize, hasHole) in [
      (`test_calc_with_export, 3, false), (`test_calc_with_hole, 2, true)] do
    let document ← ofExcept <| Json.parse
      (← IO.FS.readFile (proofOutputPath (← getEnv).mainModule decl))
    let expressions ← ofExcept (document.getObjVal? "expressions")
    let checkExpression (value : Json) : CommandElabM Unit := do
      let reference ← ofExcept (value.getObjValAs? String "$ref")
      let expression ← ofExcept (expressions.getObjVal? reference)
      unless (expression.getObjValAs? String "kind").isOk do
        throwError "calc exported an invalid expression reference {reference}"
    let steps ← ofExcept (document.getObjValAs? (Array Json) "proof")
    let some step := steps.find? fun step =>
        (step.getObjValAs? String "_ruleId").toOption ==
          some "ProofScript.Script.Basic.renderCalc"
      | throwError "missing recorded calc for {decl}"
    checkExpression (← ofExcept (step.getObjVal? "goal_before"))
    checkExpression (← ofExcept (step.getObjVal? "init"))
    let after ← ofExcept (step.getObjVal? "goal_after")
    if hasHole then
      checkExpression after
    else
      unless after == Json.null do throwError "completed calc retained a goal"
    let chain ← ofExcept (step.getObjValAs? (Array Json) "chain")
    unless chain.size == expectedSize do throwError "calc lost an elaborated chain step"
    for i in [:chain.size] do
      let entry := chain[i]!
      checkExpression (← ofExcept (entry.getObjVal? "relation"))
      checkExpression (← ofExcept (entry.getObjVal? "rhs"))
      let proof ← ofExcept (entry.getObjVal? "proof")
      if hasHole && i + 1 == chain.size then
        unless proof == (json% { kind: "hole" }) do
          throwError "calc lost its synthetic proof hole"
      else
        checkExpression proof
