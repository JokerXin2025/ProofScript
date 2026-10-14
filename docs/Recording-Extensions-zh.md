# 扩展参数录制

`import ProofScript.Script.Recording` 提供值、codec、内置实例、计划及捕获/提交引擎。
`ProofScript.Script.Record` 增加步骤与策略适配，`ProofScript.Script.Config` 增加声明命令；
`import ProofScript` 包含这三层。parser 归一化和声明期 schema 求值与运行时 API 分开。

完整示例：[Labels.lean](../examples/recording/Labels.lean)。在仓库根目录执行：

```sh
lake env lean examples/recording/Labels.lean
```

## 命名类别与容器

先为语法定义命名类别，再提供 `RecordCategory` 实例。实例的 schema 描述稳定输出形状，capture 解释 parser 实际产生的语法树：

```lean
declare_syntax_cat labelValue
syntax ident : labelValue

instance : ProofScript.Recording.RecordCategory `labelValue where
  schema := .name
  capture value := ProofScript.Recording.identifierName ⟨value.raw[0]⟩

script_macro recordLabels
  (params := [labels(timing := once, field := "items", failure := required)])
  "record_labels" "[" labels:sepBy(labelValue, ",") "]" => `(tactic| skip)
```

命名类别的节点包裹了内部 ident，因此这里读取 `raw[0]`。复杂类别应按自己的 parser 结构解析，不要假定所有类别都有同样的节点布局。

`RecordParam` 自动为数组与 optional 组合实例；`sepBy`、`sepBy1`、`+`、`*`、`?` 和括号由归一化层处理，不需要修改 Config。示例输出分别为 `[]`、`["alpha"]`、`["alpha", "beta"]`；optional 缺失为 null，存在时为元素值。实例应在 `script_macro` / `script_elab` 声明前可见，后加实例不会重新生成已有 recorder。

## 解释、时机与上下文

term/ident 默认录制表达式；str 是字符串，num 是 JSON 数字。按 term 解析的数值仍是表达式。location、rwRuleSeq、simpArgs、optConfig 的语义结构见 [JSON 文档](JSON-Schemas-zh.md)。optConfig 记录显式选项，tactic 专有的类型表达式保留语法文本，不计算默认值。

参数配置 `params := [x(...)]` 支持：

| 选项 | 值 |
| --- | --- |
| timing | once / before / after / both |
| codec | default / expression / typeOf / name / "syntax" |
| context | main / continuation / 分支名称 |
| failure | bestEffort / required |
| field | 输出字段名称 |

显式 codec 当前仅支持单项；容器使用类别实例组合。intro/clear 分别为 after/before 语法糖。both 在字段名后追加 `_before`、`_after`，模板必须使用展开后的名称。策略声明可用 `continuation := 1` 指定执行后目标列表中索引 1 为续接目标，之前的目标为证明分支。

捕获会恢复 Lean 状态，再将成功的表达式快照与引用提交到共享表。不要在 capture 中依赖外部 IO 回滚：文件写入、网络请求等外部副作用不会被状态恢复撤销。

## 自定义计划和字段契约

类别实例不适合描述整个步骤的执行结果时，使用 `script_recorder` 与 `recordStep` / `recordStrategy`。用 `fields := #[...]` 声明实际输出的 `OutputField`：name、schema、nullable。nullable 表示 bestEffort 捕获失败可输出 null，与 optional 表示输入缺失的含义独立。

schema 支持 expression、string、number、boolean、name、syntax、literal、array、optional、object、union、json。嵌套表达式应使用 `.expression` 快照和 `.object` / `.array` 组合；引擎会递归合并表并收集引用。`.json` 适用于组件元数据和资源引用，不用于绕过表达式快照。

```lean
script_recorder recordLabels
  (fields := #[{ name := "items", schema := .array .name, nullable := false }])
  "record_labels" "[" labels:sepBy(labelValue, ",") "]" => do
    recordStep [] (parameters := { parameters := #[
      ProofScript.Recording.param (.array (.category `labelValue))
        "items" .once (labels.getElems.map fun value => ⟨value.raw⟩) .required
    ] })
```

自动声明直接从 codec 与配置导出契约。手写 recorder 未写 fields 时导出 null 契约；已迁移的内置 recorder 均声明契约。运行时计划的字段名和声明契约必须一致。

`recordStep` 接收内联字段、`parameters` 计划及可选的 `execute` 动作；`recordStrategy` 使用同样的字段和计划，另接收分支标签与 continuation 索引。捕获闭包仅属于当前调用，持久化注册只保存声明名称、parser 签名和字段契约，跨模块导入和编辑器回滚不会保留调用闭包。

手写 recorder 在生成声明前检查签名：支持的 parser 比较类别、容器和提取方式，不支持的 parser 比较语法树结构。源参数名以 `_` 开头时，recorder 可以更换绑定名。

已 elaborate 的表达式使用 `snapshotExpression`，提交时使用 `commitValue` 合并本地表达式表。`RecordedValue.toJson` 仅用于检查值，其中的 `$ref` 仍属于快照的本地表。旧 ParamRaw 与 preTerms/postTerms API 已移除，所有捕获通过计划调度。

## 模板与协议

```lean
script_info recordLabels {
  template := [{ lang := "zh", tag := "标签", content := "${items}" }]
}
```

`script_info` 在导入声明模块的证明模块生效；当前模块的更新供后续导入方使用。模板占位符按实际字段及 schema 校验，数组索引和对象字段可组合，如 `${rules.0.expression}`。整个结构化值也可显示；文本、键名与模板正文会进行 HTML 转义，表达式通过 `$ref` 解析和 Lean2TeX 渲染。可选/失败值为 null 时显示 `—`。索引越界或缺失对象字段会报错，因此使用固定索引的模板应确保调用有足够元素。

证明与渲染导出使用 `0.1.0`，旧版本只在 Python 消费者边界兼容。新增数组不再有单元素折叠；num 不再使用文本或表达式形状。页面、计算与 Lean2TeX 事件继续使用各自的 `0.0.0` 协议。
