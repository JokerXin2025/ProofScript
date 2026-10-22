# 录制值重构：第一阶段契约

本文固定 [重构方案](Recording-Value-Refactor-zh.md) 第一阶段的设计决定，供第二至第七阶段实现和验收。制定日期为 2026-10-20，录制协议为 **`0.1.0`**。第六阶段统一切换生产与消费；第七阶段已删除旧表达式导出器、快照和兼容接口。下文第一阶段的验证记录保留当时状态。

配套产物：

- [正式格式 schema](schema/recording-proof.schema.json)：固定 JSON 形状并接入生产读取器；删除了迁移时的重复 schema。
- 第一阶段的目标格式 fixture、格式契约检查和 Lean 语义基线已完成验证；第七阶段按用户要求删除本次新增测试及 fixture。最终验收使用保留的原有测试与真实页面构建，记录见重构方案第七阶段。

## 1. 固定的决定

| 问题 | 决定 |
| --- | --- |
| 内部值 | `RecordedValue { data : RecordedData, nodes : Array ExprNode }`；不增加隐式 annotations 或 references 字段 |
| 节点引用 | 使用 `Nat`，子节点先于父节点；导入时按构造子统一加偏移 |
| 捕获语义 | 捕获时实例化已赋值的 Expr/Level 元变量，剥离 `mdata`，保留未赋值 ID |
| 图的所属范围 | 每份证明一张节点表，策略和嵌入子证明共用；每个 computation function 独立持有节点表 |
| wire 引用 | 保留 `eN` 和单键 `{"$ref":"eN"}`，增加明确的 `expressionRoots` 路径清单 |
| 用户 JSON | 未登记的对象永远按普通数据解释，即使包含 `$ref`、`kind` 或看起来像旧表达式 |
| 展示补充信息 | 内置记录器显式调用辅助函数，生成普通的 `<field>_display` 伴随字段，按出现路径关联 |
| 默认类型信息 | 不再为任意节点生成 `typeOf`；需要类型时显式录制，声明类型由展示辅助函数按需捕获 |
| 引用策略 | 主体和展示字段分别应用 `collectReferences`；展示字段默认 `false`，渲染依赖独立收集 |
| 格式切换 | 录制协议升级到 `0.1.0`，统一拒绝旧录制产物并要求重建，不猜测迁移旧字段 |
| 实现切换时机 | 第二至第五阶段可保留明确的适配层，第六阶段统一切换生产和消费入口 |

## 2. 表达式和图的不变量

### 2.1 规范化与冻结

1. 在捕获任务实际执行时调用 `instantiateMVars`，不是在构造 `ParamCapture` 或提交时调用。
2. 实例化同时覆盖表达式和 `.sort` / `.const` 中已赋值的 Level 元变量。未赋值元变量保留其 ID，不在提交或显示时重新查赋值。
3. 所有 `.mdata _ expr` 层均剥离，不占节点或路径层级。源位置只通过显式展示任务捕获。
4. 不执行 `whnf`、类型推断、隐式参数删除、自由变量声明展开或其他表达式改写。`.letE.nondep`、binder 名字/信息、字面量和 universe 结构原样保留。
5. 表示允许开放项：bvar 是 de Bruijn 索引，fvar/mvar 是捕获时的 Lean ID。提交与纯编码不需要原局部上下文。该表示不承诺是可在新环境直接运行的闭合 Lean 项。

### 2.2 节点的最终字段

以下字段之外的节点字段一律拒绝；节点引用均编码为 `ExprRef = {"$ref":"eN"}`。

| kind | 必需字段（不重复列 kind） |
| --- | --- |
| `bvar` | `index : Nat` |
| `fvar` / `mvar` | `id : String` |
| `sort` | `level : LevelJSON` |
| `const` | `name : String`, `levels : Array LevelJSON` |
| `app` | `fn : ExprRef`, `arg : ExprRef` |
| `lam` / `forall` | `name : String`, `type : ExprRef`, `body : ExprRef`, `binderInfo : BinderInfoJSON` |
| `let` | `name : String`, `type : ExprRef`, `value : ExprRef`, `body : ExprRef`, `nondep : Bool` |
| `lit` | `lit : LiteralJSON` |
| `proj` | `typeName : String`, `index : Nat`, `expr : ExprRef` |

