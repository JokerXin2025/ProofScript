# Info 命令：为页面配置展示信息

Info 命令用于设置定理名称、证明步骤文案和数学表达式排版。站点标题及作者等项目元数据由 PS4HTML 的 `ps4html-config.toml` 管理，参见[配置契约](PS4HTML-Config-Contract-zh.md)。Info 只影响展示，不修改 Lean 声明或证明。一般在目标声明或脚本规则**注册之后**书写配置：

```lean
import ProofScript

theorem add_self (n : Nat) : n + n = 2 * n := by omega
theorem_info add_self { names := [{ lang := zh, value := "自身相加" }], tags := [{ lang := zh, value := "自然数" }] }

decl_info infixl HAdd.hAdd "+" (mode := formula, precedence := 65)
```

完整页面使用 `lake build MyLibrary:ps4html` 构建。普通 `lake build` 和 IDE 默认不登记展示配置；命令仍解析字段和目标，因此书写错误也可能在普通构建中报出。修改源码后仅运行 `ps4html make --cache` 不会更新配置，必须重新构建页面。只在当前模块试验时，可在配置前写 `set_option pageBuild true`；它不会重新编译已按普通模式导入的模块。

## 按用途选择命令

| 想配置什么 | 命令 | 目标 |
| --- | --- | --- |
| 站点标题、作者等 | 根目录 `ps4html-config.toml` | PS4HTML 渲染；当前 package 的所有库共用 |
| 定理的展示名、标签 | `theorem_info 声明名 { ... }` | 已存在的 Lean 声明 |
| 证明步骤、策略的文案及配色 | `script_info 注册ID { ... }` | 已注册的脚本规则 |
| 表达式模板、符号、别名或变量名前缀 | `decl_info 声明名 { ... }` | 已存在的 Lean 声明 |

注:
1. 字段之间用逗号分隔
2. 与 Lean 关键字产生冲突时可用 `«...»` 转义.
3. 语言代码使用 `zh`, `en` 等内置语言类型 `Language` 构造子，不写成字符串.
4. 声明展示统一使用 `decl_info`，符号、wrapper、alias 和模板增删有相应简写。

## 站点项目元数据：`ps4html-config.toml`

PS4HTML 从 Lake 项目根目录读取可选 TOML 文件，不读取 Lean 的项目 Info 事件。所有库共用同一份站点元数据；声明和脚本 Info 的 imports 可见性不受影响。

```toml
[site]
title = "微积分笔记"
authors = ["Alice", "Bob"]
keywords = ["calculus", "Lean"]
description = "形式化课程笔记"
year = "2026"
license = "CC-BY-4.0"
base_url = "https://example.org/calculus/"

[render]
default_language = "en"
```

文件和字段都可省略；缺省标题使用 Lake package 名，缺省界面语言为英语。`base_url` 是整个 `.PS4HTML/build/` 的公开地址，须为合法 HTTP(S) 根 URL；可运行 `ps4html config check` 独立校验，无须构建 Lean。只修改 TOML 时重新渲染即可。

## 定理简写：`theorem_info`

为已声明的定理配置元信息, 一般在 `#page theorem`, `#page lemma` 等命令后立即使用, 命令本身不声明定理或创建定理组件.

```lean
theorem Nat.add_comm (m n : Nat) : m + n = n + m := by ring

theorem_info Nat.add_comm {
  names := [{ lang := zh, value := "自然数的加法交换律" },
    { lang := en, value := "Commutativity of addition" }],
  tags := [{ lang := zh, value := "自然数" }, { lang := zh, value := "加法" },
    { lang := zh, value := "交换律" }]
}
```

| 字段 | 类型 | 默认值 |
| --- | --- | --- |
| `names` | List InternationalName | `[]`；每种语言最多一个名称 |
| `tags` | List InternationalName | `[]`；每种语言允许多个标签 |

`theorem_info add_self {}` 也合法；字段块不可省略。该命令展开为在 `decl_info` 中添加 `kind := «theorem»`，因此只能作用于原生 theorem，可配置所有 `decl_info` 字段；显式再写 `kind` 会导致重复字段错误。标签列表再次赋值时整体替换。定理所属项目由**声明所在模块**决定，不能通过配置更改。

## 脚本：`script_info`

目标是 `script_macro` 或 `script_elab` 的**注册 ID**，不是脚本输入时的关键字。内置规则可以使用其注册 ID，例如 `«exact»`；要配置其它模块的规则，使用其完整 ID。

