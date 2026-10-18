import ProofScript

open Lean Meta Elab Tactic ProofScript ProofScript.Recording

namespace Test.RecorderDSLTest

set_option linter.unusedTactic false

-- Give user-facing DSL examples an independent recording session.
private def withTestRecording (execution : Syntax) (action : TacticM α) : TacticM α := do
  let previous := recordingSessionExt.getState (← getEnv)
  let previousRefs := theoremRefsExt.getState (← getEnv)
  modifyEnv (recordingSessionExt.setState · (some {}))
  try
    withExprJsonExport do
      clearTheoremRefs
      ensureBox ""
      withRecordingRule `Test.RecorderDSLTest execution action
  finally
    modifyEnv fun env =>
      theoremRefsExt.setState (recordingSessionExt.setState env previous) previousRefs

private def writeLabel [RecorderContext] (value : String) : TacticM Unit :=
  recordValue "label" value

run_cmd do
  let env ← getEnv
  for code in ["capture_params #[]", "record_value \"key\" 7", "execute_recorded"] do
    if (Parser.runParserCategory env `tactic code).isOk then
      throwError "recorder statement leaked into the native tactic parser: {code}"

-- Blocks support Lean control flow and lexical helpers. Nested blocks restore
-- the outer destination, and execution/captures happen only at their statements.
example : True → True := by
  run_tac
    if (← synthInstance? (mkConst ``RecorderContext)).isSome then
      throwError "a recorder context escaped into a global instance"
    let hypothesis := mkIdent `evidence
    withTestRecording (← `(tactic| intro $hypothesis:ident)) do
      let originalGoals ← getGoals
      let after := #[param (.category `ident) "after" hypothesis .required]
      recording_step do
        let mut total := 2
        for i in [0:3] do
          total := total + i
        if total == 5 then
          record_value "count" total
        else
          throwError "unexpected control flow"
        writeLabel "outer"
        recording_step do
          writeLabel "inner"
        record_value "after_nested" true
        unless (← getGoals) == originalGoals do
          throwError "a recording block implicitly executed the selected tactic"
        capture_params #[param (.category `ident) "before" hypothesis]
        execute_recorded
        capture_params after
      let proof ← takeBox ""
      unless proof.size == 2 &&
          (proof[0]!.getObjValAs? Nat "count").toOption == some 5 &&
          (proof[0]!.getObjValAs? String "label").toOption == some "outer" &&
          (proof[0]!.getObjValAs? Bool "after_nested").toOption == some true &&
          (proof[1]!.getObjValAs? String "label").toOption == some "inner" do
        throwError "control flow or lexical recording destinations were lost"
      unless (proof[0]!.getObjVal? "before").toOption == some Json.null &&
          (proof[0]!.getObjVal? "after").isOk &&
          (proof[0]!.getObjVal? "after").toOption != some Json.null do
        throwError "captures did not observe their respective execution states"
      for step in proof do
        if (step.getObjVal? "goal_before").isOk || (step.getObjVal? "goal_after").isOk then
          throwError "recording blocks implicitly added goal snapshots"
  assumption

-- The strategy form without a continuation prepares branches even if its body
-- returns early. Existing script branch traversal completes the recording.
example : True ∧ True := by
  run_tac
    withTestRecording (← `(tactic| constructor)) do
      recording_strategy (["left", "right"] : List String) do
        execute_recorded
        return ()
      advanceStrategyCase
      advanceStrategyCase
      finishRecordingStrategy
      let proof ← takeBox ""
      let branches ← ofExcept (proof[0]!.getObjValAs? (Array Json) "branches")
      unless branches.size == 2 &&
          (branches[0]!.getObjValAs? String "name").toOption == some "left" &&
          (branches[1]!.getObjValAs? String "name").toOption == some "right" do
        throwError "successful return skipped strategy preparation"
  all_goals trivial

-- The optional continuation argument enables captures in the continuation goal.
example : True := by
  run_tac
    let hypothesis := mkIdent `saved
    withTestRecording (← `(tactic| script_claim $hypothesis:ident : True)) do
      recording_strategy (["proof"] : List String) (continuation := some 1) do
        execute_recorded
        capture_params #[
          { (param (.category `ident) "hypothesis" hypothesis .required)
            with context := .continuation }
        ]
      advanceStrategyCase
      finishRecordingStrategy
      let proof ← takeBox ""
      unless (proof[0]!.getObjVal? "hypothesis").isOk &&
          (proof[0]!.getObjVal? "hypothesis").toOption != some Json.null do
        throwError "continuation capture lost its local context"
  all_goals trivial

-- A registered recorder may rename its parser binder; execute_recorded still
-- runs the original invocation with its original argument.
script_macro dslRegistered "dsl_registered" _original:term => `(tactic| exact $_original)

script_recorder dslRegistered
    (fields := #[{ name := "marker", schema := .number, nullable := false }])
    "dsl_registered" renamed:term => recording_step do
  let _ := renamed
  record_value "marker" (11 : Nat)
  execute_recorded

example : True := by
  run_tac
    withTestRecording (← `(tactic| skip)) do
      let source ← `(scriptTactic| dsl_registered True.intro)
      let some (registration, sourceCall) :=
          registeredTacticCall (scriptTacticRegistrations (← getEnv)) source.raw
        | throwError "missing DSL test registration"
      let some kind := registration.recordingKind
        | throwError "missing DSL test recorder"
      let recorder : TSyntax `tactic := ⟨← ofExcept <|
        rewriteTacticCall sourceCall registration.name
          (recordingTacticName registration.name) kind⟩
      evalTactic (← `(tactic| run_recorded_step $source:scriptTactic $recorder:tactic))
      let proof ← takeBox ""
      unless proof.size == 1 &&
          (proof[0]!.getObjValAs? Nat "marker").toOption == some 11 &&
          (proof[0]!.getObjValAs? String "_ruleId").toOption ==
            some "Test.RecorderDSLTest.dslRegistered" do
        throwError "registered DSL recorder lost its original invocation"

end Test.RecorderDSLTest
