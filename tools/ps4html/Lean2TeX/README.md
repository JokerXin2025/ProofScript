# Lean2TeX

PS4HTML 消费录制的原生表达式及模块冻结配置，将表达式转换为 DisplayTree 并渲染为 TeX。配置位于 `.ProofScript/info/<模块路径>.json`，渲染范围取自 `manifests/targets/`；`make --cache` 只读取已完成产物。

生产入口通过 `validate_document` / `ExpressionResolver.resolve_at` 取得根清单声明的 occurrence。mdata 透明，ProofScript.* 标量元数据由外层优先。应用头及参数顺序取自原生结构，Python 不展开声明、不回放 Info 事件、不解析模板 content。

## 在 Lean 文件中配置

`import ProofScript` 提供配置命令，不安装数学展示预设。目标必须是已有声明；普通根字段只更新显式写出的项，templates 整体替换，extra 按键合并。独立模块对同一普通根字段写入相同值也算冲突。完整语法见 [Info 命令说明](../../../docs/Info-Commands-zh.md)。

```lean
decl_info relation Eq "=" (mode := formula)
decl_info wrapper OfNat.ofNat 1
decl_info infixl HAdd.hAdd "+" (mode := formula, precedence := 65)
decl_info Real { var_name := "x", templates := [
  { label := "formula", content := template%:100 ${ "\\mathbb{R}" }$ }
] }
decl_info Exists { default_template := "text", templates := [
  { label := "function",
    content := template%:90 raw ${ "\\operatorname{Exists}(" arg(0) "," arg(1) ")" }$ },
  { label := "text", lang := zh,
    content := template%:20 raw { "存在 " $ binder(1, 1) "\\in " arg(0) $ " 使得" body(1, 1) } },
  { label := "text", lang := en,
    content := template%:20 raw { "there exists " $ binder(1, 1) "\\in " arg(0) $ " such that " body(1, 1) } }
] }
```

例子中的 Real 需导入 Mathlib。Exists 的类型参数属于原始槽 0，谓词属于槽 1；auto_arity 为 false 的模板可读取两者。每条模板独立选择显式或原始参数编号，允许稀疏、重复和重排选择器。`binder(1, 1)` 取第一层变量，`body(1, 1)` 取去除第一层 lambda 后的正文，`body(1, 0)` 保留整个参数。每个参数所需的最少连续 lambda 层数由选择器的最大深度决定。参数数量必须等于声明的完整原生 arity；缺参、多参都普通展示。零参数常量可套用模板，定理仍走 theorem_info 通路。

concept、relation、prefix、infix、postfix 共用同一模板模型。wrapper_index 使用包含隐式参数的原始索引，只有 wrapper 透明；alias_target 转发到已经配置且原生 binder 布局兼容的目标链。两类声明自身模板忽略。

模板身份为 `(label, lang)`。普通 label 可无语言，formula 无特殊规则；label 查找按当前语言、none、英语回退。label 选择按用户请求、冻结默认、列表其它项、普通展示回退。default_template 为 none 时，Lean 取最终列表首项 label；悬空默认及 binder 不匹配由渲染器静默回退。

整个 `$` label 名称空间保留；四种符号简写置顶 `$relation/$prefix/$infix/$postfix`，语言始终 none，不改变显式默认。简写默认 formula，可用 `mode := text` 修改；手写模板使用 `template% { ... }` 表示文本、`template% ${ ... }$` 表示公式。优先级用 `template%:70`，原始参数编号用 `template% raw`，组合时优先级在 raw 前面。不再接受独立的 mode、precedence、auto_arity、isolated_args 字段。

所有模板都有 precedence（冻结默认 60）。`$infixl` 和 `$infixr` 分别表示左结合与右结合，`$infix` 不省略同级括号；同优先级仅同一原始常量和同一实际模板可按标签省括号，其它组合保留。跨 text/formula 仍比较优先级，括号位于公式侧。`arg!`、`binder!`、`body!` 只对当前插入跳过自动括号，即使父子优先级均为 100；它们不改变子表达式的真实优先级。内部 `$ ... $` 是非嵌套的双向模式切换，按片段整体转换。

## 冻结数据与浏览器重绘

