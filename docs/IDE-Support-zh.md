# IDE 与语言服务器支持

ProofScript 使用 Lean 自带的语言服务器。声明目标、脚本规则、局部变量和已知配置字段会登记语义信息，因此可以悬停查看类型、跳转到定义、查找引用和高亮同一符号。

这些信息在验证模式和页面模式中都会生成。验证模式仍不解码或校验页面配置，不执行录制器、资源编译或导出；未知的页面配置目标仍可被跳过。配置字符串、枚举文字和 `extra` 中的自由键按各自的字面量规则处理，不按同名 Lean 声明解析。

## 交互范围

| 输入 | 关联对象 |
| --- | --- |
| `def_info`、`theorem_info` 的目标，`def_info.alias` 中的声明名 | 实际解析到的 Lean 声明 |
| `script_macro` / `script_elab` 的注册 ID、`script_recorder` / `script_info` 的对应 ID、脚本调用关键字 | 该注册的同一个源 parser 声明 |
| 脚本配置 `intro`、`clear`、`params` 中的参数名 | 对应规则的语法参数绑定 |
| `have`、`claim`、`intro`、`contra`、`funext`、解包等步骤引入的名字 | 当前局部上下文中的变量 |
| Info 的内置字段和嵌套对象字段、定理内联 `info` 字段 | 配置模型中的结构字段；字段名支持补全 |
| 页面组件的 `title` / `label`，`@computation` 的函数名 | 对应结构字段或 Lean 声明 |
| `@theorem`、`@lemma` 的名字、类型、参数和证明项 | Lean 原生定理及其局部绑定 |

脚本注册的 IDE 身份使用已有的 `sourceKind`，不会另外占用注册 ID 对应的 Lean 常量名。同关键字的重载各有自己的身份。录制器和导入后的规则仍使用原注册的身份。

录制参数时的临时 elaboration 会回滚编辑器信息；`embed` 重放其他证明时也不会把原证明的源码位置登记到调用文件中。实际执行步骤、调用参数和结果变量仍保留语言服务器信息。

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

自定义页面命令可以在 `whenPageBuild` 外登记编辑器信息，再在其中执行配置与资源工作。Info 模型可调用 `ProofScript.Info.annotateInfoFields` 或 `annotateInfoObject`；组件元数据可调用 `ProofScript.addComponentMetadataInfo`。自定义 `InfoCodec` 的 `annotate` 钩子只负责语义注释，不应调用 `parse`、校验、求值或写入配置状态。Option、数组、列表和结构 codec 会递归转发该钩子。

## 回归检查

```sh
lake build ProofScript Test ProofScript.Script.Embed
python3 -m unittest Test/test_language_server.py -v
lake build TestPage:pageTests
```

语言服务器测试通过真实 JSON-RPC 请求检查高亮范围、定义目标、悬浮信息、字段补全和目标状态，并覆盖验证、页面录制和导入规则。测试包含 Basic 的全部 47 个注册、Mathlib 的全部 26 个注册以及 `embed`。页面输出写入临时目录。脚本注册清单与测试样例同步检查，新增脚本时需要补充可执行样例。
