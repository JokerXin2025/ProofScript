import ProofScript
import Mathlib


namespace ClassicalFormula

#page title "经典数学公式"

relation_info Eq {
  name := "等于", symbol := "="
}
operator_info HAdd.hAdd {
  name := "加法", symbol := "+",
  fixity := «infix», precedence := 65, associativity := left
}
operator_info HMul.hMul {
  name := "乘法", symbol := "\\,",
  fixity := «infix», precedence := 70, associativity := left
}
operator_info HSub.hSub {
  name := "减法", symbol := "-",
  fixity := «infix», precedence := 65, associativity := left
}
concept_info HDiv.hDiv {
  name := "除法", default := "formula",
  templates := [{
    label := "formula", isolated_arguments := [0, 1],
    content := "\\frac{#0}{#1}"
  }, {
    label := "fraction", lang := zh, isolated_arguments := [0, 1],
    content := "\\dfrac{#0}{#1}"
  }, {
    label := "fraction", lang := en, isolated_arguments := [0, 1],
    content := "\\dfrac{#0}{#1}"
  }, {
    label := "quotient", lang := zh,
    content := "#0\\mathbin{/}#1"
  }, {
    label := "quotient", lang := en,
    content := "#0\\mathbin{/}#1"
  }]
}
concept_info HPow.hPow {
  name := "乘方", default := "formula", templates := [{
    label := "formula", isolated_arguments := [1],
    content := "{#0}^{#1}"
  }, {
    label := "power", lang := zh, isolated_arguments := [0, 1],
    content := "\\left(#0\\right)^{#1}"
  }, {
    label := "power", lang := en, isolated_arguments := [0, 1],
    content := "\\left(#0\\right)^{#1}"
  }]
}
wrapper_info OfNat.ofNat {
  name := "数值解析器", index := some 1
}
wrapper_info Nat.cast {
  name := "自然数嵌入", index := some 2
}
concept_info Nat {
  name := "ℕ", templates := [{
    label := "formula", content := "\\mathbb{N}"
  }, {
    label := "number-set", lang := zh, content := "\\mathbb{N}"
  }, {
    label := "number-set", lang := en, content := "\\mathbb{N}"
  }]
}
concept_info Int {
  name := "ℤ", templates := [{
    label := "formula", content := "\\mathbb{Z}"
  }, {
    label := "number-set", lang := zh, content := "\\mathbb{Z}"
  }, {
    label := "number-set", lang := en, content := "\\mathbb{Z}"
  }]
}
concept_info Real {
  name := "ℝ", templates := [{
    label := "formula", content := "\\mathbb{R}"
  }, {
    label := "number-set", lang := zh, content := "\\mathbb{R}"
  }, {
    label := "number-set", lang := en, content := "\\mathbb{R}"
  }]
}
concept_info SummationFilter.unconditional {
  name := "全体自然数", templates := [{
    label := "formula", content := "#0"
  }, {
    label := "domain", lang := zh, content := "#0"
  }, {
    label := "domain", lang := en, content := "#0"
  }]
}
concept_info Real.pi {
  name := "π", templates := [{
    label := "formula", content := "\\pi"
  }, {
    label := "name", lang := zh, content := "\\pi"
  }, {
    label := "name", lang := en, content := "\\pi"
  }]
}
concept_info Real.sqrt {
  name := "平方根", templates := [{
    label := "formula", isolated_arguments := [0],
    content := "\\sqrt{#0}"
  }, {
    label := "root", lang := zh,
    content := "\\sqrt{#0}"
  },
  { label := "root", lang := en, content := "\\sqrt{#0}" }
]}
concept_info Nat.factorial {
  name := "阶乘", templates := [{
    label := "formula", content := "#0!"
  }, {
    label := "factorial", lang := zh, content := "#0!"
  }, {
    label := "factorial", lang := en, content := "#0!"
  }]
}
concept_info tsum {
  name := "无穷级数之和", default := "display",
  templates := [{
    label := "formula", binders := [(0, 1)],
    content := "\\sum_{@0=0}^{\\infty}@@0"
  }, {
    label := "display", lang := zh, binders := [(0, 1)],
    content := "\\displaystyle\\sum_{@0=0}^{\\infty}@@0"
  }, {
    label := "display", lang := en, binders := [(0, 1)],
    content := "\\displaystyle\\sum_{@0=0}^{\\infty}@@0"
  }, {
    label := "function", lang := zh,
    content := "\\operatorname{tsum}(#0)"
  }, {
    label := "function", lang := en,
    content := "\\operatorname{tsum}(#0)"
  }]
}

