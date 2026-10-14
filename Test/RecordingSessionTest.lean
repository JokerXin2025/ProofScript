import ProofScript

open Lean ProofScript Lean.Elab.Tactic

elab "check_recording_rollback" : tactic => do
  ensureBox "rollbackProbe"
  appendBoxItem "rollbackProbe" (Json.str "kept")
  let keptRef ← Expr2JSON (mkConst ``Nat)
  let saved ← Lean.Elab.Tactic.saveState
  appendBoxItem "rollbackProbe" (Json.str "discarded")
  let discardedRef ← Expr2JSON (mkConst ``Bool)
  saved.restore
  unless (← takeBox "rollbackProbe") == #[Json.str "kept"] do
    throwError "recording state survived tactic state restoration"
  let table ← getExprJsonTable
  let .ok keptId := keptRef.getObjValAs? String "$ref"
    | throwError "missing retained expression reference"
  let .ok discardedId := discardedRef.getObjValAs? String "$ref"
    | throwError "missing discarded expression reference"
  unless (table.getObjVal? keptId).isOk && !(table.getObjVal? discardedId).isOk do
    throwError "expression table survived tactic state restoration"

elab "check_calc_capture_scope" : tactic => do
  let previous := calcProofsExt.getState (← getEnv)
  let captured ← withCalcProofs do
    unless calcProofsExt.getState (← getEnv) == some #[] do
      throwError "calc capture did not start empty"
    modifyEnv (calcProofsExt.setState · (some #[(0, mkConst ``Nat, mkConst ``Nat)]))
    let saved ← Lean.Elab.Tactic.saveState
    modifyEnv (calcProofsExt.setState · (some #[]))
    saved.restore
    unless (calcProofsExt.getState (← getEnv)).map (·.size) == some 1 do
      throwError "calc capture survived tactic state restoration"
  unless captured.size == 1 && calcProofsExt.getState (← getEnv) == previous do
    throwError "calc capture failed to return its proofs or restore its parent"
  let nested ← withCalcProofs do
    let _ ← withCalcProofs do
      modifyEnv (calcProofsExt.setState · (some #[(1, mkConst ``Bool, mkConst ``Bool)]))
    unless calcProofsExt.getState (← getEnv) == some #[] do
      throwError "nested calc capture replaced its parent"
  unless nested.isEmpty && calcProofsExt.getState (← getEnv) == previous do
    throwError "nested calc capture escaped its scope"
  try
    let _ ← withCalcProofs do
      throwError "intentional calc capture failure"
  catch _ => pure ()
  unless calcProofsExt.getState (← getEnv) == previous do
    throwError "failed calc capture escaped its scope"

-- The recording state follows the elaborator environment on rollback, and a
-- nested session does not replace the caller's recording after it exits.
run_cmd do
  withRecordingSession do
    pushRecordingTag "outer"
    ensureBox "outer"
    let saved ← get
    appendBoxItem "outer" (Json.str "discarded")
    set saved
    unless (← takeBox "outer").isEmpty do
      throwError "recording state survived command state restoration"
    withRecordingSession do
      unless (← currentRecordingTag).isEmpty do
        throwError "nested recording inherited its parent's box tag"
      pushRecordingTag "inner"
    unless (← currentRecordingTag) == "outer" do
      throwError "nested recording did not restore its parent"
  if (recordingSessionExt.getState (← getEnv)).isSome then
    throwError "recording session escaped its command scope"
  withRecordingSession do
    unless (← currentRecordingTag).isEmpty do
      throwError "new recording inherited an earlier proof's state"
  try
    withRecordingSession do
      pushRecordingTag "failed"
      ensureBox "failed"
      appendBoxItem "failed" (Json.str "discarded")
      throwError "intentional recording failure"
  catch _ => pure ()
  if (recordingSessionExt.getState (← getEnv)).isSome then
    throwError "failed recording left an active session"
  withRecordingSession do
    unless (← currentRecordingTag).isEmpty || !(← takeBox "failed").isEmpty do
      throwError "failed recording leaked into the next session"
  withRecordingSession do
    let code := "recorded code"
    let expressions := Json.mkObj []
    let owner := `Test.RecordingSessionTest
    let missing ← try
      let _ ← recordedProofJson "root" code expressions owner
      pure false
    catch _ => pure true
    unless missing do
      throwError "missing proof root was silently exported"
    ensureBox "root"
    let empty ← try
      let _ ← recordedProofJson "root" code expressions owner
      pure false
    catch _ => pure true
    unless empty do
      throwError "empty proof root was silently exported"
    let entry := Json.mkObj [("_ruleId", Json.str "ProofScript.Script.Basic.trivial")]
    appendBoxItem "root" entry
    mergeBoxLast "root" (Json.mkObj [("value", Json.str "before")])
    mergeBoxLast "root" (Json.mkObj [("value", Json.str "after")])
    let merged := Json.mkObj [("_ruleId", Json.str "ProofScript.Script.Basic.trivial"),
      ("value", Json.str "after")]
    unless (← takeBox "root") == #[merged] do
      throwError "recording fields did not overwrite the last record"
    appendBoxItem "root" entry
    let proof ← recordedProofJson "root" code expressions owner
    unless (← recordedProofJson "root" code expressions owner) == proof do
      throwError "finishing a proof changed its recorded data"
    unless (proof.getObjVal? "module").toOption == some (Json.str owner.toString) &&
        (proof.getObjVal? "code").toOption == some (Json.str code) &&
        (proof.getObjVal? "expressions").toOption == some expressions &&
        (proof.getObjVal? "proof").toOption == some (Json.arr #[entry]) do
      throwError "finished proof lost its document fields"

-- Proof and computation use distinct exports. This also verifies that nested
-- exports restore the parent's table and that command rollback restores nodes.
run_cmd withExprJsonExport do
  let first ← Lean.Elab.Command.liftTermElabM <| Expr2JSON (mkConst ``Nat)
  let .ok firstId := first.getObjValAs? String "$ref"
    | throwError "missing parent expression reference"
  let saved ← get
  let discarded ← Lean.Elab.Command.liftTermElabM <| Expr2JSON (mkConst ``Bool)
  let .ok discardedId := discarded.getObjValAs? String "$ref"
    | throwError "missing discarded expression reference"
  set saved
  let parentTable ← getExprJsonTable
  unless (parentTable.getObjVal? firstId).isOk &&
      !(parentTable.getObjVal? discardedId).isOk do
    throwError "expression table survived command state restoration"
  withExprJsonExport do
    unless (← getExprJsonTable) == Json.mkObj [] do
      throwError "nested expression export inherited parent's nodes"
    let nested ← Lean.Elab.Command.liftTermElabM <| Expr2JSON (mkConst ``Bool)
    let .ok nestedId := nested.getObjValAs? String "$ref"
      | throwError "missing nested expression reference"
    unless (← getExprJsonTable).getObjVal? nestedId |>.isOk do
      throwError "nested expression reference is unresolved"
  unless (← getExprJsonTable) == parentTable do
    throwError "nested expression export did not restore parent's table"
run_cmd do
  withExprJsonExport do
    unless (← getExprJsonTable) == Json.mkObj [] do
      throwError "expression export leaked between commands"
  try
    withExprJsonExport do
      let _ ← Lean.Elab.Command.liftTermElabM <| Expr2JSON (mkConst ``Nat)
      throwError "intentional expression export failure"
  catch _ => pure ()
  withExprJsonExport do
    unless (← getExprJsonTable) == Json.mkObj [] do
      throwError "failed expression export leaked its nodes"
    let first ← Lean.Elab.Command.liftTermElabM <| Expr2JSON (mkConst ``Nat)
    let reused ← Lean.Elab.Command.liftTermElabM <| Expr2JSON (mkConst ``Nat)
    unless first == reused do
      throwError "expression export lost its cache within one scope"

@theorem recordingSessionFirst : True := script
  trivial

@theorem recordingSessionSecond : True := script
  trivial

@theorem recordingSessionTacticRollback : (1 : Nat) = 1 := script
  calc
    1 = 1 := by
      check_recording_rollback
      check_calc_capture_scope
      rfl
