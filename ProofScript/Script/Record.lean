import ProofScript.Utils.Sundry
import ProofScript.Script.ExprJSON
import ProofScript.Core.References
import ProofScript.Script.Recording

open Lean Meta Elab Tactic


namespace ProofScript

/-- Record one object per invocation, with goal snapshots and before/after captures. -/
def recordStep (before : Array Recording.ParamCapture := #[])
    (after : Array Recording.ParamCapture := #[])
    (execute : TacticM Unit := executeRecordedStep) : TacticM Unit := do
  let before := #[Recording.goalParam "goal_before"] ++ before
  let after := #[Recording.goalParam "goal_after"] ++ after
  Recording.validateCaptures (before ++ after)
  withMainContext <| Recording.withRecordingStep fun step => do
    step.capturePlan before
    execute
    step.capturePlan after

/-- Default strategy scheduling; branch proofs finish through the script lifecycle. -/
def recordStrategy (nodes : List String)
    (before : Array Recording.ParamCapture := #[]) (after : Array Recording.ParamCapture := #[])
    (continuationIndex : Option Nat := none) : TacticM Unit := do
  let before := #[Recording.goalParam "goal_before"] ++ before
  let after := #[Recording.goalParam "goal_after"] ++ after
  Recording.validateCaptures (before ++ after)
  withMainContext <| Recording.withRecordingStep fun step => do
    step.capturePlan before
    executeRecordedStep
    let contexts ← Recording.resolveStrategyContexts nodes continuationIndex
    step.capturePlan after contexts.goal
    step.prepareBranches contexts

end ProofScript
