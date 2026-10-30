# Lean2TeX

PS4HTML 使用录制协议 `0.3.0` 的原生表达式与 Lean-owned 配置，将表达式转换为 DisplayTree 并渲染为 TeX。Lean 按所属模块及其传递导入闭包的最终 Info 完成合并，Info 协议为 `9.0.0`、manifest 版本为 `9`、snapshot payload 版本为 `7`，配置保存在 `.ProofScript/info/snapshots/`，产物清单 `info/index.json` 选择具体快照。Python 不重放配置事件。`make --cache` 使用隔离的 `.PS4HTML/inputs/<包>/<库>/.ProofScript/` 完成版本。

生产入口通过 `validate_document` / `ExpressionResolver.resolve_at` 取得根清单声明的表达式 occurrence。`mdata` 是透明结构包装；名称、命名类型描述和源码位置取自其中的 `ProofScript.*` 标量键，嵌套同名键由外层优先。来源只属于当前 occurrence，不继承给结构子项。应用头和参数顺序从原生结构得到，参数筛选只消费 Lean 配置快照导出的数字索引。

## 在 Lean 文件中配置

`def_info` 的目标必须是已经存在的 Lean 声明；每个命令只更新写出的字段。以下例子应放在导入目标声明之后：

```lean
def_info Eq { calc_symbol := some "=" }
def_info OfNat.ofNat { unwrap := some 1 }
def_info HAdd.hAdd { kind := operator, styles := [
  { name := "formula", template := "#0+#1", fixity := «infix», precedence := 65,
    associativity := left }
] }
def_info Real { var_name := "x" }
phrase_info "forall" { template := [
  { lang := "zh", content := "${body}对一切 $${binder}\\in ${type}$ 成立" },
  { lang := "en", content := "${body} holds for every $${binder}\\in ${type}$" }
] }
```

`alias := some OtherDeclaration` 转发到已有声明的配置，`unwrap := some N` 选择从零开始的**原始应用参数**（包括隐式参数）。`alias`、`unwrap` 不可同时有效；省略字段表示沿用已有值，`none` 表示清除，`reset` 恢复默认值。提供 `calc_symbol` 而省略 `styles` 时，渲染器直接执行优先级 50、无结合方向的二元中缀布局。显式 `styles` 以整个有序列表替换；`phrase_info.template` 按语言合并。若在两个互不导入的模块中对同一配置字段赋值，Lean 在消费时报告冲突。

`#N` 在 `auto_arity := true` 时引用自动选择后的第 N 个语义子表达式，在 `auto_arity := false` 时引用完整原始应用参数的第 N 项。`binders := [(1, 2)]` 表示第 1 个语义参数至少含两层连续 lambda；`@1`、`@@1` 分别取相应 binder，`@@@1` 取后续部分。含 `@` 的规则需要一条无 binder 条件的回退样式。多个同名 style 按声明顺序尝试。动态 `#*` 模板不再支持。

`auto_arity := true` 在 Lean 冻结配置时沿常量声明的 `forallE` binder 计算可展示参数，不选取隐式、严格隐式和实例参数；`auto_arity := false` 使用完整原始应用参数。

样式的 `isolated_arguments := [0, 1]` 表示模板已将对应显示参数独立分组（索引从 0 开始），渲染时跳过这些位置由优先级或结合方向产生的自动括号。例如 `\frac{#0}{#1}` 的分子和分母、`{#0}^{#1}` 的指数；其他参数仍按原优先级规则加括号。

ProofScript 基础配置位于 `ProofScript/Builtin/Config.lean`，Mathlib 的 `Real` / `Set` 配置位于 `ProofScript/Mathlib/Info.lean`。`import ProofScript` 加载完整默认展示；只需基础配置时导入 `ProofScript.Builtin.Config`。每份证明和页面组件使用所属模块及全部传递导入模块的最终配置，包含本模块较晚提交及 `#page end` 后提交的 Info；独立 proof 使用相同规则。下游覆盖只影响下游内容，不改变复用的上游证明快照。未知顶层字段保存为 `extra`，已知字段类型错误会报错。

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

