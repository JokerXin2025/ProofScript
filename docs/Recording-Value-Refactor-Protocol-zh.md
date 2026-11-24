# 录制值重构：协议与迁移清单

> 状态：消费端契约已收敛；本次新增的 Python 测试脚本和 Lean 测试模块已按要求移除，原先依赖它们的验收覆盖不再随仓库保留。远端 CI 尚未运行。以重新构建后的产物为准，旧产物必须重新导出。历史文档 `ProofScript-Refactor-Phase1-zh.md` 记录的是另一轮重构，不适用于本次工作。

## 1. 边界与目标

`RecordedValue` 仅表示 `script_recorder`（包括自动生成的 recorder）写入的**单个字段值**，保留 `plain Json`、`expression Expr`、`array (Array RecordedValue)`；删除 `object`。`plain` 仍可接收任意 JSON，但项目内已有的 recorder 的 `plain` 值（包括数组元素）只写 JSON 字符串或数字。显式传给 `record_value` 的第三方 JSON 不受此实现约定限制。

以下数据不是 recorder 字段值，采用各自的 Lean 模型和 JSON 编码：

| 数据 | 模型职责 | 导出关系 |
| --- | --- | --- |
| 证明步骤和策略分支 | 步骤 ID、字段集合、分支名称及子步骤 | 文档级表达式表；`$ruleId` / `$branches` 是框架字段，不能由 `record_value` 写入 |
| 定理陈述 | 参数（变量、类型、原生 Bool `instance`）、条件、结论 | 与证明步骤共享文档级表达式表；无录制步骤的证明也保留陈述 |
| 计算函数 | 声明、类型文字、表达式、实现 | 自有表达式表，不与证明共享 |

上下文相关的表达式捕获与纯表达式图编码应从 `RecordedValue` 的构造中拆开供上述模型复用。领域模型中的 `Bool` 不受 recorder 标量字符串化约定影响。模型可以有对象和具名字段；禁止的是 `RecordedValue.object`，不是 JSON 对象。

## 2. 新版产物与校验

证明文档和计算函数对象分别添加 `"recordingProtocol": 2`，读取端要求该值；旧产物报错并要求重新导出，不提供旧格式兼容。页面、Info 及模块清单不因本次调整增加版本字段。证明文档的步骤仍是扁平 JSON 对象，保留 `$ruleId` 和 `$branches` 作为专用模型的导出字段；其余键为 recorder 字段。计算函数保持原有 JSON 字段名；定理陈述也保持 `statement.parameters` / `conditions` / `conclusion` 的字段名及表达式引用形状。

**仅 recorder 字段**使用显式标记，以免把普通 JSON 数组误读为 `.array`、把普通 `{"$ref":"e0"}` 误读为表达式：

```json
{"kind":"plain","value":{"$ref":"e0"}}
{"kind":"array","value":[{"kind":"plain","value":"forward"}]}
{"kind":"expression","value":{"$ref":"e0"}}
```

这些标记也是协议结构，不允许额外键；`.plain.value` 是不透明的、任意合法 JSON。`.array.value` 递归包含带标记的录制值。只有 `.expression.value` 注册表达式根；例如步骤字段 `rules_expression_before` 的数组第零项的根路径为 `['proof', 0, 'rules_expression_before', 'value', 0, 'value']`。陈述和计算函数的根路径沿用其专用模型的原始形状。表达式遍历及 ID 分配继续遵守稳定顺序，依赖、绑定与路径校验要跟着更新，不能靠扫描普通 JSON 的 `$ref` 推断表达式。

`record_value` / `record_param` 一次只写一个字段。**不增加多字段返回接口或自动字段展开机制**；结构化参数在手写 recorder 中捕获一次，再用多次 `record_value` 写入。先一起捕获、验证；多次写入放在同一个现有的 `withRollback` 块内，失败时回滚整个块，不能留下半套平行数组。不新增提交 API。普通单字段参数的自动录制可继续保留；依赖结构化参数的自动录制器须改为手写。结构化参数不再提供产生旧对象的 `RecordValue` 实例；不受支持的自动录制请求应在声明时给出提示，而不是静默导出普通 JSON 对象。

## 3. 字段命名、语义与对齐

