# Lean2TeX 变量管理系统

当前实现为 Python，相关代码在 `Lean2TeX/variable.py`、`semantic.py`、`renderer.py`。
命名池通过 Lean 的 `var_info` 声明，随 `.ProofScript/lean2tex/events/` 导出，由 `ConfigurationIndex` 按证明模块合并。

变量根据语义类型选择名字池，已分配名称避免冲突，同一自由变量通过 ID 缓存保持一致。
绑定变量由转换器处理作用域及绑定引用；最终 TeX 携带 `htmlData` 元数据，供
`PS4HTML/assets/js/lean2tex.js` 在同一定理范围内高亮对应引用。

每个定理创建独立 ProofEngine 和表达式渲染器。外部调用者复用 Lean2TeX 实例时，
应在定理边界调用 `renderer.reset()`。

详细分配规则、fallback 和测试说明见 [Lean2TeX 模块说明](Lean2TeX/模块说明.md)。
旧版 Lean 实现的 `Prelude.lean`、`VariableToml.lean` 等不属于当前运行架构。
