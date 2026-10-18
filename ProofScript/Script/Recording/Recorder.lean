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
    TacticM RecordedValue := do
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

/-- Execute this invocation's selected original tactic. Recording blocks never execute it implicitly. -/
def execute [RecorderContext] : TacticM Unit := executeRecordedStep

/-- A recorder is ordinary term/do code; its primitives require the block's lexical context. -/
syntax (name := recordingStep) "recording_step " "do " doSeq : term
syntax (name := recordingStrategy) "recording_strategy " term:max " do " doSeq : term
syntax (name := recordingStrategyContinuation)
  "recording_strategy " term:max " (" &"continuation" " := " term ")" " do " doSeq : term

syntax (name := captureParamsStatement) "capture_params " term : doElem
syntax (name := recordValueStatement) "record_value " term:arg term:arg : doElem
syntax (name := executeRecordedStatement) "execute_recorded" : doElem

macro_rules
  | `(recording_step do $body:doSeq) =>
    `(withStepRecorder fun context => do
      letI : RecorderContext := context
      do $body:doSeq)
  | `(recording_strategy $nodes (continuation := $continuation) do $body:doSeq) =>
    `(withStrategyRecorder { nodes := $nodes, continuationIndex := $continuation } fun context => do
      letI : RecorderContext := context
      do $body:doSeq)
  | `(recording_strategy $nodes do $body:doSeq) =>
    `(withStrategyRecorder { nodes := $nodes } fun context => do
      letI : RecorderContext := context
      do $body:doSeq)
  | `(doElem| capture_params $parameters) =>
    `(doElem| captureParams $parameters)
  | `(doElem| record_value $field $value) =>
    `(doElem| recordValue $field $value)
  | `(doElem| execute_recorded) =>
    `(doElem| execute)

end ProofScript.Recording
