import ProofScript
import Mathlib

/-!
  Mathematical-analysis expression gallery: actual limits, finite sums,
  interval integrals and derivatives in checked theorem statements. Proofs are
  omitted because the page exercises statement rendering and template switching.
  `lake build +Test.PageTheoremExpressionInteractions:ps4html`
  Exceptional rendering cases live in Test.PageTheoremExpressionBoundaries.
-/

set_option pageBuild true

open ProofScript Filter Topology Finset intervalIntegral

namespace PageTheoremExpressionInteractions

-- These are display configurations for genuine Mathlib declarations, not
-- stand-in predicates. Automatic arity selects explicit arguments only; no
-- template refers to typeclass instances or implicit type parameters.
decl_info nhds { concept_info := { templates := [
  { label := "formula", content := "\\mathcal{N}(#0)" },
  { label := "neighborhood", lang := zh, content := "\\operatorname{nhds}(#0)" },
  { label := "neighborhood", lang := en, content := "\\operatorname{nhds}(#0)" }
] } }
decl_info Filter.atTop { concept_info := { templates := [
  { label := "formula", content := "\\operatorname{atTop}" },
  { label := "symbol", lang := zh, content := "\\infty" },
  { label := "symbol", lang := en, content := "\\infty" }
] } }
decl_info Finset.range { concept_info := { templates := [
  { label := "formula", content := "\\{0,\\ldots,#0-1\\}" },
  { label := "range", lang := zh, content := "\\operatorname{range}(#0)" },
  { label := "range", lang := en, content := "\\operatorname{range}(#0)" }
] } }
decl_info abs { concept_info := { templates := [
  { label := "formula", content := "\\left|#0\\right|", isolated_arguments := [0] },
  { label := "function", lang := zh, content := "\\operatorname{abs}(#0)" },
  { label := "function", lang := en, content := "\\operatorname{abs}(#0)" }
] } }
decl_info MeasureTheory.MeasureSpace.volume { concept_info := { templates := [
  { label := "formula", content := "\\mathrm{d}x" },
  { label := "measure", lang := zh, content := "\\operatorname{vol}" },
  { label := "measure", lang := en, content := "\\operatorname{vol}" }
] } }
decl_info Filter.Tendsto { concept_info := { templates := [
  { label := "formula", content := "#0\\xrightarrow[#1]{}#2" },
  { label := "prose", lang := zh, mode := text, content := "#0沿着#1收敛到#2" },
  { label := "prose", lang := en, mode := text, content := "#0 converges to #2 along #1" }
] } }
decl_info Finset.sum { concept_info := { default := "display", templates := [
  { label := "formula", content := "\\sum_{@1\\in #0}@@1", binders := [(1, 1)] },
  { label := "display", lang := zh, content := "\\displaystyle\\sum_{@1\\in #0}@@1", binders := [(1, 1)] },
  { label := "display", lang := en, content := "\\displaystyle\\sum_{@1\\in #0}@@1", binders := [(1, 1)] },
  { label := "function", lang := zh, content := "\\operatorname{sum}(#0,#1)" },
  { label := "function", lang := en, content := "\\operatorname{sum}(#0,#1)" }
] } }
decl_info intervalIntegral { concept_info := { default := "display", templates := [
  { label := "formula", content := "\\int_{#1}^{#2}@@0\\,\\mathrm{d}@0",
    binders := [(0, 1)] },
  { label := "display", lang := zh, content := "\\displaystyle\\int_{#1}^{#2}@@0\\,\\mathrm{d}@0",
    binders := [(0, 1)] },
  { label := "display", lang := en, content := "\\displaystyle\\int_{#1}^{#2}@@0\\,\\mathrm{d}@0",
    binders := [(0, 1)] },
  { label := "function", lang := zh, content := "\\operatorname{integral}(#0,#1,#2)" },
  { label := "function", lang := en, content := "\\operatorname{integral}(#0,#1,#2)" }
] } }
decl_info HasDerivAt { concept_info := { templates := [
  { label := "formula", content := "#0'(#2)=#1" },
  { label := "prose", lang := zh, mode := text, content := "函数#0在#2处的导数等于#1" },
  { label := "prose", lang := en, mode := text, content := "the derivative of #0 at #2 equals #1" }
] } }
decl_info ContinuousAt { concept_info := { templates := [
  { label := "formula", content := "#0\\text{ 在 }#1\\text{ 处连续}" },
  { label := "prose", lang := zh, mode := text, content := "函数#0在#1处连续" },
  { label := "prose", lang := en, mode := text, content := "#0 is continuous at #1" }
] } }
decl_info Continuous { concept_info := { templates := [
  { label := "formula", content := "\\operatorname{Continuous}(#0)" },
  { label := "prose", lang := zh, mode := text, content := "函数#0连续" },
  { label := "prose", lang := en, mode := text, content := "#0 is continuous" }
] } }

