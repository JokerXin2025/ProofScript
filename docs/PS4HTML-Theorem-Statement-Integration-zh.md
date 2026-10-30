# 定理表述接入：实现与迁移边界

## 结论

前端原型可以接入现有系统，无需引入第二套公式或变量高亮机制。本次接入覆盖
`#page theorem` / `#page lemma` 的 `:= script` 和 `:= by` 路径：在第一条证明策略执行前捕获局部上下文和目标，
将表述与证明步骤编码到同一个表达式 owner，使用同一个 Lean2TeX 实例渲染。

HTML 位于 `.proof-flip-front` 中、`.proof-children` 前；语言随现有 theorem 面板切换。
参数、条件、目标经过 HTML 转义，公式继续由 KaTeX 处理。

## 参数模板

新增 `def_info.parameter_template : Option String`，默认 `none`。例：

```lean
def_info Real { parameter_template := some "$#self\\in\\mathbb{R}$" }
def_info Set { parameter_template := some "$#self\\subseteq #0$" }
```

- 模板是文本，公式使用 `$...$`。
- `#self`：参数自由变量，经普通 fvar 渲染路径输出，包含原始身份的高亮标记。
- `#type`：参数完整类型的公式表示。
- `#N`：类型应用的第 N 个**显式**参数；`auto_arity := false` 时按完整 Lean 应用参数编号。
  依据冻结快照的 `argument_indices`，不在 Python 猜测隐式参数。
- 替换只进行一次，不重新解释插入内容。没有配置时回退为 `x : T`。
- 该字段只影响定理参数声明，普通表达式中的 `x` 仍只显示变量本身。
- 模板按原始类型头匹配，暂不继承 `alias`，也不做定义展开；普通类型表达式的 alias/unwrap 行为不变。
- 当前是单个语言无关模板；集合使用数学式 `s ⊆ A`，没有固定中文。
  需要“在 A 上的集合 s”等双语文本时，还应扩展为语言条目。

已配置 Nat、Int、Rat、Real、Set、Set.Elem。非依赖单箭头函数结构直接显示
`f : A → B`，因为箭头是 Lean 的 `forallE` 而非可直接配置的常量。

`Set.Icc` 的显式参数是两个端点，`[#0,#1]` 属于它的普通表达式模板。
`x : Set.Icc a b` 的类型经 `Set.Elem` 表示，参数模板显示 `x ∈ [a,b]`。
不能把 `[a,b]` 单独作为所有区间元素的声明，否则变量身份和成员关系都被抹去。

## 数据与高亮

录制协议升级为 `0.4.0`。证明 JSON 必须包含框架保留字段
`statement = {parameters, conditions, conclusion}`，不存在省略或 null 的合法形式。
原生 `by` 证明同样包含 statement、expressions、expressionRoots，仅省略 proof 步骤数组。
录制导出缺少已捕获的 statement 时立即失败；读取器拒绝缺失字段和旧版本。
参数保存 `variable`、`type` 表达式根以及 `instance` 标记；条件和结论也是表达式根。
这些根进入既有 `expressionRoots`、依赖收集、快照冻结和内容摘要流程。
解码器检查必需根以及参数 variable 的 fvar 形状。

高亮范围沿用 `.theorem-proof`：同一定理面板的表述、条件、目标、证明正文联动；
不同定理不会因为重用 Lean 的内部 ID 而串联。绑定变量仍有各自的局部作用域。
`#self` 不是用显示名称伪造变量；这对重名变量、匿名变量尤其重要。

## 迁移

1. 新读取器拒绝没有 statement 的旧证明，不从第一步猜测缺失的条件。
2. 获取表述必须重新执行 `lake build <Library>:ps4html`，同时重新生成页面模式的
   olean、证明、快照和摘要。只改 JSON 或复制普通 `lake build` 的 olean 不够。
   普通构建模式不会持久化 `def_info` 的页面配置。
3. recording 从 0.3.0 升为 0.4.0，导出器与前端须同步升级。由于 computation function
   使用共享的录制版本常量，其 recordingVersion 也升级为 0.4.0，结构与执行 ABI 不变。
4. Info 模型 schema 自动导出新字段，新 Python 使用缺省读取以兼容旧快照；新 Lean
   对旧持久化配置的兼容不应依赖手工迁移，推荐完整页面重建。

## 仍需处理的语义边界

- `:= by` 已导出并展示表述，证明部分仍显示源码，不生成伪造的 script 步骤。
- 只捕获证明开始时的局部上下文，结论中的 `∀`/`→` 不会被提前 `intro` 拆分。
  这样避免为了展示改变证明行为，也避免制造与后续 intro 不同的 fvar 身份。
- 隐式对象参数保留；类型类实例作为条件保留其类型、隐藏实例名。条件保持局部上下文顺序。
  任意类型类尚未自动归并成“设 A 为群”等自然语言；未配置的类可能显示底层数学常量名。
- 捕获局部上下文也可能包含 section 中最终未被定理使用的变量。精确筛选需要结合最终声明
  telescope 与最初 fvar 的对应关系，不能简单删除所有未在目标中出现的参数（它们可能出现在条件中）。
- 局部 let 的定义值尚未导出为参数定义；依赖证明项的类型、复杂 subtype/coercion、类型别名、
  依赖函数、多重函数箭头仍可能落入通用渲染，不能视为完整数学自然语言支持。
- 显示名称相同的不同 fvar 高亮不会混淆，但名字消歧仍依赖现有分配策略。
- 用户可写不含 `#self` 的模板；若省略变量，则该参数卡片没有变量本身可供 hover。
  建议对象声明模板始终保留 `#self`。

## 验证

```sh
lake build ProofScript ProofScript.Info.Snapshot
python3 scripts/test-theorem-statements.py
```

测试使用真实 Lean 页面模式录制和快照冻结，检查类型参数索引、实数/集合/区间/映射、
表述 DOM 位置、表述与正文目标的 fvar 标识一致、原生 by 定理/引理捕获、表达式根校验，
以及拒绝缺失 statement 和旧版本文档。
测试中的配置显式写在临时模块中，避免普通构建导入的 olean 不含页面配置。
尚未执行浏览器 KaTeX/指针事件验收；身份一致性已验证，交互继续复用既有 JS。
