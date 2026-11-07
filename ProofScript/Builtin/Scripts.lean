import ProofScript.Utils.Tactic
import ProofScript.Utils.Syntax
import ProofScript.Script.Command
import ProofScript.Info.Theorem
import ProofScript.Script.Script
import ProofScript.Script.Recording
import Batteries.Tactic.Init
import ProofScript.Core.BuildMode
import ProofScript.Info.Commands
import Mathlib.Tactic

import ProofScript.Extensions.Title
import ProofScript.Extensions.ProofText

import ProofScript.Builtin.Scripts.Admit
import ProofScript.Builtin.Scripts.Assumption
import ProofScript.Builtin.Scripts.BetaReduce
import ProofScript.Builtin.Scripts.By
import ProofScript.Builtin.Scripts.Change
import ProofScript.Builtin.Scripts.Congr
import ProofScript.Builtin.Scripts.Contradiction
import ProofScript.Builtin.Scripts.Decide
import ProofScript.Builtin.Scripts.Exfalso
import ProofScript.Builtin.Scripts.Exists
import ProofScript.Builtin.Scripts.LeftRight
import ProofScript.Builtin.Scripts.Omega
import ProofScript.Builtin.Scripts.Pointwise
import ProofScript.Builtin.Scripts.QuotInduction
import ProofScript.Builtin.Scripts.Rewrite
import ProofScript.Builtin.Scripts.Rfl
import ProofScript.Builtin.Scripts.Symm
import ProofScript.Builtin.Scripts.Trivial
import ProofScript.Builtin.Scripts.Unfold

import ProofScript.Builtin.Scripts.SplitAnd

import ProofScript.Builtin.Scripts.Cite
import ProofScript.Builtin.Scripts.Remark
import ProofScript.Builtin.Scripts.Svg


#page title "Scripts in *ProofScript*"

#page text r#""#


#page sub title (label := "BuiltinTactics")
"Built-in Tactics"

#page text r#"
These are provided as *built-in tactics*:
+ *«admit»*
  - Lean syntax: `"admit" reason:str`
  - clear: `reason`
+ *«assumption»*
  - Lean syntax: `"assumption"`
+ *«betaReduce»*
  - Lean syntax: `"beta_reduce" loc:(location)?`
  - clear: `loc`
+ *«by»*
  - Lean syntax: `"by " tac:tactic decr:(str)?`
  - clear: `tac`, `decr`
+ *«change»*
  - Lean syntax: `"change " eq:term loc:(location)?`
  - clear: `eq`, `loc`
+ *«congr»*
  - Lean syntax: `"congr" num:(ppSpace num)?`
  - clear: `num`
+ *«contradiction»*
  - Lean syntax: `"contradiction"`
+ *«decide»*
  - Lean syntax: `"decide" config:optConfig`
  - clear: `config`
+ *«nativeDecide»*
  - Lean syntax: `"native_decide" config:optConfig`
  - clear: `config`
+ *«exfalso»*
  - Lean syntax: `"exfalso"`
+ *«exists»*
  - Lean syntax: `"exists " data:term`
  - clear: `data`
+ *«existsWith»*
  - Lean syntax: `"exists " data:term "with" cond:term`
  - clear: `data`, `cond`
+ *«left»*
  - Lean syntax: `"left"`
+ *«right»*
  - Lean syntax: `"right"`
+ *«omega»*
  - Lean syntax: `"omega" config:optConfig`
  - clear: `config`
+ *«bvOmega»*
  - Lean syntax: `"bv_omega"`
+ *«pointwise»*
  - Lean syntax: `"pointwise" loc:(location)?`
  - clear: `loc`
+ *«quotInduction»*
  - Lean syntax: `"quot_induction " q:term "with" a:ident`
+ *«rewrite»*
  - Lean syntax: `"rewrite" config:optConfig rules:rwRuleSeq loc:(location)?`
  - clear: `config`, `rules`, `loc`
+ *«rw»*
  - Lean syntax: `"rw " config:optConfig rules:rwRuleSeq loc:(location)?`
  - clear: `config`, `rules`, `loc`
+ *«rwPos»*
  - Lean syntax: `"rw_pos " h:term loc:(location)?`
  - clear: `h`, `loc`
+ *«rwNeg»*
  - Lean syntax: `"rw_neg " h:term loc:(location)?`
  - clear: `h`, `loc`
+ *«rfl»*
  - Lean syntax: `"rfl"`
+ *«rfl'»*
  - Lean syntax: `"rfl'"`
+ *«eqRefl»*
  - Lean syntax: `"eq_refl"`
+ *«applyRfl»*
  - Lean syntax: `"apply_rfl"`
+ *«acRfl»*
  - Lean syntax: `"ac_rfl"`
+ *«symm»*
  - Lean syntax: `"symm" loc:(location)?`
  - clear: `loc`
+ *«symmSaturate»*
  - Lean syntax: `"symm_saturate"`
+ *«trivial»*
  - Lean syntax: `"trivial"`
+ *«unfold»*
  - Lean syntax: `"unfold" defs:(ppSpace colGt ident)+ loc:(location)?`
  - clear: `defs`, `loc`
"#


#page sub title (label := "BuiltinStrategies")
"Built-in Strategies"

#page text r#"
These are provided as *built-in strategies*:
+ *«splitAnd»*
  - Lean syntax: `"split_and"`
  - branches: `left`, `right`
+ *«splitAnd!»*
  - Lean syntax: `"split_and!"`
  - branches: `goalI`, `goalII`, `goalIII`, etc.
"#


#page sub title (label := "BuiltinMetadata")
"Built-in Metadata Collectors"

#page text r#"
These are provided as *built-in metadata collectors*:
+ *«cite»*
  - Lean syntax: `"cite " thm:ident`
  - clear: `thm`
+ *«remark»*
  - Lean syntax: `"remark" text:str`
  - clear: `text`
+ *«svg»*
  - Lean syntax: `"svg" code:str`
  - clear: `code`
"#

#page sub title (label := "RestrictedMathlibTactics")
"Restricted Native Tactics"

#page text r#"
These Lean native tactics are supported but restricted:
+ *«exists»*
  - origin Lean syntax: `"exists " es:term,+`
  - restriction: Only one parameter can be provided at a time
"#


#page sub title (label := "UnsupportedMathlibTactics")
"Unsupported Native Tactics"

#page text r#"
These Lean native tactics are *not supported*:
+ *«allGoals»*
  - Lean syntax: `"all_goals " tacticSeq`
  - reason: For metaprogramming only
+ *«anyGoals»*
  - Lean syntax: `"any_goals " tacticSeq`
  - reason: For metaprogramming only
+ *«dbgTrace»*
  - Lean syntax: `"dbg_trace " str`
  - reason: For debugging purposes only
+ *«done»*
  - Lean syntax: `"done"`
  - reason: For metaprogramming only
+ *«fail»*
  - Lean syntax: `"fail" (ppSpace str)?`
  - reason: For metaprogramming only
+ *«failIfSuccess»*
  - Lean syntax: `"fail_if_success " tacticSeq`
  - reason: For metaprogramming only
+ *«first»*
  - Lean syntax: `"first " withPosition((ppDedent(ppLine) colGe "| " tacticSeq)+)`
  - reason: For metaprogramming only
+ *«focus»*
  - Lean syntax: `"focus " tacticSeq`
  - reason: For metaprogramming only
+ *«repeat»*
  - Lean syntax: `"repeat " tacticSeq`
  - reason: For metaprogramming only
+ *«repeat'»*
  - Lean syntax: `"repeat' " tacticSeq`
  - reason: For metaprogramming only
+ *«repeat1'»*
  - Lean syntax: `"repeat1' " tacticSeq`
  - reason: For metaprogramming only
