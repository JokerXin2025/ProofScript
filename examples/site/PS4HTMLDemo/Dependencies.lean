import PS4HTMLDemo.Library

project_info "PS4HTMLDemo" {}

namespace PS4HTMLDemo.Dependencies

#page text r#"
= 高等数学定理依赖导航 <calculus-dependency-navigation>

本页用本科高等数学中的典型结果展示依赖导航。声明采用轻量命题接口，
名称及 `apply` 调用只表达课程层面的依赖，不是这些分析定理的完整形式化陈述。

导航使用最终证明的直接依赖：正文选中当前定理，左侧同时列出它使用的定理和
直接使用它的导出定理。鼠标进入导航后仍保留当前源定理，移出两者后隐藏。
"#

#page theorem importedIdentity (P : Prop) (h : P) : P := by
  exact PS4HTMLDemo.Library.identityLemma P h

theorem_info importedIdentity { name := "跨页面 lemma 依赖" }

#page theorem limitUniqueness (P : Prop) (h : P) : P := script
  apply (importedIdentity P)
  assumption

theorem_info limitUniqueness {name := "极限唯一性定理"}

#page theorem limitArithmetic (P : Prop) (h : P) : P := script
  apply (limitUniqueness P)
  assumption

theorem_info limitArithmetic {name := "极限的四则运算法则"}

#page theorem squeezeTheorem (P : Prop) (h : P) : P := script
  apply (limitUniqueness P)
  assumption

theorem_info squeezeTheorem {name := "夹逼定理"}

#page theorem firstImportantLimit (P : Prop) (h : P) : P := script
  apply (squeezeTheorem P)
  assumption

theorem_info firstImportantLimit {name := "第一个重要极限"}

#page theorem secondImportantLimit (P : Prop) (h : P) : P := script
  apply (limitArithmetic P)
  apply (squeezeTheorem P)
  assumption

theorem_info secondImportantLimit {name := "第二个重要极限"}

#page theorem continuityComposition (P : Prop) (h : P) : P := script
  apply (limitArithmetic P)
  assumption

theorem_info continuityComposition {name := "连续函数的复合定理"}

#page theorem equivalentInfinitesimals (P : Prop) (h : P) : P := script
  apply (firstImportantLimit P)
  apply (secondImportantLimit P)
  assumption

theorem_info equivalentInfinitesimals {name := "基本等价无穷小公式"}

#page theorem equivalentSubstitution (P : Prop) (h : P) : P := script
  apply (equivalentInfinitesimals P)
  apply (limitArithmetic P)
  assumption

theorem_info equivalentSubstitution {name := "等价无穷小代换定理"}

#page theorem differentiabilityImpliesContinuity (P : Prop) (h : P) : P := script
  apply (limitArithmetic P)
  apply (continuityComposition P)
  assumption

theorem_info differentiabilityImpliesContinuity {name := "导数定义与可导必连续"}

#page theorem fermatTheorem (P : Prop) (h : P) : P := script
  apply (differentiabilityImpliesContinuity P)
  assumption

theorem_info fermatTheorem {name := "费马驻点定理"}

#page theorem rolleTheorem (P : Prop) (h : P) : P := script
  apply (fermatTheorem P)
  apply (continuityComposition P)
  assumption

theorem_info rolleTheorem {name := "罗尔中值定理"}

#page theorem lagrangeMeanValueTheorem (P : Prop) (h : P) : P := script
  apply (rolleTheorem P)
  assumption

theorem_info lagrangeMeanValueTheorem {name := "拉格朗日中值定理"}

#page theorem cauchyMeanValueTheorem (P : Prop) (h : P) : P := script
  apply (rolleTheorem P)
  apply (lagrangeMeanValueTheorem P)
  assumption

theorem_info cauchyMeanValueTheorem {name := "柯西中值定理"}

#page theorem lHopitalRule (P : Prop) (h : P) : P := script
  apply (cauchyMeanValueTheorem P)
  apply (equivalentSubstitution P)
  assumption

theorem_info lHopitalRule {name := "洛必达法则"}

#page theorem monotonicityCriterion (P : Prop) (h : P) : P := script
  apply (lagrangeMeanValueTheorem P)
  assumption

theorem_info monotonicityCriterion {name := "函数单调性的导数判别法"}

#page theorem extremumCriterion (P : Prop) (h : P) : P := script
  apply (fermatTheorem P)
  apply (monotonicityCriterion P)
  assumption

