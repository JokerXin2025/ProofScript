import Test.RecordingAPIRules

project_info "Test.RecordingAPITest" { title := "RecordingAPITest" }

open Lean Elab Tactic ProofScript ProofScript.Recording

set_option linter.unusedVariables false

-- Explicit full tags and bullets must produce the same output names, while
-- preserving the requested branch order and exact context lookup.
example : True ∧ True := by
  constructor
  run_tac
    let goals ← getGoals
    for (goal, tag) in goals.zip [`scope.left, `other.right] do
      goal.setTag tag
    let named ← resolveStrategyContexts ["other.right", "scope.left"]
    let anonymous ← resolveStrategyContexts ["", ""]
    unless named.branches.map (·.name) == ["right", "left"] &&
        anonymous.branches.map (·.name) == ["left", "right"] do
      throwError "branch names must come from goal tags"
    unless (← named.goal (.branch "left")) == goals[0]? &&
        (← named.goal (.branch "scope.left")) == goals[0]? &&
        (← named.goal (.branch "scope")).isNone do
      throwError "branch contexts must use canonical names or exact tags"
  all_goals trivial

example : True ∧ True := script
  api_tagged
  | other.right => trivial
  | scope.left => trivial

example : True ∧ True := script
  api_tagged
  · trivial
  · trivial

-- Reject abbreviations in ordinary (non-recording) script execution too.
example : True ∧ True := by
  fail_if_success
    exact (script
      api_tagged
      | right => trivial
      | left => trivial)
  fail_if_success
    exact (script
      api_tagged
      | scope => trivial
      | other => trivial)
  constructor <;> trivial

@theorem recordingAPIMetadata : True := script
  api_metadata
  trivial

@theorem recordingAPINested : True := script
  api_nested
  trivial

@theorem recordingAPIRecovery : True := script
  api_recovery
  trivial

@theorem recordingAPIMixed : True := script
  api_mixed
  trivial

/--
error: duplicate recorded parameter field `label`
-/
#guard_msgs in
@theorem recordingAPIPlanCollision : True := script
  api_plan_collision

@theorem recordingAPIMetadataOnly : True := script
  api_metadata_only

@theorem recordingAPIGoals : True → True := script
  api_goal_snapshots
  assumption

/--
error: duplicate recorded parameter field `goal_before`
-/
#guard_msgs in
@theorem recordingAPIGoalCollision : True := script
  api_goal_collision

/--
error: reserved recorded parameter field `_ruleId`
-/
#guard_msgs in
@theorem recordingAPIReserved : True := script
  api_reserved

/--
error: duplicate recorded parameter field `label`
-/
#guard_msgs in
@theorem recordingAPIDuplicate : True := script
  api_duplicate

/--
error: duplicate recorded parameter field `goal_before`
-/
#guard_msgs in
@theorem recordingAPIDuplicateGoal : True := script
  api_duplicate_goal

/--
error: recording step is closed
-/
#guard_msgs in
@theorem recordingAPIClosed : True := script
  api_closed

@theorem recordingAPISnapshots (discarded : True) : True := script
  api_snapshots discarded
  trivial

@theorem recordingAPIScheduled (discarded : True) : True := script
  api_scheduled discarded

/--
error: duplicate recorded parameter field `label`
-/
#guard_msgs in
@theorem recordingAPIPhaseCollision : True := script
  api_phase_collision

/--
error: failed to record parameter `h`: Unknown identifier `discarded`
-/
#guard_msgs in
@theorem recordingAPIRequiredAfter (discarded : True) : True := script
  api_required_after discarded
  trivial

@theorem recordingAPIFinish : True := script
  api_finish

@theorem recordingAPICitations : True := script
  api_citations
  trivial

@theorem recordingAPIStrategies : True ∧ True := script
  api_split
  | right =>
    api_claim rightClaim
    · trivial
    exact rightClaim
  | left =>
    api_claim outerClaim
    | proof =>
      api_claim innerClaim
      · trivial
      exact innerClaim
    api_claim laterClaim
    · exact outerClaim
    exact laterClaim

@theorem recordingAPIFullBranches : True ∧ True := script
  api_tagged
  | other.right => trivial
  | scope.left => trivial

@theorem recordingAPIAnonymousBranches : True ∧ True := script
  api_tagged
  · trivial
  · trivial

