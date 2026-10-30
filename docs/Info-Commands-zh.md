# Info 命令使用手册

本文介绍当前五种 Info 命令的输入语法、全部内置字段、更新规则和展示行为。文中的“保留字段”指框架认识并检查类型的内置字段；其它顶层字段作为附加信息保存到 `extra`。

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
| `def_info 声明名 { ... }` | 已存在的 Lean 常量 | 表达式排版与类型的变量前缀 |
| `phrase_info "短语键" { ... }` | 非空字符串 | 多语言表达式短语 |

### 构建模式

普通 `lake build` 和 IDE 默认使用验证模式：五种 Info 命令均不做字段解码与语义校验、不登记 Info 配置事件。命令语法仍须能够解析，同一模块也不能在使用这些命令后切换 `proofScript.pageBuild`。

两种模式都会保留 IDE 语义信息：`def_info`、`theorem_info` 的声明目标，以及 `def_info` 的 `«alias» := some 声明名` 支持悬停、跳转、同名引用联动和声明名补全；`script_info` 的注册 ID 与对应 `script_macro` / `script_elab` 定义使用同一个符号身份。内置字段名（包括模板、样式、颜色等嵌套对象）链接到配置模型的对应字段，并提供字段名补全。验证模式只尝试登记这些引用，未找到或有歧义的目标不会使构建失败，也不会执行配置值中的 Lean 代码。字符串项目 ID、短语键、枚举值及附加字段仍按各自的字面量语法处理。

脚本、页面命令和自定义扩展的语义信息约定见 [IDE 与语言服务器支持](IDE-Support-zh.md)。

为减少编辑时的开销，保持默认的 `proofScript.pageBuild = false` 即可：InfoTree 标注独立保留，配置值解码、持久化配置事件和页面导出均跳过。无需把 `theorem_info` 等命令重新定义成 `pure ()`；同名空实现会同时绕过编辑器标注，并影响导入它的模块。共用源码通常不必显式固定该选项，页面构建目标会按需启用它。

`lake build MyLibrary:ps4html` 自动启用页面模式，五种命令才执行下文描述的解析、校验、更新和合并。该构建会在隔离目录中重编译所需用户源码、ProofScript 框架及配置依赖，恢复基础策略 renderer、Lean2TeX 和 Mathlib 展示默认值。普通验证 `.olean` 中没有被跳过的配置，不能只在下游打开开关后恢复它们。

除导入示例外，下文每个 Lean 代码块均以 `import ProofScript` 和页面模式为前提。仅实验当前模块配置时，可以在首个 Info 或页面命令前写 `set_option proofScript.pageBuild true`；它不会重新执行已按验证模式编译的导入模块中的默认配置，完整页面应使用 Lake facet 构建。`{ ... }` 等带省略号的语法表示只在行内说明中使用。

模型、schema、配置 codec、查询函数及显式底层录制 API 在两种模式中均可使用。这里的 codec 指 Info 配置值的解码器，不是录制参数的读取器。查询只能读取实际登记的配置，不能恢复被跳过的命令；显式录制可以独立记录数据，完整页面导出仍需要相应展示配置。

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

五种命令都具有 `extra`，默认 `{}`。未知顶层字段自动进入这个容器：

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
| `project` | Option String | `none`；未赋值时在最终消费时推导 | 项目归属 |
| `name` | String | `""` | 人类可读的展示名 |
| `tags` | List String | `[]` | 分类标签；更新时整体替换 |
| `extra` | ExtraFields | `{}` | 附加元数据 |

定理项目归属在消费模块最终配置时确定，不在声明或首次 `theorem_info` 时捕获活动项目。显式的 `project` 赋值优先；完全没有赋值时，使用该定理首次登记模块本地登记的唯一项目 ID；本地没有项目时，使用该模块传递导入闭包中的唯一项目 ID。`#page theorem` / `#page lemma` 在定义模块登记，普通 Lean 声明在首次 `theorem_info` 所在模块登记。存在多个候选项目时，必须用 `theorem_info ... { project := "项目ID" }` 明确归属。无法确定项目的命名证明不能导出项目内依赖。

后续只修改名称、标签会保留已有的显式归属。`project := none` 和 `project := reset` 都明确解除归属，不触发项目推导。`project_info` 选择的活动项目仍用于省略目标的 `project_info` 命令，不再靠“最后一次选择哪个项目”决定定理归属。

```lean
project_info "First" { title := "第一项目" }
theorem sample : True := True.intro
theorem_info sample -- 空字段配置，不捕获此处的活动项目

project_info "Second" { title := "第二项目" }
theorem_info sample { name := "示例" }
theorem_info sample { project := "Second" } -- 两个本地项目，显式选择；some "Second" 也可以
theorem_info sample { project := none }   -- 解除归属
```

`theorem_info` 是定理展示元数据的唯一配置入口，放在目标声明之后，设置定理自身的标题、标签和项目。所有页面内容读取本模块与传递导入模块的最终配置，包括 `#page end` 后的更新：

```lean
#page theorem reflexive (n : Nat) : n = n := script
  rfl
theorem_info reflexive { name := "自反性", project := "Paper" }
```

