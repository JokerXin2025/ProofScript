import ProofScript

open Lean Elab Tactic ProofScript ProofScript.Recording

script_macro apiMetadata "api_metadata" => `(tactic| skip)
script_recorder apiMetadata (fields := ProofScript.Recording.goalFields ++ #[
  { name := "module", schema := .string, nullable := false }])
  "api_metadata" => withRecordingStep fun step => do
    step.recordGoal "goal_before"
    step.recordJson "module" (toJson (← getEnv).mainModule)
    executeRecordedStep
    step.recordGoal "goal_after"

script_macro apiNested "api_nested" => `(tactic| skip)
script_recorder apiNested (fields := ProofScript.Recording.goalFields ++ #[
  { name := "label", schema := .string, nullable := false }])
  "api_nested" => withRecordingStep fun outer => do
    outer.recordGoal "goal_before"
    withRecordingStep fun inner => do
      inner.recordGoal "goal_before"
      inner.recordJson "label" "inner"
      inner.recordGoal "goal_after"
    outer.recordJson "label" "outer"
    executeRecordedStep
    outer.recordGoal "goal_after"

script_macro apiRecovery "api_recovery" => `(tactic| skip)
script_recorder apiRecovery (fields := ProofScript.Recording.goalFields ++ #[
  { name := "label", schema := .string, nullable := false }])
  "api_recovery" => do
    try
      withRecordingStep fun step => do
        step.recordGoal "goal_before"
        step.recordJson "label" "discarded"
        throwError "intentional recording failure"
    catch _ => pure ()
    withRecordingStep fun step => do
      step.recordGoal "goal_before"
      step.recordJson "label" "retained"
      executeRecordedStep
      step.recordGoal "goal_after"

script_macro apiMixed "api_mixed" => `(tactic| skip)
script_recorder apiMixed (fields := ProofScript.Recording.goalFields ++ #[
  { name := "label", schema := .string, nullable := false },
  { name := "count", schema := .number, nullable := false }])
  "api_mixed" => withRecordingStep fun step => do
    step.recordGoal "goal_before"
    step.recordJson "label" "direct"
    step.capturePlan #[
      { name := "count", onFailure := .required,
        capture := pure (.scalar (json% 7)) }
    ]
    executeRecordedStep
    step.recordGoal "goal_after"

