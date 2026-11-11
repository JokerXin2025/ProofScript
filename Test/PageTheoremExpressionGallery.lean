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

decl_info shift { name := "后继变换", «concept_info» := { templates := [
  { label := "formula", content := "\\operatorname{shift}(#0)" },
  { label := "call", lang := en, content := "\\operatorname{next}(#0)" },
  { label := "call", lang := zh, content := "\\operatorname{后继}(#0)" }
] } }
decl_info combine { name := "合并", «concept_info» := { templates := [
  { label := "formula", content := "#0\\oplus #1" },
  { label := "call", lang := en, content := "\\operatorname{combine}(#0,#1)" },
  { label := "call", lang := zh, content := "\\operatorname{合并}(#0,#1)" }
] } }
-- Wrapper layouts and symbolic kinds are intentionally configured via their
-- dedicated commands; those kinds do not consume concept templates.
wrapper_info boxed { index := some 0 }
decl_info boxed { name := "装箱", «concept_info» := { templates := [
  { label := "formula", content := "#0" },
  { label := "call", lang := en, content := "\\operatorname{box}(#0)" }
] } }
decl_info startsWith { «concept_info» := { templates := [
  { label := "formula", content := "\\operatorname{startsWith}(#0,#1)" },
  { label := "prose", lang := en, mode := text, content := "#1 begins with #0" },
  { label := "prose", lang := zh, mode := text, content := "#1以#0开头" }
] } }
decl_info pairLeft { «concept_info» := { templates := [
  { label := "formula", content := "(#0,#1)" },
  { label := "call", lang := en, content := "\\operatorname{pair}(#0,#1)" },
  { label := "call", lang := zh, content := "\\operatorname{有序对}(#0,#1)" }
] } }
decl_info tagged { «concept_info» := { templates := [
  { label := "formula", content := "\\langle #0\\rangle" },
  { label := "call", lang := en, content := "\\operatorname{tag}(#0)" },
  { label := "call", lang := zh, content := "\\operatorname{标记}(#0)" }
] } }
relation_info agrees { symbol := "\\simeq" }
decl_info agrees { «concept_info» := { templates := [
  { label := "formula", content := "#0\\simeq #1" },
  { label := "call", lang := en, content := "\\operatorname{agrees}(#0,#1)" }
] } }
operator_info Nat.add { symbol := "+", fixity := «infix», precedence := 65, associativity := left }
decl_info Nat.add { «concept_info» := { templates := [
  { label := "formula", content := "#0+#1" },
  { label := "call", lang := en, content := "\\operatorname{add}(#0,#1)" }
] } }
decl_info Eq { «concept_info» := { templates := [
  { label := "formula", content := "#0=#1" },
  { label := "call", lang := en, content := "\\operatorname{equal}(#0,#1)" },
  { label := "call", lang := zh, content := "\\operatorname{等于}(#0,#1)" }
] } }
decl_info Prod.fst { «concept_info» := { templates := [
  { label := "formula", content := "\\operatorname{first}(#0)" },
  { label := "call", lang := en, content := "\\operatorname{fst}(#0)" }
] } }
decl_info Prod.snd { «concept_info» := { templates := [
  { label := "formula", content := "\\operatorname{second}(#0)" },
  { label := "call", lang := en, content := "\\operatorname{snd}(#0)" }
] } }
decl_info GalleryPair.first { «concept_info» := { templates := [
  { label := "formula", content := "\\operatorname{first}(#0)" },
  { label := "call", lang := en, content := "\\operatorname{field}(#0)" }
] } }
decl_info And { «concept_info» := { templates := [
  { label := "formula", content := "#0\\land #1" },
  { label := "call", lang := en, content := "\\operatorname{both}(#0,#1)" },
  { label := "call", lang := zh, content := "\\operatorname{同时}(#0,#1)" }
] } }

-- Ordinary and higher-order lambdas: bound indices and free parameters coexist.
#page theorem nested_lambdas (f : Nat → Nat) (x : Nat) :
    (fun a : Nat => fun b : Nat => fun c : Nat => f (combine (a + b) c)) x x x = f (combine (x + x) x) := by sorry
theorem_info nested_lambdas { name := "多层（元）常规lambda函数" }

-- Dependent binders alternate with non-dependent implication arrows.
#page theorem alternating_binders (x : Nat) (h : x = x) :
    (∀ a : Nat, a = a → ∀ b : Nat, b = b → ∀ c : Nat, combine a (combine b c) = combine a (combine b c)) := by sorry
theorem_info alternating_binders { name := "多层（元）依赖/非依赖交替链" }

#page theorem nested_lets (x : Nat) :
    (let first := shift x
     let second := combine first x
     let third := combine second first
     third) = combine (combine (shift x) x) (shift x) := by sorry
theorem_info nested_lets { name := "多层（元）let语句" }

#page theorem universe_and_unknowns (α : Type u) (β : Type v) :
    (∀ _ : Sort (max u v), True) ∧ (∀ _ : Sort (imax u v), True) ∧
      (∀ _ : Type 1, True) := by sorry
theorem_info universe_and_unknowns { name := "宇宙类型和元变量" }

#page theorem numeral_and_string (x : Nat) :
    startsWith "数学<&>" (combine x 10000) ∧ startsWith "" (shift 0) := by sorry
theorem_info numeral_and_string { name := "数字字面量与字符串字面量" }

#page theorem bare_names (x : Nat) :
    (let unapplied := shift
     unapplied x = shift x) ∧
      (let proof := nested_lets x
       proof = proof) := by sorry
theorem_info bare_names { name := "裸常量与定理名称" }

#page theorem application_shapes (x y : Nat) (f : Nat → Nat → Nat) :
    (let partiallyApplied := combine x
     partiallyApplied y = combine x y) ∧
      f (combine x y) (boxed (shift y)) = f (combine x y) (boxed (shift y)) ∧
      tagged (boxed (combine x y)) = tagged (combine x y) := by sorry
theorem_info application_shapes { name := "部分应用、concept完全应用与包装器" }

#page theorem symbolic_layout (x y z : Nat) :
    agrees (x + y) (y + x) ∧ (x + y) + z = x + (y + z) := by sorry
theorem_info symbolic_layout { name := "运算符与关系符" }

#page theorem projection_layout (x y : Nat) (p : GalleryPair) :
    (pairLeft x y).1 = x ∧ (pairLeft x y).2 = y ∧
      (nativeFirst p) = p.first := by sorry
theorem_info projection_layout { name := "投影" }


end PageTheoremExpressionGallery
