# ProofScript JSON 模式

本文档规定了 ProofScript 输出的公开 JSON 格式。

内置消费者为 [`tools/ps4html`](../tools/ps4html/README.md)。证明与渲染协议使用 `0.1.0`，页面、计算和 Lean2TeX 协议保持 `0.0.0`。

机器可读的 JSON Schema 文件如下：

- `docs/schema/recording-proof.schema.json`
- `docs/schema/render-effective.schema.json`（每模块的有效 `script_info` 规则）
- `docs/schema/lean2tex-events.schema.json`（每模块由 Lean 导出的表达式渲染配置事件）
- `docs/schema/computation-pending.schema.json`
- `docs/schema/computation-bundle.schema.json`
- `docs/schema/computation-published-bundle.schema.json`
- `docs/schema/computation-index.schema.json`

以上模式均使用 JSON Schema Draft 2020-12。

## 1. 版本控制

当前证明与渲染模式版本为 `0.1.0`，其余协议仍为 `0.0.0`。本次录制协议升级改变数组与 num 的输出语义，旧数据由消费者的版本适配入口处理。

项目元数据与证明树 JSON 在顶层 `schemaVersion` 字段中嵌入版本号；页面 JSON 使用所属项目导出的版本号。

版本变更遵循以下规则：

- 补丁版本：修正文档，或调整不会改变所接受 JSON 的约束。
- 次版本：添加向后兼容的字段或组件种类。
- 主版本：以不兼容的方式更改现有字段、标签或语义。

内置消费者接受证明/渲染 `0.0.0` 与 `0.1.0`；其他协议仍仅接受 `0.0.0`。旧数组单元素输出只在旧版本边界适配；新版标量不能冒充数组。旧手写 recorder 缺失的语义字段不会被凭空补造，仍按原模板/renderer 检查。

## 2. 页面 JSON

### 2.1 位置

对于 Lean 模块 `Paper.Chapter.Main`，页面文件为：

```text
.ProofScript/pages/Paper/Chapter/Main.json
```

### 2.2 顶层对象

```json
{
  "module": "Paper.Chapter.Main",
  "source": "/project/Paper/Chapter/Main.lean",
  "components": []
}
```

字段：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `module` | 字符串 | 完全限定的 Lean 模块名称。 |
| `source` | 字符串 | Lean 报告的源文件路径。目前通常为绝对路径。 |
| `components` | 数组 | 按源码顺序排列的组件。 |

项目元数据单独导出到 `.ProofScript/project.json`，包含 `schemaVersion` 与 `ProjectInfo`。一个站点只能配置一次 `project_info`；站点构建时会拒绝多个配置。

### 2.3 源码位置

每个组件都包含：

```json
{
  "file": "/project/Paper/Main.lean",
  "start": 120,
  "stop": 180
}
```

`start` 和 `stop` 是 Lean 源文件中的 UTF-8 字节偏移量，而非行号和列号。

### 2.4 组件封装结构

```json
{
  "source": { "file": "...", "start": 0, "stop": 10 },
  "data": {
    "text": { "value": {} }
  }
}
```

`data` 是一个带标签的对象。应当恰好包含一个组件标签。

当前标签包括：

- `text`
- `theorem`
- `lemma`
- `latex`
- `figure`
- `references`
- `computation`

组件信封是开放的：模块可以添加新的标签，而无需修改 ProofScript 的页面模型。自定义命令将
组件专属的数据序列化后，通过 `addPageComponent` 提交标签、JSON 数据和
可选标签即可。`theorem` 和 `lemma` 是页面导出器特殊处理的组件，以便在 `page_end` 时解析
声明元数据。

### 2.5 文本组件

```json
{
  "text": {
    "value": {
      "source": "= Title <title>\n",
      "blocks": []
    }
  }
}
```

原始 ProofText 源码和解析后的语义 AST 均会保留。

当前的行内标签包括：

- `text`
- `strong`
- `emphasis`
- `strongEmphasis`
- `code`
- `strike`
- `underline`
- `highlight`
- `superscript`
- `subscript`
- `link`
- `reference`
- `math`
- `softBreak`
- `hardBreak`

当前的块级标签包括：

- `paragraph`
- `heading`
- `code`
- `orderedList`
- `unorderedList`
- `quote`
- `displayMath`

### 2.6 定理与引理组件

```json
{
  "theorem": {
    "value": {
      "name": "主要定理",
      "proof": ".ProofScript/proofs/Paper/Main/mainTheorem.json",
      "sorryAx": false
    }
  }
}
```

