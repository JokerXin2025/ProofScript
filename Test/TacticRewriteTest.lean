import ProofScript

-- The recorder binds a different name, while its default action executes the
-- original registration with the original argument syntax.
script_macro «recordedIdentity»
"recorded_identity" _proof:term => `(tactic| exact $_proof)

script_recorder «recordedIdentity»
(fields := #[{ name := "proof", schema := .expression, nullable := false }])
"recorded_identity" proof:term => do
  ProofScript.recordStep []
    (parameters := { parameters := #[
      ProofScript.Recording.param (.category `term) "proof" .before proof .required
    ] })

open Lean Elab Command ProofScript in
run_cmd do
  let id := `Test.TacticRewriteTest.recordedIdentity
  let events := scriptRegistrationExt.getState (← getEnv)
  let some manualKind := (events.findSome? fun event =>
      match event with
      | .setRecorder ruleId kind _ => if ruleId == id then some kind else none
      | .register _ => none)
    | throwError "handwritten recorder did not override the automatic registration"
  let some registration := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == id)
    | throwError "missing recorded identity registration"
  unless registration.recordingKind == some manualKind do
    throwError "handwritten recorder was not selected"

@theorem recorded_identity_default_action (P : Prop) (h : P) : P := script
  recorded_identity h

theorem projection_test (P : Prop) : ¬ (P ∧ ¬ P) := script
  contra h
  | proof =>
    unpack_and ⟨hP, hNP⟩ := h
    contradiction

theorem nested_application_test (P : Prop) (h : P) : P := script
  assumption

theorem named_projection_test (P Q : Prop) (h : P ∧ Q) : P := script
  unpack_and ⟨hP, _hQ⟩ := h
  assumption

theorem numeric_term_test : 1 + 1 = 2 := script
  rfl

theorem string_argument_test (P : Prop) (h : P) : P := script
  remark "field .1 and number 42"
  assumption

theorem native_name_choice_test (P : Prop) : P ∨ ¬ P := script
  cases_on P
  | true h =>
    left
    assumption
  | false h =>
    right
    assumption

theorem recorded_projection_test (P : Prop) : ¬ (P ∧ ¬ P) := script
  contra h
  | proof =>
    unpack_and ⟨hP, hNP⟩ := h
    contradiction

theorem recorded_arguments_test (P Q : Prop) (h : P ∧ Q) : P := script
  remark "field .1 and number 42"
  unpack_and ⟨hP, _hQ⟩ := h
  assumption

theorem prefixed_unpack_and_test (P Q : Prop) (h : P ∧ Q) : P := by
  script_unpack_and ⟨hP, _hQ⟩ := h
  exact hP

theorem prefixed_unpack_iff_test (P Q : Prop) (h : P ↔ Q) : P → Q := by
  script_unpack_iff ⟨hForward, _hBackward⟩ := h
  exact hForward

theorem prefixed_obtain_exist_test (p : Nat → Prop) (h : ∃ n, p n) : ∃ n, p n := by
  script_obtain_exist ⟨n, hn⟩ := h
  exact Exists.intro n hn
