# Info 命令：为页面配置展示信息

Info 命令用于设置项目标题、定理名称、证明步骤文案和数学表达式排版。它们只影响展示，不修改 Lean 声明或证明。一般在目标声明或脚本规则**注册之后**书写配置：

```lean
import ProofScript

project_info { title := "微积分笔记", authors := ["Alice"] }

theorem add_self (n : Nat) : n + n = 2 * n := by omega
theorem_info add_self { name := "自身相加", tags := ["自然数"] }

operator_info HAdd.hAdd {
  symbol := "+", fixity := «infix», precedence := 65, associativity := left
}
```

完整页面使用 `lake build MyLibrary:ps4html` 构建。普通 `lake build` 和 IDE 默认不登记展示配置；命令仍解析字段和目标，因此书写错误也可能在普通构建中报出。修改源码后仅运行 `ps4html make --cache` 不会更新配置，必须重新构建页面。只在当前模块试验时，可在配置前写 `set_option pageBuild true`；它不会重新编译已按普通模式导入的模块。

## 按用途选择命令

| 想配置什么 | 命令 | 目标 |
| --- | --- | --- |
| 项目标题、作者等 | `project_info { ... }` | 当前 Lake 库；沿 imports 可见并支持多次更新 |
| 定理的展示名、标签 | `theorem_info 声明名 { ... }` | 已存在的 Lean 声明 |
| 证明步骤、策略的文案及配色 | `script_info 注册ID { ... }` | 已注册的脚本规则 |
| 表达式模板、符号、别名或变量名前缀 | `decl_info 声明名 { ... }` | 已存在的 Lean 声明 |

注:
1. 字段之间用逗号分隔
2. 与 Lean 关键字产生冲突时可用 `«...»` 转义.
3. 语言代码使用 `zh`, `en` 等内置语言类型 `Language` 构造子，不写成字符串.
4. ProofScript 针对不同类别声明提供了专属 Info 配置命令, 详见下文.

## 项目：`project_info`

项目身份由 Lake 的包和库确定，无须把库名传给命令。可以在一个或多个模块中多次更新；当前模块只读取自身及 imports 中属于同一库的记录。独立上游对同一字段写入不同值时，固化会报告冲突。

```lean
project_info {
  title := "微积分笔记",
  authors := ["Alice", "Bob"],
  keywords := ["calculus", "Lean"],
  description := "形式化课程笔记",
  year := "2026",
  license := "CC BY 4.0",
  base_url := "https://example.org/calculus"
}
```

所有字段都可省略；`title`、`description`、`year`、`license`、`base_url` 默认为空字符串，`authors`、`keywords` 默认为空列表。完全没有登记时，页面标题使用 Lake 库名。`year` 和 `base_url` 只是文本，不会自动校验日期或网址。

## 定理：`theorem_info`

为已声明的定理配置元信息, 一般在 `#page theorem`, `#page lemma` 等命令后立即使用, 命令本身不声明定理或创建定理组件.

```lean
theorem Nat.add_comm (m n : Nat) : m + n = n + m := by ring

theorem_info Nat.add_comm {
  name := "自然数的加法交换律",
  tags := ["自然数", "加法", "交换律"]
}
```

| 字段 | 类型 | 默认值 |
| --- | --- | --- |
| `name` | String | `""`；展示时通常回退到声明短名 |
| `tags` | List String | `[]` |

`theorem_info add_self` 和 `theorem_info add_self {}` 也合法。标签列表再次赋值时整体替换。定理所属项目由**声明所在模块**决定，不能通过 `theorem_info` 更改。

## 脚本：`script_info`

目标是 `script_macro` 或 `script_elab` 的**注册 ID**，不是脚本输入时的关键字。内置规则可以使用其注册 ID，例如 `«exact»`；要配置其它模块的规则，使用其完整 ID。

```lean
script_macro «finishDoc» "finish_doc " proof:term => `(tactic| exact $proof:term)

