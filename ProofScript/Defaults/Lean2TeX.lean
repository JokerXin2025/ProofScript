import ProofScript.Info.Commands

open ProofScript

/-! Basic expression rendering rules -/

def_info OfNat.ofNat { unwrap := some 1 }
def_info Nat.cast { unwrap := some 2 }
def_info Int.cast { unwrap := some 2 }

def_info Eq { calc_symbol := some "=" }
def_info Ne { calc_symbol := some "\\ne" }
def_info LT.lt { calc_symbol := some "<" }
def_info LE.le { calc_symbol := some "\\leqslant" }
def_info GT.gt { calc_symbol := some ">" }
def_info GE.ge { calc_symbol := some "\\geqslant" }

phrase_info "forall" { template := [
  { lang := "zh", content := "${body}对一切 $${binder}\\in ${type}$ 成立" },
  { lang := "en", content := "${body} holds for every $${binder}\\in ${type}$" }
] }
phrase_info "exists" { template := [
  { lang := "zh", content := "存在 $${binder}\\in ${type}$ 使得${body}" },
  { lang := "en", content := "there exists $${binder}\\in ${type}$ such that ${body}" }
] }

def_info HAdd.hAdd { kind := operator, arguments := explicit, styles := [
  { name := "formula", template := "#0+#1", fixity := «infix», precedence := 65,
    associativity := left }
] }
def_info HMul.hMul { kind := operator, arguments := explicit, styles := [
  { name := "formula", template := "#0\\cdot #1", fixity := «infix», precedence := 70,
    associativity := left }
] }
def_info HPow.hPow { kind := operator, arguments := explicit, styles := [
  { name := "formula", template := "{#0}^{#1}", fixity := «infix», precedence := 80,
    associativity := right, isolated_arguments := [1] }
] }

def_info And { kind := logic, arguments := explicit, styles := [
  { name := "formula", mode := text, template := "#0且#1", fixity := «infix», precedence := 40, associativity := left },
  { name := "prose-zh", mode := text, template := "#0且#1", fixity := «infix», precedence := 40, associativity := left },
  { name := "prose-en", mode := text, template := "#0 and #1", fixity := «infix», precedence := 40, associativity := left },
  { name := "debug", mode := text, template := "And(#0, #1)", fixity := custom, precedence := 100, associativity := none }
] }
def_info Not { kind := logic, arguments := explicit, styles := [
  { name := "formula", mode := text, template := "命题#0不成立", fixity := «prefix», precedence := 45 },
  { name := "prose-zh", mode := text, template := "命题#0不成立", fixity := «prefix», precedence := 45 },
  { name := "prose-en", mode := text, template := "proposition #0 is false", fixity := «prefix», precedence := 45 }
] }
def_info True { kind := const, arguments := [], styles := [
  { name := "formula", mode := text, template := "虚真" },
  { name := "prose-zh", mode := text, template := "虚真" },
  { name := "prose-en", mode := text, template := "true" }
] }
def_info False { kind := const, arguments := [], styles := [
  { name := "formula", mode := text, template := "矛盾" },
  { name := "prose-zh", mode := text, template := "矛盾" },
  { name := "prose-en", mode := text, template := "false" }
] }
def_info Or { kind := logic, arguments := explicit, styles := [
  { name := "formula", mode := text, template := "#0或#1", fixity := «infix», precedence := 35, associativity := left },
  { name := "prose-zh", mode := text, template := "#0或#1", fixity := «infix», precedence := 35, associativity := left },
  { name := "prose-en", mode := text, template := "#0 or #1", fixity := «infix», precedence := 35, associativity := left }
] }
def_info Iff { kind := logic, arguments := explicit, styles := [
  { name := "formula", mode := text, template := "#0当且仅当#1", fixity := «infix», precedence := 25 },
  { name := "prose-zh", mode := text, template := "#0当且仅当#1", fixity := «infix», precedence := 25 },
  { name := "prose-en", mode := text, template := "#0 if and only if #1", fixity := «infix», precedence := 25 }
] }

def_info Nat.succ { kind := operator, arguments := explicit, styles := [
  { name := "formula", template := "#0+1", fixity := «infix», precedence := 65, associativity := left }
] }
def_info HSub.hSub { kind := operator, arguments := explicit, styles := [
  { name := "formula", template := "#0-#1", fixity := «infix», precedence := 65, associativity := left }
] }
def_info HDiv.hDiv { kind := operator, arguments := explicit, styles := [
  { name := "formula", template := "\\frac{#0}{#1}", fixity := «infix», precedence := 70,
    isolated_arguments := [0, 1] }
] }
def_info Neg.neg { kind := operator, arguments := explicit, styles := [
  { name := "formula", template := "-#0", fixity := «prefix», precedence := 75 }
] }
def_info Inv.inv { kind := operator, arguments := explicit, styles := [
  { name := "formula", template := "{#0}^{-1}", fixity := «postfix», precedence := 80 }
] }
def_info Dvd.dvd { kind := relation, arguments := explicit, styles := [
  { name := "formula", template := "#0\\mid #1", fixity := «infix», precedence := 50 }
] }
def_info Nat { kind := const, arguments := [], styles := [
  { name := "formula", template := "\\mathbb{N}", fixity := atom, precedence := 100 },
  { name := "Mathbb", template := "\\mathbb{N}", fixity := atom, precedence := 100 },
  { name := "Mathbf", template := "\\mathbf{N}", fixity := atom, precedence := 100 }
] }
def_info And.left { kind := projection, arguments := explicit, styles := [
  { name := "formula", template := "#0", fixity := atom, precedence := 100 }
] }
def_info And.right { kind := projection, arguments := explicit, styles := [
  { name := "formula", template := "#0", fixity := atom, precedence := 100 }
] }
def_info Or.inl { kind := constructor, arguments := explicit, styles := [
  { name := "formula", template := "#0", fixity := atom, precedence := 100 }
] }
def_info Or.inr { kind := constructor, arguments := explicit, styles := [
  { name := "formula", template := "#0", fixity := atom, precedence := 100 }
] }
def_info Membership.mem { kind := relation, arguments := explicit, styles := [
  { name := "formula", template := "#0\\in #1", fixity := «infix», precedence := 50 }
] }
def_info Inter.inter { kind := operator, arguments := explicit, styles := [
  { name := "formula", template := "#0\\cap #1", fixity := «infix», precedence := 70, associativity := left }
] }

var_info "Real" { default := "x", names := ["x", "y", "z", "a", "b", "c", "u", "v", "w"] }
var_info "Nat" { default := "n", names := ["n", "m", "i", "j", "k", "p", "q"] }
var_info "Int" { default := "n", names := ["n", "m", "i", "j", "k", "p", "q"] }
var_info "Rat" { default := "q", names := ["r", "s", "t"] }
var_info "Prop" { default := "P", names := ["P", "Q", "R", "S", "T"] }
var_info "Proof" { default := "h", names := ["h", "h_1", "h_2", "h_3"] }
var_info "Type" { default := "α", names := ["\\alpha", "\\beta", "\\gamma", "\\delta"] }
var_info "Function" { default := "f", names := ["f", "g", "h", "u", "v"] }
