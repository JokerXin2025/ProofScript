import ProofScript

/-!
  Checked statement-only boundary cases for expression rendering. No proof
  recorder is required; build with
  `lake build +Test.PageTheoremExpressionBoundaries:ps4html`.
  Unassigned Expr.mvar and Level.mvar cannot occur in a kernel-checked theorem
  statement, so neither can be represented in this statement-only gallery.
-/

set_option pageBuild true

open ProofScript

namespace PageTheoremExpressionBoundaries

def BoundaryWrap (value : Nat) := value
def BoundaryAlias {α : Sort u} (a b : α) : Prop := a = b
def BoundaryBinary (a b : Nat) : Nat := a + b

wrapper_info BoundaryWrap { index := some 0 }
alias_info BoundaryAlias { target := some Eq }
decl_info BoundaryBinary { concept_info := { templates := [
    { label := "formula", content := "#0+#1" },
    { label := "call", lang := zh, content := "\\operatorname{binary}(#0,#1)" },
    { label := "call", lang := en, content := "\\operatorname{binary}(#0,#1)" }
  ] } }

def BoundaryLinear (_ : Nat) (_ : String) (_ : Nat) : Prop := True
def BoundaryFraction (_ : Nat) (_ : String) : Prop := True
def BoundaryPower (_ : Nat) (_ : String) : Prop := True

-- The only ungrouped linear template can expose HTML string styles. Fraction
-- and superscript must keep their strings inside KaTeX.
decl_info BoundaryLinear { concept_info := { templates := [{ label := "formula", content := "#0+#1+#2" }] } }
decl_info BoundaryFraction { concept_info := { templates := [{ label := "formula", content := "\\frac{#0}{#1}",
                   isolated_arguments := [0, 1] }] } }
decl_info BoundaryPower { concept_info := { templates := [{ label := "formula", content := "{#0}^{#1}",
                   isolated_arguments := [1] }] } }

-- Wrapper and alias preserve their original application and relation meaning.
#page theorem boundary_wrapper_alias (x y : Nat) :
    BoundaryAlias (BoundaryWrap (x + 1)) (BoundaryWrap (y + 1)) ∧
      BoundaryWrap (x + y) = BoundaryWrap (y + x) := by
  admit

-- Insufficient arguments bypass the configured binary templates; an fvar
-- head exercises the other generic application path.
#page theorem boundary_partial_application (x : Nat) (f : Nat → Nat) :
    BoundaryBinary x = BoundaryBinary x ∧ f (x + 1) = f (x + 1) := by
  admit

-- A dependent -> arrow -> dependent transition must not merge forall chains.
#page theorem boundary_alternating_forall :
    (∀ n : Nat, True → ∀ m : Nat, n = n ∧ m = m) := by
  admit

#page theorem boundary_long_chains :
    (∀ a b c d : Nat, a = a ∧ b = b ∧ c = c ∧ d = d) ∧
      (True → True → True → True) := by
  admit

-- Anonymous arguments and unused binders request generated display names.
#page theorem boundary_anonymous (_ : Nat) (_ : Nat) :
    (fun _ : Nat => True) 1 ∧ (∀ _ : Nat, True) := by
  admit

-- Zero, the Ionian limit and a value beyond the Chinese highest unit.
#page theorem boundary_numeral_limits :
    0 = (0 : Nat) ∧ 10000 = (10000 : Nat) ∧
    1000000000000000000000000000000000000000000000000 =
      (1000000000000000000000000000000000000000000000000 : Nat) := by
  admit

-- The direct literals exercise linear splitting, grouped math, and a generic
-- function call. Empty and escaped strings remain checked statement values.
#page theorem boundary_string_layout (x y : Nat) (f : String → Nat) :
    BoundaryLinear x "加<&>" y ∧
    BoundaryFraction x "分母" ∧ BoundaryPower y "上标" ∧
    f "函数参数" = f "" := by
  admit

-- A direct linear conclusion is a render root, so the literal can actually
-- switch between plain, strong and code HTML rather than only inside And.
#page theorem boundary_linear_literal (x y : Nat) :
    BoundaryLinear x "加<&>" y := by
  admit

universe u v
-- Kernel-checkable sort constructors: zero, succ, param, max and imax.
#page theorem boundary_sort_universes (α : Type u) (β : Type v) :
    (∀ _ : Prop, True) ∧ (∀ _ : Type, True) ∧
    (∀ _ : Type 1, True) ∧ (∀ _ : Sort u, True) ∧
    (∀ _ : Sort (max u v), True) ∧
    (∀ _ : Sort (imax u v), True) := by
  admit

-- The second value sees the first let binder; stacked layout needs a hit
-- target on each row, including the final `in` row.
#page theorem boundary_stacked_let (x : Nat) :
    (let first := x + 1
     let second := first * 2
     second + first) = (x + 1) * 3 := by
  admit

#page end

end PageTheoremExpressionBoundaries
