import PS4HTMLDemo.Library

project_info "PS4HTMLDemo" {}

namespace PS4HTMLDemo.Dependencies

@text r#"
= 高等数学定理依赖导航 <calculus-dependency-navigation>

本页用本科高等数学中的典型结果展示依赖导航。声明采用轻量命题接口，
名称及 `apply` 调用只表达课程层面的依赖，不是这些分析定理的完整形式化陈述。

导航使用最终证明的直接依赖：正文选中当前定理，左侧同时列出它使用的定理和
直接使用它的导出定理。鼠标进入导航后仍保留当前源定理，移出两者后隐藏。
"#

@theorem importedIdentity (info := { name := "跨页面 lemma 依赖" }) (P : Prop) (h : P) : P := by
  exact PS4HTMLDemo.Library.identityLemma P h

@theorem limitUniqueness (info := {name := "极限唯一性定理"}) (P : Prop) (h : P) : P := script
  apply (importedIdentity P)
  assumption

@theorem limitArithmetic (info := {name := "极限的四则运算法则"}) (P : Prop) (h : P) : P := script
  apply (limitUniqueness P)
  assumption

@theorem squeezeTheorem (info := {name := "夹逼定理"}) (P : Prop) (h : P) : P := script
  apply (limitUniqueness P)
  assumption

@theorem firstImportantLimit (info := {name := "第一个重要极限"}) (P : Prop) (h : P) : P := script
  apply (squeezeTheorem P)
  assumption

@theorem secondImportantLimit (info := {name := "第二个重要极限"}) (P : Prop) (h : P) : P := script
  apply (limitArithmetic P)
  apply (squeezeTheorem P)
  assumption

@theorem continuityComposition (info := {name := "连续函数的复合定理"}) (P : Prop) (h : P) : P := script
  apply (limitArithmetic P)
  assumption

@theorem equivalentInfinitesimals (info := {name := "基本等价无穷小公式"}) (P : Prop) (h : P) : P := script
  apply (firstImportantLimit P)
  apply (secondImportantLimit P)
  assumption

@theorem equivalentSubstitution (info := {name := "等价无穷小代换定理"}) (P : Prop) (h : P) : P := script
  apply (equivalentInfinitesimals P)
  apply (limitArithmetic P)
  assumption

@theorem differentiabilityImpliesContinuity (info := {name := "导数定义与可导必连续"}) (P : Prop) (h : P) : P := script
  apply (limitArithmetic P)
  apply (continuityComposition P)
  assumption

@theorem fermatTheorem (info := {name := "费马驻点定理"}) (P : Prop) (h : P) : P := script
  apply (differentiabilityImpliesContinuity P)
  assumption

@theorem rolleTheorem (info := {name := "罗尔中值定理"}) (P : Prop) (h : P) : P := script
  apply (fermatTheorem P)
  apply (continuityComposition P)
  assumption

@theorem lagrangeMeanValueTheorem (info := {name := "拉格朗日中值定理"}) (P : Prop) (h : P) : P := script
  apply (rolleTheorem P)
  assumption

@theorem cauchyMeanValueTheorem (info := {name := "柯西中值定理"}) (P : Prop) (h : P) : P := script
  apply (rolleTheorem P)
  apply (lagrangeMeanValueTheorem P)
  assumption

@theorem lHopitalRule (info := {name := "洛必达法则"}) (P : Prop) (h : P) : P := script
  apply (cauchyMeanValueTheorem P)
  apply (equivalentSubstitution P)
  assumption

@theorem monotonicityCriterion (info := {name := "函数单调性的导数判别法"}) (P : Prop) (h : P) : P := script
  apply (lagrangeMeanValueTheorem P)
  assumption

@theorem extremumCriterion (info := {name := "函数极值的充分条件"}) (P : Prop) (h : P) : P := script
  apply (fermatTheorem P)
  apply (monotonicityCriterion P)
  assumption

@theorem convexityCriterion (info := {name := "曲线凹凸性与拐点判别"}) (P : Prop) (h : P) : P := script
  apply (monotonicityCriterion P)
  apply (differentiabilityImpliesContinuity P)
  assumption

@theorem taylorFormulaPeano (info := {name := "泰勒公式（皮亚诺余项）"}) (P : Prop) (h : P) : P := script
  apply (equivalentInfinitesimals P)
  apply (differentiabilityImpliesContinuity P)
  apply (lagrangeMeanValueTheorem P)
  assumption

@theorem taylorFormulaLagrange (info := {name := "泰勒公式（拉格朗日余项）"}) (P : Prop) (h : P) : P := script
  apply (taylorFormulaPeano P)
  apply (lagrangeMeanValueTheorem P)
  assumption

@theorem taylorLimitMethod (info := {name := "泰勒展开求极限法"}) (P : Prop) (h : P) : P := script
  apply (taylorFormulaPeano P)
  apply (equivalentSubstitution P)
  apply (lHopitalRule P)
  assumption

@theorem fundamentalTheoremOfCalculus (info := {name := "微积分基本定理"}) (P : Prop) (h : P) : P := script
  apply (continuityComposition P)
  apply (lagrangeMeanValueTheorem P)
  assumption

@theorem newtonLeibnizFormula (info := {name := "牛顿—莱布尼茨公式"}) (P : Prop) (h : P) : P := script
  apply (fundamentalTheoremOfCalculus P)
  assumption

@theorem integrationBySubstitution (info := {name := "定积分换元法"}) (P : Prop) (h : P) : P := script
  apply (newtonLeibnizFormula P)
  apply (continuityComposition P)
  assumption

@theorem integrationByParts (info := {name := "定积分分部积分法"}) (P : Prop) (h : P) : P := script
  apply (newtonLeibnizFormula P)
  apply (differentiabilityImpliesContinuity P)
  assumption

@theorem improperIntegralComparison (info := {name := "反常积分比较判别法"}) (P : Prop) (h : P) : P := script
  apply (squeezeTheorem P)
  apply (newtonLeibnizFormula P)
  assumption

@theorem positiveSeriesComparison (info := {name := "正项级数比较判别法"}) (P : Prop) (h : P) : P := script
  apply (squeezeTheorem P)
  apply (improperIntegralComparison P)
  assumption

@theorem ratioAndRootTests (info := {name := "比值与根值判别法"}) (P : Prop) (h : P) : P := script
  apply (positiveSeriesComparison P)
  apply (secondImportantLimit P)
  assumption

@theorem powerSeriesOperations (info := {name := "幂级数的逐项求导与积分"}) (P : Prop) (h : P) : P := script
  apply (ratioAndRootTests P)
  apply (fundamentalTheoremOfCalculus P)
  apply (taylorFormulaLagrange P)
  assumption

@theorem powerSeriesExpansion (info := {name := "函数的幂级数展开"}) (P : Prop) (h : P) : P := script
  apply (powerSeriesOperations P)
  apply (taylorFormulaLagrange P)
  apply (taylorLimitMethod P)
  assumption

page_end
end PS4HTMLDemo.Dependencies