- 带时间阶段的字段统一为 `<参数名>_<成员名>_before` / `<参数名>_<成员名>_after`，例如 `rules_expression_before`、`rules_direction_before`。不带阶段的字段为 `chain_relation`、`chain_rhs` 等。参数名取调用处现有字段名前缀。
- 上下文保留 `$` 前缀：`$context_names_before`、`$context_types_before`、`$context_names_after`、`$context_types_after`。每侧的名称和类型数组等长、同序，名称唯一；上下文捕获在同一快照完成。缺少某侧记录不表示空上下文。
- 目标字段保持 `$goal_before` / `$goal_after`。有目标时为表达式，没有剩余目标时为字符串 `"completed"`；字段缺失表示未记录，不能解释为完成。
- 默认 `Bool` 转为字符串 `"true"` / `"false"`，默认 `Option.none` 转为字符串 `"null"`，`Nat` / `Int` 保持 JSON 数字；具体领域优先使用下表中的语义字符串。显式 `RecordValue.plain` 和 `RecordValue Json` 仍不变换任意 JSON 的内部类型。
- 平行数组必须长度相同、按原输入顺序对齐，空输入产生等长的空数组。缺少单项信息时使用字符串 `"not applicable"`，不得删除该项；表达式槽可在专用场景使用另行指定的状态字符串。读取端对内置成组字段验证长度、元素种类及状态值。

| 语义 | 录制字符串 |
| --- | --- |
| 重写方向 | `"forward"` / `"backward"` |
| 位置范围 | `"all"` / `"selected"`；未指定位置用 `"not specified"` |
| 位置是否含目标 | `"included"` / `"excluded"`；未指定用 `"not applicable"` |
| 目标已经完成 | `"completed"` |
| 未提供可选值 | `"null"` |
| 该属性不适用 | `"not applicable"` |
| 证明空位 | `"hole"` |
| simp 条目类型 | `"star"` / `"erase"` / `"lemma"` |
| simp 阶段 | `"pre"` / `"post"`；不适用用 `"not applicable"` |

不要在通用渲染器中按字符串内容推断类型：`"null"`、`"hole"` 等只在约定的具体字段中具有特殊语义。

## 4. 现有实现的迁移映射

以下名称是目标字段，不是旧字段的别名。`before` / `after` 只用于原 recorder 确实在该阶段捕获的参数；不要为了对称性额外捕获一次。非表达式状态在对应数组中以字符串表示。

| 当前来源 | 目标字段与处理方式 |
| --- | --- |
| `Recorder.lean` 的 `record_context "$context_before/after"`、`Command.lean` 的自动上下文录制 | `$context_names_before/after`、`$context_types_before/after`；上下文专用宏在一次快照及回滚范围内写两列（并非结构化参数的通用多字段接口）；仪表盘按名称对齐 |
| `Recorder.lean` 的无剩余目标 `.plain .null` | `$goal_before/after` 的 `"completed"`；`SimpArgs` 的可选表达式失败值则用 `"not applicable"`，不混淆目标状态 |
| `RwRuleSeq.lean` 的 `{ reverse, expression }[]` | `rules_expression_before/after`、`rules_direction_before/after`；逆向为 `"backward"` |
| `SimpArgs.lean` 的 `{kind, name?, phase?, reverse?, expression?}[]` | `args_kind_before/after`、`args_name_before/after`、`args_phase_before/after`、`args_direction_before/after`、`args_expression_before/after`；不适用槽填 `"not applicable"`，擦除项的名称仍保留 |
| `Location.lean` 的 `{kind, wildcard, goal, hypotheses}` | `loc_scope_before/after`、`loc_goal_before/after`、`loc_hypotheses_before/after`；`kind: location` 为冗余常量不再输出；可选参数缺失仍输出全部三个字段 |
| `OptConfig.lean` 的 `{name, value}[]` | `config_name_before/after`、`config_kind_before/after`、`config_value_before/after`；`kind` 标记 `"boolean"` / `"number"` / `"string"` / `"syntax"`，`value` 为数字或字符串；语法值保留源码文本 |
| `Scripts.lean` 的 calc `chain[{relation,rhs,proof}]` | `chain_relation`、`chain_rhs`、`chain_proof`；原 `init` 不变，`chain_proof` 元素为表达式或 `"hole"` |
| `Scripts.lean` 的 infer `chain[{rhs,proof}]` | `chain_rhs`、`chain_proof`；原 `init` 不变，空位同上 |
| `Test/PageScriptBoard.lean` 的 `premises` 对象 | `premises_names`、`premises_types`；模板与 board 改为读取完整字段 |
| SVG / LaTeX recorder 的 `metadata` 和 LaTeX 的 `source` JSON 对象 | `metadata_title`、`metadata_label`、`metadata_extra_names`、`metadata_extra_values`、`source_language`、`source_code`；`label` 缺失用 `"null"`，extra 两列等长。专用 renderer 由这些字段重建自己的输入 |
| `JsonBox.lean` 的步骤 `.object`、`Strategy.lean` 的分支 `.object` | 专用步骤/分支模型；结构键 `$ruleId` / `$branches` 的导出布局不变，`Command.lean` 的初始 recorder 不再写 `$ruleId` |
| `Declaration.lean` 的陈述 `.object`、`ComputationEncoding.lean` 的计算函数 `.object` | 专用陈述/函数模型与独立编码，PS4HTML 沿用相应专用 schema，不受 recorder 标量规则约束 |

