import ProofScript.Utils
import ProofScript.Script.ExprJSON
import ProofScript.Core.References
import ProofScript.Script.Recording

open Lean Meta Elab Tactic


namespace ProofScript

/-- The selected parser candidate is scoped to this tactic invocation, including
    nested `evalTactic` calls. No recording identity survives elaboration rollback. -/
private def recordingRuleOption : Name := `proofScript.recordingRule
private def recordingExecutionOption : Name := `proofScript.recordingExecution

def withRecordingRule (ruleId : Name) (execution : Syntax) (action : TacticM α) : TacticM α := do
  withOptions (·.set recordingRuleOption ruleId |>.set recordingExecutionOption execution) action

def getRecordingRule : TacticM Name := do
  match (← getOptions).get? recordingRuleOption with
  | some ruleId => return ruleId
  | _ => throwError "recording tactic must be invoked through run_recorded_step"

/-- Execute the selected registration using the original call's arguments. -/
def executeRecordedStep : TacticM Unit := do
  let some execution := (← getOptions).get? recordingExecutionOption
  | throwError "recording tactic must be invoked through run_recorded_step"
  withOptions (·.setBool `proofScript.scriptMode.active true) <|
    evalTactic execution

def recordRefsFromExpr (expr : Expr) : TacticM Unit := do
  unless ← referencesEnabled do return
  for constant in Expr.getUsedConstants expr do
    addTheoremRef constant

/-- 构建参数记录器的 JSON 对象。所有参数字段直接放在顶层。 -/
def paramsRecJson (extraFields : List (String × Json)) (ruleId : Name) :=
  Json.mkObj <| [("_ruleId", Json.str ruleId.toString)] ++ extraFields

private def recordGoal (boxName : String) : TacticM Unit := do
  let goalJson ← Expr2JSON (← GetGoal) { withTypes := true }
  appendBoxItem boxName (Json.mkObj [("_goal_", goalJson)])

/-- 初始化步骤参数记录，将规则 ID 和内联字段写入指定 box。 -/
private def recordInlineFields (boxName : String) (ruleId : Name)
    (inlineFields : List (String × Json)) : TacticM Unit :=
  appendBoxItem boxName (paramsRecJson inlineFields ruleId)

/-- Record one invocation using a plan. Headers, execution and captures share a rollback boundary. -/
def recordStep  (inlineFields : List (String × Json))
                (parameters : Recording.RecordingPlan := {})
                (execute : TacticM Unit := executeRecordedStep)
                : TacticM Unit := Recording.withRollback <| withMainContext do
  if let .error message := parameters.validate (inlineFields.map (·.1)) then
    throwError "{message}"
  let tag ← currentRecordingTag
  recordGoal tag
  recordInlineFields tag (← getRecordingRule) inlineFields
  Recording.runPlan parameters execute fun fields =>
    for (name, value) in fields do
      mergeBoxLast tag (Json.mkObj [(name, value)])

/-- Use Lean's exact/suffix/prefix tag precedence, but reject multiple matches at
    the same precedence instead of silently choosing the first goal. -/
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

def recordStrategy  (stepName : String) (nodes : List String)
                    (inlineFields : List (String × Json))
                    (parameters : Recording.RecordingPlan := {})
                    (continuationIndex : Option Nat := none)
                    : TacticM Unit := Recording.withRollback <| withMainContext do
  if let .error message := parameters.validate (inlineFields.map (·.1)) then
    throwError "{message}"
  let tag ← currentRecordingTag
  recordGoal tag
  appendBoxItem tag <| Json.mkObj [("_pending_strategy_", Json.str stepName)]
  mergeBoxLast tag (paramsRecJson inlineFields (← getRecordingRule))
  let beforeContext : Recording.ContextSelector → TacticM (Option MVarId)
    | .main => return (← getGoals).head?
    | _ => return none
  mergeBoxLast tag (Json.mkObj (← Recording.captureFields parameters true beforeContext))
  executeRecordedStep
  -- Resolve bullets against the same remaining-goal order used by Lean's focus tactic.
  -- Named branches may consume a later goal before a subsequent bullet is reached.
  let goals ← getGoals
  -- When declared, the continuation follows the strategy's proof goals.
  let branchGoals := continuationIndex.map goals.take |>.getD goals
  let mut remaining ← branchGoals.filterM fun goal => return !(← goal.isAssigned)
  let mut resolved : List String := []
  let mut resolvedGoals : List (String × MVarId) := []
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
    if label.isEmpty || label == "anonymous" || resolved.contains label ||
        ["name", "info"].contains label then
      throwError "ambiguous strategy branch label `{label}`; use distinct explicit `| case =>` branches"
    resolved := resolved ++ [label]
    resolvedGoals := resolvedGoals ++ [(label, goal)]
  let selectGoal : Recording.ContextSelector → TacticM (Option MVarId)
    | .main => pure goals.head?
    | .continuation => pure (continuationIndex.bind fun index => goals[index]?)
    | .branch label => do
      if let some goal := resolvedGoals.lookup label then return some goal
      resolveStrategyGoal branchGoals label
  mergeBoxLast tag (Json.mkObj (← Recording.captureFields parameters false selectGoal))
  pushResolvedBranches resolved
  startStrategy tag resolved

end ProofScript
