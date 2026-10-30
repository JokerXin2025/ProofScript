import ProofScript

/-! Two explicit recorder versions share one step while `execute` invokes the predecessor. -/

open Lean ProofScript
open Lean.Elab.Tactic

set_option proofScript.pageBuild true

script_macro versionedRecorderRule
  "versioned_recorder" h:ident => `(tactic| exact $h:ident)

script_recorder versionedRecorderRule => do
  record_value "first" "yes"
  record_value "label" "original"
  execute

run_cmd do
  let some registration := (scriptTacticRegistrations (← getEnv)).find?
       (·.ruleId == `versionedRecorderRule)
    | throwError "missing recorder registration"
  unless registration.explicitRecordingKind.isSome &&
      registration.explicitRecordingParent.isNone do
    throwError "the first explicit recorder must replace the automatic recorder"

script_recorder versionedRecorderRule => do
  execute
  record_value "second" "yes"

script_recorder versionedRecorderRule => do
  execute
  record_value "third" "yes"
  record_value "label" "updated"

run_cmd do
  let some registration := (scriptTacticRegistrations (← getEnv)).find?
       (·.ruleId == `versionedRecorderRule)
    | throwError "missing recorder registration"
  unless registration.explicitRecordingKind.isSome &&
      registration.explicitRecordingParent.isSome &&
      registration.explicitRecordingKind != registration.explicitRecordingParent do
    throwError "the latest explicit recorder must capture its predecessor"

#page theorem versionedProof (P : Prop) (h : P) : P := script
  versioned_recorder h

script_elab versionedStrategy (kind := strategy)
  "versioned_strategy" => Lean.Elab.Tactic.withMainContext do
    let goal ← getMainGoal
    let goals ← goal.apply (mkConst ``And.intro)
    replaceMainGoal goals

script_recorder versionedStrategy => do
  record_value "strategy_first" true
  execute

script_recorder versionedStrategy => do
  execute
  record_value "strategy_second" true

#page theorem versionedStrategyProof (P Q : Prop) (hP : P) (hQ : Q) : P ∧ Q := script
  versioned_strategy
  | left => trivial
  | right => trivial

-- Check the actual exported proof, not just the registration table.
run_cmd do
  let moduleName ← getMainModule
  let readProof (declaration : Name) : Lean.Elab.Command.CommandElabM (Array Json) := do
    let path ← Lean.Elab.Command.liftIO <| activeOutputPath (proofOutputPath moduleName declaration)
    let text ← Lean.Elab.Command.liftIO <| IO.FS.readFile path
    let document ← match Json.parse text with
      | .ok document => pure document
      | .error message => throwError "invalid recorded proof: {message}"
    match document.getObjValAs? (Array Json) "proof" with
    | .ok proof => pure proof
    | .error message => throwError "missing recorded proof: {message}"
  let steps ← readProof (moduleName ++ `versionedProof)
  unless steps.size == 1 do throwError "recorder versions must share one JSON step"
  for field in ["first", "second", "third"] do
    unless (steps[0]!.getObjVal? field).isOk do
      throwError "missing field `{field}` from shared recorder step"
  unless steps[0]!.getObjValAs? String "label" == .ok "updated" do
    throwError "the latest recorder must replace the previous label"
  let steps ← readProof (moduleName ++ `versionedStrategyProof)
  unless steps.size == 1 do throwError "strategy versions must share one JSON step"
  for field in ["strategy_first", "strategy_second"] do
    unless (steps[0]!.getObjVal? field).isOk do
      throwError "missing field `{field}` from strategy recorder step"
  let branches ← match steps[0]!.getObjValAs? (Array Json) "$branches" with
    | .ok branches => pure branches
    | .error message => throwError "missing strategy branches: {message}"
  unless branches.size == 2 do throwError "strategy branches must be prepared once"
  for branch in branches do
    let .ok proof := branch.getObjValAs? (Array Json) "proof"
      | throwError "strategy branch must contain a proof"
    unless proof.size == 1 do throwError "each strategy branch must contain one step"

#page theorem automaticProof : True := script
  trivial

run_cmd do
  let moduleName ← getMainModule
  let path ← Lean.Elab.Command.liftIO <| activeOutputPath
    (proofOutputPath moduleName (moduleName ++ `automaticProof))
  let text ← Lean.Elab.Command.liftIO <| IO.FS.readFile path
  let document ← match Json.parse text with
    | .ok document => pure document
    | .error message => throwError "invalid automatic proof: {message}"
  let .ok proof := document.getObjValAs? (Array Json) "proof"
    | throwError "automatic recorder did not export a proof"
  unless proof.size == 1 && (proof[0]!.getObjVal? "$goal_before").isOk &&
      (proof[0]!.getObjVal? "$goal_after").isOk do
    throwError "automatic recorder must record one step and both goals"

