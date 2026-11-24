import ProofScript.Script.Recording.Strategy
import ProofScript.Script.Recording.Parameter
import ProofScript.Script.Recording.Params

open Lean Elab Tactic


/-!
Recorder blocks provide a lexical scope for ordinary `TacticM` code:

```lean
script_recorder myTactic => do
  record_goal "$goal_before"
  record_context "$context_before"
  record_param "h" h
  record_value "name" "my_tctic"
  execute
  record_goal "$goal_after"
  record_context "$context_after"
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

open scoped ValueRecorder

/-- Run a recorder's `do` block, restoring tactic state if it fails. -/
macro "with_rollback" " do" body:doSeq : doElem =>
  `(doElem| Lean.Elab.Tactic.withRollback do $body:doSeq)

private def recordValue {α : Type} [step : RecordingStep] [RecordValue α]
    (field : String) (value : α) (context : RecordContext := none)
    : TacticM Unit := withRollback do
  step.ensureOpen
  let recorded ← recordValueFromContext field value context
  step.recordValue field recorded

private def recordGoal (target : Option MVarId := none)
    : TacticM RecordedValue := do
  match target.or (← getGoals).head? with
  | none => return .plain (toJson "completed")
  | some goal => goal.withContext <| recordExpression (← goal.getType)

/-- Snapshot visible local names and types together, preserving their alignment. -/
private def recordContext (target : Option MVarId := none)
    : TacticM (Array String × Array RecordedValue) := do
  match target.or (← getGoals).head? with
  | none => return (#[], #[])
  | some goal => goal.withContext do
      let mut names := #[]
      let mut types := #[]
      let mut used : List String := []
      for decl in (← getLCtx) do
        if decl.isImplementationDetail then continue
        let base := decl.userName.toString
        let mut name := base
        let mut index := 1
        while used.contains name do
          name := s!"{base}_{index}"
          index := index + 1
        used := name :: used
        names := names.push name
        types := types.push (← recordExpression decl.type)
      return (names, types)

private def recordContextFields [step : RecordingStep] (field : String)
    (target : Option MVarId := none) : TacticM Unit := withRollback do
  step.ensureOpen
  let suffix ← match field with
    | "$context_before" => pure "before"
    | "$context_after" => pure "after"
    | _ => throwError "record_context expects `$context_before` or `$context_after`"
  let (names, types) ← recordContext target
  recordValue ("$context_names_" ++ suffix) names
  recordValue ("$context_types_" ++ suffix) types

private def executeRecorderPredecessor [RecorderPredecessor] : TacticM Unit :=
  RecorderPredecessor.run

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

/-- Record the main goal. No remaining goal is represented by `completed`. -/
macro "record_goal "
    field:term:arg
: doElem => `(doElem| (open scoped ProofScript.ValueRecorder in
  recordValue $field (← recordGoal)
))

/-- Record the visible local context of a named goal. -/
macro "record_context "
    field:term:arg
    atomic("(" &"goal" " := ") goal:term ")"
: doElem => `(doElem| recordContextFields $field (some (← resolveGoal! (← getGoals) $goal)))

/-- Record the main goal's context columns, or empty arrays when none remains. -/
macro "record_context "
    field:term:arg
: doElem => `(doElem| recordContextFields $field)

/-- Execute the predecessor implementation selected for the current recorder. -/
macro "execute" : doElem => `(doElem| executeRecorderPredecessor)

/-- Select the initial recorder (resolved when the enclosing recorder is declared). -/
macro "execute" &"init" : doElem => `(doElem| executeRecorderPredecessor)

/-- Select a previously labeled recorder (resolved when the enclosing recorder is declared). -/
macro "execute" "(" &"label" " := " _label:str ")" : doElem =>
  `(doElem| executeRecorderPredecessor)

end ProofScript