已知依赖旧结构化参数实例的自动声明包括 `simp`、`rewrite`、`rw`、`field`、`omega`、`decide`、`nativeDecide`、`betaReduce`、`change`、`rwPos`、`rwNeg`、`pointwise`、`unfold`、`symm`；实施时以完整 `script_recorder ... auto` 搜索结果复核可选的 `location`、`simpArgs`、`optConfig` 组合。它们不能在删除 `.object` 后继续使用旧实例；简单参数仍可自动录制。

## 5. 模板、仪表盘及专用展示

- `${field}` 精确查找一个**完整的字段名**，不再分割 `.`、解析数字下标或递归进入对象。若确有名为 `a.b` 的完整字段，`${a.b}` 只查该键；缺失则报错。动态策略 renderer 注入的 `${index}` / `${index'}` 保留，不属于录制字段路径。
- board 的 `value` 与模板共用完整字段名查找；字段缺失显示“未记录”。原来展示 `premises` 的 board/模板应显式改为 `premises_names` 和 `premises_types`。不影响定理声明使用的另一套 `template%` 语法。
- 模板与 board 共享一个 recorder 值渲染器：表达式使用 Lean2TeX；录制数组非空时逐项渲染并用 `, ` 分隔，空数组显示 `[]`；`plain` 字符串原样作为文本显示、数字按数字显示，其他 `plain` JSON **重新序列化为 JSON 代码**（不是恢复输入时的空白或缩进）。所有文本及 JSON 代码均做 HTML 转义。`plain` 下的 JSON 对象/数组不得递归寻找表达式引用。
- 仪表盘的状态区消费新的上下文两列和目标状态，区别缺失、空数组和 `"completed"`。专用 calc / infer、策略、SVG、定理陈述及 computation 分别按其目标字段或模型读取，不用通用对象展开代替。删除按普通 JSON 对象的 `$ref` 外形推断 recorder 表达式的校验。

## 6. 实施与验收顺序

1. 分离表达式捕获/编码，建立步骤/分支、陈述、计算函数专用模型；保持表达式表、绑定路径和依赖收集可校验。
2. 改造 recorder 单值协议与步骤储存；显式多次写入结构化参数，替换所有现有 `.object` 用法，再移除构造子。
3. 更新 PS4HTML schema、resolver、模板、board、状态区和专用 renderer；旧产物需明确提示重建。
4. 更新 `docs/schema/recording-*.schema.json`、README、中英文示例与测试，重新构建导出和渲染产物。

验收至少覆盖：plain JSON 对象 `{"$ref":"e0"}` 不成为表达式；plain JSON 数组与 recorder 数组展示不同；表达式根仅来自注册的 `expression`；平行数组空值/缺项/长度不一致；自动录制结构化参数迁移；模板完整字段与包含点号的字面键；缺失状态与完成状态；calc/infer 的 `"hole"`；纯 tactic 证明的 statement；计算函数的独立表达式表；HTML 转义；旧协议失败并提示重建。

## 7. 阶段四交付后的验收记录与剩余问题

首次验收只读检查发现以下问题；后续第四阶段收尾对其作了处理：

