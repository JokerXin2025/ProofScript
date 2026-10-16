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