+ *«rotateLeft»*
  - Lean syntax: `"rotate_left" (ppSpace num)?`
  - reason: No corresponding semantics
+ *«rotateRight»*
  - Lean syntax: `"rotate_right" (ppSpace num)?`
  - reason: No corresponding semantics
+ *«skip»*
  - Lean syntax: `"skip"`
  - reason: For metaprogramming only
+ *«sleep»*
  - Lean syntax: `"sleep " num`
  - reason: For debugging purposes only
+ *«traceMessage»*
  - Lean syntax: `"trace " str`
  - reason: For debugging purposes only
+ *«traceState»*
  - Lean syntax: `"trace_state"`
  - reason: For debugging purposes only
+ *«try»*
  - Lean syntax: `"try " t:tacticSeq`
  - reason: For metaprogramming only
+ *«unhygienic»*
  - Lean syntax: `"unhygienic " t:tacticSeq`
  - reason: Not recommended for use
+ *«withReducible»*
  - Lean syntax: `"with_reducible " tacticSeq`
  - reason: For metaprogramming only
+ *«withReducibleAndInstances»*
  - Lean syntax: `"with_reducible_and_instances " tacticSeq`
  - reason: For metaprogramming only
+ *«withUnfoldingAll»*
  - Lean syntax: `"with_unfolding_all " tacticSeq`
  - reason: For metaprogramming only
+ *«withUnfoldingNone»*
  - Lean syntax: `"with_unfolding_none " tacticSeq`
  - reason: For metaprogramming only
"#

open Lean Meta Parser Elab Tactic
open ProofScript

script_macro «simp» (clear := [config, args])
"simp" config:optConfig args:simpArgs loc:(location)? =>
  match args with
  | `(simpArgs| [$rules,*]) => `(tactic|
      simp $config:optConfig only [$rules,*] $[$loc:location]?)
  | _ => Macro.throwUnsupported

script_info «simp» {
  template := [{
    lang := zh, tag := "化简",
    content := ""
  }, {
    lang := en, tag := "«simp»",
    content := ""
  }]
}

/-! ## Script-Steps -/

private partial def hasProofParameter (type : Expr) : MetaM Bool := do
  let type ← Meta.whnf type
  match type with
  | .forallE name domain body binderInfo =>
      if ← isProp domain then pure true
      else withLocalDecl name binderInfo domain fun x =>
        hasProofParameter (body.instantiate1 x)
  | _ => pure false

private def rejectProofParameters (term : TSyntax `term) (value : Expr) : TacticM Unit := do
  let some _ := value.getAppFn.const?
  | return
  let functionType ← inferType value.getAppFn
  if ← hasProofParameter functionType then
    throwErrorAt term "`have` and `exact` cannot apply a function with proof parameters"

script_elab «have» (intro := [h])
"have" h:ident ":=" term:term => withMainContext do
  let expression ← elabTerm term none
  let expression ← instantiateMVars expression
  rejectProofParameters term expression
  let type ← inferType expression
  let goal ← getMainGoal
  let rest ← goal.assert h.getId type expression
  let (fvarId, rest) ← rest.intro1P
  rest.withContext do
    Elab.Term.addLocalVarInfo h (mkFVar fvarId)
  replaceMainGoal [rest]

script_info «have» {
  template := [{
    lang := zh, tag := "引入事实",
    content := "${h_after}"
  }, {
    lang := en, tag := "«have»",
    content := "${h_after}"
  }]
}

/-- Introduce a local definition. Its type and value are recorded by the `let`
    recorder at this step, rather than attached to later variable occurrences. -/
script_elab «let» (intro := [h])
"let" h:ident type:(group(":" term))? ":=" term:term => withMainContext do
  let type ← type.mapM fun type => Term.elabType type.raw[1]
  let expression ← match type with
    | some type => elabTermEnsuringType term type
    | none => elabTerm term none
  let expression ← instantiateMVars expression
  let type ← instantiateMVars <| ← match type with
    | some type => pure type
    | none => inferType expression
  let rest ← (← getMainGoal).define h.getId type expression
  let (fvarId, rest) ← rest.intro1P
  rest.withContext do
    Elab.Term.addLocalVarInfo h (mkFVar fvarId)
  replaceMainGoal [rest]

script_recorder «let» => do
  record_goal "$goal_before"
  execute
  withMainContext do
    let declaration ← getLocalDeclFromUserName h.getId
    record_param "name" h
    record_value "type" (← recordExpression declaration.type)
    let value ← recordExpression declaration.value
    record_value "value" value
  record_goal "$goal_after"

script_info «let» {
  template := [{
    lang := zh, tag := "定义",
    content := "${name} : ${type} := ${value}"
  }, {
    lang := en, tag := "«let»",
    content := "${name} : ${type} := ${value}"
  }]
}

script_elab «exact» (clear := [value])
"exact" value:term => withMainContext do
  let goal ← getMainGoal
  let expression ← Elab.Tactic.elabTermEnsuringType value <| ← goal.getType
  let expression ← instantiateMVars expression
  rejectProofParameters value expression
  goal.assign expression
  replaceMainGoal []

script_info «exact» {
  template := [{
    lang := zh, tag := "«exact»",
    content := ""
  }, {
    lang := en, tag := "«exact»",
    content := ""
  }]
}

private partial def exactAndProj? (value target : Expr) : MetaM (Option Expr) :=
  withIncRecDepth do
    let saved ← Meta.saveState
    let type ← inferType value
    if ← Meta.withAssignableSyntheticOpaque <| isDefEq type target then
      return some value
    saved.restore
    let type ← whnf <| ← inferType value
    unless type.isAppOfArity ``And 2 do return none
    -- Future extensions to Prod/Iff/dependent projections need explicit projection rules here.
    for projection in [``And.left, ``And.right] do
      let saved ← Meta.saveState
      let projected := mkApp3 (mkConst projection) (type.getArg! 0) (type.getArg! 1) value
      if let some proof ← exactAndProj? projected target then return some proof
      saved.restore
    return none

script_elab «exact_proj» (clear := [value])
"exact_proj" value:term => withMainContext do
  let goal ← getMainGoal
  let target ← goal.getType
  let direct? ← try
      pure (some <| ← withoutRecover <| elabTermEnsuringType value target)
    catch ex =>
      if ex.isInterrupt || ex.isMaxRecDepth || ex.isMaxHeartbeat then throw ex
      pure none
  let expression ← match direct? with
    | some expression => pure expression
    | none => elabTerm value none
  let expression ← instantiateMVars expression
  -- Check the supplied term, not the proof-parameter-bearing projections we generate.
  rejectProofParameters value expression
  let some proof ← exactAndProj? expression target
    | throwErrorAt value "exact_proj failed: neither the term nor its And projections match the goal"
  goal.assign proof
  replaceMainGoal []

script_info «exact_proj» {
  template := [{
    lang := zh, tag := "投影",
    content := "待证目标蕴涵于已知条件“${value_before}”之中"
  }, {
    lang := en, tag := "«exact_proj»",
    content := ""
  }]
}

script_elab «intro» (intro := [h])
"intro" h:(colGt ident)+ => do
  for h in h do withMainContext do
    let goal ← getMainGoal
    let goalExpr ← whnf <| ← goal.getType
    match goalExpr with
    | .forallE _ domain body _ =>
      if (← isProp domain) && (← whnf body).isConstOf ``False then
        throwError "to solve the goal of form `... → False`, please use `contra`"
      let (fvarId, newMVarId) ← goal.intro h.getId
      newMVarId.withContext do
        Elab.Term.addLocalVarInfo h (mkFVar fvarId)
      replaceMainGoal [newMVarId]
    | _ =>
      throwError "intro failed: the current goal has no binder to introduce."

script_info «intro» {
  template := [{
    lang := zh, tag := "«intro»",
    content := ""
  }, {
    lang := en, tag := "«intro»",
    content := ""
  }]
}

private def unpackProof (h : TSyntax `term) : TacticM (MVarId × FVarId) := withMainContext do
  let proof ← instantiateMVars <| ← elabTerm h none
  let goal ← getMainGoal
  match proof with
  | .fvar id => return (goal, id)
  | _ =>
    let asserted ← goal.assert (← mkFreshUserName `unpackProof) (← inferType proof) proof
    let (id, rest) ← asserted.intro1P
    return (rest, id)

-- Split n - 1 times down the right spine; a singleton renames the whole conjunction.
script_elab «unpack_and» (intro := [names], clear := [h])
"unpack_and" "⟨" names:sepBy1(ident, ",") "⟩" ":=" h:term => withMainContext do
  let names := names.getElems
  let (initialGoal, initialRemainder) ← unpackProof h
  let mut goal := initialGoal
  let mut remainder := initialRemainder
  for i in [:names.size] do
    let (nextGoal, nextRemainder) ← goal.withContext do
      if i == 0 || i + 1 < names.size then
        let type ← whnf <| ← remainder.getType
        unless type.isAppOfArity ``And 2 do
          throwErrorAt names[i]! "unpack_and failed: proof '{h}' or its right-hand remainder is not a conjunction (And)"
      if i + 1 == names.size then
        let goal ← goal.rename remainder names[i]!.getId
        goal.withContext do
          Elab.Term.addLocalVarInfo names[i]! (mkFVar remainder)
        pure (goal, remainder)
      else
        let altNames := { varNames := [names[i]!.getId, names[i + 1]!.getId] }
        let #[subgoal] ← goal.cases remainder #[altNames]
        | throwError "unexpected error occurred during executing `unpack_and`"
        let #[first, second] := subgoal.fields
        | throwError "unexpected error occurred during executing `unpack_and`"
        subgoal.mvarId.withContext do
          Elab.Term.addLocalVarInfo names[i]! first
        pure (subgoal.mvarId, second.fvarId!)
    goal := nextGoal
    remainder := nextRemainder
  replaceMainGoal [goal]

script_info «unpack_and» {
  template := [{
    lang := zh, tag := "拆解",
    content := ""
  }, {
    lang := en, tag := "unpack",
    content := ""
  }]
}

script_elab «unpack_iff» (intro := [h₁, h₂], clear := [h])
"unpack_iff" "⟨" h₁:ident "," h₂:ident "⟩" ":=" h:term => withMainContext do
  let (goal, fvarId) ← unpackProof h
  let subgoal ← goal.withContext do
    let hExpr ← whnf <| ← fvarId.getType
    unless hExpr.isAppOfArity ``Iff 2 do
      throwErrorAt h "unpack_iff failed: proof '{h}' is not an equivalence (Iff)"
    let altNames := { varNames := [h₁.getId, h₂.getId] }
    let #[subgoal] ← goal.cases fvarId #[altNames]
      | throwError "unexpected error occurred during executing `unpack_iff`"
    pure subgoal
  subgoal.mvarId.withContext do
    let #[first, second] := subgoal.fields
    | throwError "unexpected error occurred during executing `unpack_iff`"
    Elab.Term.addLocalVarInfo h₁ first
    Elab.Term.addLocalVarInfo h₂ second
  replaceMainGoal [subgoal.mvarId]

script_info «unpack_iff» {
  template := [{
    lang := zh, tag := "拆解",
    content := ""
  }, {
    lang := en, tag := "unpack",
    content := ""
  }]
}

script_elab «obtain_exist» (intro := [h₁, h₂], clear := [h])
"obtain_exist" "⟨" h₁:ident "," h₂:ident "⟩" ":=" h:term => withMainContext do
  let (goal, fvarId) ← unpackProof h
  let subgoal ← goal.withContext do
    let hExpr ← whnf <| ← fvarId.getType
    unless hExpr.isAppOfArity ``Exists 2 do
      throwErrorAt h "obtain_exist failed: proof '{h}' is not an existential proposition (Exists)"
    let altNames := { varNames := [h₁.getId, h₂.getId] }
    let #[subgoal] ← goal.cases fvarId #[altNames]
      | throwError "unexpected error occurred during executing `obtain_exist`"
    pure subgoal
  subgoal.mvarId.withContext do
    let #[first, second] := subgoal.fields
    | throwError "unexpected error occurred during executing `obtain_exist`"
    Elab.Term.addLocalVarInfo h₁ first
    Elab.Term.addLocalVarInfo h₂ second
  replaceMainGoal [subgoal.mvarId]

script_info «obtain_exist» {
  template := [{
    lang := zh, tag := "拆解",
    content := ""
  }, {
    lang := en, tag := "«obtain_exist»",
    content := ""
  }]
}

script_macro «obtain_exist'» (intro := [h₁, h₂, h₃], clear := [h])
"obtain_exist" "⟨" h₁:ident "," h₂:ident "," h₃:ident "⟩" ":=" h:term => `(tactic| focus
  script_obtain_exist ⟨$h₁, existBody⟩ := $h
  script_unpack_and ⟨$h₂, $h₃⟩ := existBody
)

script_info «obtain_exist'» {
  template := [{
    lang := zh, tag := "拆解",
    content := ""
  }, {
    lang := en, tag := "«obtain_exist'»",
    content := ""
  }]
}