`BinderInfoJSON` 沿用 `default`、`implicit`、`strictImplicit`、`instImplicit`。Level 沿用 `level.zero/succ/max/imax/param/mvar` 及当前 `Utils/Json.lean` 的字段形状；Literal 沿用 `literal.nat/str`。名字和 ID 继续使用 `Name.toString` 的字符串形式，不更改独立的 Info 名字编码。

`proj.typeName` 是完整的结构类型名。例如 ``.proj `Prod 1 p`` 记录 `typeName = "Prod"` 和 `index = 1`，不输出旧的 `structName/fieldName` 组合；字段名需要调用方显式查询。投影索引、bvar 索引以及辅助展示 view 的索引都不是表达式节点引用。

### 2.3 合法性与导入

- 一份图包含连续编号 `e0` 至 `e(size-1)`；wire ID 使用规范形式 `^e(0|[1-9][0-9]*)$`，不接受 `e00`。JSON 对象本身的键顺序不影响编号。
- 每个子引用必须严格小于所在节点编号，每个根引用必须在界内。这既排除环，也使追加导入保留有效性。
- 内部构建器先生成子节点再追加父节点；导入将根与子引用同时加上目标数组长度。Lean 内部不再扫描验证整份值，直接构造的扩展值也须遵守所属数组约定；外部 JSON 解码仍按上述 wire 契约验证。
- `RecordedData.object` 的字段键应唯一。生产路径通过固定字段、配置声明检查和步骤写入检查保证这一点，不再递归扫描数据树检查重复键。
- 合并已有值时只映射节点内部的子引用和 `RecordedData.expression`。普通 JSON、对象/出现路径、binder/proj 索引及展示 view 索引不调整。
- 允许有效但不可达的节点。引用和渲染依赖只从实际根遍历；初版不做跨捕获去重，也不把节点编号当作稳定业务 ID。

### 2.4 隔离与引用顺序

每个参数仍有独立的 Lean 状态隔离边界；其内部数组/对象共用本次构建器。一个参数的临时 elaboration 不对下一个参数可见。`capture_params` 的批次原子性不意味着参数共享 elaboration 状态。

嵌套捕获失败但允许继续时，必须同时恢复子任务的节点和缓存；例如 simp erase 的 simproc 名称不能 elaboration 为项时，仍保留正常的 name 和 `expression = null`。捕获成功/失败均恢复临时状态，提交只有失败才回滚。

常量遍历固定兼容 Lean 4.32：

| 构造子 | 访问顺序 |
| --- | --- |
| app | fn → arg |
| lam / forall | type → body |
| let | type → value → body |
| proj | 仅 expr，不收集 typeName |
| const | 加入本常量，按首次出现去重 |
| fvar / mvar / bvar / sort / lit | 不查声明、类型或其他补充信息 |

数据根按捕获时的数组/对象字段顺序遍历，保持现有引用首次加入顺序。最终根路径清单的排序仅服务确定性导出，不用来重建引用顺序。`referenceCollection` 和字段开关继续控制对 `Core/References` 的写入，不改变表达式身份、渲染依赖或最终证明依赖事实。

## 3. 输出边界：expressionRoots

### 3.1 证明文档

有步骤的文档必须同时包含 `proof`、`expressions` 和 `expressionRoots`；仅元数据步骤可以使用空节点表和空根清单。code-only 文档只包含 `schemaVersion/module/code`，三者全部缺省，不接受混搭。

```json
{
  "schemaVersion": "0.1.0",
  "module": "Demo",
  "code": "...",
  "expressions": {
    "e0": {"kind": "const", "name": "Nat.succ", "levels": []},
    "e1": {"kind": "fvar", "id": "_uniq.12"},
    "e2": {"kind": "app", "fn": {"$ref": "e0"}, "arg": {"$ref": "e1"}}
  },
  "expressionRoots": [["proof", 0, "subject"]],
  "proof": [{
    "_ruleId": "Demo.rule",
    "subject": {"$ref": "e2"},
    "payload": {"$ref": "e999"}
  }]
}
```

`subject` 是表达式；`payload` 是普通数据，不要求存在 `e999`。若把未登记的 `payload` 声明成 schema.expression，则属于契约不匹配，不能自动补登记。

### 3.2 清单生成与读取

- 最终组装完成后，从 `RecordedData.expression` 自动生成 owner 内的完整路径。`.plain` 中不寻找根；用户不手写根清单。
- 路径沿用 `JsonPath` 数组编码，字符串表示对象键，非负整数表示数组位置。字符串 `"0"` 不转换成数组索引。
- 每条路径唯一且存在，值必须恰为一个 `ExprRef`，指向有效节点。证明的路径位于 `proof` 数据区，不能指向节点表、清单自身、源码或协议字段。
- 清单顺序固定为数组按索引、对象按键的字典序遍历；生产端生成规范顺序，解码器无需依靠该顺序解释引用。
- 从登记根进入节点表后，仅沿本构造子的子节点字段解引用，不递归猜测任意 JSON 对象。
- 已声明的 schema.expression 位置必须登记；optional/null 不登记。schema.json 内可组合显式的 `RecordedData.expression`，其根同样登记。纯 JSON 想成为表达式时，必须改用明确的节点/值导入接口。
- `fields = null` 的不透明手写契约继续支持。消费者能检查已登记项，无法区分未登记普通对象与生产端漏登记的表达式，因此未登记对象始终是普通数据，不以形状猜测来补救。
- 该清单包含关闭引用收集的目标、类型和展示辅助表达式。表达式根不代替 artifact 的 `bindings`，后者仍绑定步骤与 invocation contract。

策略的路径例如 `["proof", 0, "branches", 1, "proof", 2, "subject"]`；嵌入证明例如 `["proof", 0, "proof", 1, "subject"]`。子证明移入父树后只补路径前缀，不创建独立的 `eN` 命名空间。

## 4. 显式展示信息

### 4.1 伴随字段

内置展示辅助函数生成 `<field>_display`，它是普通 `RecordedData`，不是 `RecordedValue` 或 `ExprNode` 的额外字段。主体与伴随字段都声明在调用的输出契约中；重名按既有重复字段规则拒绝。

固定的普通数据形状为：

```text
Display {
  kind: "expression-display-v1",
  field: String,
  views: Array View
}
View {
  root:
    {kind: "field", path: JsonPath}
    | {kind: "auxiliary", expression: ExprRef},
  hints: Array Hint
}
Hint {
  path: Array String,
  isProp: Bool | null,
  declaration: {name: String, typeView: Nat | null, valueView: Nat | null} | null,
  appBinders: Array (BinderInfoJSON | null) | null,
  sourceRange: {file: String, start: Nat, stop: Nat} | null
}
```

所有 Hint 字段都输出，未知项使用 `null`，hint 本身可以缺省。`sourceRange` 使用源文件的 UTF-8 byte offset，满足 `start ≤ stop`。

- `field` 是同一步骤主体字段的精确名字。主 view 的 `path` 相对该字段的数据树：单表达式为 `[]`，重写规则数组中的表达式可为 `[0, "expression"]`。每个主路径至多一个 view，且必须指向已登记的表达式根。
- 辅助 view 保存声明类型或局部定义值，它的 `expression` 必须用 `RecordedData.expression` 构造并加入全局根清单，不能藏进 `.plain`。
- `typeView/valueView` 仅是当前 `views` 数组的下标，只能指向 auxiliary view，且 view 之间无环。这些数字与节点下标无关，不做表达式 rebase。
- Hint 的 `path` 相对当前 view 的结构根，只使用合法子节点边 `fn/arg/type/body/value/expr`。例如 app 的 `arg` 合法而 `type` 非法。同一 view 中路径唯一。
- Hint 内容必须匹配目标节点：`declaration` 非 null 只允许 fvar/mvar，`valueView` 非 null 只允许 fvar，`appBinders` 非 null 只允许 app。解码器按实际节点检查这些关联，不能仅检查对象形状。
- 展示信息按出现路径绑定，不按全局节点 ID 合并。因此，同一个 bvar 节点在两个 binder 下可以有不同的显示上下文，剥离 mdata 后也不会把不同源位置误合并。

消费者只有在输出契约明确声明该字段为上述 Display 的 object/union/literal 结构，且 `kind/field` 为相应 literal 时，才自动将其应用到主体字段；不根据任意 `.json` 的 marker 或字段名猜测。不透明手写契约仍可消费纯结构，专用渲染器可以显式选择并验证一个 Display。Display schema 可由现有 `ParamSchema` 构造子表达，不增加 schema kind 或提升 contractVersion。

### 4.2 捕获和提交责任

1. 显式展示任务在同一次隔离捕获、同一时点生成主体和伴随字段，再批次原子提交。允许分别导入自包含值；主 view 通过字段路径关联，无需要求两份值有相同的节点编号。
2. 伴随字段固定 `collectReferences := false`；主体保留自身策略。一个字段的数据变化、展示查询失败和两个字段的重名检查不能破坏这组写入的原子性。正常缺失或主体 best-effort 失败时，主体和伴随字段均为 `null`。
3. helper 不对任意节点推断 `typeOf`。它显式读取 fvar/mvar 声明的名字和类型，以及 fvar 的可选局部值，分别建立 auxiliary view；辅助表达式需要的展示信息也在同一任务中捕获。
4. 仅在表达式没有 loose bvar 时查询 `isProp` 和需要 Meta 计算的参数信息。开放 binder 体或查询失败使用 unknown，禁止把开放项交给类型推断。declaration 查询失败记 `null`；其辅助类型查询失败可以保留 name 并令 `typeView = null`。
5. `appBinders` 若非 null，长度必须等于该应用沿 fn 展平后的参数个数，按左到右排列。不能确定的参数为 `null`；`isExplicit/isTypeclass` 由消费方从 BinderInfo 派生。
6. 源位置只有在显式请求并提供原 Syntax 或可用原始 metadata 时捕获；显式根 Syntax 优先，不把根范围自动传播给所有后代，不输出其他 metadata。
7. 补充查询不可改变已冻结的主体结构，也不能在 tactic 执行之后再查捕获前的展示信息。辅助查询递归需要终止保护，失败返回缺省 hint 或错误结果，不留下部分图。

展示 helper 的调用组是新增的显式能力，不能将所有已有 `record_value` 或自定义转换自动升级为该模式。阶段三/五需要实现这样的成组捕获/原子写入入口；普通参数之间的状态隔离不变。

### 4.3 缺省行为与允许的变化

| 信息 | 新行为 |
| --- | --- |
| 缺少整个 Display 或某个 hint | 正常渲染核心结构；缺失信息视为 unknown |
| `isProp = null` | 不等价于 false，不擅自把变量归为命题、证明或数据 |
| 未知声明 | 用 ID 支持稳定的变量命名回退，不展示猜测类型 |
| 已知声明有 typeView | 用该 view 提供类型展示及命题/证明分类；typeView 缺失则不推测 |
| 已知声明无 valueView | 不展开局部值；捕获失败可以附诊断，不能重新查 Lean 状态 |
| 参数显式性未知 | 保留相应参数；无法可靠选择 `arguments := explicit` 时使用完整应用回退并给诊断，不猜参数位置 |
| 没有 sourceRange | 不提供源码定位 |
| 没有 typeOf | 不再提供任意子表达式的推断类型 hover；需要时显式录制独立类型字段 |

内置 recorder 在有有效上下文时显式生成渲染所需的 Display，保持自由变量用户名字、声明类型/局部值以及已知隐式/实例参数的显示能力。纯结构自定义 recorder 可以使用上述缺省；不承诺凭结构恢复缺失的声明信息。

## 5. 字段迁移表

| 当前输出 | 新位置或处理决定 |
| --- | --- |
| `kind` 及构造子结构字段 | 保留在纯节点中，使用第 2 节字段 |
| 任意节点 `isProp` | 对应出现路径的 hint.isProp，允许 null |
| fvar/mvar `name/type` | hint.declaration.name/typeView；声明类型为辅助表达式 |
| fvar `value` | hint.declaration.valueView |
| fvar 声明 `index/binderInfo` | 初版不输出；binder 自身的 binderInfo 仍在结构节点中 |
| 任意节点 `typeOf` | 默认删除；需要时录制为独立普通字段 |
| app `headConstant` | 消费方从二元 app 的 fn 链推导 |
| app `arguments[*].expr` | 消费方从 fn/arg 结构展平 |
| app 参数 `binderInfo` | hint.appBinders |
| app `isExplicit/isTypeclass` | 从 appBinders 派生 |
| `sourceRange` | 对应 occurrence hint，显式请求时捕获 |
| `mdata` / 原 metadata | 核心节点不输出，不把任意 metadata 作为 JSON 转存 |
| proj `structName/fieldName` | 改为真正的 `typeName/index/expr`；字段显示名不自动补齐 |
| 快照 `references` | 删除；从主体数据根和节点结构派生 |

伴随类型带来的 definition/variable/phrase 配置仍参与渲染依赖收集，不受其 `collectReferences = false` 影响。最终 theorem proofDependencies 继续来自最终证明事实，不从 Display 或录制引用列表代替推导。

## 6. 全部入口与版本迁移

### 6.1 生产与消费范围

| 边界 | 后续实现要求 |
| --- | --- |
| Codec / Conversion / Builtins | 核心捕获走共享构建器；显式展示任务独立调用 |
| location / rw / simp / config / calc / infer | 保留容器和 hole/null 语义，根清单覆盖其中真正的表达式叶子 |
| goal_before / goal_after | 仍为表达式或 null，自动 recorder 显式捕获对应 Display；关闭引用收集 |
| JsonBox / Strategy | 所有步骤、分支和子证明结构化组装；最终编码才生成根清单 |
| embed | 目标、类型、参数、h 和表达式 fallback 接入同一图，回放子证明保留 bindings 路径 |
| Output.Dependencies | 从登记根及显式展示信息推导渲染依赖，删除任意 `$ref` 扫描 |
| PS4HTML schema/info/模板 | 只解析登记根，并检查 schema.expression 覆盖；不再识别旧 inline expression JSON |
| Lean2TeX | 使用纯结构和显式 Display；相同节点的不同 occurrence 不共享上下文 hint |
| computation | 采用下面的独立 function owner；保留其执行协议 |

### 6.2 computation 的独立图

`ComputationFunction` 增加 `recordingVersion` 和 `expressionRoots`；路径相对 `function`，不与任意证明或其他 computation 共用节点表。

```json
{
  "recordingVersion": "0.1.0",
  "declaration": "Demo.compute",
  "type": "Bool → Nat",
  "expression": {"$ref": "e0"},
  "implementation": {"$ref": "e3"},
  "expressions": {
    "e0": {"kind": "const", "name": "Demo.compute", "levels": []},
    "e1": {"kind": "const", "name": "Bool", "levels": []},
    "e2": {"kind": "lit", "lit": {"kind": "literal.nat", "value": 0}},
    "e3": {"kind": "lam", "name": "_", "type": {"$ref": "e1"}, "body": {"$ref": "e2"}, "binderInfo": "default"}
  },
  "expressionRoots": [["expression"], ["implementation"]]
}
```

该例对应 `Demo.compute : Bool → Nat` 的实现 `fun _ => 0`。页面 provenance 的读取器必须检查 `function.recordingVersion`；缺失或旧版本要求重建。外层 component 的 schemaVersion 和 computation bundle/pending 协议不因此变化，finalizer 保留完整 function 数据。若需要展示信息，由生产者显式增加 `expression_display/implementation_display`；其辅助引用也属于本 function 图，不允许跨 owner。

### 6.3 版本矩阵与切换规则

| 协议 | 当前 → 目标 | 决定 |
| --- | --- | --- |
| recording/proof | `0.0.0 → 0.1.0` | 升级：节点、根边界和展示契约改变 |
| invocation contract | `1 → 1` | 结构不变，已有 recordingVersion 区分新语义 |
| Info | `5.0.0 → 5.0.0` | 结构不变；index 严格检查 recordingVersion |
| manifest | `5 → 5` | artifact/binding 结构不变 |
| snapshot payload | `4 → 4` | 结构不变；严格检查 recordingVersion |
| Info 模型 schema | `1.0.0 → 1.0.0` | 一般元数据模型不属于录制表达式中间表示 |
| computation function.recordingVersion | 缺省 → `0.1.0` | 新增显式表达式格式门禁 |
| computation component/pending/bundle | `0.0.0 → 0.0.0` | 执行格式不变 |
| computation ABI | `proofscript-json-v1` | 保持不变 |

第六阶段一次切换 `Script/Contract.lean` 的录制版本、`PS4HTML/recording.py` 及相关校验入口、正式录制 schema。`PS4HTML/schema.py` 的资源版本常量用途应分开核对，不能全局替换所有 `0.0.0`。

`Info/Snapshot.lean`、`Output/Protocol.lean`、`Output/Export.lean`、`PS4HTML/info.py` 已携带/校验 recordingVersion，继续严格检查新值。生成的合同 ID、snapshot ID、schema、内容摘要及 proofFactsDigest 全部重新生成，不手工改版本或摘要来复用旧内容。

拒绝旧 proof、旧 index/snapshot/contract 的录制版本，以及缺少新 function 版本的 computation 表达式数据；错误给出重新执行页面构建的提示。原生 proof 与 code-only 证明的能力不变。`ps4html make --cache` 不做格式迁移；重新运行 `lake build <Library>:ps4html` 生成完整新产物。

## 7. 验收基线

### 7.1 对照用例

| 基线 | 必须保持 | 允许变化 |
| --- | --- | --- |
| RecordingAPITest / RecordingAPIRules 的 snapshots、recovery、citations | 捕获后清除局部声明仍能提交；重复/关闭字段及批次失败不遗留状态；字段引用开关 | 节点编号和布局；增加 Display/根清单 |
| RecorderDSLTest / RecordingConfigTest | before/after 与分支/continuation 上下文；原 tactic 执行和嵌套写入目的地 | 转换/捕获接口内部实现 |
| RecordingComplexTest / RecordingNormalizeTest | rw、simp、location、config 容器及 erase/hole/null 语义 | 表达式节点移除自动字段 |
| CalcTest / InferRecordingTest | 链长度、关系和 proof hole；完成后目标 null | 根编号与展示信息存储位置 |
| ReferencesOptionTest / RecordingReferencesTest | 全局开关、首次出现去重及加入顺序 | 展示类型只在显式主体字段开启引用时参与引用 |
| ExprJSONFieldsTest + Lean 语义基线 | dependent binder、let、开放 bvar、proj 索引含义 | typeOf 缺省；proj 字段修正 |
| 内置 HAdd/HMul 等 `arguments := explicit` | 有 Display 时不把隐式/实例参数显示成操作数 | 缺少信息的纯结构 recorder 使用明确回退 |
| variable hover / theorem site 样例 | 同一自由变量命名稳定，binder 作用域与链接高亮正确 | 任意子表达式不再自动提供推断类型 |
| Embed 与 ComputationComponentTest | 子证明路径/参数语义；计算 provenance 图和执行 ABI | 新表达式图及版本字段 |
| test_metadata_scope.py / test_unrecorded.py | 旧产物拒绝、合同/快照边界及普通步骤回退 | 新录制版本需要重建 |

第一阶段的新格式 fixture 通过目标 schema 只代表形状成立。跨节点引用、根路径指向、声明字段覆盖、展示 view/occurrence 关联和原子回滚，必须用实际 API/解码器验收，不能以一个 schema 检查代替。

原 fixture 中的 `declaredExpressionPaths/displayPaths` 只是外部调用契约的测试投影，不是 wire 字段。消费方必须提供完整 invocation contract，以验证按 `ParamSchema` 识别展示字段；不能把这个投影用作权限清单。

### 7.2 本阶段的验证记录

- `lake env lean Test/RecordingValueSemanticsBaseline.lean` 和 `lake build Test.RecordingValueSemanticsBaseline`：当时通过，Lean 4.32.0；固定 Expr/Level 冻结、引用遍历及 bvar/proj 语义。当时加入默认 `Test` 构建，后于第七阶段删除。
- `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tools/ps4html python3 -m unittest Test/test_recording_value_contract.py Test/test_metadata_scope.py Test/test_unrecorded.py`：22 项通过。其中 4 项契约检查覆盖 schema 本身、11 个有效样例及 19 个无效变体的形状预期；另 18 项以当前 `0.0.0` 实现记录旧行为基线。
- `lake build`：未通过。当前工作树的 `Test/InfoCoreAPITest.lean`、`Test/InfoSchemaTest.lean` 和 `Test/TheoremDependencyContractTest.lean` 仍引用不存在的 `JsonPath.Part.field`，实际构造子已为 `.key`；这些引用在本阶段改动前已存在，本阶段未修改。构建日志：`/private/tmp/recording-value-phase1-verification.log`。
- `lake build TestPage:pageTests`：未通过，共 10 个测试目标失败：RendererDependencyScopeTest、InfoAPITest、MetadataScopeTest、RecorderSelectionTest、ComputationComponentTest、NativeTacticIsolationTest、CiteTest、TheoremDependencyProbeTest、RecordingAPITest、RecordingComplexTest。包括产物/声明缺失、`#guard_msgs` 预期消息不匹配，以及 RecordingAPITest 的引用策略断言失败；不能将当前页面录制行为记为全绿基线。本阶段没有修改这些测试或生产录制实现。构建日志：`/private/tmp/recording-value-phase1-page-tests.log`。
- fixture 的语义拒绝项留待实际 importer、resolver 和 display adapter 实现后验收。本阶段不宣称新录制器或新解析器已经实现。
