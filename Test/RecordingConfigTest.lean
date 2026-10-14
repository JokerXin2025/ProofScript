import ProofScript.Script.Basic

open Lean Elab Tactic Meta ProofScript ProofScript.Recording

set_option linter.unusedVariables false

private def withTestRecording (action : TacticM Unit) : TacticM Unit := do
  let saved ← Tactic.saveState
  try
    modifyEnv (recordingSessionExt.setState · (some {}))
    ensureBox "test"
    pushRecordingTag "test"
    withExprJsonExport action
  finally
    saved.restore

private def recordedNode (value : Json) : TacticM Json := do
  let .ok id := value.getObjValAs? String "$ref"
    | throwError "expected a recorded expression reference, got {value.compress}"
  let .ok node := (← getExprJsonTable).getObjVal? id
    | throwError "unresolved recorded expression reference `{id}`"
  return node

private def assertRecordedName (value : Json) (name : String) : TacticM Unit := do
  let node ← recordedNode value
  let actual := (node.getObjValAs? String "name").toOption.map fun n =>
    (n.splitOn "._@.").head!
  unless actual == some name do
    throwError "expected `{name}`, got {node.compress}"

script_elab configName
  (params := [x(codec := name, timing := once, field := "label", failure := required)])
  "config_name" x:ident => pure ()

script_macro configMacro
  (params := [x(codec := name, timing := once, field := "label", failure := required)])
  "config_macro" x:ident => `(tactic| skip)

declare_syntax_cat configOpaque
syntax ident : configOpaque
script_elab configSyntax
  (params := [x(codec := "syntax", timing := once, field := "source")])
  "config_syntax" x:configOpaque => pure ()

script_elab configType
  (params := [x(codec := typeOf, timing := before, field := "subject", failure := required)])
  "config_type" x:term => pure ()

-- This strategy has no claim-related name. Its continuation is the second goal.
script_elab configStrategy
  (strategy := true, continuation := 1,
   params := [h(timing := after, context := continuation, failure := required)])
  "config_strategy" h:ident => pure ()

script_elab configBranch
  (strategy := true,
   params := [h(codec := typeOf, timing := after, context := right, failure := required)])
  "config_branch" h:ident => pure ()

script_elab configContinuation
  (strategy := true, continuation := 1,
   params := [h(timing := after, context := continuation, failure := required)])
  "config_continue" h:ident => withMainContext do
    let goal ← getMainGoal
    let proof ← mkFreshExprMVar (mkConst ``True)
    proof.mvarId!.setTag `proof
    let rest ← goal.assert h.getId (mkConst ``True) proof
    let (_, rest) ← rest.intro1P
    replaceMainGoal [proof.mvarId!, rest]

script_elab configTwoProofs
  (strategy := true, continuation := 2,
   params := [h(timing := after, context := continuation, failure := required)])
  "config_two_proofs" h:ident => withMainContext do
    let goal ← getMainGoal
    let first ← mkFreshExprMVar (mkConst ``True)
    let second ← mkFreshExprMVar (mkConst ``True)
    first.mvarId!.setTag `first
    second.mvarId!.setTag `second
    let type := mkApp2 (mkConst ``And) (mkConst ``True) (mkConst ``True)
    let proof := mkApp4 (mkConst ``And.intro) (mkConst ``True) (mkConst ``True) first second
    let rest ← goal.assert h.getId type proof
    let (_, rest) ← rest.intro1P
    replaceMainGoal [first.mvarId!, second.mvarId!, rest]

