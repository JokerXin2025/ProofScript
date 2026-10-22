# Info 命令使用手册

本文介绍当前六种 Info 命令的输入语法、全部内置字段、更新规则和展示行为。文中的“保留字段”指框架认识并检查类型的内置字段；其它顶层字段作为附加信息保存到 `extra`。

## 1. 入口与命令总览

一般项目使用完整入口：

```lean
import ProofScript
```

仅编写配置模型或元数据命令时，可以使用 `import ProofScript.Info`。它不加载页面和录制运行时，也不加载基础展示配置；配置脚本规则前仍须导入对应的脚本注册模块。

| 命令 | 目标 | 配置对象 |
| --- | --- | --- |
| `project_info ["项目ID"] { ... }` | 非空字符串字面量；可省略 | 项目与文献信息 |
| `theorem_info 声明名 [{ ... }]` | 已存在的 Lean 声明 | 定理展示名、标签与项目归属 |
| `script_info 注册ID { ... }` | 已注册的脚本规则 ID | 步骤与策略的展示方式 |
| `def_info 声明名 { ... }` | 已存在的 Lean 常量 | 表达式的 TeX/文本排版 |
| `var_info "类别" { ... }` | 非空字符串 | 自动变量名分配 |
| `phrase_info "短语键" { ... }` | 非空字符串 | 多语言表达式短语 |

### 构建模式

普通 `lake build` 和 IDE 默认使用验证模式：六种 Info 命令均不做字段解码与语义校验、不登记 Info 配置事件。命令语法仍须能够解析，同一模块也不能在使用这些命令后切换 `proofScript.pageBuild`。

两种模式都会保留 IDE 语义信息：`def_info`、`theorem_info` 的声明目标，以及 `def_info` 的 `«alias» := some 声明名` 支持悬停、跳转、同名引用联动和声明名补全；`script_info` 的注册 ID 与对应 `script_macro` / `script_elab` 定义使用同一个符号身份。内置字段名（包括模板、样式、颜色等嵌套对象）链接到配置模型的对应字段，并提供字段名补全。验证模式只尝试登记这些引用，未找到或有歧义的目标不会使构建失败，也不会执行配置值中的 Lean 代码。字符串项目 ID、变量类别、短语键、枚举值及附加字段仍按各自的字面量语法处理。

脚本、页面命令和自定义扩展的语义信息约定见 [IDE 与语言服务器支持](IDE-Support-zh.md)。

`lake build MyLibrary:ps4html` 自动启用页面模式，六种命令才执行下文描述的解析、校验、更新和合并。该构建会在隔离目录中重编译所需用户源码、ProofScript 框架及配置依赖，恢复基础策略 renderer、Lean2TeX 和 Mathlib 展示默认值。普通验证 `.olean` 中没有被跳过的配置，不能只在下游打开开关后恢复它们。

除导入示例外，下文每个 Lean 代码块均以 `import ProofScript` 和页面模式为前提。仅实验当前模块配置时，可以在首个 Info 或页面命令前写 `set_option proofScript.pageBuild true`；它不会重新执行已按验证模式编译的导入模块中的默认配置，完整页面应使用 Lake facet 构建。`{ ... }` 等带省略号的语法表示只在行内说明中使用。

模型、schema、codec、查询函数及显式底层录制 API 在两种模式中均可使用。查询只能读取实际登记的配置，不能恢复被跳过的命令；显式录制可以独立捕获数据，完整页面导出仍需要相应展示配置。

## 2. 所有命令共用的规则

### 2.1 字段与值的写法

字段之间用逗号分隔，字段名可写标识符或字符串。遇到 Lean 关键字时可以使用 `«名字»`，例如 `«alias»`、`«infix»`。

配置值由专门的解析器读取。字符串、布尔、数值及列表使用字面量，不能用任意 Lean 表达式替代。

| 类型 | 输入示例 |
| --- | --- |
| 字符串 | `"中文标题"` |
| 布尔 | `true`、`false` |
| 自然数 | `0`、`2` |
| 列表或数组 | `["a", "b"]`、`[0, 2]`；输入统一用 `[...]` |
| 嵌套对象 | `{ lang := "zh", content := "..." }` |
| 枚举 | `relation`、`explicit`、`«infix»`；不加字符串引号 |
| 普通 Option | `none` 或 `some 值` |
| 重置 | `reset` |

部分 Option 字段额外支持省略 `some`：`theorem_info.project`、`def_info.kind/arguments/styles`、策略模板和 case 的 `introducer`。其它 Option 字段按对应章节的语法填写。

### 2.2 重复配置、替换与重置

同一目标可以反复配置，每条命令只更新写出的字段。

```lean
project_info "Notes" { title := "初稿", authors := ["Alice"], keywords := ["algebra"] }
project_info "Notes" { title := "修订稿" }
project_info "Notes" { keywords := reset }
```

最终标题为“修订稿”，作者仍是 `Alice`，关键词恢复为默认的空列表。

