import ProofScript.Script.Recording.Engine
import ProofScript.Script.Core

open Lean Elab Tactic ProofScript ProofScript.Recording

example : True := by
  run_tac withExprJsonExport do
    let invalid : RecordingPlan := { parameters := #[
      { name := "x", timing := .both, capture := pure (.scalar Json.null) },
      { name := "x_before", timing := .once, capture := pure (.scalar Json.null) }
    ] }
    match invalid.validate with
    | .error _ => pure ()
    | .ok _ => throwError "overlapping output field names were accepted"
    let phase ← IO.mkRef false
    let fieldsRef ← IO.mkRef ([] : List (String × Json))
    let plan : RecordingPlan := { parameters := #[
      { name := "static", timing := .once, capture := do
          return .scalar (Json.str "once") },
      { name := "changing", timing := .both, capture := do
          return .scalar (Json.str (if ← phase.get then "after" else "before")) },
      { name := "missing", timing := .after, capture := do
          throwError "intentional failure" },
      { name := "expr", timing := .before, capture := do
          expression (← `(term| Nat.zero)).raw }
    ] }
    runPlan plan (phase.set true) fun captured =>
      fieldsRef.modify (· ++ captured)
    let fields ← fieldsRef.get
    unless ← phase.get do
      throwError "recorded action did not execute"
    unless (fields.lookup "static") == some (Json.str "once") &&
        (fields.lookup "changing_before") == some (Json.str "before") &&
        (fields.lookup "changing_after") == some (Json.str "after") &&
        (fields.lookup "missing") == some Json.null do
      throwError "capture phases or best-effort fallback were incorrect"
    let some expr := fields.lookup "expr" | throwError "expression field missing"
    let .ok id := expr.getObjValAs? String "$ref"
      | throwError "expression field has no reference"
    unless (← getExprJsonTable).getObjVal? id |>.isOk do
      throwError "isolated snapshot produced an unresolved reference"
  trivial

example : True := by
  run_tac withExprJsonExport do
    let plan : RecordingPlan := { parameters := #[
      { name := "strict", timing := .after, onFailure := .required,
        capture := throwError "expected failure" }
    ] }
    let saved ← getExprJsonTable
    let outcome ← try
      runPlan plan (do
        let _ ← Expr2JSON (mkConst ``Nat)
        pure ()) (fun _ => pure ())
      pure false
    catch _ => pure true
    unless outcome && (← getExprJsonTable) == saved do
      throwError "required failure did not roll back execution/export"
  trivial

example : True := by
  run_tac withExprJsonExport do
    let first ← Expr2JSON (mkConst ``Nat)
    let .ok initialFields := (← getExprJsonTable).getObj?
      | throwError "initial table malformed"
    let raw := (← `(term| Nat.zero)).raw
    let .success (.expression snapshot) ← tryCapture (expression raw)
      | throwError "snapshot capture failed"
    let rebased ← mergeExprJsonSnapshot snapshot.json snapshot.table
    let table ← getExprJsonTable
    let .ok firstId := first.getObjValAs? String "$ref"
      | throwError "initial reference missing"
    let .ok secondId := rebased.getObjValAs? String "$ref"
      | throwError "merged reference missing"
    if firstId == secondId || !(table.getObjVal? firstId).isOk ||
        !(table.getObjVal? secondId).isOk then
      throwError "snapshot merge collided with an existing reference"
    let .ok fields := snapshot.table.getObj?
      | throwError "snapshot table malformed"
    let .ok mergedFields := table.getObj?
      | throwError "merged table malformed"
    unless mergedFields.size == fields.size + initialFields.size do
      throwError "snapshot nodes were lost: {fields.size}, merged {mergedFields.size}"
  trivial
