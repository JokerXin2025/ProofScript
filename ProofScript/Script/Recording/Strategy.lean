import ProofScript.Script.Recording.Runtime

namespace ProofScript.Recording

open Lean Elab Tactic

/-- A resolved proof branch with its canonical, goal-derived output name. -/
structure StrategyBranch where
  name : String
  goal : MVarId

/-- Goals produced by strategy execution, before its branch proofs run. -/
structure StrategyContexts where
  branches : List StrategyBranch
  main : Option MVarId := none
  continuation : Option MVarId := none
  private proofGoals : List MVarId := []

/-- Resolve only a full goal tag; abbreviated prefixes and suffixes are not selectors. -/
def resolveStrategyGoal (goals : List MVarId) (label : String) :
    TacticM (Option MVarId) := do
  let name := label.toName
  let candidates ← goals.filterM fun goal =>
    return name == (← goal.getTag).eraseMacroScopes
  match candidates with
  | [] => return none
  | [goal] => return some goal
  | _ => throwError "ambiguous strategy branch `{label}`; multiple goals have this full tag"

/-- Resolve script labels in the same remaining-goal order used by Lean's focus tactic. -/
def resolveStrategyContexts (nodes : List String) (continuationIndex : Option Nat := none) :
    TacticM StrategyContexts := do
  let goals ← getGoals
  let proofGoals := continuationIndex.map goals.take |>.getD goals
  let mut remaining ← proofGoals.filterM fun goal => return !(← goal.isAssigned)
  let mut branches : List StrategyBranch := []
  for node in nodes do
    let goal ←
      if node.isEmpty then
        match remaining with
        | goal :: _ => pure goal
        | [] => throwError "anonymous strategy branch has no remaining goal"
      else do
        let some goal ← resolveStrategyGoal remaining node
          | throwError "strategy branch `{node}` has no matching goal; use a full goal tag or `·`"
        pure goal
    remaining := remaining.erase goal
    let goalTag := (← goal.getTag).eraseMacroScopes
    let label := match goalTag with
      | .str _ last => last
      | _ => goalTag.toString
    if label.isEmpty || label == "anonymous" || branches.any (·.name == label) ||
        ["name", "info"].contains label then
      throwError "invalid or duplicate goal-derived strategy branch label `{label}`; strategy goals must have distinct non-reserved final tag components"
    branches := branches ++ [{ name := label, goal }]
  return {
    branches
    main := goals.head?
    proofGoals
    continuation := continuationIndex.bind fun index => goals[index]?
  }

/-- Select an actual goal for a direct capture or a strategy parameter capture. -/
def StrategyContexts.goal (contexts : StrategyContexts) : ContextSelector → TacticM (Option MVarId)
  | .main => pure contexts.main
  | .continuation => pure contexts.continuation
  | .branch label => do
    if let some branch := contexts.branches.find? (·.name == label) then
      return some branch.goal
    resolveStrategyGoal contexts.proofGoals label

/-- Route subsequent script proofs to child recordings and reserve stable completion data. -/
def RecordingStep.prepareBranches (step : RecordingStep) (contexts : StrategyContexts) : TacticM Unit :=
  step.prepareBranchLabels (contexts.branches.map (·.name))

/-- Internal script completion, after branch routing returns to the parent destination. -/
def finishRecordingStrategy : TacticM Unit := withRollback do
  let pending ← takeRecordingStrategy
  let mut branches := #[]
  for index in [:pending.labels.length] do
    let label := pending.labels[index]!
    let (proof, bindings) ← takeBoxWithContracts (pending.childPrefix ++ "_" ++ label)
    attachRecordingSlotContracts pending.slot <| bindings.map fun binding =>
      { binding with path := #[.key "branches", .index index, .key "proof"] ++ binding.path }
    branches := branches.push <| .object [
      ("name", .plain (toJson label)), ("proof", .array proof)]
  mergeRecordingSlotFields pending.slot [("branches", .array branches)]

end ProofScript.Recording
