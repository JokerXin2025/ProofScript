import Test.RecorderVersionBase

open Lean ProofScript Elab Tactic

script_recorder importedRecorder (label := "extension") => do
  execute (label := "base")
  record_value "extension" true

example : True ∧ True := by
  run_tac do
    withRecordingSession do
      pushRecordingTag "imported-label"
      ensureBox "imported-label"
      setRecordingStatement (.plain .null)
      let call ← `(tactic| _script_imported_recorder)
      let some registration := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == `importedRecorder)
        | throwError "missing imported registration"
      let raw := if call.raw.getKind == `choice then call.raw.getArgs[0]! else call.raw
      let selected := changeNodeKind raw registration.recordingKind.get! raw.getArgs
      evalTactic (⟨selected⟩ : TSyntax `tactic)
      let (document, _) ← recordedProofJson "imported-label" "" `Test.RecorderVersionExtension
      let proof ← Lean.ofExcept <| document.getObjValAs? (Array Json) "proof"
      unless proof.size == 1 &&
          (proof[0]!.getObjValAs? Bool "base").toOption == some true &&
          (proof[0]!.getObjValAs? Bool "extension").toOption == some true do
        throwError "imported label did not execute its original body"

run_cmd do
  let some registration := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == `importedRecorder)
    | throwError "imported registration missing"
  unless registration.recorders.size == 3 &&
      registration.recorders[1]!.label == some "base" &&
      registration.recorders[2]!.label == some "extension" do
    throwError "imported recorder history was not preserved"

/-- error: duplicate recorder label `base` -/
#guard_msgs (substring := true) in
script_recorder importedRecorder (label := "base") => do
  execute init
