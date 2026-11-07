import ProofScript.Info.Commands

open ProofScript

/-! Basic expression rendering rules -/

wrapper_info OfNat.ofNat { index := some 1 }
wrapper_info Nat.cast { index := some 2 }
wrapper_info Int.cast { index := some 2 }

relation_info Eq { symbol := "=" }
relation_info Ne { symbol := "\\ne" }
relation_info LT.lt { symbol := "<" }
relation_info LE.le { symbol := "\\leqslant" }
relation_info GT.gt { symbol := ">" }
relation_info GE.ge { symbol := "\\geqslant" }

decl_info Exists { concept_info := { default := "text", auto_arity := false, templates := [
  { label := "formula", content := "\\exists\\ @1\\in #0,\\ @@1", binders := [(1, 1)] },
  { label := "function", lang := some en, content := "\\operatorname{Exists}(#0,#1)" },
  { label := "text", lang := some zh, mode := text,
    content := "存在 $@1\\in #0$ 使得@@1",
    binders := [(1, 1)] },
  { label := "text", lang := some en, mode := text,
    content := "there exists $@1\\in #0$ such that @@1",
    binders := [(1, 1)] }
] } }

operator_info HAdd.hAdd { symbol := "+", fixity := «infix», precedence := 65, associativity := left }
operator_info HMul.hMul { symbol := "\\cdot", fixity := «infix», precedence := 70, associativity := left }
decl_info HPow.hPow { concept_info := { templates := [
  { label := "formula", content := "{#0}^{#1}", isolated_arguments := [1] }
] } }

decl_info And { concept_info := { default := "plain", templates := [
  { label := "formula", content := "#0\\land #1" },
  { label := "plain", lang := zh, mode := text, content := "#0且#1" },
  { label := "plain", lang := en, mode := text, content := "#0 and #1" },
  { label := "debug", lang := en, mode := text, content := "And(#0, #1)" }
] } }
decl_info Not { concept_info := { default := "plain", templates := [
  { label := "formula", mode := text, content := "命题#0不成立" },
  { label := "plain", lang := zh, mode := text, content := "命题#0不成立" },
  { label := "plain", lang := en, mode := text, content := "proposition #0 is false" }
] } }
decl_info True { concept_info := { default := "plain", templates := [
  { label := "formula", mode := text, content := "虚真" },
  { label := "plain", lang := zh, mode := text, content := "虚真" },
  { label := "plain", lang := en, mode := text, content := "true" }
] } }
decl_info False { concept_info := { default := "plain", templates := [
  { label := "formula", mode := text, content := "矛盾" },
  { label := "plain", lang := zh, mode := text, content := "矛盾" },
  { label := "plain", lang := en, mode := text, content := "false" }
] } }
decl_info Or { concept_info := { default := "plain", templates := [
  { label := "formula", mode := text, content := "#0或#1" },
  { label := "plain", lang := zh, mode := text, content := "#0或#1" },
  { label := "plain", lang := en, mode := text, content := "#0 or #1" }
] } }
decl_info Iff { concept_info := { default := "plain", templates := [
  { label := "formula", mode := text, content := "#0当且仅当#1" },
  { label := "plain", lang := zh, mode := text, content := "#0当且仅当#1" },
  { label := "plain", lang := en, mode := text, content := "#0 if and only if #1" }
] } }

decl_info Nat.succ { concept_info := { templates := [
  { label := "formula", content := "#0+1" }
] } }
operator_info HSub.hSub { symbol := "-", fixity := «infix», precedence := 65, associativity := left }
decl_info HDiv.hDiv { concept_info := { templates := [
  { label := "formula", content := "\\frac{#0}{#1}", isolated_arguments := [0, 1] }
] } }
operator_info Neg.neg { symbol := "-", fixity := «prefix», precedence := 75, associativity := none }
decl_info Inv.inv { concept_info := { templates := [
  { label := "formula", content := "{#0}^{-1}" }
] } }
operator_info Dvd.dvd { symbol := "\\mid", fixity := «infix», precedence := 50, associativity := none }
decl_info Nat { var_name := "n", parameter_template := some "$#self\\in\\mathbb{N}$", concept_info := { default := "mathbb", templates := [
  { label := "formula", content := "\\mathbb{N}" },
  { label := "mathbb", lang := en, content := "\\mathbb{N}" },
  { label := "mathbf", lang := en, content := "\\mathbf{N}" }
] } }
decl_info And.left { concept_info := { templates := [
  { label := "formula", content := "#0" }
] } }
decl_info And.right { concept_info := { templates := [
  { label := "formula", content := "#0" }
] } }
decl_info Or.inl { concept_info := { templates := [
  { label := "formula", content := "#0" }
] } }
decl_info Or.inr { concept_info := { templates := [
  { label := "formula", content := "#0" }
] } }
operator_info Membership.mem { symbol := "\\in", fixity := «infix», precedence := 50, associativity := none }
operator_info Inter.inter { symbol := "\\cap", fixity := «infix», precedence := 70, associativity := left }
decl_info Rat { var_name := "q", parameter_template := some "$#self\\in\\mathbb{Q}$", concept_info := { templates := [
  { label := "formula", content := "\\mathbb{Q}" }
] } }
