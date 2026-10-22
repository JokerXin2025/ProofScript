import ProofScript.Script.Script
import ProofScript.Script.ScriptDB
import ProofScript.Script.Recording.Display
import ProofScript.Info.Commands

open Lean
open Lean.Elab.Tactic (evalTactic)
open Lean.Parser.Tactic (tacticSeq)

namespace ProofScript

/-! Embed captures explicit display companions while their local contexts exist.
    Replay children share their parent's proof graph and retain contract paths. -/

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

private def embedOutputFields : Array Recording.OutputField :=
  let subjects : Array Recording.OutputField := #[
    { name := "goal_before", schema := .optional .expression, nullable := false },
    { name := "goal_after", schema := .optional .expression, nullable := false },
    { name := "h", schema := .expression, nullable := false },
    { name := "type", schema := .expression, nullable := false },
    { name := "theorem", schema := .name, nullable := false },
    { name := "args", schema := .array .expression, nullable := false },
    { name := "argKinds", schema := .array (.union [.literal "data", .literal "proof"]), nullable := false },
    { name := "proof", schema := .union [.expression, .array .json], nullable := false }]
  subjects ++ #["goal_before", "goal_after", "h", "type", "args", "proof"].map fun name =>
    { name := name ++ "_display", schema := Recording.displaySchema name, nullable := true }

/-- Both fields are frozen together, then imported together. Auxiliary display
    expressions never contribute citations; the enclosing embed transaction also
    rolls this import back if elaboration, replay or final assembly fails. -/
private def captureEmbedField (field : String) (capture : Recording.CaptureM Recording.RecordedData)
    (source : Option Syntax := none) (collectReferences : Bool := true) :
    Lean.Elab.Tactic.TacticM (Recording.RecordedData × Recording.RecordedData) := do
  let captured ← Recording.CaptureM.run <| Recording.captureWithDisplay field capture source
  let .object capturedFields := captured.data
    | throwError "invalid embed display capture"
  let some subject := capturedFields.lookup "value"
    | throwError "embed display capture has no subject"
  if collectReferences && (← referencesEnabled) then
    for name in ({ captured with data := subject } : Recording.RecordedValue).references do
      addTheoremRef name
  let .object fields ← importRecordingValue captured
    | throwError "invalid imported embed display capture"
  let some value := fields.lookup "value"
    | throwError "imported embed display capture has no subject"
  let some display := fields.lookup "display"
    | throwError "imported embed display capture has no companion"
  return (value, display)

script_recorder embed (fields := embedOutputFields)
"embed" proof:term "as" h:ident => Lean.Elab.Tactic.withRollback do
  let ruleId ← getRecordingRule
  let tag ← currentRecordingTag
  let boxName := tag
  -- ① 目标快照与其他字段一起写入单个步骤对象。
  let (goalData, goalDisplay) ← captureEmbedField "goal_before" Recording.goalSnapshot
    (collectReferences := false)
  -- ② elaborate 定理应用 → 头常量、结论类型、参数
  let e ← Lean.Elab.Tactic.withMainContext <| Lean.Elab.Tactic.elabTerm proof none
  let e ← Lean.instantiateMVars e
  let fnExpr := e.getAppFn
  let some (c, _) := fnExpr.const?
    | throwError "embed: 参数必须是定理应用（如 `dvd_trans h_ab h_bc`）"
  let (typeData, typeDisplay) ← captureEmbedField "type" <|
    Recording.CaptureM.withMainContext do
      Recording.snapshotExpression (← Lean.Meta.inferType e)
  let (argsData, argsDisplay) ← captureEmbedField "args" <|
    Recording.CaptureM.withMainContext <| ToRecordedValue.capture e.getAppArgs
  let argKinds ← Recording.CaptureM.run <| Recording.CaptureM.withMainContext do
    let kinds ← e.getAppArgs.mapM fun a => do
      let isProof ← try
        isProofBinderType (← Lean.Meta.inferType a)
      catch _ => pure false
      pure (Json.str (if isProof then "proof" else "data"))
    return .plain (.arr kinds)
  let .plain argKindsJson := argKinds.data
    | throwError "invalid embed argument classification"
  -- ③ Replay the persisted script in a child recording box.
  let (proofData, proofDisplay, bindings) ← match findScript (← getEnv) c with
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
            -- Persisted syntax belongs to the embedded theorem's source file.
            -- Its replay must not create editor references in the caller's file.
            Elab.withEnableInfoTree false <|
              Lean.Elab.Tactic.evalTacticAt seq' subGoal.mvarId!
          finally
            popRecordingTag
        unless subGoals.isEmpty do
          throwError "embed: 被嵌入定理的证明未闭合（剩余目标）"
        let subName := subTag
        let (proofArr, bindings) ← takeBoxWithContracts subName
        pure (Recording.RecordedData.array proofArr, Recording.RecordedData.plain Json.null,
          bindings.map fun binding =>
          { binding with path := #[.key "proof"] ++ binding.path })
    | none => do
        let (value, display) ← captureEmbedField "proof"
          (Recording.CaptureM.withMainContext <| Recording.snapshotExpression e) (some proof.raw)
        pure (value, display, #[])
  -- ④ 引入 h
  evalTactic (← `(tactic| have $h:ident := $proof:term))
  let (hData, hDisplay) ← captureEmbedField "h" (Recording.expression h.raw) (some h.raw)
  let (afterGoalData, afterGoalDisplay) ← captureEmbedField "goal_after" Recording.goalSnapshot
    (collectReferences := false)
  -- ⑤ 参数记录器 → 主 box
  let step := Recording.RecordedData.object [
    ("_ruleId", .plain (toJson ruleId)),
    ("goal_before", goalData),
    ("goal_before_display", goalDisplay),
    ("goal_after", afterGoalData),
    ("goal_after_display", afterGoalDisplay),
    ("h", hData),
    ("h_display", hDisplay),
    ("type", typeData),
    ("type_display", typeDisplay),
    ("theorem", .plain (toJson c.toString)),
    ("args", argsData),
    ("args_display", argsDisplay),
    ("argKinds", .plain argKindsJson),
    ("proof", proofData),
    ("proof_display", proofDisplay)]
  appendBoxItem boxName step bindings

script_info embed { renderer := embed }

end ProofScript
