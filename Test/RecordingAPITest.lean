import Test.RecordingAPIRules

project_info "Test.RecordingAPITest" { title := "RecordingAPITest" }

open Lean Elab Tactic ProofScript ProofScript.Recording

set_option linter.unusedVariables false

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

@theorem recordingAPISuffixBranches : True ∧ True := script
  api_tagged
  | right => trivial
  | left => trivial

@theorem recordingAPIPrefixBranches : True ∧ True := script
  api_tagged
  | scope => trivial
  | other => trivial

/--
error: ambiguous strategy branch `proof`; use a full goal tag
-/
#guard_msgs in
@theorem recordingAPIAmbiguous : True ∧ True := script
  api_ambiguous
  | proof => trivial

@references
page_end