script_elab configClear (clear := [h]) "config_clear" h:ident => do
  evalTactic (← `(tactic| clear $h))

example : True := by
  run_tac do
    let saved ← Tactic.saveState
    try
      modifyEnv (recordingSessionExt.setState · (some {}))
      ensureBox "test"
      pushRecordingTag "test"
      withExprJsonExport do
        withRecordingRule `test (← `(tactic| skip)) do
          evalTactic (← `(tactic| _script_config_name unbound))
          evalTactic (← `(tactic| _script_config_syntax opaqueValue))
          evalTactic (← `(tactic| _script_config_type (0 : Nat)))
        let records ← takeBox "test"
        unless (records[1]!.getObjVal? "label").toOption == some (Json.str "unbound") do
          throwError "name codec/timing/field config was not applied"
        unless (records[3]!.getObjValAs? String "source").isOk do
          throwError "explicit syntax codec unexpectedly requires an instance"
        assertRecordedName (← ofExcept (records[5]!.getObjVal? "subject")) "Nat"
        let parent ← getMainGoal
        let proof ← mkFreshExprMVar (mkConst ``True)
        let continuation ← withLocalDeclD `introduced (mkConst ``True) fun _ =>
          mkFreshExprMVar (mkConst ``True)
        setGoals [proof.mvarId!, continuation.mvarId!]
        let h : TSyntax `ident := ⟨mkIdent `introduced⟩
        withRecordingRule `test (← `(tactic| skip)) do
          evalTactic (← `(tactic| _script_config_strategy $h _strategy_cases ""))
        let records ← takeBox "test"
        assertRecordedName (← ofExcept (records[1]!.getObjVal? "h")) "introduced"
        setGoals [parent]
        let plan : RecordingPlan := { parameters := #[{
          name := "absent", timing := .after, context := .branch "missing",
          capture := pure (.scalar (Json.str "wrong"))
        }] }
        let fields ← captureFields plan false (fun _ => pure none)
        unless fields.lookup "absent" == some Json.null do
          throwError "missing branch ignored best-effort policy"
        let strict := { plan with parameters := plan.parameters.map (fun p =>
          { p with onFailure := .required }) }
        let failed ← try
          let _ ← captureFields strict false (fun _ => pure none)
          pure false
        catch _ => pure true
        unless failed do throwError "missing required context was accepted"
    finally
      saved.restore
  trivial

example : True := by
  run_tac withTestRecording do
    withRecordingRule `test (← `(tactic| script_config_macro unbound)) do
      evalTactic (← `(tactic| _script_config_macro unbound))
    let records ← takeBox "test"
    unless (records[1]!.getObjVal? "label").toOption == some (Json.str "unbound") do
      throwError "script_macro did not apply its parameter configuration"
  trivial

-- Both branches bind `shared`, but to different types. Named capture must use the right goal.
example : True := by
  run_tac withTestRecording do
    let left ← withLocalDeclD `shared (mkConst ``Nat) fun _ =>
      mkFreshExprMVar (mkConst ``True)
    let right ← withLocalDeclD `shared (mkConst ``Bool) fun _ =>
      mkFreshExprMVar (mkConst ``True)
    left.mvarId!.setTag `left
    right.mvarId!.setTag `right
    setGoals [left.mvarId!, right.mvarId!]
    let h : TSyntax `ident := ⟨mkIdent `shared⟩
    withRecordingRule `test (← `(tactic| skip)) do
      evalTactic (← `(tactic| _script_config_branch $h _strategy_cases "right\nleft"))
    let records ← takeBox "test"
    assertRecordedName (← ofExcept (records[1]!.getObjVal? "h")) "Bool"
    unless (← getGoals) == [left.mvarId!, right.mvarId!] do
      throwError "capture changed the remaining-goal order"
  trivial

-- The clear shorthand captures the hypothesis before execution removes it.
example (discarded : True) : True := by
  run_tac withTestRecording do
    let h : TSyntax `ident := ⟨mkIdent `discarded⟩
    withRecordingRule `test (← `(tactic| script_config_clear $h)) do
      evalTactic (← `(tactic| _script_config_clear $h))
    let records ← takeBox "test"
    assertRecordedName (← ofExcept (records[1]!.getObjVal? "h")) "discarded"
    (← getMainGoal).withContext do
      if ((← getLCtx).findFromUserName? `discarded).isSome then
        throwError "clear execution did not remove the captured hypothesis"
    unless !(records[1]!.getObjVal? "h_after").isOk do
      throwError "clear shorthand recorded after deleting the hypothesis"
  trivial

-- Resolver errors, missing branches, and missing continuations obey the same failure policy.
example : True := by
  run_tac withTestRecording do
    let goal ← getMainGoal
    let table ← getExprJsonTable
    for context in [ContextSelector.continuation, .branch "missing"] do
      for strict in [false, true] do
        let plan : RecordingPlan := { parameters := #[{
          name := "absent", timing := .after, context,
          onFailure := if strict then .required else .bestEffort,
          capture := pure (.scalar (Json.str "incorrect fallback"))
        }] }
        for resolver in [
            (fun (_ : ContextSelector) => pure none : ContextSelector → TacticM (Option MVarId)),
            (fun _ => do
              setGoals []
              throwError "resolver failed") ] do
          let outcome ← try
            pure (some (← captureFields plan false resolver))
          catch _ => pure none
          if strict then
            unless outcome.isNone do throwError "required context failure was ignored"
          else
            unless outcome.bind (·.lookup "absent") == some Json.null do
              throwError "best-effort context failure did not produce null"
          unless (← getGoals) == [goal] && (← getExprJsonTable) == table do
            throwError "context resolution escaped capture isolation"
  trivial