Lean 为根记录导出 arity、binder_infos、parameter_argument_indices，为每条模板导出 argument_indices 和 instructions。指令为 literal（content）、argument（index/mode/max_precedence）、binder（index/depth/mode/max_precedence）和 mode_switch（mode/instructions）。模式切换的子指令不可再含 mode_switch；选择器的 mode 必须匹配所在片段。index 是模板参数编号，经该模板映射读取 native 槽。输入配置不能填写这些派生字段。

DisplayTree 保留稳定的原始参数槽，所有候选模板复用同一批节点和变量身份。Python 和浏览器执行相同指令、语言/结构回退与括号规则，切换 auto_arity 不重分配变量。每个 render root 保存原始常量身份、候选模板、初始选择、冻结名称和实际模板身份；alias 与目标独立选择。内置 label 的菜单标题本地化，kind 分类细分 prefix/infix/postfix。

calc 使用独立纯文本入口，从 alias 最终目标读取 calc_symbol，缺省为该目标 name。删除模板、改变 mode 或用户选择均不改变它。HTML、美元符号及 TeX 命令均按字面转义显示，保留原始常量的交互身份但不加入模板重绘；局部关系走普通表达式回退，infer 保持公式箭头。

模块在编译完成后固化本模块及 imports 中的最终可见配置；后置更新也生效，下游不会改变已导出的上游模块。旧嵌套字段和旧符号类别没有兼容通路。旧输出目录移走后重新运行 Lake 页面目标。

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

每个模块从 `.ProofScript/info/<模块路径>.json` 加载冻结配置。`renderer.convert(expr)` 返回 DisplayTree，`renderer.render_display(display)` 排版已有树。`renderer.render_relation(expr)` 返回 calc 的字面文本，或对非常量关系返回 None，调用方使用普通表达式渲染；文本调用方负责 HTML 转义并排除公式解释。`ProofEngine.render_relation` 已完成这些处理。每个渲染器拥有独立的变量分配和诊断状态；无可用模板时静默回退，缺失模块 Info 则阻止发布。

自定义自由变量名称应在捕获时写入该 occurrence 的原生 `MData` 键 `ProofScript.userName`；绑定变量名称取自所属的 `lam`、`forall` 或 `let`。匿名变量按 `ProofScript.type` 选择前缀：`decl:` 查询冻结的 `decl_info.var_name`，为空时取最后一个声明名分量的首字母；`proof/sort:Prop/sort:Type/function/unknown` 分别使用 `h/P/T/f/v`。自定义原样 recorder 缺少类型注解时使用 `v`。调用者应传入包含相应 binder 的表达式根。表达式类型统一使用 `PS4HTML.schema.Expression`。格式变化后须运行 `lake build <Library>:ps4html` 重新构建录制产物。

自动名称按前缀从 `1` 连续编号，同一 fvar ID 复用生成结果，退出局部作用域不回收编号。用户名称不改名，也不占用编号。`DisplayNode.generated` 控制 `\textcolor{gray}{...}`，bvar 继承 binder 的名称和标记；元变量固定显示灰色 `?`。`var_name` 按数学名称排版，不参与模板占位符替换。变量也不会匹配同名声明宏。

`renderer.render(expr)` 在转换或排版异常时恢复计数和缓存；单独 `convert(expr)` 在转换失败时回滚，成功后提交分配。`render_display` 只排版已有节点，不修改分配状态。命名前缀只使用 definition 记录，不再有独立的变量配置对象或名字池。

## 变量联动

公式使用 KaTeX `\htmlData` 携带语义引用：同一 fvar 按 `fvarId`，binder 与正文 bvar 按 `bindId` / `bindRef` 联动；独立表达式转换的 binder 身份互不相同。前端只在同一个 `.theorem-proof` 中高亮相同引用，binder 声明使用不同背景。自动变量携带 `data-l2t-generated` 标记，悬停时文字保持灰色。

脚本中的 `let x := value` 或 `let x : Type := value` 在定义发生时显式记录 `name`、`type`、`value`，由普通步骤模板展示。后续变量出现不复制这些字段，也不生成声明类型或定义值的悬停提示。原生表达式内部的 `letE` 仍按其结构渲染。

构建诊断汇总位于 `.PS4HTML/build/<库>/lean2tex-report.json`。