`#page lemma` 使用相同方式配置。定理声明与 `theorem_info` 是独立命令，元数据更新不参与证明声明的事务。后续同名 `theorem_info` 可继续覆盖字段。原生 `/-- ... -/` 文档注释仍会传给 Lean theorem，供编辑器悬停等功能使用，与页面元数据独立。

`#page theorem` / `#page lemma` 是宏：先由 `script_theorem_impl` / `script_lemma_impl` 生成不同名的内部 `def`，同步检查证明，再发布直接引用该 `def` 的原生 theorem，保留 IDE 的编译通过标记。证明只执行一次，失败时统一提示“证明存在错误”。原生文档注释与页面元数据都属于公开定理，内部声明不作为页面定理或依赖节点导出。

两种构建模式都使用上述声明结构。普通构建和 IDE 跳过录制和导出；`cite` 在两种模式下都检查完整参数是否为命题证明，不要求 `theorem_info`。五种 Info 命令在普通模式也跳过字段解码、语义校验和登记，同时保留已有目标和已知字段的编辑器信息。`lake build MyLibrary:ps4html` 自动启用页面模式，并重编译所需用户源码、框架及配置依赖，恢复完整的模块配置与证明记录。

依赖图的上半部分列出当前声明使用的定理或引理，下半部分列出使用当前声明的定理。`#page lemma` 可以出现在上半部分，也具有自己的依赖图，但不会作为下半部分的下游目标出现。该规则只影响展示，实际证明依赖仍完整保存。

项目引用在最终消费前必须由 `project_info` 配置，可以在定理或 `#page end` 之后补充。页面中的定理 `name` 为空时使用声明末段名称；文献列表有自己的默认标题。`theorem_info` 本身不创建页面组件；页面定理通过 `#page theorem` / `#page lemma` 声明，文献列表通过 `#page references` 插入。未配置元数据的声明不会自动作为已登记文献展示。

## 5. `script_info`：脚本步骤与策略展示

### 5.1 目标是注册 ID

