import ProofScript.Script.Command
import ProofScript.Utils.Syntax

open Lean
open Parser.Tactic (tacticSeq1Indented)
open Elab.Tactic (evalTactic)


namespace ProofScript


/-! ## `script` 脚本语法

脚本 body 支持 script tactic、命名分支 `| branch => ...` 和匿名分支 `· ...`。
分支 body 递归使用 script 语法，展开时转换为 Lean 的 case / cdot tactic。 -/

-- Reuse sequence/branch node layouts, but never the native tactic parser.
def scriptTacticSeq : Lean.Parser.Parser := Parser.node ``Parser.Tactic.tacticSeq <|
  Parser.node ``tacticSeq1Indented <|
    Parser.Tactic.sepBy1IndentSemicolon (Parser.categoryParser `scriptTactic 0)

declare_syntax_cat scriptStmt

syntax (ppDedent(ppLine) scriptTacticSeq) : scriptStmt

/-! 缩进敏感的 `scriptStmt+`：仿 `inferSteps`，用单个 `withPosition` 包裹整个序列，
    `colGe` 要求每个 scriptStmt 的缩进列 ≥ 首 stmt 缩进列，从而把「同缩进/更浅的后续 tactic」
    排除在 script 块之外（避免 `have h : P := script …` 的子证明贪婪吞掉下一行 tactic）。 -/
syntax scriptStmts := withPosition(ppLine (colGe scriptStmt) (ppLine linebreak (colGe scriptStmt))*)

-- Parse branch bodies recursively so their continuations stay inside the branch.
syntax scriptBranch := Parser.Tactic.inductionAltLHS+ (" => " scriptStmts)?
syntax scriptBranch : scriptStmt
-- Lean's bullet elaborator records focus info on the cdotTk node, not a bare atom.
syntax scriptBullet := cdotTk scriptStmts
syntax scriptBullet : scriptStmt

/-- 从 `scriptStmts` 节点提取 scriptStmt 数组。结构：`[首 stmt, (linebreak colGe scriptStmt)* 节点]`。 -/
def scriptStmtsToArray (stmts : Syntax) : Array Syntax :=
  if h : stmts.getArgs.size >= 2 then
    #[stmts[0]] ++ stmts[1].getArgs
  else
    #[stmts[0]]

/-! ## `| branch =>` → `case branch =>` 语法转换（保留位置） -/

/-- 将 `ident` 节点包装为 `binderIdent` 节点（`case` 的 tag/binder 需要）。 -/
private def identToBinderIdent (id : Syntax) : Syntax := Syntax.node id.getHeadInfo `Lean.binderIdent #[id]

/-- 将 `inductionAlt`（`| tag binders => body`）转换为 `case tag binders => body`，
    复用原始 ident / tacticSeq 节点并继承其位置。 -/
def inductionAltToCase (alt : Syntax) : Syntax :=
  let lhs := alt.getArg 0 |>.getArg 0
  let body := alt.getArg 1 |>.getArg 1
  let lhsArgs := lhs.getArgs
  let tagIdent := lhsArgs[1]!.getArgs[1]!
  let binderIdents := lhsArgs[2]!.getArgs
  let tagBI := identToBinderIdent tagIdent
  let binderBIs := binderIdents.map identToBinderIdent
  let caseArg := Syntax.node tagIdent.getHeadInfo ``Parser.Tactic.caseArg #[tagBI, mkNullNode binderBIs]
  Syntax.node alt.getHeadInfo ``Parser.Tactic.case #[mkAtomFrom alt "case", mkNullNode #[caseArg], mkAtomFrom alt "=>", body]

/-- 提取 `| tag binders => body` 的分支标签。 -/
def inductionAltTag (alt : Syntax) : String :=
  let lhs := alt.getArg 0 |>.getArg 0
  lhs.getArgs[1]!.getArgs[1]!.getId.toString

/-- Flatten ordinary sequences and recursively convert branches to native `case` tactics. -/
partial def collectTactics (stmts : Array Syntax) : Array Syntax :=
  stmts.foldl (fun tactics s =>
    let inner := s.getArg 0
    if inner.getKind == ``scriptBranch then
      let caseStx := inductionAltToCase inner
      let body := collectTactics (scriptStmtsToArray caseStx[3])
      tactics.push (caseStx.setArg 3 (buildTacticSeq body))
    else if inner.getKind == ``scriptBullet then
      let body := collectTactics (scriptStmtsToArray inner[1])
      tactics.push (Syntax.node inner.getHeadInfo ``Lean.cdot
        #[inner[0], buildTacticSeq body])
    else
      let seqNode := inner.getArg 0
      if seqNode.getKind == ``tacticSeq1Indented then
        seqNode.getArgs.foldl (fun ts n =>
          n.getArgs.foldl (fun ts2 x => if x.isAtom then ts2 else ts2.push x) ts
        ) tactics
      else
        tactics.push inner
  ) #[]

/-! ## 策略名验证 -/

/-- 从策略名 atom 构造 ident（位置关联到原 atom），用于 `run_script_step` 参数。 -/
def tacticNameIdent (t : Syntax) : Option Syntax :=
  match findFirstAtom t with
  | some atom =>
      -- Carry the literal keyword, not a namespace path or an escaped identifier.
      some (mkIdentFrom atom (Name.mkSimple atom.getAtomVal))
  | none => none

def scriptTacticName (name : String) : String := "script_" ++ name

def recordingTacticName (name : String) : String := "_" ++ scriptTacticName name

def scriptTacticBaseName? (name : String) : Option String :=
  if name.startsWith "script_" then some (name.drop 7 |>.toString) else none

/-- Select the registered parser candidate without descending into tactic arguments. -/
def registeredTacticCall (registrations : List ScriptTacticRegistration)
    (t : Syntax) : Option (ScriptTacticRegistration × Syntax) :=
  if t.getKind == `choice then
    t.getArgs.findSome? fun candidate =>
      registrations.find? (fun r => r.sourceKind == candidate.getKind)
        |>.map (·, candidate)
  else
    registrations.find? (fun r => r.sourceKind == t.getKind)
      |>.map (·, t)

/-- Rewrite only a tactic call's root kind and direct keyword token. All parameter syntax is reused. -/
def rewriteTacticCall (call : Syntax) (sourceName targetName : String)
    (targetKind : Name) : Except String Syntax := do
  let some tokenIdx := call.getArgs.findIdx? fun arg =>
      arg.isAtom && arg.getAtomVal == sourceName
    | throw s!"cannot find tactic keyword `{sourceName}` in registered call"
  let args := call.getArgs.set! tokenIdx (mkAtomFrom call.getArgs[tokenIdx]! targetName)
  return changeNodeKind call targetKind args

/-- 把一个 `scriptStmt` 的内层语法展平为 tactic 数组（处理 `;` 与缩进序列）。
    跳过 atom（`;` 分隔符）与 `null`（`;` 的 optional 包裹/空标记）节点。 -/
def flattenTactics (inner : Syntax) : Array Syntax :=
  let seqNode := inner.getArg 0
  if seqNode.getKind == ``tacticSeq1Indented then
    seqNode.getArgs.foldl (fun ts n =>
      n.getArgs.foldl (fun ts2 x => if x.isAtom || x.getKind == `null then ts2 else ts2.push x) ts
    ) #[]
  else
    #[inner]

