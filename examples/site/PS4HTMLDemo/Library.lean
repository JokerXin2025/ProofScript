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

#page text r#"
= 参考定理库 <library>

本模块提供主展示页面所引用的基础结果。定理元数据会跨模块保存在环境中，
同项目的自动证明引用会进入依赖图，也会进入页面的参考文献暂存区。
手动 `cite` 仅补充文献；`#page references` 消费暂存区后，定理的持久化引用仍保留。
"#

#page theorem andLeft (P Q : Prop) (h : P ∧ Q) : P := script
  unpack_and ⟨hP, hQ⟩ := h
  assumption

theorem_info andLeft {
  name := "合取左投影",
  tags := ["logic", "projection"]
}

-- Ordinary Lean theorems need explicit project ownership to enter the project graph.
theorem ordinaryIdentity (P : Prop) (h : P) : P := h
theorem_info ordinaryIdentity { project := "PS4HTMLDemo", name := "普通 Lean 恒等定理" }

#page lemma identityLemma (P : Prop) (h : P) : P := script
  apply (ordinaryIdentity P)
  assumption

theorem_info identityLemma { name := "普通定理的 lemma 包装" }

#page text r#"
上面的证明展示了一个最小但完整的 theorem component。主页面会引用
@thm:PS4HTMLDemo.Library.andLeft，并在参考文献板块中链接回本页。
"#

#page end

end PS4HTMLDemo.Library
