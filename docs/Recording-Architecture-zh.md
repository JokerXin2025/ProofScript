# ProofScript 参数录制重构：目标、进度与交接

> 本文是后续会话的工作入口。更新于 2026-10-13。
> **阶段 0–6 已完成，参数录制重构已收尾。**
> 最终验证范围为当前仍存在的相关测试。完整旧测试库仍有用户删除的依赖和已停用 embed，本次不恢复这些内容。

## 1. 用户要求与工作区约束

用户希望以统一类型类管理不同语法参数的录制行为，便于扩展，允许较大架构调整。
本次已完成整个阶段 6。用户明确表示：**部分旧回归测试已被其删除，不要恢复或继续处理这些测试。**

工作区从开始就有大量用户的暂存和未暂存改动；期间用户继续调整了目录、导入及测试。
例如引用模块现在位于 `ProofScript/Core/References.lean`，不能沿用早期会话里的旧路径。
继续工作时先读当前文件，不要 reset、覆盖或清理用户改动，也不要擅自提交。
本次新增文件中有未跟踪文件，不能只看 `git diff` 判断工作是否存在。

## 2. 最终架构目标

```text
script_macro / script_elab 声明
    → parser 结构归一化（提取方式 + 参数形状）
    → 类型类 / 显式 codec 选择
    → 每次调用的 RecordingPlan
    → 上下文选择、隔离捕获、执行前后调度
    → 表达式快照合并、引用收集、记录输出
    → 版本化 JSON 与渲染消费者
```

职责边界：

- 语法层负责识别单项、数组、可选值和实际 parser 绑定结构。
- `RecordCategory` 管理命名类别；`RecordParam` 管理按形状组合的录制行为。
- codec 决定参数如何解释，例如表达式、名称、原始语法、表达式的类型。
- 计划负责时机、目标上下文、失败策略、输出字段。
- 引擎负责隔离和提交，新增类别通常不应修改核心生成器。
- 最终移除 `ParamRaw`、旧参数通道和字符串类别分派；保留必要输出兼容应在边界实现。

## 3. 已有模块与职责

目录：`ProofScript/Script/Recording/`

| 文件 | 当前职责 |
| --- | --- |
| `Shape.lean` | `ParamShape`、依赖类型 `ParamInput`、`ParamSchema` |
| `Value.lean` | `RecordedValue`、`ExprSnapshot`、`CaptureResult` |
| `Codec.lean` | 类型类、隔离捕获、表达式与类型快照、名称和文本 codec |
| `Builtins.lean` | term / ident / str / num 实例；num 输出 JSON 数字 |
| `Complex.lean` | location / rwRuleSeq / simpArgs / optConfig 语义 codec 与 schema |
| `Metadata.lean` | 声明期 schema 求值、实际输出字段契约 |
| `Plan.lean` | 时机、失败策略、上下文、codec 选项、参数闭包和计划 |
| `Engine.lean` | 捕获调度、上下文切换、引用与 JSON 提交、执行回滚 |
| `Normalize.lean` | parser 结构分析、类型化签名与归一化值的代码生成 |

同级 `Script/Recording.lean` 是运行时公共入口，导出 Engine、Builtins、Complex。
依赖方向为 Shape → Value → Codec → Plan → Engine；Builtins 与 Complex 分别依赖 Codec，
不再互相导入。Normalize 仅依赖 Shape 和命令 elaboration，Metadata 负责声明期求值。
内置 term/ident/str/num 实例显式命名，独立导入不会与复杂类别的匿名实例重名。

其他关键文件：

- `Script/Config.lean`：声明配置、注册、实例检查、自动 recorder 生成。
- `Script/Record.lean`：目标记录、步骤/策略计划适配、调用身份与策略分支解析。
- `Script/ExprJSON.lean`：`mergeExprJsonSnapshot` 将隔离快照的 `$ref` 重定位到共享表。
- `Script/Basic.lean`：内置策略声明、手写 recorder；claim 等已开始用显式上下文配置。
- `Script/JsonBox.lean`：环境扩展中的录制状态。
- `Script/Script.lean`：脚本收集、策略分支调度；分支边界由注册元数据驱动，不再特判 claim 名称。
- `lakefile.lean`：测试 roots；只为本次新增测试追加了入口，用户删掉的旧 roots 不在本任务清理范围内。

## 4. 阶段 0–3 的结果

### 阶段 0：基线与技术验证

- 梳理自动 recorder、手写覆盖、表达式表、引用与渲染调用链。
- 验证依赖类型输入、实例分派、tactic 状态恢复可行。
- 初始基线 `lake build ProofScript.Script.Record` 通过。
- 明确实例在声明生成 recorder 时解析，后加实例不自动重生成旧 recorder。