```lean
script_macro finishDoc "finish_doc" proof:term => `(tactic| exact $proof:term)
script_info finishDoc {
  template := [{ lang := "zh", tag := "完成证明", content := "${proof}" }]
}
```

`finishDoc` 是 `script_macro` 的注册 ID，`finish_doc` 是用户写脚本时使用的关键字。完整 ruleId 为“定义模块名 + 注册 ID”，不由声明时的 Lean namespace 决定。

单段 ID 只在当前模块中查找，不进行普通 Lean 名称解析。配置导入规则时使用完整 ID，例如：

```lean
script_info «exact» {
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

完全没有配置记录时，普通注册会获得 `lang := "zh"`、以脚本关键字为标签、内容为空的默认模板；`kind := strategy` 的注册使用动态 `strategy` 渲染器。一旦创建了配置记录，就必须满足该记录的完整性要求。例如给一个全新普通规则仅配置 `display := false`，并不能替代所需模板。

### 5.3 普通模板

| 字段 | 类型 | 默认值/要求 |
| --- | --- | --- |
| `lang` | String | 必填且非空；不限定为 `zh` / `en` |
| `tag` | String | 必填；步骤标签，可为空字符串 |
| `content` | String | 必填；步骤正文，可为空字符串 |

```lean
script_info «change» {
  template := [
    { lang := "zh", tag := "改写目标", content := "改写为 ${equation_before}" },
    { lang := "en", tag := "Change the goal", content := "${equation_before}" }
  ]
}
```

渲染时先精确匹配语言，找不到则使用有效模板数组的第一项。增加其它语言不会删除已有语言；同语言更新替换整条模板，不能只写 `content`。

### 5.4 策略模板、case 与介绍段

模板对象出现 `cases` 时按策略模板解析；否则按普通模板解析。模板种类必须与脚本注册的 `kind` 属性一致。

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
script_info «split_and» {
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
script_info «contra» {
  template := [{
    lang := "zh", tag := "反证法", inline := true,
    introducer := { tag := "假设", content := "假设 ${hypothesis}，导出矛盾" },
    cases := [{ name := "proof", tag := "", title := "" }]
  }]
}
```

### 5.5 `${...}` 占位符与实际记录数据

脚本模板读取的是 recorder 输出字段，不是任意 Lean 局部变量，也不是 `script_info.extra`。可用字段取决于具体注册与 recorder，例如 `${h}`、`${equation_before}`、`${$goal_before}`。普通参数默认在执行前后分别记录；`intro` 参数只在执行后读取，`clear` 参数只在执行前读取；strategy 的 `intro` 参数跳过自动读取。手写 recorder 的字段和时机由语句决定，不要仅根据输入参数名推测输出字段名。

PS4HTML 支持 `${字段}`、`${对象.成员}`、`${数组.0.成员}`，数组下标从 0 开始；不支持表达式求值或方括号索引。完整字段名优先匹配，再按点分路径。

Lean 原样保存并导出普通模板的 `tag/content`、介绍段的 `tag/content`、策略标题和 case 的 `tag/title` 字符串，不解析或校验其中的 `${...}`。未知字段、未知路径、空占位符 `${}` 和未闭合的 `${unclosed` 均不会因字符串内容被 Lean 拒绝。模板外层结构、必填字段、语言、case 以及普通/策略模板与注册类型是否相符等检查仍然保留。

占位符的解释与错误处理由渲染端负责。PS4HTML 在消费实际步骤时读取记录数据，包括 bundle 加载时的数据校验，对非空闭合占位符中的缺失字段或无效路径报错；遇到 null 时停止路径读取并显示 `—`，数组以逗号连接，表达式交给 Lean2TeX。表达式值的内部结构不作为模板路径开放。空或未闭合占位符按普通文本显示，模板文本均进行 HTML 转义；当前没有专门的占位符转义语法。仓库外的消费端须自行实现对应解释与错误处理。

普通步骤的默认适配器提供 `$goal_before`、`$goal_after` 两个框架可空表达式字段；策略的默认适配器只提供 `$goal_before`。手写 recorder 不保证提供这些字段，占位符须以实际记录数据为准。修改 `script_info` 不会修改 recorder、执行入口或调用契约。`display := false` 仍须满足配置完整性与普通/策略类型要求；PS4HTML 会检查隐藏策略的真实 `$branches` 结构。

表达式字段保存原生 `Expr`。默认读取函数沿其结构在 `MData` 中始终注记自由变量名称 `ProofScript.userName`、命名类型描述 `ProofScript.type` 及可获得的可信源码位置 `ProofScript.sourceFile/sourceStart/sourceStop`。所有标量元数据（包括自定义键）始终导出，没有启用开关；源码位置缺失时不添加对应三个字段。参数与已有 Lean 值统一通过 `RecordValue` 实例转换；手写 `script_recorder` 可选择捕获逻辑，`script_info` 只配置这些记录的展示方式。

`ProofScript.type` 是命名提示字符串，不保存完整类型表达式。默认 reader 为自由变量以及 `lam`、`forallE`、`letE` 的绑定节点生成此注解；绑定节点描述的是被绑定变量的类型。

| 描述 | 含义 |
| --- | --- |
| `proof` | 变量的类型是命题，如 `h : P` 或 `h : ∀ x, P x` |
| `decl:<完整声明名>` | 类型的应用头是声明常量，如 `List Nat` 对应 `decl:List` |
| `sort:Prop` | 变量本身是命题，如 `P : Prop` |
| `sort:Type` | 变量的类型是其余 Sort，如 `α : Type` |
| `function` | 非命题的函数或依赖函数类型 |
| `unknown` | 其余类型形状，如 `x : α` 的类型头为局部变量 |

分类先判断类型是否为命题，再检查结构；除证明判定所需的查询外，不为寻找类型头展开定义。依赖绑定和 let 的查询使用临时局部上下文，记录仍保留原来的 bvar、绑定名和索引。已有外层 MData 优先；自定义 recorder 直接返回 `RecordedValue.expression expr` 时仍原样记录，由其自行提供注解。编码器只导出标量，不查询上下文。

导出器识别每个表达式出现位置的有效 `ProofScript.type`：值为 `decl:<完整声明名>` 时，将该声明加入 `definition` 配置依赖。即使只记录了一个 fvar、结构中没有出现它的类型常量，也能冻结当时的 `def_info.var_name`。嵌套注解只使用最外层同名键，不把注解继承给结构子节点；共享节点的不同出现位置分别读取其注解。普通 JSON、无关元数据和被覆盖的内层类型注解不增加依赖，类型注解也不增加文献引用。渲染器已据此选择匿名变量的前缀，具体编号和显示规则见第 7 节。

手写 recorder 使用 `record_param` 按语句顺序读取实际参数，使用 `record_value` 转换已有或计算所得的值；两者共用内部写入函数，但分别打开 `ProofScript.ParamRecorder` 与 `ProofScript.ValueRecorder` 的 scoped `RecordValue` 实例，容器实例由元素实例决定是否可用。这是默认可见性约定，不阻止调用方显式打开另一个 scope。`RecordValue.record value context` 执行转换；`RecordContext := Option MVarId`，`none` 保留调用处上下文，`record_param "field" value (goal := name)` 解析 `Name` 类型的目标名称后传入 `some goal`。`record_goal "field"` 读取主目标；`record_goal "field" (goal := name)` 同样按名称解析并读取指定目标。上述操作都只记录值，表达式及其数组、对象也不写入文献引用暂存区，不受 `dependencyCollection` 影响。渲染所需的配置依赖仍由导出器单独解析。每项记录的临时 elaboration 状态始终恢复；真实读取或转换失败会附带字段名抛错，不能降级为 `null`；缺失的 `Option` 值仍是合法的 JSON `null`。需要让连续记录在后续失败时整体回滚时，用 `withRollback` 包住这些语句。同一步骤内后一次成功写入同名字段会覆盖前一次值，失败写入保留此前的值；录制键名直接写入记录，展示所需字段及值结构由 PS4HTML 检查。完整 API 与目标快照示例见[录制 API 示例](../examples/recording/RecordingAPI.lean)和[录制器说明](../README-zh.md#自定义脚本策略)。

内置 `let x := value` 和 `let x : Type := value` 在定义发生时记录 `name`（普通字符串）、`type`、`value`（表达式），并提供 `$goal_before`、`$goal_after`。这些字段可由 `${name}`、`${type}`、`${value}` 展示；后续自由变量引用不重复保存定义信息。

`change`、`exact_proj`、`provide` 的模板分别读取 `${equation_before}`、`${value_before}`、`${data_before}`；位置参数同样使用时机后缀，例如 `${loc_before.hypotheses}`。普通参数默认提供执行前后的两个字段；需要自定义记录顺序或字段名时使用手写 recorder。内置 recorder 的字段、时机及引用边界见[第六阶段迁移说明](Script-Binding-Phase6-zh.md)。

### 5.6 颜色

`color` 只保留三个 Option 颜色字段：`tag`、`border`、`background`，各自默认 `none`。颜色只能写 `#RGB`、`#RGBA`、`#RRGGBB` 或 `#RRGGBBAA`；输入使用 `some "#..."`，不接受 CSS 颜色名称。

```lean
script_info «exact» {
  color := {
    tag := some "#166a80",
    border := some "#9ac7d0",
    background := some "#eff8fa"
  }
}
script_info «rfl» {
  color := (some "#166a80", none, some "#eff8fa")
}
```

三元组的顺序是标签、边框、背景。后续只写一个分量会替换整个 `color`，其余恢复 `none`。

### 5.7 全部 renderer 取值

| 枚举输入 | 用途 | 需要的录制字段 |
| --- | --- | --- |
| `none` | 使用普通或策略模板 | 由模板占位符决定 |
| `«strategy»` | 按实际分支动态展示策略 | 策略注册，运行时有非空 `$branches` |
| `«calc»` | 等式/关系计算链 | `init`、`chain` |
| `«infer»` | 命题推导链 | `init`、`chain` |
| `«media»` | LaTeX/SVG 资源 | `metadata`、`svg`、`source` |
| `«diagram»` | 内联 SVG | `code` |
| `«remark»` | 备注 | `text` |
| `«admit»` | 未完成证明说明 | `reason` |
| `«embed»` | 嵌入证明 | `theorem`、`args`、`argKinds`、`proof`、`h`、`type` |
| `«unrecorded»` | 保留 ruleId `ProofScript.unrecorded` 的红色“未导出数据”提示 | `name`；策略分支仍展示 |

```lean
script_info «renderCalc» { renderer := «calc» }
script_info «constructor» { renderer := «strategy» }
```

专用 renderer 使用自己的展示逻辑；同时配置的模板仍须满足外层结构与普通/策略类型要求，但其字符串不由 Lean 解析，也不参与该 renderer 的输出。`strategy` renderer 的内建布局在语言为 `zh` 时使用中文，其余语言使用英文，不采用普通模板的语言回退规则。自定义策略未登记专门布局时，以 ruleId 末段为标题、实际分支名为标签。

后端根据实际记录数据检查上述必要字段及其形状，Lean 不再维护 renderer 所需输出字段的声明。设置 renderer 不能让缺少数据的 recorder 自动输出这些字段，也不能把普通注册变成策略注册。

## 6. `def_info`：表达式排版

### 6.1 顶层保留字段

目标是已存在的 Lean 常量。它控制该常量及其应用如何展示，不改变 Lean 定义或数学含义。

| 字段 | 存储类型 | 默认值/消费规则 |
| --- | --- | --- |
| `var_name` | String | `""`；独立保存该类型的变量前缀 |
| `kind` | Option DefinitionKind | `none`；普通模式通常取 `const`，有 `calc_symbol` 时取 `relation` |
| `auto_arity` | Bool | `true`；自动选择可展示的显式参数 |
| `styles` | Option (Array DefinitionStyle) | `none`；可由 `calc_symbol` 生成，否则使用默认名称显示 |
| `calc_symbol` | Option String | `none`；非空关系符号 |
| `unwrap` | Option Nat | `none`；直接展示某个原始应用参数 |
| `«alias»` | Option DeclarationRef | `none`；复用另一声明的配置 |
| `extra` | ExtraFields | `{}` |

`kind` 全部取值为 `«const»`、`operator`、`relation`、`logic`、`projection`、`constructor`、`«type»`。它是展示分类，不会自动推导参数、优先级或模板。

`kind`、`arguments`、`styles` 可直接写裸值；`calc_symbol`、`unwrap`、`alias` 使用 `some ...` 或 `none`。`styles := []` 是显式空列表，禁用自定义样式，也会阻止从 `calc_symbol` 自动生成样式；它不等于 `styles := none` 或 `styles := reset`。

所有顶层字段均可省略，`def_info Nat {}` 和 `def_info Nat { var_name := "n" }` 都合法。`{}` 是空补丁，保留已有配置；显式 `var_name := ""` 清空前缀。前缀独立于表达式的样式、别名和 unwrap，不沿显示别名继承。

Python 配置通过 `variable_prefixes` 按声明名提供该产物快照中的 `var_name`。匿名变量根据有效 `decl:` 注解查询该前缀；为空或未配置时，取声明名最后一个分量的首字母，保留大小写。例如 `Foo.Bar` 使用 `B`，`Foo.«A.B»` 使用 `A`。`proof` 固定使用 `h`，不读取 `theorem_info`。

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
  styles := [{
    template := "#0\\oplus #1",
    fixity := «infix», precedence := 65, associativity := left
  }]
}
```

`auto_arity := true` 时，系统按声明签名自动选择显式参数，模板中的 `#0`、`#1` 对应选择后的展示参数。`auto_arity := false` 时，模板索引直接对应完整 Lean 应用参数的原始索引；`binders` 与 `isolated_arguments` 使用同一索引语义。

`auto_arity := true` 在冻结配置时按目标声明原生 `forallE` 的 binder 标注计算参数索引；隐式、严格隐式和实例参数不选取。`auto_arity := false` 使用实际应用中的全部原始参数。实际应用参数数量及 lambda 形状仍由后端检查。

### 6.3 每个 style 的全部保留字段

| 字段 | 类型/取值 | 默认值 | 用途 |
| --- | --- | --- | --- |
| `name` | String | `"formula"` | 样式选择名 |
| `mode` | `formula` / `text` | `formula` | 数学公式或文本模式 |
| `template` | String | 必填 | 排版模板 |
| `fixity` | `atom/prefix/postfix/infix/binder/application/custom` | `custom` | 括号处理的布局类别 |
| `precedence` | Nat，0–100 | `100` | 越大结合越紧 |
| `associativity` | `left/right/none` | `none` | 相同优先级中缀表达式的结合方向 |
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
| `@0` | 使用参数 0 的第一个 lambda binder |
| `@@0` | binder 数量为 1 时，使用去掉该层 lambda 后的正文 |

`auto_arity := true` 时，所有 `#N` 和 `@...N` 引用的展示参数编号须从 0 连续，允许重复引用。`auto_arity := false` 时，编号直接对应原始应用参数，可以跳过未展示的参数。动态 `#*` 模板不再支持。

```lean
def_info List.map {
  styles := [
    { template := "\\operatorname{map}(@0\\mapsto @@0,#1)", binders := [(0, 1)] },
    { template := "\\operatorname{map}(#0,#1)" }
  ]
}
```

上例先尝试第一个参数至少为一层 lambda 的样式，再使用不依赖 lambda 的普通样式。`binders := [(j, n)]` 可配合最多 `n+1` 个 `@`；对于恰好 n 层 lambda，依次得到各层 binder 和最终正文。当前最后一级若仍遇到 lambda，会取该层 binder 名，编写深层模板时应按实际表达式形状选择。

非空样式数组至少需要一个不含 `@` 的样式。`@` 引用必须具有相应的 `binders` 配置。固定参数模式中的 `isolated_arguments` 必须是模板实际引用的参数。

### 6.5 动态参数

```lean
def InfoDocPack (a b c : Nat) := a + b + c
def_info InfoDocPack {
  kind := constructor,
  auto_arity := false,
  styles := [{ template := "\\langle #0, #1, #2\\rangle" }]
}
```

`auto_arity := false` 让模板索引直接对应完整原始应用参数。参数数量固定时可以用 `#0`、`#1`、`#2` 等显式列出；动态 `#*` 不再支持。

### 6.6 `calc_symbol` 简写

```lean
def_info Eq { calc_symbol := some "=" }
def_info LE.le { calc_symbol := some "\\le" }
```

有 `calc_symbol` 时默认分类为 `relation`。没有显式 `styles` 时，渲染器直接以该符号进行二元中缀渲染，默认优先级为 50、结合方向为 `none`；配置阶段不会生成模板。

没有显式样式的关系渲染要求实际应用提供两个展示参数；参数选择由 `auto_arity` 决定。若已经显式提供 `styles`，则使用显式模板；`calc_symbol` 仍作为关系元数据保留。

### 6.7 别名与 unwrap

```lean
def InfoDocWrap (n : Nat) := n
def InfoDocEqual (a b : Nat) := a = b
def_info InfoDocWrap { unwrap := some 0 }
def_info InfoDocEqual { «alias» := some Eq }
```

`unwrap` 选择完整原始应用的某个参数，不经过 `arguments` 筛选。`alias` 沿目标配置链解释当前应用，不展开 Lean 定义；目标链须有配置且不能形成循环。

只有 `alias` 与 `unwrap` 互斥。它们启用时可以保留 `kind/arguments/styles/calc_symbol`，但普通展示字段暂不消费；局部类型检查仍执行。切回普通模式时清除相应 Option；没有样式时使用默认名称显示。

### 6.8 缺配置与样式回退

没有自定义显示规则时，包括空配置和仅含 `var_name` 的配置，常量使用短名展示，应用使用普通函数应用，并产生相应诊断。注册了非空样式但没有匹配样式时，产生样式诊断并只显示常量短名，应用参数不会全部保留。模板引用了实际缺失的参数时，显示 `[missing ...]` 诊断占位。

## 7. 自动变量名

```lean
def_info Nat { var_name := "n" }
def_info Int { var_name := "n" }
```

fvar 的可用名称取自当前出现位置的 `ProofScript.userName`，绑定变量取原生 `lam`、`forallE`、`letE` 的名称。空名、`_`、`[anonymous]`、Lean 内部生成名和卫生名视为匿名，普通 `_h` 保留。可用名称始终保留，用户重名不改写，也不占用自动编号。

匿名变量只读取第 5.5 节的类型描述，不从结构类型树重新分类。`decl:` 查询 `def_info.var_name`，`proof/sort:Prop/sort:Type/function/unknown` 分别使用 `h/P/T/f/v`；缺少类型注解时也使用 `v`。计数器按前缀共享，上例的 `Nat` 和 `Int` 依次得到 `n_{1}`、`n_{2}`，数字从 1 开始、始终加花括号。前缀按数学名称排版，支持希腊字母和已有下标，不按 Script 模板解释。

同一定理中的同一 fvar ID 复用已生成的名称；binder 在引入时分配一次，正文的所有 bvar 继承其名称、生成标记和绑定身份。离开局部作用域不回收编号，下一定理重新计数。转换或渲染抛出异常时恢复本次新增的计数和缓存。分开调用 `convert` 与 `render_display` 时，分配在 `convert` 成功后提交；需要整次失败回滚时使用 `render`。

自动名称显示为 `\textcolor{gray}{n_{1}}`，普通用户名称不着灰色；未赋值的表达式元变量始终显示为 `\textcolor{gray}{?}`，不编号。颜色由内部生成标记决定。变量不匹配声明宏；悬停仍按 fvar ID 或绑定 ID 联动，灰色变量只改变高亮背景和边框，文字保持灰色。同名不同变量的关联身份仍各自独立。

专用 `let` 步骤单独展示定义时记录的类型和值；后续变量引用不生成声明类型或定义值悬停提示。模板直接使用 `${subject}` 等表达式字段，由 Lean2TeX 完成命名、颜色和身份关联，无需额外处理类型注解。

内置声明前缀为 `Nat/Int → n`、`Rat → q`，由基础配置模块提供；`Real → x` 位于 Mathlib 配置模块。命题、类型、函数和证明使用固定规则，没有对应的独立名字池配置。

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

本节描述页面模式中实际登记的配置；验证模式跳过的 Info 命令不参与合并。

### 9.1 跨模块合并

五种命令使用同一套导入规则：

1. 同一模块后写覆盖前写。
2. 后代模块的赋值覆盖其导入祖先中的同字段赋值。
3. 独立导入分支修改不同字段可以合并；`template` 以语言为单位，`extra` 以键为单位。
4. 独立分支写入相同值可以共存；不同值保留为冲突，并记录双方来源。
5. 汇总模块可以通过显式赋值或 `reset` 消解对应冲突；不能依靠交换 `import` 顺序选一个值。

例如两个独立模块把同一项目标题写为不同字符串，汇总模块须重新写 `title`。若冲突发生在某种模板语言，重新写其它语言并不会消除它。普通 Lean 定理若在独立分支中首次登记，并从各分支推导出不同默认项目，汇总模块也须显式写 `theorem_info T { project := "P" }` 消解归属冲突。

这些更新属于模块环境，不是 namespace 内的临时变量；`end` 不会撤销配置。

### 9.2 模块最终配置

每份证明和页面组件都以所属模块为配置边界。模块完整编译后，导出器读取该模块及其全部传递导入模块登记的 Info，合并成最终配置：

- 本模块中位于证明、组件或 `#page end` 后的更新也生效；不按内容创建位置截断。
- 未导入的兄弟模块及下游模块不能改变本模块已经导出的配置。
- `namespace`、`section` 和 `#page end` 都不创建配置作用域。

```lean
project_info "Demo" { title := "示例页面" }
def_info Nat { var_name := "n" }

#page theorem reflexive : ∀ _ : Nat, True := script
  exact (fun _ => True.intro)

#page theorem later : ∀ _ : Nat, True := script
  exact (fun _ => True.intro)
#page end

def_info Nat { var_name := "k" }
theorem_info reflexive { name := "自反性" }
```

`reflexive` 的组件标题是“自反性”，两份证明中匿名 `Nat` 变量都使用前缀 `k`。将这些 Info 命令移到同模块中的其它位置，只要目标声明已经存在，并保持重复赋值的先后关系，最终展示不变。独立证明以及 `#page end` 后记录的证明也使用同一个模块最终视图。

`#page references` 在组件位置收集引用的声明身份，定理展示名与项目信息则在导出时使用所属模块的最终配置解析。证明导航的项目归属和依赖筛选使用相同视图。元数据不会改变已经检查的 Lean 证明、实际录制字段或脚本调用契约。

`#page theorem`／`#page lemma` 的自动文献引用在证明成功完成后统一生成，`script` 和普通 `by` 使用同一套 helper／auxiliary 展开与候选过滤。过滤严格检查常量声明的类型 `Meta.isProp info.type`：`def MyProp : Prop` 不会成为引用，保存命题证明的普通定义可以成为引用。自动项带有 `isDependency := true`，仅在 `dependencyCollection` 开启时收集。

`cite` 先通过 `Meta.isProp (inferType expression)` 检查整个参数是命题证明，再按 `Meta.isProp info.type` 过滤其中的常量。非证明参数在参数位置报错；证明定义、应用、lambda 和局部证明均可使用，无需 `theorem_info`。手动项带有 `isDependency := false`，不受 `dependencyCollection` 影响，并与自动项一起写入 `theoremRefsExt`。成功事务将自动项与手动项按名称合并到 `DeclarationFacts.proofRefs`，同名自动项优先；引用在 proof artifact、页面组件及证明文件处理成功后提交，失败时恢复此前引用和事实。普通验证模式的页面定理只检查证明，不保留页面引用或定理导出事实。

`#page references` 展示有定理元数据的引用，并保留 `isDependency` 标记；仅由 `cite` 引入的引用不会形成导航边。命名 proof artifact 的 `proofRefs` 保存完整引用集合，导航字段 `proofDependencies` 则从中筛选自动引用及同项目目标。清空页面暂存区不影响这两个持久化字段。

动态引用扩展由 `Core/References.lean` 私有管理。自定义集成通过 `getTheoremRefs`、`clearTheoremRefs`、`addTheoremRef` 操作引用，不直接改写环境扩展。`withIsolatedTheoremRefs` 为证明隔离暂存区，返回 action 期间收集的引用，并在退出时恢复外层暂存区；手动和自动引用统一经过 `theoremRefsExt`。定理命令只在事务成功后追加页面引用，持久化事实和导出规范化统一使用 Core 的 `mergeRef`。`dependencyCollection` 只控制证明完成后的自动收集，录制器和 `cite` 都不读取该开关。

`#page end` 在两种模式下都关闭页面内容收集；页面模式额外将草稿持久化到 `.olean`，不写页面 JSON。其后的页面组件在入口立即报错，组件代码不会执行；Info 命令则继续进入模块环境，并参与当前页面的最终导出。导出器直接根据草稿和模块最终配置生成页面 JSON，可重复覆盖导出，不依赖先前生成的页面文件。页面组件和证明产物通过 `snapshotId` 关联配置快照；快照按实际依赖收集配置，因此同模块的不同内容可能有不同快照 ID，但配置的模块视图一致。

无关、未消费的不完整配置不阻塞内容。被消费的配置必须在最终视图中完整且无冲突；较晚的 `script_info` 可更新较早证明的展示，但不会改写录制事实。多项目模块应通过 `theorem_info` 明确定理的项目归属，单项目模块可使用最终项目推导。独立导入分支的冲突仍遵循第 9.1 节，不以导入顺序选择结果。

多项目页面自身的默认 `projectId` 为 `null`，不会取最后一次 `project_info` 选中的项目；页面中的每份命名证明仍须明确归属，证明的项目校验不会因此放宽。

类型注解带来的 `definition` 依赖也读取模块最终配置。下游模块可为自己的内容覆盖上游展示规则；重用上游证明产物时仍使用上游所属模块的快照，下游覆盖不会反向修改它。Python 消费端按产物的 `snapshotId` 读取 `variable_prefixes`，不重放配置事件。声明名沿用无损 Name 分量编码，带点的单个分量和数字分量均保留其身份。

### 9.3 构建与缓存

页面模式下，配置命令只更新环境，不逐条写配置文件；验证模式不写入这些配置事件。配置事件、页面草稿、快照和产物清单从页面构建的 `.olean` 统一导出。页面 JSON 在导出时生成；证明和外部资源仍由编译阶段生成。普通验证 `.olean` 中跳过的配置和草稿必须通过页面重编译恢复。

完整站点使用 `lake build MyLibrary:ps4html`。已有完整导出可用 `ps4html make --cache` 重新渲染，不重新运行 Lean。缓存渲染使用绑定的快照；编辑源文件中的 Info 命令后，需要先重新构建才能更新快照。

Info 协议当前为 `9.0.0`，artifact manifest 为 `9`，snapshot payload 为 `7`，录制协议为 `0.3.0`，录制契约版本为 `2`。命名证明的事实包含 `declarationKind`，区分 `theorem` 与 `lemma`。快照的 `query` 只保存所属模块，例如 `{"module": ["MyLibrary", "Chapter"]}`；查询和产物不再提供 `boundary` 或历史序号接口。完成清单在 `.ProofScript/info/index.json`，模型 Schema 在 `.ProofScript/info/schema/models.json`。不完整、摘要不一致、带旧查询字段或版本不支持的缓存会被拒绝。旧 manifest 须通过 Lean 重新构建，不做兼容转换。

录制契约只保存 `contractVersion`、`recordingVersion`、`ruleId`、`name`、`kind`、`continuation` 六项调用元数据，不包含输出 `fields`；规则注册导出也不包含 `recordedFields`。手写 recorder 直接写入实际数据，不使用 `(fields := ...)` 声明；渲染端根据实际字段和表达式根清单解释记录，不得把缺少输出声明当作零输出字段。proof 与独立函数的结构分别见 [proof Schema](schema/recording-proof.schema.json) 和 [function Schema](schema/recording-function.schema.json)。旧契约缓存需要通过 Lean 重新导出。

命名 proof artifact 包含只读字段 `proofRefs`，每项为 `{ "name": ["MyLibrary", "lemma"], "isDependency": true }`；两个字段均必需。该数组保存完整引用，包括 `isDependency = false` 的 `cite` 项和其它项目的目标。`proofDependencies` 是导航投影，仅保留 `isDependency = true` 且在同一冻结视图下属于源项目的名称；证明定义与定理适用相同规则。`dependencyCollection false` 关闭自动引用及自动导航边，保留手动引用。`projectId` 来自源定理自身的冻结归属，不使用导出器的活动项目。

名称使用无损数组编码，`proofFactsDigest` 绑定完整引用、导航投影、声明身份及种类、项目、源证明和快照。消费端拒绝重复引用名、缺失标记、手动引用形成的导航边，以及与冻结项目不一致的投影。这些事实不是 `theorem_info` 的可编辑配置。manifest `9` 不兼容旧缓存；旧版 bundle、缺少 `proofRefs` 或证明事实的缓存都必须通过 `lake build MyLibrary:ps4html` 重建。

项目名在 Lean 内部和 JSON 中均为字符串，例如 `{"kind": "project", "target": "代数学 · 上册"}`；定理归属 `project` 和产物清单 `projectId` 也直接使用字符串。其他目标仍保存为 `Name`，导出为分量数组，例如 `{"kind": "theorem", "target": ["Nat", "add_comm"]}`；数字分量保留为 JSON 整数。短语的字面量键保存为单个字符串分量，例如 `"forall"` 导出为 `["forall"]`，`"A.B"` 导出为 `["A.B"]`。旧版导出需要重新构建。

## 10. 查询与字段定义的权威来源

配置通常由页面自动消费；需要在 Lean 中主动检查时可以调用强类型查询。以下示例同样要求页面模式，验证模式会跳过 `project_info`，因此不能据此查询到 `"Notes"`：

```lean
project_info "Notes" { title := "查询示例" }

open Lean Elab Command ProofScript
run_cmd do
  let env ← getEnv
  let query : Query := { moduleName := env.mainModule }
  match resolveProjectInfo env query "Notes" with
  | .ok info => logInfo info.value.title
  | .error error => throwError error.render
```

五类查询分别为 `resolveProjectInfo`、`resolveTheoremInfo`、`resolveScriptInfo`、`resolveDefinitionInfo`、`resolvePhraseInfo`，均使用显式 `Query`。不要用导出器自身的模块名代替被查询模块。源码中的 `run_cmd` 只能查询执行到该命令时已有的环境；页面导出器在模块编译完成后查询，才能包含该模块后续登记的 Info。

字段类型与默认值以领域结构体为准，字段规则由对应 `InfoSchema` 实例提供，配置种类和依赖查询由 `InfoSpec` 定义：

| 内容 | 源文件 |
| --- | --- |
| 项目模型、活动项目 | [Info/Project.lean](../ProofScript/Info/Project.lean) |
| 定理模型与元数据更新 | [Info/Theorem.lean](../ProofScript/Info/Theorem.lean) |
| 脚本模型、嵌套模板、契约检查 | [Info/Script.lean](../ProofScript/Info/Script.lean) |
| 表达式模型、样式、条件默认值 | [Info/Definition.lean](../ProofScript/Info/Definition.lean) |
| 短语模型 | [Info/Phrase.lean](../ProofScript/Info/Phrase.lean) |
| 公共输入语法和类型解析 | [Info/Syntax.lean](../ProofScript/Info/Syntax.lean)、[Info/Codec.lean](../ProofScript/Info/Codec.lean) |
| 基础配置实例 | [Builtin/Script.lean](../ProofScript/Builtin/Script.lean)、[Builtin/Config.lean](../ProofScript/Builtin/Config.lean) |
| Mathlib 配置实例 | [Mathlib/Info.lean](../ProofScript/Mathlib/Info.lean) |

若要增加新的内置字段，应修改对应结构体，让 `deriving InfoSchema` 生成字段描述；特殊合并或校验通过生成的类型化字段句柄和 `withOverrides!` 注册为 `InfoSchema` 实例，配置处理和 JSON 解码统一使用该实例。若只保存业务附加信息，直接使用 `extra` 即可。

自定义 `xxx_info` 命令应先调用 `recordModuleBuildMode`，仅在返回 `true` 时解析配置值、校验目标并登记配置。需要 IDE 支持时，两种模式都可调用 `annotateInfoFields schema fields` 或 `annotateInfoObject schema object` 登记字段信息；声明目标在验证模式中使用 `addDeclarationReferenceInfo` 尝试登记引用。单纯使用 `whenPageBuild do` 也能保留验证模式的跳过行为，但编辑器看不到延迟动作中的语义信息。`commitInfo`、显式 renderer 依赖声明等底层环境 API 保持可用，由调用方决定是否门控。

`InfoCodec.annotate` 是独立的编辑器入口，默认不执行任何动作。`schemaCodec` 使用它递归登记嵌套字段；`Option`、数组、列表和 `optionalInputCodec` 会转发到元素的入口。自定义值类型若包含声明引用或自定义对象语法，可以实现此入口；它只能登记可识别的语义信息，不应调用 `parse`、执行配置值、提交元数据或报告无效配置，取消和资源耗尽异常应继续传播。

模型和值类型统一通过 Lean 的 `toJson` 编码、`fromJson?` 解码。`InfoCodec` 继承标准 `ToJson`，不再定义单独的 `encode`；它的 `decode` 返回结构化 `Diagnostic`，保留字段路径、数组下标和关联字段，标准 `FromJson` 实例自动调用该解码器并把诊断渲染为错误字符串。新增特殊值类型只需实现一份解码逻辑；Info 内部继续使用结构化诊断进行来源追踪。完整模型的领域消费通过相应查询，使用 `InfoSchema` 实例校验，并按 `InfoSpec` 查询依赖。