```lean
script_macro «finishDoc» "finish_doc " proof:term => `(tactic| exact $proof:term)

script_info «finishDoc» {
  templates := [
    { lang := zh, tag := "完成证明", content := "${proof}" },
    { lang := en, tag := "Finish", content := "${proof}" }
  ]
}
```

| 字段 | 类型 | 默认值 / 说明 |
| --- | --- | --- |
| `templates` | 脚本模板数组 | `[]`；再次赋值整体替换，语言不可重复 |
| `renderer` | 渲染器枚举 | `default`，表示由模板渲染 |
| `display` | Bool | `true`；`false` 隐藏整个步骤及其分支 |
| `color` | `ScriptColor` | 标签、边框、背景均为 `none` |
| `board` | `List (String × String)` | `[]`；普通步骤仪表盘下部的展示名与 recorder 字段名 |

普通模板的 `lang`、`tag`、`content` 都必须填写；`tag`、`content` 可以是空字符串。再次配置 `templates` 会**替换整个列表**。如需保留其它语言，可使用增删简写。例如：

```lean
script_info «exact» {
  templates := [{ lang := zh, tag := "直接得到", content := "由 ${value_before} 可得" }],
  color := { tag := some "#166a80", border := some "#9ac7d0" }
}
```

增删简写使用当前可见的完整列表，按语言识别模板；增加已有语言或删除不存在的语言会报错：

```lean
script_info templates «exact» + [{ lang := en, tag := "Exact", content := "${value_before}" }]
script_info templates «exact» - [en]
```

两种简写最终都写入完整的 `templates` 字段，因此互不依赖的模块分别修改同一列表仍会冲突。

`color` 也可写成 `(标签, 边框, 背景)` 三元组，例如 `(some "#166a80", none, none)`；颜色支持 `#RGB`、`#RGBA`、`#RRGGBB`、`#RRGGBBAA`。整个颜色对象在再次赋值时被替换，省略的分量恢复为 `none`。

### 普通步骤仪表盘：`board`

页面中点击普通 script 步骤的头部会展开仪表盘；再次点击、按 Enter 或空格可收起。左右栏分别显示「原状态」和「新状态」：上下文取自 recorder 的 `$context_before` / `$context_after`（局部声明名称到其**类型表达式引用**的 JSON 对象），目标取自 `$goal_before` / `$goal_after`。未记录上下文时不显示该侧上下文；目标缺失或为 `null` 时显示「✓目标已完成」。自动 recorder 已在目标录制前后同步录制上下文；手写 recorder 可使用 `record_context "键名"` 或 `record_context "键名" (goal := `标签)` 指定目标。没有剩余目标时上下文为空对象 `{}`。已有的表达式高亮、公式交互也适用于仪表盘。

下方信息由 `board` 指定，例如：

```lean
script_recorder snapshotRule => do
  record_goal "$goal_before"
  record_context "$context_before"
  record_param "evidence" h
  record_value "label" "captured"
  execute
  record_goal "$goal_after"
  record_context "$context_after"

script_info snapshotRule {
  board := [("使用的证据", "evidence"), ("记录标签", "label")]
}