script_macro fallbackRule
  "fallback_rule" _h:("using" ident) => `(tactic| exact True.intro)

example : True := script
  fallback_rule using True.intro

run_cmd do
  let some registration := (scriptTacticRegistrations (← getEnv)).find?
       (·.ruleId == `fallbackRule)
    | throwError "missing fallback registration"
  unless registration.automaticRecordingKind.isNone &&
      registration.fallbackRecordingKind.isSome do
    throwError "fallback recorder must be generated for a compound parameter"

#page theorem fallbackProof : True := script
  fallback_rule using True.intro

run_cmd do
  let moduleName ← getMainModule
  let path ← Lean.Elab.Command.liftIO <| activeOutputPath
    (proofOutputPath moduleName (moduleName ++ `fallbackProof))
  let text ← Lean.Elab.Command.liftIO <| IO.FS.readFile path
  let document ← match Json.parse text with
    | .ok document => pure document
    | .error message => throwError "invalid fallback proof: {message}"
  let .ok proof := document.getObjValAs? (Array Json) "proof"
    | throwError "fallback recorder did not export a proof"
  unless proof.size == 1 &&
      proof[0]!.getObjValAs? String "$ruleId" == .ok unrecordedRuleId.toString &&
      proof[0]!.getObjValAs? String "name" == .ok "fallback_rule" do
    throwError "fallback recorder must emit one unrecorded step with the tactic name"

script_recorder fallbackRule => do
  record_value "compound" true
  execute

#page theorem compoundRecorderProof : True := script
  fallback_rule using True.intro

run_cmd do
  let moduleName ← getMainModule
  let path ← Lean.Elab.Command.liftIO <| activeOutputPath
    (proofOutputPath moduleName (moduleName ++ `compoundRecorderProof))
  let text ← Lean.Elab.Command.liftIO <| IO.FS.readFile path
  let document ← match Json.parse text with
    | .ok document => pure document
    | .error message => throwError "invalid compound recorder proof: {message}"
  let .ok proof := document.getObjValAs? (Array Json) "proof"
    | throwError "compound recorder did not export a proof"
  unless proof.size == 1 && (proof[0]!.getObjVal? "compound").isOk do
    throwError "compound recorder must bind its invocation and reuse one step"

#page theorem nestedStrategyProof (P Q R : Prop) (hP : P) (hQ : Q) (hR : R) :
    (P ∧ Q) ∧ R := script
  versioned_strategy
  | left =>
    versioned_strategy
    | left => trivial
    | right => trivial
  | right => trivial

#page theorem continuationProof (P Q : Prop) (hP : P) (hQ : Q) : P ∧ Q := script
  claim h : P
  | proof => trivial
  versioned_strategy
  | left => trivial
  | right => trivial

#page theorem anonymousStrategyProof (P Q : Prop) (hP : P) (hQ : Q) : P ∧ Q := script
  versioned_strategy
  · trivial
  · trivial

run_cmd do
  let moduleName ← getMainModule
  let readProof (name : Name) : Lean.Elab.Command.CommandElabM (Array Json) := do
    let path ← Lean.Elab.Command.liftIO <| activeOutputPath
      (proofOutputPath moduleName (moduleName ++ name))
    let text ← Lean.Elab.Command.liftIO <| IO.FS.readFile path
    let .ok document := Json.parse text | throwError "invalid nested recording JSON"
    let .ok steps := document.getObjValAs? (Array Json) "proof"
      | throwError "nested recording has no proof"
    return steps
  let nested ← readProof `nestedStrategyProof
  unless nested.size == 1 do throwError "outer strategy must produce one step"
  let .ok outer := nested[0]!.getObjValAs? (Array Json) "$branches"
    | throwError "outer strategy has no branches"
  unless outer.size == 2 do throwError "outer strategy must have two branches"
  let .ok left := outer[0]!.getObjValAs? (Array Json) "proof"
    | throwError "outer left branch has no proof"
  unless left.size == 1 do throwError "nested strategy must occupy one child step"
  let .ok inner := left[0]!.getObjValAs? (Array Json) "$branches"
    | throwError "nested strategy has no branches"
  unless inner.size == 2 do throwError "nested strategy must have two branches"
  for branch in inner do
    let .ok proof := branch.getObjValAs? (Array Json) "proof"
      | throwError "nested branch has no proof"
    unless proof.size == 1 do throwError "nested branch must have one step"
  let continuation ← readProof `continuationProof
  unless continuation.size == 2 do throwError "continuation must return to parent box"
  let .ok claimBranches := continuation[0]!.getObjValAs? (Array Json) "$branches"
    | throwError "claim has no branches"
  unless claimBranches.size == 1 &&
      claimBranches[0]!.getObjValAs? String "name" == .ok "proof" do
    throwError "claim must export only its proof branch"
  let .ok restBranches := continuation[1]!.getObjValAs? (Array Json) "$branches"
    | throwError "continuation strategy has no branches"
  unless restBranches.size == 2 do throwError "continuation strategy lost its branches"
  let anonymous ← readProof `anonymousStrategyProof
  unless anonymous.size == 1 do throwError "anonymous strategy must produce one step"
  let .ok anonymousBranches := anonymous[0]!.getObjValAs? (Array Json) "$branches"
    | throwError "anonymous strategy has no branches"
  unless anonymousBranches.size == 2 do throwError "anonymous branches were not routed"

-- A failed recorder must restore both its proof state and its reserved slot.
script_macro rollbackRule
  "rollback_rule" h:ident => `(tactic| exact $h:ident)