script_elab «funext» (intro := [arg])
"funext" arg:ident => withMainContext do
  let target ← getMainGoalExpr'
  unless target.isAppOfArity ``Eq 3 do
    throwError "`funext` can only be used on function equality goals"
  let lhsType ← whnf <| ← inferType (target.getArg! 1)
  let rhsType ← whnf <| ← inferType (target.getArg! 2)
  match lhsType, rhsType with
  | .forallE _ domain _ _, .forallE _ domain' _ _ =>
    unless ← isDefEq domain domain' do
      throwError "`funext` requires both sides of the equality to have the same function domain"
    evalTactic <| ← `(tactic| funext $arg:ident)
  | _, _ => throwError "`funext` can only be used on function equality goals"

script_info «funext» {
  template := [{
    lang := zh, tag := "外延性",
    content := ""
  }, {
    lang := en, tag := "By function extensionality,",
    content := ""
  }]
}

script_elab «provide» (clear := [data])
"provide" data:term => withMainContext do
  let target ← getMainGoalExpr'
  let expectedType := if target.isAppOfArity ``Exists 2 then target.getArg! 0 else target
  let dataExpr ← elabTermEnsuringType data expectedType
  if ← isProp (← inferType dataExpr) then
    throwErrorAt data "`provide` expects data, not a proof"
  let data ← Term.exprToSyntax dataExpr
  if target.isAppOfArity ``Exists 2 then
    evalTactic (← `(tactic| refine Exists.intro $data ?_))
  else
    evalTactic (← `(tactic| exact $data))

script_info «provide» {
  template := [{
    lang := zh, tag := "选取",
    content := "${data_before}"
  }, {
    lang := en, tag := "«provide»",
    content := "${data_before}"
  }]
}

script_elab «apply» (clear := [h])
"apply" h:term => withMainContext do
  let hExpr ← instantiateMVars <| ← Elab.Tactic.elabTermForApply h
  let hType ← whnf <| ← inferType hExpr
  let target ← whnf <| ← getMainGoalExpr
  let premise ←
    if hType.isAppOfArity ``Iff 2 then
      let lhs := hType.getArg! 0
      let rhs := hType.getArg! 1
      if ← isDefEq target rhs then
        pure (hType.getArg! 0, mkApp (mkConst ``Iff.mp) hExpr)
      else if ← isDefEq target lhs then
        pure (hType.getArg! 1, mkApp (mkConst ``Iff.mpr) hExpr)
      else
        throwErrorAt h m!"Either `{lhs}` or `{rhs}` should be definitionally equal to `{target}`"
    else
      match hType with
      | .forallE _ premiseType conclusion _ =>
        unless (← isProp premiseType) && (← isProp conclusion) do
          throwErrorAt h m!"`{h}` should be in the form of `P → Q`, `P ← Q`, or `P ↔ Q`"
        unless ← isDefEq target conclusion do
          throwErrorAt h m!"`{conclusion}` should be definitionally equal to `{target}`"
        pure (premiseType, hExpr)
      | _ =>
        throwErrorAt h m!"`{h}` should be in the form of `P → Q`, `P ← Q`, or `P ↔ Q`"
  let (premiseType, applied) := premise
  let premiseMVar ← mkFreshExprMVar premiseType
  let goal ← getMainGoal
  goal.assign (mkApp applied premiseMVar)
  replaceMainGoal [premiseMVar.mvarId!]

script_info «apply» {
  template := [{
    lang := zh, tag := "应用定理",
    content := "${h_before}"
  }, {
    lang := en, tag := "Applying the theorem,",
    content := "${h_before}"
  }]
}

/-! ## Script-Strategy -/

/-! ### Assertions -/

script_elab «claim» (intro := [h], kind := strategy, continuation := `rest)
"claim" h:ident ":" type:term => focus <| withMainContext do
  -- A natural metavariable preserves the original elaboration of the proof branch.
  let proofMVar ← mkFreshExprMVar (← elabTerm type none)
  let fvarId ← elabAsFVar (← Term.exprToSyntax proofMVar) (some h.getId)
  withMainContext do Term.addLocalVarInfo h (mkFVar fvarId)
  let rest ← getMainGoal
  setGoals [proofMVar.mvarId!, rest]
  evalTactic (← `(tactic| set_goal_tags [`proof, `rest]))

script_recorder «claim» => do
  record_goal "$goal_before"
  execute
  record_param "h" h (goal := `rest)