script_info «finishDoc» {
  template := [
    { lang := zh, tag := "完成证明", content := "${proof}" },
    { lang := en, tag := "Finish", content := "${proof}" }
  ]
}
```

| 字段 | 类型 | 默认值 / 说明 |
| --- | --- | --- |
| `template` | 脚本模板数组 | `[]`；普通模板按语言合并 |
| `renderer` | 渲染器枚举 | `none`，表示由模板自动渲染 |
| `display` | Bool | `true`；`false` 隐藏整个步骤及其分支 |
| `color` | `ScriptColor` | 标签、边框、背景均为 `none` |
| `board` | `List (String × String)` | `[]`；普通步骤仪表盘下部的展示名与 recorder 字段名 |

普通模板的 `lang`、`tag`、`content` 都必须填写；`tag`、`content` 可以是空字符串。相同语言再次配置会**替换该语言的整条模板**，其它语言保留。例如：

```lean
script_info «exact» {
  template := [{ lang := zh, tag := "直接得到", content := "由 ${value_before} 可得" }],
  color := { tag := some "#166a80", border := some "#9ac7d0" }
}
```

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
```

元组第一项为原样展示的名称，第二项为 recorder 对象中的**字面键名**（`"foo.bar"` 不代表嵌套路径）。可以重复展示名和指定同一个字段；显示顺序就是列表顺序。重复配置 `board` 会整体替换，`board := []` 清空并隐藏下部区域。指定字段不存在时显示「未记录」，字段值为 `null` 时显示 `—`。表达式引用通过现有表达式解析器展示，文本会转义。JSON 导出格式为 `"board": [{"name": "使用的证据", "value": "evidence"}, ...]`，保留顺序和重复名。完整示例见[录制 API](../examples/recording/RecordingAPI.lean)，字段和交互约定见[仪表盘协议](Proof-Step-Dashboard-Protocol-zh.md)。

`board` 可以配置在 strategy 或元数据的 `script_info` 上，但当前仅普通 script 的自动模板步骤启用仪表盘；`unknown`、`calc`、`infer`、`introducer` 等特殊步骤暂不支持。

### 模板中的 `${...}`

`${字段}`、`${对象.成员}`、`${数组.0.成员}` 读取的是脚本 **recorder 实际记录的值**，不是 Lean 局部变量，也不是 `script_info` 的附加字段。数组从 0 开始。比如 `${value_before}` 只有在相应规则确实记录该字段时才可用。修改 `script_info` 不会让 recorder 增加字段。

Lean 保存模板字符串；PS4HTML 在消费实际步骤时检查非空闭合占位符的字段路径，缺失路径会导致渲染错误。写模板前可参照内置脚本配置和[录制 API 示例](../examples/recording/RecordingAPI.lean)确定实际字段。

### 策略模板与专用 renderer

策略注册的模板带 `cases`。每个 case 都需要 `name`、`tag`、`title`，`name` 要与录制分支对应；模板中的 case 顺序就是展示顺序。

```lean
script_info «splitAnd» {
  template := [{
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

已有专用渲染器可用 `renderer := «calc»`、`«infer»`、`«strategy»`、`«media»`、`«diagram»`、`«remark»`、`«admit»`、`«embed»`、`«unrecorded»` 指定；它们所需的数据仍须由对应 recorder 输出。未单独配置的普通规则会获得默认的中文空正文模板；显式新建 `renderer := none` 的配置则须提供模板。

## 声明排版：`decl_info` 与专用命令

先确定要表达的排版方式：

| 需要的效果 | 用哪个命令 |
| --- | --- |
| 自定义 TeX、多语言文案、参数重排、分式或 binder | `decl_info ... { concept_info := { ... } }` 或 `concept_info ...` |
| 前缀、后缀、中缀符号 | `operator_info ...` |
| 普通二元关系符号 | `relation_info ...` |
| 隐藏应用外壳，仅显示一个原始参数 | `wrapper_info ...` |
| 复用另一声明的展示规则 | `alias_info ...` |
| 配置常量展示名、匿名变量前缀或参数描述 | `decl_info ...` |

五种 `kind` 分别是 `concept`（默认）、`operator`、`relation`、`wrapper`、`«alias»`。专用命令会同时设置 `kind` 与对应的 `*_info` 对象。例如 `relation_info Eq { symbol := "=" }` 等价于 `decl_info Eq { kind := relation, relation_info := { symbol := "=" } }`。专用命令的字段**数量和顺序固定**，需要只更新部分字段时用 `decl_info`。

`decl_info.name` 是保留的字符串字段，用于显示裸常量和普通应用回退时的常量头；省略或重置时默认使用完整 Lean 声明名。例如 `decl_info Nat.succ { name := "后继" }`。这些 `const` 节点不使用常量模板；参数齐全且匹配规则的应用仍使用 `concept`、`operator` 或 `relation` 排版。原生 Lean 定理（含 lemma）的常量节点归为独立的“定理”类别，显示 `theorem_info.name`；未配置或名称为空时使用完整声明名。命题证明类型的普通 `def` 仍按常量处理。名称来自各证明的冻结 Info 快照。

### `concept`：需要模板的展示

```lean
def interval (a b : Nat) : Nat × Nat := (a, b)