1. **已修复：全量 Lean 测试构建失败。** `lake build Test` 原在 `Test/TransientProofDependencies.lean:29–56` 报 `explicit theorem dependency was discarded`。测试的 `step.theorem` 已由旧协议裸字符串改为 `{"kind":"plain","value":"<声明名>"}`，保留原有的显式依赖断言；重跑 `lake build Test` 通过。真实导出产物的逐类端到端核对仍属于第六阶段。
2. **已修复已知校验缺口：内置字段组。** `schema.py` 现在要求内置结构化参数的 `before` 字段组完整存在；仅 `simp` 的位置还强制要求 `after` 组，其余 `after` 组只有出现时才校验。calc/infer 的 `init`、非空链及 calc 关系列，以及 SVG/LaTeX 的必备元数据列也在文档入口校验。新增缺整组、缺单列及空链反例；不为没有在该阶段捕获的参数强加字段。
3. **已修复已知校验缺口：平行数组行语义。** `simp` 的 `star`、`erase`、`lemma` 行按实际捕获器约束不适用槽、阶段、方向及表达式种类；配置 `boolean` 限字符串 `"true"` / `"false"`，`number` 限非负整数，字符串/语法值保持字符串。对应正反例已加入协议测试；第三方同名字段仍保留任意 `.plain` JSON。
4. **已明确架构边界：上下文专用宏。** `record_context` 内部 `recordContextFields` 仍一次捕获快照、在同一回滚块写入 names/types 两列；它不是 `record_param` 的多字段返回，也不是通用自动展开接口。第 2 节的“显式写多次”针对结构化参数，此处保留专用宏以避免拆散上下文原子快照。

第四阶段收尾重跑 `lake build Test`、录制值协议、board 协议及集成、仪表盘与 simp 位置测试通过；现有协议 2 导出的证明文档也通过 `validate_document(module_protocol=True)`。最初验收已通过 `lake build ProofScript`、定向 Lean 测试、页面组件及定理 IDE 测试。`python3 -m unittest discover -s scripts -p 'test-*.py'` 未发现测试（该文件命名模式与 unittest 的默认模块导入规则不匹配），不能把它当成测试通过；需要逐个运行现有脚本或提供明确的测试入口。

## 8. 阶段五：完成 PS4HTML 消费端迁移与契约收敛

模板的完整字段名查询、带标记录制值解码、仪表盘新状态字段，以及 calc/infer/SVG 等专用 renderer **已有实现**；阶段五剩余工作不是从头重写，而是补齐并核对以下边界：

- 修复第 7 节的文档级内置字段组和逐行语义校验；使文档加载、默认模板/board、专用 renderer 对同一内置格式的要求一致。覆盖 `simp`、`rw`/`rewrite`、位置、配置、calc/infer、SVG/LaTeX；对空数组、缺失字段、长度不一致及混合 `"hole"` 的输入分别设正反例。
- 确保专用 renderer 不靠 `zip` 截断不等长数组来隐式丢项；验证应在渲染前拒绝不一致数据。对未使用专用 renderer、隐藏步骤和仅加载文档的路径，也要决定并测试一致的拒绝行为。
- 核对 `plain` 任意 JSON 保持不透明：包含 `$ref` 的对象、JSON 数组与录制数组显示不同，JSON 代码经重新序列化和 HTML 转义；表达式仅从标记为 `expression` 且列入 `expressionRoots` 的叶子解析。保留模板字面点号字段和动态策略 `${index}` / `${index'}` 的用例。
- 核对定理陈述和计算函数各自的专用数据模型及表达式表，不把这两个领域重新塞回 `RecordedValue`；保留无录制步骤的证明与独立计算函数的渲染/校验用例。

阶段五完成条件：PS4HTML 对新协议的有效数据能正常生成页面；对上述无效数据在明确的校验入口报错；现有板面、状态对比、策略分支和专用 renderer 的集成测试通过。不要仅以 `validate_document` 的宽松通过或单个页面成功作为全部通过依据。

**阶段五实施记录：** 文档入口已校验内置 rule 的必备阶段字段、平行数组及逐行语义，包含 calc/infer 非空链、关系与证明空位、媒体 extra 列和 LaTeX 来源列；自定义规则的同名 `plain` JSON 不受内置限制。`validate_record` 对隐藏的专用 renderer 仍检查其数据，隐藏策略也验证分支结构；隐藏的默认模板不要求无须显示的占位符。calc/infer/SVG 渲染函数在 `zip` 前自行检查列长度，防止直接调用时静默截断。模板与 board 仅按完整键取值，复杂 `plain` JSON 不进入表达式图且做 HTML 转义；新增字面点号字段、JSON 转义、隐藏 renderer、无录制步骤的陈述和独立计算函数渲染测试。