-- Function limit at a point: nested composition, arithmetic and a genuine
-- neighborhood filter rather than an artificial limit predicate.
#page theorem interaction_limit_composition (f g : ℝ → ℝ) (a b c : ℝ)
    (hf : Tendsto f (𝓝 a) (𝓝 b)) (hg : Tendsto g (𝓝 b) (𝓝 c)) :
    Tendsto (fun x : ℝ => g (f x)) (𝓝 a) (𝓝 c) := by
  admit

-- The atTop filter gives a sequence limit; this also shows literal numerals,
-- exponentiation and the same bound variable in several subexpressions.
#page theorem interaction_sequence_limit (a : ℕ → ℝ) (L : ℝ)
    (ha : Tendsto a atTop (𝓝 L)) :
    Tendsto (fun n : ℕ => a n + (1 : ℝ) / (n + 1)) atTop (𝓝 L) := by
  admit

-- A finite sum with a lambda summand and an index range, as in the usual
-- formula for the sum of the first n natural numbers.
#page theorem interaction_finite_sum (n : ℕ) :
    (∑ k ∈ Finset.range n, (k : ℝ)) = (n * (n - 1) : ℝ) / 2 := by
  admit

-- Linearity of finite sums exercises separate sum occurrences, scalar
-- multiplication and the variable-dependent summand.
#page theorem interaction_sum_linearity (s : Finset ℕ) (a b : ℕ → ℝ) :
    (∑ k ∈ s, (2 : ℝ) * a k + b k) =
      2 * (∑ k ∈ s, a k) + ∑ k ∈ s, b k := by
  admit

-- A concrete interval integral keeps both bound expressions and its function
-- argument visible to the formula / expanded template switcher.
#page theorem interaction_integral_linearity (f g : ℝ → ℝ) (a b : ℝ) :
    (∫ x in a..b, (f x + 2 * g x)) =
      (∫ x in a..b, f x) + 2 * (∫ x in a..b, g x) := by
  admit

-- Fundamental theorem of calculus: the integral has a variable upper bound,
-- so the renderer displays an integral nested inside a derivative statement.
#page theorem interaction_fundamental_theorem (f : ℝ → ℝ) (a x : ℝ)
    (hf : Continuous f) :
    HasDerivAt (fun t : ℝ => ∫ y in a..t, f y) (f x) x := by
  admit

-- A two-step calculation yields consecutive native let expressions for the
-- default "result, where …" layout and the inline / stacked alternatives.
#page theorem interaction_partial_sums (a : ℕ → ℝ) (n : ℕ) :
    (let partialSum := ∑ k ∈ Finset.range n, a k
     let next := partialSum + a n
     next) = ∑ k ∈ Finset.range (n + 1), a k := by
  admit

-- Derivative rules exercise both HasDerivAt's prose template and distinct
-- binder identities for the two function arguments.
#page theorem interaction_product_derivative (f g : ℝ → ℝ)
    (x f' g' : ℝ) (hf : HasDerivAt f f' x) (hg : HasDerivAt g g' x) :
    HasDerivAt (fun t : ℝ => f t * g t) (f' * g x + f x * g') x := by
  admit

-- Equivalence between continuity and a neighborhood-limit condition puts
-- different prose/formula templates on both sides of a logical connective.
#page theorem interaction_continuity_criterion (f : ℝ → ℝ) (x : ℝ) :
    ContinuousAt f x ↔ Tendsto f (𝓝 x) (𝓝 (f x)) := by
  admit

-- An epsilon-delta characterization supplies alternating dependent binders,
-- inequalities, an existential witness and the application f y.
#page theorem interaction_epsilon_delta (f : ℝ → ℝ) (x : ℝ) :
    ContinuousAt f x →
      ∀ ε : ℝ, 0 < ε → ∃ δ : ℝ, 0 < δ ∧
        ∀ y : ℝ, |y - x| < δ → |f y - f x| < ε := by
  admit

-- A convergence hypothesis for partial sums connects the finite-sum and
-- limit menus in a single expression tree.
#page theorem interaction_series_limit (a : ℕ → ℝ) (L : ℝ) :
    Tendsto (fun n : ℕ => ∑ k ∈ Finset.range n, a k) atTop (𝓝 L) →
      ∀ ε : ℝ, 0 < ε → ∃ N : ℕ, ∀ n : ℕ, N ≤ n →
        |(∑ k ∈ Finset.range n, a k) - L| < ε := by
  admit

#page end

end PageTheoremExpressionInteractions