### 阶段 1：参数内核

- 实现类别、数组、optional 输入及实例组合。
- 内部区分可选值缺失与捕获失败。
- 表达式快照同时持有根 JSON、完整本地表达式表及常量引用。
- `isolatedCapture` 使用 tactic saved state，在成功/失败后恢复状态。
- 纯字面量捕获不需要目标。
- 内核验证包含 metavariable 成功/失败捕获后恢复。

### 阶段 2：计划与引擎

- `once / before / after / both`、`required / bestEffort`。
- 输出字段冲突检查，异构参数通过闭包存于计划。
- `recordStep` 接入 `runPlan`，旧策略捕获也接入新引擎。
- 隔离表达式快照合并共享表，重写根与节点内部 `$ref`。
- 阶段 4 已将普通步骤和策略调用的记录头、执行、捕获及分支初始化纳入同一回滚边界。

### 阶段 3：自动生成器

- 删除固定类别白名单及旧 `ParamRaw` 生成辅助函数。
- 支持命名类别、括号、`+`、`*`、`?`、`sepBy`、`sepBy1`，及已识别的列约束/排版包装。
- 复合序列不能默认按 term 处理，需要命名类别。
- 当时注册增加 `parameterShapes`，渲染侧暂留兼容字符串标签；阶段 6 已统一为类型化 parser 签名及结构化输入形状。
- 缺失实例和不支持 parser 的诊断分开，保留普通执行和手写覆盖。
- 阶段 3 曾用 `legacySingleton` 保留旧 ident 单元素输出；阶段 5 移除自动生成器的该配置，阶段 6 删除旧字段与引擎分支，所有自动数组保持稳定形状。
- 跨模块实例与自动 recorder 测试曾通过。

## 5. 阶段 4：已完成的实现

目标：统一参数级配置与策略上下文；用 codec 替代专用类型参数通道。

### 新声明配置

```lean
script_elab exampleName
  (params := [x(codec := name, timing := once,
                field := "label", failure := required)])
  "example_name" x:ident => pure ()
```

选项：

- `timing`：once / before / after / both。
- `codec`：default / expression / typeOf / name / "syntax"。
  `syntax` 是 Lean 关键字，当前示例使用字符串 `"syntax"`。
- `context`：main / continuation；其他名称或字符串表示分支标签。
- `failure`：required / bestEffort。
- `field`：输出字段名；both 时仍追加 `_before` 和 `_after`。

`intro`、`clear` 保留为时机语法糖；同一参数同时显式指定 timing 会报冲突。
显式 codec 当前只支持单项参数；容器继续走元素实例与组合实例，声明检查拒绝错误用法。
`name` 只接受 ident，expression/typeOf 当前声明检查仅允许 term/ident。
显式 syntax codec 不要求类别已有 RecordParam 实例。

### 上下文协议

- `ParamCapture.context`：main / continuation / branch。
- 策略声明可设置 `continuation := 1`，表示执行后目标列表中索引 1（从零计数）。该目标之前是策略证明分支；后续目标是续接或外围目标。
- `ScriptCfg`、注册元数据和 `recordStrategy` 使用 `Option Nat` 区分未声明 continuation 与显式索引；未声明时该角色不存在，不能默认使用主目标。
- 脚本收集根据注册的 continuation 索引限制证明分支数量，完成后回到父 box；支持一个或多个证明分支后的 continuation bullet。
- `recordStrategy` 已移除按 `stepName == "claim"` / `"claim_exist"` 选择局部上下文的逻辑。
- `Basic.lean` 的 claim、claimExistTwo、claimExistThree 显式配置 continuation 和对应参数角色。
- `cases_by` / `contra` 的类型记录改用计划中的 `expressionType`。
- `preTypeTerms / postTypeTerms` 专用接口及无调用方的 `legacyType` 已移除。
- 命名分支优先复用已解析的 label→goal 映射；其他标签按 exact / suffix / prefix 优先级查找，同一优先级的多重匹配报歧义。
- 缺失或歧义上下文及 resolver 异常都在隔离捕获中处理：bestEffort 输出 null，required 抛错并回滚调用。

### 已定位和修复的问题

1. `params` parser 外层还有 `scriptCfgValue` 包装；原索引导致配置被静默忽略，已修正。
2. 自动生成 elaborator 的内部 `x` 与用户参数 `x` 冲突，曾读到策略关键字。
   现在 recorder 的参数模式及引用一起重命名为 `__recordParam_<原名>`。
   `Test.RecordingConfigTest` 已验证参数名 x 的实际记录结果。
