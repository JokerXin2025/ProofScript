# IDE 与语言服务器支持

ProofScript 使用 Lean 自带的语言服务器。声明目标、脚本规则、局部变量和已知配置字段会登记语义信息，因此可以悬停查看类型、跳转到定义、查找引用和高亮同一符号。

这些信息在验证模式和页面模式中都会生成。验证模式仍不解码或校验页面配置，不执行录制器、资源编译或导出；未知的页面配置目标仍可被跳过。配置字符串、枚举文字和 `extra` 中的自由键按各自的字面量规则处理，不按同名 Lean 声明解析。

## 交互范围

| 输入 | 关联对象 |
| --- | --- |
| `def_info`、`theorem_info` 的目标，`def_info.alias` 中的声明名 | 实际解析到的 Lean 声明 |
| `script_macro` / `script_elab` 的注册 ID、`script_recorder` / `script_info` 的对应 ID、脚本调用关键字 | 该注册的同一个源 parser 声明 |
| 脚本配置 `intro`、`clear` 中的参数名 | 对应规则的语法参数绑定 |
| `have`、`let`、`claim`、`intro`、`contra`、`funext`、解包等步骤引入的名字 | 当前局部上下文中的变量 |
| Info 的内置字段和嵌套对象字段 | 配置模型中的结构字段；字段名支持补全 |
| 页面组件的 `title` / `label`，`#page computation` 的函数名 | 对应结构字段或 Lean 声明 |
| `#page theorem`、`#page lemma` 的公开名字与文档注释 | Lean 原生定理 |
| `#page theorem`、`#page lemma` 的类型、参数和证明步骤 | 同步检查证明的内部 `def` 及其局部绑定 |

脚本注册的 IDE 身份使用已有的 `sourceKind`，不会另外占用注册 ID 对应的 Lean 常量名。同关键字的重载各有自己的身份。录制器和导入后的规则仍使用原注册的身份。

手写录制器统一写 `script_recorder foo => do ...`，策略关键字、parser 和参数绑定均复用 `foo` 的原始声明。命令读取原注册的 `kind` 配置，自动管理录制对象和策略分支。录制器 ID 的跳转仍指向原策略声明；`intro`、`clear` 中的参数名继续关联原绑定。参数读取时机和输出字段由 `record_param`、`record_value` 等语句决定，不再通过 `params`、`timing`、`context` 或 `field` 配置。`record_param "field" value` 的 `value` 是该声明绑定的实际 Lean 值，`field` 是输出字符串键，不作为 Lean 声明解析。参数和值的录制都只保存数据，不收集文献引用，也不影响实际执行步骤的 IDE 语义引用。生成的策略分支参数由框架管理，手写录制器无需读取。

`#page theorem` / `#page lemma` 宏先生成不同名的内部 `def`，再发布直接引用它的原生 theorem。所有模式都同步检查内部证明，证明只执行一次；原生命令负责公开声明与编译通过标记。证明失败统一显示“证明存在错误”。页面模式额外完成录制与导出，内部声明不作为页面定理展示。

录制参数时的临时 elaboration 会回滚编辑器信息；`embed` 重放其他证明时也不会把原证明的源码位置登记到调用文件中。实际执行步骤、调用参数和结果变量仍保留语言服务器信息。

## 文献引用与编辑器引用

`dependencyCollection` 只控制页面构建中已完成证明的自动文献引用，以及由这些引用生成的定理导航边。它不影响 Lean 的悬停、跳转、查找引用或变量高亮，也不控制参数和值的录制。编辑器符号信息不从 `proofRefs` 或页面的动态暂存区推导。

`cite` 在验证模式和页面模式都会 elaboration 完整参数，检查其类型是否为命题；非证明参数在参数位置报错。应用、lambda、局部证明和证明定义均可使用，不要求 `theorem_info`。参数中的声明和局部变量保留正常的编辑器语义信息。它通过 Core 收集声明类型为命题的常量，标记为手动引用；页面模式将这些引用随定理导出，同名常量若也在最终证明中被自动收集，标记提升为依赖。

`#page theorem`／`#page lemma` 的引用事务由 Core API 隔离。普通验证仅检查证明，退出后恢复此前的页面引用状态，不生成页面定理的持久化引用事实。`#page references` 消费动态暂存区不会清除编辑器语义信息，也不会清除已完成定理的 `proofRefs`。完整的数据与导出边界见[统一 Info 配置](Info-Commands-zh.md#92-模块最终配置)。

## 扩展命令和脚本

普通的 `script_macro` 转发应直接复用用户的语法节点：

```lean
script_macro myIntro (intro := [h])
"my_intro" h:ident => `(tactic| intro $h:ident)
```

手写 elaborator 使用 Meta API 创建局部变量时，需要在新目标的上下文中登记定义：

```lean
let (fvarId, rest) ← goal.intro h.getId
rest.withContext do
  Lean.Elab.Term.addLocalVarInfo h (Lean.mkFVar fvarId)
replaceMainGoal [rest]
```

现有用户标识符应保留原始 syntax；`getId` 后用 `mkIdent` 重建会丢失源码位置。仅添加 `withRef` 或 tactic 状态信息，不能替代声明或变量的语义引用。

`page_component "名字" ... => do` 定义的命令通过 `#page 名字 ...` 调用。组件定义中可在 `when_page_build` 的缩进块外登记编辑器信息，再在块内执行配置校验与资源工作；整个组件在 `#page end` 之后会在入口报错。`when_page_build` 只可用于组件定义的上下文，不影响通用的 `whenPageBuild` API。Info 模型可调用 `ProofScript.annotateInfoFields` 或 `annotateInfoObject`；组件元数据可调用 `ProofScript.addComponentMetadataInfo`。自定义 `InfoCodec` 的 `annotate` 钩子只负责语义注释，不应调用 `parse`、校验、求值或写入配置状态。Option、数组、列表和结构 codec 会递归转发该钩子。