-- Ambiguous suffixes are capture failures; exact declared branch labels remain usable.
example : True := by
  run_tac withTestRecording do
    let first ← mkFreshExprMVar (mkConst ``True)
    let second ← mkFreshExprMVar (mkConst ``True)
    first.mvarId!.setTag `first.shared
    second.mvarId!.setTag `second.shared
    setGoals [first.mvarId!, second.mvarId!]
    let plan : RecordingPlan := { parameters := #[{
      name := "ambiguous", timing := .after, context := .branch "shared",
      capture := pure (.scalar (Json.str "wrong"))
    }] }
    withRecordingRule `test (← `(tactic| skip)) do
      recordStrategy "test" ["first.shared", "second.shared"] [] (parameters := plan)
    let records ← takeBox "test"
    unless (records[1]!.getObjVal? "ambiguous").toOption == some Json.null do
      throwError "ambiguous suffix silently selected the first goal"
    let saved ← Tactic.saveState
    let strict := { plan with parameters := plan.parameters.map fun p =>
      { p with onFailure := .required } }
    let failed ← try
      withRecordingRule `test (← `(tactic| skip)) do
        recordStrategy "test" ["first.shared", "second.shared"] [] (parameters := strict)
      pure false
    catch _ => pure true
    unless failed && (← takeBox "test").isEmpty do
      throwError "required ambiguous capture left a strategy placeholder"
    saved.restore
    let failed ← try
      withRecordingRule `test (← `(tactic| skip)) do
        recordStrategy "test" ["shared"] []
      pure false
    catch _ => pure true
    unless failed do throwError "ambiguous explicit branch silently selected the first goal"
  trivial

-- Real execution and branch collection, including a second bullet for the continuation.
example : True := by
  run_tac withTestRecording do
    let stmts ← `(scriptStmts|
      config_continue introduced
      · trivial
      · exact introduced)
    evalTactic (buildTacticSeq (← collectRecordTactics (scriptStmtsToArray stmts)))
    let records ← takeBox "test"
    let some step := records.find? fun j =>
      (j.getObjValAs? String "_ruleId").toOption == some "Test.RecordingConfigTest.configContinuation"
      | throwError "missing custom continuation strategy"
    assertRecordedName (← ofExcept (step.getObjVal? "h")) "introduced"
    let branches ← ofExcept (step.getObjValAs? (Array Json) "branches")
    unless branches.size == 1 && records.size == 4 && (← currentRecordingTag) == "test" do
      throwError "continuation bullet was recorded as a proof branch"
  trivial

example : True := by
  run_tac withTestRecording do
    let stmts ← `(scriptStmts|
      config_two_proofs paired
      · trivial
      · trivial
      · exact_proj paired)
    evalTactic (buildTacticSeq (← collectRecordTactics (scriptStmtsToArray stmts)))
    let records ← takeBox "test"
    assertRecordedName (← ofExcept (records[1]!.getObjVal? "h")) "paired"
    unless (← ofExcept (records[1]!.getObjValAs? (Array Json) "branches")).size == 2 &&
        (← currentRecordingTag) == "test" do
      throwError "multi-branch continuation boundary was ignored"
  trivial

example : True := by
  run_tac withTestRecording do
    let stmts ← `(scriptStmts|
      claim hc : True
      · trivial
      · exact hc)
    evalTactic (buildTacticSeq (← collectRecordTactics (scriptStmtsToArray stmts)))
    let records ← takeBox "test"
    assertRecordedName (← ofExcept (records[1]!.getObjVal? "h")) "hc"
    unless (← ofExcept (records[1]!.getObjValAs? (Array Json) "branches")).size == 1 do
      throwError "claim continuation escaped the registered boundary"
  trivial

example : True := by
  run_tac withTestRecording do
    let stmts ← `(scriptStmts|
      claim_exist ⟨n, hn⟩ : ∃ _ : Nat, True
      · exact ⟨0, True.intro⟩
      · exact hn)
    evalTactic (buildTacticSeq (← collectRecordTactics (scriptStmtsToArray stmts)))
    let records ← takeBox "test"
    assertRecordedName (← ofExcept (records[1]!.getObjVal? "h₁")) "n"
    assertRecordedName (← ofExcept (records[1]!.getObjVal? "h₂")) "hn"
    unless (← ofExcept (records[1]!.getObjValAs? (Array Json) "branches")).size == 1 &&
        (← currentRecordingTag) == "test" do
      throwError "claim_exist continuation escaped the registered boundary"
  trivial