script_info «claim» {
  template := [{
    lang := zh, tag := "断言",
    cases := [{name := "proof", tag := "证明", title := ""}]
  }, {
    lang := en, tag := "Proving an intermediate claim,",
    cases := [{name := "proof", tag := "Proof", title := ""}]
  }]
}

private def claimExist (names : Array (TSyntax `ident)) (type : TSyntax `term) : TacticM Unit :=
    focus <| withMainContext do
  let proofMVar ← mkFreshExprMVar (← elabTerm type none)
  let subject := mkIdent (← mkFreshUserName `claimExist)
  let _ ← elabAsFVar (← Term.exprToSyntax proofMVar) (some subject.getId)
  withRef type <| evalTactic (← `(tactic| first
    | guard_hyp $subject:ident :~ (Exists _)
    | fail "claim_exist requires an existential proposition (Exists)"))
  let first := names[0]!
  let second := names[1]!
  -- Rename after destructuring so names such as `rfl` remain ordinary identifiers.
  if names.size == 2 then
    evalTactic (← `(tactic| rcases $subject:ident with ⟨_, _⟩; rename_i $first:ident $second:ident))
  else
    let third := names[2]!
    withRef third <| evalTactic (← `(tactic| first
      | guard_hyp $subject:ident :~ (∃ _, _ ∧ _)
      | fail "claim_exist requires a conjunction after the existential witness (And)"))
    evalTactic (← `(tactic| rcases $subject:ident with ⟨_, _, _⟩;
      rename_i $first:ident $second:ident $third:ident))
  setGoals (proofMVar.mvarId! :: (← getGoals))
  evalTactic (← `(tactic| set_goal_tags [`proof, `rest]))

script_elab «claimExistTwo» (intro := [h₁, h₂], kind := strategy, continuation := `rest)
"claim_exist" "⟨" h₁:ident "," h₂:ident "⟩" ":" type:term =>
  claimExist #[h₁, h₂] type

script_recorder «claimExistTwo» => do
  record_goal "$goal_before"
  execute
  record_param "h₁" h₁ (goal := `rest)
  record_param "h₂" h₂ (goal := `rest)

script_info «claimExistTwo» {
  template := [{
    lang := zh, tag := "断言",
    cases := [{name := "proof", tag := "证明", title := ""}]
  }, {
    lang := en, tag := "Proving an existential claim,",
    cases := [{name := "proof", tag := "Proof", title := ""}]
  }]
}

script_elab «claimExistThree» (intro := [h₁, h₂, h₃], kind := strategy, continuation := `rest)
"claim_exist" "⟨" h₁:ident "," h₂:ident "," h₃:ident "⟩" ":" type:term =>
  claimExist #[h₁, h₂, h₃] type

script_recorder «claimExistThree» => do
  record_goal "$goal_before"
  execute
  record_param "h₁" h₁ (goal := `rest)
  record_param "h₂" h₂ (goal := `rest)
  record_param "h₃" h₃ (goal := `rest)

script_info «claimExistThree» {
  template := [{
    lang := zh, tag := "断言",
    cases := [{name := "proof", tag := "证明", title := ""}]
  }, {
    lang := en, tag := "Proving an existential claim,",
    cases := [{name := "proof", tag := "Proof", title := ""}]
  }]
}

/-! ### Existential Construction -/

script_macro «witness» (kind := strategy)
"witness" => `(tactic| focus
  first
  | guard_target =~ (∃ _, _)
  | fail "`witness` can only be used with `∃` propositions"
  apply Exists.intro
  set_goal_tags [`proof, `data]
)

script_info «witness» {
  color := (some (22, 106, 128), some (154, 199, 208), some (239, 248, 250)),
  template := [{
    lang := zh, tag := "构造",
    introducer := {tag := "目标拆解", content := "将目标拆分为数据构造和性质证明两个子目标"},
    cases := [
      {name := "data", tag := "子目标 I", title := ""},
      {name := "proof", tag := "子目标 II", title := ""}
    ]
  }, {
    lang := en, tag := "As a constructive proof,",
    introducer := {tag := "To construct the proof,", content := "split the goal into data construction and proof subgoals"},
    cases := [
      {name := "data", tag := "Subgoal I,", title := ""},
      {name := "proof", tag := "Subgoal II,", title := ""}
    ]
  }]
}

/-- Split the equivalence goal into its two directions `suffice` and `necess`.

Here is an example:
```lean
example {P : Prop} : P ↔ P := script
  split_iff
  | suffice h => exact h
  | necess h => exact h
```
-/
script_macro «split_iff» (kind := strategy)
"split_iff" => `(tactic| focus
  first
  | guard_target =~ (_ ↔ _)
  | fail "`split_iff` can only be used with `↔` propositions"
  apply Iff.intro <;> intro _
  set_goal_tags [`suffice, `necess]
)

script_info «split_iff» {
  template := [{
    lang := zh, tag := "目标拆解",
    introducer := {tag := "拆解", content := "拆分等价性为充分性和必要性"},
    cases := [
      {name := "suffice", tag := "充分性", title := ""},
      {name := "necess", tag := "必要性", title := ""}
    ]
  }, {
    lang := en, tag := "Goal Decomposition",
    introducer := {tag := "decompose", content := "Decompose the equivalence into sufficiency and necessity"},
    cases := [
      {name := "suffice", tag := "Sufficiency", title := ""},
      {name := "necess", tag := "Necessity", title := ""}
    ]
  }]
}

/-! ### Case Analysis on Disjunctions -/

script_macro «cases_by» (kind := strategy)
"cases_by" h:term => `(tactic| focus
  first
  | guard_expr (type_of% $h) =~ (_ ∨ _)
  | fail "`cases_by` can only be used with `∨` propositions"
  rcases $h:term with $(mkIdent `hp) | $(mkIdent `hq)
  set_goal_tags [`left, `right]
)

script_recorder «cases_by» => do
  withRollback do
    record_goal "$goal_before"
    record_param "h" h
    record_value "subject" (← recordValueFrom "subject" (expressionType h.raw))
  execute

script_info «cases_by» {
  template := [{
    lang := zh, tag := "分类讨论",
    introducer := {tag := "分类依据", content := "对命题 ${subject} 的不同情形分别讨论"},
    cases := [
      {name := "left", tag := "情形 I", title := ""},
      {name := "right", tag := "情形 II", title := ""}
    ]
  }, {
    lang := en, tag := "By cases,",
    introducer := {tag := "As the case distinction,", content := "consider the possible cases of ${subject}"},
    cases := [
      {name := "left", tag := "In Case I,", title := ""},
      {name := "right", tag := "In Case II,", title := ""}
    ]
  }]
}

script_macro «cases_by!» (kind := strategy)
"cases_by!" h:term => `(tactic| focus
  first
  | guard_expr (type_of% $h) =~ (_ ∨ _)
  | fail "`cases_by!` can only be used with `∨` propositions"
  -- Keep an existing hypothesis, or introduce a compound proof without splitting it yet.
  rcases $h:term with _
  -- Preserve context order, alias unfolding, and skipped impossible eliminations.
  run_tac do
    let leaves ← (← getMainGoal).casesRec fun declaration => do
      pure ((← whnf declaration.type).isAppOfArity ``Or 2)
    unless leaves.length ≥ 2 do
      throwError "unexpected error occurred during executing `cases_by!`"
    setGoals leaves
  set_goal_tags' fun i => Name.mkSimple ("goal" ++ (i + 1).toRoman)
)

script_info «cases_by!» {
  renderer := «strategy»
}

/-! ### Case Analysis on Propositions or Inductive Types -/

script_elab «cases_on» (kind := strategy)
"cases_on" value:term => withMainContext do
  let (_valueExpr, valueType) ← do
    let valueExpr ← elabTerm value none
    pure (valueExpr, ← whnf <| ← inferType valueExpr)
  if valueType == .sort .zero then
    evalTactic <| ← `(tactic| open Classical in
      by_cases h : $value:term)
    evalTactic (← `(tactic| set_goal_tags [`true, `false]))
  else if ← isProp valueType then
    throwError "`cases_on` cannot be used on a proof of a proposition; pass the proposition itself"
  else
    evalTactic <| ← `(tactic| cases $value:term)

script_info «cases_on» {
  renderer := «strategy»
}

/-! ### Proof by Contradiction -/

script_macro «contra» (intro := [h], kind := strategy)
"contra" h:ident => `(tactic| focus
  first
  | guard_target =~ (_ → False)
    intro _
    rename_i $h:ident
  | by_contra $h
  set_goal_tags [`proof]
)

script_recorder «contra» => do
  record_goal "$goal_before"
  execute
  withRollback <| withMainContext do
    let some localDecl := (← getLCtx).findFromUserName? h.getId
    | throwError "contra did not introduce `{h.getId}`"
    let hypothesis ← recordValueFrom "hypothesis" <| recordExpression localDecl.type
    record_value "hypothesis" hypothesis

script_info «contra» {
  color := (some (163, 59, 69), some (221, 176, 180), some (252, 242, 242)),
  template := [{
    lang := zh, tag := "反证法",
    inline := true,
    introducer := {tag := "假设", content := "假设 ${hypothesis}，推得矛盾"},
    cases := [{name := "proof", tag := "", title := ""}]
  }, {
    lang := en, tag := "By contradiction,",
    inline := true,
    introducer := {tag := "For the contrary assumption,", content := "suppose ${hypothesis} and derive a contradiction."},
    cases := [{name := "proof", tag := "", title := ""}]
  }]
}

/-- Use induction on a natural number. -/
script_macro «induction» (kind := strategy)
"induction" n:ident => `(tactic|
  induction $n:ident
)

script_info «induction» {
  color := (some (43, 106, 74), some (163, 194, 177), some (242, 247, 244)),
  template := [{
    lang := zh, tag := "数学归纳法",
    introducer := {tag := "归纳对象", content := "对变量 ${n} 使用数学归纳法"},
    cases := [
      {name := "zero", tag := "基础情形", title := "验证命题对 $0$ 成立"},
      {name := "succ", tag := "归纳步骤", title := "假设命题对 $k$ 成立, 下面证明命题对 $k+1$ 成立"}
    ]
  }, {
    lang := en, tag := "Induction",
    introducer := {tag := "variable", content := "on the natural number ${n}, apply mathematical induction."},
    cases := [
      {name := "zero", tag := "In the base case,", title := "verify that the proposition holds for $0$"},
      {name := "succ", tag := "In the inductive step,", title := "suppose the proposition holds for $k$, then prove it for $k+1$"}
    ]
  }]
}

private theorem strongInductionOn {motive : Nat → Prop}
    (zero : motive 0) (t : Nat)
    (succ : (n : Nat) → ((m : Nat) → m < n.succ → motive m) → motive n.succ)
  : motive t
:= Nat.strongRecOn t <| fun n ih =>
    match n with
    | 0    => zero
    | n + 1 => succ n ih

/-- Use complete induction on a natural number. -/
script_macro «completeInduction» (kind := strategy)
"complete_induction" n:ident => `(tactic|
  induction $n:ident using strongInductionOn
)

script_info «completeInduction» {
  color := (some (97, 81, 154), some (189, 179, 216), some (246, 243, 250)),
  template := [{
    lang := zh, tag := "强归纳法",
    introducer := {tag := "归纳对象", content := "对自然数 ${n} 使用强数学归纳法。"},
    cases := [
      {name := "zero", tag := "基础情形", title := "验证命题对 $0$ 成立"},
      {name := "succ", tag := "归纳步骤", title := "假设命题对所有小于 $k+1$ 的自然数成立，证明 $k+1$ 的情形"}
    ]
  }, {
    lang := en, tag := "Strong induction",
    introducer := {tag := "variable", content := "on the natural number ${n}, apply strong induction."},
    cases := [
      {name := "zero", tag := "In the base case,", title := "verify the proposition for $0$"},
      {name := "succ", tag := "In the inductive step,", title := "suppose the proposition holds for all smaller numbers, then prove it for $k+1$"}
    ]
  }]
}

/-! ### Arbitrary Constructor -/

local elab "check_exclusive_ctor" : tactic => do evalTactic <| ← `(tactic| focus
  first
  | fail_if_success guard_target =~ (_ ∧ _)
  | fail "`constructor` cannot be used for `∧`; use `split_and`"
  first
  | fail_if_success guard_target =~ (_ ↔ _)
  | fail "`constructor` cannot be used for `↔`; use `split_iff`"
  first
  | fail_if_success guard_target =~ (∃ _, _)
  | fail "`constructor` cannot be used for `∃`; use `witness`"
  first
  | fail_if_success guard_target =~ (_ ∨ _)
  | fail "`constructor` cannot be used for `∨`; use `left` or `right`"
)

script_macro «constructor» (kind := strategy)
"constructor" => `(tactic| check_exclusive_ctor; constructor)

script_info «constructor» {
  renderer := «strategy»,
  color := (some (162, 100, 35), some (223, 195, 157), some (253, 248, 238))
}

script_elab «constructor!» (kind := strategy)
"constructor!" ctor:term => focus <| withMainContext do
  evalTactic (← `(tactic| check_exclusive_ctor))
  let ctorExpr ← elabTerm ctor none
  let some (ctorName, _) := ctorExpr.getAppFn.const?
  | throwErrorAt ctor "the named constructor must be a constructor constant"
  let some ctorInfo ← isCtor? ctorName
  | throwErrorAt ctor m!"`{ctorName}` is not a constructor"
  -- Reuse `apply`'s elaborator without changing its original failure wording.
  evalApplyLikeTactic (fun goal expression => goal.apply expression) (← Term.exprToSyntax ctorExpr)
  let fieldNames := ctorInfo.type.getForallBinderNames.drop ctorInfo.numParams
  let oldNames ← (← getGoals).mapM (·.getTag)
  -- Preserve the existing assignment for partial constructors and any extra goals.
  let names := fieldNames.take oldNames.length ++ oldNames.drop fieldNames.length
  evalTactic (← `(tactic| set_goal_tags $(quote names)))

script_info «constructor!» {
  renderer := «strategy»,
  color := (some (162, 100, 35), some (223, 195, 157), some (253, 248, 238))
}

/-! ## Calculation Chains -/

script_macro «renderCalc»
"calc" steps:calcSteps => `(tactic| calc $steps)

/-- Recorder for `_script_calc`: record the initial term and every chain step.
    `init` is the left side of the first relation; `chain` contains
    `{relation, rhs, proof}` entries, with proofs containing `?_` recorded as holes. -/
script_recorder «renderCalc» => do
  record_goal "$goal_before"
  -- Replay native step elaboration in temporary state, retaining each expected
  -- type and proof. Temporary goals, nested recordings, and info trees are
  -- discarded before the original script executes below.
  let (init, chain) ← Tactic.withoutModifyingState' do
    let views ← Term.mkCalcStepViews steps
    let target := (← getMainGoalExpr).consumeMData
    let entries ← runTermElab do
      let mut result? : Option (Expr × Expr) := none
      let mut previousRhs? : Option Expr := none
      let mut entries := #[]
      for view in views do
        let term ← match previousRhs? with
          | some rhs => Term.annotateFirstHoleWithType view.term (← inferType rhs)
          | none => pure view.term
        let type ← Term.elabType term
        let some (_, lhs, rhs) ← Term.getCalcRelation? type
          | throwErrorAt view.term "invalid 'calc' step, relation expected{indentExpr type}"
        if let some previousRhs := previousRhs? then
          unless ← isDefEqGuarded lhs previousRhs do
            throwErrorAt view.term "invalid 'calc' step, left-hand side is{indentD m!"{lhs} : {← inferType lhs}"}\n\
              but previous right-hand side is{indentD m!"{previousRhs} : {← inferType previousRhs}"}"
        let proof ← withFreshMacroScope <| Term.elabTermEnsuringType view.proof type
        result? := some <| ← match result? with
          | some (result, resultType) => do
            Term.synthesizeSyntheticMVarsUsingDefault
            withRef view.term <| Term.mkCalcTrans result resultType proof type
          | none => pure (proof, type)
        previousRhs? := some rhs
        entries := entries.push (type, proof)
      Term.synthesizeSyntheticMVarsUsingDefault
      let (result, resultType) := result?.get!
      unless ← isDefEq resultType target do
        -- Native calc may add a final step. Reproduce its unifications without
        -- adding that implicit step to the recorded chain.
        if let some (_, lhs, rhs) ← Term.getCalcRelation? resultType then
          if let some (relation, targetLhs, targetRhs) ← Term.getCalcRelation? target then
            if ← isDefEq lhs targetLhs <&&> isDefEq (← inferType rhs) (← inferType targetLhs) then
              let lastType := mkApp2 relation rhs targetRhs
              let lastProof ← mkFreshExprSyntheticOpaqueMVar lastType
              try
                let (_, type) ← Term.mkCalcTrans result resultType lastProof lastType
                discard <| isDefEq type target
              catch _ => pure ()
      return entries
    let some (_, lhs, _) ← Term.getCalcRelation? (← instantiateMVars entries[0]!.1)
      | throwError "calc: cannot extract the initial relation"
    let init ← recordExpression lhs
    let chain ← (views.zip entries).mapM fun (view, type, proof) => do
      let some (rel, _, rhs) ← Term.getCalcRelation? (← instantiateMVars type)
        | throwErrorAt view.term "calc: cannot extract a binary relation from the step"
      let proof ← if containsSyntheticHole view.proof.raw then
          pure (RecordedValue.object [("kind", .plain (json% "hole"))])
        else recordExpression proof
      return RecordedValue.object [
        ("relation", ← recordExpression rel),
        ("rhs", ← recordExpression rhs), ("proof", proof)]
    return (init, chain)
  record_value "init" init
  record_value "chain" chain
  execute
  record_goal "$goal_after"

script_info «renderCalc» {
  renderer := «calc»
}

/-! ## Inference Chains -/

/-! Follow the native `calc` layout: the first step is wrapped in its own
    `withPosition` and the remaining steps share a second `withPosition` that
    re-anchors at the second step's column. This lets the second step sit at a
    shallower column than the first, while still distinguishing subsequent
    steps from following tactics. -/

syntax inferArrow := " => " <|> " ⇒ "
syntax inferFirstStep := ppIndent(colGe term inferArrow (atomic(ident " : "))? term " := " term)
syntax inferStep := ppIndent(colGe inferArrow (atomic(ident " : "))? term " := " term)
syntax inferSteps := ppLine withPosition(inferFirstStep) withPosition((ppLine linebreak inferStep)*)

/-- Tactic proofs own their holes; only ordinary terms use inference placeholders. -/
private partial def inferIsTacticProof (stx : Syntax) : Bool :=
  match stx with
  | `(term| by $_) => true
  | `(term| ($proof:term)) => inferIsTacticProof proof.raw
  | _ => false

open Lean.Meta in
/-- Recursively find a subexpression of `e` whose type is definitionally equal
    to `targetType`. Instantiate binders with `withLocalDecl`/`withLetDecl`
    before traversing their bodies so bound variables remain well-scoped. -/
private partial def inferFindSubtermOfType  (e : Expr) (targetType : Expr)
    : MetaM Bool := do
  let e ← instantiateMVars e
  let checkSelf : MetaM Bool :=
    try
      let ty ← inferType e
      isDefEqGuarded ty targetType
    catch _ => pure false
  if ← checkSelf then return true
  match e with
  | .app f a => return (← inferFindSubtermOfType f targetType) || (← inferFindSubtermOfType a targetType)
  | .lam _ t b bi =>
      if ← inferFindSubtermOfType t targetType then return true
      withLocalDecl `infer_x bi t fun x => inferFindSubtermOfType (b.instantiate1 x) targetType
  | .letE _ t v b _ =>
      if ← inferFindSubtermOfType t targetType then return true
      if ← inferFindSubtermOfType v targetType then return true
      withLetDecl `infer_x t v fun x => inferFindSubtermOfType (b.instantiate1 x) targetType
  | .forallE _ t b bi =>
      if ← inferFindSubtermOfType t targetType then return true
      withLocalDecl `infer_x bi t fun x => inferFindSubtermOfType (b.instantiate1 x) targetType
  | .mdata _ b => inferFindSubtermOfType b targetType
  | .proj _ _ b => inferFindSubtermOfType b targetType
  | _ => pure false

open Term in
/-- Elaborate the first `P => Q := prf` step as a proof of `Q`, and ensure
    that it contains a proof of `P`; otherwise the initial proposition is meaningless. -/
local elab "infer_check_first" P:term " => " Q:term " := " prf:term : term => do
  if !inferIsTacticProof prf.raw && containsSyntheticHole prf.raw then
    throwErrorAt prf "infer: the first step cannot contain '?_'; provide a proof of the initial proposition"
  let pType ← elabType P
  let qType ← elabType Q
  let prfExpr ← elabTermEnsuringType prf qType
  synthesizeSyntheticMVarsNoPostponing
  let prfExpr ← instantiateMVars prfExpr
  unless ← inferFindSubtermOfType prfExpr pType do
    let pStr := (Syntax.reprint P.raw).getD "?" |>.trimAscii
    throwErrorAt prf s!"infer: the first step must contain a proof of proposition '{pStr}'"
  return prfExpr

/-- Replace the unique `?_` in `stx` with `rep` and return the resulting syntax
    together with the number of holes encountered. -/
private partial def inferReplaceHole (stx : Syntax) (rep : TSyntax `term) : StateT Nat MacroM Syntax := do
  if stx.getKind == ``Parser.Term.syntheticHole then
    modify (· + 1)
    return rep.raw
  else
    let args ← stx.getArgs.mapM fun a => inferReplaceHole a rep
    if args == stx.getArgs then return stx
    else return Syntax.node stx.getHeadInfo stx.getKind args

/-- Replace exactly one `?_` in `stx`; otherwise report an error. -/
private def inferReplaceSingleHole  (stx : Syntax)
                                    (rep : TSyntax `term)
                                    : MacroM (TSyntax `term) := do
  let (stx', count) ← (inferReplaceHole stx rep).run 0
  if count != 1 then
    Macro.throwErrorAt stx s!"infer: each chain step must contain exactly one '?_', but found {count}"
  return ⟨stx'⟩

/-- Expand an `infer` chain into successive optionally named `have`s. Each step is
    added to the local context. Later terms use `?_` for the preceding result;
    tactic proofs instead receive a local `this` and keep native hole semantics.
    The final result is only attempted as a goal-closing term. -/
private def buildInferTactic (steps : Syntax) : MacroM (TSyntax `tactic) := do
  let mut tactics : Array Syntax := #[]
  let firstStep := steps[0]
  let restSteps := steps[1]
  let `(inferFirstStep| $P:term $_arrow:inferArrow $[$firstLabel:ident :]? $Q:term := $proof0:term) := firstStep
  | Macro.throwError "infer: invalid first-step syntax"
  let firstProof ← `(term| infer_check_first $P:term => $Q:term := $proof0:term)
  let firstName ← withFreshMacroScope <|
    MonadQuotation.addMacroScope `this
  let firstId : TSyntax `ident := firstLabel.getD ⟨mkIdent firstName⟩
  tactics := tactics.push (← `(tactic| have $firstId:ident : $Q:term := $firstProof:term)).raw
  let mut previous ← `(term| $firstId:ident)
  for step in restSteps.getArgs do
    let `(inferStep| $_arrow:inferArrow $[$label:ident :]? $R:term := $proof:term) := step
    | Macro.throwError "infer: invalid chain-step syntax"
    let proof' ← if inferIsTacticProof proof.raw then do
      -- Deliberately expose this alias to user syntax, only inside this proof.
      let thisId := mkIdentFrom proof `this
      `(term| let $thisId:ident := $previous; $proof)
    else
      inferReplaceSingleHole proof.raw previous
    let stepName ← withFreshMacroScope <|
      MonadQuotation.addMacroScope `this
    let stepId : TSyntax `ident := label.getD ⟨mkIdent stepName⟩
    tactics := tactics.push (← `(tactic| have $stepId:ident : $R:term := $proof':term)).raw
    previous ← `(term| $stepId:ident)
  tactics := tactics.push (← `(tactic| try exact $previous:term)).raw
  let seq : TSyntax ``Parser.Tactic.tacticSeq := ⟨buildTacticSeq tactics⟩
  `(tactic| ($seq:tacticSeq))

/-- Parse `inferSteps` and extract the initial proposition and each step.
    Returns `(initial proposition, [(right-hand proposition, proof term)])`. -/
private def parseInferSteps (steps : Syntax)
    : MacroM (TSyntax `term × Array (TSyntax `term × TSyntax `term)) := do
  -- The actual structure is `inferFirstStep (ppLine linebreak inferStep)*`.
  let firstStep := steps[0]
  let restSteps := steps[1]
  let `(inferFirstStep| $init:term $_arrow:inferArrow $[$_firstLabel:ident :]? $Q:term := $prf1:term) := firstStep
  | Macro.throwError s!"infer: invalid first-step syntax, kind: {firstStep.getKind}"
  let mut chain := #[(Q, prf1)]
  for i in [:restSteps.getArgs.size] do
    let step := restSteps[i]
    let `(inferStep| $_arrow:inferArrow $[$_label:ident :]? $R:term := $prf:term) := step
    | Macro.throwError s!"infer: invalid chain-step syntax, kind: {step.getKind}"
    chain := chain.push (R, prf)
  return (init, chain)

script_macro «infer»
"infer" steps:inferSteps => buildInferTactic steps.raw

script_recorder «infer» => do
  let (init, chain) ← liftMacroM <| parseInferSteps steps
  let recordChain : TacticM RecordedValue := do
    let mut values := #[]
    for i in [:chain.size] do
      let (rhs, prf) := chain[i]!
      let rhsExpr ← elabTerm rhs none
      let proof ←
        -- Later tactic proofs need a preceding result that does not exist at this phase.
        if containsSyntheticHole prf.raw || (i > 0 && inferIsTacticProof prf.raw) then
          pure (.object [("kind", .plain (toJson "hole"))])
        else
          recordExpression (← elabTerm prf (some rhsExpr))
      values := values.push <| .object [
        ("rhs", ← recordExpression rhsExpr),
        ("proof", proof)
      ]
    return .array values
  withRollback do
    record_goal "$goal_before"
    record_value "init" (← expression init.raw)
    record_value "chain" (← recordChain)
  execute
  record_goal "$goal_after"

script_info «infer» {
  renderer := «infer»
}

macro "infer" steps:inferSteps : term => `(term| script infer $steps)

/-! # Mathlib Native Tactics -/

open Lean Parser Mathlib Tactic

/- Compound Mathlib argument parsers do not expose a stable `RecordValue`
   representation. Their presentations do not consume those arguments, so the
   wrappers below use handwritten recorders that retain the common goal
   snapshots while executing the original tactic unchanged. -/

script_macro «continuity»
"continuity" => `(tactic| continuity)

script_macro «exact_mod_cast» (clear := [proof])
"exact_mod_cast" proof:term => `(tactic| exact_mod_cast $proof:term)

script_macro «field» (clear := [args])
"field" args:(simpArgs)? => `(tactic| field $[$args:simpArgs]?)

script_macro «gcongr»
"gcongr" template:(ppSpace colGt term)? names:("with" (ppSpace colGt rintroPat)*)? =>
  match names with
  | none => `(tactic| gcongr $[$template]?)
  | some withNames =>
      let patterns : Array (Lean.TSyntax `rintroPat) :=
        withNames.raw.getArgs[1]!.getArgs.map (fun stx => ⟨stx⟩)
      `(tactic| gcongr $[$template]? with $patterns*)

script_recorder «gcongr» => do
  record_goal "$goal_before"
  execute
  record_goal "$goal_after"

declare_syntax_cat scriptITautoArgs
syntax "*" : scriptITautoArgs
syntax "[" term,* "]" : scriptITautoArgs

script_macro «itauto»
"itauto" args:(scriptITautoArgs)? =>
  match args with
  | some arg =>
      if arg.raw.getArgs[0]!.isAtom then `(tactic| itauto *)
      else
        match arg with
        | `(scriptITautoArgs| [$terms,*]) => `(tactic| itauto [$terms,*])
        | _ => Lean.Macro.throwUnsupported
  | none => `(tactic| itauto)

script_recorder «itauto» => do
  record_goal "$goal_before"
  execute
  record_goal "$goal_after"

script_macro «itauto!»
"itauto!" args:(scriptITautoArgs)? =>
  match args with
  | some arg =>
      if arg.raw.getArgs[0]!.isAtom then `(tactic| itauto! *)
      else
        match arg with
        | `(scriptITautoArgs| [$terms,*]) => `(tactic| itauto! [$terms,*])
        | _ => Lean.Macro.throwUnsupported
  | none => `(tactic| itauto!)

script_recorder «itauto!» => do
  record_goal "$goal_before"
  execute
  record_goal "$goal_after"

script_macro «linarith»
"linarith" args:linarithArgsRest => `(tactic| linarith $args:linarithArgsRest)