3. 显式 codec 不应被默认实例缺失阻断；预检查已跳过有显式 codec 的参数。
4. 缺失上下文不能回退到其他目标；失败应交给参数 failure 策略。

## 6. 阶段 4：收尾结果与验收

### P0：最新引擎修改已验证

- [x] 修复交接时 Engine 的最后一处缩进错误；上下文 resolver 在 `tryCapture` 内执行。
- [x] 构建 `Test.RecordingConfigTest`、`ProofScript.Script.Basic`，并完成最终定向回归。

### P1：功能验证已完成

- [x] 两个目标均有同名局部变量、类型不同，命名分支选择后导出的 typeOf 为正确类型；捕获后目标顺序保持不变。
- [x] 真实 claim、两参数和三参数 claim_exist 的执行后参数 JSON 非 null，且 `$ref` 解析到相应局部变量；测试直接执行录制脚本，不依赖 embed。
- [x] 自定义策略名的单证明分支和双证明分支均按注册 continuation 元数据调度；续接 bullet 不进入策略证明分支。
- [x] clear 语法糖在执行删除假设前导出参数，删除后的局部上下文中该假设已不存在。
- [x] 验证 20 种无效声明：不存在参数、重复选项/参数配置、intro/clear 冲突、非法 codec/容器搭配、字段冲突与保留字段、非法上下文等。
- [x] 声明校验和运行时计划共用 `validateOutputFields`，检查 field 基名、both 展开的输出名、空名和保留字段；inlineFields、旧兼容参数和新计划也共用字段命名空间。
- [x] 多重后缀匹配不再静默选中首个目标；已解析的完整分支标签仍能正确定位目标。
- [x] 无 continuation 声明、continuation 索引越界、分支缺失和 resolver 异常在 required/bestEffort 下遵循一致协议。

以上主要由 `Test/RecordingConfigTest.lean` 的 JSON 语义断言验证，包括 script_elab 和 script_macro 的配置入口。

### P2：实现已收敛

- [x] `Script/Script.lean` 中两处 claim 名称特判已移除，注册元数据决定分支边界。
- [x] 删除重复的 `paramWithCodec`，保留 `param`（实例组合）与 `explicitParam`（显式单项 codec）。
- [x] 删除 `Record.lean` 的 typeOnly、单独 snapshotTerms 路径及 `Compat.lean` 的 legacyType；仍在使用的 ParamRaw / serializeParamRaw 保留到后续阶段。
- [x] 普通步骤和策略调用均使用 `withRollback`：执行前捕获、执行后捕获或执行本身失败，会恢复记录头、box、目标及赋值、表达式表、引用、分支栈与已解析标签。
- [x] 上述回滚协议针对一次步骤/策略调用；策略后续分支证明由外层 Lean elaboration 的状态恢复管理。外部 IO 不在回滚范围内。
- [x] Config 生成器缩进和注释已整理；声明校验和生成器共用参数时机规则，没有临时诊断输出。
- [x] 现存 Normalize 测试改为复用 RecordingKernelTest 的跨模块实例，不恢复已删除的 RecordingCategoryDecl 辅助文件。
- [x] 最终定向构建和 `git diff --check` 通过，本文已更新。

**阶段 4 验收已满足：自动和手写录制使用同一计划能力；目标选择与分支调度不依赖策略名；类型捕获不再走专用通道；新引入/删除假设、continuation 和命名分支均在正确上下文中捕获。**

## 7. 阶段 5：复杂类别、内置 recorder 与消费者迁移（已完成）

