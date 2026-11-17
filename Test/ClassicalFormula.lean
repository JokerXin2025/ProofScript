import Test.SharedDeclInfo
import ProofScript
import Mathlib


namespace ClassicalFormula

-- Formula-specific presentation: integer intervals, fractional-part remainder,
-- smoothness hypotheses and complex discs in the examples below.
decl_info SummationFilter.unconditional { names := [{ lang := zh, value := "全体自然数" }], templates := [
  { label := "formula", content := template% ${ arg(0) }$ },
  { label := "domain", lang := zh, content := template% ${ arg(0) }$ },
  { label := "domain", lang := en, content := template% ${ arg(0) }$ }
] }
decl_info Real.measureSpace { names := [{ lang := zh, value := "实数上的勒贝格测度空间" }], templates := [
  { label := "formula", content := template%:100 ${ "\\mathrm{Lebesgue}" }$ },
  { label := "measure", lang := zh, content := template%:100 ${ "\\mathrm{Lebesgue}" }$ },
  { label := "measure", lang := en, content := template%:100 ${ "\\mathrm{Lebesgue}" }$ }
] }
decl_info MeasureTheory.MeasureSpace.volume { names := [{ lang := zh, value := "体积测度" }], templates := [
  { label := "formula", content := template%:100 ${ "\\mathrm{d}x" }$ },
  { label := "measure", lang := zh, content := template%:100 ${ "\\mathrm{d}x" }$ },
  { label := "measure", lang := en, content := template%:100 ${ "\\mathrm{d}x" }$ }
] }
decl_info Finset.Ico { names := [{ lang := zh, value := "整数区间" }], default_template := "formula", templates := [
  { label := "formula", content := template%:90 ${ "\\{" arg(0) ",\\ldots," arg(1) "-1\\}" }$ },
  { label := "interval", lang := zh, content := template%:70 ${ "[" arg(0) "," arg(1) ")\\cap\\mathbb{Z}" }$ },
  { label := "interval", lang := en, content := template%:70 ${ "[" arg(0) "," arg(1) ")\\cap\\mathbb{Z}" }$ }
] }
decl_info Int.fract { names := [{ lang := zh, value := "小数部分" }], default_template := "formula", templates := [
  { label := "formula", content := template%:100 ${ "\\{" arg(0) "\\}" }$ },
  { label := "fractional", lang := zh, content := template%:100 ${ "\\operatorname{frac}(" arg(0) ")" }$ },
  { label := "fractional", lang := en, content := template%:100 ${ "\\operatorname{frac}(" arg(0) ")" }$ }
] }
decl_info ContDiff { names := [{ lang := zh, value := "连续可微" }], default_template := "formula", templates := [
  { label := "formula", content := template%:50 ${ arg(2) "\\in C^{" arg(1) "}(" arg(0) ")" }$ },
  { label := "smoothness", lang := zh, content := template%:50 ${ arg(2) "\\in C^{" arg(1) "}(" arg(0) ")" }$ },
  { label := "smoothness", lang := en, content := template%:50 ${ arg(2) "\\in C^{" arg(1) "}(" arg(0) ")" }$ }
] }
decl_info DifferentiableOn { names := [{ lang := zh, value := "区域上的可微性" }], default_template := "formula", templates := [
  { label := "formula", content := template%:50 ${ arg(1) $ " 在 " $ arg(2) $ " 上对 " $ arg(0) $ " 可微" $ }$ },
  { label := "prose", lang := zh, content := template%:50 { "函数" arg(1) "在" arg(2) "上对" arg(0) "可微" } },
  { label := "prose", lang := en, content := template%:50 { arg(1) " is differentiable over " arg(0) " on " arg(2) } }
] }
decl_info Metric.closedBall { names := [{ lang := zh, value := "闭圆盘" }], default_template := "formula", templates := [
  { label := "formula", content := template%:90 ${ "\\overline{D}(" arg(0) "," arg(1) ")" }$ },
  { label := "set", lang := zh, content := template%:100 ${ "\\{z:|z-" arg(0) "|\\leq " arg(1) "\\}" }$ },
  { label := "set", lang := en, content := template%:100 ${ "\\{z:|z-" arg(0) "|\\leq " arg(1) "\\}" }$ }
] }
decl_info Metric.ball { names := [{ lang := zh, value := "开圆盘" }], default_template := "formula", templates := [
  { label := "formula", content := template%:90 ${ "D(" arg(0) "," arg(1) ")" }$ },
  { label := "set", lang := zh, content := template%:100 ${ "\\{z:|z-" arg(0) "|<" arg(1) "\\}" }$ },
  { label := "set", lang := en, content := template%:100 ${ "\\{z:|z-" arg(0) "|<" arg(1) "\\}" }$ }
] }

