import ProofScript

open ProofScript

declare_syntax_cat unsupportedRecordingCategory
syntax ident : unsupportedRecordingCategory

script_macro unsupportedAuto "unsupported_auto_recording" loc:(unsupportedRecordingCategory)? =>
  `(tactic| trivial)

-- Unsupported automatic parameters do not prevent ordinary execution.
example : True := script
  unsupported_auto_recording

/--
error: [script recorder] 'unsupported_auto_recording': 参数 'loc' 缺少 RecordParam 实例；请提供类别实例或定义 script_recorder
-/
#guard_msgs in
@theorem unsupportedRecorded : True := script
  unsupported_auto_recording

-- A handwritten recorder overrides the unavailable automatic recorder.
script_recorder unsupportedAuto "unsupported_auto_recording" loc:(unsupportedRecordingCategory)? => do
  recordStep

@theorem handwrittenRecorded : True := script
  unsupported_auto_recording

/--
error: [script recorder] `Test.RecorderSelectionTest.unsupportedAuto` already has a handwritten recorder
-/
#guard_msgs in
script_recorder unsupportedAuto "unsupported_auto_recording" loc:(unsupportedRecordingCategory)? => do
  recordStep
