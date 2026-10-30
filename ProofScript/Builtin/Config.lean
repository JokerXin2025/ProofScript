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

def_info HAdd.hAdd { kind := operator, styles := [
  { name := "formula", template := "#0+#1", fixity := «infix», precedence := 65,
    associativity := left }
] }
def_info HMul.hMul { kind := operator, styles := [
  { name := "formula", template := "#0\\cdot #1", fixity := «infix», precedence := 70,
    associativity := left }
] }
def_info HPow.hPow { kind := operator, styles := [
  { name := "formula", template := "{#0}^{#1}", fixity := «infix», precedence := 80,
    associativity := right, isolated_arguments := [1] }
] }

def_info And { kind := logic, styles := [
  { name := "formula", mode := text, template := "#0且#1", fixity := «infix», precedence := 40, associativity := left },
  { name := "prose-zh", mode := text, template := "#0且#1", fixity := «infix», precedence := 40, associativity := left },
  { name := "prose-en", mode := text, template := "#0 and #1", fixity := «infix», precedence := 40, associativity := left },
  { name := "debug", mode := text, template := "And(#0, #1)", fixity := custom, precedence := 100, associativity := none }
] }
def_info Not { kind := logic, styles := [
  { name := "formula", mode := text, template := "命题#0不成立", fixity := «prefix», precedence := 45 },
  { name := "prose-zh", mode := text, template := "命题#0不成立", fixity := «prefix», precedence := 45 },
  { name := "prose-en", mode := text, template := "proposition #0 is false", fixity := «prefix», precedence := 45 }
] }
def_info True { kind := const, styles := [
  { name := "formula", mode := text, template := "虚真" },
  { name := "prose-zh", mode := text, template := "虚真" },
  { name := "prose-en", mode := text, template := "true" }
] }
def_info False { kind := const, styles := [
  { name := "formula", mode := text, template := "矛盾" },
  { name := "prose-zh", mode := text, template := "矛盾" },
  { name := "prose-en", mode := text, template := "false" }
] }
def_info Or { kind := logic, styles := [
  { name := "formula", mode := text, template := "#0或#1", fixity := «infix», precedence := 35, associativity := left },
  { name := "prose-zh", mode := text, template := "#0或#1", fixity := «infix», precedence := 35, associativity := left },
  { name := "prose-en", mode := text, template := "#0 or #1", fixity := «infix», precedence := 35, associativity := left }
] }
def_info Iff { kind := logic, styles := [
  { name := "formula", mode := text, template := "#0当且仅当#1", fixity := «infix», precedence := 25 },
  { name := "prose-zh", mode := text, template := "#0当且仅当#1", fixity := «infix», precedence := 25 },
  { name := "prose-en", mode := text, template := "#0 if and only if #1", fixity := «infix», precedence := 25 }
] }

def_info Nat.succ { kind := operator, styles := [
  { name := "formula", template := "#0+1", fixity := «infix», precedence := 65, associativity := left }
] }
def_info HSub.hSub { kind := operator, styles := [
  { name := "formula", template := "#0-#1", fixity := «infix», precedence := 65, associativity := left }
] }
def_info HDiv.hDiv { kind := operator, styles := [
  { name := "formula", template := "\\frac{#0}{#1}", fixity := «infix», precedence := 70,
    isolated_arguments := [0, 1] }
] }
def_info Neg.neg { kind := operator, styles := [
  { name := "formula", template := "-#0", fixity := «prefix», precedence := 75 }
] }
def_info Inv.inv { kind := operator, styles := [
  { name := "formula", template := "{#0}^{-1}", fixity := «postfix», precedence := 80 }
] }
def_info Dvd.dvd { kind := relation, styles := [
  { name := "formula", template := "#0\\mid #1", fixity := «infix», precedence := 50 }
] }
def_info Nat { var_name := "n", parameter_template := some "$#self\\in\\mathbb{N}$", kind := const, styles := [
  { name := "formula", template := "\\mathbb{N}", fixity := atom, precedence := 100 },
  { name := "Mathbb", template := "\\mathbb{N}", fixity := atom, precedence := 100 },
  { name := "Mathbf", template := "\\mathbf{N}", fixity := atom, precedence := 100 }
] }
def_info And.left { kind := projection, styles := [
  { name := "formula", template := "#0", fixity := atom, precedence := 100 }
] }
def_info And.right { kind := projection, styles := [
  { name := "formula", template := "#0", fixity := atom, precedence := 100 }
] }
def_info Or.inl { kind := constructor, styles := [
  { name := "formula", template := "#0", fixity := atom, precedence := 100 }
] }
def_info Or.inr { kind := constructor, styles := [
  { name := "formula", template := "#0", fixity := atom, precedence := 100 }
] }
def_info Membership.mem { kind := relation, styles := [
  { name := "formula", template := "#0\\in #1", fixity := «infix», precedence := 50 }
] }
def_info Inter.inter { kind := operator, styles := [
  { name := "formula", template := "#0\\cap #1", fixity := «infix», precedence := 70, associativity := left }
] }

def_info Int { var_name := "n", parameter_template := some "$#self\\in\\mathbb{Z}$" }
def_info Rat { var_name := "q", parameter_template := some "$#self\\in\\mathbb{Q}$" }