script_macro apiPlanCollision "api_plan_collision" => `(tactic| trivial)
script_recorder apiPlanCollision "api_plan_collision" => withRecordingStep fun step => do
  step.recordGoal "goal_before"
  step.recordJson "label" "direct"
  step.capturePlan #[
    { name := "label", capture := pure (.scalar (json% "plan")) }
  ]
  executeRecordedStep
  step.recordGoal "goal_after"

script_macro apiScheduled "api_scheduled" h:ident => `(tactic| clear $h:ident; trivial)
script_recorder apiScheduled (fields := ProofScript.Recording.goalFields ++ #[
  { name := "evidence_before", schema := .expression, nullable := false },
  { name := "evidence_after", schema := .expression },
  { name := "closed", schema := .string, nullable := false }])
  "api_scheduled" h:ident => do
    recordStep
      (before := #[param (.category `ident) "evidence_before" h .required])
      (after := #[
        param (.category `ident) "evidence_after" h,
        { name := "closed", onFailure := .required, capture := pure (.scalar (json% "no remaining goal")) }
      ])

script_macro apiPhaseCollision "api_phase_collision" => `(tactic| trivial)
script_recorder apiPhaseCollision "api_phase_collision" => do
  recordStep
    (before := #[{ name := "label", capture := pure (.scalar (json% "before")) }])
    (after := #[{ name := "label", capture := pure (.scalar (json% "after")) }])

script_macro apiRequiredAfter (params := [h(timing := both, failure := required)])
  "api_required_after" h:ident => `(tactic| clear $h:ident)

script_macro apiMetadataOnly "api_metadata_only" => `(tactic| trivial)
script_recorder apiMetadataOnly (fields := #[
  { name := "goal", schema := .string, nullable := false }])
  "api_metadata_only" => withRecordingStep fun step => do
    step.recordJson "goal" "ordinary metadata"
    executeRecordedStep

script_macro apiGoalSnapshots "api_goal_snapshots" => `(tactic| intro evidence)
script_info apiGoalSnapshots {
  template := [{ lang := "zh", tag := "目标", content := "${goal_before} → ${goal_after}" },
               { lang := "en", tag := "Goals", content := "${goal_before} → ${goal_after}" }]
}
script_info apiMetadataOnly {
  template := [{ lang := "zh", tag := "元数据", content := "${goal}" },
               { lang := "en", tag := "Metadata", content := "${goal}" }]
}

script_macro apiGoalCollision "api_goal_collision" => `(tactic| trivial)
script_recorder apiGoalCollision "api_goal_collision" => do
  recordStep (before := #[{ name := "goal_before", capture := pure (.scalar (json% "conflict")) }])

script_macro apiReserved "api_reserved" => `(tactic| trivial)
script_recorder apiReserved "api_reserved" => withRecordingStep fun step => do
  step.recordGoal "goal_before"
  step.recordJson "_ruleId" "bad"
  executeRecordedStep
  step.recordGoal "goal_after"

script_macro apiDuplicate "api_duplicate" => `(tactic| trivial)
script_recorder apiDuplicate "api_duplicate" => withRecordingStep fun step => do
  step.recordGoal "goal_before"
  step.recordJson "label" "first"
  step.recordJson "label" "second"
  executeRecordedStep
  step.recordGoal "goal_after"

script_macro apiDuplicateGoal "api_duplicate_goal" => `(tactic| trivial)
script_recorder apiDuplicateGoal "api_duplicate_goal" => withRecordingStep fun step => do
  step.recordGoal "goal_before"
  step.recordGoal "goal_before"
  executeRecordedStep
  step.recordGoal "goal_after"

script_macro apiClosed "api_closed" => `(tactic| trivial)
script_recorder apiClosed "api_closed" => do
  let closed ← withRecordingStep fun step => do
    step.recordGoal "goal_before"
    return step
  closed.recordJson "label" "late"
  executeRecordedStep

script_macro apiSnapshots "api_snapshots" h:ident => `(tactic| clear $h:ident)
script_recorder apiSnapshots (fields := ProofScript.Recording.goalFields ++ #[
  { name := "before", schema := .expression, nullable := false },
  { name := "after", schema := .expression },
  { name := "payload", schema := .array (.object [
      ("proof", .expression), ("flag", .boolean)]), nullable := false }])
  "api_snapshots" h:ident => withRecordingStep fun step => do
    step.recordGoal "goal_before"
    step.captureField "before" (expression h.raw)
    let payload ← isolatedCapture do
      return .array #[.object [("proof", ← expression h.raw), ("flag", .scalar (json% true))]]
    step.recordValue "payload" payload
    executeRecordedStep
    step.recordGoal "goal_after"
    step.captureField "after" (expression h.raw) { onFailure := .bestEffort }

script_macro apiFinish "api_finish" => `(tactic| trivial)
script_recorder apiFinish (fields := ProofScript.Recording.goalFields ++ #[
  { name := "closed", schema := .string, nullable := false }])
  "api_finish" => withRecordingStep fun step => do
    step.recordGoal "goal_before"
    executeRecordedStep
    step.recordGoal "goal_after"
    step.captureField "closed" (pure (.scalar (json% "no remaining goal")))

theorem apiDiscardedReference : True := True.intro
theorem_info apiDiscardedReference { name := "Discarded reference" }
theorem apiKeptReference : True := True.intro
theorem_info apiKeptReference { name := "Kept reference" }
theorem apiSuppressedReference : True := True.intro
theorem_info apiSuppressedReference { name := "Suppressed reference" }

script_macro apiCitations "api_citations" => `(tactic| skip)
script_recorder apiCitations (fields := ProofScript.Recording.goalFields ++ #[
  { name := "kept", schema := .expression, nullable := false },
  { name := "suppressed", schema := .expression, nullable := false }])
  "api_citations" => do
    try
      withRecordingStep fun step => do
        step.recordGoal "goal_before"
        step.captureField "discarded" (expression (mkIdent ``apiDiscardedReference))
        throwError "intentional recording failure"
    catch _ => pure ()
    withRecordingStep fun step => do
      step.recordGoal "goal_before"
      step.captureField "kept" (expression (mkIdent ``apiKeptReference))
      let rejected ← isolatedCapture (expression (mkIdent ``apiDiscardedReference))
      try
        step.recordValue "kept" rejected
      catch _ => pure ()
      step.captureField "suppressed" (expression (mkIdent ``apiSuppressedReference))
        { collectReferences := false }
      executeRecordedStep
      step.recordGoal "goal_after"

script_elab apiClaim (strategy := true, continuation := 1)
  "api_claim" h:ident => do
    evalTactic (← `(tactic| script_claim $h:ident : True))

script_recorder apiClaim (fields := ProofScript.Recording.goalFields ++ #[
  { name := "h", schema := .expression, nullable := false },
  { name := "label", schema := .string, nullable := false }])
  "api_claim" h:ident "_strategy_cases" strategyCases:str => do
    try
      withRecordingStep fun step => do
        step.recordGoal "goal_before"
        executeRecordedStep
        step.recordGoal "goal_after"
        step.prepareBranches (← resolveStrategyContexts (strategyCases.getString.splitOn "\n") (some 1))
        throwError "intentional branch preparation failure"
    catch _ => pure ()
    withRecordingStep fun step => do
      step.recordGoal "goal_before"
      executeRecordedStep
      step.recordGoal "goal_after"
      let contexts ← resolveStrategyContexts (strategyCases.getString.splitOn "\n") (some 1)
      step.captureField "h" (expression h.raw) { goal := ← contexts.goal .continuation }
      step.prepareBranches contexts
      step.recordJson "label" (toJson h.getId.toString)

script_elab apiSplit (strategy := true) "api_split" => do
  evalTactic (← `(tactic| script_split_and))

script_recorder apiSplit (fields := ProofScript.Recording.goalFields ++ #[
  { name := "leftType", schema := .expression, nullable := false }])
  "api_split" "_strategy_cases" strategyCases:str => withRecordingStep fun step => do
    step.recordGoal "goal_before"
    executeRecordedStep
    step.recordGoal "goal_after"
    let contexts ← resolveStrategyContexts (strategyCases.getString.splitOn "\n")
    step.captureField "leftType" (do
      snapshotExpression (← (← getMainGoal).getType))
      { goal := ← contexts.goal (.branch "left") }
    step.prepareBranches contexts

-- These are real tactic goals; both the recording resolver and Lean's case tactic
-- must accept the suffix and prefix labels used below.
script_elab apiTagged (strategy := true) "api_tagged" => do
  evalTactic (← `(tactic| constructor))
  let goals ← getGoals
  for (goal, tag) in goals.zip [`scope.left, `other.right] do
    goal.setTag tag

script_elab apiAmbiguous (strategy := true) "api_ambiguous" => do
  evalTactic (← `(tactic| constructor))
  let goals ← getGoals
  for (goal, tag) in goals.zip [`left.proof, `right.proof] do
    goal.setTag tag

script_info apiMetadata {
  template := [{ lang := "zh", tag := "环境", content := "${module}" },
               { lang := "en", tag := "Environment", content := "${module}" }]
}
script_info apiNested {
  template := [{ lang := "zh", tag := "嵌套", content := "${label}" },
               { lang := "en", tag := "Nested", content := "${label}" }]
}
script_info apiRecovery {
  template := [{ lang := "zh", tag := "恢复", content := "${label}" },
               { lang := "en", tag := "Recovery", content := "${label}" }]
}
script_info apiMixed {
  template := [{ lang := "zh", tag := "组合", content := "${label} ${count}" },
               { lang := "en", tag := "Combined", content := "${label} ${count}" }]
}
script_info apiSnapshots {
  template := [{ lang := "zh", tag := "快照", content := "${before} → ${after}; ${payload}" },
               { lang := "en", tag := "Snapshot", content := "${before} → ${after}; ${payload}" }]
}
script_info apiScheduled {
  template := [{ lang := "zh", tag := "默认编排", content := "${evidence_before} → ${evidence_after}; ${closed}" },
               { lang := "en", tag := "Scheduled", content := "${evidence_before} → ${evidence_after}; ${closed}" }]
}
script_info apiFinish {
  template := [{ lang := "zh", tag := "结束", content := "${closed}" },
               { lang := "en", tag := "Finished", content := "${closed}" }]
}
script_info apiCitations {
  template := [{ lang := "zh", tag := "引用", content := "${kept}; ${suppressed}" },
               { lang := "en", tag := "Citation", content := "${kept}; ${suppressed}" }]
}
script_info apiClaim {
  template := [{ lang := "zh", tag := "断言", introducer := { tag := "断言", content := "${label}：${h}" },
                 cases := [{ name := "proof", tag := "证明", title := "" }] },
               { lang := "en", tag := "Claim", introducer := { tag := "Claim", content := "${label}: ${h}" },
                 cases := [{ name := "proof", tag := "Proof", title := "" }] }]
}
script_info apiSplit {
  template := [{ lang := "zh", tag := "分支", introducer := { tag := "分支", content := "${leftType}" }, cases := [
                 { name := "right", tag := "右侧", title := "" },
                 { name := "left", tag := "左侧", title := "" }] },
               { lang := "en", tag := "Branches", introducer := { tag := "Branches", content := "${leftType}" }, cases := [
                 { name := "right", tag := "Right", title := "" },
                 { name := "left", tag := "Left", title := "" }] }]
}