example : True := by
  run_tac withTestRecording do
    let stmts ← `(scriptStmts|
      claim_exist ⟨n, hp, hq⟩ : ∃ _ : Nat, True ∧ True
      | proof => exact ⟨0, True.intro, True.intro⟩
      exact hq)
    evalTactic (buildTacticSeq (← collectRecordTactics (scriptStmtsToArray stmts)))
    let records ← takeBox "test"
    for (field, name) in [("h₁", "n"), ("h₂", "hp"), ("h₃", "hq")] do
      assertRecordedName (← ofExcept (records[1]!.getObjVal? field)) name
  trivial

-- Test the actual strategy adapter's default, out-of-range and missing branch roles.
example : True := by
  run_tac withTestRecording do
    for (context, index) in [
        (ContextSelector.continuation, none), (.continuation, some 9),
        (.branch "missing", none)] do
      for strict in [false, true] do
        let saved ← Tactic.saveState
        let goal ← getMainGoal
        goal.setTag `proof
        let table ← getExprJsonTable
        let plan : RecordingPlan := { parameters := #[{
          name := "absent", timing := .after, context,
          onFailure := if strict then .required else .bestEffort,
          capture := pure (.scalar (Json.str "wrong"))
        }] }
        let failed ← try
          withRecordingRule `test (← `(tactic| skip)) do
            recordStrategy "test" ["proof"] [] (parameters := plan)
              (continuationIndex := index)
          pure false
        catch _ => pure true
        let records ← takeBox "test"
        if strict then
          unless failed && records.isEmpty && (← currentRecordingTag) == "test" do
            throwError "required missing context left recording state"
        else
          unless !failed && (records[1]!.getObjVal? "absent").toOption == some Json.null do
            throwError "best-effort missing context used another goal"
        unless (← getGoals) == [goal] && !(← goal.isAssigned) do
          throwError "missing context changed goals"
        if strict && (← getExprJsonTable) != table then
          throwError "required context failure left expression nodes"
        saved.restore
  trivial

local elab "config_execution_failure" : tactic => do
  let goal ← getMainGoal
  goal.assign (mkConst ``True.intro)
  setGoals []
  let _ ← Expr2JSON (mkConst ``Bool)
  addTheoremRef ``Bool
  pushResolvedBranches ["discarded"]
  startStrategy (← currentRecordingTag) ["discarded"]
  throwError "intentional execution failure"

