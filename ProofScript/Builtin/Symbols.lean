import ProofScript.Info.Decl.Commands
import Mathlib

import ProofScript.Extensions.Title
import ProofScript.Extensions.ProofText

-- TODO: determine the precedence of text-templates

#page title "Symbol Configurations"


#page sub title (label := "BuiltinRelations")
"Relations"

decl_info relation Eq r"="                (mode := formula)
decl_info relation Ne r"\ne"              (mode := formula)
decl_info relation LE.le r"\leqslant"     (mode := formula)
decl_info relation LT.lt r"<"             (mode := formula)
decl_info relation GE.ge r"\geqslant"     (mode := formula)
decl_info relation GT.gt r">"             (mode := formula)
decl_info relation Membership.mem r"\in"  (mode := formula)
decl_info relation Dvd.dvd r"\mid"        (mode := formula)


#page sub title (label := "BuiltinUnaryOperators")
"Unary Operators"

decl_info prefix Neg.neg r"-"         (mode := formula, precedence := 75)
decl_info postfix Nat.factorial r"!"  (mode := formula, precedence := 100)


#page sub title (label := "BuiltinBinaryOperators")
"Binary Operators"

decl_info infixl HAdd.hAdd r"+"       (mode := formula, precedence := 65)
decl_info infixl HSub.hSub r"-"       (mode := formula, precedence := 65)
decl_info infixl HMul.hMul r""        (mode := formula, precedence := 70)
decl_info infixr HSMul.hSMul r"\cdot" (mode := formula, precedence := 70)
-- `HDiv.hDiv` is preferably rendered by template "\\frac"
-- `Inv.inv` is preferably rendered by template "-1"
-- `HPow.hPow` is preferably rendered by template "^"

decl_info templates HMul.hMul + [{
  label := "\\cdot", content :=
  template%:70 ${ arg(0) r"\cdot" arg(1) }$
}, {
  label := "times", lang := zh, content :=
  template%:70 { arg(0) "乘" arg(1) }
}, {
  label := "product", lang := zh, content :=
  template% { arg(0) "与" arg(1) "的乘积" }
}]

decl_info templates HDiv.hDiv + [{
  label := "\\frac", content :=
  template%:100 ${ r"\frac{" arg!(0) r"}{" arg!(1) r"}" }$
}, {
  label := "\\dfrac", content :=
  template%:100 ${ r"\dfrac{" arg!(0) r"}{" arg!(1) r"}" }$
}, {
  label := "/", content :=
  template%:70 ${ arg(0) r"\mathbin /" arg(1) }$
}, {
  label := "divided-by", lang := zh, content :=
  template%:70 { arg(0) "除以" arg(1) }
}, {
  label := "divide", lang := zh, content :=
  template%:70 { arg(1) "除" arg(0) }
}, {
  label := "quotient", lang := zh, content :=
  template% { arg(0) "与" arg(1) "的商" }
}]

decl_info templates Inv.inv + [{
  label := "-1", content :=
  template%:80 ${ arg(0) r"^{-1}" }$
}, {
  label := "reciprocal", lang := zh, content :=
  template% { arg(0) "的倒数" }
}]

decl_info templates HPow.hPow + [{
  label := "^", content :=
  template%:80 ${ arg(0) r"^{" arg!(1) r"}" }$
}, {
  label := "power", lang := zh, content :=
  template% { arg(0) "的" arg(1) "次方" }
}]