script_recorder rollbackRule => do
  record_value "attempted" true
  execute

script_recorder rollbackRule => do
  record_value "before_failure" true
  throwError "intentional recorder failure"
  execute

elab "check_recorder_rollback" : tactic => do
  withRecordingSession do
    pushRecordingTag "rollback"
    ensureBox "rollback"
    let slot ← reserveRecordingSlot "rollback" `testSlot `testRule
    try
      Lean.Elab.Tactic.withRollback do
        mergeRecordingSlotFields slot [("attempted", .plain (toJson true))]
        throwError "intentional rollback"
    catch _ => pure ()
    let .object fields ← getRecordingSlotItem slot
      | throwError "missing restored step"
    if fields.any (·.1 == "attempted") then
      throwError "failed recorder leaked slot fields"

example : True := by
  check_recorder_rollback
  trivial

elab "check_failed_recorder" : tactic => do
  withRecordingSession do
    pushRecordingTag "failed_recorder"
    ensureBox "failed_recorder"
    let source ← `(scriptTactic| rollback_rule True.intro)
    let some (registration, call) := registeredTacticCall
        (scriptTacticRegistrations (← getEnv)) source.raw
      | throwError "missing rollback recorder registration"
    let rewritten ← match rewriteTacticCall call registration.name
        ("_script_" ++ registration.name) registration.recordingKind.get! with
      | .ok rewritten => pure rewritten
      | .error message => throwError message
    let before ← getGoals
    let failed ← try
      evalTactic (⟨rewritten⟩ : TSyntax `tactic)
      pure false
    catch ex =>
      let message ← ex.toMessageData.toString
      unless (message.splitOn "intentional recorder failure").length > 1 do
        throwError "recorder failed for an unexpected reason: {message}"
      pure true
    unless failed do throwError "recorder must fail"
    unless (← getGoals) == before do throwError "failed recorder changed goals"
    unless (← selectedRecordingContract).isNone do
      throwError "failed recorder leaked its contract"
    let (items, bindings) ← takeBoxWithContracts "failed_recorder"
    unless items.isEmpty && bindings.isEmpty do
      throwError "failed recorder leaked a recording step or binding"

example (P : Prop) (bad : P) : P := by
  check_failed_recorder
  exact bad

private partial def hasRecorderInfo (tree : Lean.Elab.InfoTree) (kind : Name)
    (start : String.Pos.Raw) : Bool :=
  match tree with
  | .context _ child => hasRecorderInfo child kind start
  | .node info children =>
    (match info with
      | .ofTermInfo term =>
        term.expr.isConstOf kind && term.stx.getPos? == some start
      | _ => false) || children.toArray.any (hasRecorderInfo · kind start)
  | .hole _ => false

elab "check_recorder_info " source:scriptTactic : tactic => do
  let some (registration, call) := registeredTacticCall
      (scriptTacticRegistrations (← getEnv)) source.raw
    | throwError "missing source registration"
  let rewritten ← match rewriteTacticCall call registration.name
      ("_script_" ++ registration.name) registration.recordingKind.get! with
    | .ok rewritten => pure rewritten
    | .error message => throwError message
  let some keyword := findFirstAtom call
    | throwError "missing source keyword"
  let some start := keyword.getPos?
    | throwError "source keyword lost its position"
  withRecordingSession do
    pushRecordingTag "editor_info"
    ensureBox "editor_info"
    evalTactic (⟨rewritten⟩ : TSyntax `tactic)
    let trees := (← Lean.Elab.getInfoState).trees.toArray
    unless trees.any (hasRecorderInfo · registration.sourceKind start) do
      throwError "recorder keyword lost its source-linked declaration info"

example (P : Prop) (h : P) : P := by
  check_recorder_info versioned_recorder h
