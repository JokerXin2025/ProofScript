import ProofScript.Script.Recording.Parameter

open Lean Elab Tactic


namespace ProofScript

/-- Capture explicitly selected locations; `at *` is a single marker. -/
def captureLocation (value : Option Syntax) : TacticM (Array RecordedValue) :=
  withoutModifyingState' <| Term.withoutErrToSorry <| withoutRecover do
    let some raw := value | return #[]
    let value : TSyntax `location := ⟨raw⟩
    match expandLocation value.raw with
    | .wildcard => return #[.plain (toJson "all")]
    | .targets hypotheses target =>
        let expressions ← hypotheses.mapM expression
        return if target then expressions.push (.plain (toJson "target")) else expressions