| 操作 | 语义 |
| --- | --- |
| 省略字段 | 保留该字段原有的有效值 |
| 普通字段赋值 | 替换该字段；普通列表也整体替换 |
| `none` | 给 Option 字段赋空值；某些字段随后会据此计算条件默认值 |
| `reset` | 屏蔽此前继承的值并恢复字段默认；没有默认值的必填字段恢复为“未提供” |
| `template := [...]` | 仅 `script_info`、`phrase_info` 按 `lang` 合并；相同语言的整条模板被替换 |
| `styles := [...]` | `def_info` 的整个样式数组被替换 |
| `color := {...}` | 整个颜色对象被替换；省略的分量恢复为 `none` |
| 附加字段赋值 | 按 `extra` 中的键替换；键对应的对象或数组不会递归合并 |

嵌套对象不是递归 patch。例如更新某个语言模板时，仍须填写该模板的全部必填字段。

对于按语言合并的 `template`，`template := []` 不删除已有语言。若要只保留一组新语言，应分两条命令先 `template := reset`，再写新模板；同一命令不能重复赋同一字段。`phrase_info.template` 重置后暂无值，需要在消费前重新补全。

### 2.3 附加字段 `extra`

六种命令都具有 `extra`，默认 `{}`。未知顶层字段自动进入这个容器：

```lean
project_info "Notes" {
  title := "课程笔记",
  edition := 2,
  reviewed := true,
  extra := {
    "review.status" := "checked",
    source := { repository := "https://example.org/notes", revision := 3 },
    ratings := [4.5, 5],
    comment := null
  }
}
project_info "Notes" { edition := reset, extra := { "review.status" := reset } }
```

附加值支持字符串、数值、负数、布尔、`null`、数组和对象；附加值中的 `none` 也表示 JSON null。`null` 是保存一个空值，`reset` 是删除这个附加键。

显式 `extra` 中可以使用与内置字段相同的键，例如 `extra := { title := "附加标题" }`，但它不会修改内置的 `title`。带点的字符串键如 `"review.status"` 是一个完整键，不表示嵌套路径。

`extra := {}` 不清空原有附加字段，`extra := reset` 也不是支持的写法；删除时逐键写 `reset`。附加对象内部的 `reset` 不作为通用 JSON 值使用。

当前项目附加信息可出现在文献详情中。其它领域的附加字段会被保存和导出，是否展示由消费者决定；增加键名不会自动生成新的渲染行为。

### 2.4 检查发生在什么时候

- 命令输入时检查字段类型、重复键、嵌套对象结构及局部约束。一条命令全部解析成功后才提交，不会只保存前半条字段。
- 未知顶层字段存入 `extra`；与内置字段相似的拼写可能触发警告。显式写在 `extra` 内可避免这类拼写提示。
- 模板、样式、颜色等没有 `extra` 的嵌套对象拒绝未知字段。
- 必填字段缺失、字段之间的组合约束、跨模块冲突和脚本契约匹配，主要在查询或快照消费时检查。

因此可以分多条命令逐步补齐记录，但被页面或渲染实际使用前必须完整。下文表格中的“必填”均指最终消费时必须具备；一个新输入的嵌套模板或样式则须当场完整。

## 3. `project_info`：项目与文献元数据

### 3.1 目标与活动项目

```lean
namespace Course

project_info "Algebra" { title := "代数笔记" }
project_info { description := "更新当前活动项目" }
project_info "Analysis" { title := "分析笔记" }
project_info "Algebra" {} -- 切回已有项目，字段保持不变

end Course
```

项目 ID 直接保存为非空 `String`，输入统一使用字符串字面量，例如 `"Algebra"`、`"代数学 · 上册"`、`"A.B"`。项目 ID 按完整文本匹配，命名空间和 `open` 不参与解析，字符串中的点不表示命名空间。

每次 `project_info` 都将目标设为活动项目。省略项目名时更新活动项目；尚无活动项目时，以当前模块名创建默认项目。导入分支造成活动项目歧义时，使用显式目标选择。

### 3.2 全部保留字段

| 字段 | 类型 | 默认值 | 用途 |
| --- | --- | --- | --- |
| `title` | String | `""` | 项目标题 |
| `authors` | List String | `[]` | 作者列表 |
| `keywords` | List String | `[]` | 关键词列表 |
| `description` | String | `""` | 项目简介 |
| `year` | String | `""` | 年份文本，输入如 `"2026"` |
| `license` | String | `""` | 许可说明 |
| `base_url` | String | `""` | 项目网址 |
| `extra` | ExtraFields | `{}` | 附加元数据 |

这些文本字段不额外执行年份、URL 或许可标识校验。

```lean
project_info "Algebra" {
  title := "代数基础",
  authors := ["Alice", "Bob"],
  keywords := ["group theory", "Lean"],
  description := "面向初学者的形式化课程笔记",
  year := "2026",
  license := "CC BY 4.0",
  base_url := "https://example.org/algebra",
  edition := 2
}
```

## 4. `theorem_info`：定理展示与归属

```lean
project_info "Paper" { title := "证明笔记" }
theorem identity (n : Nat) : n = n := rfl
theorem_info identity { name := "自反性", tags := ["equality"] }
theorem_info identity { tags := ["basic", "equality"] }
```

目标必须已声明，按 Lean 的命名空间与名称解析规则查找。它通常是定理；当前实现检查目标是已存在的全局声明，不额外限制其声明种类。

| 字段 | 类型 | 默认值 | 用途 |
| --- | --- | --- | --- |
| `project` | Option String | `none`，首次配置可初始化为活动项目 | 项目归属 |
| `name` | String | `""` | 人类可读的展示名 |
| `tags` | List String | `[]` | 分类标签；更新时整体替换 |
| `extra` | ExtraFields | `{}` | 附加元数据 |

