import ProofScript

open Lean Elab Tactic ProofScript ProofScript.Recording

script_macro apiMetadata "api_metadata" => `(tactic| skip)
script_recorder apiMetadata (fields := ProofScript.Recording.goalFields ++ #[
  { name := "module", schema := .string, nullable := false }])
  "api_metadata" => recording_step do
    capture_params #[goalParam "goal_before"]
    record_value "module" (toJson (← getEnv).mainModule)
    execute_recorded
    capture_params #[goalParam "goal_after"]

script_macro apiNested "api_nested" => `(tactic| skip)
script_recorder apiNested (fields := ProofScript.Recording.goalFields ++ #[
  { name := "label", schema := .string, nullable := false }])
  "api_nested" => recording_step do
    capture_params #[goalParam "goal_before"]
    recording_step do
      capture_params #[goalParam "goal_before"]
      record_value "label" "inner"
      capture_params #[goalParam "goal_after"]
    record_value "label" "outer"
    execute_recorded
    capture_params #[goalParam "goal_after"]

script_macro apiRecovery "api_recovery" => `(tactic| skip)
script_recorder apiRecovery (fields := ProofScript.Recording.goalFields ++ #[
  { name := "label", schema := .string, nullable := false }])
  "api_recovery" => do
    try
      recording_step do
        capture_params #[goalParam "goal_before"]
        record_value "label" "discarded"
        throwError "intentional recording failure"
    catch _ => pure ()
    recording_step do
      capture_params #[goalParam "goal_before"]
      record_value "label" "retained"
      execute_recorded
      capture_params #[goalParam "goal_after"]

script_macro apiMixed "api_mixed" => `(tactic| skip)
script_recorder apiMixed (fields := ProofScript.Recording.goalFields ++ #[
  { name := "label", schema := .string, nullable := false },
  { name := "count", schema := .number, nullable := false }])
  "api_mixed" => recording_step do
    capture_params #[goalParam "goal_before"]
    record_value "label" "direct"
    capture_params #[
      { name := "count", onFailure := .required,
        capture := pure (.scalar (json% 7)) }
    ]
    execute_recorded
    capture_params #[goalParam "goal_after"]

script_macro apiPlanCollision "api_plan_collision" => `(tactic| trivial)
script_recorder apiPlanCollision "api_plan_collision" => recording_step do
  capture_params #[goalParam "goal_before"]
  record_value "label" "direct"
  capture_params #[
    { name := "label", capture := pure (.scalar (json% "plan")) }
  ]
  execute_recorded
  capture_params #[goalParam "goal_after"]

script_macro apiScheduled "api_scheduled" h:ident => `(tactic| clear $h:ident; trivial)
script_recorder apiScheduled (fields := ProofScript.Recording.goalFields ++ #[
  { name := "evidence_before", schema := .expression, nullable := false },
  { name := "evidence_after", schema := .expression },
  { name := "closed", schema := .string, nullable := false }])
  "api_scheduled" h:ident => recording_step do
    capture_params #[goalParam "goal_before", param (.category `ident) "evidence_before" h .required]
    execute_recorded
    capture_params #[
      goalParam "goal_after",
      param (.category `ident) "evidence_after" h,
      { name := "closed", onFailure := .required, capture := pure (.scalar (json% "no remaining goal")) }
    ]

script_macro apiPhaseCollision "api_phase_collision" => `(tactic| trivial)
script_recorder apiPhaseCollision "api_phase_collision" => recording_step do
  capture_params #[goalParam "goal_before", { name := "label", capture := pure (.scalar (json% "before")) }]
  execute_recorded
  capture_params #[goalParam "goal_after", { name := "label", capture := pure (.scalar (json% "after")) }]

script_macro apiRequiredAfter (params := [h(timing := both, failure := required)])
  "api_required_after" h:ident => `(tactic| clear $h:ident)

script_macro apiMetadataOnly "api_metadata_only" => `(tactic| trivial)
script_recorder apiMetadataOnly (fields := #[
  { name := "goal", schema := .string, nullable := false }])
  "api_metadata_only" => recording_step do
    record_value "goal" "ordinary metadata"
    execute_recorded

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
script_recorder apiGoalCollision "api_goal_collision" => recording_step do
  capture_params #[goalParam "goal_before", { name := "goal_before", capture := pure (.scalar (json% "conflict")) }]
  execute_recorded
  capture_params #[goalParam "goal_after"]

script_macro apiReserved "api_reserved" => `(tactic| trivial)
script_recorder apiReserved "api_reserved" => recording_step do
  capture_params #[goalParam "goal_before"]
  record_value "_ruleId" "bad"
  execute_recorded
  capture_params #[goalParam "goal_after"]

script_macro apiDuplicate "api_duplicate" => `(tactic| trivial)
script_recorder apiDuplicate "api_duplicate" => recording_step do
  capture_params #[goalParam "goal_before"]
  record_value "label" "first"
  record_value "label" "second"
  execute_recorded
  capture_params #[goalParam "goal_after"]