decl_info interval { concept_info := {
  templates := [{ label := "formula", content := "(#0,#1)" }]
} }
```

`concept_info` 的字段如下；使用专用命令时须依次提供全部三个字段：

```lean
concept_info interval {
  auto_arity := true,
  templates := [{ label := "formula", content := "(#0,#1)" }],
  default := "formula"
}
```

| 字段 | 默认值 | 作用 |
| --- | --- | --- |
| `auto_arity` | `true` | 按声明签名只选显式参数；`false` 时 `#N` 对应实际应用的原始参数索引 |
| `templates` | `[]` | 展示模板；再次赋值时整体替换 |
| `default` | `"formula"` | 默认选择的模板标签 |

每条模板必须有 `label`（非空可打印 ASCII）和 `content`。`formula` 标签不写语言；其它标签必须写 `lang := zh`、`lang := en` 等语言构造子。同一 `label + lang` 组合不能重复，且最多有一条 `formula` 模板。`default` 必须指向已有的 `formula` 标签，或具有英语模板的标签；模板至少包含一条 `formula` 或英语模板。

模板还可指定 `mode := text`（默认 `formula`）、`binders := [(参数索引, lambda 层数)]` 和 `isolated_arguments := [参数索引]`。公式模板的 `content` 通常不带外围 `$`；文本模板内可以用 `$...$` 嵌入公式。`isolated_arguments` 表示模板已自行处理该参数的分组，不自动加括号。

| 占位符 | 含义 |
| --- | --- |
| `#0`、`#1` | 选中的第 0、1 个参数 |
| `@0` | 参数 0 的第一层 lambda 绑定变量 |
| `@@0` | `binders := [(0, 1)]` 时，去掉该层 lambda 后的正文 |

带 `@` 的模板须声明足够的 `binders` 层数，且同一模板组中还须有一条**不含 `@`** 的回退模板。默认 `auto_arity := true` 时，模板引用的参数编号须从 0 连续；`auto_arity := false` 时可以跳过隐藏的原始参数。动态 `#*` 不支持。

```lean
-- 函数参数是 lambda 时可选择 binder 样式；否则回退到 formula。
decl_info List.map { concept_info := { templates := [
  { label := "formula", content := "\\operatorname{map}(#0,#1)" },
  { label := "binder", lang := en,
    content := "\\operatorname{map}(@0\\mapsto @@0,#1)", binders := [(0, 1)] }
] } }
```

上例仅在请求 `"binder"` 标签且函数参数满足 lambda 条件时使用后一条；默认仍使用 `formula`。语言或结构不匹配时，渲染器依次尝试请求标签、默认标签及公式回退。固定数量的显式参数适用 `operator`/`relation`；需要自行重排或选择隐式参数时用 `concept`。

### `operator`、`relation`：符号自动渲染

```lean
operator_info HAdd.hAdd {
  symbol := "+", fixity := «infix», precedence := 65, associativity := left
}
operator_info Neg.neg {
  symbol := "-", fixity := «prefix», precedence := 75, associativity := none
}
relation_info Eq { symbol := "=" }
```

`operator_info` 简写必须按 `symbol`、`fixity`、`precedence`、`associativity` 的顺序填写。`symbol` 必须非空；fixity 只能是 `«prefix»`、`«postfix»` 或 `«infix»`。前缀/后缀运算符各用一个参数，中缀运算符用两个。优先级范围是 0–100，结合方向为 `left`、`right` 或 `none`；渲染器据此自动添加必要括号。

`relation_info` 要求非空 `symbol`，使用两个参数，固定中缀优先级 50、结合方向 `none`。这两类规则都按声明的原生 binder 选择显式参数，不读取 `concept_info.auto_arity` 或模板。若需要倒置参数、分式一类复杂布局或中英文文案，请用 `concept` 模板。

### `wrapper`、`alias`：解包和复用

```lean
wrapper_info OfNat.ofNat { index := some 1 }
def MyEqual (a b : Nat) : Prop := a = b
alias_info MyEqual { target := some Eq }
```

