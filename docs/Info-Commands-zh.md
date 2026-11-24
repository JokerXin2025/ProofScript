# Info 命令使用指南

Info 命令决定 ProofScript 页面上**怎样展示**已有的定理、证明步骤和数学表达式，不改变 Lean 声明，也不改变证明是否成立。你不需要开发 ProofScript 才能使用它们：最常见的工作只是给定理起一个中文名，或给某个运算符指定页面上的写法。

本文先介绍可以直接照着使用的配置，再介绍模板、录制数据和跨模块配置等进阶内容。关于如何建立 ProofScript 项目和页面，请先看 [README 快速开始](../README-zh.md#快速开始)。

## 先从这里开始

### 选对配置位置

| 你想改变的内容 | 使用 | 写在哪里 |
| --- | --- | --- |
| 整个站点的标题、作者、默认界面语言 | `ps4html-config.toml` | Lake 项目根目录，与 `lakefile.toml` 或 `lakefile.lean` 同级 |
| 一条定理在页面上的名称、标签 | `theorem_info` | Lean 文件中，定理声明之后 |
| 某种证明步骤的文字、颜色、仪表盘 | `script_info` | Lean 文件中，脚本规则注册之后 |
| 数学对象的名称、符号、表达式排版 | `decl_info` | Lean 文件中，声明之后；也可配置已导入的声明 |

前三种 Lean 命令配置的是**已有目标**，不会创建定理或脚本规则。`theorem_info` 是定理专用的 `decl_info` 简写；`script_info` 的目标是规则的**注册 ID**，不是证明里键入的策略名称。`import ProofScript` 提供这些命令，但不会自动安装数学表达式的展示预设。

### 一个最小例子

```lean
import ProofScript

#page theorem add_self (n : Nat) : n + n = 2 * n := by omega

theorem_info add_self {
  names := [{ lang := zh, value := "自身相加" }],
  tags := [{ lang := zh, value := "自然数" }]
}

decl_info infixl HAdd.hAdd "+" (mode := formula, precedence := 65)
```

`names` 决定定理标题，`tags` 保存分类标签（目前尚无标签 UI）；最后一行让加法在表达式中显示为中缀 `+`。字段间用逗号隔开；语言写 `zh`、`en`，**不加引号**。名称碰到 Lean 关键字时可用 `«...»` 转义。

在项目根目录运行 `lake build MyLibrary:ps4html`（把 `MyLibrary` 换成实际库名），再用 `ps4html serve` 本地查看页面。普通 `lake build` 和 IDE 默认只检查而不登记展示配置；它们仍可能报告字段或目标错误。修改 Lean 中的 Info 后，要重新运行 Lake 页面构建；只运行 `ps4html make --cache` 不会更新导出的配置。只修改 TOML 时则重新渲染即可。

如果只想在当前模块试验，可在配置之前写 `set_option pageBuild true`；这不会补录已经按普通模式编译的导入模块。

## 站点信息：`ps4html-config.toml`

站点标题等信息不写在 Lean 的 Info 命令中，而由 PS4HTML 在渲染时读取项目根目录的可选 TOML 文件。一个项目内的所有库共用这份配置：

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
default_language = "zh"
```

文件及各字段均可省略；标题默认使用 Lake package 名，界面语言默认为英语。`base_url` 是整个 `.PS4HTML/build/` 的公开部署根地址，而非某个页面的地址。可用 `ps4html config check` 在不构建 Lean 的情况下检查文件。所有字段的类型和地址规则见[站点配置契约](PS4HTML-Config-Contract-zh.md)。

## 定理名称与标签：`theorem_info`

先声明定理，再给它添加展示信息；`#page theorem` / `#page lemma` 的页面定理也同样适用：

```lean
#page theorem add_comm_example (m n : Nat) : m + n = n + m := by omega

theorem_info add_comm_example {
  names := [
    { lang := zh, value := "自然数加法交换律" },
    { lang := en, value := "Commutativity of natural-number addition" }
  ],
  tags := [{ lang := zh, value := "自然数" }, { lang := zh, value := "加法" }]
}
```

- `names`：每种语言最多一个名称；可省略 `lang`，表示与语言无关的名称。`value` 不能为空。
- `tags`：同一语言可有多个甚至重复标签；目前只保存和导出，不在界面显示。
- 找不到当前语言的名称时，依次尝试无语言名称、英文名称和 Lean 名称。原生定理/引理的 Lean 回退名称只显示末尾分量。

字段块必须保留，`theorem_info add_comm_example {}` 也是合法写法。它只能用于原生 theorem，内部会设置 `kind := «theorem»`；因此不要在同一字段块再写 `kind`。它也接受下面介绍的 `decl_info` 字段，但原生定理不会使用普通声明的表达式模板。Info 不能改变定理所属模块或项目。

再次设置 `names` 或 `tags` 会替换整个列表，而不是增加一个条目。需要增删条目时使用[列表简写](#多次配置与列表增删)。

## 证明步骤：`script_info`

`script_info` 控制 ProofScript *script* 步骤的展示。配置自定义规则时，用 `script_macro` / `script_elab` 的注册 ID；修改导入模块的规则时用完整 ID。内置规则也可配置，例如 `«exact»`。下例假定 `finishDoc` 已注册，并且它的录制器确实记录了 `proof` 字段：

```lean
script_info «finishDoc» {
  templates := [
    { lang := zh, tag := "完成证明", content := "${proof}" },
    { lang := en, tag := "Finish", content := "${proof}" }
  ]
}
```

普通步骤模板的 `lang`、`tag`、`content` 都要填写；`tag` 和 `content` 可以是空字符串。同一列表不能有重复语言。`${proof}` 是从该步骤的**录制数据**中取值，不是 Lean 局部变量；如果没有录制这个字段，渲染时会报错。详情见[占位符与录制数据](#占位符与录制数据)。

| 字段 | 默认值 | 用途 |
| --- | --- | --- |
| `templates` | `[]` | 各语言的步骤文字；再次赋值会替换整个列表 |
| `renderer` | `default` | 使用模板，或指定专用渲染器 |
| `display` | `true` | 为 `false` 时隐藏整个步骤及分支 |
| `color` | 三项均为 `none` | 标签、边框、背景色 |
| `board` | `[]` | 普通步骤展开后显示的附加录制字段 |

例如给内置步骤设置颜色和中文模板：

```lean
script_info «exact» {
  templates := [{ lang := zh, tag := "直接得到", content := "由 ${value_before} 可得" }],
  color := { tag := some "#166a80", border := some "#9ac7d0" }
}
```

使用 `${value_before}` 前，应确认该规则实际记录了它。颜色也可以写为 `(标签, 边框, 背景)` 三元组，例如 `(some "#166a80", none, none)`；支持 `#RGB`、`#RGBA`、`#RRGGBB`、`#RRGGBBAA`。重新设置 `color` 会替换整个颜色对象，未写的分量回到 `none`。

内置的专用渲染器可写为 `renderer := «calc»`、`«infer»`、`«svg»`、`«remark»` 或 `«admit»`；相应规则仍须录制渲染器要求的数据。例如 `svg` 需要 `metadata_title`、`metadata_label`、`metadata_extra_names`、`metadata_extra_values` 和 SVG 字符串 `code`；若附带源码，还须同时提供 `source_language` 与 `source_code`。未另行配置的普通规则会使用默认的中文空正文模板；如果显式创建 `display := true` 且 `renderer := «default»` 的配置，则须提供模板。`display := false` 时可不提供模板；`admit` 的理由为空时仍显示标注。

### 占位符与录制数据

`${字段}` 仅按完整字段名读取录制器输出；例如 `${rules}` 读取重写规则表达式列表，`${foo.bar}` 只读取字面名称为 `foo.bar` 的字段，不会递归解析对象或数组。模板不能凭空创建字段，也不会读取 Lean 的局部变量。Lean 保存模板字符串；PS4HTML 在渲染实际步骤时检查非空且闭合的占位符，字段缺失会报错。编写模板前，可查看[录制 API 示例](../README-zh.md)与[内置脚本配置](../ProofScript/Builtin/Scripts.lean)。

### 步骤仪表盘：`board`

页面中点击普通步骤的标题，可以展开记录前后的目标、上下文和附加字段；再次点击或按 Enter / 空格收起。`board` 只配置下方的**附加字段**，格式为 `(页面展示名, recorder 字段名)`：

```lean
script_info snapshotRule {
  board := [("使用的证据", "evidence"), ("记录标签", "label")]
}
```

第二项是录制对象的完整字面键名，`"foo.bar"` 不表示嵌套路径。字段顺序就是展示顺序，允许重复展示名或重复引用同一字段；字段缺失显示“未记录”，录制值为字符串 `"completed"` 只在目标状态字段表示完成；其他 `plain` JSON（如 `null`）按 JSON 代码展示。`board := []` 清空并隐藏下方区域。手写录制器可用 `record_param "evidence" h`、`record_value "label" "captured"` 等记录对应值。

仪表盘左右侧的上下文分别取 `$context_names_before` / `$context_types_before` 和 `$context_names_after` / `$context_types_after` 两组等长字段，目标取 `$goal_before` / `$goal_after`。自动录制器会在录制目标前后同步录制上下文；手写录制器仍使用 `record_context "$context_before"` 或 `record_context "$context_after"`（也可加 `(goal := `标签)`），写入时会自动拆为名称和类型两列。未记录上下文时不显示该侧上下文；空上下文是两列空数组。目标缺失显示“未记录”，目标值为 `"completed"` 才显示“✓目标已完成”。当前只有普通 script 的自动模板步骤支持仪表盘；`unknown`、`calc`、`infer`、`introducer` 等特殊步骤暂不支持，即使在相应配置上写了 `board` 也不会显示。

### 分支策略模板（进阶）

对 `split_and` 一类产生分支的策略，模板还要描述分支。**静态分支**逐一写 `cases`，每项的 `name` 必须与录制的分支名一致，`tag` 和 `title` 也必填；数组顺序就是页面顺序：

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

`introducer` 可放在策略整体或单个 case 上，且需要 `tag`、`content`。`inline := true` 只允许一个 case，并要求该 case 的 `tag`、`title` 均为空。普通步骤模板与策略模板不可混用于不相符的注册类型。

**动态分支**不预先列出 `name`，而是按录制的 `$branches` 顺序重复一个 `case`：

```lean
script_info «splitAnd!» {
  templates := [{
    lang := zh, tag := "递归拆分合取",
    case := { tag := "子目标 ${index'}", title := "" }
  }]
}
```

动态 case 的 `tag`、`title` 必填，`introducer` 可选；不写 `name` / `inline`。`${index}` 和 `${index'}` 分别从 0、1 开始计数，会展示为支持数字记法切换的数字节点，优先于同名录制字段。顶层 `tag` / `introducer` 仍只读取录制数据；静态模板没有上述序号特例。动态 case 的其他占位符读取策略步骤记录的字段，不会自动取得当前分支的 `name`。各语言可分别采用静态或动态模板；动态策略未配置时使用通用动态模板。

## 数学对象与表达式：`decl_info`

`decl_info` 配置已存在的 Lean 声明。最简单的用途是给它取页面名称或为匿名变量指定前缀：

```lean
decl_info Nat {
  names := [{ lang := zh, value := "自然数" }, { lang := en, value := "Natural numbers" }],
  var_name := "n"
}
```

如果要把声明渲染为符号，优先使用简写，无需从头写模板：

```lean
decl_info relation Eq "="
decl_info relation LE.le "\\le" (mode := formula)
decl_info LE.le { calc_symbol := "≤" }

decl_info prefix Neg.neg "-" (mode := formula, precedence := 75)
decl_info infixl HAdd.hAdd "+" (mode := formula, precedence := 65)
decl_info postfix Nat.factorial "!" (mode := formula, precedence := 80)
```

此外还有 `infix` 和 `infixr`。`relation` 把声明归为关系，prefix/postfix/infix 系列归为运算符；其余声明默认是 `concept`。简写默认采用公式模式；要改成文本模式可写 `mode := text`。prefix/postfix 要求声明恰有一个显式参数，relation/infix 系列恰有两个。relation 固定优先级为 50，并用提供的符号覆盖 `calc_symbol`；其他简写不会修改 `calc_symbol`。例如 Lean 字符串 `"\\le"` 表示 TeX `\le`，但 calc 中的连接符按**纯文本**显示，想用 `≤` 就另设 `calc_symbol`。中缀允许空符号以省略乘号等，其余简写不允许空符号。

### 自定义表达式模板

符号简写不够用时，给 `templates` 一个列表。`label` 是读者可选择的样式名；`default_template` 是默认选用的 label：

```lean
def interval (a b : Nat) : Nat × Nat := (a, b)

decl_info interval {
  templates := [
    { label := "pair", content := template%:100 ${ "(" arg(0) "," arg(1) ")" }$ },
    { label := "description", lang := zh,
      content := template% { "从" arg(0) "到" $ arg(1) $ "的区间" } }
  ],
  default_template := "pair"
}
```

`template% { ... }` 是文本模板，`template% ${ ... }$` 是公式模板；示例中的 `arg(0)`、`arg(1)` 插入第一个和第二个**显式参数**。字符串片段原样输出，字符串外的空格和换行只为排版源码。文本模板内部用 `$ ... $` 暂时切换到公式模式，公式模板内也可反向切换；切换片段必须成对且非空，不能嵌套。目前字符串片段不接受美元符号。完整内容必须使用 `template%` 专属字面量，不能使用旧式字符串模板。

每项模板都需要非空、可打印 ASCII 的 `label` 和非空 `content`；`lang` 可不写（表示语言无关），同一 `(label, lang)` 不能重复。`formula` 是普通 label，不是强制字段。`template%:70` 设置优先级（0–100，省略时为 60）；`template%:70 raw ${ ... }$` 将编号方式改为包含隐式、严格隐式和实例参数的**所有原始参数**。模板对象中不再填写 `precedence`、`auto_arity` 或旧的 `isolated_args`。

| 片段 | 用途 |
| --- | --- |
| `arg(0)`、`arg(1)` | 插入本模板编号方式下的参数，可跳过或重复，不能越界 |
| `binder(0, 1)` | 取参数 0 的第一层 lambda 绑定变量（层号从 1 开始） |
| `body(0, 0)`、`body(0, 2)` | 取参数 0 的完整表达式，或去除前两层 lambda 后的正文（深度从 0 开始） |
| `arg!(0)`、`binder!(0, 1)`、`body!(0, 1)` | 本次插入由模板自行处理括号，仍保留文本/公式模式转换 |

`binder` / `body` 还决定模板所要求的最少连续 lambda 层数；条件不符时尝试其他模板。字符串中的 `#0`、`@0` 不代表参数。模板选择顺序是“用户选择的 label → `default_template` → 其余 label → 普通展示”；每个 label 依次试当前语言、无语言、英语，并检查对应版本的参数结构。原生 theorem/lemma 不使用这些模板。

只有声明**完整应用**、参数数目与原生声明相符并且模板可用时，普通常量才会使用模板；缺参、多参会回退普通应用并保留全部参数。参数个数只数声明类型最外层连续绑定，不展开返回类型的别名；零参数常量可以使用零参数模板。裸函数和回退应用的头部也会按当前语言选择 `names`。

优先级决定嵌套表达式是否加括号：原子表达式常取 100，函数调用常取 90；同级仅同一原始常量、同一实际模板的 `$infixl` 或 `$infixr` 可按对应结合性省略括号，`$infix` 等仍保留括号。跨文本/公式也比较优先级。无需另写 `associativity` 字段。

### wrapper、alias、变量和 calc

少数声明本身只是展示上的包装或别名：

```lean
decl_info wrapper OfNat.ofNat 1
decl_info wrapper Nat.cast 2

-- 假定 MyEqual 已声明
decl_info relation Eq "=" (mode := formula)
decl_info alias MyEqual → Eq
-- 也可使用 ASCII 箭头：decl_info alias MyEqual -> Eq
```

wrapper 显示指定的原始参数（索引从 0 开始，**包含隐式参数**），要求完整应用；alias 将展示转发到已有声明，不展开 Lean 定义，也不要求两端的原生参数布局一致。alias 可以指向尚未配置展示信息的声明，但不能指向不存在的声明或构成环。这两类声明不使用自身模板；对应活动字段 `wrapper_index`、`alias_target` 缺失或无效会报错。原生 theorem 仍按定理名称显示，不转发不活跃的 alias 配置。

`calc_symbol` 是 calc 块中的非空纯文本连接符，不解析为 TeX；未设置时按语言选名称。alias 使用最终目标的 `calc_symbol` 或名称，而不是自身的这两个字段。更换模板不影响 calc 连接符。

`var_name` 是该类型的匿名变量前缀。`parameter_template` 可以给定理参数提供文字描述，例如：

```lean
decl_info Nat {
  var_name := "n",
  parameter_template := some "$#self\\in\\mathbb{N}$"
}
```

其中 `#self` 指参数本身，`#type` 指完整类型，`#N` 按类型声明的显式参数编号；它与上面的表达式模板语法相互独立，不支持 `@` 或 `#*`。更多变量命名规则见 [Lean2TeX 说明](../tools/ps4html/Lean2TeX/README.md)。

### 字段速查

| `decl_info` 字段 | 默认值 / 说明 |
| --- | --- |
| `names` | `[]`；每种语言（含无语言）最多一个非空名称 |
| `tags` | `[]`；允许同语言多个标签，目前不显示 UI |
| `kind` | `concept`；还可为 `relation`、`operator`、`wrapper`、`«alias»`、`«theorem»`（最后一种仅适用于原生 theorem） |
| `var_name` | `""`；匿名变量前缀 |
| `templates` | `[]`；完整的表达式模板列表 |
| `default_template` | `none`；最终列表非空且未指定时取首项 label |
| `wrapper_index`、`alias_target` | `none`；相应 kind 的必要字段 |
| `calc_symbol` | `none`；calc 中的纯文本连接符 |
| `parameter_template` | `none`；定理参数描述 |
| `extra` | 附加信息按键合并；未知根字段也保存于此 |

## 多次配置与列表增删

同一目标可以多次配置：**没写的字段保留旧值，写出的普通根字段整体替换**。因此再次写 `templates := [...]` 不会只追加一种语言；`names`、`tags`、`board`、`color` 同理。想在当前可见列表中增删条目，可使用简写：

```lean
decl_info names Nat + [{ lang := en, value := "Natural numbers" }]
decl_info names Nat - [en]
decl_info tags Nat + [{ lang := zh, value := "算术" }]
decl_info tags Nat - [{ lang := zh, value := "算术" }]

script_info templates «exact» + [{ lang := en, tag := "Exact", content := "${value_before}" }]
script_info templates «exact» - [en]
script_info board snapshotRule + [("附加标签", "label")]
script_info board snapshotRule - [("附加标签", "label")]

decl_info templates Eq + [
  { label := "call", content := template%:90 ${ "\\operatorname{Eq}(" arg(0) "," arg(1) ")" }$ }
]
decl_info templates Eq - [("call", none)]
```

`names -` 按语言删除；`tags -` 按 `(lang, value)` 删除一个匹配项；脚本模板按语言增删。`board +` 依次追加，`board -` 按完整二元组逐项删除最早的一处。声明模板按 `(label, lang)` 增删，新增项在列表末尾；已有身份、重复项或删除不存在的项会报错。符号简写生成的 `$relation`、`$prefix`、`$postfix`、`$infix`、`$infixl`、`$infixr` 是保留 label，不能用模板 `+` / `-` 操作；符号简写会把对应模板放在列表首位，不改变已有显式 `default_template`。手写保留运算符模板也必须符合其操作数布局。普通模板不能用 `+` 替换已有项，须整体重写根字段。

这些增删命令读取当前**完整可见列表**，再写回完整列表，并非跨模块按条目自动合并。独立模块各自改同一个列表仍可能冲突；有导入冲突时，先在下游显式赋值完整根字段来解决。

## 预览、冲突与常见问题

在 Lean 文件中可查看当前位置可见的配置，或把目标恢复默认值：

```lean
#preview theorem_info add_self
#preview decl_info Nat
#preview script_info «exact»

reset decl_info Nat
reset script_info «exact»
```

预览会检查并展示当前配置，但不会修改记录或页面请求；完整导出使用模块的最终状态。`reset` 清空该目标的展示字段与附加键，声明的 `kind` 回到 `concept`。定理的 Info 也存于声明配置中。

Info 随 Lean 模块的 import 关系传播：同模块后写可覆盖先写；依赖关系中下游可覆盖上游；互不依赖的模块写入**同一个普通根字段**，即便值相同也会在固化时报冲突。不同字段通常可合并，`extra` 按键合并。完整库导出还可能检查未被某页面引用的配置，因此错误不一定出现在正在查看的页面。不要靠调换 import 顺序解决冲突；在共同的下游模块明确写出最终字段值。

| 现象 | 优先检查 |
| --- | --- |
| 页面上看不到新名称或模板 | 是否运行 `lake build MyLibrary:ps4html`；是否只运行了普通构建或 `ps4html make --cache`；配置是否写在声明/注册之后 |
| `${...}` 渲染报错 | 录制器是否真的输出同名完整字段；点号是字段名的一部分，不是对象路径 |
| 表达式没有采用模板 | 声明是否完整应用，参数数目、语言和 lambda 层数是否符合模板要求 |
| 添加一种语言后其他语言消失 | 是否把整个 `names` / `templates` 列表重新赋值了；需要时使用增删简写或写完整列表 |
| 导入后提示配置冲突 | 是否有两个独立模块更新同一普通根字段；在下游明确指定最终值 |
| 站点标题未变化 | 标题应写入项目根目录的 `ps4html-config.toml`，可运行 `ps4html config check` |

旧命令、旧嵌套字段与旧式字符串模板需要迁移 Lean 源码并重新运行 Lake 页面导出；仅重新渲染缓存不会转换格式。格式变化后还应清理旧 `.ProofScript` 产物。更多可运行示例见[经典数学公式](../Test/ClassicalFormula.lean)、[表达式交互](../Test/PageTheoremExpressionInteractions.lean)、[边界示例](../Test/PageTheoremExpressionBoundaries.lean)和 [Info 源码](../ProofScript/Info/)。
