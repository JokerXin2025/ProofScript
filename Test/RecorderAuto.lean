import ProofScript.Script.Script

open Lean ProofScript Elab Tactic

script_elab recorderAuto "recorder_auto" n:num => do
  evalTactic (← `(tactic| skip))

script_recorder recorderAuto (label := "params") auto

script_elab recorderIntro "recorder_intro" h:ident => do
  evalTactic (← `(tactic| intro $h:ident))

script_recorder recorderIntro auto (intro := [h])

example : True → True := by
  run_tac do
    withRecordingSession do
      pushRecordingTag "auto-intro"
      ensureBox "auto-intro"
      setRecordingStatement (.plain .null)
      let call ← `(tactic| _script_recorder_intro h)
      let some registration := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == `recorderIntro)
        | throwError "missing intro recorder"
      let raw := if call.raw.getKind == `choice then call.raw.getArgs[0]! else call.raw
      let selected := changeNodeKind raw registration.recordingKind.get! raw.getArgs
      evalTactic (⟨selected⟩ : TSyntax `tactic)
      let (document, _) ← recordedProofJson "auto-intro" "" `Test.RecorderAuto
      let proof ← Lean.ofExcept <| document.getObjValAs? (Array Json) "proof"
      let step := proof[0]!
      unless (step.getObjVal? "h_after").toOption.isSome &&
          (step.getObjVal? "h_before").toOption.isNone do
        throwError "intro parameter was recorded on the wrong side"
    evalTactic (← `(tactic| assumption))

script_elab unsupportedAuto "unsupported_auto" param:(group("(" term ")"))? => do
  evalTactic (← `(tactic| skip))

declare_syntax_cat recorderMissingReader
syntax "payload" : recorderMissingReader

script_elab missingReader "missing_reader" param:recorderMissingReader => do
  evalTactic (← `(tactic| skip))

/-- error: [script recorder] 'missing_reader': 参数 'param' 缺少 RecordValue 实例 -/
#guard_msgs (substring := true) in
script_recorder missingReader auto

run_cmd do
  let some registration := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == `missingReader)
    | throwError "missing missingReader registration"
  unless registration.recorders.size == 1 do
    throwError "missing instance added an invalid recorder version"

/-- error: [script recorder] 'unsupported_auto': 参数 'param' parameter parser produces an anonymous syntax type -/
#guard_msgs (substring := true) in
script_recorder unsupportedAuto auto

run_cmd do
  let some registration := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == `unsupportedAuto)
    | throwError "missing unsupportedAuto"
  unless registration.recorders.size == 1 do
    throwError "failed auto command changed recorder history"

/-- error: `intro` and `clear` belong to `script_recorder <id> auto` -/
#guard_msgs (substring := true) in
script_elab legacyAuto (intro := [h]) "legacy_auto" h:ident => pure ()

/-- error: unknown auto recorder config field `kind` -/
#guard_msgs (substring := true) in
script_recorder recorderAuto auto (kind := tactic)

/-- error: [script recorder] 'recorder_auto': 参数 'absent' 不在 syntax 参数中 -/
#guard_msgs (substring := true) in
script_recorder recorderAuto auto (clear := [absent])

script_recorder recorderAuto => do
  execute (label := "params")

run_cmd do
  let some registration := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == `recorderAuto)
    | throwError "missing recorderAuto"
  unless registration.recorders.size == 3 && registration.recorders[1]!.label == some "params" do
    throwError "auto did not create a regular labeled recorder version"

example : True := by
  run_tac do
    withRecordingSession do
      pushRecordingTag "auto-fields"
      ensureBox "auto-fields"
      setRecordingStatement (.plain .null)
      let call ← `(tactic| _script_recorder_auto 7)
      let some registration := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == `recorderAuto)
        | throwError "missing auto recorder"
      let raw := if call.raw.getKind == `choice then call.raw.getArgs[0]! else call.raw
      let selected := changeNodeKind raw registration.recordingKind.get! raw.getArgs
      evalTactic (⟨selected⟩ : TSyntax `tactic)
      let (document, _) ← recordedProofJson "auto-fields" "" `Test.RecorderAuto
      let proof ← Lean.ofExcept <| document.getObjValAs? (Array Json) "proof"
      unless proof.size == 1 do throwError "auto created multiple recording steps"
      let step := proof[0]!
      unless (step.getObjValAs? String "$ruleId").toOption == some "recorderAuto" &&
          (step.getObjVal? "n_before").toOption.isSome &&
          (step.getObjVal? "n_after").toOption.isSome &&
          (step.getObjVal? "$goal_before").toOption.isSome &&
          (step.getObjVal? "$goal_after").toOption.isSome do
        throwError "explicit auto did not record parameters and goal snapshots"
    evalTactic (← `(tactic| trivial))