script_macro apiDuplicateGoal "api_duplicate_goal" => `(tactic| trivial)
script_recorder apiDuplicateGoal "api_duplicate_goal" => recording_step do
  capture_params #[goalParam "goal_before"]
  capture_params #[goalParam "goal_before"]
  execute_recorded
  capture_params #[goalParam "goal_after"]

script_macro apiClosed "api_closed" => `(tactic| trivial)
script_recorder apiClosed "api_closed" => do
  let closed ← recording_step do
    capture_params #[goalParam "goal_before"]
    return (inferInstance : RecorderContext).step
  -- Deliberately bypass the DSL scope to exercise a closed low-level handle.
  closed.recordJson "label" "late"

script_macro apiSnapshots "api_snapshots" h:ident => `(tactic| clear $h:ident)
script_recorder apiSnapshots (fields := ProofScript.Recording.goalFields ++ #[
  { name := "before", schema := .expression, nullable := false },
  { name := "after", schema := .expression },
  { name := "payload", schema := .array (.object [
      ("proof", .expression), ("flag", .boolean)]), nullable := false }])
  "api_snapshots" h:ident => recording_step do
    capture_params #[goalParam "goal_before", param (.category `ident) "before" h .required]
    let payload ← isolatedCapture do
      return .array #[.object [("proof", ← expression h.raw), ("flag", .scalar (json% true))]]
    record_value "payload" payload
    execute_recorded
    capture_params #[goalParam "goal_after", param (.category `ident) "after" h]

script_macro apiFinish "api_finish" => `(tactic| trivial)
script_recorder apiFinish (fields := ProofScript.Recording.goalFields ++ #[
  { name := "closed", schema := .string, nullable := false }])
  "api_finish" => recording_step do
    capture_params #[goalParam "goal_before"]
    execute_recorded
    capture_params #[
      goalParam "goal_after",
      { name := "closed", onFailure := .required, capture := pure (.scalar (json% "no remaining goal")) }
    ]

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
      recording_step do
        capture_params #[
          goalParam "goal_before",
          { name := "discarded", onFailure := .required,
            capture := expression (mkIdent ``apiDiscardedReference) }
        ]
        throwError "intentional recording failure"
    catch _ => pure ()
    recording_step do
      capture_params #[
        goalParam "goal_before",
        { name := "kept", onFailure := .required,
          capture := expression (mkIdent ``apiKeptReference) }
      ]
      let rejected ← isolatedCapture (expression (mkIdent ``apiDiscardedReference))
      try
        record_value "kept" rejected
      catch _ => pure ()
      capture_params #[
        { name := "suppressed", onFailure := .required, collectReferences := false,
          capture := expression (mkIdent ``apiSuppressedReference) }
      ]
      execute_recorded
      capture_params #[goalParam "goal_after"]

script_elab apiClaim (strategy := true, continuation := 1)
  "api_claim" h:ident => do
    evalTactic (← `(tactic| script_claim $h:ident : True))

script_recorder apiClaim (fields := ProofScript.Recording.strategyGoalFields ++ #[
  { name := "h", schema := .expression, nullable := false },
  { name := "label", schema := .string, nullable := false }])
  "api_claim" h:ident "_strategy_cases" strategyCases:str => do
    try
      recording_step do
        -- The inner runner has prepared branches before this outer block fails.
        recording_strategy (strategyCases.getString.splitOn "\n") (continuation := some 1) do
          capture_params #[goalParam "goal_before"]
          execute_recorded
        throwError "intentional branch preparation failure"
    catch _ => pure ()
    recording_strategy (strategyCases.getString.splitOn "\n") (continuation := some 1) do
      capture_params #[goalParam "goal_before"]
      execute_recorded
      capture_params #[
        { (param (.category `ident) "h" h .required) with context := .continuation }
      ]
      record_value "label" h.getId.toString

script_elab apiSplit (strategy := true) "api_split" => do
  evalTactic (← `(tactic| script_split_and))

script_recorder apiSplit (fields := ProofScript.Recording.strategyGoalFields ++ #[
  { name := "leftType", schema := .expression, nullable := false }])
  "api_split" "_strategy_cases" strategyCases:str =>
    recording_strategy (strategyCases.getString.splitOn "\n") do
      capture_params #[goalParam "goal_before"]
      execute_recorded
      capture_params #[
        { name := "leftType", context := .branch "left", onFailure := .required,
          capture := do snapshotExpression (← (← getMainGoal).getType) }
      ]

-- Only the left branch has h; put the right branch first so after capture must
-- select its configured branch rather than use the main goal's context.
script_elab apiBranchCapture
    (strategy := true,
     params := [h(timing := after, context := left, failure := required)])
    "api_branch_capture" h:ident => do
  evalTactic (← `(tactic| constructor))
  evalTactic (← `(tactic| intro $h:ident))
  setGoals (← getGoals).reverse

-- Qualified tags exercise exact script selection and canonical output names.
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
