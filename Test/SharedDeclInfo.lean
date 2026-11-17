import ProofScript
import Mathlib

open ProofScript Filter Topology Finset intervalIntegral

/-!
Common Lean/Mathlib display configuration shared by Test pages.

Expansion roadmap (keep page-specific notation and examples in their own modules):
* Logic and sets: add `False`, `Not`, `Or`, `Set`, `Set.Icc`,
  `Set.union` and `Set.inter`, with precedence and bilingual alternatives.
* Algebra and number systems: add `Rat`, `Zero`, `One`,
  `Nat.succ`, and standard coercions only where the rendered meaning is
  independent of the instance and ambient type.
* Analysis and finite structures: add `Finset`, `Finset.prod`, `Set.indicator`,
  `Filter.Eventually`, `ContinuousOn` and `DifferentiableAt` with templates
  that preserve binder scope and do not assume a particular domain.
For each new entry, first exercise it in a checked Test theorem statement;
only promote it here when the same display is valid across test modules.
-/
decl_info relation LE.le "≤" (mode := formula)
decl_info relation LT.lt "<" (mode := formula)
decl_info prefix Neg.neg "-" (mode := formula, precedence := 75)
decl_info Eq { names := [{ lang := zh, value := "等于" }] }
decl_info relation Eq "=" (mode := formula)
decl_info templates Eq + [
  { label := "formula", content := template%:50 ${ arg(0) "=" arg(1) }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{equal}(" arg(0) "," arg(1) ")" }$ },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{等于}(" arg(0) "," arg(1) ")" }$ }
]
decl_info HAdd.hAdd { names := [{ lang := zh, value := "加法" }] }
decl_info infixl HAdd.hAdd "+" (mode := formula, precedence := 65)
decl_info HMul.hMul { names := [{ lang := zh, value := "乘法" }] }
decl_info infixl HMul.hMul "\\cdot" (mode := formula, precedence := 70)
decl_info HSub.hSub { names := [{ lang := zh, value := "减法" }] }
decl_info infixl HSub.hSub "-" (mode := formula, precedence := 65)
decl_info HDiv.hDiv {
  names := [{ lang := zh, value := "除法" }], default_template := "formula",
  templates := [
    { label := "formula", content := template%:70 ${ "\\frac{" arg!(0) "}{" arg!(1) "}" }$ },
    { label := "fraction", lang := zh, content := template%:70 ${ "\\dfrac{" arg!(0) "}{" arg!(1) "}" }$ },
    { label := "fraction", lang := en, content := template%:70 ${ "\\dfrac{" arg!(0) "}{" arg!(1) "}" }$ },
    { label := "quotient", lang := zh, content := template%:70 ${ arg(0) "\\mathbin{/}" arg(1) }$ },
    { label := "quotient", lang := en, content := template%:70 ${ arg(0) "\\mathbin{/}" arg(1) }$ }
  ]
}
decl_info HPow.hPow {
  names := [{ lang := zh, value := "乘方" }], default_template := "formula", templates := [
    { label := "formula", content := template%:80 ${ "{" arg(0) "}^{" arg!(1) "}" }$ },
    { label := "power", lang := zh, content := template%:80 ${ "\\left(" arg!(0) "\\right)^{" arg!(1) "}" }$ },
    { label := "power", lang := en, content := template%:80 ${ "\\left(" arg!(0) "\\right)^{" arg!(1) "}" }$ }
  ]
}
decl_info OfNat.ofNat { names := [{ lang := zh, value := "数值解析器" }] }
decl_info wrapper OfNat.ofNat 1
decl_info Nat.cast { names := [{ lang := zh, value := "自然数嵌入" }] }
decl_info wrapper Nat.cast 2
decl_info Int.cast { names := [{ lang := zh, value := "整数嵌入" }] }
decl_info wrapper Int.cast 2
decl_info Nat { names := [{ value := "ℕ" }], var_name := "n", templates := [
  { label := "formula", content := template%:100 ${ "\\mathbb{N}" }$ },
  { label := "number-set", lang := zh, content := template%:100 ${ "\\mathbb{N}" }$ },
  { label := "number-set", lang := en, content := template%:100 ${ "\\mathbb{N}" }$ }
] }
decl_info Int { names := [{ value := "ℤ" }], templates := [
  { label := "formula", content := template%:100 ${ "\\mathbb{Z}" }$ },
  { label := "number-set", lang := zh, content := template%:100 ${ "\\mathbb{Z}" }$ },
  { label := "number-set", lang := en, content := template%:100 ${ "\\mathbb{Z}" }$ }
] }
decl_info Real { names := [{ value := "ℝ" }], var_name := "x", templates := [
  { label := "formula", content := template%:100 ${ "\\mathbb{R}" }$ },
  { label := "number-set", lang := zh, content := template%:100 ${ "\\mathbb{R}" }$ },
  { label := "number-set", lang := en, content := template%:100 ${ "\\mathbb{R}" }$ }
] }
decl_info Real.pi { names := [{ value := "π" }], templates := [
  { label := "formula", content := template%:100 ${ "\\pi" }$ },
  { label := "name", lang := zh, content := template%:100 ${ "\\pi" }$ },
  { label := "name", lang := en, content := template%:100 ${ "\\pi" }$ }
] }
decl_info Real.sqrt { names := [{ lang := zh, value := "平方根" }], templates := [
  { label := "formula", content := template%:100 ${ "\\sqrt{" arg!(0) "}" }$ },
  { label := "root", lang := zh, content := template%:100 ${ "\\sqrt{" arg(0) "}" }$ },
  { label := "root", lang := en, content := template%:100 ${ "\\sqrt{" arg(0) "}" }$ }
] }
decl_info Nat.factorial { names := [{ lang := zh, value := "阶乘" }], templates := [
  { label := "formula", content := template%:80 ${ arg(0) "!" }$ },
  { label := "factorial", lang := zh, content := template%:80 ${ arg(0) "!" }$ },
  { label := "factorial", lang := en, content := template%:80 ${ arg(0) "!" }$ }
] }
decl_info tsum { names := [{ lang := zh, value := "无穷级数之和" }], default_template := "display", templates := [
  { label := "formula", content := template% ${ "\\sum_{" binder(0, 1) "=0}^{\\infty}" body(0, 1) }$ },
  { label := "display", lang := zh, content := template% ${ "\\displaystyle\\sum_{" binder(0, 1) "=0}^{\\infty}" body(0, 1) }$ },
  { label := "display", lang := en, content := template% ${ "\\displaystyle\\sum_{" binder(0, 1) "=0}^{\\infty}" body(0, 1) }$ },
  { label := "function", lang := zh, content := template% ${ "\\operatorname{tsum}(" arg(0) ")" }$ },
  { label := "function", lang := en, content := template% ${ "\\operatorname{tsum}(" arg(0) ")" }$ }
] }
decl_info Finset.sum { names := [{ lang := zh, value := "有限求和" }], default_template := "display", templates := [
  { label := "formula", content := template% ${ "\\sum_{" binder(1, 1) "\\in " arg(0) "}" body(1, 1) }$ },
  { label := "display", lang := zh, content := template% ${ "\\displaystyle\\sum_{" binder(1, 1) "\\in " arg(0) "}" body(1, 1) }$ },
  { label := "display", lang := en, content := template% ${ "\\displaystyle\\sum_{" binder(1, 1) "\\in " arg(0) "}" body(1, 1) }$ },
  { label := "function", lang := zh, content := template% ${ "\\operatorname{sum}(" arg(0) "," arg(1) ")" }$ },
  { label := "function", lang := en, content := template% ${ "\\operatorname{sum}(" arg(0) "," arg(1) ")" }$ }
] }
decl_info intervalIntegral { names := [{ lang := zh, value := "区间积分" }], default_template := "display", templates := [
  { label := "formula", content := template% ${ "\\int_{" arg(1) "}^{" arg(2) "}" body(0, 1) "\\,\\mathrm{d}" binder(0, 1) }$ },
  { label := "display", lang := zh, content := template% ${ "\\displaystyle\\int_{" arg(1) "}^{" arg(2) "}" body(0, 1) "\\,\\mathrm{d}" binder(0, 1) }$ },
  { label := "display", lang := en, content := template% ${ "\\displaystyle\\int_{" arg(1) "}^{" arg(2) "}" body(0, 1) "\\,\\mathrm{d}" binder(0, 1) }$ },
  { label := "function", lang := zh, content := template% ${ "\\operatorname{integral}(" arg(0) "," arg(1) "," arg(2) ")" }$ },
  { label := "function", lang := en, content := template% ${ "\\operatorname{integral}(" arg(0) "," arg(1) "," arg(2) ")" }$ }
] }
decl_info deriv { names := [{ lang := zh, value := "导数" }], default_template := "formula", templates := [
  { label := "formula", content := template%:90 ${ arg(0) "'(" arg(1) ")" }$ },
  { label := "derivative", lang := zh, content := template%:90 ${ "\\frac{\\mathrm{d}}{\\mathrm{d}x}" arg(0) "\\big|_{x=" arg(1) "}" }$ },
  { label := "derivative", lang := en, content := template%:90 ${ "\\frac{\\mathrm{d}}{\\mathrm{d}x}" arg(0) "\\big|_{x=" arg(1) "}" }$ }
] }
decl_info Membership.mem { names := [{ lang := zh, value := "属于" }], default_template := "formula", templates := [
  { label := "formula", content := template%:50 ${ arg(1) "\\in " arg(0) }$ },
  { label := "membership", lang := zh, content := template%:50 ${ arg(1) "\\in " arg(0) }$ },
  { label := "membership", lang := en, content := template%:50 ${ arg(1) "\\in " arg(0) }$ }
] }
decl_info Complex { names := [{ value := "ℂ" }], default_template := "formula", templates := [
  { label := "formula", content := template%:100 ${ "\\mathbb{C}" }$ },
  { label := "number-set", lang := zh, content := template%:100 ${ "\\mathbb{C}" }$ },
  { label := "number-set", lang := en, content := template%:100 ${ "\\mathbb{C}" }$ }
] }
decl_info Complex.I { names := [{ value := "i" }], default_template := "formula", templates := [
  { label := "formula", content := template%:100 ${ "\\mathrm{i}" }$ },
  { label := "imaginary", lang := zh, content := template%:100 ${ "\\mathrm{i}" }$ },
  { label := "imaginary", lang := en, content := template%:100 ${ "\\mathrm{i}" }$ }
] }
decl_info Complex.ofReal { names := [{ lang := zh, value := "实数嵌入复数" }] }
decl_info wrapper Complex.ofReal 0
decl_info And { templates := [
  { label := "formula", content := template%:35 ${ arg(0) "\\land " arg(1) }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{both}(" arg(0) "," arg(1) ")" }$ },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{同时}(" arg(0) "," arg(1) ")" }$ }
] }
decl_info True { templates := [
  { label := "formula", content := template%:100 ${ "\\top" }$ }
] }
decl_info Iff { templates := [
  { label := "formula", content := template%:25 ${ arg(0) "\\leftrightarrow " arg(1) }$ }
] }
decl_info Exists { templates := [
  { label := "formula", content := template%:20 raw ${ "\\exists " binder(1, 1) "\\in " arg(0) ",\\ " body(1, 1) }$ }
] }
decl_info nhds { templates := [
  { label := "formula", content := template%:90 ${ "\\mathcal{N}(" arg(0) ")" }$ },
  { label := "neighborhood", lang := zh, content := template%:90 ${ "\\operatorname{nhds}(" arg(0) ")" }$ },
  { label := "neighborhood", lang := en, content := template%:90 ${ "\\operatorname{nhds}(" arg(0) ")" }$ }
] }
decl_info Filter.atTop { templates := [
  { label := "formula", content := template%:100 ${ "\\operatorname{atTop}" }$ },
  { label := "symbol", lang := zh, content := template%:100 ${ "\\infty" }$ },
  { label := "symbol", lang := en, content := template%:100 ${ "\\infty" }$ }
] }
decl_info Finset.range { templates := [
  { label := "formula", content := template%:100 ${ "\\{0,\\ldots," arg(0) "-1\\}" }$ },
  { label := "range", lang := zh, content := template%:100 ${ "\\operatorname{range}(" arg(0) ")" }$ },
  { label := "range", lang := en, content := template%:100 ${ "\\operatorname{range}(" arg(0) ")" }$ }
] }
decl_info abs { templates := [
  { label := "formula", content := template%:100 ${ "\\left|" arg!(0) "\\right|" }$ },
  { label := "function", lang := zh, content := template%:90 ${ "\\operatorname{abs}(" arg(0) ")" }$ },
  { label := "function", lang := en, content := template%:90 ${ "\\operatorname{abs}(" arg(0) ")" }$ }
] }
decl_info Filter.Tendsto { templates := [
  { label := "formula", content := template%:50 ${ arg(0) "\\xrightarrow[" arg(1) "]{}" arg(2) }$ },
  { label := "prose", lang := zh, content := template%:50 { arg(0) "沿着" arg(1) "收敛到" arg(2) } },
  { label := "prose", lang := en, content := template%:50 { arg(0) " converges to " arg(2) " along " arg(1) } }
] }
decl_info HasDerivAt { templates := [
  { label := "formula", content := template%:50 ${ arg(0) "'(" arg(2) ")=" arg(1) }$ },
  { label := "prose", lang := zh, content := template%:50 { "函数" arg(0) "在" arg(2) "处的导数等于" arg(1) } },
  { label := "prose", lang := en, content := template%:50 { "the derivative of " arg(0) " at " arg(2) " equals " arg(1) } }
] }
decl_info ContinuousAt { templates := [
  { label := "formula", content := template%:50 ${ arg(0) $ " 在 " $ arg(1) $ " 处连续" $ }$ },
  { label := "prose", lang := zh, content := template%:50 { "函数" arg(0) "在" arg(1) "处连续" } },
  { label := "prose", lang := en, content := template%:50 { arg(0) " is continuous at " arg(1) } }
] }
decl_info Continuous { templates := [
  { label := "formula", content := template%:50 ${ "\\operatorname{Continuous}(" arg(0) ")" }$ },
  { label := "prose", lang := zh, content := template%:50 { "函数" arg(0) "连续" } },
  { label := "prose", lang := en, content := template%:50 { arg(0) " is continuous" } }
] }
