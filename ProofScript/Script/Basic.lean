import ProofScript.Script.Command
import ProofScript.Info.Theorem
import ProofScript.Script.Script
import ProofScript.Script.Record
import ProofScript.Page.Component.Core
import ProofScript.Page.Component.Latex

open Lean Meta Parser Elab Tactic
open ProofScript

script_macro «assumption»
"assumption" => `(tactic| assumption)

script_macro «change»
"change" equation:term loc:(location)? => `(tactic|
  change $equation $[$loc:location]?
)

script_macro «contradiction»
"contradiction" => `(tactic| contradiction)

script_macro «exfalso»
"exfalso" => `(tactic| exfalso)

script_macro «omega»
"omega" => `(tactic| omega)

script_macro «rfl»
"rfl" => `(tactic| rfl)

script_macro «symm»
"symm" => `(tactic| symm)

script_macro «trivial»
"trivial" => `(tactic| trivial)

script_macro «simp» (params := [config(timing := once), args(timing := before)])
"simp" config:optConfig args:simpArgs loc:(location)? =>
  match args with
  | `(simpArgs| [$rules,*]) => `(tactic|
      simp $config:optConfig only [$rules,*] $[$loc:location]?)
  | _ => Macro.throwUnsupported

script_macro «rw» (params := [config(timing := once), rules(timing := before)])
"rw" config:optConfig rules:rwRuleSeq loc:(location)? => `(tactic|
  rw $config:optConfig $rules:rwRuleSeq $[$loc:location]?
)

script_macro «unfold»
"unfold" definitions:(colGt ident)+ => `(tactic|
  unfold $definitions*
)

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
  let (_, rest) ← rest.intro1P
  replaceMainGoal [rest]

script_elab «exact»
"exact" value:term => withMainContext do
  let goal ← getMainGoal
  let expression ← Elab.Tactic.elabTermEnsuringType value <| ← goal.getType
  let expression ← instantiateMVars expression
  rejectProofParameters value expression
  goal.assign expression
  replaceMainGoal []

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

script_elab «exact_proj»
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

script_elab «left»
"left" => withMainContext do
  let goal ← getMainGoal
  let goalExpr ← whnf <| ← goal.getType
  unless goalExpr.isAppOfArity ``Or 2 do
    throwError "`left` can only be used with propositions connected by `∨`"
  let newMVarIds ← goal.apply (mkConst ``Or.inl)
  replaceMainGoal newMVarIds

script_elab «right»
"right" => withMainContext do
  let goal ← getMainGoal
  let goalExpr ← whnf <| ← goal.getType
  unless goalExpr.isAppOfArity ``Or 2 do
    throwError "`right` can only be used with propositions connected by `∨`"
  let newMVarIds ← goal.apply (mkConst ``Or.inr)
  replaceMainGoal newMVarIds

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

script_elab «obtain_exist'» (intro := [h₁, h₂, h₃], clear := [h])
"obtain_exist" "⟨" h₁:ident "," h₂:ident "," h₃:ident "⟩" ":=" h:term => do
  -- Keep the intermediate proof off user binder source spans and out of recording.
  let proof := mkIdent <| ← mkFreshUserName `existBody
  evalTactic <| ← `(tacticSeq|
    script_obtain_exist ⟨$h₁, $proof⟩ := $h
    script_unpack_and ⟨$h₂, $h₃⟩ := $proof
  )

