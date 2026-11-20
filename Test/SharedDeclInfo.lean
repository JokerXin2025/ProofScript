import ProofScript
import Mathlib

open Lean Elab Command ProofScript Filter Topology Finset intervalIntegral

/-!
Common Lean/Mathlib display configuration shared by Test pages.

Shared coverage includes logic, sets, number systems, finite structures,
filters and calculus. Templates preserve binder scope, visible domains and
instance-independent meanings. The checked statements below exercise each
new entry; page-specific notation and examples belong in their own modules.
-/
decl_info Eq { names := [{ lang := zh, value := "等于" }] }
decl_info templates Eq + [
  { label := "formula", content := template%:50 ${ arg(0) "=" arg(1) }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{equal}(" arg(0) "," arg(1) ")" }$ },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{等于}(" arg(0) "," arg(1) ")" }$ }
]
decl_info HAdd.hAdd { names := [{ lang := zh, value := "加法" }] }
decl_info HMul.hMul { names := [{ lang := zh, value := "乘法" }] }
decl_info HSub.hSub { names := [{ lang := zh, value := "减法" }] }
decl_info HPow.hPow { names := [{ lang := zh, value := "乘方" }] }

decl_info Nat { names := [{ value := "ℕ" }], templates := [
  { label := "formula", content := template%:100 ${ "\\mathbb{N}" }$ },
  { label := "number-set", lang := zh, content := template%:100 ${ "\\mathbb{N}" }$ },
  { label := "number-set", lang := en, content := template%:100 ${ "\\mathbb{N}" }$ }
] }
decl_info Int { names := [{ value := "ℤ" }], templates := [
  { label := "formula", content := template%:100 ${ "\\mathbb{Z}" }$ },
  { label := "number-set", lang := zh, content := template%:100 ${ "\\mathbb{Z}" }$ },
  { label := "number-set", lang := en, content := template%:100 ${ "\\mathbb{Z}" }$ }
] }
decl_info Real { names := [{ value := "ℝ" }], templates := [
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
decl_info Nat.factorial { names := [{ lang := zh, value := "阶乘" }] }
decl_info tsum { names := [{ lang := zh, value := "无穷级数" }], default_template := "display", templates := [
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

-- Logic: retain both symbolic notation and phrases for reading propositions aloud.
decl_info False { names := [{ lang := zh, value := "假" }], templates := [
  { label := "formula", content := template%:100 ${ "\\bot" }$ },
  { label := "prose", lang := zh, content := template% { "假命题" } },
  { label := "prose", lang := en, content := template% { "false" } }
] }
decl_info Not { names := [{ lang := zh, value := "否定" }], templates := [
  { label := "formula", content := template%:40 ${ "\\neg " arg(0) }$ },
  { label := "prose", lang := zh, content := template% { "并非" arg(0) } },
  { label := "prose", lang := en, content := template% { "not " arg(0) } },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{非}(" arg(0) ")" }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{not}(" arg(0) ")" }$ }
] }
decl_info Or { names := [{ lang := zh, value := "析取" }], templates := [
  { label := "formula", content := template%:30 ${ arg(0) "\\lor " arg(1) }$ },
  { label := "prose", lang := zh, content := template% { arg(0) "或" arg(1) } },
  { label := "prose", lang := en, content := template% { arg(0) " or " arg(1) } },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{至少一个成立}(" arg(0) "," arg(1) ")" }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{either}(" arg(0) "," arg(1) ")" }$ }
] }