/-- 收集策略调用后连续出现的 `| case =>` 分支名。 -/
def collectFollowingStrategyCases (stmts : Array Syntax) (start : Nat) : List String := Id.run do
  let mut nodes : List String := []
  let mut i := start
  while i < stmts.size do
    let inner := stmts[i]!.getArg 0
    if inner.getKind == ``scriptBranch then
      nodes := nodes ++ [inductionAltTag inner]
    else if inner.getKind == ``scriptBullet then
      nodes := nodes ++ [""]
    else break
    i := i + 1
  return nodes

/-- Hint mapping table for Lean native tactics -/
def nativeHintMap : List (String × String) := [
  ("apply", "Use `apply` with a proposition of the form `P -> Q` or `P <-> Q`."),
  ("intro", "Use `intro` in script blocks, or `contra` for implications to `False`."),
  ("rw", "Use `rw` in `script` blocks."),
  ("rfl", "Use `trivial` instead of `rfl`."),
  ("assumption", "Use `trivial` instead of `assumption`."),
  ("trivial", "`trivial` is already allowed in `script` blocks."),
  ("contradiction", "Use `trivial` instead of `contradiction`."),
  ("tauto", "Use `trivial` instead of `tauto`."),
  ("symm", "Use `symm` — it is allowed in `script` blocks."),
  ("unfold", "Use `unfold` — it is allowed in `script` blocks."),
  ("change", "Use `change` in `script` blocks."),
  ("simp", "Use `simp` — it is allowed in `script` blocks."),
  ("omega", "Use `omega` — it is allowed in `script` blocks."),
  ("dsimp", "Use `simp` instead of `dsimp`."),
  ("simpa", "Use `simp` instead of `simpa`."),
  ("ring", "Use `ring` — it is allowed in `script` blocks."),
  ("linarith", "Use `linarith` — it is allowed in `script` blocks."),
  ("nlinarith", "Use `nlinarith` — it is allowed in `script` blocks."),
  ("norm_num", "Use `norm_num` — it is allowed in `script` blocks."),
  ("field", "Use `field` — it is allowed in `script` blocks."),
  ("field_simp", "Use `field` instead of `field_simp`."),
  ("refine", "Use `provide` or `apply` instead of `refine`."),
  ("rcases", "Use `cases_on` or `obtain_exist` instead of `rcases`."),
  ("obtain", "Use `obtain` — it is allowed in `script` blocks."),
  ("by_cases", "Use `cases_on` — it is allowed in `script` blocks."),
  ("by_contra", "Use `by_contra` — it is allowed in `script` blocks."),
  ("exfalso", "Use `trivial` instead of `exfalso`.")
]

