import ProofScript

open ProofScript

project_info "Test.RecorderSelectionTest" { title := "Recorder selection" }

set_option linter.unusedVariables false

declare_syntax_cat unsupportedRecordingCategory
syntax ident : unsupportedRecordingCategory

script_macro unsupportedAuto "unsupported_auto_recording" loc:(unsupportedRecordingCategory)? =>
  `(tactic| trivial)

-- Unsupported automatic parameters do not prevent ordinary execution.
example : True := script
  unsupported_auto_recording

/--
warning: [script recorder] 'unsupported_auto_recording': 参数 'loc' 缺少 RecordParam 实例；请提供类别实例或定义 script_recorder；未导出数据
-/
#guard_msgs in
@theorem unsupportedRecorded : True := script
  unsupported_auto_recording

script_macro unsupportedSplit (strategy := true)
    "unsupported_split" loc:(unsupportedRecordingCategory)? => `(tactic| constructor)

/--
warning: [script recorder] 'unsupported_split': 参数 'loc' 缺少 RecordParam 实例；请提供类别实例或定义 script_recorder；未导出数据
---
warning: [script recorder] 'unsupported_split': 参数 'loc' 缺少 RecordParam 实例；请提供类别实例或定义 script_recorder；未导出数据
-/
#guard_msgs in
@theorem unsupportedStrategyRecorded : True ∧ (True ∧ True) := script
  unsupported_split
  | right =>
    unsupported_split
    · trivial
    · trivial
  | left => trivial

script_elab unsupportedClaim (strategy := true, continuation := 1)
    "unsupported_claim" h:ident loc:(unsupportedRecordingCategory)? => do
  Lean.Elab.Tactic.evalTactic (← `(tactic| script_claim $h:ident : True))

/--
warning: [script recorder] 'unsupported_claim': 参数 'loc' 缺少 RecordParam 实例；请提供类别实例或定义 script_recorder；未导出数据
-/
#guard_msgs in
@theorem unsupportedContinuationRecorded : True := script
  unsupported_claim saved
  | proof => trivial
  exact saved

-- Unsupported parser structure also falls back, even with a renderer that needs missing fields.
script_elab unsupportedCompound "unsupported_compound" value:(ident term) => pure ()
script_info unsupportedCompound { renderer := «calc» }

#guard_msgs (drop warning) in
@theorem unsupportedCompoundRecorded : True := script
  unsupported_compound label True
  trivial

-- Only missing recorder data is recoverable; execution errors must still reject the proof.
script_elab unsupportedFailure "unsupported_failure" value:(ident term) =>
  Lean.throwError "actual tactic failure"

/-- error: actual tactic failure -/
#guard_msgs (drop warning, error) in
@theorem unsupportedExecutionFailure : True := script
  unsupported_failure label True

-- A handwritten recorder overrides the unavailable automatic recorder.
script_recorder unsupportedAuto "unsupported_auto_recording" loc:(unsupportedRecordingCategory)? => recording_step do
  capture_params #[Recording.goalParam "goal_before"]
  execute_recorded
  capture_params #[Recording.goalParam "goal_after"]

@theorem handwrittenRecorded : True := script
  unsupported_auto_recording

open Lean Elab Command in
run_cmd do
  let owner := (← getEnv).mainModule
  let readProof := fun (decl : Name) => do
    let .ok document := Json.parse (← IO.FS.readFile (proofOutputPath owner decl))
      | throwError "invalid recorded proof"
    ofExcept (document.getObjValAs? (Array Json) "proof")
  let checkPlaceholder := fun (step : Json) => do
    unless (step.getObjValAs? String "_ruleId").toOption == some unrecordedRuleId.toString do
      throwError "missing reserved unrecorded rule ID"
    unless (step.getObjValAs? String "name").isOk do
      throwError "missing original script name"
    if (step.getObjVal? "goal_before").isOk || (step.getObjVal? "goal_after").isOk then
      throwError "unrecorded steps must not pretend to capture goal data"
  let ordinary ← readProof `unsupportedRecorded
  unless ordinary.size == 1 do throwError "ordinary placeholder was lost"
  checkPlaceholder ordinary[0]!
  let strategy ← readProof `unsupportedStrategyRecorded
  unless strategy.size == 1 do throwError "strategy branches escaped to the parent"
  checkPlaceholder strategy[0]!
  let branches ← ofExcept (strategy[0]!.getObjValAs? (Array Json) "branches")
  unless branches.size == 2 do throwError "missing strategy branches"
  let right ← ofExcept (branches[0]!.getObjValAs? (Array Json) "proof")
  unless right.size == 1 do throwError "nested branches escaped their strategy"
  checkPlaceholder right[0]!
  let nested ← ofExcept (right[0]!.getObjValAs? (Array Json) "branches")
  unless nested.size == 2 do throwError "missing anonymous branches"
  let continuation ← readProof `unsupportedContinuationRecorded
  unless continuation.size == 2 &&
      (continuation[1]!.getObjValAs? String "_ruleId").toOption == some "ProofScript.Script.Basic.exact" do
    throwError "continuation escaped its parent recording"
  checkPlaceholder continuation[0]!
  let compound ← readProof `unsupportedCompoundRecorded
  unless compound.size == 2 do throwError "steps after an unrecorded call were lost"
  checkPlaceholder compound[0]!
  let handwritten ← readProof `handwrittenRecorded
  unless handwritten.size == 1 &&
      (handwritten[0]!.getObjValAs? String "_ruleId").toOption == some (owner ++ `unsupportedAuto).toString do
    throwError "handwritten recorder did not restore the original rule ID"
  -- Snapshots must freeze the fallback contract captured before the handwritten override.
  let views ← match Info.freezeModuleArtifacts (← getEnv) owner with
    | .ok views => pure views
    | .error error => throwError error.render
  unless views.any (fun (_, snapshot) => snapshot.contracts.any (·.ruleId == unrecordedRuleId)) do
    throwError "placeholder contracts were not retained by the Info exporter"

/--
error: [script recorder] `Test.RecorderSelectionTest.unsupportedAuto` already has a handwritten recorder
-/
#guard_msgs in
script_recorder unsupportedAuto "unsupported_auto_recording" loc:(unsupportedRecordingCategory)? => recording_step do
  capture_params #[Recording.goalParam "goal_before"]
  execute_recorded
  capture_params #[Recording.goalParam "goal_after"]