-- Sets and intervals are polymorphic: avoid assuming an order on Set's elements.
decl_info Set { names := [{ lang := zh, value := "集合" }], templates := [
  { label := "formula", content := template%:90 ${ "\\operatorname{Set}(" arg(0) ")" }$ },
  { label := "type", lang := zh, content := template%:50 { arg(0) "的集合" } },
  { label := "type", lang := en, content := template%:50 { "sets of " arg(0) } },
  { label := "predicate", lang := zh, content := template%:90 ${ arg(0) "\\to\\mathrm{Prop}" }$ },
  { label := "predicate", lang := en, content := template%:90 ${ arg(0) "\\to\\mathrm{Prop}" }$ }
] }
decl_info Set.Icc { names := [{ lang := zh, value := "闭区间" }], templates := [
  { label := "formula", content := template%:90 ${ "[" arg(0) "," arg(1) "]" }$ },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{Icc}(" arg(0) "," arg(1) ")" }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{Icc}(" arg(0) "," arg(1) ")" }$ },
  { label := "prose", lang := zh, content := template% { "从" arg(0) "到" arg(1) "的闭区间" } },
  { label := "prose", lang := en, content := template% { "the closed interval from " arg(0) " to " arg(1) } }
] }
decl_info Set.union { names := [{ lang := zh, value := "并集" }], templates := [
  { label := "formula", content := template%:60 ${ arg(0) "\\cup " arg(1) }$ },
  { label := "prose", lang := zh, content := template% { arg(0) "与" arg(1) "的并集" } },
  { label := "prose", lang := en, content := template% { "the union of " arg(0) " and " arg(1) } },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{并}(" arg(0) "," arg(1) ")" }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{union}(" arg(0) "," arg(1) ")" }$ }
] }
decl_info Set.inter { names := [{ lang := zh, value := "交集" }], templates := [
  { label := "formula", content := template%:65 ${ arg(0) "\\cap " arg(1) }$ },
  { label := "prose", lang := zh, content := template% { arg(0) "与" arg(1) "的交集" } },
  { label := "prose", lang := en, content := template% { "the intersection of " arg(0) " and " arg(1) } },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{交}(" arg(0) "," arg(1) ")" }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{inter}(" arg(0) "," arg(1) ")" }$ }
] }

-- Number systems and instance-independent zero/one notation.
decl_info Rat { names := [{ value := "ℚ" }], templates := [
  { label := "formula", content := template%:100 ${ "\\mathbb{Q}" }$ },
  { label := "number-set", lang := zh, content := template%:100 ${ "\\mathbb{Q}" }$ },
  { label := "number-set", lang := en, content := template%:100 ${ "\\mathbb{Q}" }$ }
] }
decl_info Zero.zero { names := [{ lang := zh, value := "零元" }], templates := [
  { label := "formula", content := template%:100 ${ "0" }$ },
  { label := "prose", lang := zh, content := template% { "零元" } },
  { label := "prose", lang := en, content := template% { "zero" } }
] }
decl_info One.one { names := [{ lang := zh, value := "单位元" }], templates := [
  { label := "formula", content := template%:100 ${ "1" }$ },
  { label := "prose", lang := zh, content := template% { "一" } },
  { label := "prose", lang := en, content := template% { "one" } }
] }
decl_info Nat.succ { names := [{ lang := zh, value := "后继" }], templates := [
  { label := "formula", content := template%:65 ${ arg(0) "+1" }$ },
  { label := "prose", lang := zh, content := template% { arg(0) "的后继" } },
  { label := "prose", lang := en, content := template% { "the successor of " arg(0) } },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{succ}(" arg(0) ")" }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{succ}(" arg(0) ")" }$ }
] }

-- Finite collections, products, and indicator functions keep the domain explicit.
decl_info Finset { names := [{ lang := zh, value := "有限集合" }], templates := [
  { label := "formula", content := template%:90 ${ "\\operatorname{Finset}(" arg(0) ")" }$ },
  { label := "type", lang := zh, content := template% { arg(0) "的有限集合" } },
  { label := "type", lang := en, content := template% { "finite subsets of " arg(0) } }
] }
decl_info Finset.prod { names := [{ lang := zh, value := "有限乘积" }], default_template := "display", templates := [
  { label := "formula", content := template% ${ "\\prod_{" binder(1, 1) "\\in " arg(0) "}" body(1, 1) }$ },
  { label := "display", lang := zh, content := template% ${ "\\displaystyle\\prod_{" binder(1, 1) "\\in " arg(0) "}" body(1, 1) }$ },
  { label := "display", lang := en, content := template% ${ "\\displaystyle\\prod_{" binder(1, 1) "\\in " arg(0) "}" body(1, 1) }$ },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{乘积}(" arg(0) "," arg(1) ")" }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{prod}(" arg(0) "," arg(1) ")" }$ }
] }
decl_info Set.indicator { names := [{ lang := zh, value := "集合示性函数" }], templates := [
  { label := "formula", content := template%:90 ${ "\\mathbf{1}_{" arg(0) "}\\cdot " arg(1) }$ },
  { label := "prose", lang := zh, content := template% { arg(1) "在" arg(0) "上的示性函数" } },
  { label := "prose", lang := en, content := template% { "the indicator of " arg(0) " applied to " arg(1) } },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{indicator}(" arg(0) "," arg(1) ")" }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{indicator}(" arg(0) "," arg(1) ")" }$ }
] }