使用 `@lemma` 声明时，值结构相同，但组件标签明确为 `lemma`：

```json
{
  "lemma": {
    "value": {
      "name": "辅助引理",
      "proof": ".ProofScript/proofs/Paper/Main/supportingLemma.json",
      "sorryAx": false
    }
  }
}
```

`name` 来自 `theorem_info` 中的展示名；未指定时采用 Lean 声明的非限定名称。定理引用及 HTML 锚点
使用从 `proof` 路径确定的完整 Lean 声明名。`proof` 是独立证明树 JSON 文件的路径。`sorryAx` 表示该声明是否传递依赖 Lean 的
`sorryAx`。页面不会嵌入证明文档。`@theorem` 和 `@lemma` 均支持 `:= script` 与不受策略
白名单限制的 `:= by`。

### 2.7 LaTeX 与图片组件

```json
{
  "latex": {
    "value": {
      "metadata": {
        "title": "交换图",
        "label": "main-diagram",
        "extra": []
      },
      "language": "latex",
      "source": "\\begin{tikzpicture}...",
      "svg": {
        "$resource": {
          "path": ".ProofScript/resources/svg/123.svg",
          "hash": "123",
          "mediaType": "image/svg+xml",
          "encoding": "utf-8"
        }
      }
    }
  }
}
```

`@latex` 接受任意 LaTeX 源码并将其编译为 SVG。完整 SVG 存入引用的 UTF-8 资源文件；内容
hash 用于完整性校验，相同 SVG 会共享同一资源文件，不会丢弃任何 SVG 信息。

`@figure` 接受一个相对图片资源路径：

```json
{
  "figure": {
    "value": {
      "metadata": {
        "title": "概览图片",
        "label": "overview-image",
        "extra": [["width", "wide"]]
      },
      "path": "assets/overview.png",
      "extension": "png"
    }
  }
}
```

两类组件共用 `figure` 引用命名空间。图片路径必须是包含扩展名的相对路径。ProofScript
只记录路径和扩展名，不复制或读取图片文件。

### 2.8 计算组件

`@computation` 将 Lean 函数声明连接到带版本的下游 renderer manifest。所有参数都放在一个配置对象中：

```lean
@computation {
  metadata := (title := "有限计算"),
  renderer := "example/calculator-v1",
  function := Paper.compute,
  payload := r#"{"fallback":"等待计算资源"}"#
}
```

导出的值包含 `schemaVersion`、组件元数据、renderer ID、函数声明及其结构化表达式表、执行信息和
renderer 专用的 `payload`。函数必须是 `α → β` 或 `α → Except String β`，并且存在相应的
`FromJson α` 与 `ToJson β` 实例。elaboration 阶段会生成 pending manifest；Wasm bundle 和
页面中的 ready resource 由后续 bundler/finalize 阶段生成。相关的 pending、bundle、published
bundle 和 index 格式见 `docs/schema/` 中对应的 schema 文件。

### 2.9 引用组件

不带参数的 `@references` 命令会插入：

```json
{
  "references": {
    "value": [
      {
        "name": "Library.result",
        "info": {
          "project": {},
          "name": "显示名称",
          "label": "result",
          "tags": [],
          "extra": []
        }
      }
    ]
  }
}
```

该组件会被准确放置在 `@references` 出现的位置。插入后，引用暂存区会被清空。
`@references` 不再支持导出独立 JSON 文件。

## 3. 证明树 JSON

### 3.1 位置

证明树写入以下路径：

```text
.ProofScript/proofs/<module path>/<declaration path>.json
```

### 3.2 顶层对象

顶层对象包含模式版本、所属模块、完整 Lean 源代码、表达式表和证明步骤数组。展示配置在模块级规则文件中，proof 不包含逐次渲染结果：

```json
{
  "schemaVersion": "0.1.0",
  "module": "Paper.Main",
  "code": "@theorem mainTheorem : True := script\n  trivial",
  "expressions": {
    "e0": { "kind": "const", "name": "True", "levels": [], "isProp": true },
    "e1": { "kind": "const", "name": "True.intro", "levels": [], "isProp": false }
  },
  "proof": [
    { "_goal_": { "$ref": "e0" } },
    { "_ruleId": "ProofScript.Script.Basic.trivial" }
  ]
}
```

当 `@theorem` 或 `@lemma` 使用 `:= by` 时，ProofScript 接受任意可通过 Lean 编译的策略，
不检查策略合法性，也不记录具体步骤，而是输出代码-only 文档：