script_elab «funext»
"funext" arg:ident => withMainContext do
  let xName := arg.getId
  let target ← whnf <| ← GetGoal
  unless target.isAppOfArity ``Eq 3 do
    throwError "`funext` can only be used on function equality goals"
  let lhsType ← whnf <| ← inferType (target.getArg! 1)
  let rhsType ← whnf <| ← inferType (target.getArg! 2)
  match lhsType, rhsType with
  | .forallE _ domain _ _, .forallE _ domain' _ _ =>
    unless ← isDefEq domain domain' do
      throwError "`funext` requires both sides of the equality to have the same function domain"
    evalTactic <| ← `(tactic| funext $(mkIdent xName))
  | _, _ => throwError "`funext` can only be used on function equality goals"

script_elab «provide»
"provide" data:term => withMainContext do
  let goal ← getMainGoal
  let target ← whnf <| ← goal.getType
  let isWitnessDataGoal := match ← goal.getType with
    | .mdata data _ => data.getBool witnessDataGoalMDataKey false
    | _ => false
  if isWitnessDataGoal then
    evalTactic <| ← `(tactic| exact $data:term)
  else if target.isAppOfArity ``Exists 2 then
    evalTactic <| ← `(tactic| exists $data:term)
  else throwError "`provide` can only be used in the `data` branch of `witness` or on an existential goal"

script_elab «apply» (clear := [h])
"apply" h:term => withMainContext do
  let hExpr ← instantiateMVars <| ← Elab.Tactic.elabTermForApply h
  let hType ← whnf <| ← inferType hExpr
  let target ← whnf <| ← GetGoal
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

script_macro quot_induction (intro := [a])
"quot_induction" q:term "with" a:ident => `(tactic|
  refine Quot.inductionOn $q:term (fun $a:ident => ?_)
)

/-! ## Script-Strategy -/

/-! ### Assertions -/

script_elab «claim» (intro := [h], strategy := true, continuation := 1,
  params := [h(context := continuation)])