- [x] `Complex.lean` 提供 location、rwRuleSeq、simpArgs、optConfig 的语义 codec 与 schema，包含短类别和完整 parser 名称的实例，不新增 Config 类别分派。
- [x] ParamSchema 支持 boolean、literal、object、union、json；RecordedValue 支持嵌套 object。快照提交与引用收集递归处理对象、数组和 optional。
- [x] Basic 的 change、simp、rw、constructor、constructor!、cite 改为自动 recorder；cases_by、contra、latex、calc、infer 使用计划 API 并声明实际字段契约。Basic 不再调用 ParamRaw / serializeParamRaw / preTerms / postTerms。
- [x] calc 保留执行时捕获的 elaborated proof，执行与录制处于同一事务；snapshotExpression 支持执行后无剩余目标的快照，calc proof 单次执行测试通过。
- [x] Embed 保持用户停用状态，不恢复功能或旧测试。
- [x] 注册与渲染元数据携带 recordedFields（name/schema/nullable）。自动字段根据 codec、field、timing 和 failure 求值；手写 recorder 可声明 `fields := #[...]`，外部未声明者导出 null 契约。
- [x] Lean 在 script_info 声明及导入后的有效规则合并时校验模板；Python 校验契约结构、实际值、注册与有效规则的一致性，支持对象/数组嵌套路径和 HTML 转义。
- [x] 证明、渲染清单、事件和有效规则升级为 0.1.0。页面/项目、计算和 Lean2TeX 事件协议仍为 0.0.0；Lean2TeX 的渲染模块清单读取入口兼容新版清单。
- [x] 自动数组在零/单/多元素时形状不变；Python recording.py 在旧 0.0.0 消费者边界按契约适配旧单元素数组，新版标量按数组 schema 拒绝。旧手写步骤缺失的复杂字段不补造，仍遵循其原 renderer/template 要求。
- [x] num 输出 JSON 数字，term 数值仍输出表达式引用。optConfig 记录显式标志、数字、字符串；需要 tactic 预期类型的配置表达式保留 syntax，不物化默认配置。
- [x] 双语 README、JSON 文档、扩展教程与 Labels 示例已更新。新增 recording-proof.schema.json，没有恢复用户删除的 proof.schema.json。

### 新发现与边界

1. 捕获期间禁止 Lean 的错误恢复（withoutErrToSorry / withoutRecover），避免未知名称被 synthetic sorry 伪装成成功快照；bestEffort / required 继续遵循引擎失败协议。
2. RecordingKernelTest 原先的 quotation 把局部 h 加上宏作用域；严格捕获暴露该测试问题，已用 mkIdent 构造实际局部名。没有恢复已删辅助文件。
3. script_info 仍按原设计在导入声明模块的证明模块生效，本模块更新供后续导入方使用。RecordingComplexRules 与 RecordingComplexTest 分离验证真实跨模块模板；两者为本次新增的 roots。
4. 新的整页测试发现 PageRenderer 定理依赖扫描缺少 re 导入，已补齐。
5. 外部 IO 不受 Lean 状态回滚管理；latex 的编译/资源写入仍位于捕获计划之外。

### 验收结果

RecordingComplexTest 验证显式/通配/缺失 location，rw 方向和空/单/多数组，simp pre/reverse/erase/star，配置标量与 typed syntax，数字/term 区分，嵌套快照重定位、隔离失败和引用保留。
实际导出覆盖数组、optional、两种 constructor、rw、simp、change/cite、calc、infer 及代码-only 证明。
Python 验证九个结构化证明的双语渲染、整个页面与两条引用、实际导出的机器 schema、清单契约一致性及故意不一致的拒绝、旧版单元素适配、新版类型/模板错误与转义。

**阶段 5 验收已满足：复杂类别通过实例扩展；自动与手写内置录制使用同一计划；真实证明、引用与渲染能消费 0.1.0 输出。**

## 8. 阶段 6：删除旧架构并完成回归（已完成）

- [x] 删除 `ParamRaw`、`ParamSnapshot`、serializeParamRaw、preTerms/postTerms 和全部兼容捕获辅助函数；删除 Compat.lean。停用 Embed 的最后一处调用改为 isolatedCapture + expression + commitValue，仅检查 API 编译。
- [x] 删除 parameterLabel / shapeLabel、旧字符串类别比较及重复 parameterShapes。ScriptTacticRegistration 只保存类型化 ParamParserSignature：支持的 parser 比较类别、容器与提取方式，复合 parser 比较 Syntax 结构，不能因两者 shape 均缺失而误匹配。
- [x] 手写 recorder 在生成 parser/elaborator 前验证签名；保留 `_` 开头源参数的绑定重命名，以及策略的内部 strategyCases:str 参数。拒绝不同类别、不同数组提取方式和不同复合 parser；相同 parser 在不同源码位置仍能匹配。
- [x] 删除 legacySingleton 字段和引擎折叠分支。旧 0.0.0 单元素兼容仅位于 Python recording.py，0.1.0 数组保持稳定形状。
- [x] 新增 `ProofScript.Script.Recording` 公共入口并整理依赖。计划与引擎依赖通用 Codec，基础和复杂实例独立导入；Normalize 不依赖运行时计划。扩展教程明确 snapshotExpression / commitValue / toJson 的边界。
- [x] 渲染模块清单的输入元数据改为 `parameters: [{name, shape}]`，shape 为 category/array/optional 或 null；删除旧字符串 kind 标签。输出契约仍使用 recordedFields，与输入形状独立。
- [x] 新增 RecordingRegistrationTest：验证外部类别与手写 override 的真实跨模块导入；模拟编辑器撤销声明、override、模板和 parser 后，用同一 ID 改为 num 重新 elaboration；注册、渲染字段和事件没有旧状态残留。持久化扩展只包含声明名称、parser/shape/schema 元数据，捕获闭包仅存在于调用计划。
- [x] RecordingKernelTest / NormalizeTest / PlanTest / ComplexTest 验证零/单/多元素、optional、执行后无目标、捕获失败、metavariable 隔离、快照重定位与引用。ConfigTest / SessionTest / NestedStrategyTest 验证嵌套、完整调用回滚、分支和 continuation。
- [x] TacticRewriteTest 的手写录制改用 required 计划与明确字段契约，并真正导出证明。Python 新增语义检查：导入后手写 recorder 的 proof 指向局部 h，重新声明后的 value 为数字 42、契约与清单一致且无旧模板；同时检查结构化输入形状。
- [x] 相关测试与双语 README、扩展教程、JSON 文档完成；没有恢复用户删除的文件。

