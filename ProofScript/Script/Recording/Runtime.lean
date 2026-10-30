import ProofScript.Script.Recording.RecordEngine
import ProofScript.Script.Recording.Parameter
import ProofScript.Script.JsonBox
import ProofScript.Utils.Tactic
import ProofScript.Utils.Syntax

open Lean Meta Elab Tactic

namespace ProofScript

register_option proofScript.recording.strategyNodes : String := {
  defValue := ""
  descr := "internal strategy branch information for generated script recorders"
}

/-- The branch labels attached to the current recorded strategy invocation.
    Generated recorder entries install this value before evaluating their body, so
    handwritten recorders do not need to expose the synthetic `_strategy_cases`
    parser argument. Empty labels are kept distinct from `Name.anonymous`: they
    represent an anonymous branch rather than a named goal. -/
def decodeRecordingStrategyNodes (encoded : String) : List (Option Name) :=
  (if encoded.isEmpty then [""] else encoded.splitOn "\n").map fun label =>
    if label.isEmpty then none else some label.toName

def recordingStrategyNodes : TacticM (List (Option Name)) := do
  let encoded := (← getOptions).get `proofScript.recording.strategyNodes ""
  pure (decodeRecordingStrategyNodes encoded)

/-- Scope the hidden branch information while evaluating a generated recorder body. -/
def withRecordingStrategyNodes (encoded : String)
    (action : TacticM α) : TacticM α :=
  withOptions (·.set `proofScript.recording.strategyNodes encoded) action

/-- The selected parser candidate is scoped to this tactic invocation, including
    nested `evalTactic` calls. No recording identity survives elaboration rollback. -/
private def recordingRuleOption : Name := `proofScript.recordingRule

/-- The predecessor captured when a recorder body is declared. -/
class RecorderPredecessor where
  run : TacticM Unit

/-- Reuse argument nodes without reparsing, preserving the original source positions. -/
def recorderPredecessorCall (call : Syntax) (sourceName targetName : String)
    (targetKind : Name) (isRecorder isStrategy : Bool) : TacticM Syntax := do
  let some tokenIdx := call.getArgs.findIdx? fun arg =>
      arg.isAtom && arg.getAtomVal == sourceName
    | throwError "cannot find recorder keyword `{sourceName}`"
  let args := call.getArgs.set! tokenIdx (mkAtomFrom call.getArgs[tokenIdx]! targetName)
  if !isRecorder && isStrategy && args.size < 2 then
    throwError "strategy recorder is missing its branch payload"
  let args := if !isRecorder && isStrategy then args.extract 0 (args.size - 2) else args
  return changeNodeKind call targetKind args

/-- Pin the actual selected contract before the recorder runs; rollback includes all nested bindings. -/
def withRecordingRule (ruleId : Name) (action : TacticM α) : TacticM α := withRollback do
  let some registration := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == ruleId)
    | throwError "unknown script recording rule `{ruleId}`"
  let fallback := registration.explicitRecordingKind.isNone && registration.automaticRecordingKind.isNone
  let contract := if fallback then { registration with ruleId := unrecordedRuleId } else registration
  let previous ← selectedRecordingContract
  selectRecordingContract (some (.ofRegistration contract))
  try
    withOptions (·.set recordingRuleOption contract.ruleId) do
      if fallback then
        logWarningAt (← getRef) m!"{registration.autoRecordingError.getD s!"script strategy `{ruleId}` has no recorder"}；未导出数据"
      action
  finally
    selectRecordingContract previous

def getRecordingRule : TacticM Name := do
  match (← getOptions).get? recordingRuleOption with
  | some ruleId => return ruleId
  | _ => throwError "recording tactic must be invoked through a script recorder"

/-- Return the declaration registration selected for this recorder invocation.
    The Environment remains the source of truth; the invocation contract only
    carries the routing identity needed while a recording is running. -/
def currentRecordingRegistration : TacticM (Option ScriptTacticRegistration) := do
  let ruleId ← getRecordingRule
  pure <| (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == ruleId)

def currentRecordingConfig : TacticM (Option ScriptRecordingConfig) := do
  match ← currentRecordingRegistration with
  | some registration => return some registration.config
  | none => return (← selectedRecordingContract).map fun contract =>
      { kind := contract.kind, continuation := contract.continuation }

/-- Execute the predecessor call bound by the generated recorder body. -/
def executeRecorderPredecessor [predecessor : RecorderPredecessor] : TacticM Unit :=
  predecessor.run


/-- A scoped recording destination. Its storage position is deliberately private. -/
class RecordingStep where
  private mk ::
  private slot : RecordingSlot

def RecordingStep.ensureOpen (step : RecordingStep) : TacticM Unit :=
  unless ← recordingSlotIsOpen step.slot do
    throwError "recording step is closed"

/-- Manage one recording destination without implicitly executing a tactic. -/
def withRecordingStep (action : RecordingStep → TacticM α) : TacticM α := withRollback do
  let slot ← reserveRecordingSlot (← currentRecordingTag) (← mkFreshId) (← getRecordingRule)
  let step := RecordingStep.mk slot
  let result ← action step
  step.ensureOpen
  closeRecordingSlot slot
  return result

/-- Commit a value without collecting references. -/
def RecordingStep.recordValue (step : RecordingStep) (field : String) (value : RecordedValue)
    : TacticM Unit := withRollback do
  step.ensureOpen
  mergeRecordingSlotFields step.slot [(field, value)]

/-- Internal bridge from resolved strategy contexts to branch routing. -/
def RecordingStep.prepareBranchTargets (step : RecordingStep)
    (branches : List RecordingStrategyBranch) : TacticM Unit :=
  withRollback do
    step.ensureOpen
    if branches.isEmpty then throwError "recording strategy must have at least one branch"
    let mut seen : List Name := []
    for branch in branches do
      let label := branch.label
      if label.isAnonymous || label == `anonymous || seen.contains label || [`name, `info].contains label then
        throwError "invalid or duplicate strategy branch label `{label}`; branches must have distinct non-reserved export labels"
      seen := label :: seen
    let childPrefix := step.slot.box ++ "_strategy_" ++ step.slot.token.toString
    registerRecordingStrategy { slot := step.slot, childPrefix, labels := branches.map (·.label) }
    for branch in branches do
       ensureBox (childPrefix ++ "_" ++ branch.label.toString)
    beginStrategyBranches childPrefix (branches.map fun branch =>
      { label := branch.label, goal := branch.goal })

end ProofScript
