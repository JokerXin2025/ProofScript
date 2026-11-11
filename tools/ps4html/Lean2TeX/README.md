# Lean2TeX

PS4HTML 使用录制协议 `0.4.0` 的原生表达式与 Lean 固化的配置，将表达式转换为 DisplayTree 并渲染为 TeX。模块导出协议为 `14.0.0`；配置保存在 `.ProofScript/info/<模块路径>.json`，目标清单从 `.ProofScript/manifests/targets/` 选择模块。Python 不回放配置事件。`make --cache` 读取已完成的库目标导出。

生产入口通过 `validate_document` / `ExpressionResolver.resolve_at` 取得根清单声明的表达式 occurrence。`mdata` 是透明结构包装；名称和命名类型描述取自其中的 `ProofScript.*` 标量键，嵌套同名键由外层优先。应用头和参数顺序从原生结构得到，参数筛选只消费 Lean 配置快照导出的数字索引。

## 在 Lean 文件中配置

`decl_info` 的目标必须是已经存在的 Lean 声明；每个命令只更新写出的字段。以下例子应放在导入目标声明之后：

```lean
relation_info Eq { symbol := "=" }
wrapper_info OfNat.ofNat { index := some 1 }
operator_info HAdd.hAdd { symbol := "+", fixity := «infix», precedence := 65, associativity := left }
decl_info Real { var_name := "x", concept_info := { templates := [
  { label := "formula", content := "\\mathbb{R}" }
] } }
decl_info Exists { concept_info := { default := "text", auto_arity := false, templates := [
  { label := "formula", content := "\\exists\\ #1" },
  { label := "text", lang := some zh, mode := text,
    content := "存在 $@1\\in #0$ 使得@@1",
    binders := [(1, 1)] },
  { label := "text", lang := some en, mode := text,
    content := "there exists $@1\\in #0$ such that @@1",
    binders := [(1, 1)] }
] } }
```

`Exists` 使用 `concept` 模板渲染：`#0` 引用类型、`@1` 引用谓词 lambda 的变量、`@@1` 引用正文；`binders` 限定文本模板只匹配 lambda。依赖型 `forall` 的中英文短语由 PS4HTML 内置。

`kind` 有 `concept`（默认）、`wrapper`、`relation`、`operator`、`«alias»`。`concept_info` 独占 `auto_arity/templates/default`；`operator_info` 使用 `symbol/fixity/precedence/associativity` 自动渲染前缀、后缀或中缀，`relation_info.symbol` 自动渲染二元中缀。运算符和关系固定选择声明的显式参数；复杂排版使用 `concept`。变量命名独立生效。

`kind := «alias»` 配合 `alias_info := { target := some OtherDeclaration }` 转发到已有声明的配置；`kind := wrapper` 配合 `wrapper_info := { index := some N }` 选择从零开始的**原始应用参数**（包括隐式参数）。省略字段表示沿用已有值；`reset decl_info 声明名` 将配置恢复默认值。`concept_info.templates` 整体替换。互不导入的模块对同一配置字段赋值时，Lean 在消费时报告冲突。

`templates` 中每项用非空 ASCII `label` 标识，非 `formula` 项必须指定语言构造子（如 `lang := zh`、`lang := en`）或 `Language.custom`；`formula` 不指定语言。`default` 必须指向 `formula` 或含英文模版的 label。每组 `label + lang` 唯一。`#N` 在 `auto_arity := true` 时引用自动选择后的第 N 个语义子表达式，在 `auto_arity := false` 时引用完整原始应用参数的第 N 项。`binders := [(1, 2)]` 表示第 1 个语义参数至少含两层连续 lambda；`@1`、`@@1` 分别取相应 binder，`@@@1` 取后续部分。动态 `#*` 模板不再支持。

`auto_arity := true` 在 Lean 冻结配置时沿常量声明的 `forallE` binder 计算可展示参数，不选取隐式、严格隐式和实例参数；`auto_arity := false` 使用完整原始应用参数。

`concept` 模板的 `isolated_arguments := [0, 1]` 表示内容已将对应显示参数独立分组（索引从 0 开始），例如 `\frac{#0}{#1}` 的分子和分母、`{#0}^{#1}` 的指数。符号运算符按优先级与结合方向自动加括号。

