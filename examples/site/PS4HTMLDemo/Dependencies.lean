import ProofScript

namespace PS4HTMLDemo.Dependencies

@text r#"
= 高等数学定理依赖导航 <calculus-dependency-navigation>

本页用本科高等数学中的典型结果展示依赖导航。声明采用轻量命题接口，
名称及 `apply` 调用只表达课程层面的依赖，不是这些分析定理的完整形式化陈述。
"#

@theorem limitUniqueness (P : Prop) (h : P) : P := script
  assumption
theorem_info limitUniqueness {name := "极限唯一性定理"}

@theorem limitArithmetic (P : Prop) (h : P) : P := script
  apply (limitUniqueness P)
  assumption
theorem_info limitArithmetic {name := "极限的四则运算法则"}

@theorem squeezeTheorem (P : Prop) (h : P) : P := script
  apply (limitUniqueness P)
  assumption
theorem_info squeezeTheorem {name := "夹逼定理"}

@theorem firstImportantLimit (P : Prop) (h : P) : P := script
  apply (squeezeTheorem P)
  assumption
theorem_info firstImportantLimit {name := "第一个重要极限"}

@theorem secondImportantLimit (P : Prop) (h : P) : P := script
  apply (limitArithmetic P)
  apply (squeezeTheorem P)
  assumption
theorem_info secondImportantLimit {name := "第二个重要极限"}

@theorem continuityComposition (P : Prop) (h : P) : P := script
  apply (limitArithmetic P)
  assumption
theorem_info continuityComposition {name := "连续函数的复合定理"}

@theorem equivalentInfinitesimals (P : Prop) (h : P) : P := script
  apply (firstImportantLimit P)
  apply (secondImportantLimit P)
  assumption
theorem_info equivalentInfinitesimals {name := "基本等价无穷小公式"}

@theorem equivalentSubstitution (P : Prop) (h : P) : P := script
  apply (equivalentInfinitesimals P)
  apply (limitArithmetic P)
  assumption
theorem_info equivalentSubstitution {name := "等价无穷小代换定理"}

@theorem differentiabilityImpliesContinuity (P : Prop) (h : P) : P := script
  apply (limitArithmetic P)
  apply (continuityComposition P)
  assumption
theorem_info differentiabilityImpliesContinuity {name := "导数定义与可导必连续"}

@theorem fermatTheorem (P : Prop) (h : P) : P := script
  apply (differentiabilityImpliesContinuity P)
  assumption
theorem_info fermatTheorem {name := "费马驻点定理"}

@theorem rolleTheorem (P : Prop) (h : P) : P := script
  apply (fermatTheorem P)
  apply (continuityComposition P)
  assumption
theorem_info rolleTheorem {name := "罗尔中值定理"}

@theorem lagrangeMeanValueTheorem (P : Prop) (h : P) : P := script
  apply (rolleTheorem P)
  assumption
theorem_info lagrangeMeanValueTheorem {name := "拉格朗日中值定理"}

@theorem cauchyMeanValueTheorem (P : Prop) (h : P) : P := script
  apply (rolleTheorem P)
  apply (lagrangeMeanValueTheorem P)
  assumption
theorem_info cauchyMeanValueTheorem {name := "柯西中值定理"}

@theorem lHopitalRule (P : Prop) (h : P) : P := script
  apply (cauchyMeanValueTheorem P)
  apply (equivalentSubstitution P)
  assumption
theorem_info lHopitalRule {name := "洛必达法则"}

@theorem monotonicityCriterion (P : Prop) (h : P) : P := script
  apply (lagrangeMeanValueTheorem P)
  assumption
theorem_info monotonicityCriterion {name := "函数单调性的导数判别法"}

@theorem extremumCriterion (P : Prop) (h : P) : P := script
  apply (fermatTheorem P)
  apply (monotonicityCriterion P)
  assumption
theorem_info extremumCriterion {name := "函数极值的充分条件"}

@theorem convexityCriterion (P : Prop) (h : P) : P := script
  apply (monotonicityCriterion P)
  apply (differentiabilityImpliesContinuity P)
  assumption
theorem_info convexityCriterion {name := "曲线凹凸性与拐点判别"}

@theorem taylorFormulaPeano (P : Prop) (h : P) : P := script
  apply (equivalentInfinitesimals P)
  apply (differentiabilityImpliesContinuity P)
  apply (lagrangeMeanValueTheorem P)
  assumption
theorem_info taylorFormulaPeano {name := "泰勒公式（皮亚诺余项）"}

@theorem taylorFormulaLagrange (P : Prop) (h : P) : P := script
  apply (taylorFormulaPeano P)
  apply (lagrangeMeanValueTheorem P)
  assumption
theorem_info taylorFormulaLagrange {name := "泰勒公式（拉格朗日余项）"}

@theorem taylorLimitMethod (P : Prop) (h : P) : P := script
  apply (taylorFormulaPeano P)
  apply (equivalentSubstitution P)
  apply (lHopitalRule P)
  assumption
theorem_info taylorLimitMethod {name := "泰勒展开求极限法"}

@theorem fundamentalTheoremOfCalculus (P : Prop) (h : P) : P := script
  apply (continuityComposition P)
  apply (lagrangeMeanValueTheorem P)
  assumption
theorem_info fundamentalTheoremOfCalculus {name := "微积分基本定理"}

@theorem newtonLeibnizFormula (P : Prop) (h : P) : P := script
  apply (fundamentalTheoremOfCalculus P)
  assumption
theorem_info newtonLeibnizFormula {name := "牛顿—莱布尼茨公式"}

@theorem integrationBySubstitution (P : Prop) (h : P) : P := script
  apply (newtonLeibnizFormula P)
  apply (continuityComposition P)
  assumption
theorem_info integrationBySubstitution {name := "定积分换元法"}

@theorem integrationByParts (P : Prop) (h : P) : P := script
  apply (newtonLeibnizFormula P)
  apply (differentiabilityImpliesContinuity P)
  assumption
theorem_info integrationByParts {name := "定积分分部积分法"}

@theorem improperIntegralComparison (P : Prop) (h : P) : P := script
  apply (squeezeTheorem P)
  apply (newtonLeibnizFormula P)
  assumption
theorem_info improperIntegralComparison {name := "反常积分比较判别法"}

@theorem positiveSeriesComparison (P : Prop) (h : P) : P := script
  apply (squeezeTheorem P)
  apply (improperIntegralComparison P)
  assumption
theorem_info positiveSeriesComparison {name := "正项级数比较判别法"}

@theorem ratioAndRootTests (P : Prop) (h : P) : P := script
  apply (positiveSeriesComparison P)
  apply (secondImportantLimit P)
  assumption
theorem_info ratioAndRootTests {name := "比值与根值判别法"}

@theorem powerSeriesOperations (P : Prop) (h : P) : P := script
  apply (ratioAndRootTests P)
  apply (fundamentalTheoremOfCalculus P)
  apply (taylorFormulaLagrange P)
  assumption
theorem_info powerSeriesOperations {name := "幂级数的逐项求导与积分"}

@theorem powerSeriesExpansion (P : Prop) (h : P) : P := script
  apply (powerSeriesOperations P)
  apply (taylorFormulaLagrange P)
  apply (taylorLimitMethod P)
  assumption
theorem_info powerSeriesExpansion {name := "函数的幂级数展开"}

page_end
end PS4HTMLDemo.Dependencies