script_info board snapshotRule + [("附加标签", "label")]
script_info board snapshotRule - [("记录标签", "label")]
```

元组第一项为原样展示的名称，第二项为 recorder 对象中的**字面键名**（`"foo.bar"` 不代表嵌套路径）。可以重复展示名和指定同一个字段；显示顺序就是列表顺序。重复配置 `board` 会整体替换，`board := []` 清空并隐藏下部区域。`script_info board ... +` 按顺序追加，`-` 按完整二元组逐项删除最早的一处；不存在的二元组会报错，两种简写都写回完整列表。指定字段不存在时显示「未记录」，字段值为 `null` 时显示 `—`。表达式引用通过现有表达式解析器展示，文本会转义。JSON 导出格式为 `"board": [{"name": "使用的证据", "value": "evidence"}, ...]`，保留顺序和重复名。完整示例见[录制 API](../README-zh.md)，字段和交互约定见[仪表盘协议](Proof-Step-Dashboard-Protocol-zh.md)。

`board` 可以配置在 strategy 或元数据的 `script_info` 上，但当前仅普通 script 的自动模板步骤启用仪表盘；`unknown`、`calc`、`infer`、`introducer` 等特殊步骤暂不支持。

### 模板中的 `${...}`

`${字段}`、`${对象.成员}`、`${数组.0.成员}` 读取的是脚本 **recorder 实际记录的值**，不是 Lean 局部变量，也不是 `script_info` 的附加字段。数组从 0 开始。比如 `${value_before}` 只有在相应规则确实记录该字段时才可用。修改 `script_info` 不会让 recorder 增加字段。

Lean 保存模板字符串；PS4HTML 在消费实际步骤时检查非空闭合占位符的字段路径，缺失路径会导致渲染错误。写模板前可参照内置脚本配置和[录制 API 示例](../README-zh.md)确定实际字段。

### 静态与动态策略模板

策略注册的模板带 `cases`。每个 case 都需要 `name`、`tag`、`title`，`name` 要与录制分支对应；模板中的 case 顺序就是展示顺序。

```lean
script_info «splitAnd» {
  templates := [{
    lang := zh, tag := "分别证明",
    introducer := { tag := "目标拆解", content := "证明合取的两部分" },
    cases := [
      { name := "left", tag := "第一部分", title := "左侧命题" },
      { name := "right", tag := "第二部分", title := "右侧命题" }
    ]
  }]
}
```

`introducer` 可放在整个策略或单个 case 上，包含必填的 `tag`、`content`。`inline := true` 仅允许一个 case，且该 case 的 `tag`、`title` 都必须为空。普通模板和策略模板不能混用到不相符的注册类型。

动态分支使用 `DynamicStrategyScriptTemplate`，不指定 `name` 或 `inline`，按 `$branches` 的录制顺序重复 `case := { tag, title, introducer? }`。顶层仍有 `tag` 和可选 `introducer`。各语言可以分别选用静态或动态模板：

```lean
script_info «splitAnd!» {
  templates := [{
    lang := zh, tag := "递归拆分合取",
    case := { tag := "子目标 ${index'}", title := "" }
  }]
}
```

动态分支字段中的 `${index}` 和 `${index'}` 分别从 0、1 开始，按实际分支顺序生成数字字面量展示节点，支持页面的数字记法切换；优先于同名 recorder 字段。顶层 `tag` / `introducer` 则照常从 recorder 读取字段，静态策略模板也不对序数作特殊处理。动态分支中的其他占位符读取策略步骤自行记录的字段，不会自动读取当前分支的 `name`。动态策略未配置时使用通用动态模板。

已有专用渲染器可用 `renderer := «calc»`、`«infer»`、`«svg»`、`«remark»`、`«admit»` 指定；`svg` 读取 `metadata`、SVG 字符串 `code` 和可选的 `source := { lang, code }`，其余渲染器所需的数据也须由对应 recorder 输出。未单独配置的普通规则会获得默认的中文空正文模板；显式新建且 `display := true` 的 `renderer := «default»` 配置须提供模板；`display := false` 时可以没有模板。`admit` 即使理由为空也显示标注。

## 声明排版：`decl_info`

concept、relation、operator 共用模板选择和渲染，kind 用于分类。wrapper 显示一个原始参数，alias 转发到另一个声明，二者不使用自身模板。`import ProofScript` 提供命令，不安装数学展示预设；可在页面或自行维护的配置模块中明确配置。

```lean
decl_info Nat {
  names := [{ lang := zh, value := "自然数" }, { lang := en, value := "Natural numbers" }], var_name := "n",
  templates := [{ label := "formula", content := template%:100 ${ "\\mathbb{N}" }$ }]
}
def interval (a b : Nat) : Nat × Nat := (a, b)
decl_info interval {
  templates := [
    { label := "pair", content := template%:100 ${ "(" arg(0) "," arg(1) ")" }$ },
    { label := "description", lang := zh, content := template% { "从" arg(0) "到" $ arg(1) $ "的区间" } },
    { label := "description", lang := en, content := template% { "the interval from " arg(0) " to " arg(1) } }
  ],
  default_template := "pair"
}
```

六种 kind 是 `concept`（默认）、`relation`、`operator`、`wrapper`、`«alias»`、`«theorem»`。最后一种只可用于原生 theorem；`#page lemma` 的页面身份仍由证明事实确定。

| 根字段 | 默认值 / 说明 |
| --- | --- |
| `names` | `[]`，有序的 `{ lang, value }` 列表；每种语言（包括未指定语言）最多一个名称 |
| `tags` | `[]`，有序的 `{ lang, value }` 列表；同语言允许多个或重复标签，整字段替换，暂不提供标签 UI |
| `var_name` | `""`，匿名变量命名前缀 |
| `kind` | `concept` |
| `templates` | `[]`，赋值时替换完整列表 |
| `default_template` | `none`；固化时取最终列表首项 label，空列表保持 none |
| `wrapper_index` | `none`；wrapper 必须填写有效的原始参数索引 |
| `alias_target` | `none`；alias 必须填写已存在的目标声明，目标可未配置 |
| `calc_symbol` | `none`；calc 中的非空纯文本连接符，缺省按语言选择 names |
| `parameter_template` | `none`，定理参数的文字描述 |
| `extra` | 附加信息，按键合并；未知根字段也存入这里 |

普通常量在完整应用且有可用模板时使用模板。原生参数数量包含隐式、严格隐式及实例参数，只数声明类型最外层连续的函数绑定，不展开返回类型的别名。例如 `Set.Ioo a b : Set α` 的显式参数只有两个端点，不会因 `Set α` 可展开为 `α → Prop` 而多算一个元素参数。缺参、多参时回退普通应用，保留全部参数，不能提前套用模板。原生零参数常量可使用零参数模板。裸函数常量和普通应用回退的头部按当前语言选择 names。

`InternationalName` 的 `lang` 可以省略（等同 `none`，语言无关），`value` 必须非空。名称选择依次尝试当前语言、无语言、英语，仍无匹配时回退 Lean 名称。原生 theorem/lemma 的 Lean 回退名称为末尾分量，普通声明为完整名称；Lean 声明身份始终不变。当前站点只提供中英文切换。`tags` 目前仅保存和导出，不用于界面展示。`names`、`tags` 根字段整体替换；可以用以下命令编辑当前可见列表：

```lean
decl_info names Nat + [{ lang := en, value := "Natural numbers" }]
decl_info names Nat - [en]
decl_info tags Nat + [{ lang := zh, value := "算术" }]
decl_info tags Nat - [{ lang := zh, value := "算术" }]
```

`names -` 按语言删除；`tags -` 按 `(lang, value)` 删除一个匹配项。原生 theorem/lemma 不使用通用模板，直接按语言选择声明名称。证明类型的普通 def 仍是普通常量。展示读取证明所属模块的最终冻结视图，下游模块的更新不改变已导出的上游内容。旧 `name` 字段和旧导出格式须迁移并重新执行 Lake 页面导出；仅重新渲染缓存不会转换格式。

### 模板字段及选择

每项必须填写非空、可打印 ASCII 的 label 和非空 content。身份由 `(label, lang)` 唯一确定，lang 可为 none、zh、en 等语言构造子。所有普通 label 均允许无语言版本，formula 只是普通名称，也可以带语言。

| 模板字段 | 默认值 / 作用 |
| --- | --- |
| `label`、`content` | 必填且非空 |
| `lang` | `none` |
| 模式 | `template% { ... }` 为文本；`template% ${ ... }$` 为公式 |
| 插入分组 | 使用 `arg!`、`binder!`、`body!` 对本次插入禁用自动括号 |
| 参数编号 | 默认按显式参数；头部添加 `raw` 则按所有原始参数编号 |
| 优先级 | `template%:70` 指定；省略时固化为 `60`，有效范围 0–100 |

`content` 必须是 `template% { ... }` 或 `template% ${ ... }$` 专属字面量，语法定义在 `ProofScript/Info/Template.lean`。头部顺序是 `template%`、可选 `:<num>`、可选 `raw`，例如 `template%:70 raw ${ arg(0) }$`。precedence 和 auto_arity 属于 TemplateContent，不再接受模板对象中的同名字段；isolated_args 已移除。

字符串片段按原样输出；字符串外的空格和换行只用于源码排版。内部 `$ ... $` 是非嵌套的模式切换片段：文本模板中切为公式，公式模板中切为文本。每个开启符都必须有关闭符；非配对符号由语法解析器拒绝。切换片段不能为空。目前字符串片段不接受美元符号，以免与下游内联公式定界符混淆。

`arg(N)` 按每条模板自己的编号方式取参数，可以跳过或重复，但不能超过声明原生参数范围。`arg!(N)` 表示模板已处理该次插入的分组，例如分式的分子、分母和已用花括号包围的指数；同一参数的其它引用不受影响。即使父子优先级均为 100，带 `!` 的插入也不会自动添加括号，但仍进行模式转换。字符串中的 `#0`、`@0` 不再有占位符含义。

| 选择器 | 含义 |
| --- | --- |
| `arg(0)`、`arg(1)` | 本模板的第 0、1 个参数 |
| `binder(0, 1)` | 参数 0 的第一层 lambda 绑定变量 |
| `binder(0, 2)` | 参数 0 的第二层 lambda 绑定变量，要求至少两层 |
| `body(0, 0)` | 参数 0 的完整表达式 |
| `body(0, 2)` | 去除前两层 lambda 后的剩余正文（可仍是 lambda） |

`binder(m,n)` 的层号从 1 开始，`body(m,n)` 的深度从 0 开始；两者都不受独立字段限制。每个参数的最少连续 lambda 层数由该参数所有 binder/body 选择器的最大深度决定。`body(m,0)` 不要求 lambda。不要求无条件保底模板，全部不适用时回退普通应用。旧字符串模板不再接受；`parameter_template` 的 `#self/#type/#N` 是独立协议，不受此次声明模板 DSL 迁移影响。

Lean 在读取配置时直接构建结构化片段，固化时生成 `argument_indices` 与 `instructions`，不再扫描模板字符串。导出 JSON 仍包含顶层 `mode`、`precedence`、`auto_arity` 和供检查的 `content` 字符串。选择器指令携带布尔 `max_precedence`；`body(m,n)` 导出独立的 `body` 指令和 `depth: n`；模式切换导出为 `{kind: "mode_switch", mode: "text"或"formula", instructions: [...]}`，内部不能再含模式切换。Python 与浏览器执行相同指令；content 不参与语义解析。

```lean
decl_info List.map { templates := [
  { label := "function", content := template%:90 ${ "\\operatorname{map}(" arg(0) "," arg(1) ")" }$ },
  { label := "binder", lang := en, content := template%:90 ${ "[" binder(0, 1) " \\mapsto " body(0, 1) "](" arg(1) ")" }$ }
] }
```

选择顺序为「用户选择的 label → 固化的 default_template → 列表中的其余 label → 普通展示」。每个 label 按「当前语言 → 无语言 → 英语」尝试，并检查该版本自己的 binder 条件。默认 label 不存在、语言不可用或结构不匹配均静默回退。alias 和目标分别保存用户选择；内置 label 在菜单显示友好名称。

### 符号简写及模板增删

```lean
decl_info relation Eq "="
decl_info relation LE.le "\\le" (mode := formula)
decl_info LE.le { calc_symbol := "≤" }

decl_info prefix Neg.neg "-" (mode := formula, precedence := 75)
decl_info infixl HAdd.hAdd "+" (mode := formula, precedence := 65)
decl_info postfix Nat.factorial "!" (mode := formula, precedence := 80)

decl_info templates Eq + [
  { label := "call", content := template%:90 ${ "\\operatorname{Eq}(" arg(0) "," arg(1) ")" }$ }
]
decl_info templates Eq - [("call", none)]
```

六种符号简写中，relation 设置 kind 为 relation；prefix、postfix、infix、infixl、infixr 设置 kind 为 operator，分别生成 `$relation`、`$prefix`、`$postfix`、`$infix`、`$infixl`、`$infixr` 模板（lang 为 none）并放在列表首位。同身份旧模板先移除，其余项保持顺序，不修改已有显式 default_template。简写默认 **formula 模式**；需要文本模式时可显式填写 `mode := text`。relation 固定使用优先级 50，并原样覆盖 calc_symbol；其它简写不修改 calc_symbol。选项字段顺序任意，重复或未知字段报错。

prefix/postfix 简写要求恰有一个显式参数，relation/infix/infixl/infixr 要求恰有两个。infix/infixl/infixr 的符号可以是空字符串（例如用于省略乘号）；prefix/postfix/relation 仍要求非空。手写的五个保留前中后缀模板在固化时也检查布局：操作数各出现一次，位置符合 label，不得添加其它包围结构或使用 binder 选择器；中缀的符号片段可以为空，允许 binder 条件。

整个 `$` label 空间保留，当前只有上述六个名称合法且 lang 必须为 none。`decl_info templates ... +` / `-` 禁止操作保留 label。它们先读取唯一确定的完整列表，再一次写回：添加到末尾，已有身份、批内重复、删除不存在的身份均报错且不留下部分写入。`+ []` / `- []` 也记录一次完整 templates 写入。

普通模板不能通过加号替换；重写列表使用根 `templates := [...]`。列表有导入冲突时，读取式增删及符号简写均报错，须显式赋值完整根字段解决。

### 优先级与结合性

所有普通模板统一比较优先级。只有同一原始常量、同一实际 `(label, lang)` 的 `$infixl`、`$infixr`，才分别按左结合或右结合规则省略同级括号；`$infix` 及其它同级组合保留括号。alias 与目标仍是不同常量。结合性由模板标签决定，不再接受 associativity 字段。

普通 `#0` 模板同样遵守自身优先级，只有 wrapper 透明继承子表达式的属性。跨文本/公式也检查优先级，括号加在公式一侧；两个文本之间用文本括号。原子模板可显式取 100，函数调用可取 90，避免默认 60 产生额外括号。

### wrapper 与 alias

```lean
decl_info wrapper OfNat.ofNat 1
decl_info wrapper Nat.cast 2

-- MyEqual 须已声明；目标可以没有显式配置。
decl_info relation Eq "=" (mode := formula)
decl_info alias MyEqual → Eq
-- 也接受 ASCII 箭头：
decl_info alias MyEqual -> Eq
```

wrapper 索引从 0 开始，包含隐式参数，且要求完整应用。alias 不展开 Lean 定义，可以指向未配置声明，不检查两侧原生参数布局，但拒绝目标不存在和别名环。原生 theorem 只按名称渲染，其不活跃的 alias 配置不发生转发。

wrapper/alias 活动字段缺失或无效时固化报错。非活动的 wrapper_index、alias_target 可保留但忽略；自身 templates 不展示，但仍做基本合法性检查。

### calc 连接符

calc_symbol 只在 calc 块使用，是非空纯文本，绝不作为 TeX 或模板解析。relation 简写传入 `"\\le"` 时，calc 也按字面显示 `\le`；想显示 ≤，另写 `decl_info LE.le { calc_symbol := "≤" }`。

所有 kind 都可配置 calc_symbol。alias 使用最终目标的 calc_symbol，缺省使用该目标的 name，忽略 alias 自身这两个字段。模板删除、切换或语言变化均不影响连接符；它保留原始常量的悬浮及链接身份。局部关系表达式回退普通展示，infer 箭头仍以公式渲染。

### 变量名称及参数描述

```lean
decl_info Nat {
  var_name := "n",
  parameter_template := some "$#self\\in\\mathbb{N}$"
}
```

var_name 配置类型对应的匿名变量前缀，规则见 [Lean2TeX](../tools/ps4html/Lean2TeX/README.md)。parameter_template 中 `#self` 是参数本身，`#type` 是完整类型，`#N` 始终按类型声明的显式参数编号，与模板的 auto_arity 无关。不支持 `@` 和 `#*`。

## 更新、冲突、重置和预览

同一目标可多次配置，省略根字段保留旧值，写出的普通根字段整体替换。`decl_info.templates` 和 `script_info.templates` 均没有跨模块的单项合并机制。互不支配的独立模块写入同一普通根字段，即使值相同也报冲突；同一事件重复导入会去重，同模块后写和依赖关系中的后写可覆盖先写。

extra 按键合并。

```lean
reset decl_info Nat
reset script_info «exact»

#preview decl_info Nat
#preview theorem_info add_self
#preview script_info «exact»
```

`reset decl_info` 重置目标的全部展示字段；预览命令也读取同一份配置。重置后的 kind 默认是 `concept`。预览消费当前可见配置并做固化检查，完整导出则以模块最终状态为准。通用命令和简写均支持字段补全、目标跳转和悬浮。

模块、Info、页面交互和录制数据不携带版本字段。旧命令和旧嵌套字段仍需迁移源码并重新导出；格式变化后应清理旧 `.ProofScript` 产物并运行 Lake 导出目标。

可运行示例见[经典数学公式](../Test/ClassicalFormula.lean)、[表达式交互](../Test/PageTheoremExpressionInteractions.lean)、[边界示例](../Test/PageTheoremExpressionBoundaries.lean)和[内置脚本配置](../ProofScript/Builtin/Scripts.lean)。接口见 [Info 源码](../ProofScript/Info/)。