```json
{
  "schemaVersion": "0.1.0",
  "code": "@lemma supportingLemma : True := by\n  trivial"
}
```

该模式仍会直接扫描 elaboration 后的 proof term，自动采集带 `theorem_info` 的引用。

每一项均为以下逻辑形式之一。

目标记录：

```json
{
  "_goal_": { "$ref": "e0" }
}
```

步骤记录：

```json
{
    "_ruleId": "ProofScript.Script.Basic.assumption"
}
```

前后均记录的参数分别使用 `proof_before` 和 `proof_after` 等独立字段；解析失败的值为
`null`，只记录单个时点的参数保持原名。

合并策略记录：

```json
{
  "_ruleId": "ProofScript.Script.Basic.split_and",
  "branches": [{"name": "left", "proof": []}, {"name": "right", "proof": []}]
}
```

策略步骤的确切字段取决于策略及其记录器。展示按 `_ruleId` 选择模块规则；策略参数直接记录在根对象中，`branches` 内各分支以 `name` 标识。使用方应保留未知录制字段。

### 3.3 表达式值

目标和策略参数使用 `{ "$ref": "eN" }` 形式的表达式引用。`eN` 在顶层 `expressions`
对象中解析，所有被引用的条目都必须存在。表达式条目使用 `kind` 判别字段，其值包括：

- `bvar`
- `fvar`
- `mvar`
- `sort`
- `const`
- `app`
- `lam`
- `forall`
- `let`
- `lit`
- `mdata`
- `proj`

表达式表构成有向无环图。递归表达式字段（`fn`、`arg`、`type`、`body`、`value`、`expr`、
`typeOf` 以及每个 `arguments[].expr`）使用引用而非复制子树。解析全部引用后，可以无损恢复
完整表达式中的所有字段。ID 仅在当前证明文档内有效。

每个序列化表达式节点都包含 `isProp`，它通过 Lean 的 `Meta.isProp` 对该节点本身计算。
因此可以区分命题 `P`、证明 `h : P` 和数据表达式，无需根据名字或 JSON 结构猜测。

application 节点保留二叉 `fn`、`arg` 字段，并额外提供：

```json
{
  "headConstant": "HAdd.hAdd",
  "arguments": [
    {
      "expr": { "$ref": "e7" },
      "binderInfo": "instImplicit",
      "isExplicit": false,
      "isTypeclass": true
    }
  ]
}
```

`headConstant` 是完全限定声明名；函数头不是常量时为 null。`arguments` 是按调用顺序展平
的参数数组。binder 信息来自 head declaration 实例化后的 forall telescope；无法可靠匹配
时相关字段为 null。

表达式节点还可能包含 `sourceRange`，格式与页面组件相同，采用
`{file,start,stop}` UTF-8 字节偏移。只有 Lean 在表达式 metadata 中保留了源码 Syntax 时
才会输出；无法确定的位置会省略，而不会猜测。

### 3.4 LaTeX 组件步骤

证明内的 `latex` 策略与页面级 `@latex` 组件一样，接收 metadata 和任意 LaTeX 源码，
生成的步骤记录包含：

```json
{
  "_ruleId": "ProofScript.Script.Basic.latex",
  "metadata": {
    "title": "Inline figure",
    "label": "inline-figure",
    "extra": []
  },
  "language": "latex",
  "source": "\\begin{figure}...",
  "svg": {
    "$resource": {
      "path": ".ProofScript/resources/svg/123.svg",
      "hash": "123",
      "mediaType": "image/svg+xml",
      "encoding": "utf-8"
    }
  }
}
```

### 3.5 外部资源与 embed

大型不可变数据使用资源引用：

```json
{
  "$resource": {
    "path": ".ProofScript/proofs/Library/Theorem.json",
    "hash": "123",
    "mediaType": "application/vnd.proofscript.proof+json",
    "encoding": "utf-8"
  }
}
```

路径相对于项目工作目录。读取方必须读取完整 UTF-8 文件，并验证其内容 hash 与引用一致。
SVG 资源包含原始完整 SVG。`embed` 步骤引用原始完整证明文档，不再复制和重放证明树；父步骤
仍保留 `theorem`、`type`、`args`、`argKinds` 和引入的 `h` 字段，因此原有信息均可取得。

当前格式使用表达式 DAG 和外部 SVG 引用而不重复内联内容；读取方解析
`$ref` 与 `$resource` 后即可获得相同数据。

### 3.6 参数契约与结构化值（0.1.0）

