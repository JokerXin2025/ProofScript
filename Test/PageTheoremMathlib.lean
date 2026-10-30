import ProofScript
import Mathlib

/-
  A deliberately varied page-theorem fixture.  This module is page-built so it
  exercises the proof recorder, the native theorem declaration, and the page
  component transaction at the same time.
-/
set_option proofScript.pageBuild true
set_option linter.defProp false

open scoped BigOperators
open Lean Elab Command ProofScript

namespace PageTheoremMathlib

/- The `by` path with a polymorphic algebraic structure and an instance binder. -/
/-- Left distributivity is preserved by the `#page theorem` declaration path. -/
#page theorem commring_left_distrib
    {R : Type*} [CommRing R] (a b c : R) :
    a * (b + c) = a * b + a * c := by
  ring

/- The `script` path with a Mathlib arithmetic tactic. -/
#page theorem nat_binomial_square (n : ℕ) :
    (n + 1) ^ 2 = n ^ 2 + 2 * n + 1 := script
  ring

#page theorem integer_affine_monotone (a b : ℤ) (h : a ≤ b) :
    5 * a - 7 ≤ 5 * b - 7 := script
  omega

#page theorem real_square_nonnegative (x : ℝ) :
    0 ≤ (x - 3) ^ 2 := by
  positivity

/- This uses a previous page theorem as a normal Lean declaration. -/
#page theorem positive_affine (x : ℝ) (hx : 0 ≤ x) :
    0 ≤ x + 1 := by
  linarith

#page theorem positive_affine_twice (x : ℝ) (hx : 0 ≤ x) :
    0 ≤ (x + 1) + 1 := by
  have h₁ := positive_affine x hx
  linarith

/- Field syntax, side conditions, and a native Mathlib tactic. -/
#page theorem rational_cancel (x : ℚ) (hx : x ≠ 0) :
    x / x = 1 := by
  field_simp [hx]

/- Big operators and finite containers. -/
#page theorem finite_range_card (n : ℕ) :
    (Finset.range n).card = n := by
  simp

#page theorem sum_range_constant (n : ℕ) :
    (∑ _ ∈ Finset.range n, (1 : ℤ)) = n := by
  simp

/- Set image/preimage syntax with implicit type parameters. -/
#page theorem image_preimage_subset
    {α β : Type*} (f : α → β) (s : Set β) :
    f '' (f ⁻¹' s) ⊆ s := by
  intro y hy
  rcases hy with ⟨x, hx, rfl⟩
  exact hx

/- Function extensionality with dependent implicit type parameters. -/
#page theorem function_extensionality_example
    {α β : Type*} (f g : α → β) (h : ∀ x, f x = g x) :
    f = g := by
  funext x
  exact h x

/- Strategy branches, conjunctions, and a proof that mixes native arithmetic. -/
#page theorem arithmetic_conjunction (a b : ℤ) (h : a ≤ b) :
    a ≤ b ∧ a + 1 ≤ b + 1 := script
  split_and
  | left => assumption
  | right => omega

/- Existential construction and normalization of a concrete Mathlib expression. -/
#page theorem exists_square_seven : ∃ n : ℕ, n ^ 2 = 49 := by
  exact ⟨7, by norm_num⟩

/- A recursive proposition with a nontrivial induction proof. -/
#page theorem list_append_length
    {α : Type*} (xs ys : List α) :
    (xs ++ ys).length = xs.length + ys.length := by
  simp

/- An explicit equivalence gives the parser a Unicode connective and both
   directions of an implication. -/
#page theorem iff_swap (P Q : Prop) : P ∧ Q ↔ Q ∧ P := by
  constructor <;> intro h
  · exact ⟨h.2, h.1⟩
  · exact ⟨h.2, h.1⟩

#page end

run_cmd do
  let env ← getEnv
  let moduleName ← getMainModule
  let state := getPageState env
  unless state.closed do
    throwError "#page theorem Mathlib fixture did not close its page"
  unless state.components.size == 15 do
    throwError m!"expected 15 theorem components, got {state.components.size}"
  unless state.components.all (·.kind == "theorem") do
    throwError "the fixture contains a non-theorem page component"
  let some page := modulePageDraft? env moduleName
    | throwError "#page theorem Mathlib fixture did not persist a page draft"
  unless page.components.size == state.components.size do
    throwError "the persisted page draft lost theorem components"
  let names : Array Name := #[
    `commring_left_distrib,
    `nat_binomial_square,
    `integer_affine_monotone,
    `real_square_nonnegative,
    `positive_affine,
    `positive_affine_twice,
    `rational_cancel,
    `finite_range_card,
    `sum_range_constant,
    `image_preimage_subset,
    `function_extensionality_example,
    `arithmetic_conjunction,
    `exists_square_seven,
    `list_append_length,
    `iff_swap]
  unless names.size == state.components.size do
    throwError "the fixture's theorem name list is out of sync"
  for name in names do
    let declaration := (← getCurrNamespace) ++ name
    unless (env.find? declaration).any (fun info => match info with
      | .thmInfo _ => true
      | _ => false) do
      throwError m!"missing native theorem declaration {declaration}"
  for (component, name) in state.components.zip names do
    unless component.declaration == some ((← getCurrNamespace) ++ name) do
      throwError m!"component order or identity changed for {name}"
  let artifactCount := (moduleArtifacts env moduleName)
    |>.filter (fun artifact => artifact.key.kind == .proof) |>.size
  unless artifactCount == names.size do
    throwError m!"expected one proof artifact per theorem, got {artifactCount}"

end PageTheoremMathlib
