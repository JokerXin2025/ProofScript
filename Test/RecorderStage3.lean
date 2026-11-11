import ProofScript

open Lean ProofScript Elab Tactic

script_elab stage3 "stage3" => do
  evalTactic (← `(tactic| skip))

script_recorder stage3 (label := "one") => do
  execute
  record_value "one" true

script_recorder stage3 (label := "two") => do
  execute init
  record_value "two" true

script_recorder stage3 => do
  execute (label := "one")
  record_value "three" true

-- The labeled version is fixed when this declaration is elaborated.
script_recorder stage3 => do
  execute
  record_value "four" true

run_cmd do
  let some registration := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == `stage3)
    | throwError "missing stage3 registration"
  unless registration.recorders.size == 5 do
    throwError "expected five recorder versions"
  unless registration.recorders[1]!.label == some "one" &&
      registration.recorders[2]!.label == some "two" do
    throwError "recorder labels were not persisted"

-- A missing `execute` is rejected at declaration time.
/-- error: script_recorder requires exactly one top-level `execute` -/
#guard_msgs in
script_recorder stage3 => do
  pure ()

/-- error: script_recorder requires exactly one top-level `execute` -/
#guard_msgs in
script_recorder stage3 => do
  execute
  execute

/-- error: `execute` must be a direct statement of the outer recorder `do` block -/
#guard_msgs in
script_recorder stage3 => do
  if true then
    execute
  pure ()

/-- error: unknown recorder label `absent` for `stage3` -/
#guard_msgs in
script_recorder stage3 => do
  execute (label := "absent")

/-- error: duplicate recorder label `one` for `stage3` -/
#guard_msgs in
script_recorder stage3 (label := "one") => do
  execute

-- A top-level execute can be skipped by an early return; the step rejects it.
script_elab stage3Early "stage3_early" => do
  evalTactic (← `(tactic| trivial))

script_recorder stage3Early => do
  if true then return
  execute

example : True := by
  run_tac do
    withRecordingSession do
      pushRecordingTag "runtime-guard"
      ensureBox "runtime-guard"
      let call ← `(tactic| _script_stage3_early)
      let some registration := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == `stage3Early)
        | throwError "missing early-return recorder"
      let raw := if call.raw.getKind == `choice then call.raw.getArgs[0]! else call.raw
      let selected := changeNodeKind raw registration.recordingKind.get! raw.getArgs
      let failure ← try
        evalTactic (⟨selected⟩ : TSyntax `tactic)
        pure "no error"
      catch e => pure (← e.toMessageData.toString)
      unless failure.contains "without executing its initial version" do
        throwError "expected runtime guard error, got: {failure}"
    evalTactic (← `(tactic| trivial))

example : True := by
  run_tac do
    withRecordingSession do
      pushRecordingTag "duplicate-initial"
      ensureBox "duplicate-initial"
      let failure ← try
        withRecordingRule `stage3 do
          withRecordingStep fun step => do
            step.markInitialExecuted
            step.markInitialExecuted
        pure "no error"
      catch e => pure (← e.toMessageData.toString)
      unless failure.contains "executed its initial version more than once" do
        throwError "expected duplicate initial recorder guard, got: {failure}"
    evalTactic (← `(tactic| trivial))

example : True := by
  run_tac do
    withRecordingSession do
      pushRecordingTag "initial-only"
      ensureBox "initial-only"
      setRecordingStatement (.plain .null)
      let call ← `(tactic| _script_stage3)
      let some registration := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == `stage3)
        | throwError "missing initial recorder"
      let raw := if call.raw.getKind == `choice then call.raw.getArgs[0]! else call.raw
      let initial := changeNodeKind raw registration.recorders[0]!.kind raw.getArgs
      evalTactic (⟨initial⟩ : TSyntax `tactic)
      let (document, _) ← recordedProofJson "initial-only" "" `Test.RecorderStage3
      let proof ← Lean.ofExcept <| document.getObjValAs? (Array Json) "proof"
      let step := proof[0]!
      unless (step.getObjValAs? String "$ruleId").toOption == some "stage3" &&
          (step.getObjVal? "one").toOption.isNone &&
          (step.getObjVal? "$goal_before").toOption.isNone &&
          (step.getObjValAs? Nat "$time_before").toOption.isSome &&
          (step.getObjValAs? Nat "$time_after").toOption.isSome do
        throwError "initial recorder should only provide the base fields"
    evalTactic (← `(tactic| trivial))

example : True := by
  run_tac do
    withRecordingSession do
      pushRecordingTag "version-dispatch"
      ensureBox "version-dispatch"
      setRecordingStatement (.plain .null)
      let call ← `(tactic| _script_stage3)
      let some registration := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == `stage3)
        | throwError "missing versioned recorder"
      let raw := if call.raw.getKind == `choice then call.raw.getArgs[0]! else call.raw
      let selected := changeNodeKind raw registration.recordingKind.get! raw.getArgs
      evalTactic (⟨selected⟩ : TSyntax `tactic)
      let (document, _) ← recordedProofJson "version-dispatch" "" `Test.RecorderStage3
      let proof ← Lean.ofExcept <| document.getObjValAs? (Array Json) "proof"
      unless proof.size == 1 do throwError "versions created more than one recording step"
      let step := proof[0]!
      unless (step.getObjValAs? String "$ruleId").toOption == some "stage3" &&
          (step.getObjValAs? Bool "one").toOption == some true &&
          (step.getObjValAs? Bool "three").toOption == some true &&
          (step.getObjValAs? Bool "four").toOption == some true &&
          (step.getObjVal? "two").toOption.isNone do
        throwError "labeled delegation did not select its declared target"
      let before ← Lean.ofExcept <| step.getObjValAs? Nat "$time_before"
      let after ← Lean.ofExcept <| step.getObjValAs? Nat "$time_after"
      unless before ≤ after do throwError "initial recorder timestamps are reversed"
    evalTactic (← `(tactic| trivial))