公共 API 分层：

| 导入 | 能力 |
| --- | --- |
| `ProofScript.Script.Recording` | RecordCategory / RecordParam、RecordedValue、param / explicitParam、隔离捕获、快照与提交引擎 |
| `ProofScript.Script.Record` | recordStep / recordStrategy、调用身份与执行适配 |
| `ProofScript.Script.Config` | script_macro / script_elab / script_recorder 声明、签名与契约校验 |
| `ProofScript` | 上述能力及其他用户模块 |

**阶段 6 验收已满足：旧 Lean 参数架构已删除，注册与捕获职责分离，当前相关录制和消费者回归通过。**

## 9. 后续实现要牢记的边界

- 表达式快照必须在上下文和临时 metavariable 状态恢复前完成序列化；不能只带出 Expr 后续再解析。
- `$ref` 必须携带表并在提交时重定位；不能只使用 RecordedValue.toJson 丢掉表。
- 捕获隔离覆盖 Lean 可回溯状态，不自动撤销外部 IO / 全局引用副作用。
- 不要以“构建通过”代替检查记录字段：配置解析曾被忽略却照样编译，必须对 JSON 做语义断言。
- 扩展实例必须在步骤声明前可见；显式 codec 可以绕过默认实例，但仍须检查输入适用性。
- 工作区文件与早期会话相比已变动；只针对当前存在的文件执行回归。

## 10. 最终验证状态与复现命令

2026-10-13，阶段 6 的最终定向构建成功（3056 jobs），覆盖主库、停用 Embed 的 API 编译、18 个测试入口及跨模块规则依赖：

```sh
lake build ProofScript ProofScript.Script.Embed \
  Test.RecordingKernelTest Test.RecordingPlanTest \
  Test.RecordingNormalizeTest Test.RecordingConfigTest Test.RecordingComplexTest \
  Test.RecordingRegistrationTest \
  Test.CasesByTermTest Test.NestedStrategyTest \
  Test.RecordingReferencesTest Test.RecordingSessionTest \
  Test.RecorderSelectionTest Test.UnpackTermTest Test.ObtainExistTest \
  Test.InferRecordingTest Test.CalcTest Test.CalcExecutionCounter \
  Test.TacticRewriteTest Test.BasicRestrictionsTest
lake env lean Test/CiteTest.lean
lake env lean examples/recording/Labels.lean
PYTHONPATH=tools/ps4html python3 -m unittest \
  Test.test_recording_contract Test.test_render_layout \
  Test.test_lean2tex_configuration Test.test_latex_presentation
git diff --check
```

Python 的 51 个测试通过；CiteTest、Labels 示例和 `git diff --check` 通过。
Python 测试需先构建 RecordingComplexTest 与 RecordingRegistrationTest，使用真实导出，并在临时目录中复制整页测试的导入闭包，避开历史输出缓存。扩展教程的手写覆盖片段已在阶段 5 的临时 Lean 模块验证。
构建存在 unusedVariables / unusedTactic 警告，无录制或协议错误。

验证边界：

- Test.NativeTacticIsolationTest 依赖用户删除的 Test.SpacedRegistrationDecl，本次没有恢复，定向列表仍排除它。
- ClaimContextTest / ClaimExistTest 包含停用的 embed；真实 claim / claim_exist 由 RecordingConfigTest 独立验证。
- 用户删除的其他历史测试和 lakefile 中旧 roots 没有恢复或清理，不声称完整 `lake build Test` 通过。
- Embed 仅做删除旧 API 后的编译检查，继续保持用户停用状态，没有恢复功能测试。

**全部六个阶段已完成，无剩余重构待办。保留用户删除文件及停用 Embed 的约束。**