script_recorder «linarith» => do
  record_goal "$goal_before"
  execute
  record_goal "$goal_after"

script_macro «linarith!»
"linarith!" args:linarithArgsRest => `(tactic| linarith! $args:linarithArgsRest)

script_recorder «linarith!» => do
  record_goal "$goal_before"
  execute
  record_goal "$goal_after"

script_macro «measurability»
"measurability" => `(tactic| measurability)

script_macro «nlinarith»
"nlinarith" args:linarithArgsRest => `(tactic| nlinarith $args:linarithArgsRest)

script_recorder «nlinarith» => do
  record_goal "$goal_before"
  execute
  record_goal "$goal_after"

script_macro «nlinarith!»
"nlinarith!" args:linarithArgsRest => `(tactic| nlinarith! $args:linarithArgsRest)

script_recorder «nlinarith!» => do
  record_goal "$goal_before"
  execute
  record_goal "$goal_after"

script_macro «norm_cast»
"norm_cast" loc:(location)? => `(tactic| norm_cast $[$loc:location]?)

script_macro «norm_num»
"norm_num" cfg:optConfig onlyFlag:("only")?
    args:(simpArgs)? loc:(location)? =>
  match onlyFlag with
  | none => `(tactic| norm_num $cfg:optConfig $[$args:simpArgs]? $[$loc:location]?)
  | some _ => `(tactic| norm_num $cfg:optConfig only $[$args:simpArgs]? $[$loc:location]?)

script_recorder «norm_num» => do
  record_goal "$goal_before"
  execute
  record_goal "$goal_after"

script_macro «positivity»
"positivity" => `(tactic| positivity)