-- Topology and calculus: the filter, domain and point must remain visible.
decl_info Filter.Eventually { names := [{ lang := zh, value := "最终成立" }], templates := [
  { label := "formula", content := template%:50 ${ "\\forall^{\\mathrm{eventually}} " binder(0, 1) "\\in " arg(1) ",\\ " body(0, 1) }$ },
  { label := "prose", lang := zh, content := template% { "沿" arg(1) "最终有" arg(0) } },
  { label := "prose", lang := en, content := template% { arg(0) " holds eventually along " arg(1) } },
  { label := "call", lang := zh, content := template%:90 ${ "\\operatorname{Eventually}(" arg(0) "," arg(1) ")" }$ },
  { label := "call", lang := en, content := template%:90 ${ "\\operatorname{Eventually}(" arg(0) "," arg(1) ")" }$ }
] }
decl_info ContinuousOn { names := [{ lang := zh, value := "在集合上连续" }], templates := [
  { label := "formula", content := template%:50 ${ "\\operatorname{ContinuousOn}(" arg(0) "," arg(1) ")" }$ },
  { label := "prose", lang := zh, content := template% { "函数" arg(0) "在" arg(1) "上连续" } },
  { label := "prose", lang := en, content := template% { arg(0) " is continuous on " arg(1) } },
  { label := "restriction", lang := zh, content := template%:50 ${ arg(0) "\\big|_{" arg(1) "}\\text{ 连续}" }$ },
  { label := "restriction", lang := en, content := template%:50 ${ arg(0) "\\big|_{" arg(1) "}\\text{ is continuous}" }$ }
] }
decl_info DifferentiableAt { names := [{ lang := zh, value := "在一点可微" }], templates := [
  { label := "formula", content := template%:50 ${ "\\operatorname{DifferentiableAt}_{" arg(0) "}(" arg(1) "," arg(2) ")" }$ },
  { label := "prose", lang := zh, content := template% { "函数" arg(1) "在" arg(2) "处对" arg(0) "可微" } },
  { label := "prose", lang := en, content := template% { arg(1) " is differentiable over " arg(0) " at " arg(2) } },
  { label := "derivative", lang := zh, content := template%:50 ${ arg(1) "\\text{ 在 }" arg(2) "\\text{ 处可微（标量域 }" arg(0) "\\text{）}" }$ },
  { label := "derivative", lang := en, content := template%:50 ${ arg(1) "\\text{ differentiable at }" arg(2) "\\text{ over }" arg(0) }$ }
] }

-- Checked statement fixtures for the shared configurations above.
example (p q : Prop) (s t : Set ℕ) (a b : ℕ)
    (_ : False ∨ ¬p ∨ q) (_ : a ∈ Set.Icc a b)
    (_ : a ∈ s ∪ t) (_ : a ∈ s ∩ t) : True := trivial
example (n : ℕ) (q : ℚ) (s : Finset ℕ) (f : ℕ → ℕ)
    (_ : Nat.succ n = n + 1) (_ : q = (0 : ℚ) + (1 : ℚ))
    (_ : Finset.prod s f = Finset.prod s f)
    (_ : Set.indicator (Set.Icc 0 n) f n = Set.indicator (Set.Icc 0 n) f n) : True := trivial
example (s : Set ℝ) (f : ℝ → ℝ) (x : ℝ)
    (_ : Filter.Eventually (fun n : ℕ => n ≤ n) Filter.atTop)
    (_ : ContinuousOn f s) (_ : DifferentiableAt ℝ f x) : True := trivial

-- Check the resolved native arity of every new template, including those
-- whose implicit parameters are omitted by the template DSL.
run_cmd do
  let env ← getEnv
  for target in [`False, `Not, `Or, `Set, `Set.Icc, `Set.union, `Set.inter,
      `Rat, `Zero.zero, `One.one, `Nat.succ, `Finset, `Finset.prod,
      `Set.indicator, `Filter.Eventually, `ContinuousOn, `DifferentiableAt] do
    match freezeDeclInfo env env.mainModule target with
    | .ok _ => pure ()
    | .error error => throwError "{error}"
