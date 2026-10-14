# Lean2TeX

PS4HTML 使用 ProofScript 导出的 ExprJSON 和 Lean-owned 配置，将表达式转换为 DisplayTree 并渲染为 TeX。配置来自证明所属模块的传递导入，保存在 `.ProofScript/lean2tex/events/`；模块导入图来自 `.ProofScript/rendering/modules/`。`make --cache` 使用隔离的 `.PS4HTML/inputs/<包>/<库>/.ProofScript/` 快照。

## 在 Lean 文件中配置

`def_info` 的目标必须是已经存在的 Lean 声明；每个命令只更新写出的字段。以下例子应放在导入目标声明之后：

```lean
def_info Eq { calc_symbol := some "=" }
def_info OfNat.ofNat { unwrap := some 1 }
def_info HAdd.hAdd { kind := operator, arguments := explicit, styles := [
  { name := "formula", template := "#0+#1", fixity := «infix», precedence := 65,
    associativity := left }
] }
var_info "Real" { default := "x", names := ["x", "y", "z"] }
phrase_info "forall" { template := [
  { lang := "zh", content := "${body}对一切 $${binder}\\in ${type}$ 成立" },
  { lang := "en", content := "${body} holds for every $${binder}\\in ${type}$" }
] }
```

`alias := some OtherDeclaration` 转发到已有声明的配置，`unwrap := some N` 选择从零开始的**原始应用参数**（包括隐式参数）。`alias`、`unwrap` 不可同时有效；省略字段表示沿用已有值，`none` 表示清除。提供 `calc_symbol` 而省略 `styles` 时，Python 自动生成优先级 50、无结合方向的二元中缀样式。显式 `styles` 以整个有序列表替换；`phrase_info.template` 按语言合并。若在两个互不导入的模块中对同一配置字段赋值，构建报告冲突。

`#N` 引用筛选后的第 N 个语义子表达式；`#*` 与 `dynamic_arity` 配合。`binders := [(1, 2)]` 表示第 1 个语义参数至少含两层连续 lambda；`@1`、`@@1` 分别取相应 binder，`@@@1` 取后续部分。含 `@` 的规则需要一条无 binder 条件的回退样式。多个同名 style 按声明顺序尝试。

样式的 `isolated_arguments := [0, 1]` 表示模板已将对应显示参数独立分组（索引从 0 开始），渲染时跳过这些位置由优先级或结合方向产生的自动括号。例如 `\frac{#0}{#1}` 的分子和分母、`{#0}^{#1}` 的指数；其他参数仍按原优先级规则加括号。

ProofScript 基础配置位于 `ProofScript/Lean2TeX/Basic.lean`，Mathlib 的 `Real` / `Set` 配置位于 `ProofScript/Mathlib/Scripts.lean`。下游模块要在导出证明前导入所需配置；本模块内新增的配置供后续导入该模块的证明使用。

## Python 接口

```python
from Lean2TeX import load

renderer = load(export_root, proof_module)
tex = renderer.render(expr, language="en")

# 也可复用已解析的不可变配置，并为每个定理创建独立渲染器：
from Lean2TeX.configuration import ConfigurationIndex
from Lean2TeX.core import Expr2TeX

config = ConfigurationIndex(export_root).effective(proof_module)
renderer = Expr2TeX.from_config(config)
```

`renderer.convert(expr)` 返回 DisplayTree，`renderer.render_display(display)` 将其转成 TeX，`renderer.render_relation(expr)` 为 calc 链提供关系符号。每个渲染器拥有独立的变量分配和诊断状态。缺少宏配置时保留可见的 fallback 和 `L2T001` 诊断；错误或缺失的配置事件则阻止站点发布。

## 变量联动

公式使用 KaTeX `\htmlData` 携带语义引用：同一 fvar 按 `fvarId`，binder 与正文 bvar 按 `bindId` / `bindRef` 联动；独立表达式转换的 binder 身份互不相同。前端只在同一个 `.theorem-proof` 中高亮相同引用，binder 声明使用不同颜色。

构建诊断汇总位于 `.PS4HTML/build/<包>/<库>/lean2tex-report.json`。