theorem_info extremumCriterion {name := "函数极值的充分条件"}

#page theorem convexityCriterion (P : Prop) (h : P) : P := script
  apply (monotonicityCriterion P)
  apply (differentiabilityImpliesContinuity P)
  assumption

theorem_info convexityCriterion {name := "曲线凹凸性与拐点判别"}

#page theorem taylorFormulaPeano (P : Prop) (h : P) : P := script
  apply (equivalentInfinitesimals P)
  apply (differentiabilityImpliesContinuity P)
  apply (lagrangeMeanValueTheorem P)
  assumption

theorem_info taylorFormulaPeano {name := "泰勒公式（皮亚诺余项）"}

#page theorem taylorFormulaLagrange (P : Prop) (h : P) : P := script
  apply (taylorFormulaPeano P)
  apply (lagrangeMeanValueTheorem P)
  assumption

theorem_info taylorFormulaLagrange {name := "泰勒公式（拉格朗日余项）"}

#page theorem taylorLimitMethod (P : Prop) (h : P) : P := script
  apply (taylorFormulaPeano P)
  apply (equivalentSubstitution P)
  apply (lHopitalRule P)
  assumption

theorem_info taylorLimitMethod {name := "泰勒展开求极限法"}

#page theorem fundamentalTheoremOfCalculus (P : Prop) (h : P) : P := script
  apply (continuityComposition P)
  apply (lagrangeMeanValueTheorem P)
  assumption

theorem_info fundamentalTheoremOfCalculus {name := "微积分基本定理"}

#page theorem newtonLeibnizFormula (P : Prop) (h : P) : P := script
  apply (fundamentalTheoremOfCalculus P)
  assumption

theorem_info newtonLeibnizFormula {name := "牛顿—莱布尼茨公式"}

#page theorem integrationBySubstitution (P : Prop) (h : P) : P := script
  apply (newtonLeibnizFormula P)
  apply (continuityComposition P)
  assumption

theorem_info integrationBySubstitution {name := "定积分换元法"}

#page theorem integrationByParts (P : Prop) (h : P) : P := script
  apply (newtonLeibnizFormula P)
  apply (differentiabilityImpliesContinuity P)
  assumption

theorem_info integrationByParts {name := "定积分分部积分法"}

#page theorem improperIntegralComparison (P : Prop) (h : P) : P := script
  apply (squeezeTheorem P)
  apply (newtonLeibnizFormula P)
  assumption

theorem_info improperIntegralComparison {name := "反常积分比较判别法"}

#page theorem positiveSeriesComparison (P : Prop) (h : P) : P := script
  apply (squeezeTheorem P)
  apply (improperIntegralComparison P)
  assumption

theorem_info positiveSeriesComparison {name := "正项级数比较判别法"}

#page theorem ratioAndRootTests (P : Prop) (h : P) : P := script
  apply (positiveSeriesComparison P)
  apply (secondImportantLimit P)
  assumption

theorem_info ratioAndRootTests {name := "比值与根值判别法"}

#page theorem powerSeriesOperations (P : Prop) (h : P) : P := script
  apply (ratioAndRootTests P)
  apply (fundamentalTheoremOfCalculus P)
  apply (taylorFormulaLagrange P)
  assumption

theorem_info powerSeriesOperations {name := "幂级数的逐项求导与积分"}

#page theorem powerSeriesExpansion (P : Prop) (h : P) : P := script
  apply (powerSeriesOperations P)
  apply (taylorFormulaLagrange P)
  apply (taylorLimitMethod P)
  assumption

theorem_info powerSeriesExpansion {name := "函数的幂级数展开"}

#page references

#page text r#"
= 手动引用与自动依赖 <manual-citations>

下面的证明关闭自动引用收集，但仍可用 `cite` 补充文献。恒等 lemma 出现在
这一节的参考文献中，而不会成为该定理的导航依赖。参考文献显示后会清空暂存区，
前面定理已经保存的依赖不受影响。
"#

set_option dependencyCollection false in
#page theorem manualCitation (P : Prop) (h : P) : P := script
  cite (PS4HTMLDemo.Library.identityLemma P h)
  exact h

theorem_info manualCitation { name := "关闭自动收集后的手动引用" }

#page references

#page end
end PS4HTMLDemo.Dependencies
