import Test.SharedDeclInfo

-- Page recording also elaborates and annotates the intermediate calculations.
set_option maxHeartbeats 800000


axiom IsDeriv : (ℝ → ℝ) → (ℝ → ℝ) → Prop
axiom IsContinuous : (ℝ → ℝ) → Prop
axiom IsLocalExtremum (f : ℝ → ℝ) (x₀ : ℝ) : Prop

axiom ivt_average {g : ℝ → ℝ} (h_cont : IsContinuous g) (x₁ x₂ : ℝ) :
    ∃ c ∈ Set.Icc (min x₁ x₂) (max x₁ x₂), g c = (g x₁ + g x₂) / 2
axiom fermat_lemma {f f' : ℝ → ℝ} {x₀ : ℝ} (h_deriv : IsDeriv f f') (h_ext : IsLocalExtremum f x₀) :
    f' x₀ = 0
axiom taylor_lagrange {f f' f'' : ℝ → ℝ} {x₀ x : ℝ} (h_neq : x₀ ≠ x)
    (h_deriv1 : IsDeriv f f') (h_deriv2 : IsDeriv f' f'') :
    ∃ ξ ∈ Set.Ioo (min x₀ x) (max x₀ x), f x = f x₀ + f' x₀ * (x - x₀) + (f'' ξ / 2) * (x - x₀)^2

-- 本模块的分析概念以文字呈现；算式沿用 SharedDeclInfo 中的数学记号。
decl_info IsDeriv {
  kind := relation,
  names := [{ lang := zh, value := "导函数关系" }, { lang := en, value := "Derivative relation" }],
  default_template := "prose",
  templates := [
    { label := "prose", lang := zh,
      content := template%:50 { "函数 " $ arg(0) $ " 的导函数为 " $ arg(1) $ } },
    { label := "prose", lang := en,
      content := template%:50 { "the derivative of " $ arg(0) $ " is " $ arg(1) $ } }
  ]
}

decl_info IsContinuous {
  names := [{ lang := zh, value := "连续性" }, { lang := en, value := "Continuity" }],
  default_template := "prose",
  templates := [
    { label := "prose", lang := zh,
      content := template%:50 { "函数 " $ arg(0) $ " 连续" } },
    { label := "prose", lang := en,
      content := template%:50 { "the function " $ arg(0) $ " is continuous" } }
  ]
}

decl_info IsLocalExtremum {
  names := [{ lang := zh, value := "局部极值" }, { lang := en, value := "Local extremum" }],
  default_template := "prose",
  templates := [
    { label := "prose", lang := zh,
      content := template%:50 { "函数 " $ arg(0) $ " 在 " $ arg(1) $ " 处取得局部极值" } },
    { label := "prose", lang := en,
      content := template%:50 { "the function " $ arg(0) $ " has a local extremum at " $ arg(1) $ } }
  ]
}

-- 这三条辅助结论是公理，用 decl_info 配置其引用；raw 参数包含隐式的函数与展开点。
decl_info ivt_average {
  names := [{ lang := zh, value := "连续函数的介值定理（平均值形式）" },
    { lang := en, value := "Intermediate value theorem (arithmetic mean)" }],
  templates := [
    { label := "prose", lang := zh,
      content := template%:90 raw { "对函数 " $ arg(0) $ " 在 " $ arg(2) $ " 与 " $ arg(3) $
        " 之间应用介值定理（平均值形式）" } },
    { label := "prose", lang := en,
      content := template%:90 raw { "the intermediate value theorem for " $ arg(0) $
        " between " $ arg(2) $ " and " $ arg(3) $ " (arithmetic mean)" } }
  ]
}

decl_info fermat_lemma {
  names := [{ lang := zh, value := "费马引理（极值点处导数为零）" },
    { lang := en, value := "Fermat's lemma (zero derivative at an extremum)" }],
  templates := [
    { label := "prose", lang := zh,
      content := template%:90 raw { "对函数 " $ arg(0) $ " 在极值点 " $ arg(2) $ " 处应用费马引理" } },
    { label := "prose", lang := en,
      content := template%:90 raw { "Fermat's lemma for " $ arg(0) $ " at the extremum " $ arg(2) $ } }
  ]
}

decl_info taylor_lagrange {
  names := [{ lang := zh, value := "二阶泰勒公式（拉格朗日余项）" },
    { lang := en, value := "Second-order Taylor formula with Lagrange remainder" }],
  templates := [
    { label := "prose", lang := zh,
      content := template%:90 raw { "将函数 " $ arg(0) $ " 在 " $ arg(3) $ " 处作二阶泰勒展开并代入 "
        $ arg(4) $ "（拉格朗日余项）" } },
    { label := "prose", lang := en,
      content := template%:90 raw { "the second-order Taylor formula for " $ arg(0) $ " about "
        $ arg(3) $ " evaluated at " $ arg(4) $ " (Lagrange remainder)" } }
  ]
}

decl_info relation GT.gt ">"
decl_info relation GE.ge "≥"
decl_info LT.lt { names := [{ lang := zh, value := "小于" }, { lang := en, value := "Less than" }] }
decl_info LE.le { names := [{ lang := zh, value := "小于或等于" }, { lang := en, value := "Less than or equal to" }] }
decl_info GT.gt { names := [{ lang := zh, value := "大于" }, { lang := en, value := "Greater than" }] }
decl_info GE.ge { names := [{ lang := zh, value := "大于或等于" }, { lang := en, value := "Greater than or equal to" }] }
decl_info Eq { names := [{ lang := zh, value := "等于" }, { lang := en, value := "Equality" }] }
decl_info Neg.neg { names := [{ lang := zh, value := "相反数" }, { lang := en, value := "Negation" }] }
decl_info HAdd.hAdd { names := [{ lang := zh, value := "加法" }, { lang := en, value := "Addition" }] }
decl_info HSub.hSub { names := [{ lang := zh, value := "减法" }, { lang := en, value := "Subtraction" }] }
decl_info HMul.hMul { names := [{ lang := zh, value := "乘法" }, { lang := en, value := "Multiplication" }] }
decl_info HDiv.hDiv { names := [{ lang := zh, value := "除法" }, { lang := en, value := "Division" }] }
decl_info HPow.hPow { names := [{ lang := zh, value := "乘方" }, { lang := en, value := "Exponentiation" }] }
decl_info abs { names := [{ lang := zh, value := "绝对值" }, { lang := en, value := "Absolute value" }] }
decl_info Membership.mem { names := [{ lang := zh, value := "属于" }, { lang := en, value := "Membership" }] }
decl_info Not { names := [{ lang := zh, value := "否定" }, { lang := en, value := "Negation" }] }
decl_info Set.Icc { names := [{ lang := zh, value := "闭区间" }, { lang := en, value := "Closed interval" }] }
decl_info Min.min {
  names := [{ lang := zh, value := "最小值" }, { lang := en, value := "Minimum" }],
  templates := [{ label := "formula",
    content := template%:100 ${ "\\min\\{" arg!(0) ", " arg!(1) "\\}" }$ }]
}
decl_info Max.max {
  names := [{ lang := zh, value := "最大值" }, { lang := en, value := "Maximum" }],
  templates := [{ label := "formula",
    content := template%:100 ${ "\\max\\{" arg!(0) ", " arg!(1) "\\}" }$ }]
}
decl_info Set.Ioo {
  names := [{ lang := zh, value := "开区间" }, { lang := en, value := "Open interval" }],
  templates := [
    { label := "formula", content := template%:100 ${ "(" arg!(0) ", " arg!(1) ")" }$ },
    { label := "prose", lang := zh,
      content := template%:100 { "从 " $ arg(0) $ " 到 " $ arg(1) $ " 的开区间" } },
    { label := "prose", lang := en,
      content := template%:100 { "the open interval from " $ arg(0) $ " to " $ arg(1) $ } }
  ]
}

-- 让存在量词与合取读作句子，同时保留可切换的公式模板。
decl_info templates Exists + [
  { label := "prose", lang := zh,
    content := template%:20 raw { "存在 " $ binder(1, 1) "\\in " arg(0) $ "，使得 " body!(1, 1) } },
  { label := "prose", lang := en,
    content := template%:20 raw { "there exists " $ binder(1, 1) "\\in " arg(0) $ " such that " body!(1, 1) } }
]
decl_info Exists {
  names := [{ lang := zh, value := "存在" }, { lang := en, value := "Existence" }],
  default_template := "prose"
}
decl_info templates And + [
  { label := "prose", lang := zh, content := template%:35 { arg(0) "，且 " arg(1) } },
  { label := "prose", lang := en, content := template%:35 { arg(0) " and " arg(1) } }
]
decl_info And {
  names := [{ lang := zh, value := "并且" }, { lang := en, value := "Conjunction" }],
  default_template := "prose"
}


-- 为证明中引用的基本引理提供可读名称；它们的 Lean 身份保持不变。
theorem_info neg_lt_zero {
  names := [{ lang := zh, value := "正数的相反数为负" }, { lang := en, value := "The negative of a positive number is negative" }]
}
theorem_info ne_of_lt {
  names := [{ lang := zh, value := "严格小于推出不相等" }, { lang := en, value := "Strict inequality implies distinctness" }]
}
theorem_info ne_of_gt {
  names := [{ lang := zh, value := "严格大于推出不相等" }, { lang := en, value := "Strict reverse inequality implies distinctness" }]
}
theorem_info le_of_lt {
  names := [{ lang := zh, value := "严格不等式推出非严格不等式" }, { lang := en, value := "Strict inequality implies weak inequality" }]
}
theorem_info min_eq_left {
  names := [{ lang := zh, value := "较小者在左时取左端最小值" }, { lang := en, value := "Minimum equals the smaller left operand" }]
}
theorem_info min_eq_right {
  names := [{ lang := zh, value := "较小者在右时取右端最小值" }, { lang := en, value := "Minimum equals the smaller right operand" }]
}
theorem_info max_eq_left {
  names := [{ lang := zh, value := "较大者在左时取左端最大值" }, { lang := en, value := "Maximum equals the larger left operand" }]
}
theorem_info max_eq_right {
  names := [{ lang := zh, value := "较大者在右时取右端最大值" }, { lang := en, value := "Maximum equals the larger right operand" }]
}
theorem_info LT.lt.trans {
  names := [{ lang := zh, value := "严格不等式的传递性" }, { lang := en, value := "Transitivity of strict inequality" }]
}
theorem_info LE.le.trans {
  names := [{ lang := zh, value := "非严格不等式的传递性" }, { lang := en, value := "Transitivity of weak inequality" }]
}
theorem_info Iff.mpr {
  names := [{ lang := zh, value := "等价命题的反向蕴涵" }, { lang := en, value := "Reverse implication of an equivalence" }]
}
theorem_info And.left {
  names := [{ lang := zh, value := "取合取命题的第一个条件" }, { lang := en, value := "First condition of a conjunction" }]
}
theorem_info And.right {
  names := [{ lang := zh, value := "取合取命题的第二个条件" }, { lang := en, value := "Second condition of a conjunction" }]
}
theorem_info Eq.symm {
  names := [{ lang := zh, value := "等式的对称性" }, { lang := en, value := "Symmetry of equality" }]
}
theorem_info Eq.trans {
  names := [{ lang := zh, value := "等式的传递性" }, { lang := en, value := "Transitivity of equality" }]
}
theorem_info congrArg {
  names := [{ lang := zh, value := "函数保持相等性" }, { lang := en, value := "Functions preserve equality" }]
}
theorem_info congrFun' {
  names := [{ lang := zh, value := "相等函数在同一点的值相等" }, { lang := en, value := "Equal functions agree at every point" }]
}
theorem_info congr {
  names := [{ lang := zh, value := "相等函数作用于相等参数的结果相等" }, { lang := en, value := "Equal functions applied to equal arguments give equal values" }]
}
theorem_info of_eq_true {
  names := [{ lang := zh, value := "等于真命题的命题成立" }, { lang := en, value := "A proposition equal to true holds" }]
}
theorem_info eq_self {
  names := [{ lang := zh, value := "自身相等" }, { lang := en, value := "Self-equality" }]
}
theorem_info pow_pos {
  names := [{ lang := zh, value := "正数的自然数次幂为正" }, { lang := en, value := "A natural power of a positive number is positive" }]
}
theorem_info sub_zero {
  names := [{ lang := zh, value := "减去零不变" }, { lang := en, value := "Subtracting zero" }]
}
theorem_info zero_add {
  names := [{ lang := zh, value := "零加任意数等于该数" }, { lang := en, value := "Adding zero on the left" }]
}
theorem_info add_zero {
  names := [{ lang := zh, value := "任意数加零不变" }, { lang := en, value := "Adding zero on the right" }]
}
theorem_info zero_mul {
  names := [{ lang := zh, value := "零乘任意数等于零" }, { lang := en, value := "Multiplication by zero" }]
}
theorem_info neg_sq {
  names := [{ lang := zh, value := "相反数的平方不变" }, { lang := en, value := "Squaring a negative" }]
}
theorem_info neg_add {
  names := [{ lang := zh, value := "和的相反数" }, { lang := en, value := "Negation of a sum" }]
}
theorem_info mul_neg {
  names := [{ lang := zh, value := "乘以相反数" }, { lang := en, value := "Multiplication by a negative" }]
}
theorem_info add_add_add_comm {
  names := [{ lang := zh, value := "四项和的重排" }, { lang := en, value := "Rearranging a sum of four terms" }]
}
theorem_info add_neg_cancel {
  names := [{ lang := zh, value := "相反数相加抵消" }, { lang := en, value := "Cancellation of additive inverses" }]
}
theorem_info add_mul {
  names := [{ lang := zh, value := "乘法对加法的分配律" }, { lang := en, value := "Distributivity over addition" }]
}
theorem_info add_div {
  names := [{ lang := zh, value := "同分母分式相加" }, { lang := en, value := "Adding fractions with a common denominator" }]
}
theorem_info mul_div_cancel_right₀ {
  names := [{ lang := zh, value := "约去非零公因子" }, { lang := en, value := "Cancelling a nonzero common factor" }]
}
theorem_info abs_sub {
  names := [{ lang := zh, value := "差的绝对值三角不等式" }, { lang := en, value := "Triangle inequality for a difference" }]
}
theorem_info abs_mul {
  names := [{ lang := zh, value := "乘积的绝对值" }, { lang := en, value := "Absolute value of a product" }]
}
theorem_info abs_div {
  names := [{ lang := zh, value := "商的绝对值" }, { lang := en, value := "Absolute value of a quotient" }]
}
theorem_info abs_of_pos {
  names := [{ lang := zh, value := "正数的绝对值等于自身" }, { lang := en, value := "Absolute value of a positive number" }]
}
theorem_info abs_of_nonneg {
  names := [{ lang := zh, value := "非负数的绝对值等于自身" }, { lang := en, value := "Absolute value of a nonnegative number" }]
}
theorem_info abs_nonneg {
  names := [{ lang := zh, value := "绝对值非负" }, { lang := en, value := "Nonnegativity of absolute value" }]
}
theorem_info sq_nonneg {
  names := [{ lang := zh, value := "平方非负" }, { lang := en, value := "Nonnegativity of a square" }]
}
theorem_info sq_le_sq' {
  names := [{ lang := zh, value := "对称区间内的平方上界" }, { lang := en, value := "Square bound on a symmetric interval" }]
}
theorem_info div_le_iff₀ {
  names := [{ lang := zh, value := "正分母不等式的等价变形" }, { lang := en, value := "Clearing a positive denominator in an inequality" }]
}
theorem_info lt_of_not_ge {
  names := [{ lang := zh, value := "不大于等于则严格小于" }, { lang := en, value := "Failure of a reverse weak inequality implies strict inequality" }]
}