#page title "经典数学公式"

/-- Ramanujan's formula for the reciprocal of π (proof omitted). -/
#page theorem ramanujan_pi
  : 1 / Real.pi =
      (2 * Real.sqrt 2 / 9801) * ∑' n : ℕ,
        (Nat.factorial (4 * n) : ℝ) * (1103 + 26390 * n)
        / ((Nat.factorial n : ℝ) ^ 4 * (396 : ℝ) ^ (4 * n))
:= by admit

theorem_info ramanujan_pi {
  names := [{ lang := zh, value := "拉马努金圆周率公式" },
    { lang := en, value := "Ramanujan's formula for π" }],
  tags := [{ lang := zh, value := "圆周率" }, { lang := zh, value := "无穷级数" }]
}

/-- The first-order Euler–Maclaurin formula with its periodic Bernoulli remainder.
    For an integer interval `[a,b)`, the endpoint correction is `(f a - f b)/2`. -/
#page theorem euler_maclaurin (f : ℝ → ℝ) (a b : ℤ) (hab : a ≤ b)
    (hf : ContDiff ℝ 1 f)
  : ∑ k ∈ Finset.Ico a b, f (k : ℝ) =
      (∫ x in (a : ℝ)..(b : ℝ), f x) + (f a - f b) / 2
      + ∫ x in (a : ℝ)..(b : ℝ), (Int.fract x - (1 : ℝ) / 2) * deriv f x
:= by admit

theorem_info euler_maclaurin {
  names := [{ lang := zh, value := "欧拉—麦克劳林求和公式（一阶余项）" }],
  tags := [{ lang := zh, value := "求和" }, { lang := zh, value := "积分" },
    { lang := zh, value := "伯努利函数" }]
}

decl_info circleIntegral {
  names := [{ lang := zh, value := "圆周积分" }], default_template := "display", templates := [{
    label := "formula",
    content := template% ${ "\\oint_{|" binder(0, 1) "-" arg(1) "|=" arg(2) "}" body(0, 1) "\\,\\mathrm{d}" binder(0, 1) }$
  }, {
    label := "display", lang := zh,
    content := template% ${ "\\displaystyle\\oint_{|" binder(0, 1) "-" arg(1) "|=" arg(2) "}" body(0, 1) "\\,\\mathrm{d}" binder(0, 1) }$
  }, {
    label := "display", lang := en,
    content := template% ${ "\\displaystyle\\oint_{|" binder(0, 1) "-" arg(1) "|=" arg(2) "}" body(0, 1) "\\,\\mathrm{d}" binder(0, 1) }$
  }, {
    label := "function", lang := zh,
    content := template% ${ "\\operatorname{circleIntegral}(" arg(0) "," arg(1) "," arg(2) ")" }$
  }, {
    label := "function", lang := en,
    content := template% ${ "\\operatorname{circleIntegral}(" arg(0) "," arg(1) "," arg(2) ")" }$
  }]
}
/-- Cauchy's integral formula on a closed disc (proof omitted). -/
#page theorem cauchy_integral (f : ℂ → ℂ) (c w : ℂ) (R : ℝ)
    (hf : DifferentiableOn ℂ f (Metric.closedBall c R)) (hw : w ∈ Metric.ball c R)
  : f w = (1 / (2 * (Real.pi : ℂ) * Complex.I)) * ∮ z in C(c, R), f z / (z - w)
:= by admit

theorem_info cauchy_integral {
  names := [{ lang := zh, value := "柯西积分公式" }],
  tags := [{ lang := zh, value := "复分析" }, { lang := zh, value := "圆周积分" }]
}

end ClassicalFormula