第五阶段历史验证：协议用例（原 `scripts/test-recording-value-protocol.py`，现已移除）、保留的 board 和 dashboard 测试，以及实际 board、无步骤定理与 calc 页面曾通过。较大的 `Test.«ECNU20260523-Problem22»:ps4html` 曾在 600 秒超时，**不视为通过或失败**。

## 9. 阶段六：产物、文档、全量回归与交付

1. **保持全量构建通过。** 旧协议夹具已迁移且 `lake build Test` 通过；在后续改动后重跑，并针对真实导出步骤核对显式定理依赖及表达式依赖。若有其他失败，逐项记录并修复。
2. **继续扩展回归测试。** 第 7 节已知的缺组、错列和逐行语义反例已覆盖；后续还要检查结构化参数自动录制在声明时明确拒绝、显式多字段在同一 `withRollback` 下回滚、根路径/绑定路径及依赖收集在新包装层下正确。对内置规则之外的同名自定义字段验证允许 `plain` 任意 JSON。上下文接口按第 7 节记录的专用宏边界处理。
3. **逐类重新导出协议 2 产物并验证页面。** 覆盖普通步骤、策略和子证明、`simp`/重写及位置、calc/infer、SVG/LaTeX、无录制步骤的定理陈述及计算函数；检查旧协议明确提示重新构建。不要拿工作区里尚未重建的旧 `.ProofScript` 文件判断新实现。核对示例输出、`docs/schema/recording-proof.schema.json` 与 `docs/schema/recording-function.schema.json` 同真实导出一致。
4. **收尾文档与测试入口。** 对照 README 中英文、Info 命令说明、前端交接文档和本清单统一字段名与新语义；CI 入口不得指向已删除的测试。现有 workflow 仍有 `Under Development: exit 1`，远端 CI 尚未通过；原先依赖新增 gallery 的计算页面测试随测试模块一起移除。

第六阶段历史执行记录：删除前曾使用新增 gallery 模块真实导出 infer、SVG、LaTeX 与计算函数，并以新增 Python 脚本核对 JSON Schema；新增双字段回滚测试也曾通过。**这些测试文件现已按要求删除，历史结果不能视为当前仓库仍可运行的回归。** 保留的 board、无步骤定理、calc 页面及库级导出验证仍可复跑。普通 `python3 -m unittest discover -s scripts -p 'test-*.py'` 曾发现 0 项，须逐脚本或显式指定 unittest 文件。

库范围历史验收：`lake build Test:proofscriptExport` 曾成功发布包含 20 模块、61 份协议 2 证明的库 target，全部通过 Python 协议及 proof JSON Schema；`scripts/test-module-render.py` 曾 11 项通过。移除新增 Lean 模块后，需重新构建当前 Test 库 target 才能获得与现有源码一致的新清单，不能继续将原来的 20 模块/61 份证明称为当前库验收结果。`.ProofScript/manifests/modules/Test/VersoStage1.json` 另保留无源文件的历史旧协议缓存，不擅自删除。

`python3 scripts/test-page-components.py` 已完整重跑通过，包含 `pageBuild=False`、`pageBuild=True` 和后续坏语法检查（输出 `All page-component checks passed.`）；此前 900 秒超时不计通过，以本次完整运行结果为准。

收尾复核：删除测试后，首次 `lake build ProofScript Test` 因 `ProofScript/Builtin/Scripts/Decide.lean` 两处 `with_rollback` 缺少 `do` 而失败；修复后定向构建通过，最终 `lake build ProofScript Test` 成功完成 8802 个任务。保留的 board、dashboard 与模板测试共 33 项通过；`git diff --check` 已通过。库级 `Test:proofscriptExport` 尚未按删除后的模块根重新运行；远端 CI 尚未运行。

测试清理后的当前状态：新增测试覆盖已被主动移除，普通 Lean 构建已复验通过；旧页面产物和库 target 可能仍包含已删模块，不能把清理前的库级导出与页面验收直接套用于清理后的测试集合。远端 CI 结果待实际运行确认。