script_macro «push_cast»
"push_cast" cfg:optConfig disch:(discharger)?
    onlyFlag:("only")? lemmas:(simpArgs)?
    loc:(location)? => do
  let base ← match onlyFlag with
    | none => `(tactic| push_cast $cfg:optConfig $[$disch:discharger]? $[$loc:location]?)
    | some _ => `(tactic| push_cast $cfg:optConfig $[$disch:discharger]? only $[$loc:location]?)
  match lemmas with
  | none => pure base
  | some args =>
      let parts := base.raw.getArgs
      let withLemmas := parts.set! 4 args.raw
      pure (Lean.Syntax.node base.raw.getHeadInfo base.raw.getKind withLemmas)

script_recorder «push_cast» => do
  record_goal "$goal_before"
  execute
  record_goal "$goal_after"

script_macro «qify»
"qify" args:(simpArgs)? loc:(location)? =>
  `(tactic| qify $[$args:simpArgs]? $[$loc:location]?)

script_macro «rify»
"rify" args:(simpArgs)? loc:(location)? =>
  `(tactic| rify $[$args:simpArgs]? $[$loc:location]?)

script_macro «ring»
"ring" => `(tactic| ring)

script_macro «ring!»
"ring!" => `(tactic| ring!)

script_macro «ring_nf»
"ring_nf" cfg:optConfig loc:(location)? =>
  `(tactic| ring_nf $cfg:optConfig $[$loc:location]?)

script_macro «ring_nf!»
"ring_nf!" cfg:optConfig loc:(location)? =>
  `(tactic| ring_nf! $cfg:optConfig $[$loc:location]?)

