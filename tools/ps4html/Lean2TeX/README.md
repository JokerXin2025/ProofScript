# Lean2TeX

PS4HTML 使用 ProofScript 导出的 ExprJSON 和 Lean-owned 配置，将表达式转换为 DisplayTree 并渲染为 TeX。Lean 按模块与消费边界完成合并，配置保存在 `.ProofScript/info/snapshots/`，产物清单 `info/index.json` 选择具体快照。Python 不重放配置事件。`make --cache` 使用隔离的 `.PS4HTML/inputs/<包>/<库>/.ProofScript/` 完成版本。

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

`alias := some OtherDeclaration` 转发到已有声明的配置，`unwrap := some N` 选择从零开始的**原始应用参数**（包括隐式参数）。`alias`、`unwrap` 不可同时有效；省略字段表示沿用已有值，`none` 表示清除，`reset` 恢复默认值。提供 `calc_symbol` 而省略 `styles` 时，Lean 在消费时生成优先级 50、无结合方向的二元中缀样式。显式 `styles` 以整个有序列表替换；`phrase_info.template` 按语言合并。若在两个互不导入的模块中对同一配置字段赋值，Lean 在消费时报告冲突。

`#N` 引用筛选后的第 N 个语义子表达式；`#*` 与 `dynamic_arity` 配合。`binders := [(1, 2)]` 表示第 1 个语义参数至少含两层连续 lambda；`@1`、`@@1` 分别取相应 binder，`@@@1` 取后续部分。含 `@` 的规则需要一条无 binder 条件的回退样式。多个同名 style 按声明顺序尝试。

样式的 `isolated_arguments := [0, 1]` 表示模板已将对应显示参数独立分组（索引从 0 开始），渲染时跳过这些位置由优先级或结合方向产生的自动括号。例如 `\frac{#0}{#1}` 的分子和分母、`{#0}^{#1}` 的指数；其他参数仍按原优先级规则加括号。

ProofScript 基础配置位于 `ProofScript/Defaults/Lean2TeX.lean`，Mathlib 的 `Real` / `Set` 配置位于 `ProofScript/Mathlib/Info.lean`。`import ProofScript` 加载完整默认展示；只需表达式默认配置时导入 `ProofScript.Defaults.Lean2TeX`。每份证明和页面组件使用创建时捕获的配置边界：上游模块提供全部最终配置，本模块只读取该内容之前提交的配置。独立 proof 使用相同规则；`page_end` 只负责页面输出，不改变配置作用范围。未知顶层字段保存为 `extra`，已知字段类型错误会报错。

## Python 接口

```python
from Lean2TeX import load

renderer = load(export_root, proof_module, snapshot_id=artifact["snapshotId"])
tex = renderer.render(expr, language="en")

# 也可复用已解析的配置，并为每个定理创建独立渲染器：
from PS4HTML.info import InfoBundle
from Lean2TeX.core import Expr2TeX

config = InfoBundle(export_root).configuration(proof_module, snapshot_id=artifact["snapshotId"])
renderer = Expr2TeX.from_config(config)
```

模块所有产物消费同一个快照时可省略 `snapshot_id`，存在多个视图或没有消费快照时必须选择产物的 snapshotId。
`renderer.convert(expr)` 返回 DisplayTree，`renderer.render_display(display)` 将其转成 TeX，`renderer.render_relation(expr)` 为 calc 链提供关系符号。每个渲染器拥有独立的变量分配和诊断状态。缺少宏配置时保留可见的 fallback 和 `L2T001` 诊断；错误或缺失的完成快照阻止站点发布。

## 变量联动

公式使用 KaTeX `\htmlData` 携带语义引用：同一 fvar 按 `fvarId`，binder 与正文 bvar 按 `bindId` / `bindRef` 联动；独立表达式转换的 binder 身份互不相同。前端只在同一个 `.theorem-proof` 中高亮相同引用，binder 声明使用不同颜色。

构建诊断汇总位于 `.PS4HTML/build/<包>/<库>/lean2tex-report.json`。
