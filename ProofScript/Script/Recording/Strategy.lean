import ProofScript.Script.Recording.Runtime

namespace ProofScript.Recording

open Lean Elab Tactic

/-- An ordered, resolved proof branch. -/
structure StrategyBranch where
  name : String
  goal : MVarId

/-- Goals produced by strategy execution, before its branch proofs run. -/
structure StrategyContexts where
  branches : List StrategyBranch
  main : Option MVarId := none
  continuation : Option MVarId := none
  private proofGoals : List MVarId := []

/-- Follow Lean's exact/suffix/prefix precedence and reject ties at each level. -/
private def resolveStrategyGoal (goals : List MVarId) (label : String) :
    TacticM (Option MVarId) := do
  let name := label.toName
  for matchTag in [(name == ·), (name.isSuffixOf ·), (name.isPrefixOf ·)] do
    let candidates ← goals.filterM fun goal =>
      return matchTag (← goal.getTag).eraseMacroScopes
    match candidates with
    | [] => pure ()
    | [goal] => return some goal
    | _ => throwError "ambiguous strategy branch `{label}`; use a full goal tag"
  return none

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
          | throwError "strategy branch `{node}` has no matching goal"
        pure goal
    remaining := remaining.erase goal
    let goalTag := (← goal.getTag).eraseMacroScopes
    let label := if !node.isEmpty then node else
      match goalTag with
      | .str _ last => last
      | _ => goalTag.toString
    if label.isEmpty || label == "anonymous" || branches.any (·.name == label) ||
        ["name", "info"].contains label then
      throwError "ambiguous strategy branch label `{label}`; use distinct explicit `| case =>` branches"
    branches := branches ++ [{ name := label, goal }]
  return {
    branches
    main := goals.head?
    proofGoals
    continuation := continuationIndex.bind fun index => goals[index]?
  }

/-- Select an actual goal for a direct capture or a plan's context callback. -/
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
      { binding with path := #[.field "branches", .index index, .field "proof"] ++ binding.path }
    branches := branches.push <| json% { name: $label, proof: $proof }
  mergeRecordingSlotFields pending.slot [("branches", Json.arr branches)]

end ProofScript.Recording