`wrapper_info.index` 是**原始应用参数**的零基索引，包含隐式参数，不经过显式参数筛选。`alias_info.target` 转到目标声明的配置链，不展开 Lean 定义；目标须有配置，链不能成环。这两种 kind 不使用自身的模板。

### 变量命名与参数描述

`var_name` 和 `parameter_template` 不依赖 `kind`，可以单独更新：

```lean
decl_info Nat { var_name := "n" }
decl_info Nat { parameter_template := some "$#self\\in\\mathbb{N}$" }
```

`var_name` 是该声明类型下匿名变量的名称前缀；空字符串回退到声明末段的首字母。内置配置的 `Nat`/`Int` 使用 `n`、`Rat` 使用 `q`，Mathlib 的 `Real` 使用 `x`。可用的用户名称保留；自动名称从 1 编号，例如灰色的 `n₁`。证明变量固定使用 `h`。详细身份与编号规则参见[变量系统说明](../tools/ps4html/Variable-System.md)。

`parameter_template` 用于定理参数的文字描述；`#self` 指该参数本身，`#type` 指类型，`#N` 指类型声明的第 N 个显式参数，数学片段用 `$...$`。它的 `#N` **始终按显式类型参数计数**，不受 `concept_info.auto_arity` 影响。不支持 `@` 或 `#*`。

## 更新、重置与导入合并

同一目标可以多次配置：省略的顶层字段保持原值，普通字段和嵌套对象整体替换，不递归修改嵌套字段。例如仅更新 `concept_info.templates`，需同时写入希望保留的 `auto_arity` 和 `default`；`script_info.template` 则按 `lang` 合并，同语言的模板整条替换。

```lean
theorem_info add_self { name := "自身相加" }
theorem_info add_self { tags := ["自然数"] } -- 保留 name

reset theorem_info add_self                  -- 恢复默认值
theorem_info add_self { name := "加法示例" }
```

支持 `reset project_info`、`reset theorem_info 名称`、`reset script_info 注册ID`、`reset decl_info 名称`。重置会清除目标已有的字段和附加信息；此后可以继续提交新的配置记录。

页面导出以**产物所属模块及其传递导入的最终配置**为准：同模块后写覆盖先写，下游模块覆盖所导入模块；互不导入的分支若对同一字段写入不同值，会在固化时报告冲突，不能靠调整 `import` 顺序解决。任意位置的后续 Info 更新都可影响本模块先前添加的组件；下游更新不会反向改写上游已导出的证明。`pageBuild = false` 区间仍校验字段但不记录更新，重新开启不会补录。可用 `#preview project_info`、`#preview theorem_info <声明>`、`#preview decl_info <声明>`、`#preview script_info <ID>` 检查命令位置的配置。

### 附加信息 `extra`

四类配置都允许附加字段；未知**顶层**字段自动保存在 `extra`，不改变内置展示行为：

```lean
theorem_info add_self {
  name := "自身相加",
  reviewed := true,
  extra := { "review.status" := "checked", edition := 2 }
}
```

附加值可用字符串、数值、布尔、`null`、数组和对象。按键更新；`extra := {}` 不清空已有键，需要清空时重置整个目标。嵌套的内置对象不接受未知字段。

## 常见问题

- **页面样式未更新？** 运行 `lake build MyLibrary:ps4html`；普通构建不登记配置，缓存重渲染也不会重新读取 Lean 源码。
- **`expected a Language constructor`？** 将模板里的 `lang := "zh"` 改为 `lang := zh`（英语为 `en`）。
- **符号排版缺少操作数或需要重排参数？** 符号规则只处理显式参数的一元/二元排版；改用 `concept_info` 模板。
- **占位符字段不存在？** `${...}` 必须对应 recorder 的实际输出；`script_info` 不会自动记录参数。
- **配置写在声明之前或别名目标不存在？** 将配置移到声明可见之后，并检查 `alias_info.target` 的目标配置。

更多示例见[内置声明规则](../ProofScript/Builtin/Config.lean)、[Mathlib 声明规则](../ProofScript/Mathlib/Info.lean)和[内置脚本配置](../ProofScript/Builtin/Script.lean)。需要新增字段或查询配置时，可查看 [Info 源码](../ProofScript/Info/)及 [Lean2TeX 说明](../tools/ps4html/Lean2TeX/README.md)。