"claim" h:ident ":" type:term => withMainContext do
  let goal ← getMainGoal
  let type ← elabTerm type none
  let proofMVar ← mkFreshExprMVar type
  proofMVar.mvarId!.setTag `proof
  let restMVar ← goal.assert h.getId type proofMVar
  let (_, restMVar') ← restMVar.intro1P
  replaceMainGoal [proofMVar.mvarId!, restMVar']

open Term (addLocalVarInfo) in
private def claimExist (names : Array (TSyntax `ident)) (type : TSyntax `term) : TacticM Unit :=
    withMainContext do
  let goal ← getMainGoal
  let typeExpr ← elabTerm type none
  unless (← whnf typeExpr).isAppOfArity ``Exists 2 do
    throwErrorAt type "claim_exist requires an existential proposition (Exists)"
  let proofMVar ← mkFreshExprMVar typeExpr
  proofMVar.mvarId!.setTag `proof
  let asserted ← goal.assert (← mkFreshUserName `claimExist) typeExpr proofMVar
  let (existId, rest) ← asserted.intro1P
  let subgoal ← rest.withContext do
    let altNames := { varNames := [names[0]!.getId, names[1]!.getId] }
    let #[subgoal] ← rest.cases existId #[altNames]
      | throwError "unexpected error occurred during executing `claim_exist`"
    pure subgoal
  let #[first, second] := subgoal.fields
    | throwError "unexpected error occurred during executing `claim_exist`"
  subgoal.mvarId.withContext do
    addLocalVarInfo names[0]! first
    if names.size == 2 then
      addLocalVarInfo names[1]! second
  let rest ← if names.size == 2 then pure subgoal.mvarId else do
    let remainder := second.fvarId!
    let subgoal' ← subgoal.mvarId.withContext do
      unless (← whnf <| ← remainder.getType).isAppOfArity ``And 2 do
        throwErrorAt names[2]! "claim_exist requires a conjunction after the existential witness (And)"
      let altNames := { varNames := [names[1]!.getId, names[2]!.getId] }
      let #[subgoal'] ← subgoal.mvarId.cases remainder #[altNames]
        | throwError "unexpected error occurred during executing `claim_exist`"
      pure subgoal'
    subgoal'.mvarId.withContext do
      let #[left, right] := subgoal'.fields
        | throwError "unexpected error occurred during executing `claim_exist`"
      addLocalVarInfo names[1]! left
      addLocalVarInfo names[2]! right
    pure subgoal'.mvarId
  replaceMainGoal [proofMVar.mvarId!, rest]

script_elab «claimExistTwo» (intro := [h₁, h₂], strategy := true, continuation := 1,
  params := [h₁(context := continuation), h₂(context := continuation)])
"claim_exist" "⟨" h₁:ident "," h₂:ident "⟩" ":" type:term =>
  claimExist #[h₁, h₂] type

script_elab «claimExistThree» (intro := [h₁, h₂, h₃], strategy := true, continuation := 1,
  params := [h₁(context := continuation), h₂(context := continuation), h₃(context := continuation)])
"claim_exist" "⟨" h₁:ident "," h₂:ident "," h₃:ident "⟩" ":" type:term =>
  claimExist #[h₁, h₂, h₃] type

/-! ### Existential Construction -/

script_elab «witness» (strategy := true)
"witness" => withMainContext do
  let goal ← getMainGoal
  let goalExpr ← whnf <| ← goal.getType
  unless goalExpr.isAppOfArity ``Exists 2 do
    throwError "`witness` can only be used with `∃` propositions"
  let mvarIds ← goal.apply <| ← Meta.mkConstWithFreshMVarLevels ``Exists.intro
  match mvarIds with
  | [m₁, m₂] =>
    m₁.setTag `proof
    m₂.setTag `data
    let dataType ← m₂.getType
    m₂.setType (.mdata (Lean.MData.empty.setBool witnessDataGoalMDataKey true) dataType)
    replaceMainGoal [m₁, m₂]
  | _ =>
    throwError "unexpected error occurred during executing `witness`"

/-! ### Goal Decomposition: Conjunction -/

script_elab «split_and» (strategy := true)
"split_and" => withMainContext do
  let goal ← getMainGoal
  let goalExpr ← whnf <| ← goal.getType
  if !goalExpr.isAppOfArity ``And 2 then
    throwError "`split_and` can only be used with `∧` propositions"
  else
    let mvarIds ← goal.apply (mkConst ``And.intro)
    replaceMainGoal mvarIds

private partial def splitAndRec (mvarId : MVarId)
                                : MetaM (List MVarId) := do
  let goalExpr ← whnf <| ← mvarId.getType
  if goalExpr.isAppOfArity ``And 2 then
    let mvarIds ← mvarId.apply (mkConst ``And.intro)
    match mvarIds with
    | [m₁, m₂] =>
      let leftLeaves ← splitAndRec m₁
      let rightLeaves ← splitAndRec m₂
      return leftLeaves ++ rightLeaves
    | _ => return [mvarId]
  else
    return [mvarId]

script_elab «split_and!» (strategy := true)
"split_and!" => withMainContext do
  let goal ← getMainGoal
  let goalExpr ← whnf <| ← goal.getType
  unless goalExpr.isAppOfArity ``And 2 do
    throwError "`split_and!` can only be used with `∧` propositions"
  let leaves ← splitAndRec goal
  let mut i := 1
  for leaf in leaves do
    let tagName := Name.mkSimple s!"goal{toRoman i}"
    leaf.setTag tagName
    i := i + 1
  replaceMainGoal leaves

/-! ### Goal Decomposition: Equivalence -/

script_elab «split_iff» (strategy := true)
"split_iff" => withMainContext do
  let goal ← getMainGoal
  let goalExpr ← whnf <| ← goal.getType
  unless goalExpr.isAppOfArity ``Iff 2 do
    throwError "`split_iff` can only be used with `↔` propositions"
  let mvarIds ← goal.apply (mkConst ``Iff.intro)
  match mvarIds with
  | [m₁, m₂] =>
    let (_, m₁') ← m₁.intro `_
    let (_, m₂') ← m₂.intro `_
    m₁'.setTag `suffice
    m₂'.setTag `necess
    replaceMainGoal [m₁', m₂']
  | _ =>
    throwError "unexpected error occurred during executing `split_iff`"

/-! ### Case Analysis on Disjunctions -/

private def casesByProof (h : TSyntax `term) (tacticName : String) : TacticM (MVarId × FVarId) :=
    withMainContext do
  let proof ← instantiateMVars <| ← elabTerm h none
  let type ← inferType proof
  unless (← whnf type).isAppOfArity ``Or 2 do
    throwError "`{tacticName}` can only be used with `∨` propositions"
  let goal ← getMainGoal
  match proof with
  | .fvar id => return (goal, id)
  | _ =>
    let asserted ← goal.assert (← mkFreshUserName `casesByProof) type proof
    let (id, rest) ← asserted.intro1P
    return (rest, id)

script_elab «cases_by» (clear := [h], strategy := true)
"cases_by" h:term => withMainContext do
  let (goal, fvarId) ← casesByProof h "cases_by"
  let altNames := #[
    { varNames := [Name.mkSimple "hp"] },
    { varNames := [Name.mkSimple "hq"] }
  ]
  let subgoals ← goal.cases fvarId altNames
  match subgoals with
  | #[leftGoal, rightGoal] =>
      leftGoal.mvarId.setTag `left
      rightGoal.mvarId.setTag `right
      replaceMainGoal [leftGoal.mvarId, rightGoal.mvarId]
  | _ =>
    throwError "unexpected error occurred during executing `cases_by`"
script_recorder «cases_by» (fields := ProofScript.Recording.goalFields ++ #[
  { name := "h", schema := .expression },
  { name := "subject", schema := .expression, nullable := false }])
"cases_by" h:term "_strategy_cases" strategyCases:str => withMainContext do
  recordStrategy (strategyCases.getString.splitOn "\n")
    (before := #[
      ProofScript.Recording.param (.category `term) "h" h,
      { name := "subject", onFailure := .required,
        collectReferences := false, capture := ProofScript.Recording.expressionType h.raw }
    ])

script_elab «cases_by!» (clear := [h], strategy := true)
"cases_by!" h:term => withMainContext do
  let (goal, hId) ← casesByProof h "cases_by!"
  let leaves ← goal.casesRec fun declaration => do
    pure ((declaration.fvarId == hId) ||
      (← whnf declaration.type).isAppOfArity ``Or 2)
  unless leaves.length ≥ 2 do
    throwError "unexpected error occurred during executing `cases_by!`"
  let mut tagged : List MVarId := []
  let mut i := 1
  for leaf in leaves do
    leaf.setTag (Name.mkSimple s!"goal{toRoman i}")
    tagged := tagged ++ [leaf]
    i := i + 1
  replaceMainGoal tagged

/-! ### Case Analysis on Propositions or Inductive Types -/

script_elab «cases_on» (clear := [value], strategy := true)
"cases_on" value:term => withMainContext do
  let (_valueExpr, valueType) ← do
    let valueExpr ← elabTerm value none
    pure (valueExpr, ← whnf <| ← inferType valueExpr)
  if valueType == .sort .zero then
    evalTactic <| ← `(tactic| open Classical in
      by_cases h : $value:term)
    let goals ← getGoals
    match goals with
    | [trueGoal, falseGoal] =>
      trueGoal.setTag `true
      falseGoal.setTag `false
    | _ =>
      throwError "unexpected error occurred during executing `cases_on`"
  else if ← isProp valueType then
    throwError "`cases_on` cannot be used on a proof of a proposition; pass the proposition itself"
  else
    evalTactic <| ← `(tactic| cases $value:term)

/-! ### Proof by Contradiction -/

script_elab «contra» (intro := [h], strategy := true)
"contra" h:ident => withMainContext do
  let goal ← getMainGoal
  let isArrowToFalse :=
    match ← whnf <| ← goal.getType with
    | .forallE _ _ body _ => body.isConstOf ``False
    | _                   => false
  if isArrowToFalse then
    let (_, newMVarId) ← goal.intro h.getId
    newMVarId.setTag `proof
    replaceMainGoal [newMVarId]
  else
    evalTactic <| ← `(tactic| by_contra $h)
    let newMVarId ← getMainGoal
    newMVarId.setTag `proof
    replaceMainGoal [newMVarId]

script_recorder «contra» (fields := ProofScript.Recording.goalFields ++ #[
  { name := "h", schema := .expression },
  { name := "hypothesis", schema := .expression, nullable := false }])
"contra" h:ident "_strategy_cases" strategyCases:str => do
  recordStrategy (strategyCases.getString.splitOn "\n")
    (after := #[
      ProofScript.Recording.param (.category `ident) "h" h,
      { name := "hypothesis", onFailure := .required,
        collectReferences := false, capture := ProofScript.Recording.expressionType h.raw }
    ])

/-! ### Induction -/

script_macro «induction» (clear := [n], strategy := true)
"induction" n:ident => `(tactic|
  induction $n:ident
)

/-! ### Complete Induction -/

private theorem strongInductionOn {motive : Nat → Prop}
    (zero : motive 0) (t : Nat)
    (succ : (n : Nat) → ((m : Nat) → m < n.succ → motive m) → motive n.succ)
  : motive t
:= Nat.strongRecOn t <|
    fun n ih =>
      match n with
      | 0    => zero
      | n + 1 => succ n ih

script_macro «complete_induction» (clear := [n], strategy := true)
"complete_induction" n:ident => `(tactic|
  induction $n:ident using strongInductionOn
)

/-! ### Arbitrary Constructor -/

private def rejectOverlappingConstructor (target : Expr) : MetaM Unit := do
  let target ← whnf target
  if target.isAppOfArity ``And 2 then
    throwError "`constructor` cannot be used for `∧`; use `split_and`"
  if target.isAppOfArity ``Iff 2 then
    throwError "`constructor` cannot be used for `↔`; use `split_iff`"
  if target.isAppOfArity ``Exists 2 then
    throwError "`constructor` cannot be used for `∃`; use `witness`"
  if target.isAppOfArity ``Or 2 then
    throwError "`constructor` cannot be used for `∨`; use `left` or `right`"

script_elab «constructor» (strategy := true)
"constructor" => withMainContext do
  let goal ← getMainGoal
  rejectOverlappingConstructor <| ← goal.getType
  let goals ← goal.constructor
  replaceMainGoal goals

private partial def constructorFieldNames (type : Expr) : List Name :=
  match type with
  | .forallE name _ body _ => name :: constructorFieldNames body
  | _ => []

private def applyNamedConstructor (goal : MVarId)
                                  (ctor : TSyntax `term)
                                  : TacticM (List MVarId) := do
  let ctorExpr ← elabTerm ctor none
  let some (ctorName, _) := ctorExpr.getAppFn.const?
  | throwErrorAt ctor "the named constructor must be a constructor constant"
  let some ctorInfo ← isCtor? ctorName
  | throwErrorAt ctor m!"`{ctorName}` is not a constructor"
  let goals ← goal.apply ctorExpr
  let fieldNames := (constructorFieldNames ctorInfo.type).drop ctorInfo.numParams
  for (subgoal, name) in goals.zip fieldNames do
    subgoal.setTag name
  return goals

script_elab «constructor!» (strategy := true)
"constructor!" ctor:term => withMainContext do
  let goal ← getMainGoal
  rejectOverlappingConstructor <| ← goal.getType
  replaceMainGoal <| ← applyNamedConstructor goal ctor

/-! ## Metadata -/

/-! ### Remark -/

script_elab «remark» (clear := [text])
"remark" text:str => fun _ => pure ()

/-! ### SVG -/

script_elab «svg» (clear := [code])
"svg" code:str => fun _ => pure ()

/-! LaTeX (Compiled to SVG) -/

script_elab «latex»
"latex" _metadata:componentMeta _code:str => fun _ => pure ()

script_recorder «latex» (fields := ProofScript.Recording.goalFields ++ #[
  { name := "metadata", schema := .json, nullable := false },
  { name := "language", schema := .string, nullable := false },
  { name := "source", schema := .string, nullable := false },
  { name := "svg", schema := .json, nullable := false }])
"latex" metadata:componentMeta code:str => ProofScript.Recording.withRecordingStep fun step => do
  step.recordGoal "goal_before"
  let metadata ←
    match parseComponentMetadata metadata.raw with
    | .ok value => pure value
    | .error message => throwErrorAt metadata message
  let svg ←
    writeTextResource "svg" "svg" "image/svg+xml" <| ←
      compileLatexToSvg code.getString
  step.recordJson "metadata" (componentMetadataJson metadata)
  step.recordJson "language" "latex"
  step.recordJson "source" (Json.str code.getString)
  step.recordJson "svg" svg
  executeRecordedStep
  step.recordGoal "goal_after"

/-! Informal Proof -/

script_elab «admit» (clear := [reason])
"admit" reason:str => do
  let goal ← getMainGoal
  let target ← goal.getType
  evalTactic <| ← `(tactic| admit)

macro "admit" reason:str : term => `(term| script admit $reason:str)

/-! ### Manual Citation -/

private def citeTheorem (thm : TSyntax `term) : TacticM Unit := withMainContext do
  let expression ← instantiateMVars <| ← elabTerm thm none
  let some (declaration, _) := expression.getAppFn.const?
  | throwErrorAt thm "`cite` requires a theorem declaration"
  let env ← getEnv
  match Info.resolveTheoremInfo env { moduleName := env.mainModule } declaration with
  | .error error =>
    if error.message == "theorem metadata is not configured" then
      throwErrorAt thm m!"`{declaration}` is not a literature theorem"
    else throwErrorAt thm error.render
  | .ok _ => pure ()
  unless ← referencesEnabled do return
  for constant in Expr.getUsedConstants expression do
    addTheoremRef constant

script_elab «cite» (params := [thm(codec := expression, timing := once, field := "theorem", failure := required)])
"cite" thm:term => do citeTheorem thm; fun _ => pure ()

/-! ## Calculation Chains -/

script_macro «renderCalc»
"calc" steps:calcSteps => do
  `(tactic| calc $steps:calcSteps)

/-- Parse `calcSteps` into one `(relation term, proof term)` pair per step.
    The native structure is `calcFirstStep (calcStep)*` (see
    `Lean.Elab.Calc.mkCalcStepViews`). Unlike `infer`, a `calc` relation
    (`=`/`≤` and so on) is embedded in the relation term itself, so it is
    extracted syntactically and decomposed after elaboration. -/
private def parseCalcSteps  (steps : Syntax)
                            : MacroM (Array (TSyntax `term × TSyntax `term)) := do
  -- `calcSteps` has a first-step node followed by a `many` node of later steps.
  let firstStep := steps[0]
  let restSteps := steps[1]
  let first ← match firstStep with
              | `(calcFirstStep| $term:term := $proof:term) => pure (term, proof)
              | `(calcFirstStep| $term:term) =>
                  -- Without `:=`, complete the relation with `= _` and use `rfl`.
                  let rel : TSyntax `term ← `($term:term = _)
                  let rfl : TSyntax `term ← `(rfl)
                  pure (rel, rfl)
              | _ => Macro.throwError s!"calc: invalid first-step syntax (kind: {firstStep.getKind})"
  let mut out := #[first]
  for i in [:restSteps.getArgs.size] do
    let step := restSteps[i]
    let `(Lean.calcStep| $term:term := $proof:term) := step
    | Macro.throwError s!"calc: invalid chain-step syntax (kind: {step.getKind})"
    out := out.push (term, proof)
  return out

/-- Check whether a syntax tree contains a synthetic hole `?_`. -/
private partial def calcContainsSyntheticHole (stx : Syntax) : Bool :=
  if stx.getKind == ``Parser.Term.syntheticHole then true
  else stx.getArgs.any calcContainsSyntheticHole

/-- Decompose `e` into `(relation, left, right)`.
    The final two arguments are expected to be explicit, as in
    `Lean.Elab.Term.getCalcRelation?`. -/
private def decomposeCalcRelation (e : Expr) : Option (Expr × Expr × Expr) :=
  if e.getAppNumArgs < 2 then none
  else some (e.appFn!.appFn!, e.appFn!.appArg!, e.appArg!)

-- Capture native `calc` elaboration in the current calc invocation. The
-- environment slot backtracks with Lean and the outer value survives nesting.
private abbrev CalcProofs := Array (Nat × Expr × Expr)
initialize calcProofsExt : EnvExtension (Option CalcProofs) ← registerEnvExtension (pure none)

def withCalcProofs (action : TacticM Unit) : TacticM CalcProofs := do
  let previous := calcProofsExt.getState <| ← getEnv
  modifyEnv (calcProofsExt.setState · (some #[]))
  try
    action
    return (calcProofsExt.getState <| ← getEnv).getD #[]
  finally
    modifyEnv (calcProofsExt.setState · previous)

syntax (name := recordedCalcProof) "_recorded_calc_proof%" num term : term

@[term_elab recordedCalcProof] def elabRecordedCalcProof : Elab.Term.TermElab := fun stx expected? => do
  let `(_recorded_calc_proof% $index:num $proof:term) := stx
    | Elab.throwUnsupportedSyntax
  let some expected := expected? | throwError "calc proof requires an expected type"
  let expression ← Elab.Term.elabTermEnsuringType proof expected
  let some _ := calcProofsExt.getState <| ← getEnv
    | throwError "calc proof elaborated outside a recording capture"
  modifyEnv fun env => calcProofsExt.modifyState env fun proofs =>
    proofs.map (·.push (index.getNat, expected, expression))
  return expression

/-- Recording elaborator for `_calc`: record the initial term and every chain step.
    `init` is the left side of the first relation; `chain` contains
    `{relation, rhs, proof}` entries, with proofs containing `?_` recorded as holes. -/
script_recorder «renderCalc» (fields := ProofScript.Recording.goalFields ++ #[
  { name := "init", schema := .expression, nullable := false },
  { name := "chain", nullable := false, schema := .array (.object [
      ("relation", .expression), ("rhs", .expression),
      ("proof", .union [.expression, .object [("kind", .literal "hole")]])]) }])
"calc" steps:calcSteps => withMainContext <| ProofScript.Recording.withRecordingStep fun step => do
  step.recordGoal "goal_before"
  let chain ← liftMacroM <| parseCalcSteps steps
  let views ← Elab.Term.mkCalcStepViews steps
  let wrapped ← views.mapIdxM fun index view => do
    let proof ← `(_recorded_calc_proof% $(quote index) $(view.proof))
    return { view with proof }
  let first ← `(calcFirstStep| $(wrapped[0]!.term) := $(wrapped[0]!.proof))
  let rest ← (wrapped.extract 1 wrapped.size).mapM fun view =>
    `(Lean.calcStep| $(view.term) := $(view.proof))
  let recordedSteps : TSyntax ``calcSteps := ⟨steps.raw.setArg 0 first.raw |>.setArg 1 (mkNullNode rest)⟩
  let captureInit : TacticM ProofScript.Recording.RecordedValue := do
    let proofs := (calcProofsExt.getState (← getEnv)).getD #[]
    let some (_, type, _) := proofs.find? (fun entry => entry.1 == 0)
      | throwError "calc: missing first elaborated proof"
    let some (_, lhs, _) := decomposeCalcRelation (← instantiateMVars type)
      | throwError "calc: cannot extract the initial relation"
    ProofScript.Recording.snapshotExpression lhs
  let captureChain : TacticM ProofScript.Recording.RecordedValue := do
    let proofs := (calcProofsExt.getState (← getEnv)).getD #[]
    let mut values := #[]
    for i in [:chain.size] do
      let (relTerm, prf) := chain[i]!
      let some (_, type, proof) := proofs.find? (fun entry => entry.1 == i)
        | throwErrorAt prf "calc: missing elaborated proof"
      let some (rel, _, rhs) := decomposeCalcRelation (← instantiateMVars type)
        | throwErrorAt relTerm "calc: cannot extract a binary relation from the step"
      let proof ← if calcContainsSyntheticHole prf.raw then
          pure (ProofScript.Recording.RecordedValue.object [("kind", .scalar (json% "hole"))])
        else ProofScript.Recording.snapshotExpression proof
      values := values.push (.object [
        ("relation", ← ProofScript.Recording.snapshotExpression rel),
        ("rhs", ← ProofScript.Recording.snapshotExpression rhs), ("proof", proof)])
    return .array values
  let _ ← withCalcProofs do
    withScriptMode <| evalTactic (← `(tactic| script_calc $recordedSteps:calcSteps))
    step.captureField "init" captureInit
    step.captureField "chain" captureChain
  step.recordGoal "goal_after"

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

/-- Check whether a syntax tree contains a synthetic hole `?_`. -/
private partial def inferContainsSyntheticHole (stx : Syntax) :=
  if stx.getKind == ``Parser.Term.syntheticHole then true
  else stx.getArgs.any inferContainsSyntheticHole

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
private partial def inferFindSubtermOfType  (e : Expr)
                                    (targetType : Expr)
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
elab "infer_check_first" P:term " => " Q:term " := " prf:term : term => do
  if !inferIsTacticProof prf.raw && inferContainsSyntheticHole prf.raw then
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

script_macro «infer»
"infer" steps:inferSteps => buildInferTactic steps.raw

macro "infer" steps:inferSteps : term => `(term| script infer $steps:inferSteps)

/-- Parse `inferSteps` and extract the initial proposition and each step.
    Returns `(initial proposition, [(right-hand proposition, proof term)])`. -/
private def parseInferSteps (steps : Syntax)
                            : MacroM (TSyntax `term × Array (TSyntax `term × TSyntax `term)) := do
  -- The actual structure is `inferFirstStep (ppLine linebreak inferStep)*`.
  let firstStep := steps[0]
  let restSteps := steps[1]
  let `(inferFirstStep| $P:term $_arrow:inferArrow $[$_firstLabel:ident :]? $Q:term := $prf1:term) := firstStep
  | Macro.throwError s!"infer: invalid first-step syntax, kind: {firstStep.getKind}"
  let mut chain := #[(Q, prf1)]
  for i in [:restSteps.getArgs.size] do
    let step := restSteps[i]
    let `(inferStep| $_arrow:inferArrow $[$_label:ident :]? $R:term := $prf:term) := step
    | Macro.throwError s!"infer: invalid chain-step syntax, kind: {step.getKind}"
    chain := chain.push (R, prf)
  return (P, chain)

