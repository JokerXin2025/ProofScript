import ProofScript.Script.Recording.Strategy
import ProofScript.Script.Recording.Conversion

/-!
Recorder blocks provide a lexical scope for ordinary `TacticM` code:

```lean
recording_step do
  capture_params #[goalParam "goal_before"]
  record_value "label" "example"
  execute_recorded
  capture_params #[goalParam "goal_after"]
```

`recording_strategy nodes (continuation := some 1) do ...` additionally prepares
branch recording destinations after its body succeeds. The continuation argument
is optional. Neither block adds snapshots or executes a tactic implicitly.

The statements are term/do syntax for recorder definitions, not native tactics.
Helpers taking `[RecorderContext]` use the scope at their call site; an action
constructed earlier retains the context it was constructed with.
-/

namespace ProofScript.Recording

open Lean Elab Tactic

/-- Strategy routing information, interpreted against the goals at capture or completion time. -/
structure StrategySpec where
  nodes : List String
  continuationIndex : Option Nat := none

/-- A lexical recorder scope. Primitives use a local instance supplied by a recording block.
    Reusable helpers should take `[RecorderContext]` at their call site. -/
class RecorderContext where
  step : RecordingStep
  strategy : Option StrategySpec := none

/-- Open one recording destination without adding snapshots or executing the tactic. -/
def withStepRecorder (body : RecorderContext → TacticM α) : TacticM α :=
  withMainContext <| withRecordingStep fun step => body { step }

/-- Prepare strategy branches after a successful body, before closing its recording destination.
    An early return from the body still prepares branches; an exception rolls back the block. -/
def withStrategyRecorder (spec : StrategySpec) (body : RecorderContext → TacticM α) :
    TacticM α :=
  withMainContext <| withRecordingStep fun step => do
    let result ← body { step, strategy := some spec }
    step.prepareBranches (← resolveStrategyContexts spec.nodes spec.continuationIndex)
    return result

private def captureInContext (context : RecorderContext) (parameter : ParamCapture) :
    CaptureM RecordedData := do
  if parameter.context == .main then
    return ← parameter.capture
  let some spec := context.strategy
    | throwError "recording context {repr parameter.context} has no goal"
  let contexts ← resolveStrategyContexts spec.nodes spec.continuationIndex
  let some goal ← contexts.goal parameter.context
    | throwError "recording context {repr parameter.context} has no goal"
  withCaptureGoal (some goal) parameter.capture

/-- Capture parameters now, resolving their selectors inside each parameter's failure boundary.
    The batch is atomic even when its caller catches an error. -/
def captureParams [context : RecorderContext] (parameters : Array ParamCapture) : TacticM Unit :=
  context.step.captureParameters parameters (captureInContext context)

/-- Record a typed value through isolated conversion and the normal reference-aware commit path. -/
def recordValue [context : RecorderContext] [ToRecordedValue α]
    (field : String) (value : α) (collectReferences : Bool := true) : TacticM Unit :=
  context.step.captureField field (ToRecordedValue.capture value) { collectReferences }

/-- Explicit display opt-in for typed values; ordinary `recordValue` stays unchanged. -/
def recordValueWithDisplay [context : RecorderContext] [ToRecordedValue α]
    (field : String) (value : α) (collectReferences : Bool := true)
    (source : Option Syntax := none) : TacticM Unit :=
  context.step.captureFieldWithDisplay field (ToRecordedValue.capture value)
    { collectReferences } source

/-- Commit a previously paired capture without querying its expired context. -/
def recordCapturedWithDisplay [context : RecorderContext] (field : String)
    (captured : RecordedValue) (collectReferences : Bool := true) : TacticM Unit :=
  context.step.recordCapturedWithDisplay field captured collectReferences

/-- Execute this invocation's selected original tactic. Recording blocks never execute it implicitly. -/
def execute [RecorderContext] : TacticM Unit := executeRecordedStep

macro "recording_step " "do " body:doSeq : term => `(term|
  withStepRecorder fun context => do
    letI : RecorderContext := context
    do $body:doSeq
)

macro "recording_strategy " nodes:term:max " do " body:doSeq : term => `(term|
  withStrategyRecorder { nodes := $nodes } fun context => do
    letI : RecorderContext := context
    do $body:doSeq
)

macro "recording_strategy " nodes:term:max " (" &"continuation" " := "
    continuation:term ")" " do " body:doSeq : term => `(term|
  withStrategyRecorder { nodes := $nodes, continuationIndex := $continuation }
    fun context => do
      letI : RecorderContext := context
      do $body:doSeq
)

macro "capture_params " parameters:term : doElem => `(doElem|
  captureParams $parameters
)

macro "record_value " field:term:arg value:term:arg : doElem => `(doElem|
  recordValue $field $value
)

macro "execute_recorded" : doElem => `(doElem| execute)

end ProofScript.Recording
