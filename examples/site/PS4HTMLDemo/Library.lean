import ProofScript

project_info "PS4HTMLDemo" {
  title := "PS4HTML 完整组件展示",
  authors := ["PS4HTML Contributors"],
  description := "一个由 ProofScript 编写并由 PS4HTML 生成的交互式形式化数学展示项目。",
  keywords := ["Lean 4", "ProofScript", "PS4HTML", "formal mathematics"],
  year := "2026",
  base_url := "https://github.com/JokerXin2025/ProofScript",
  license := "Apache-2.0"
}

namespace PS4HTMLDemo.Library

@text r#"
= 参考定理库 <library>

本模块提供主展示页面所引用的基础结果。定理元数据会跨模块保存在环境中，
同项目定理的最终证明引用会进入依赖图；可选的参考文献收集独立工作。
"#

@theorem andLeft (info := {
  name := "合取左投影",
  tags := ["logic", "projection"]
}) (P Q : Prop) (h : P ∧ Q) : P := script
  unpack_and ⟨hP, hQ⟩ := h
  assumption


-- Ordinary Lean theorems need explicit project ownership to enter the project graph.
theorem ordinaryIdentity (P : Prop) (h : P) : P := h
theorem_info ordinaryIdentity { project := "PS4HTMLDemo", name := "普通 Lean 恒等定理" }

@lemma identityLemma (info := { name := "普通定理的 lemma 包装" }) (P : Prop) (h : P) : P := script
  apply (ordinaryIdentity P)
  assumption

@text r#"
上面的证明展示了一个最小但完整的 theorem component。主页面会引用
@thm:PS4HTMLDemo.Library.andLeft，并在参考文献板块中链接回本页。
"#

page_end

end PS4HTMLDemo.Library