script_recorder «infer» (fields := ProofScript.Recording.goalFields ++ #[
  { name := "init", schema := .expression, nullable := false },
  { name := "chain", nullable := false, schema := .array (.object [
      ("rhs", .expression), ("proof", .union [.expression, .object [("kind", .literal "hole")]])]) }])
"infer" steps:inferSteps => withMainContext do
  let (init, chain) ← liftMacroM <| parseInferSteps steps
  let captureChain : TacticM ProofScript.Recording.RecordedValue := do
    let mut values := #[]
    for i in [:chain.size] do
      let (rhs, prf) := chain[i]!
      let rhsExpr ← elabTerm rhs none
      let proof ←
        -- Later tactic proofs need a preceding result that does not exist at this phase.
        if inferContainsSyntheticHole prf.raw || (i > 0 && inferIsTacticProof prf.raw) then
          pure (ProofScript.Recording.RecordedValue.object [("kind", .scalar (json% "hole"))])
        else
          ProofScript.Recording.snapshotExpression (← elabTerm prf (some rhsExpr))
      values := values.push (.object [
        ("rhs", ← ProofScript.Recording.snapshotExpression rhsExpr), ("proof", proof)])
    return .array values
  recordStep (before := #[
    { name := "init", onFailure := .required,
      capture := ProofScript.Recording.expression init.raw },
    { name := "chain", onFailure := .required, capture := captureChain }
  ])
