import ProofScript

open Lean Elab Tactic ProofScript

set_option linter.unusedVariables false

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

-- Public extension declarations use the same continuation protocol as builtin claims.
script_elab configContinuation
  (strategy := true, continuation := 1,
   params := [h(timing := after, context := continuation, failure := required)])
  "config_continue" h:ident => do
    evalTactic (← `(tactic| script_claim $h:ident : True))

script_elab configTwoProofs
  (strategy := true, continuation := 2,
   params := [h(timing := after, context := continuation, failure := required)])
  "config_two_proofs" h:ident => do
    evalTactic (← `(tactic| script_claim $h:ident : True ∧ True))
    evalTactic (← `(tactic| constructor))

-- Generated recorder binders must not capture user parameters with these names.
-- The expression exists only after execution; name-only captures never elaborate it.
script_macro configGeneratedMacro
  (params := [context(codec := name, timing := once, field := "scope_label", failure := required),
              step(timing := both, field := "evidence"),
              strategyCases(codec := name, timing := after, field := "case_label", failure := required)])
  "config_generated_macro" context:ident step:ident strategyCases:ident =>
  `(tactic| intro $step:ident)

script_elab configGeneratedStrategy
  (strategy := true, continuation := 1,
   params := [context(codec := name, timing := once, field := "scope_label", failure := required),
              step(codec := name, timing := both, field := "step_label", failure := required),
              strategyCases(timing := after, context := continuation, field := "evidence", failure := required)])
  "config_generated_strategy" context:ident step:ident strategyCases:ident => do
    evalTactic (← `(tactic| script_claim $strategyCases:ident : True))

script_elab configClear (clear := [h]) "config_clear" h:ident => do
  evalTactic (← `(tactic| clear $h:ident))

@theorem recordingConfigValues : True := script
  config_name unbound
  config_macro macroLabel
  config_syntax opaqueValue
  config_type (0 : Nat)
  trivial

@theorem recordingConfigClear (discarded : True) : True := script
  config_clear discarded
  trivial

example (discarded : True) : True := by
  script_config_clear discarded
  fail_if_success exact discarded
  trivial

@theorem recordingConfigContinuation : True := script
  config_continue introduced
  · trivial
  · exact introduced

@theorem recordingConfigTwoProofs : True := script
  config_two_proofs paired
  · trivial
  · trivial
  · exact_proj paired

@theorem recordingConfigGeneratedMacro : True → True := script
  config_generated_macro outer introduced caseLabel
  exact introduced

@theorem recordingConfigGeneratedStrategy : True := script
  config_generated_strategy outer marker saved
  · trivial
  exact saved

@theorem recordingConfigClaim : True := script
  claim hc : True
  · trivial
  · exact hc

@theorem recordingConfigClaimExistTwo (existence : ∃ _ : Nat, True) : True := script
  claim_exist ⟨n, hn⟩ : ∃ _ : Nat, True
  · exact existence
  · exact hn

@theorem recordingConfigClaimExistThree (existence : ∃ _ : Nat, True ∧ True) : True := script
  claim_exist ⟨n, hp, hq⟩ : ∃ _ : Nat, True ∧ True
  | proof => exact existence
  exact hq

-- Check generated recorders through their exported values and registered output
-- contracts, including timing expansion and the strategy snapshot boundary.
open Lean Elab Command ProofScript.Recording in
run_cmd do
  let readFirstStep := fun (decl : Name) => do
    let document ← Lean.ofExcept <| Json.parse
      (← IO.FS.readFile (proofOutputPath (← getEnv).mainModule decl))
    let proof ← Lean.ofExcept (document.getObjValAs? (Array Json) "proof")
    let some step := proof[0]? | throwError "generated recorder produced no proof steps"
    pure step
  let ordinary ← readFirstStep `recordingConfigGeneratedMacro
  unless (ordinary.getObjVal? "goal_before").toOption != some Json.null &&
      (ordinary.getObjVal? "goal_after").toOption != some Json.null &&
      (ordinary.getObjVal? "goal_before").isOk &&
      (ordinary.getObjVal? "goal_after").isOk &&
      (ordinary.getObjVal? "evidence_before").toOption == some Json.null &&
      (ordinary.getObjVal? "evidence_after").isOk &&
      (ordinary.getObjVal? "evidence_after").toOption != some Json.null &&
      (ordinary.getObjValAs? String "scope_label").toOption == some "outer" &&
      (ordinary.getObjValAs? String "case_label").toOption == some "caseLabel" do
    throwError "generated macro recorder lost binder hygiene or capture timing"
  let strategy ← readFirstStep `recordingConfigGeneratedStrategy
  unless (strategy.getObjVal? "goal_before").isOk &&
      (strategy.getObjVal? "goal_before").toOption != some Json.null &&
      !(strategy.getObjVal? "goal_after").isOk &&
      (strategy.getObjVal? "evidence").isOk &&
      (strategy.getObjVal? "evidence").toOption != some Json.null &&
      (strategy.getObjValAs? String "scope_label").toOption == some "outer" &&
      (strategy.getObjValAs? String "step_label_before").toOption == some "marker" &&
      (strategy.getObjValAs? String "step_label_after").toOption == some "marker" do
    throwError "generated strategy recorder lost continuation capture or its snapshot boundary"
  let branches ← Lean.ofExcept (ε := String) (strategy.getObjValAs? (Array Json) "branches")
  unless branches.size == 1 &&
      (branches[0]!.getObjValAs? String "name").toOption == some "proof" do
    throwError "generated strategy recorder did not prepare its proof branch"
  let macroCall ← `(scriptTactic| config_generated_macro outer introduced caseLabel)
  let strategyCall ← `(scriptTactic| config_generated_strategy outer marker saved)
  let ordinaryFields := goalFields ++ #[
    { name := "scope_label", schema := .name, nullable := false },
    { name := "evidence_before", schema := .expression },
    { name := "evidence_after", schema := .expression },
    { name := "case_label", schema := .name, nullable := false }]
  let strategyFields := strategyGoalFields ++ #[
    { name := "scope_label", schema := .name, nullable := false },
    { name := "step_label_before", schema := .name, nullable := false },
    { name := "step_label_after", schema := .name, nullable := false },
    { name := "evidence", schema := .expression, nullable := false }]
  for (source, expected) in [(macroCall, ordinaryFields), (strategyCall, strategyFields)] do
    let some (registration, _) :=
        registeredTacticCall (scriptTacticRegistrations (← getEnv)) source.raw
      | throwError "generated recorder registration was lost"
    unless registration.recordedFields == some expected do
      throwError "generated recorder contract disagrees with its configured fields"

