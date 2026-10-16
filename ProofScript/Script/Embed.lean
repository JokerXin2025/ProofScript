import ProofScript.Script.Script
import ProofScript.Script.ScriptDB
import ProofScript.Info.Commands

open Lean
open Lean.Elab.Tactic (evalTactic)
open Lean.Parser.Tactic (tacticSeq)

namespace ProofScript

/-! # 此模块暂时停用 仅在语法和API大规模迁移时修改即可 不用单独测试其功能 -/

/-! ## `embed`：嵌入定理证明

`embed <term> as <ident>` 把 `<term>`（一个**定理应用**，如 `dvd_trans h_ab h_bc`）的结论
作为局部假设引入上下文，等价于 `have <ident> := <term>`。`<term>` 必须是 `const` 头的应用。

录制版 `_embed` 在应用 `@theorem` 声明的 script 定理时，重放已保存的 script。
调用方实参通过 `args` 和 `argKinds`
（每项 `"data"`/`"proof"`）记录，供消费端按 proof/data 分类代入。若目标不是 script 定理，
则保留其完整表达式引用。
-/

/-! ### 本体（非录制）：校验是定理应用，然后 `have h := term` -/

script_elab embed
"embed" proof:term "as" h:ident => do
  let e ← Lean.Elab.Tactic.withMainContext <| Lean.Elab.Tactic.elabTerm proof none
  let e ← Lean.instantiateMVars e
  unless e.getAppFn.isConst do
    throwError "embed: 参数必须是定理应用（如 `dvd_trans h_ab h_bc`）"
  evalTactic (← `(tactic| have $h:ident := $proof:term))

/-! ### 录制版 `_embed` -/

/-- 判断一个类型 `t` 是否为命题（`isProp`）。用于把 binder `(n : t)` 分类为 proof（`t` 是命题）
    还是 data（`t` 非命题）；对实参则传它的 `inferType`。`isProp` 失败（隐式参数未解出的 mvar）
    时按 data 处理，避免误判。 -/
private def isProofBinderType (t : Expr) : MetaM Bool :=
  try
    Lean.Meta.isProp t
  catch _ => pure false

private partial def mkReplayGoalAux (fullType : Expr) : MetaM Expr := do
  match fullType with
  | .forallE n t b bi =>
      Lean.Meta.withLocalDecl n bi t fun x =>
        mkReplayGoalAux (b.instantiate1 x)
  | _ => Lean.Meta.mkFreshExprMVar fullType

private def mkReplayGoal (fullType : Expr) : MetaM Expr :=
  mkReplayGoalAux fullType

script_recorder embed
"embed" proof:term "as" h:ident => do
  let ruleId ← getRecordingRule
  let tag ← currentRecordingTag
  let boxName := tag
  -- ① 目标快照与其他字段一起写入单个步骤对象。
  let goalJson ← Lean.Elab.Tactic.withMainContext <| Expr2JSON (← GetGoal) { withTypes := true }
  -- ② elaborate 定理应用 → 头常量、结论类型、参数
  let e ← Lean.Elab.Tactic.withMainContext <| Lean.Elab.Tactic.elabTerm proof none
  let e ← Lean.instantiateMVars e
  let fnExpr := e.getAppFn
  let some (c, _) := fnExpr.const?
    | throwError "embed: 参数必须是定理应用（如 `dvd_trans h_ab h_bc`）"
  let conclType ← Lean.Elab.Tactic.withMainContext <| Lean.Meta.inferType e
  let typeJson ← Lean.Elab.Tactic.withMainContext <| Expr2JSON conclType
  let argsJson ← Json.arr <$> (e.getAppArgs.mapM fun a =>
    Lean.Elab.Tactic.withMainContext <| Expr2JSON a)
  let argKindsJson ← Json.arr <$> (e.getAppArgs.mapM fun a => do
    Lean.Elab.Tactic.withMainContext <| do
      let isProof ← try
        isProofBinderType (← Lean.Meta.inferType a)
      catch _ => pure false
      pure (Json.str (if isProof then "proof" else "data")))
  -- ③ Replay the persisted script in a child recording box.
  let (proofJson, bindings) ← match findScript (← getEnv) c with
    | some data => do
        let (_, stmts) := scriptDataParts data
        let recTactics ← collectRecordTactics stmts
        let seq' : TSyntax ``tacticSeq := ⟨buildTacticSeq recTactics⟩
        let fullType ← Lean.Elab.Tactic.withMainContext <| Lean.Meta.inferType fnExpr
        let subGoal ← Lean.Elab.Tactic.withMainContext <| mkReplayGoal fullType
        let subTag := tag ++ "_embed_" ++ h.getId.toString
        ensureBox subTag
        pushRecordingTag subTag
        let subGoals ← try
            Lean.Elab.Tactic.evalTacticAt seq' subGoal.mvarId!
          finally
            popRecordingTag
        unless subGoals.isEmpty do
          throwError "embed: 被嵌入定理的证明未闭合（剩余目标）"
        let subName := subTag
        let (proofArr, bindings) ← takeBoxWithContracts subName
        pure (Json.arr proofArr, bindings.map fun binding =>
          { binding with path := #[.field "proof"] ++ binding.path })
    | none => do
        let expression ← Lean.Elab.Tactic.withMainContext <| Expr2JSON e
        pure (expression, #[])
  -- ④ 引入 h
  evalTactic (← `(tactic| have $h:ident := $proof:term))
  let hValue ← Recording.isolatedCapture (Recording.expression h.raw)
  let hJson ← Recording.commitValue hValue
  let afterGoal ← Recording.isolatedCapture (Recording.goalSnapshot)
  let afterGoalJson ← Recording.commitValue afterGoal
  -- ⑤ 参数记录器 → 主 box
  let step := json% {
    _ruleId: $ruleId,
    goal_before: $goalJson,
    goal_after: $afterGoalJson,
    h: $hJson,
    type: $typeJson,
    "theorem": $(c.toString),
    args: $argsJson,
    argKinds: $argKindsJson,
    proof: $proofJson
  }
  appendBoxItem boxName step bindings

script_info embed { renderer := embed }

end ProofScript