@theorem recordingAPIAfterContexts : (True → True) ∧ True := script
  api_branch_capture branchHypothesis
  | right => trivial
  | left =>
    claim saved : True
    | proof => exact branchHypothesis
    exact saved

-- Check the exported envelope recursively: nested strategies share the same
-- contract as top-level strategies, while ordinary steps retain both snapshots.
open Lean Elab Command in
run_cmd do
  let readProof := fun (decl : Name) => do
    let .ok document := Json.parse
        (← IO.FS.readFile (proofOutputPath (← getEnv).mainModule decl))
      | throwError "invalid recorded proof"
    ofExcept (document.getObjValAs? (Array Json) "proof")
  for decl in [`recordingAPIMetadata, `recordingAPIStrategies,
      `recordingAPIFullBranches, `recordingAPIAnonymousBranches,
      `recordingAPIAfterContexts] do
    let mut remaining := (← readProof decl).toList
    while !remaining.isEmpty do
      let step := remaining.head!
      remaining := remaining.tail
      unless (step.getObjVal? "goal_before").isOk do
        throwError "missing goal_before snapshot"
      if let .ok branches := step.getObjValAs? (Array Json) "branches" then
        if (step.getObjVal? "goal_after").isOk then
          throwError "strategy must not record goal_after"
        let ruleId ← ofExcept (step.getObjValAs? String "_ruleId")
        if ["Test.RecordingAPIRules.apiClaim", "Test.RecordingAPIRules.apiBranchCapture",
            "ProofScript.Script.Basic.claim"].contains ruleId then
          let hypothesis ← ofExcept (step.getObjVal? "h")
          if hypothesis == Json.null then
            throwError "strategy after capture lost its branch or continuation context"
        for branch in branches do
          let proof ← ofExcept (branch.getObjValAs? (Array Json) "proof")
          remaining := proof.toList ++ remaining
      else
        unless (step.getObjVal? "goal_after").isOk do
          throwError "ordinary step lost its goal_after snapshot"
  let nested := (← readProof `recordingAPINested).filter fun step =>
    (step.getObjValAs? String "_ruleId").toOption == some "Test.RecordingAPIRules.apiNested"
  unless nested.size == 2 &&
      (nested[0]!.getObjValAs? String "label").toOption == some "outer" &&
      (nested[1]!.getObjValAs? String "label").toOption == some "inner" do
    throwError "nested recorder scopes wrote to the wrong destinations"
  let recovered := (← readProof `recordingAPIRecovery).filter fun step =>
    (step.getObjValAs? String "_ruleId").toOption == some "Test.RecordingAPIRules.apiRecovery"
  unless recovered.size == 1 &&
      (recovered[0]!.getObjValAs? String "label").toOption == some "retained" do
    throwError "failed recorder scope left a discarded recording"
  let metadata ← readProof `recordingAPIMetadataOnly
  unless metadata.size == 1 &&
      (metadata[0]!.getObjValAs? String "goal").toOption == some "ordinary metadata" &&
      !(metadata[0]!.getObjVal? "goal_before").isOk &&
      !(metadata[0]!.getObjVal? "goal_after").isOk do
    throwError "metadata-only recorder gained implicit goal snapshots"
  let recordedRefs ← getTheoremRefs
  unless recordedRefs.contains ``apiKeptReference &&
      !recordedRefs.contains ``apiDiscardedReference &&
      !recordedRefs.contains ``apiSuppressedReference do
    throwError "recorder rollback or reference suppression lost its citation policy"

/--
error: strategy branch `right` has no matching goal; use a full goal tag or `·`
-/
#guard_msgs in
@theorem recordingAPISuffixBranches : True ∧ True := script
  api_tagged
  | right => trivial
  | left => trivial

/--
error: strategy branch `scope` has no matching goal; use a full goal tag or `·`
-/
#guard_msgs in
@theorem recordingAPIPrefixBranches : True ∧ True := script
  api_tagged
  | scope => trivial
  | other => trivial

/--
error: strategy branch `proof` has no matching goal; use a full goal tag or `·`
-/
#guard_msgs in
@theorem recordingAPIAmbiguous : True ∧ True := script
  api_ambiguous
  | proof => trivial

/--
error: invalid or duplicate goal-derived strategy branch label `proof`; strategy goals must have distinct non-reserved final tag components
-/
#guard_msgs in
@theorem recordingAPIDuplicateCanonicalNames : True ∧ True := script
  api_ambiguous
  | left.proof => trivial
  | right.proof => trivial

@references
page_end