/-- Ramanujan's formula for the reciprocal of π (proof omitted). -/
#page theorem ramanujan_pi
  : 1 / Real.pi =
      (2 * Real.sqrt 2 / 9801) * ∑' n : ℕ,
        (Nat.factorial (4 * n) : ℝ) * (1103 + 26390 * n)
        / ((Nat.factorial n : ℝ) ^ 4 * (396 : ℝ) ^ (4 * n))
:= by admit

theorem_info ramanujan_pi {
  name := "拉马努金圆周率公式",
  tags := ["圆周率", "无穷级数"]
}

concept_info Finset.Ico {
  name := "整数区间", default := "formula", templates := [{
    label := "formula", content := "\\{#0,\\ldots,#1-1\\}"
  }, {
    label := "interval", lang := zh, content := "[#0,#1)\\cap\\mathbb{Z}"
  }, {
    label := "interval", lang := en, content := "[#0,#1)\\cap\\mathbb{Z}"
  }]
}
concept_info Finset.sum {
  name := "有限求和", default := "display", templates := [{
    label := "formula", binders := [(1, 1)],
    content := "\\sum_{@1\\in #0}@@1"
  }, {
    label := "display", lang := zh, binders := [(1, 1)],
    content := "\\displaystyle\\sum_{@1\\in #0}@@1"
  }, {
    label := "display", lang := en, binders := [(1, 1)],
    content := "\\displaystyle\\sum_{@1\\in #0}@@1"
  }, {
    label := "function", lang := zh, content := "\\operatorname{sum}(#0,#1)"
  }, {
    label := "function", lang := en, content := "\\operatorname{sum}(#0,#1)"
  }]
}
concept_info intervalIntegral {
  name := "区间积分", default := "display", templates := [{
    label := "formula", binders := [(0, 1)],
    content := "\\int_{#1}^{#2}@@0\\,\\mathrm{d}@0"
  }, {
    label := "display", lang := zh, binders := [(0, 1)],
    content := "\\displaystyle\\int_{#1}^{#2}@@0\\,\\mathrm{d}@0"
  }, {
    label := "display", lang := en, binders := [(0, 1)],
    content := "\\displaystyle\\int_{#1}^{#2}@@0\\,\\mathrm{d}@0"
  }, {
    label := "function", lang := zh,
    content := "\\operatorname{integral}(#0,#1,#2)"
  }, {
    label := "function", lang := en,
    content := "\\operatorname{integral}(#0,#1,#2)"
  }]
}
concept_info deriv {
  name := "导数", default := "formula", templates := [{
    label := "formula", content := "#0'(#1)"
  }, {
    label := "derivative", lang := zh, content := "\\frac{\\mathrm{d}}{\\mathrm{d}x}#0\\big|_{x=#1}"
  }, {
    label := "derivative", lang := en, content := "\\frac{\\mathrm{d}}{\\mathrm{d}x}#0\\big|_{x=#1}"
  }]
}
concept_info Int.fract {
  name := "小数部分", default := "formula", templates := [{
    label := "formula", content := "\\{#0\\}"
  }, {
    label := "fractional", lang := zh, content := "\\operatorname{frac}(#0)"
  }, {
    label := "fractional", lang := en, content := "\\operatorname{frac}(#0)"
  }]
}
wrapper_info Int.cast {
  name := "整数嵌入", index := some 2
}
concept_info Real.measureSpace {
  name := "实数上的勒贝格测度空间", templates := [{
    label := "formula", content := "\\mathrm{Lebesgue}"
  }, {
    label := "measure", lang := zh, content := "\\mathrm{Lebesgue}"
  }, {
    label := "measure", lang := en, content := "\\mathrm{Lebesgue}"
  }]
}
concept_info MeasureTheory.MeasureSpace.volume {
  name := "体积测度", templates := [{
    label := "formula", content := "\\mathrm{d}x"
  }, {
    label := "measure", lang := zh, content := "\\mathrm{d}x"
  }, {
    label := "measure", lang := en, content := "\\mathrm{d}x"
  }]
}
concept_info ContDiff {
  name := "连续可微", auto_arity := true, default := "formula",
  templates := [{
    label := "formula", content := "#2\\in C^{#1}(#0)"
  }, {
    label := "smoothness", lang := zh, content := "#2\\in C^{#1}(#0)"
  }, {
    label := "smoothness", lang := en, content := "#2\\in C^{#1}(#0)"
  }]
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
  name := "欧拉—麦克劳林求和公式（一阶余项）",
  tags := ["求和", "积分", "伯努利函数"]
}