渲染模块清单与有效规则使用 `schemaVersion: "0.1.0"`。每个 registration/rule 增加 `recordedFields`，值为实际输出字段契约的数组，或外部手写 recorder 的不透明 null 契约。清单与有效规则的契约必须一致。

模块清单的注册还包含结构化输入元数据 `parameters: [{name, shape}]`。
类别形状为 `{kind:"category", name:"term"}`，array/optional 通过 element 嵌套形状；
不支持自动归一化的复合 parser 导出 `shape: null`。这替代旧的字符串 kind 标签，
与渲染实际使用的输出字段契约相互独立。

输出字段契约示例：

```json
{
  "name": "rules",
  "nullable": true,
  "schema": {
    "kind": "array",
    "element": {
      "kind": "object",
      "fields": [
        { "name": "reverse", "schema": { "kind": "boolean" } },
        { "name": "expression", "schema": { "kind": "expression" } }
      ]
    }
  }
}
```

schema 种类为 expression、string、name、syntax、number、boolean、json；array/optional 带 element；object 带 fields（name/schema）；union 带非空 options 数组；literal 带字符串 value。对象值恰好包含声明的字段。expression 使用 `$ref`，与普通结构化对象区分；json 用于开放的组件/资源元数据。nullable 表示捕获失败可为 null，与 optional 表示输入缺失独立。

字段重命名与时机决定实际输出名：both 输出 `<field>_before` / `<field>_after`，其他时机输出 `<field>`。Lean 与 Python 都按实际名称和 schema 校验模板，包括 `${rules.0.expression}`、`${loc_before.hypotheses}`。optional 或失败捕获为 null 时显示 `—`；正文、字符串和结构化键名均转义。字段缺失或索引越界会报错。

复杂类别的输出：

| 类别 | 录制值 |
| --- | --- |
| location | `{kind:"location", wildcard:bool, goal:bool, hypotheses:[expression]}`；optional 未指定为 null。wildcard 捕获可见局部声明及目标角色。 |
| rwRuleSeq | 始终为 `{reverse:bool, expression:expression}` 数组。 |
| simpArgs | 始终为数组：lemma `{kind:"lemma", phase:"pre"或"post", reverse:bool, expression:expression}`、erase `{kind:"erase", name:string, expression:expression或null}`、star `{kind:"star"}`。非 term 的 simproc 擦除仍保留名称。 |
| optConfig | 始终为显式 `{name:string, value:bool/number/string/{kind:"syntax",text:string}}` 配置数组。空配置为 `[]`；需要 tactic 专有预期类型的表达式保留语法文本，不物化 tactic 默认值。 |

num 输出 JSON 数字；按 term 解析的数值仍为表达式引用。自动生成的数组在零、单、多元素时形状不变。RecordedValue 嵌套对象递归合并表达式快照、重定位引用并收集常量。

读取方兼容旧版 0.0.0 proof/rendering；按契约进行的旧单元素数组适配仅在旧版边界运行，新版标量不会自动变成数组。旧手写步骤可能没有新增语义字段，读取方仍遵循原模板/renderer 的要求，不凭空补造字段。重新构建 Lean 输出以获得复杂字段和完整契约。本次是 1.0 前明确的协议修订，不能只改旧数据的版本号。

## 4. 兼容性要求

写入方必须：

- 保持源组件的顺序；
- 以语义化版本字符串的形式输出页面 `schemaVersion`；
- 对源码位置使用 UTF-8 字节偏移量；
- 保持证明树独立于页面 JSON；
- 对缺失的可选标签使用 `null`；
- 按顺序保留 `extra` 元数据键值对。
- 输出证明记录或其他表达式节点引用的每一个表达式 ID；
- 在引用路径保留完整资源内容。

读取方应：

- 拒绝不支持的模式主版本；
- 忽略兼容的未知组件字段；
- 保留未知的证明步骤字段；
- 相对于项目工作目录解析定理的 `proof` 路径；
- 加载所有页面文件后，构建跨页面标签索引。
- 根据当前证明文档的 `expressions` 表解析 `$ref`；
- 相对于项目工作目录解析 `$resource`，并验证内容 hash。

## 5. 已知的模式限制

- Lean 表达式的序列化目前仅在结构层面进行描述，并且仍可扩展。
- 源文件路径目前通常为绝对路径。
- 自定义页面组件已被保留，但尚无法公开注册。
- 跨页面引用的有效性将由未来的渲染器检查，而非由各个 Lean 模块检查。