script_macro «tauto»
"tauto" => `(tactic| tauto)

script_macro «tauto_set»
"tauto_set" => `(tactic| tauto_set)

declare_syntax_cat scriptWlogGeneralizing
syntax "generalizing" (ppSpace colGt ident)* : scriptWlogGeneralizing
declare_syntax_cat scriptWlogWith
syntax "with" ident : scriptWlogWith

script_macro «wlog»
"wlog" h:ident ":" proposition:term vars:(scriptWlogGeneralizing)?
    hypothesis:(scriptWlogWith)? =>
  let generalizingArgs := vars.map (fun stx => stx.raw.getArgs)
  let xs : Array (Lean.TSyntax `ident) :=
    (generalizingArgs.map (fun args => args[1]!.getArgs)).getD #[] |>.map (fun stx => ⟨stx⟩)
  let H : Option (Lean.TSyntax `ident) := hypothesis.map (fun stx => ⟨stx.raw.getArgs[1]!⟩)
  match vars, H with
  | none, none => `(tactic| wlog $h:ident : $proposition:term)
  | some _, none => `(tactic| wlog $h:ident : $proposition:term generalizing $xs*)
  | none, some name => `(tactic| wlog $h:ident : $proposition:term with $name:ident)
  | some _, some name =>
      `(tactic| wlog $h:ident : $proposition:term generalizing $xs* with $name:ident)