第一次 `theorem_info` 未写 `project` 时，记录当时的活动项目；之后只修改名称、标签不会重新计算归属。后续切换活动项目也不会自动移动已有定理。`project := reset` 恢复结构体默认的 `none`，不会重新绑定当前活动项目。

```lean
project_info "First" { title := "第一项目" }
theorem sample : True := True.intro
theorem_info sample -- 空字段配置，也会记录首次项目归属

project_info "Second" { title := "第二项目" }
theorem_info sample { name := "仍属于第一项目" }
theorem_info sample { project := "Second" } -- 显式改归属；some "Second" 也可以
theorem_info sample { project := none }   -- 解除归属
```

`theorem_info` 只影响命令之后创建的内容。录制定理自身的标题、标签和项目使用声明内联配置，位置在名称之后、binders 之前：

```lean
@theorem reflexive (info := { name := "自反性", project := "Paper" })
    (n : Nat) : n = n := script
  rfl
```

`@lemma` 支持相同写法。页面构建中，内联字段与 `theorem_info` 使用相同 Schema、解析及校验，并属于声明事务的一部分：证明或配置失败时整条声明回滚。省略 `project` 时使用声明前的活动项目；显式 `project` 可以消除上游活动项目的歧义。声明后的同名 `theorem_info` 不会回头修改这个定理组件或它的证明。

普通构建和 IDE 中，`@theorem` / `@lemma` 只生成并检查原生 theorem，跳过内联展示配置、录制和导出；`cite` 仍检查 Lean 引用项，但不消费展示元数据。六种独立 Info 命令也跳过字段解码、语义校验和登记，同时保留已有目标和已知字段的编辑器信息。`lake build MyLibrary:ps4html` 自动启用页面模式，并重编译所需用户源码、框架及配置依赖，恢复完整的声明时配置与证明记录。

项目引用必须先由 `project_info` 配置。页面中的定理 `name` 为空时使用声明末段名称；文献列表有自己的默认标题。`theorem_info` 本身不创建页面组件；页面定理通过 `@theorem` / `@lemma` 声明，文献列表通过 `@references` 插入。未配置元数据的声明不会自动作为已登记文献展示。

## 5. `script_info`：脚本步骤与策略展示

### 5.1 目标是注册 ID

