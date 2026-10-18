import Test.RecordingComplexRules
import Test.TacticRewriteTest

project_info "Test.RecordingRegistrationTest" { title := "RecordingRegistrationTest" }

open Lean Elab Command ProofScript ProofScript.Recording

set_option linter.unusedVariables false

-- Handwritten recorders must match the parser signature of their script declaration.
script_elab compoundParser "signature_compound" value:(ident term) => pure ()

/--
error: [script recorder] parameters of `Test.RecordingRegistrationTest.compoundParser` do not match its registration
-/
#guard_msgs in
script_recorder compoundParser "signature_compound" value:(ident str) => recording_step do
  capture_params #[goalParam "goal_before"]
  execute_recorded
  capture_params #[goalParam "goal_after"]

-- The same parser at a different source position must still match.
script_recorder compoundParser "signature_compound" value:(ident term) => recording_step do
  capture_params #[goalParam "goal_before"]
  execute_recorded
  capture_params #[goalParam "goal_after"]

-- Equal semantic shapes are insufficient when quotation binders require different extraction.
script_elab separatedParser "signature_separated" values:sepBy(ident, ",") => pure ()

/--
error: [script recorder] parameters of `Test.RecordingRegistrationTest.separatedParser` do not match its registration
-/
#guard_msgs in
script_recorder separatedParser "signature_separated" values:ident* => recording_step do
  capture_params #[goalParam "goal_before"]
  execute_recorded
  capture_params #[goalParam "goal_after"]

script_recorder separatedParser "signature_separated" values:sepBy(ident, ",") => recording_step do
  capture_params #[goalParam "goal_before"]
  execute_recorded
  capture_params #[goalParam "goal_after"]

script_elab scalarParser "signature_scalar" value:str => pure ()

/--
error: [script recorder] parameters of `Test.RecordingRegistrationTest.scalarParser` do not match its registration
-/
#guard_msgs in
script_recorder scalarParser "signature_scalar" value:num => recording_step do
  capture_params #[goalParam "goal_before"]
  execute_recorded
  capture_params #[goalParam "goal_after"]

@theorem recordingRegistrationImported (P : Prop) (h : P) : P := script
  record_labels [alpha]
  recorded_identity h

-- A structurally unsupported parameter can still use its handwritten recorder.
@theorem recordingRegistrationCompound : True := script
  signature_compound label True.intro
  signature_separated first, second
  trivial
