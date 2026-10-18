import ProofScript

open Lean ProofScript ProofScript.Recording

script_macro snapshotThenClear "snapshot_then_clear" h:ident => `(tactic| clear $h:ident)

script_recorder snapshotThenClear (fields := ProofScript.Recording.goalFields ++ #[
  { name := "evidence_before", schema := .expression, nullable := false },
  { name := "module", schema := .string, nullable := false },
  { name := "evidence_after", schema := .expression }])
  "snapshot_then_clear" h:ident => recording_step do
    capture_params #[
      goalParam "goal_before",
      { name := "evidence_before", onFailure := .required, capture := expression h.raw }
    ]
    record_value "module" (toJson (← getEnv).mainModule)
    execute_recorded
    capture_params #[
      goalParam "goal_after",
      { name := "evidence_after", onFailure := .bestEffort, capture := expression h.raw }
    ]

script_info snapshotThenClear {
  template := [{ lang := "zh", tag := "快照", content := "${module}：${evidence_before} → ${evidence_after}" },
               { lang := "en", tag := "Snapshot", content := "${module}: ${evidence_before} → ${evidence_after}" }]
}

@theorem directRecorderExample (discarded : True) : True := script
  snapshot_then_clear discarded
  trivial

page_end