```lean
script_macro finishDoc "finish_doc" proof:term => `(tactic| exact $proof:term)
script_info finishDoc {
  template := [{ lang := "zh", tag := "完成证明", content := "${proof_before}" }]
}
```

`finishDoc` 是 `script_macro` 的注册 ID，`finish_doc` 是用户写脚本时使用的关键字。完整 ruleId 为“定义模块名 + 注册 ID”，不由声明时的 Lean namespace 决定。

单段 ID 只在当前模块中查找，不进行普通 Lean 名称解析。配置导入规则时使用完整 ID，例如：

```lean
script_info ProofScript.Script.Basic.«exact» {
  template := [{ lang := "zh", tag := "直接得到", content := "${value_before}" }]
}
```

### 5.2 顶层保留字段

| 字段 | 类型 | 默认值 | 用途 |
| --- | --- | --- | --- |
| `renderer` | ScriptRenderer 枚举 | `none` | 模板渲染或专用渲染器 |
| `template` | Array ScriptTemplate | `[]` | 按 `lang` 合并的展示模板 |
| `display` | Bool | `true` | 是否展示整个步骤，包括策略子分支 |
| `color` | ScriptColor | 三个分量均为 `none` | 标签、边框和背景配色 |
| `extra` | ExtraFields | `{}` | 附加配置 |

这里的 `renderer := none` 是枚举值，表示自动使用模板，不是 Option。此模式在消费时要求非空模板。

完全没有配置记录时，普通注册会获得 `lang := "zh"`、以脚本关键字为标签、内容为空的默认模板；策略注册使用动态 `strategy` 渲染器。一旦创建了配置记录，就必须满足该记录的完整性要求。例如给一个全新普通规则仅配置 `display := false`，并不能替代所需模板。

### 5.3 普通模板

| 字段 | 类型 | 默认值/要求 |
| --- | --- | --- |
| `lang` | String | 必填且非空；不限定为 `zh` / `en` |
| `tag` | String | 必填；步骤标签，可为空字符串 |
| `content` | String | 必填；步骤正文，可为空字符串 |

```lean
script_info ProofScript.Script.Basic.«change» {
  template := [
    { lang := "zh", tag := "改写目标", content := "改写为 ${equation_before}" },
    { lang := "en", tag := "Change the goal", content := "${equation_before}" }
  ]
}
```

渲染时先精确匹配语言，找不到则使用有效模板数组的第一项。增加其它语言不会删除已有语言；同语言更新替换整条模板，不能只写 `content`。

### 5.4 策略模板、case 与介绍段

模板对象出现 `cases` 时按策略模板解析；否则按普通模板解析。模板种类必须与脚本注册的 `strategy` 属性一致。

| 策略模板字段 | 类型 | 默认值/要求 |
| --- | --- | --- |
| `lang` | String | 必填且非空 |
| `tag` | String | 必填；策略整体标题 |
| `inline` | Bool | `false` |
| `introducer` | Option ScriptIntroducer | `none`；接受裸对象或 `some` 对象 |
| `cases` | Array ScriptCase | 必填、非空 |

| case 字段 | 类型 | 默认值/要求 |
| --- | --- | --- |
| `name` | String | 必填、非空，同模板内不能重复；对应实际分支名 |
| `tag` | String | 必填；分支标签 |
| `title` | String | 必填；分支标题 |
| `introducer` | Option ScriptIntroducer | `none`；分支介绍段 |

`ScriptIntroducer` 只保留 `tag`、`content` 两个必填字符串字段。

```lean
script_info ProofScript.Script.Basic.«split_and» {
  template := [{
    lang := "zh",
    tag := "分别证明",
    introducer := { tag := "目标拆解", content := "证明合取的左右两部分" },
    cases := [
      { name := "left", tag := "第一部分", title := "左侧命题" },
      { name := "right", tag := "第二部分", title := "右侧命题" }
    ]
  }]
}
```

每种语言的 case 名称集合须与实际录制分支一致，模板中的 case 顺序决定展示顺序。名称对应关系在后端结合实际步骤检查。

`inline := true` 要求恰好一个 case，且该 case 的 `tag`、`title` 均为空字符串。它省略 case 自身的折叠框，保留策略整体容器。例如：

```lean
script_info ProofScript.Script.Basic.«contra» {
  template := [{
    lang := "zh", tag := "反证法", inline := true,
    introducer := { tag := "假设", content := "假设 ${hypothesis}，导出矛盾" },
    cases := [{ name := "proof", tag := "", title := "" }]
  }]
}
```

### 5.5 `${...}` 占位符与录制契约

脚本模板读取的是 recorder 输出字段，不是任意 Lean 局部变量，也不是 `script_info.extra`。可用字段取决于具体注册与 recorder，例如 `${h}`、`${equation_before}`、`${goal_before}`。自动录制的 term 参数默认在执行前后各捕获一次，字段名带 `_before` / `_after`；不要仅根据输入参数名推测输出字段名。

支持 `${字段}`、`${对象.成员}`、`${数组.0.成员}`，数组下标从 0 开始；不支持表达式求值或方括号索引。完整字段名优先匹配，再按点分路径。

占位符会对照输出契约检查，包括普通模板的 `tag/content`、介绍段的 `tag/content`、策略标题和 case 的 `tag/title`。对象只允许访问契约声明的成员；optional 可穿透，union 中任一分支支持即可，开放 JSON 契约允许任意后续路径。表达式内部结构不开放：一个字段虽然最终导出为表达式 JSON，也不能随意使用 `${h.kind}` 等路径。opaque 契约只在 Lean 端检查占位符语法，实际字段存在性由后端检查。

运行时 null 通常显示为 `—`，数组以逗号连接，表达式交给 Lean2TeX。模板文本按文本处理并进行 HTML 转义。未闭合或空的占位符会报错；当前没有专门输出字面 `${` 的转义语法。

普通步骤的默认适配器提供 `goal_before`、`goal_after` 两个普通可空表达式字段；策略的默认适配器只提供 `goal_before`。手写 recorder 不保证提供这些字段，占位符须以实际录制契约为准。修改 `script_info` 不会修改 recorder、执行入口或录制契约。`display := false` 仍须通过配置完整性与录制契约检查。

### 5.6 颜色

`color` 只保留三个 Option 颜色字段：`tag`、`border`、`background`，各自默认 `none`。颜色只能写 `#RGB`、`#RGBA`、`#RRGGBB` 或 `#RRGGBBAA`；输入使用 `some "#..."`，不接受 CSS 颜色名称。

```lean
script_info ProofScript.Script.Basic.«exact» {
  color := {
    tag := some "#166a80",
    border := some "#9ac7d0",
    background := some "#eff8fa"
  }
}
script_info ProofScript.Script.Basic.«rfl» {
  color := (some "#166a80", none, some "#eff8fa")
}
```

三元组的顺序是标签、边框、背景。后续只写一个分量会替换整个 `color`，其余恢复 `none`。

### 5.7 全部 renderer 取值

| 枚举输入 | 用途 | 需要的录制字段 |
| --- | --- | --- |
| `none` | 使用普通或策略模板 | 由模板占位符决定 |
| `«strategy»` | 按实际分支动态展示策略 | 策略注册，运行时有非空 `branches` |
| `«calc»` | 等式/关系计算链 | `init`、`chain` |
| `«infer»` | 命题推导链 | `init`、`chain` |
| `«media»` | LaTeX/SVG 资源 | `metadata`、`svg`、`source` |
| `«diagram»` | 内联 SVG | `code` |
| `«remark»` | 备注 | `text` |
| `«admit»` | 未完成证明说明 | `reason` |
| `«embed»` | 嵌入证明 | `theorem`、`args`、`argKinds`、`proof`、`h`、`type` |
| `«unrecorded»` | 保留 ruleId `ProofScript.Recording.unrecorded` 的红色“未导出数据”提示 | `name`；策略分支仍展示 |

```lean
script_info ProofScript.Script.Basic.renderCalc { renderer := «calc» }
script_info ProofScript.Script.Basic.«constructor» { renderer := «strategy» }
```

专用 renderer 使用自己的展示逻辑；同时配置的模板仍会被检查，但不参与它的输出。`strategy` renderer 的内建布局在语言为 `zh` 时使用中文，其余语言使用英文，不采用普通模板的语言回退规则。自定义策略未登记专门布局时，以 ruleId 末段为标题、实际分支名为标签。

Lean 在契约已知时检查上述必要字段名称；字段值的实际形状由后端进一步检查。设置 renderer 不能让缺少数据的 recorder 自动输出这些字段，也不能把普通注册变成策略注册。

## 6. `def_info`：表达式排版

### 6.1 顶层保留字段

目标是已存在的 Lean 常量。它控制该常量及其应用如何展示，不改变 Lean 定义或数学含义。

| 字段 | 存储类型 | 默认值/消费规则 |
| --- | --- | --- |
| `kind` | Option DefinitionKind | `none`；普通模式通常取 `const`，有 `calc_symbol` 时取 `relation` |
| `arguments` | Option DefinitionArguments | `none`；通常取 `[]`，有 `calc_symbol` 时取 `explicit` |
| `dynamic_arity` | Bool | `false` |
| `styles` | Option (Array DefinitionStyle) | `none`；普通模式须提供非空样式，或由 `calc_sy mbol` 生成 |
| `calc_symbol` | Option String | `none`；非空关系符号 |
| `unwrap` | Option Nat | `none`；直接展示某个原始应用参数 |
| `«alias»` | Option DeclarationRef | `none`；复用另一声明的配置 |
| `extra` | ExtraFields | `{}` |

`kind` 全部取值为 `«const»`、`operator`、`relation`、`logic`、`projection`、`constructor`、`«type»`。它是展示分类，不会自动推导参数、优先级或模板。

`kind`、`arguments`、`styles` 可直接写裸值；`calc_symbol`、`unwrap`、`alias` 使用 `some ...` 或 `none`。`styles := []` 是显式空列表，普通模式下非法，不等于 `styles := none` 或 `styles := reset`。

### 6.2 普通常量与运算符

```lean
def InfoDocZero : Nat := 0
def InfoDocCombine (a b : Nat) := a + b

def_info InfoDocZero {
  kind := «const»,
  styles := [{ template := "\\mathbf{0}", fixity := atom }]
}
def_info InfoDocCombine {
  kind := operator,
  arguments := [0, 1],
  styles := [{
    template := "#0\\oplus #1",
    fixity := «infix», precedence := 65, associativity := left
  }]
}
```

`arguments := [2, 0]` 表示从完整 Lean 应用参数中依次选原始第 2、第 0 项，编号从 0 开始，包含隐式参数和实例参数，索引不得重复。模板中的 `#0`、`#1` 则编号筛选后的结果。`binders` 与 `isolated_arguments` 也使用筛选后的编号。

`arguments := explicit` 根据表达式导出的显式参数标记筛选参数。实际应用参数数量、显式标记以及参数形状，须由后端结合表达式检查。

### 6.3 每个 style 的全部保留字段

| 字段 | 类型/取值 | 默认值 | 用途 |
| --- | --- | --- | --- |
| `name` | String | `"formula"` | 样式选择名 |
| `mode` | `formula` / `text` | `formula` | 数学公式或文本模式 |
| `template` | String | 必填 | 排版模板 |
| `fixity` | `atom/prefix/postfix/infix/binder/application/custom` | `custom` | 括号处理的布局类别 |
| `precedence` | Nat，0–100 | `100` | 越大结合越紧 |
| `associativity` | `left/right/none` | `none` | 相同优先级中缀表达式的结合方向 |
| `separator` | String | `", "` | `#*` 的参数连接文本 |
| `binders` | `(参数编号, binder 数量)` 列表 | `[]` | lambda 结构匹配；数量须为正，参数编号不能重复 |
| `isolated_arguments` | 无重复自然数列表 | `[]` | 这些参数不自动加括号，由模板处理 |

普通 `styles` 整体替换，不按 `name` 合并。允许多个同名样式，用于按 lambda 结构先选特化样式再选普通回退。

`formula` 模板通常填写不带外围 `$` 的 TeX；嵌入文本时由渲染器加入数学分隔符。`text` 模式嵌入公式时转换为 `\text{...}`，其文本中的 `$...$` 片段作为数学内容处理。

当前默认请求 `"formula"` 时，渲染器先查找 `"prose-语言"`，例如 `"prose-zh"`，再回退到 `"formula"`。请求其它样式名时先查该名称，再查 `"formula"`；不会自动选数组第一项或另一种语言。候选样式还须满足 `binders` 的结构条件，按数组顺序选择首个可用项。

在相同公式模式下，子项优先级低于父项时自动加括号。父子都是相同优先级的中缀布局时，`none` 两侧加括号，`left` 对非首参数加括号，`right` 对首参数加括号；这里不额外比较运算符名称。文本模式、跨模式或 `isolated_arguments` 中的参数不使用这套自动括号规则。

### 6.4 模板占位符与 binder 样式

| 写法 | 作用 |
| --- | --- |
| `#0`、`#1` | 筛选后的参数 |
| `#*` | 用 `separator` 连接全部筛选参数，用于动态参数模式 |
| `@0` | 使用参数 0 的第一个 lambda binder |
| `@@0` | binder 数量为 1 时，使用去掉该层 lambda 后的正文 |

固定参数模式下，所有 `#N` 和 `@...N` 引用的参数编号合起来须从 0 连续，允许重复引用。每个样式是否含 `#*` 必须与 `dynamic_arity` 一致。

```lean
def_info List.map {
  arguments := explicit,
  styles := [
    { template := "\\operatorname{map}(@0\\mapsto @@0,#1)", binders := [(0, 1)] },
    { template := "\\operatorname{map}(#0,#1)" }
  ]
}
```

上例先尝试第一个参数至少为一层 lambda 的样式，再使用不依赖 lambda 的普通样式。`binders := [(j, n)]` 可配合最多 `n+1` 个 `@`；对于恰好 n 层 lambda，依次得到各层 binder 和最终正文。当前最后一级若仍遇到 lambda，会取该层 binder 名，编写深层模板时应按实际表达式形状选择。

整个样式数组至少需要一个不含 `@` 的样式。`@` 引用必须具有相应的 `binders` 配置。固定参数模式中的 `isolated_arguments` 必须是模板实际引用的参数。

### 6.5 动态参数

```lean
def InfoDocPack (a b c : Nat) := a + b + c
def_info InfoDocPack {
  kind := constructor,
  arguments := explicit,
  dynamic_arity := true,
  styles := [{ template := "\\langle #*\\rangle", separator := ", " }]
}
```

当前后端在 `dynamic_arity := true` 时始终按显式参数筛选；不要依赖同时给出的数字索引列表。每一个 style 都必须包含 `#*`。

### 6.6 `calc_symbol` 简写

```lean
def_info Eq { calc_symbol := some "=" }
def_info LE.le { calc_symbol := some "\\le" }
```

普通模式中，合并后的有效 `kind/arguments` 为 `none` 时，有 `calc_symbol` 则分别取 `relation`、`explicit`；有效 `styles` 为 `none` 时，生成模板为 `#0符号#1` 的中缀样式，优先级为 50、结合方向为 `none`。命令省略字段会保留已有值，不保证重新触发这些默认规则。TeX 字母控制序列末尾会补空格。

自动生成样式要求固定参数模式和 `relation` 分类；显式索引列表必须恰有两项。`explicit` 的实际数量不在此验证，实际应用须具有模板引用的参数；模板未引用的其它显式参数不会自动显示。若已经显式提供 `styles`，不会自动生成；`calc_symbol` 仍可用于计算链的关系符号。

### 6.7 别名与 unwrap

```lean
def InfoDocWrap (n : Nat) := n
def InfoDocEqual (a b : Nat) := a = b
def_info InfoDocWrap { unwrap := some 0 }
def_info InfoDocEqual { «alias» := some Eq }
```

`unwrap` 选择完整原始应用的某个参数，不经过 `arguments` 筛选。`alias` 沿目标配置链解释当前应用，不展开 Lean 定义；目标链须有配置且不能形成循环。

只有 `alias` 与 `unwrap` 互斥。它们启用时可以保留 `kind/arguments/styles/calc_symbol`，但普通展示字段暂不消费；局部类型检查仍执行。切回普通模式时清除相应 Option，并确保普通展示字段完整。

### 6.8 缺配置与样式回退

未配置的常量使用短名展示，未配置的应用使用普通函数应用，并产生相应诊断。已配置但没有匹配样式时，产生样式诊断并只显示常量短名，应用参数不会全部保留。模板引用了实际缺失的参数时，显示 `[missing ...]` 诊断占位。

## 7. `var_info`：自动变量名

```lean
var_info "Nat" { default := "n", names := ["n", "m", "k"] }
var_info "Prop" { default := "P", names := ["P", "Q", "R"] }
var_info "Proof" { default := "h", names := ["h", "h₁", "h₂"] }
```

| 字段 | 类型 | 默认值/要求 |
| --- | --- | --- |
| `default` | String | 必填；名称池耗尽后的前缀 |
| `names` | Array String | 必填；允许 `[]` |
| `extra` | ExtraFields | `{}` |

目标是精确匹配的非空字符串，不进行 Lean 名称解析。常见键包括完整类型常量名，如 `"Nat"`、`"Real"`，以及 `"Prop"`、`"Type"`、`"Function"`、`"Proof"`、`"Expr"`。

用户写出的可用变量名通常直接保留；名称池主要用于匿名或自动生成的变量。分配时按 `names` 顺序选尚未占用的名称，耗尽后用 `default_1`、`default_2` 等。没有该类别配置时使用 `类别名1`、`类别名2` 等。不同类别共用已占用名称集合，同一 fvar ID 重复出现时复用名称；每份证明使用独立或重置后的分配状态。

当前类型分类以直接类型形状为准：常量使用完整名称，sort 对应 `Prop/Type`，函数类型对应 `Function`。fvar 还可按命题、证明和未知表达式区分为 `Prop/Proof/Expr`；lambda/forall 的自动 binder 不具有全部 fvar 特判。任意类型应用不会自动按头常量匹配，例如配置一个容器名不保证覆盖它的所有应用类型。

## 8. `phrase_info`：多语言短语

```lean
phrase_info "forall" {
  template := [
    { lang := "zh", content := "${body}对一切 $${binder}\\in ${type}$ 成立" },
    { lang := "en", content := "${body} for every $${binder}\\in ${type}$" }
  ]
}
phrase_info "exists" {
  template := [{ lang := "zh", content := "存在 $${binder}\\in ${type}$，使得 ${body}" }]
}
```

| 顶层字段 | 类型 | 默认值/要求 |
| --- | --- | --- |
| `template` | Array PhraseTemplate | 必填、最终非空；按 `lang` 合并 |
| `extra` | ExtraFields | `{}` |

每个 `PhraseTemplate` 只保留 `lang`、`content` 两个必填字符串字段；`lang` 不能为空，同一列表内不能重复语言。

唯一允许的命名占位符为 `${body}`、`${binder}`、`${type}`，分别表示正文、变量和类型。它们与脚本 recorder 字段无关，也不使用 `def_info` 的 `#N` 语法。示例中的 `$${binder}...$` 是一个普通数学公式美元符号，紧接 `${binder}` 占位符。

当前后端主动使用 `"forall"` 和 `"exists"` 两个键。其它非空键可以存储，但需额外消费者才会影响展示。语言回退顺序为：请求语言 → `en` → `zh` → 内建英文短语；空内容会被视为无可用短语。

非依赖的蕴涵箭头直接使用公式排版，不采用 `forall` 短语；`Exists` 的谓词不是 lambda 时也使用其它回退路径。

## 9. 导入合并、页面时序与导出

本节描述页面模式中实际登记的配置；验证模式跳过的 Info 命令不参与合并，也不建立配置边界。

### 9.1 跨模块合并

六种命令使用同一套导入规则：

1. 同一模块后写覆盖前写。
2. 后代模块的赋值覆盖其导入祖先中的同字段赋值。
3. 独立导入分支修改不同字段可以合并；`template` 以语言为单位，`extra` 以键为单位。
4. 独立分支写入相同值可以共存；不同值保留为冲突，并记录双方来源。
5. 汇总模块可以通过显式赋值或 `reset` 消解对应冲突；不能依靠交换 `import` 顺序选一个值。

例如两个独立模块把同一项目标题写为不同字符串，汇总模块须重新写 `title`。若冲突发生在某种模板语言，重新写其它语言并不会消除它。

这些更新属于模块环境，不是 namespace 内的临时变量；`end` 不会撤销配置。

### 9.2 按内容位置确定配置

每份证明和每个页面组件在创建时捕获本模块的元数据提交序号。之后消费配置时：

- 读取全部传递导入模块的最终配置，包括上游 `page_end` 之后的更新。
- 本模块只读取捕获边界之前已经提交的修改；不按源码行号重新扫描。
- 内联 `(info := { ... })` 在声明完成事务中写入，并计入该声明自身的边界。
- `namespace`、`section` 和 `page_end` 都不创建配置作用域。

```lean
project_info "Demo" { title := "示例页面" }
var_info "Nat" { default := "n", names := ["n"] }

@theorem reflexive (info := { name := "自反性" }) : ∀ _ : Nat, True := script
  exact (fun _ => True.intro)

var_info "Nat" { default := "k", names := ["k"] }
theorem_info reflexive { name := "后续引用使用的标题" }

@theorem later : ∀ _ : Nat, True := script
  exact (fun _ => True.intro)
page_end
```

`reflexive` 的组件标题是“自反性”，匿名变量的自动命名配置仍是 `n`；`later` 使用 `k`。中间的修改即使位于 `page_end` 之前，也不会改变前一份证明。后面的引用可以看到“后续引用使用的标题”。独立证明、以及 `page_end` 后记录的证明，也使用各自创建时的边界，不使用模块结束视图。

`@references` 在组件位置确定它引用的定理名称与项目信息。相同定理在不同位置的引用可以使用不同展示名。证明导航的项目归属和依赖筛选也使用该证明捕获的同一查询边界。

`page_end` 负责关闭并写出页面；其后的页面组件会被忽略，Info 命令则继续进入模块环境，供后续代码及下游模块使用。页面的各个组件可以绑定不同 `snapshotId`，证明产物也各自绑定其配置快照。

快照按实际依赖收集配置；无关、未消费的不完整配置不阻塞内容。脚本调用使用实际选中的录制契约，较晚的 `script_info` 既不会改写录制事实，也不会改变较早内容的展示配置。需要在证明中使用的配置必须先完整设置；普通定理在被引用前设置 `theorem_info.project`，录制定理自身的项目则通过声明前活动项目或内联 `info` 提供。旧的“证明后补配置、到 `page_end` 统一生效”写法需要迁移。

### 9.3 构建与缓存

页面模式下，配置命令只更新环境，不逐条写配置文件；验证模式不写入这些配置事件。配置事件、快照和产物清单可从页面构建的 `.olean` 统一导出；普通验证 `.olean` 中跳过的配置必须通过页面重编译恢复。页面和证明内容由构建阶段生成。

完整站点使用 `lake build MyLibrary:ps4html`。已有完整导出可用 `ps4html make --cache` 重新渲染，不重新运行 Lean。缓存渲染使用绑定的快照；编辑源文件中的 Info 命令后，需要先重新构建才能更新快照。

Info 协议当前为 `5.0.0`，artifact manifest 为 `5`，snapshot payload 为 `4`，录制协议为 `0.0.0`。完成清单在 `.ProofScript/info/index.json`，模型 Schema 在 `.ProofScript/info/schema/models.json`。不完整、摘要不一致或版本不支持的缓存会被拒绝。

命名 proof artifact 还包含只读字段 `proofDependencies`，记录最终证明直接引用、且在同一冻结视图下属于源定理项目的定理声明名。`projectId` 来自该定理自身的冻结归属，不使用导出器的活动项目。名称使用无损数组编码，`proofFactsDigest` 绑定这些事实、源证明和快照。它们不是 `theorem_info` 的可编辑配置，也不由 `referenceCollection` 决定。旧版 bundle 或缺少证明事实的缓存必须重新通过 Lean 导出。

项目名在 Lean 内部和 JSON 中均为字符串，例如 `{"kind": "project", "target": "代数学 · 上册"}`；定理归属 `project` 和产物清单 `projectId` 也直接使用字符串。其他目标仍保存为 `Name`，导出为分量数组，例如 `{"kind": "theorem", "target": ["Nat", "add_comm"]}`；数字分量保留为 JSON 整数。变量和短语的字面量键保存为单个字符串分量，例如 `"forall"` 导出为 `["forall"]`，`"A.B"` 导出为 `["A.B"]`。旧版导出需要重新构建。

## 10. 查询与字段定义的权威来源

配置通常由页面自动消费；需要在 Lean 中主动检查时可以调用强类型查询。以下示例同样要求页面模式，验证模式会跳过 `project_info`，因此不能据此查询到 `"Notes"`：

```lean
project_info "Notes" { title := "查询示例" }

open Lean Elab Command ProofScript.Info
run_cmd do
  let env ← getEnv
  let query : Query := { moduleName := env.mainModule }
  match resolveProjectInfo env query "Notes" with
  | .ok info => logInfo info.value.title
  | .error error => throwError error.render
```

六类查询分别为 `resolveProjectInfo`、`resolveTheoremInfo`、`resolveScriptInfo`、`resolveDefinitionInfo`、`resolveVariableInfo`、`resolvePhraseInfo`，均使用显式 `Query`。不要用导出器自身的模块名代替被查询模块。

字段类型与默认值以领域结构体为准，字段规则由对应 `InfoSchema` 实例提供，配置种类和依赖查询由 `InfoSpec` 定义：

| 内容 | 源文件 |
| --- | --- |
| 项目模型、活动项目 | [Info/Project.lean](../ProofScript/Info/Project.lean) |
| 定理模型、首次归属 | [Info/Theorem.lean](../ProofScript/Info/Theorem.lean) |
| 脚本模型、嵌套模板、契约检查 | [Info/Script.lean](../ProofScript/Info/Script.lean) |
| 表达式模型、样式、条件默认值 | [Info/Definition.lean](../ProofScript/Info/Definition.lean) |
| 变量和短语模型 | [Info/Variable.lean](../ProofScript/Info/Variable.lean)、[Info/Phrase.lean](../ProofScript/Info/Phrase.lean) |
| 公共输入语法和类型解析 | [Info/Syntax.lean](../ProofScript/Info/Syntax.lean)、[Info/Codec.lean](../ProofScript/Info/Codec.lean) |
| 基础配置实例 | [Builtin/Script.lean](../ProofScript/Builtin/Script.lean)、[Builtin/Lean2TeX.lean](../ProofScript/Builtin/Lean2TeX.lean) |
| Mathlib 配置实例 | [Mathlib/Info.lean](../ProofScript/Mathlib/Info.lean) |

若要增加新的内置字段，应修改对应结构体，让 `deriving InfoSchema` 生成字段描述；特殊合并或校验通过生成的类型化字段句柄和 `withOverrides!` 注册为 `InfoSchema` 实例，配置处理和 JSON 解码统一使用该实例。若只保存业务附加信息，直接使用 `extra` 即可。

自定义 `xxx_info` 命令应先调用 `recordModuleBuildMode`，仅在返回 `true` 时解析配置值、校验目标并登记配置。需要 IDE 支持时，两种模式都可调用 `annotateInfoFields schema fields` 或 `annotateInfoObject schema object` 登记字段信息；声明目标在验证模式中使用 `addDeclarationReferenceInfo` 尝试登记引用。单纯使用 `whenPageBuild do` 也能保留验证模式的跳过行为，但编辑器看不到延迟动作中的语义信息。`commitInfo`、显式 renderer 依赖声明等底层环境 API 保持可用，由调用方决定是否门控。

`InfoCodec.annotate` 是独立的编辑器入口，默认不执行任何动作。`schemaCodec` 使用它递归登记嵌套字段；`Option`、数组、列表和 `optionalInputCodec` 会转发到元素的入口。自定义值类型若包含声明引用或自定义对象语法，可以实现此入口；它只能登记可识别的语义信息，不应调用 `parse`、执行配置值、提交元数据或报告无效配置，取消和资源耗尽异常应继续传播。

模型和值类型统一通过 Lean 的 `toJson` 编码、`fromJson?` 解码。`InfoCodec` 继承标准 `ToJson`，不再定义单独的 `encode`；它的 `decode` 返回结构化 `Diagnostic`，保留字段路径、数组下标和关联字段，标准 `FromJson` 实例自动调用该解码器并把诊断渲染为错误字符串。新增特殊值类型只需实现一份解码逻辑；Info 内部继续使用结构化诊断进行来源追踪。完整模型的领域消费通过相应查询，使用 `InfoSchema` 实例校验，并按 `InfoSpec` 查询依赖。