ProofScript 基础配置位于 `ProofScript/Builtin/Config.lean`；`import ProofScript` 加载默认展示。页面模块在编译完成后按 imports 及本模块的最终配置固化实际请求的 Info，因此后置的 `decl_info` 也生效；下游更新不会改变已导出的上游模块。未知顶层字段保存为 `extra`，已知字段类型错误会报错。

## Python 接口

```python
from Lean2TeX import load

renderer = load(export_root, proof_module)
tex = renderer.render(expr, language="en")

# 也可在每个定理开始前清空变量分配状态：
renderer.reset()

# 指定单个根对象的模版，或按对象身份设置整棵表达式：
from Lean2TeX import RenderTarget
tex = renderer.render(expr, language="en", label="formula")
tex = renderer.render(expr, language="en", selections={RenderTarget("constant", "Nat"): "mathbb"})
```

`expr` 由录制文档的表达式根清单取得，例如：

```python
from PS4HTML.schema import validate_document

resolver = validate_document(document)
expr = resolver.resolve_at(("proof", 0, "subject"))
tex = renderer.render(expr)
```

普通 JSON 中形似表达式或 `$ref` 的对象仍按数据处理。只有根清单声明的叶子及原生节点的结构引用会解析成 `Expression`；`mdata.data` 始终是不含图引用语义的标量对象。

默认表达式读取器补充 `ProofScript.userName` 和命名类型描述 `ProofScript.type`。所有标量元数据（包括自定义键）始终导出，没有启用开关。类型描述由 Lean 在有效上下文中分类，Python 只读取描述，不查询上下文或展开类型。

每个模块从 `.ProofScript/info/<模块路径>.json` 加载一份最终固化的配置；旧版 snapshotId 不再使用。`renderer.convert(expr)` 返回 DisplayTree，`renderer.render_display(display)` 将其转成 TeX，`renderer.render_relation(expr)` 为 calc 链提供关系符号。每个渲染器拥有独立的变量分配和诊断状态。缺少宏配置时保留可见的 fallback 和 `L2T001` 诊断；缺失的模块 Info 阻止站点发布。

自定义自由变量名称应在捕获时写入该 occurrence 的原生 `MData` 键 `ProofScript.userName`；绑定变量名称取自所属的 `lam`、`forall` 或 `let`。匿名变量按 `ProofScript.type` 选择前缀：`decl:` 查询冻结的 `decl_info.var_name`，为空时取最后一个声明名分量的首字母；`proof/sort:Prop/sort:Type/function/unknown` 分别使用 `h/P/T/f/v`。自定义原样 recorder 缺少类型注解时使用 `v`。调用者应传入包含相应 binder 的表达式根。表达式类型统一使用 `PS4HTML.schema.Expression`。旧录制产物须运行 `lake build <Library>:ps4html` 重新构建为 `0.4.0`。

自动名称按前缀从 `1` 连续编号，同一 fvar ID 复用生成结果，退出局部作用域不回收编号。用户名称不改名，也不占用编号。`DisplayNode.generated` 控制 `\textcolor{gray}{...}`，bvar 继承 binder 的名称和标记；元变量固定显示灰色 `?`。`var_name` 按数学名称排版，不参与模板占位符替换。变量也不会匹配同名声明宏。

`renderer.render(expr)` 在转换或排版异常时恢复计数和缓存；单独 `convert(expr)` 在转换失败时回滚，成功后提交分配。`render_display` 只排版已有节点，不修改分配状态。命名前缀只使用 definition 记录，不再有独立的变量配置对象或名字池。

## 变量联动

公式使用 KaTeX `\htmlData` 携带语义引用：同一 fvar 按 `fvarId`，binder 与正文 bvar 按 `bindId` / `bindRef` 联动；独立表达式转换的 binder 身份互不相同。前端只在同一个 `.theorem-proof` 中高亮相同引用，binder 声明使用不同背景。自动变量携带 `data-l2t-generated` 标记，悬停时文字保持灰色。

脚本中的 `let x := value` 或 `let x : Type := value` 在定义发生时显式记录 `name`、`type`、`value`，由普通步骤模板展示。后续变量出现不复制这些字段，也不生成声明类型或定义值的悬停提示。原生表达式内部的 `letE` 仍按其结构渲染。

构建诊断汇总位于 `.PS4HTML/build/<库>/lean2tex-report.json`。
