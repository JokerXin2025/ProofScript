import ProofScript.Script.Recording.Engine

open Lean Meta Elab Tactic

namespace ProofScript

/-- The selected parser candidate is scoped to this tactic invocation, including
    nested `evalTactic` calls. No recording identity survives elaboration rollback. -/
private def recordingRuleOption : Name := `proofScript.recordingRule
private def recordingExecutionOption : Name := `proofScript.recordingExecution

def withRecordingRule (ruleId : Name) (execution : Syntax) (action : TacticM α) : TacticM α := do
  withOptions (·.set recordingRuleOption ruleId |>.set recordingExecutionOption execution) action

/-- Pin the actual selected contract before the recorder runs; rollback includes all nested bindings. -/
def withRecordingRegistration (registration : ScriptTacticRegistration) (execution : Syntax)
    (action : TacticM α) : TacticM α := withRollback do
  let registration := if registration.recordingKind.isNone then
      { registration with
        ruleId := unrecordedRuleId
        recordedFields := some #[{ name := "name", schema := .string }] }
    else registration
  let previous ← selectedRecordingContract
  selectRecordingContract (some (.ofRegistration registration))
  try
    withRecordingRule registration.ruleId execution action
  finally
    selectRecordingContract previous

def getRecordingRule : TacticM Name := do
  match (← getOptions).get? recordingRuleOption with
  | some ruleId => return ruleId
  | _ => throwError "recording tactic must be invoked through run_recorded_step"

/-- Execute the selected registration using the original call's arguments. -/
def executeRecordedStep : TacticM Unit := do
  let some execution := (← getOptions).get? recordingExecutionOption
  | throwError "recording tactic must be invoked through run_recorded_step"
  withOptions (·.setBool `proofScript.scriptMode.active true) <|
    evalTactic execution

namespace Recording

/-- A scoped recording destination. Its storage position is deliberately private. -/
structure RecordingStep where
  private mk ::
  private slot : RecordingSlot

private def RecordingStep.ensureOpen (step : RecordingStep) : TacticM Unit := do
  unless ← recordingSlotIsOpen step.slot do
    throwError "recording step is closed"

private def RecordingStep.validateField (step : RecordingStep) (field : String) : TacticM Unit := do
  step.ensureOpen
  if let .error message := validateFieldName field then
    throwError "{message}"
  if ((← getRecordingSlotItem step.slot).getObjVal? field).isOk then
    throwError "duplicate recorded parameter field `{field}`"

/-- Manage one recording destination without implicitly executing a tactic. -/
def withRecordingStep (action : RecordingStep → TacticM α) : TacticM α := withRollback do
  let slot ← reserveRecordingSlot (← currentRecordingTag) (← mkFreshId) (← getRecordingRule)
  let step := RecordingStep.mk slot
  let result ← action step
  step.ensureOpen
  closeRecordingSlot slot
  return result

/-- Commit a value and its enabled references to this stable recording destination. -/
def RecordingStep.recordValue (step : RecordingStep) (field : String) (value : RecordedValue)
    (collectReferences : Bool := true) : TacticM Unit := withRollback do
  step.validateField field
  let json ← commitCapturedValue value collectReferences
  mergeRecordingSlotFields step.slot [(field, json)]

/-- Write ordinary JSON metadata using the same field checks and commit path. -/
def RecordingStep.recordJson (step : RecordingStep) (field : String) (value : Json) : TacticM Unit :=
  step.recordValue field (.scalar value)

private def RecordingStep.captureNamedField (step : RecordingStep) (field errorField : String)
    (capture : TacticM RecordedValue) (options : CaptureOptions) : TacticM Unit := withRollback do
  step.validateField field
  let value ← captureValue errorField (withCaptureGoal options.goal capture) options.onFailure
  step.recordValue field value options.collectReferences

/-- Isolate a capture and atomically commit its value to the named field. -/
def RecordingStep.captureField (step : RecordingStep) (field : String)
    (capture : TacticM RecordedValue) (options : CaptureOptions := {}) : TacticM Unit :=
  step.captureNamedField field field capture options

/-- Record a goal snapshot under an ordinary field name; a missing goal writes `null`. -/
def RecordingStep.recordGoal (step : RecordingStep) (field : String)
    (goal : Option MVarId := none) : TacticM Unit :=
  step.captureField field (goalSnapshot goal) { collectReferences := false }

/-- Capture a batch atomically, interpreting each parameter inside its isolated capture.
    Field checks remain outside the parameter's failure policy. -/
def RecordingStep.captureParameters (step : RecordingStep) (parameters : Array ParamCapture)
    (capture : ParamCapture → TacticM RecordedValue) : TacticM Unit := withRollback do
  step.ensureOpen
  for parameter in parameters do
    step.captureNamedField parameter.field parameter.name (capture parameter)
      { onFailure := parameter.onFailure, collectReferences := parameter.collectReferences }

/-- Internal bridge from resolved strategy contexts to branch routing. -/
def RecordingStep.prepareBranchLabels (step : RecordingStep) (labels : List String) : TacticM Unit :=
  withRollback do
    step.ensureOpen
    if labels.isEmpty then throwError "recording strategy must have at least one branch"
    let mut seen : List String := []
    for label in labels do
      if label.isEmpty || label == "anonymous" || seen.contains label || ["name", "info"].contains label then
        throwError "invalid or duplicate goal-derived strategy branch label `{label}`; strategy goals must have distinct non-reserved final tag components"
      seen := label :: seen
    let childPrefix := step.slot.box ++ "_strategy_" ++ step.slot.token.toString
    registerRecordingStrategy { slot := step.slot, childPrefix, labels }
    startStrategy childPrefix labels

end Recording
end ProofScript