-- Invalid declarations are tested through their public command diagnostics.

/-- error: [script config] 'invalid_config': 配置里的参数 'missing' 不在 syntax 参数 [x] 中 -/
#guard_msgs in
script_elab invalidConfig (params := [missing(codec := name)]) "invalid_config" x:ident => pure ()

/-- error: duplicate parameter option `timing` -/
#guard_msgs in
script_elab invalidConfig (params := [x(timing := once, timing := after)]) "invalid_config" x:ident => pure ()

/-- error: duplicate parameter configuration `x` -/
#guard_msgs in
script_elab invalidConfig (params := [x(codec := name), x(codec := name)]) "invalid_config" x:ident => pure ()

/-- error: [script config] 'invalid_config': `x` sets both intro/clear and timing -/
#guard_msgs in
script_elab invalidConfig (intro := [x], params := [x(timing := after)]) "invalid_config" x:ident => pure ()

/-- error: [script config] 'invalid_config': `x` sets both intro/clear and timing -/
#guard_msgs in
script_elab invalidConfig (clear := [x], params := [x(timing := before)]) "invalid_config" x:ident => pure ()

/-- error: [script config] 'invalid_config': `x` sets both intro and clear -/
#guard_msgs in
script_elab invalidConfig (intro := [x], clear := [x]) "invalid_config" x:ident => pure ()

/-- error: [script config] 'invalid_config': name codec requires ident parameter `x` -/
#guard_msgs in
script_elab invalidConfig (params := [x(codec := name)]) "invalid_config" x:term => pure ()

/-- error: [script config] 'invalid_config': expression codec requires a single term/ident parameter `x` -/
#guard_msgs in
script_elab invalidConfig (params := [x(codec := typeOf)]) "invalid_config" x:str => pure ()

/-- error: [script config] 'invalid_config': explicit codec requires a single syntax parameter `x` -/
#guard_msgs in
script_elab invalidConfig (params := [x(codec := expression)]) "invalid_config" x:ident+ => pure ()

/-- error: [script config] 'invalid_config': explicit codec requires a single syntax parameter `x` -/
#guard_msgs in
script_elab invalidConfig (params := [x(codec := "syntax")]) "invalid_config" x:(ident)? => pure ()

/-- error: [script config] 'invalid_config': duplicate recorded parameter field `same` -/
#guard_msgs in
script_elab invalidConfig (params := [x(field := "same"), y(field := "same")]) "invalid_config" x:ident y:ident => pure ()

/-- error: [script config] 'invalid_config': duplicate recorded parameter field `x_before` -/
#guard_msgs in
script_elab invalidConfig (params := [y(field := "x_before", timing := once)]) "invalid_config" x:ident y:ident => pure ()

/-- error: [script config] 'invalid_config': reserved recorded parameter field `branches` -/
#guard_msgs in
script_elab invalidConfig (params := [x(field := "branches")]) "invalid_config" x:ident => pure ()

/-- error: [script config] 'invalid_config': reserved recorded parameter field `_ruleId` -/
#guard_msgs in
script_elab invalidConfig (params := [x(field := "_ruleId", timing := once)]) "invalid_config" x:ident => pure ()

/-- error: [script config] 'invalid_config': duplicate recorded parameter field `goal_before` -/
#guard_msgs in
script_elab invalidConfig (params := [target(field := "goal_before", timing := once)])
  "invalid_config" target:ident => pure ()

/-- error: [script config] 'invalid_config': duplicate recorded parameter field `goal_after` -/
#guard_msgs in
script_elab invalidConfig (params := [target(field := "goal_after", timing := after)])
  "invalid_config" target:ident => pure ()

/-- error: [script config] 'invalid_config': duplicate recorded parameter field `goal_before` -/
#guard_msgs in
script_elab invalidConfig "invalid_config" goal:ident => pure ()

/-- error: [script config] 'invalid_config': output field for `x` must not be empty -/
#guard_msgs in
script_elab invalidConfig (params := [x(field := "")]) "invalid_config" x:ident => pure ()

/-- error: [script config] continuation requires strategy := true -/
#guard_msgs in
script_elab invalidConfig (continuation := 0) "invalid_config" x:ident => pure ()

/-- error: [script config] 'invalid_config': non-main context requires strategy := true -/
#guard_msgs in
script_elab invalidConfig (params := [x(context := continuation)]) "invalid_config" x:ident => pure ()

/-- error: unknown parameter codec `unknown` -/
#guard_msgs in
script_elab invalidConfig (params := [x(codec := unknown)]) "invalid_config" x:ident => pure ()

/-- error: unknown capture failure policy `unknown` -/
#guard_msgs in
script_elab invalidConfig (params := [x(failure := unknown)]) "invalid_config" x:ident => pure ()