-- Ordinary steps and strategies restore headers, expressions, references, assignments and stacks.
example : True := by
  run_tac withTestRecording do
    appendBoxItem "test" (Json.str "kept")
    for strategy in [false, true] do
      for phase in ["before", "after", "execute"] do
        let goal ← getMainGoal
        let goals ← getGoals
        let table ← getExprJsonTable
        let refs ← getTheoremRefs
        let some state := recordingSessionExt.getState (← getEnv)
          | throwError "missing test session"
        let plan : RecordingPlan := { parameters := #[
          { name := "expr", timing := .before, onFailure := .required,
            capture := expression (← `(term| True.intro)).raw },
          { name := "strict", timing := if phase == "before" then .before else .after,
            onFailure := .required, capture := throwError "intentional capture failure" }
        ] }
        let execution ← if phase == "execute" then `(tactic| config_execution_failure)
          else if strategy then `(tactic| script_config_continue introduced)
          else `(tactic| exact True.intro)
        let failure ← try
          withRecordingRule `test execution do
            if strategy then
              recordStrategy "test" ["proof"] [] (parameters := plan)
                (continuationIndex := some 1)
            else
              recordStep [] (parameters := plan)
          pure none
        catch ex => pure (some (← ex.toMessageData.toString))
        let expected := if phase == "execute" then "intentional execution failure"
          else "intentional capture failure"
        unless failure.any (fun message => (message.splitOn expected).length > 1) do
          throwError "expected {phase} failure, got {failure}"
        let some restored := recordingSessionExt.getState (← getEnv)
          | throwError "recording session lost on rollback"
        unless restored.boxes == state.boxes && restored.boxTags == state.boxTags &&
            restored.strategyBranches == state.strategyBranches &&
            restored.resolvedBranches == state.resolvedBranches &&
            (← getExprJsonTable) == table && (← getTheoremRefs) == refs &&
            (← getGoals) == goals && !(← goal.isAssigned) do
          throwError "{phase} failure did not roll back the complete invocation (strategy={strategy})"
  trivial

-- Inline and plan fields share one namespace, including duplicate captures.
example : True := by
  run_tac withTestRecording do
    let plan : RecordingPlan := { parameters := #[{
      name := "h", timing := .once, capture := pure (.scalar Json.null)
    }] }
    for strategy in [false, true] do
      for inline in [true, false] do
        let failed ← try
          withRecordingRule `test (← `(tactic| skip)) do
            let fields := if inline then [("h", Json.null)] else []
            let raw ← `(term| True.intro)
            let plan := if inline then plan else
              { plan with parameters := plan.parameters.push (param (.category `term) "h" .before raw) }
            if strategy then recordStrategy "test" [] fields (parameters := plan)
            else recordStep fields (parameters := plan)
          pure false
        catch _ => pure true
        unless failed && (← takeBox "test").isEmpty do
          throwError "invocation field collision was accepted"
  trivial

-- Invalid declarations must fail before generating any execution/recording registration.
open Lean.Elab.Command in
run_cmd do
  let cases := [
    ("(params := [missing(codec := name)])", "x:ident", "不在 syntax 参数"),
    ("(params := [x(timing := once, timing := after)])", "x:ident", "duplicate parameter option"),
    ("(params := [x(codec := name), x(codec := name)])", "x:ident", "duplicate parameter configuration"),
    ("(intro := [x], params := [x(timing := after)])", "x:ident", "sets both intro/clear and timing"),
    ("(clear := [x], params := [x(timing := before)])", "x:ident", "sets both intro/clear and timing"),
    ("(intro := [x], clear := [x])", "x:ident", "sets both intro and clear"),
    ("(params := [x(codec := name)])", "x:term", "name codec requires ident"),
    ("(params := [x(codec := typeOf)])", "x:str", "expression codec requires a single term/ident"),
    ("(params := [x(codec := expression)])", "x:ident+", "explicit codec requires a single syntax parameter"),
    ("(params := [x(codec := \"syntax\")])", "x:(ident)?", "explicit codec requires a single syntax parameter"),
    ("(params := [x(field := \"same\"), y(field := \"same\")])", "x:ident y:ident", "duplicate recorded parameter field"),
    ("(params := [y(field := \"x_before\", timing := once)])", "x:ident y:ident", "duplicate recorded parameter field"),
    ("(params := [x(field := \"branches\")])", "x:ident", "reserved recorded parameter field"),
    ("(params := [x(field := \"_ruleId\", timing := once)])", "x:ident", "reserved recorded parameter field"),
    ("", "_goal_:ident", "reserved recorded parameter field"),
    ("(params := [x(field := \"\")])", "x:ident", "must not be empty"),
    ("(continuation := 0)", "x:ident", "continuation requires strategy"),
    ("(params := [x(context := continuation)])", "x:ident", "non-main context requires strategy"),
    ("(params := [x(codec := unknown)])", "x:ident", "unknown parameter codec"),
    ("(params := [x(failure := unknown)])", "x:ident", "unknown capture failure policy")
  ]
  for (cfg, args, expected) in cases do
    let source := "script_elab invalidConfig " ++ cfg ++ " \"invalid_config\" " ++ args ++ " => pure ()"
    let .ok command := Parser.runParserCategory (← getEnv) `command source
      | throwError "invalid test syntax: {source}"
    let saved ← get
    let message ← try
      elabCommand command
      let errors := (← get).messages.toList.filter (·.severity == .error)
      pure (String.intercalate "\n" (← errors.mapM fun msg => msg.data.toString))
    catch ex => ex.toMessageData.toString
    set saved
    unless (message.splitOn expected).length > 1 do
      throwError "expected diagnostic `{expected}`, got `{message}` for {source}"
