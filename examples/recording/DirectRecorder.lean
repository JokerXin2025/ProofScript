import ProofScript

open Lean ProofScript ProofScript.Recording

script_macro snapshotThenClear "snapshot_then_clear" h:ident => `(tactic| clear $h:ident)

script_recorder snapshotThenClear (fields := ProofScript.Recording.goalFields ++ #[
  { name := "evidence_before", schema := .expression, nullable := false },
  { name := "module", schema := .string, nullable := false },
  { name := "evidence_after", schema := .expression }])
  "snapshot_then_clear" h:ident => withRecordingStep fun step => do
    step.recordGoal "goal_before"
    step.captureField "evidence_before" (expression h.raw)
    step.recordJson "module" (toJson (← getEnv).mainModule)
    executeRecordedStep
    step.recordGoal "goal_after"
    step.captureField "evidence_after" (expression h.raw) { onFailure := .bestEffort }

script_info snapshotThenClear {
  template := [{ lang := "zh", tag := "快照", content := "${module}：${evidence_before} → ${evidence_after}" },
               { lang := "en", tag := "Snapshot", content := "${module}: ${evidence_before} → ${evidence_after}" }]
}

@theorem directRecorderExample (discarded : True) : True := script
  snapshot_then_clear discarded
  trivial

page_end
