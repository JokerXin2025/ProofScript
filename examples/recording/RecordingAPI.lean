import ProofScript

open Lean ProofScript

/-! A small recorder example. Goal snapshots use the
    `record_goal` shorthands for `record_value`;
    ordinary fields use the typed parameter reader or `record_value`.
    Both record values without collecting literature references. -/

script_macro snapshotRule
  "snapshot_rule" h:ident => `(tactic| exact $h:ident)

script_recorder snapshotRule => do
  record_goal "$goal_before"
  record_param "evidence" h
  record_value "label" "captured"
  execute
  record_goal "$goal_after"

example (P : Prop) (h : P) : P := script
  snapshot_rule h

-- Parameter recording itself does not collect references.
theorem snapshotEvidence : True := True.intro

example : True := script
  snapshot_rule snapshotEvidence

-- This parameter is recorded for display; the executed proof uses only the local hypothesis.
script_macro snapshotOnlyRule
  "snapshot_only" _evidence:term "using" h:ident => `(tactic| exact $h:ident)

script_recorder snapshotOnlyRule => do
  record_goal "$goal_before"
  record_param "evidence" _evidence
  record_value "nested" (RecordedValue.object [
    ("proofs", .array #[.expression (mkConst ``snapshotEvidence)])])
  execute
  record_goal "$goal_after"

project_info "RecordingAPI" { title := "Recording and explicit citations" }
theorem_info snapshotEvidence { name := "Recorded evidence" }

script_info snapshotOnlyRule {
  template := [{ lang := "en", tag := "Recorded parameter", content := "${evidence}" }]
}
script_info snapshotRule {
  template := [{ lang := "en", tag := "Evidence", content := "${evidence}" }]
}

#page theorem recordedParameterOnly (h : True) : True := script
  snapshot_only snapshotEvidence using h

-- Explicit citation remains available when automatic collection is disabled.
set_option dependencyCollection false in
#page theorem explicitCitation (h : True) : True := script
  cite snapshotEvidence
  snapshot_rule h

#page references
#page end