concept_info circleIntegral {
  name := "圆周积分", default := "display", templates := [{
    label := "formula", binders := [(0, 1)],
    content := "\\oint_{|@0-#1|=#2}@@0\\,\\mathrm{d}@0"
  }, {
    label := "display", lang := zh, binders := [(0, 1)],
    content := "\\displaystyle\\oint_{|@0-#1|=#2}@@0\\,\\mathrm{d}@0"
  }, {
    label := "display", lang := en, binders := [(0, 1)],
    content := "\\displaystyle\\oint_{|@0-#1|=#2}@@0\\,\\mathrm{d}@0"
  }, {
    label := "function", lang := zh,
    content := "\\operatorname{circleIntegral}(#0,#1,#2)"
  }, {
    label := "function", lang := en,
    content := "\\operatorname{circleIntegral}(#0,#1,#2)"
  }]
}
concept_info DifferentiableOn {
  name := "解析性", default := "formula", templates := [{
    label := "formula", content := "#1\\text{ 在 }#2\\text{ 上对 }#0\\text{ 可微}"
  }, {
    label := "prose", lang := zh, mode := text,
    content := "函数#1在#2上对#0可微"
  }, {
    label := "prose", lang := en, mode := text,
    content := "#1 is differentiable over #0 on #2"
  }]
}
concept_info Metric.closedBall {
  name := "闭圆盘", default := "formula", templates := [{
    label := "formula", content := "\\overline{D}(#0,#1)"
  }, {
    label := "set", lang := zh, content := "\\{z:|z-#0|\\leq #1\\}"
  }, {
    label := "set", lang := en, content := "\\{z:|z-#0|\\leq #1\\}"
  }]
}
concept_info Metric.ball {
  name := "开圆盘", default := "formula", templates := [{
    label := "formula", content := "D(#0,#1)"
  }, {
    label := "set", lang := zh, content := "\\{z:|z-#0|<#1\\}"
  }, {
    label := "set", lang := en, content := "\\{z:|z-#0|<#1\\}"
  }]
}
concept_info Membership.mem {
  name := "属于", default := "formula", templates := [{
    label := "formula", content := "#1\\in #0"
  }, {
    label := "membership", lang := zh, content := "#1\\in #0"
  }, {
    label := "membership", lang := en, content := "#1\\in #0"
  }]
}
concept_info Complex {
  name := "ℂ", default := "formula", templates := [{
    label := "formula", content := "\\mathbb{C}"
  }, {
    label := "number-set", lang := zh, content := "\\mathbb{C}"
  }, {
    label := "number-set", lang := en, content := "\\mathbb{C}"
  }]
}
concept_info Complex.I {
  name := "i", default := "formula", templates := [{
    label := "formula", content := "\\mathrm{i}"
  }, {
    label := "imaginary", lang := zh, content := "\\mathrm{i}"
  }, {
    label := "imaginary", lang := en, content := "\\mathrm{i}"
  }]
}
wrapper_info Complex.ofReal {
  name := "实数嵌入复数", index := some 0
}

/-- Cauchy's integral formula on a closed disc (proof omitted). -/
#page theorem cauchy_integral (f : ℂ → ℂ) (c w : ℂ) (R : ℝ)
    (hf : DifferentiableOn ℂ f (Metric.closedBall c R)) (hw : w ∈ Metric.ball c R)
  : f w = (1 / (2 * (Real.pi : ℂ) * Complex.I)) * ∮ z in C(c, R), f z / (z - w)
:= by admit

theorem_info cauchy_integral {
  name := "柯西积分公式",
  tags := ["复分析", "圆周积分"]
}

end ClassicalFormula
