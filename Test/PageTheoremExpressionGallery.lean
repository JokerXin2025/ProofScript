import Test.SharedDeclInfo
import ProofScript
import Lean

/-!
  Nine checked statement-rendering fixtures. Build and render with
  `lake build +Test.PageTheoremExpressionGallery:ps4html`.
  An unassigned Expr.mvar or Level.mvar cannot survive kernel checking in a
  theorem statement; the universe case therefore uses genuine universe
  parameters and quantified unknowns rather than an unassigned metavariable.
-/

set_option pageBuild true

open ProofScript

namespace PageTheoremExpressionGallery

-- The explicit Nat.add head and projections belong to this expression-shape fixture.
decl_info infixl Nat.add "+" (mode := formula, precedence := 65)
decl_info Prod.fst { templates := [
  { label := "formula", content := template%:90 ${ "\\operatorname{first}(" arg(0) ")" }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{fst}(" arg(0) ")" }$ }
] }
decl_info Prod.snd { templates := [
  { label := "formula", content := template%:90 ${ "\\operatorname{second}(" arg(0) ")" }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{snd}(" arg(0) ")" }$ }
] }

universe u v

def shift (n : Nat) : Nat := n + 1
def combine (a b : Nat) : Nat := a + b
def boxed (n : Nat) : Nat := n
def startsWith (_ : String) (_ : Nat) : Prop := True
def pairLeft (a b : Nat) : Nat × Nat := (a, b)
def agrees (a b : Nat) : Prop := a = b
def tagged (n : Nat) : Nat := n

structure GalleryPair where
  first : Nat
  second : Nat

-- The ordinary `.first` notation elaborates to an accessor application. Build
-- the native Expr.proj form explicitly to cover the renderer's projection node.
elab "nativeFirst " p:term : term => do
  let pair ← Lean.Elab.Term.elabTerm p (some (Lean.mkConst ``GalleryPair))
  pure (.proj ``GalleryPair 0 pair)

decl_info shift { names := [{ lang := zh, value := "后继变换" }], templates := [
  { label := "formula", content := template%:90 ${ "\\operatorname{shift}(" arg(0) ")" }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{next}(" arg(0) ")" }$ },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{后继}(" arg(0) ")" }$ }
] }
decl_info combine { names := [{ lang := zh, value := "合并" }], templates := [
  { label := "formula", content := template%:65 ${ arg(0) "\\oplus " arg(1) }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{combine}(" arg(0) "," arg(1) ")" }$ },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{合并}(" arg(0) "," arg(1) ")" }$ }
] }
-- A wrapper ignores its own templates. Symbolic kinds below share the
-- ordinary template list and retain the shorthand-generated first choice.
decl_info wrapper boxed 0
decl_info boxed { names := [{ lang := zh, value := "装箱" }], templates := [
  { label := "formula", content := template% ${ arg(0) }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{box}(" arg(0) ")" }$ }
] }
decl_info startsWith { templates := [
  { label := "formula", content := template%:50 ${ "\\operatorname{startsWith}(" arg(0) "," arg(1) ")" }$ },
  { label := "prose", lang := en, content := template%:50 { arg(1) " begins with " arg(0) } },
  { label := "prose", lang := zh, content := template%:50 { arg(1) "以" arg(0) "开头" } }
] }
decl_info pairLeft { templates := [
  { label := "formula", content := template%:100 ${ "(" arg(0) "," arg(1) ")" }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{pair}(" arg(0) "," arg(1) ")" }$ },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{有序对}(" arg(0) "," arg(1) ")" }$ }
] }
decl_info tagged { templates := [
  { label := "formula", content := template%:100 ${ "\\langle " arg(0) "\\rangle" }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{tag}(" arg(0) ")" }$ },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{标记}(" arg(0) ")" }$ }
] }
decl_info relation agrees "\\simeq" (mode := formula)
decl_info agrees { calc_symbol := "≃" }
decl_info GalleryPair.first { templates := [
  { label := "formula", content := template%:90 ${ "\\operatorname{first}(" arg(0) ")" }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{field}(" arg(0) ")" }$ }
] }

-- Ordinary and higher-order lambdas: bound indices and free parameters coexist.
#page theorem nested_lambdas (f : Nat → Nat) (x : Nat) :
    (fun a : Nat => fun b : Nat => fun c : Nat => f (combine (a + b) c)) x x x = f (combine (x + x) x) := by sorry
theorem_info nested_lambdas { names := [{ lang := zh, value := "多层（元）常规lambda函数" }] }

-- Dependent binders alternate with non-dependent implication arrows.
#page theorem alternating_binders (x : Nat) (h : x = x) :
    (∀ a : Nat, a = a → ∀ b : Nat, b = b → ∀ c : Nat, combine a (combine b c) = combine a (combine b c)) := by sorry
theorem_info alternating_binders { names := [{ lang := zh, value := "多层（元）依赖/非依赖交替链" }] }

#page theorem nested_lets (x : Nat) :
    (let first := shift x
     let second := combine first x
     let third := combine second first
     third) = combine (combine (shift x) x) (shift x) := by sorry
theorem_info nested_lets { names := [{ lang := zh, value := "多层（元）let语句" }] }

#page theorem universe_and_unknowns (α : Type u) (β : Type v) :
    (∀ _ : Sort (max u v), True) ∧ (∀ _ : Sort (imax u v), True) ∧
      (∀ _ : Type 1, True) := by sorry
theorem_info universe_and_unknowns { names := [{ lang := zh, value := "宇宙类型和元变量" }] }

#page theorem numeral_and_string (x : Nat) :
    startsWith "数学<&>" (combine x 10000) ∧ startsWith "" (shift 0) := by sorry
theorem_info numeral_and_string { names := [{ lang := zh, value := "数字字面量与字符串字面量" }] }

#page theorem bare_names (x : Nat) :
    (let unapplied := shift
     unapplied x = shift x) ∧
      (let proof := nested_lets x
       proof = proof) := by sorry
theorem_info bare_names { names := [{ lang := zh, value := "裸常量与定理名称" }] }

#page theorem application_shapes (x y : Nat) (f : Nat → Nat → Nat) :
    (let partiallyApplied := combine x
     partiallyApplied y = combine x y) ∧
      f (combine x y) (boxed (shift y)) = f (combine x y) (boxed (shift y)) ∧
      tagged (boxed (combine x y)) = tagged (combine x y) := by sorry
theorem_info application_shapes { names := [{ lang := zh, value := "部分应用、concept完全应用与包装器" }] }

#page theorem symbolic_layout (x y z : Nat) :
    agrees (x + y) (y + x) ∧ (x + y) + z = x + (y + z) := by sorry
theorem_info symbolic_layout { names := [{ lang := zh, value := "运算符与关系符" }] }

#page theorem projection_layout (x y : Nat) (p : GalleryPair) :
    (pairLeft x y).1 = x ∧ (pairLeft x y).2 = y ∧
      (nativeFirst p) = p.first := by sorry
theorem_info projection_layout { names := [{ lang := zh, value := "投影" }] }


end PageTheoremExpressionGallery
