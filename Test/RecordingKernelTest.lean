import ProofScript.Script.Recording.Builtins

open Lean Elab Tactic Meta ProofScript.Recording

/- A category can be added outside the recording kernel, and containers inherit its codec. -/
instance : RecordCategory `kernelLabel where
  schema := .name
  capture value :=
    let raw := if value.raw.isIdent then value.raw else value.raw[0]
    pure (.scalar (Json.str raw.getId.eraseMacroScopes.toString))

example : True := by
  run_tac do
    let a : TSyntax `kernelLabel := ⟨mkIdent `alpha⟩
    let b : TSyntax `kernelLabel := ⟨mkIdent `beta⟩
    let shape := ParamShape.array (.category `kernelLabel)
    unless RecordParam.schema (shape := shape) == .array .name do
      throwError "derived array schema is incorrect"
    let .success empty ← captureParam shape (#[] : ParamInput shape)
      | throwError "empty array capture failed"
    unless empty.toJson == Json.arr #[] do
      throwError "empty array changed shape"
    let .success single ← captureParam shape #[a]
      | throwError "single array capture failed"
    unless single.toJson == Json.arr #[Json.str "alpha"] do
      throwError "single element array changed shape"
    let .success many ← captureParam shape #[a, b]
      | throwError "multiple array capture failed"
    unless many.toJson == Json.arr #[Json.str "alpha", Json.str "beta"] do
      throwError "multiple elements were not preserved"
    let optional := ParamShape.optional (.category `kernelLabel)
    let .success missing ← captureParam optional (none : ParamInput optional)
      | throwError "missing optional capture failed"
    unless missing.toJson == Json.null do
      throwError "missing optional should serialize as null"
    let .success present ← captureParam optional (some a)
      | throwError "present optional capture failed"
    unless present.toJson == Json.str "alpha" do
      throwError "present optional lost its value"
    let .failed _ ← tryCapture (throwError "capture failure")
      | throwError "capture failure was mistaken for an absent optional"
    let noGoals ← getGoals
    setGoals []
    let stringArg : TSyntax `str := ⟨Syntax.mkStrLit "label"⟩
    let .success stringValue ← captureParam (.category `str) stringArg
      | throwError "literal capture incorrectly requires a goal"
    unless stringValue.toJson == Json.str "label" do
      throwError "string literal was not captured"
    setGoals noGoals
  trivial

example (h : True) : True := by
  run_tac do
    let raw := mkIdent `h
    let captured ← captureParam (.category `term) ⟨raw⟩
    let .success (.expression snapshot) := captured
      | match captured with
        | .failed message => throwError "expression capture failed: {message}"
        | _ => throwError "expression capture returned wrong shape"
    if snapshot.references.contains `h then
      throwError "local identifier was recorded as a theorem reference"
    unless snapshot.json != Json.null do
      throwError "expression export is empty"
    unless snapshot.table != Json.mkObj [] do
      throwError "expression export lost its reference table"
    let .success (.expression typeSnapshot) ← tryCapture (expressionType raw)
      | throwError "type-of-expression codec failed"
    unless typeSnapshot.json != Json.null do
      throwError "type-of-expression export is empty"
    let goal ← getMainGoal
    let ty ← goal.getType
    let mvar ← mkFreshExprMVar ty
    let .success _ ← tryCapture do
      mvar.mvarId!.assign (mkConst ``True.intro)
      return .scalar Json.null
      | throwError "isolated assignment failed"
    if ← mvar.mvarId!.isAssigned then
      throwError "capture leaked a metavariable assignment"
    let .failed _ ← tryCapture do
      mvar.mvarId!.assign (mkConst ``True.intro)
      throwError "expected failure"
      | throwError "failed capture was not reported"
    if ← mvar.mvarId!.isAssigned then
      throwError "failed capture leaked a metavariable assignment"
  exact h
