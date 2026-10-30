import ProofScript.Script.Recording.Runtime
import ProofScript.Utils.Tactic

namespace ProofScript

open Lean Elab Tactic

/-- A resolved proof branch with its canonical output name. Names come from the
    full goal tag when usable, otherwise from a per-invocation synthetic ID. -/
structure StrategyBranch where
  name : Name
  goal : MVarId

/-- Goals produced by strategy execution, before its branch proofs run. -/
structure StrategyContexts where
  branches : List StrategyBranch
  main : Option MVarId := none
  continuation : Option MVarId := none
  private proofGoals : List MVarId := []

/-- Resolve script labels in the same remaining-goal order used by Lean's focus tactic.
    A continuation is a named goal role. It is removed from the anonymous branch
    pool, while explicit branch labels may still resolve any visible goal. -/
def resolveStrategyContexts (nodes : List (Option Name)) (continuation : Option Name := none) :
    TacticM StrategyContexts := do
  let goals ← getGoals
  let continuation ← match continuation with
    | none => pure none
    | some name =>
        let some goal ← resolveGoal? goals name
          | throwError "strategy continuation `{name}` has no matching goal"
        pure (some goal)
  let proofGoals := goals.filter fun goal => continuation != some goal
  let mut remaining ← proofGoals.filterM fun goal => return !(← goal.isAssigned)
  let mut branches : List StrategyBranch := []
  for node in nodes do
    let goal ←
      if node.isNone then
        match remaining with
        | goal :: _ => pure goal
        | [] => throwError "anonymous strategy branch has no remaining goal"
      else match node with
        | none => unreachable!
        | some label => do
        let some goal ← resolveGoal? remaining label
          | throwError "strategy branch `{label}` has no matching goal; use a full goal tag or `·`"
        pure goal
    remaining := remaining.erase goal
    let tag := (← goal.getTag).eraseMacroScopes
    let usableTag := !tag.isAnonymous && tag != `anonymous &&
      ![`name, `info].contains tag
    let label ← if usableTag && !branches.any (·.name == tag) then
      pure tag
    else do
      let mut index := branches.length
      let mut candidate := Name.mkSimple s!"__strategy_branch_{index}"
      while branches.any (·.name == candidate) do
        index := index + 1
        candidate := Name.mkSimple s!"__strategy_branch_{index}"
      pure candidate
    branches := branches ++ [{ name := label, goal }]
  return {
    branches
    main := goals.head?
    proofGoals
    continuation
  }

/-- Select an actual goal for a direct record or a strategy parameter record. -/
def StrategyContexts.goal (contexts : StrategyContexts) (target : Option Name) :
    TacticM (Option MVarId) := do
  match target with
  | none => pure contexts.main
  | some target => resolveGoal? (contexts.proofGoals ++ contexts.continuation.toList) target

/-- Route subsequent script proofs to child recordings and reserve stable completion data. -/
def RecordingStep.prepareBranches (step : RecordingStep) (contexts : StrategyContexts) : TacticM Unit :=
  step.prepareBranchTargets (contexts.branches.map fun branch =>
    { label := branch.name, goal := branch.goal })

/-- Prepare the route after the body returns, even when that body returns early. -/
def withPreparedStrategyBranches (step : RecordingStep) (body : TacticM α)
    (contexts : TacticM StrategyContexts) : TacticM α := do
  let result ← body
  step.prepareBranches (← contexts)
  return result

/-- Select the route entry for the goal currently focused by Lean. The route
    stores MVarIds, so anonymous bullets and named cases share one identity. -/
def selectCurrentStrategyBranch : TacticM Unit := do
  let goals ← getGoals
  let mut selected : Option (String × Name) := none
  for goal in goals do
    if selected.isNone then
      selected := ← strategyBranchForGoal goal
  let some (_, label) := selected
    | throwError "current goal is not a branch of the active recording strategy"
  activateStrategyBranch label

/-- Advance routing after a branch body. Select the next visible branch by its
    actual metavariable, or finish the route when only continuation goals remain. -/
def advanceCurrentStrategyCase : TacticM Unit := do
  let goals ← getGoals
  let mut next : Option (String × Name) := none
  for goal in goals do
    if next.isNone then
      next := ← strategyBranchForGoal goal
  advanceStrategyCase next

/-- Internal script completion, after branch routing returns to the parent destination. -/
def finishRecordingStrategy : TacticM Unit := withRollback do
  let pending ← takeRecordingStrategy
  let mut branches := #[]
  let mut branchBindings : Array (Array StepBinding) := #[]
  for index in [:pending.labels.length] do
    let label := pending.labels[index]!
    let (proof, bindings) ← takeBoxWithContracts (pending.childPrefix ++ "_" ++ label.toString)
    branches := branches.push <| .object [
      ("name", .plain (toJson label.toString)), ("proof", .array proof)]
    branchBindings := branchBindings.push bindings
  mergeRecordingSlotFields pending.slot [("$branches", .array branches)]
  for index in [:pending.labels.length] do
    attachRecordingSlotContracts pending.slot <| branchBindings[index]!.map fun binding =>
      { binding with path := #[.key "$branches", .index index, .key "proof"] ++ binding.path }

end ProofScript