script_recorder «wlog» => do
  record_goal "$goal_before"
  execute
  record_goal "$goal_after"

script_macro «wlog!»
"wlog!" cfg:optConfig h:ident ":" proposition:term
    vars:(scriptWlogGeneralizing)? hypothesis:(scriptWlogWith)? =>
  let generalizingArgs := vars.map (fun stx => stx.raw.getArgs)
  let xs : Array (Lean.TSyntax `ident) :=
    (generalizingArgs.map (fun args => args[1]!.getArgs)).getD #[] |>.map (fun stx => ⟨stx⟩)
  let H : Option (Lean.TSyntax `ident) := hypothesis.map (fun stx => ⟨stx.raw.getArgs[1]!⟩)
  match vars, H with
  | none, none => `(tactic| wlog! $cfg:optConfig $h:ident : $proposition:term)
  | some _, none => `(tactic| wlog! $cfg:optConfig $h:ident : $proposition:term generalizing $xs*)
  | none, some name => `(tactic| wlog! $cfg:optConfig $h:ident : $proposition:term with $name:ident)
  | some _, some name =>
      `(tactic| wlog! $cfg:optConfig $h:ident : $proposition:term generalizing $xs* with $name:ident)

script_recorder «wlog!» => do
  record_goal "$goal_before"
  execute
  record_goal "$goal_after"

script_macro «zify»
"zify" args:(simpArgs)? loc:(location)? =>
  `(tactic| zify $[$args:simpArgs]? $[$loc:location]?)

script_info «continuity» {
  template := [{
    lang := zh, tag := "连续性",
    content := ""
  }, {
    lang := en, tag := "«continuity»",
    content := ""
  }]
}

script_info «exact_mod_cast» {
  template := [{
    lang := zh, tag := "«exact_mod_cast»",
    content := ""
  }, {
    lang := en, tag := "«exact_mod_cast»",
    content := ""
  }]
}

script_info «field» {
  template := [{
    lang := zh, tag := "域算术",
    content := ""
  }, {
    lang := en, tag := "«field»",
    content := ""
  }]
}

script_info «measurability» {
  template := [{
    lang := zh, tag := "可测性",
    content := ""
  }, {
    lang := en, tag := "«measurability»",
    content := ""
  }]
}

script_info «positivity» {
  template := [{
    lang := zh, tag := "正性",
    content := ""
  }, {
    lang := en, tag := "«positivity»",
    content := ""
  }]
}

script_info «ring» {
  template := [{
    lang := zh, tag := "环算术",
    content := ""
  }, {
    lang := en, tag := "«ring»",
    content := ""
  }]
}

script_info «tauto» {
  template := [{
    lang := zh, tag := "重言",
    content := ""
  }, {
    lang := en, tag := "«tauto»",
    content := ""
  }]
}

script_info «tauto_set» {
  template := [{
    lang := zh, tag := "重言",
    content := ""
  }, {
    lang := en, tag := "«tauto_set»",
    content := ""
  }]
}


#page end