#page title "二阶导数的中值等式与下界"

#page theorem problem_1 (a : ℝ) (ha : a > 0) (f f' f'' : ℝ → ℝ)
    (h_deriv1 : IsDeriv f f')
    (h_deriv2 : IsDeriv f' f'')
    (h_cont : IsContinuous f'')
    (hf0 : f 0 = 0) :
    ∃ ξ ∈ Set.Ioo (-a) a, f'' ξ = (f a + f (-a)) / a^2 := script
  infer
    0 < a => ha_neg : -a < 0 := neg_lt_zero.mpr ha
  obtain_exist ⟨η₁, hη₁_bound, hη₁_eq⟩ :=
    taylor_lagrange (ne_of_lt ha) h_deriv1 h_deriv2
  obtain_exist ⟨η₂, hη₂_bound, hη₂_eq⟩ :=
    taylor_lagrange (ne_of_gt ha_neg) h_deriv1 h_deriv2
  obtain_exist ⟨ξ, hξ_bound, hξ_eq⟩ := ivt_average h_cont η₁ η₂
  provide ξ
  split_and
  | left =>
    rw [min_eq_left (le_of_lt ha), max_eq_right (le_of_lt ha)] at hη₁_bound
    rw [min_eq_right (le_of_lt ha_neg), max_eq_left (le_of_lt ha_neg)] at hη₂_bound
    infer
      η₂ < 0 => h2_lt_1 : η₂ < η₁ := hη₂_bound.right.trans hη₁_bound.left
    rw [min_eq_right (le_of_lt h2_lt_1), max_eq_left (le_of_lt h2_lt_1)] at hξ_bound
    split_and
    | left =>
      calc
        -a < η₂ := hη₂_bound.left
        _  ≤ ξ := hξ_bound.left
    | right =>
      calc
        ξ ≤ η₁ := hξ_bound.right
        _ < a := hη₁_bound.right
  | right =>
    infer
      f 0 = 0 => eq1 : f a = f' 0 * a + (f'' η₁ / 2) * a^2 := by
        calc
          f a = f 0 + f' 0 * (a - 0) + (f'' η₁ / 2) * (a - 0)^2 := hη₁_eq
          _   = 0 + f' 0 * (a - 0) + (f'' η₁ / 2) * (a - 0)^2   := by rw [hf0]
          _   = f' 0 * a + (f'' η₁ / 2) * a^2                   := by simp only [sub_zero, zero_add]
      => eq2 : f (-a) = f' 0 * (-a) + (f'' η₂ / 2) * a^2 := by
        calc
          f (-a) = f 0 + f' 0 * (-a - 0) + (f'' η₂ / 2) * (-a - 0)^2 := hη₂_eq
          _      = 0 + f' 0 * (-a - 0) + (f'' η₂ / 2) * (-a - 0)^2   := by rw [hf0]
          _      = f' 0 * (-a) + (f'' η₂ / 2) * a^2               := by simp only [sub_zero, zero_add, neg_sq]
    symm
    calc
      (f a + f (-a)) / a^2 = ((f' 0 * a + (f'' η₁ / 2) * a^2)
                              + (f' 0 * (-a) + (f'' η₂ / 2) * a^2)) / a^2
                            := by rw [eq1, eq2]
      _                    = ((f'' η₁ + f'' η₂) / 2) * a^2 / a^2
                            := by
                              rw [mul_neg, add_add_add_comm, add_neg_cancel, zero_add,
                                ← add_mul, ← add_div]
      _                    = (f'' η₁ + f'' η₂) / 2
                            := by rw [mul_div_cancel_right₀ _ (by positivity)]
      _                    = f'' ξ
                            := by rw [← hξ_eq]

theorem_info problem_1 {
  names := [{ lang := zh, value := "第一问：对称区间上的二阶导数中值等式" },
    { lang := en, value := "Part 1: A mean-value identity for the second derivative" }],
  tags := [{ lang := zh, value := "泰勒公式" }, { lang := zh, value := "介值定理" },
    { lang := en, value := "Taylor's theorem" }, { lang := en, value := "Intermediate value theorem" }]
}

#page theorem problem_2 (a : ℝ) (ha : a > 0) (f f' f'' : ℝ → ℝ)
    (h_deriv1 : IsDeriv f f')
    (h_deriv2 : IsDeriv f' f'')
    (x₀ : ℝ) (hx₀_in : -a < x₀ ∧ x₀ < a)
    (h_ext : IsLocalExtremum f x₀) :
    ∃ η ∈ Set.Ioo (-a) a, |f'' η| ≥ |f a - f (-a)| / (2 * a^2) := script
  infer
    IsLocalExtremum f x₀ => h_f'x0 : f' x₀ = 0 := fermat_lemma h_deriv1 h_ext
  obtain_exist ⟨η₁, hη₁_bound, hη₁_eq⟩ :=
    taylor_lagrange (ne_of_lt hx₀_in.right) h_deriv1 h_deriv2
  obtain_exist ⟨η₂, hη₂_bound, hη₂_eq⟩ :=
    taylor_lagrange (ne_of_gt hx₀_in.left) h_deriv1 h_deriv2
  infer
    f' x₀ = 0 => eq1 : f a = f x₀ + (f'' η₁ / 2) * (a - x₀)^2 := by
      calc
        f a = f x₀ + f' x₀ * (a - x₀) + (f'' η₁ / 2) * (a - x₀)^2 := hη₁_eq
        _   = f x₀ + 0 * (a - x₀) + (f'' η₁ / 2) * (a - x₀)^2 := by rw [h_f'x0]
        _   = f x₀ + (f'' η₁ / 2) * (a - x₀)^2 := by simp only [zero_mul, add_zero]
    => eq2 : f (-a) = f x₀ + (f'' η₂ / 2) * (a + x₀)^2 := by
      calc
        f (-a) = f x₀ + f' x₀ * (-a - x₀) + (f'' η₂ / 2) * (-a - x₀)^2 := hη₂_eq
        _      = f x₀ + 0 * (-a - x₀) + (f'' η₂ / 2) * (-a - x₀)^2 := by rw [h_f'x0]
        _      = f x₀ + (f'' η₂ / 2) * (a + x₀)^2 := by
          simp only [zero_mul, add_zero, sub_eq_add_neg, ← neg_add, neg_sq]
    => h_diff : f a - f (-a)
        = (f'' η₁ / 2) * (a - x₀)^2 - (f'' η₂ / 2) * (a + x₀)^2 := by
      linarith only [eq1, this]
    => h_abs_ineq : |f a - f (-a)| ≤
        (|f'' η₁| / 2) * (a - x₀)^2 + (|f'' η₂| / 2) * (a + x₀)^2 := by
      calc
        |f a - f (-a)| = |(f'' η₁ / 2) * (a - x₀)^2 - (f'' η₂ / 2) * (a + x₀)^2|
                        := by rw [this]
        _              ≤ |(f'' η₁ / 2) * (a - x₀)^2| + |(f'' η₂ / 2) * (a + x₀)^2|
                        := abs_sub _ _
        _              = (|f'' η₁| / 2) * (a - x₀)^2 + (|f'' η₂| / 2) * (a + x₀)^2
                        := by
                          rw [abs_mul, abs_mul, abs_div, abs_div]
                          rw [abs_of_pos (by positivity : (0 : ℝ) < 2)]
                          rw [abs_of_nonneg (sq_nonneg (a - x₀)), abs_of_nonneg (sq_nonneg (a + x₀))]
  infer
    (-a < x₀ ∧ x₀ < a) => hax_le : x₀^2 ≤ a^2 :=
      sq_le_sq' (le_of_lt hx₀_in.left) (le_of_lt hx₀_in.right)
  cases_on (|f'' η₁| ≥ |f'' η₂|)
  | true h_max =>
    provide η₁
    split_and
    | left =>
      split_and
      | left =>
        calc
          -a < x₀ := hx₀_in.left
          _  = min x₀ a := (min_eq_left (le_of_lt hx₀_in.2)).symm
          _  < η₁ := hη₁_bound.left
      | right =>
        rw [← max_eq_right (le_of_lt hx₀_in.right)]
        exact_proj hη₁_bound
    | right =>
      infer
        |f'' η₁| ≥ |f'' η₂| => h_M_nonneg : 0 ≤ |f'' η₁| :=
          (abs_nonneg (f'' η₂)).trans h_max
        => h_bound3 : |f a - f (-a)| ≤ |f'' η₁| * (2 * a^2) := by
          nlinarith only [this, h_abs_ineq, hax_le, h_max]
        => |f'' η₁| ≥ |f a - f (-a)| / (2 * a^2) :=
          (div_le_iff₀ (by positivity)).mpr ?_
  | false h_max =>
    provide η₂
    split_and
    | left =>
      split_and
      | left =>
        rw [← min_eq_right (le_of_lt hx₀_in.left)]
        exact_proj hη₂_bound
      | right =>
        calc
          η₂ < max x₀ (-a) := hη₂_bound.right
          _  = x₀ := max_eq_left (le_of_lt hx₀_in.1)
          _  < a := hx₀_in.right
    | right =>
      infer
        ¬ (|f'' η₁| ≥ |f'' η₂|) => h_M_nonneg : 0 ≤ |f'' η₂| :=
          (abs_nonneg (f'' η₁)).trans (le_of_lt (lt_of_not_ge h_max))
        => h_bound3 : |f a - f (-a)| ≤ |f'' η₂| * (2 * a^2) := by
          nlinarith only [this, h_abs_ineq, hax_le, h_max]
        => |f'' η₂| ≥ |f a - f (-a)| / (2 * a^2) :=
          (div_le_iff₀ (by positivity)).mpr ?_

theorem_info problem_2 {
  names := [{ lang := zh, value := "第二问：内部极值给出的二阶导数绝对值下界" },
    { lang := en, value := "Part 2: A lower bound for the second derivative from an interior extremum" }],
  tags := [{ lang := zh, value := "泰勒公式" }, { lang := zh, value := "费马引理" },
    { lang := zh, value := "绝对值估计" }, { lang := en, value := "Taylor's theorem" },
    { lang := en, value := "Fermat's lemma" }, { lang := en, value := "Absolute value estimates" }]
}