/-- Validate and execute one script tactic through its registered prefixed parser kind. -/
elab "run_script_step" name:ident call:scriptTactic : tactic => do
  let nameStr := name.getId.toString (escape := false)
  let registrations := scriptTacticRegistrations (← getEnv)
  let some (registration, sourceCall) := registeredTacticCall registrations call.raw
    | let hint := (nativeHintMap.lookup nameStr).getD "unknown script tactic"
      withRef name (throwError hint)
  if let some keyword := findFirstAtom sourceCall then
    Elab.addConstInfo keyword registration.sourceKind
  let rewritten ← match rewriteTacticCall sourceCall registration.name (scriptTacticName registration.name)
      registration.executionKind with
    | .ok rewritten => pure rewritten
    | .error message => withRef call (throwError message)
  Elab.Tactic.withTacticInfoContext call.raw <|
    withScriptMode <| evalTactic (⟨rewritten⟩ : TSyntax `tactic)

/-- Execute an unavailable recorder's tactic while retaining its position and branch routing. -/
elab (name := unrecordedStep) "_record_unrecorded_step" "_strategy_cases" cases:str : tactic => do
  let some contract ← selectedRecordingContract
    | throwError "unrecorded step has no invocation contract"
  Recording.withRecordingStep fun step => do
    step.recordJson "name" (toJson contract.name)
    executeRecordedStep
    if contract.strategy then
      let contexts ← Recording.resolveStrategyContexts (cases.getString.splitOn "\n") contract.continuation
      step.prepareBranches contexts

elab "run_recorded_step" source:scriptTactic call:tactic : tactic => do
  let registrations := scriptTacticRegistrations (← getEnv)
  let some (registration, sourceCall) := registeredTacticCall registrations source.raw
    | throwErrorAt source "recorded tactic has no matching registration"
  if let some keyword := findFirstAtom sourceCall then
    Elab.addConstInfo keyword registration.sourceKind
  unless registration.recordingKind == some call.raw.getKind ||
      (registration.recordingKind.isNone && call.raw.getKind == ``unrecordedStep) do
    throwErrorAt call "recorder changed after this script call was converted; rebuild the recording call"
  let execution ← match rewriteTacticCall sourceCall registration.name
      (scriptTacticName registration.name) registration.executionKind with
    | .ok rewritten => pure rewritten
    | .error message => throwErrorAt source "{message}"
  if registration.recordingKind.isNone then
    logWarningAt source m!"{registration.autoRecordingError.getD s!"script strategy `{registration.ruleId}` has no recorder"}；未导出数据"
  withRecordingRegistration registration execution <|
    Elab.Tactic.withTacticInfoContext source.raw <| evalTactic call.raw

/-! ## `:= script` Syntax -/

/-- Validate the full tag before handing binder renaming and focus to Lean's `case`. -/
elab "_check_script_branch" tag:ident : tactic => do
  let name := tag.getId.eraseMacroScopes
  let goals ← (← Elab.Tactic.getGoals).filterM fun goal => return !(← goal.isAssigned)
  unless (← Recording.resolveStrategyGoal goals name.toString).isSome do
    throwError "strategy branch `{name}` has no matching goal; use a full goal tag or `·`"

/-- 递归转换 script 序列：普通 tactic 使用 `run_script_step`；`case` 分支递归
     检查其 body 内的 tactic（否则分支内的策略会绕过校验）。 -/
private partial def checkScriptStep (t : Syntax) : MacroM (Array Syntax) := do
  if t.getKind == ``Parser.Tactic.case then
    let body := t[3]
    let mut checkedInner := #[]
    for x in flattenTactics body do
      checkedInner := checkedInner ++ (← checkScriptStep x)
    let newBody := buildTacticSeq checkedInner
    let newCase := Syntax.node t.getHeadInfo ``Parser.Tactic.case #[t[0], t[1], t[2], newBody]
    let tag : TSyntax `ident := ⟨t[1][0][0][0]⟩
    let check ← `(tactic| _check_script_branch $tag:ident)
    return #[check.raw, newCase]
  else if t.getKind == ``Lean.cdot then
    let mut checked := #[]
    for x in flattenTactics t[1] do
      checked := checked ++ (← checkScriptStep x)
    return #[t.setArg 1 (buildTacticSeq checked)]
  else
    match tacticNameIdent t with
    | some name =>
        let name' : TSyntax `ident := ⟨name⟩
         let call : TSyntax `scriptTactic := ⟨t⟩
         let run ← `(tactic| run_script_step $name':ident $call:scriptTactic)
        return #[run]
    | none => return #[t]

/-- `:= script` term：展开为 `by <tactic 序列>`，每个策略（含 `| branch =>` 分支内的）前
    注入 `run_script_step`，也支持匿名 `·` 分支。 -/
macro "script" stmts:scriptStmts : term => do
  let stmtsArray := scriptStmtsToArray stmts
  let tactics := collectTactics stmtsArray
  let mut checked := #[]
  for t in tactics do
    checked := checked ++ (← checkScriptStep t)
  let seq := ⟨buildTacticSeq checked⟩
  `(by $seq:tacticSeq)

/-! ## 录制版代码生成（语法级） -/
open Lean.Elab.Command in
 /-- 递归校验并改写：普通 tactic 校验注册表后切换录制入口；`case` 分支递归校验其 body
     （否则分支内的策略会绕过校验）。
    泛型到任意具备 `MonadRef`/`MonadError`/`MonadOptions` 的 monad，使命令 elaborator
    与 `TacticM`（`embed` 重放）都能调用。 -/
private partial def validateAndUnderscore {m : Type → Type}
                                          [Monad m]
                                          [MonadQuotation m]
                                          [MonadRef m]
                                          [MonadError m]
                                          [MonadOptions m]
                                          (registrations : List ScriptTacticRegistration)
                                          (t : Syntax)
                                          : m Syntax := do
  if t.getKind == ``Parser.Tactic.case then
    let body := t[3]
    let mut newInner : Array Syntax := Array.empty
    for x in flattenTactics body do
      newInner := newInner.push (← validateAndUnderscore registrations x)
    let newBody := buildTacticSeq newInner
    return Syntax.node t.getHeadInfo ``Parser.Tactic.case #[t[0], t[1], t[2], newBody]
  else
    match registeredTacticCall registrations t with
    | some (registration, sourceCall) =>
      let call : TSyntax `tactic ← match registration.recordingKind with
        | none => `(tactic| _record_unrecorded_step _strategy_cases "")
        | some recordingKind =>
          match rewriteTacticCall sourceCall registration.name (recordingTacticName registration.name) recordingKind with
          | .ok rewritten => pure ⟨rewritten⟩
          | .error message => withRef t (throwError message)
      let source : TSyntax `scriptTactic := ⟨t⟩
      return (← `(tactic| run_recorded_step $source:scriptTactic $call:tactic)).raw
    | none =>
      if let some name := firstAtomName t then
        let hint := (nativeHintMap.lookup name).getD "未知script策略"
        withRef t (throwError hint)
      return t

/-- 给自动生成的概略录制 tactic 追加调用处推导出的隐藏分支参数。节点 kind 已换成
    `_strategy` 的录制 kind，参数布局末尾与 `genRecording`
    生成的 `"_strategy_cases" str` 一致。 -/
def appendStrategyCases (t : Syntax) (nodes : List String) : Syntax :=
  let encoded := String.intercalate "\n" nodes
  let call := t[2]
  if call.getKind == ``unrecordedStep then
    t.setArg 2 (call.setArg 2 (Syntax.mkStrLit encoded call.getHeadInfo))
  else
    t.setArg 2 <| changeNodeKind call call.getKind <|
      call.getArgs.push (mkAtomFrom call "_strategy_cases") |>.push (Syntax.mkStrLit encoded call.getHeadInfo)

local elab "_next_strategy_case" : tactic => advanceStrategyCase

local elab "_merge_strategy" : tactic => Recording.finishRecordingStrategy

private structure PendingRecordedStrategy where
  nodes : List String
  completed : Nat := 0

open Lean.Elab.Command in
partial def collectRecordTactics {m : Type → Type} [Monad m] [MonadQuotation m] [MonadRef m]
    [MonadError m] [MonadOptions m] [MonadEnv m] [MonadLiftT IO m]
                                   (stmts : Array Syntax)
                                    : m (Array Syntax) := do
  let registrations := scriptTacticRegistrations (← getEnv)
  let mut out : Array Syntax := #[]
  let mut pendingStrategy : Option PendingRecordedStrategy := none
  let mut needsAdvance := false
  for i in [:stmts.size] do
    let s := stmts[i]!
    let inner := s.getArg 0
    if inner.getKind == ``scriptBranch || inner.getKind == ``scriptBullet then
      -- Once all registered proof branches finish, subsequent branches focus the continuation.
      if needsAdvance then
        if let some pending := pendingStrategy then
          if pending.completed == pending.nodes.length then
            out := out.push (← `(tactic| _next_strategy_case)).raw
            out := out.push (← `(tactic| _merge_strategy)).raw
            pendingStrategy := none
            needsAdvance := false
      let isBullet := inner.getKind == ``scriptBullet
      let caseStx := if isBullet then
          Syntax.node inner.getHeadInfo ``Lean.cdot #[inner[0], inner[1]]
        else inductionAltToCase inner
      let bodyIdx := if isBullet then 1 else 3
      let body ← collectRecordTactics (scriptStmtsToArray caseStx[bodyIdx])
      let caseStx' := caseStx.setArg bodyIdx (buildTacticSeq body)
      if needsAdvance && pendingStrategy.isSome then
        out := out.push (← `(tactic| _next_strategy_case)).raw
      -- Strategy branches were already resolved together; only standalone or
      -- continuation branches still need an exact-tag check here.
      if !isBullet && pendingStrategy.isNone then
        let tag : TSyntax `ident := ⟨caseStx[1][0][0][0]⟩
        out := out.push (← `(tactic| _check_script_branch $tag:ident)).raw
      out := out.push caseStx'
      pendingStrategy := pendingStrategy.map fun p => { p with completed := p.completed + 1 }
      needsAdvance := pendingStrategy.isSome
    else
      -- 概略策略的最后一个分支结束后，若还有普通续接步骤（如 `have h : P | proof => …` 之后的
      -- `<rest>`），先插入 `_next_strategy_case` 把录制 box 从分支推进回主 box，再处理续接步骤。
      if needsAdvance then
        out := out.push (← `(tactic| _next_strategy_case)).raw
        needsAdvance := false
        match pendingStrategy with
        | some _ =>
            out := out.push (← `(tactic| _merge_strategy)).raw
            pendingStrategy := none
        | none => pure ()
      let calls := flattenTactics inner
      for callIdx in [:calls.size] do
        let t := calls[callIdx]!
        let selected := (registeredTacticCall registrations t).map (·.1)
        match selected with
        | some registration =>
          if registration.strategy then
            unless callIdx + 1 == calls.size do
              withRef t <| throwError "a recorded strategy must be followed immediately by its branches"
            let nodes := collectFollowingStrategyCases stmts (i + 1)
            let nodes := registration.continuation.map nodes.take |>.getD nodes
            if nodes.isEmpty then
              withRef t <| throwError m!"strategy `{registration.ruleId}` requires at least one `| case =>` or `·` branch"
            pendingStrategy := some { nodes }
            needsAdvance := false
        | none => pure ()
        let t' ← validateAndUnderscore registrations t
        let t' := match selected with
          | some registration =>
              if registration.strategy then
                appendStrategyCases t' (pendingStrategy.map (·.nodes) |>.getD [])
              else t'
          | none => t'
        out := out.push t'
  if needsAdvance then
    out := out.push (← `(tactic| _next_strategy_case)).raw
    match pendingStrategy with
    | some _ =>
        out := out.push (← `(tactic| _merge_strategy)).raw
        pendingStrategy := none
    | none => pure ()
  return out

end ProofScript
