import ProofScript.Script.Recording.Strategy
import ProofScript.Script.Recording.Parameter

open Lean Elab Tactic


/-!
Recorder blocks provide a lexical scope for ordinary `TacticM` code:

```lean
script_recorder myTactic => do
  record_goal "$goal_before"
  record_param "h" h
  record_value "name" "my_tctic"
  execute
  record_goal "$goal_after"
```

For a strategy registration, the same `script_recorder myTactic => do ...`
body automatically prepares branch recording destinations after it succeeds.
The continuation is obtained from the registered declaration.

The statements are term/do syntax for recorder definitions, not native tactics.
Helpers taking `[RecordingStep]` use the scope at their call site; an action
constructed earlier retains the context it was constructed with.

`script_recorder` uses the registration's `strategy` flag to insert the
appropriate recording block automatically for a plain `do` body.
-/

namespace ProofScript

private def recordValue {α : Type} [step : RecordingStep] [RecordValue α]
    (field : String) (value : α) (context : RecordContext := none)
    : TacticM Unit := withRollback do
  step.ensureOpen
  let recorded ← recordValueFromContext field value context
  step.recordValue field recorded

private def recordGoal (target : Option MVarId := none) : TacticM RecordedValue := do
  match target.or (← getGoals).head? with
  | none => return .plain .null
  | some goal => goal.withContext <| recordExpression (← goal.getType)

/-- Record the current value of a script parameter in a named goal. -/
macro "record_param "
    field:term:arg
    value:term:arg
    atomic("(" &"goal" " := ") goal:term ")"
: doElem => `(doElem| (open scoped ProofScript.ParamRecorder in
  recordValue $field $value (some (← resolveGoal! (← getGoals) $goal))
))

/-- Record the current value of a script parameter in the main context. -/
macro "record_param "
    field:term:arg
    value:term:arg
: doElem => `(doElem| (open scoped ProofScript.ParamRecorder in
  recordValue $field $value
))

/-- Record a static value. -/
macro "record_value "
    field:term:arg
    value:term:arg
: doElem => `(doElem| (open scoped ProofScript.ValueRecorder in
  recordValue $field $value
))

/-- Record a named goal. -/
macro "record_goal "
    field:term:arg
    atomic("(" &"goal" " := ") goal:term ")"
: doElem => `(doElem| (open scoped ProofScript.ValueRecorder in
  recordValue $field (← recordGoal (some (← resolveGoal! (← getGoals) $goal)))
))

/-- Record the main goal. No remaining goal is represented by `null`. -/
macro "record_goal "
    field:term:arg
: doElem => `(doElem| (open scoped ProofScript.ValueRecorder in
  recordValue $field (← recordGoal)
))

/-- Execute the predecessor implementation selected for the current recorder. -/
macro "execute" : doElem => `(doElem| executeRecorderPredecessor)

end ProofScript
