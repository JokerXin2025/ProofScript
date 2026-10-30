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
  alt.getArg 0 |>.getArg 0 |>.getArgs[1]!.getArgs[1]!.getId.toString

/-- Flatten ordinary sequences and recursively convert branches to native `case` tactics. -/
private partial def collectTactics (stmts : Array Syntax) : Array Syntax :=
  stmts.foldl (init := #[]) fun tactics s =>
    let inner := s.getArg 0
    if inner.getKind == ``scriptBranch then
      let caseStx := inductionAltToCase inner
      let body := collectTactics <| scriptStmtsToArray caseStx[3]
      tactics.push <| caseStx.setArg 3 (buildTacticSeq body)
    else if inner.getKind == ``scriptBullet then
      let body := collectTactics <| scriptStmtsToArray inner[1]
      tactics.push <|
        Syntax.node inner.getHeadInfo ``cdot #[inner[0], buildTacticSeq body]
    else
      let seqNode := inner.getArg 0
      if seqNode.getKind == ``tacticSeq1Indented then
        seqNode.getArgs.foldl (init := tactics) fun ts n =>
          n.getArgs.foldl (fun ts2 x => if x.isAtom then ts2 else ts2.push x) ts
      else
        tactics.push inner

/-- 从策略名 atom 构造 ident（位置关联到原 atom），用于 `run_script_step` 参数。 -/
def tacticNameIdent (t : Syntax) : Option Syntax :=
  match findFirstAtom t with
  | some atom =>
      -- Carry the literal keyword, not a namespace path or an escaped identifier.
      some (mkIdentFrom atom (Name.mkSimple atom.getAtomVal))
  | none => none

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
    seqNode.getArgs.foldl (init := #[]) fun ts n =>
      n.getArgs.foldl (init := ts) fun ts2 x =>
        if x.isAtom || x.getKind == `null then ts2 else ts2.push x
  else
    #[inner]

/-- 收集策略调用后连续出现的 `| case =>` 分支名。 -/
def collectFollowingStrategyCases (stmts : Array Syntax) (start : Nat) : List (Option Name) := Id.run do
  let mut nodes : List (Option Name) := []
  let mut i := start
  while i < stmts.size do
    let inner := stmts[i]!.getArg 0
    if inner.getKind == ``scriptBranch then
      nodes := nodes ++ [some (inductionAltTag inner).toName]
    else if inner.getKind == ``scriptBullet then
      nodes := nodes ++ [none]
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
  let rewritten ← match rewriteTacticCall sourceCall registration.name ("script_" ++ registration.name)
      registration.executionKind with
    | .ok rewritten => pure rewritten
    | .error message => withRef call (throwError message)
  Elab.Tactic.withTacticInfoContext call.raw <|
    evalTactic (⟨rewritten⟩ : TSyntax `tactic)

/-- 递归转换 script 序列：普通 tactic 使用 `run_script_step`；`case` 分支递归
     检查其 body 内的 tactic（否则分支内的策略会绕过校验）。 -/
private partial def checkScript (t : Syntax) : MacroM (Array Syntax) := do
  if t.getKind == ``Parser.Tactic.case then
    let body := t[3]
    let mut checkedInner := #[]
    for x in flattenTactics body do
      checkedInner := checkedInner ++ (← checkScript x)
    let newBody := buildTacticSeq checkedInner
    let newCase := Syntax.node t.getHeadInfo ``Parser.Tactic.case #[t[0], t[1], t[2], newBody]
    return #[newCase]
  else if t.getKind == ``Lean.cdot then
    let mut checked := #[]
    for x in flattenTactics t[1] do
      checked := checked ++ (← checkScript x)
    return #[t.setArg 1 (buildTacticSeq checked)]
  else
    match tacticNameIdent t with
    | some name =>
        let name' : TSyntax `ident := ⟨name⟩
         let call : TSyntax `scriptTactic := ⟨t⟩
         let run ← `(tactic| run_script_step $name':ident $call:scriptTactic)
        return #[run]
    | none => return #[t]

macro "script" scripts:scriptStmts : term => do
  let tactics := collectTactics (scriptStmtsToArray scripts)
  let mut checked := #[]
  for t in tactics do
    checked := checked ++ (← checkScript t)
  let tacticSeq := ⟨buildTacticSeq checked⟩
  `(by $tacticSeq)

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
      let some recordingKind := registration.recordingKind
        | withRef t (throwError "script strategy `{registration.ruleId}` has no recorder entry")
      match rewriteTacticCall sourceCall registration.name ("_script_" ++ registration.name) recordingKind with
      | .ok rewritten => return rewritten
      | .error message => withRef t (throwError message)
    | none =>
      if let some name := firstAtomName t then
        let hint := (nativeHintMap.lookup name).getD "unknown script"
        withRef t (throwError hint)
      return t

def appendStrategyCases (t : Syntax) (nodes : List (Option Name)) : Syntax :=
  let encoded := String.intercalate "\n" (nodes.map (·.map Name.toString |>.getD ""))
  changeNodeKind t t.getKind <|
    t.getArgs.push (mkAtomFrom t "_strategy_cases") |>.push (Syntax.mkStrLit encoded t.getHeadInfo)

local elab "_select_strategy_case" : tactic => selectCurrentStrategyBranch
local elab "_next_strategy_case" : tactic => advanceCurrentStrategyCase
local elab "_merge_strategy" : tactic => finishRecordingStrategy

private structure PendingRecordedStrategy where
  nodes : List (Option Name)
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
      let selectCase ← `(tactic| _select_strategy_case)
      let body := if pendingStrategy.isSome then
          #[selectCase.raw] ++ body
        else body
      let caseStx' := caseStx.setArg bodyIdx (buildTacticSeq body)
      if needsAdvance && pendingStrategy.isSome then
        out := out.push (← `(tactic| _next_strategy_case)).raw
      out := out.push caseStx'
      pendingStrategy := pendingStrategy.map fun p => { p with completed := p.completed + 1 }
      needsAdvance := pendingStrategy.isSome
    else
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
          if registration.config.isStrategy then
            unless callIdx + 1 == calls.size do
              withRef t <| throwError "a recorded strategy must be followed immediately by its branches"
            let nodes := collectFollowingStrategyCases stmts (i + 1)
            let hasBranches := if i + 1 < stmts.size then
              let next := stmts[i + 1]!.getArg 0
              next.getKind == ``scriptBranch || next.getKind == ``scriptBullet
            else false
            if !hasBranches then
              withRef t <| throwError m!"strategy `{registration.ruleId}` requires at least one `| case =>` or `·` branch"
            pendingStrategy := some { nodes }
            needsAdvance := false
        | none => pure ()
        let t' ← validateAndUnderscore registrations t
        let t' := match selected with
          | some registration =>
              if registration.config.isStrategy then
                let payload := pendingStrategy.map (·.nodes) |>.getD []
                appendStrategyCases t' payload
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