`expr` 由录制文档的表达式根清单取得，例如：

```python
from PS4HTML.schema import validate_document

resolver = validate_document(document)
expr = resolver.resolve_at(("proof", 0, "subject"))
tex = renderer.render(expr)
```

普通 JSON 中形似表达式或 `$ref` 的对象仍按数据处理。只有根清单声明的叶子及原生节点的结构引用会解析成 `Expression`；`mdata.data` 始终是不含图引用语义的标量对象。

默认表达式读取器补充 `ProofScript.userName`、命名类型描述 `ProofScript.type` 和源码位置三个键 `ProofScript.sourceFile`、`ProofScript.sourceStart`、`ProofScript.sourceStop`；源码位置不可获得时不添加。所有标量元数据（包括自定义键）始终导出，没有启用开关。类型描述由 Lean 在有效上下文中分类，Python 只读取描述，不查询上下文或展开类型。

模块所有产物消费同一个快照时可省略 `snapshot_id`，存在多个视图或没有消费快照时必须选择产物的 snapshotId。
`renderer.convert(expr)` 返回 DisplayTree，`renderer.render_display(display)` 将其转成 TeX，`renderer.render_relation(expr)` 为 calc 链提供关系符号。每个渲染器拥有独立的变量分配和诊断状态。缺少宏配置时保留可见的 fallback 和 `L2T001` 诊断；错误或缺失的完成快照阻止站点发布。

自定义自由变量名称应在捕获时写入该 occurrence 的原生 `MData` 键 `ProofScript.userName`；绑定变量名称取自所属的 `lam`、`forall` 或 `let`。匿名变量按 `ProofScript.type` 选择前缀：`decl:` 查询冻结的 `def_info.var_name`，为空时取最后一个声明名分量的首字母；`proof/sort:Prop/sort:Type/function/unknown` 分别使用 `h/P/T/f/v`。自定义原样 recorder 缺少类型注解时使用 `v`。调用者应传入包含相应 binder 的表达式根。表达式类型统一使用 `PS4HTML.schema.Expression`。旧录制产物须运行 `lake build <Library>:ps4html` 重新构建为 `0.3.0`。

自动名称按前缀从 `1` 连续编号，同一 fvar ID 复用生成结果，退出局部作用域不回收编号。用户名称不改名，也不占用编号。`DisplayNode.generated` 控制 `\textcolor{gray}{...}`，bvar 继承 binder 的名称和标记；元变量固定显示灰色 `?`。`var_name` 按数学名称排版，不参与模板占位符替换。变量也不会匹配同名声明宏。

`renderer.render(expr)` 在转换或排版异常时恢复计数和缓存；单独 `convert(expr)` 在转换失败时回滚，成功后提交分配。`render_display` 只排版已有节点，不修改分配状态。命名前缀只使用 definition 记录，不再有独立的变量配置对象或名字池。

## 变量联动

公式使用 KaTeX `\htmlData` 携带语义引用：同一 fvar 按 `fvarId`，binder 与正文 bvar 按 `bindId` / `bindRef` 联动；独立表达式转换的 binder 身份互不相同。前端只在同一个 `.theorem-proof` 中高亮相同引用，binder 声明使用不同背景。自动变量携带 `data-l2t-generated` 标记，悬停时文字保持灰色。

脚本中的 `let x := value` 或 `let x : Type := value` 在定义发生时显式记录 `name`、`type`、`value`，由普通步骤模板展示。后续变量出现不复制这些字段，也不生成声明类型或定义值的悬停提示。原生表达式内部的 `letE` 仍按其结构渲染。

构建诊断汇总位于 `.PS4HTML/build/<包>/<库>/lean2tex-report.json`。
