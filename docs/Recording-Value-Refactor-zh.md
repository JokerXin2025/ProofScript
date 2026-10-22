# 录制值与表达式表示重构方案

本文描述 ProofScript 录制数据层的分阶段重构，作为实现与兼容性验证的依据。七个阶段均已完成，旧实现、本次新增测试及相关产物已清理，并通过最终整体验收。录制协议为 `0.1.0`，编码集中在完整证明或 computation 函数的导出边界。下文各阶段的过渡边界和验证记录描述其完成时的状态，当前接口以第七阶段及其后续精简记录为准。

第一阶段的具体决定已固定于 [第一阶段契约](Recording-Value-Contract-zh.md)，包括 `0.1.0` 格式、显式展示字段、根路径清单及版本迁移规则。

## 1. 目标与设计边界

将当前“递归录制值中嵌套独立表达式快照”的表示，改为：

> 一份录制数据树，加上一份类型化表达式节点数组。数据树与节点之间通过数组下标引用，最终导出时才生成 JSON。

本方案采用以下约定：

1. 使用 `Array ExprNode` 保存表达式节点，不额外定义仅包装数组的 `ExprGraph`。
2. 使用 `Nat` 表示节点下标，不额外定义 `ExprNodeId`。
3. 表达式捕获仅记录表达式自身的结构，不自动查询类型、局部声明、命题属性或源位置。
4. 用户需要的补充信息，由记录器在合适的上下文和时机中显式查询、捕获。
5. 常量引用从被记录表达式的结构派生，不在 `RecordedValue` 中单独保存 `references`。
6. 保留捕获隔离、失败策略、原子提交和录制步骤回滚等现有语义。

该重构既调整内部数据结构，也收缩表达式导出器的职责。删除自动补充信息会影响输出契约和前端，不能仅作为内部等价替换处理。

## 2. 重构前的架构

本节描述迁移起点。旧递归模型及迁移期间的 `Recording/LegacyValue.lean` 已在第七阶段删除；当前实现见第 10 节。

相关实现主要位于：

- `ProofScript/Script/Recording/Value.lean`：录制值和表达式快照。
- `ProofScript/Script/Recording/Conversion.lean`：已有 Lean 值的转换。
- `ProofScript/Script/Recording/Codec.lean`：隔离捕获和语法参数解释。
- `ProofScript/Script/Recording/Engine.lean`：提交与引用收集。
- `ProofScript/Script/Recording/Runtime.lean`：字段写入与录制步骤生命周期。
- `ProofScript/Script/ExprJSON.lean`：表达式 JSON 导出和节点表合并。

### 2.1 每个表达式保存独立快照

重构前的核心类型为：

```lean
structure ExprSnapshot where
  json : Json
  table : Json
  references : Array Name

inductive RecordedValue where
  | scalar (json : Json)
  | expression (snapshot : ExprSnapshot)
  | array (values : Array RecordedValue)
  | object (fields : List (String × RecordedValue))
  | optional (value : Option RecordedValue)
```

表达式快照中的三个字段分别保存：

- `json`：表达式入口，通常为 `{"$ref": "e0"}`。
- `table`：本次表达式捕获的局部 JSON 节点表。
- `references`：对捕获时已实例化的表达式调用 `Expr.getUsedConstants` 得到的常量名。

数组或对象中的多个表达式通常分别持有节点表。同一个录制值内可以存在多个属于不同局部表的 `e0`。

### 2.2 捕获和提交

```text
语法参数 / 已有 Lean 值
  → 在隔离状态中解释和转换
  → RecordedValue，内部可能包含多个 ExprSnapshot
  → 恢复捕获前的 Lean 状态
  → 递归提交各表达式快照
  → 合并 JSON 节点表，调整 $ref，收集常量引用
  → 将 JSON 写入录制步骤
```

旧模型的 `array` 和 `object` 有真实用途，包括重写规则、simp 参数、位置参数、配置项、calc 链和推理链。它们让提交器能够找到嵌套快照，保留节点表和引用信息。

### 2.3 旧表示的成本

- JSON 同时充当内部中间表示和最终输出格式。
- 节点数组会被转换成带 `e0`、`e1` 等键的 JSON 对象，提交时再按键读取。
- 节点引用是 JSON 字段中的字符串，合并需要遍历并重写 `$ref`。
- 多个子表达式快照的表在提交时分别合并。
- 表达式导出器承担类型推断、局部声明读取和展示信息补全等额外职责。
- 常量引用作为平行信息保存，因为当前导出结果混合了原表达式结构和额外推导信息，不能简单扫描所有节点来还原原表达式的引用。

## 3. 新的数据模型

### 3.1 录制数据与表达式节点分离

```lean
inductive RecordedData where
  | plain (value : Json)
  | expression (root : Nat)
  | array (values : Array RecordedData)
  | object (fields : List (String × RecordedData))

structure RecordedValue where
  data : RecordedData
  nodes : Array ExprNode
```

`RecordedData` 描述输出形状，`nodes` 保存其中所有表达式所需的节点。两者出现的表达式下标均属于这份节点数组。

数组和对象仍然存在，但只承担数据组合职责，不再递归携带独立快照。`plain` 可以容纳任意普通 JSON；其中即便出现名为 `$ref` 的字段，也只是用户数据，不能被内部节点合并逻辑解释为表达式引用。

缺失值可以表示为 `.plain Json.null`，存在值直接使用其内部数据。可选性的输出契约仍由 schema 描述；捕获失败仍由异常或显式错误结果表达，不以缺失值代替错误控制流。

### 3.2 表达式节点

以下定义展示预期覆盖的表达式结构；实际模块划分和派生实例由实现阶段确定：

```lean
inductive ExprNode where
  | bvar (index : Nat)
  | fvar (id : FVarId)
  | mvar (id : MVarId)
  | sort (level : Level)
  | const (name : Name) (levels : List Level)
  | app (fn arg : Nat)
  | lam (name : Name) (type body : Nat) (info : BinderInfo)
  | forallE (name : Name) (type body : Nat) (info : BinderInfo)
  | letE (name : Name) (type value body : Nat) (nondep : Bool)
  | lit (value : Literal)
  | proj (typeName : Name) (index : Nat) (expr : Nat)
```

这些节点是捕获后的结构数据，不需要在提交时查询 Lean 局部上下文。

`proj` 的 `typeName` 是结构类型名，例如 ``.proj `Prod 0 expr`` 中的 `Prod`，不是投影字段名。最终编码必须按这个含义定义字段，不能照搬当前导出器用 `typeName.getPrefix` 作为结构名、用 `typeName` 作为字段名的行为；若需要用户可读的投影字段名，应显式查询结构元数据。

“只记录表达式自身”并不意味着删除所有类型和名字：lambda、forall 和 let 的类型与名字本来就是表达式构造子的组成部分，必须保留。自由变量的用户名字和声明类型则需要额外查询局部声明，不属于此处的自动捕获内容。

### 3.3 元变量与元数据

捕获前继续执行 `instantiateMVars`，冻结捕获时已经存在的元变量赋值。未赋值的元变量保留为 `mvar` 节点，提交时不再根据后续状态重新实例化。

本方案采用剥离 `mdata` 的约定：

```text
Expr.mdata metadata expr → 捕获 expr
```

因此，该表示保存的是“实例化已赋值元变量并剥离元数据后的表达式结构”，不是对原始 `Lean.Expr` 的逐字段无损备份。源位置等信息若需要保留，应由记录器显式输出。

### 3.4 下标有效性

`Nat` 不提供边界或所属数组的静态保证，因此由构建和导入接口维护以下不变量：

- 每个表达式根和子节点引用都小于其所属节点数组的长度。
- 一个 `RecordedValue` 内的表达式引用不依赖另一份值的节点数组。
- 导入其他值时必须同时映射节点内部引用和数据树中的根引用。
- 普通数字、de Bruijn 索引和投影字段索引不是节点引用。
- 表达式节点构成无环图。按第一阶段契约，子节点必须先于父节点，使子节点下标小于父节点下标；追加导入保留这一性质。

引用调整应集中在类似 `ExprNode.rebase` 和 `RecordedData.rebase` 的函数中，按构造子处理，不能对所有 `Nat` 无差别加偏移量。

内部构建器先生成子节点再追加父节点；导入同时平移数据根和全部结构边。后续精简取消了 Lean 内部的整图和数据树校验，由上述构造算法维护不变量；扩展代码直接构造 `RecordedValue` 时也须遵守所属数组约定。外部 JSON 解码仍按 wire 契约验证根、子引用与节点字段。

## 4. 删除自动 annotations

不再引入 `ExprNodeBody` 与 `ExprAnnotations` 的分层，直接使用 `ExprNode`。表达式捕获器不再自动生成下列信息：

| 当前补充信息 | 新方案 |
| --- | --- |
| 推断得到的 `typeOf` | 由记录器显式调用 `inferType` 并记录 |
| `isProp` | 由记录器显式判断并记录 |
| 自由变量用户名字、声明类型、局部定义值 | 由记录器读取局部声明并记录 |
| 元变量声明名字和类型 | 由记录器读取元变量声明并记录 |
| 应用参数的显式性、类型类参数标记等 | 由记录器按需要计算并记录 |
| 源位置 | 由记录器从语法等来源获取并记录 |
| `headConstant`、展开后的应用参数等派生展示字段 | 不由核心节点自动输出；有需要时显式生成或由消费方从结构推导 |

例如，记录器需要表达式和类型时，可以显式组织以下操作：

```lean
-- 接口使用示意，位于录制器代码中。
let expr ← elabTerm syntax none
let type ← inferType expr
record_value "expression" expr
record_value "type" type
```

普通 `TacticM` 语句并不会因为位于 recorder 中就自动成为隔离捕获。若这些查询或 elaboration 仅为录制服务，应放进相应的隔离捕获任务中；`record_value` 只隔离其自身的转换操作，不能追溯隔离此前已经执行的语句。

补充信息必须在上下文有效时读取。仅保存 `FVarId`，无法在局部声明消失后恢复其用户名字或类型。此责任从表达式导出器转移到了记录器。

可以提供显式调用的通用辅助函数，例如记录局部声明或表达式类型，但它们不应重新变成表达式捕获的隐式步骤。

仅增加一个顶层 `type` 字段不足以维持当前展示能力：表达式内部任意自由变量的名字、类型，以及嵌套应用的参数显式性，都可能被渲染器使用。[第一阶段契约第 4 节](Recording-Value-Contract-zh.md#4-显式展示信息) 已将补充字段固定为显式的 `<field>_display`，按字段/结构出现路径关联，辅助表达式正常参与节点导入。内置记录器显式调用辅助函数，伴随字段关闭引用收集；这些查询不放回核心 `ExprNode` 捕获器。

## 5. 捕获流程

### 5.1 一次捕获共享一个节点构建器

`CaptureM` 使用 `StateT CaptureState TacticM` 维护本次捕获的节点数组。第三阶段保留 `ToRecordedValue` 名称，其内部转换接口为：

```lean
class ToRecordedValue (α : Type) where
  capture : α → CaptureM RecordedData
```

`CaptureM.run` 是纯图捕获的运行边界，负责隔离 Lean 状态，并将结果冻结为 `RecordedValue`。结构捕获原语 `CaptureM.captureExpression` 只实例化元变量并记录结构，不调用旧导出器，也不查询声明或推断类型。

```text
保存 Lean 状态
  → 建立本次捕获的节点构建器
  → 转换普通值、解释语法、捕获表达式
  → 构造 RecordedData
  → 冻结 RecordedValue { data, nodes }
  → 恢复 Lean 状态
  → 返回独立的捕获结果
```

容器转换在当前构建器中运行，不为每个元素建立独立节点表。`CaptureM.run` 直接返回 `RecordedValue`；展示补充信息由 `captureWithDisplay` 显式捕获。第三阶段引入的旧快照包装已在第七阶段删除，随后删除了纯转发别名 `isolatedCapture`。

### 5.2 两类输入路径

语法参数仍通过 `RecordParam` 决定解释方式：

```text
TSyntax
  → 类别对应的解释逻辑
  → Expr 或普通数据
  → RecordedData
```

已有 Lean 值通过转换实例进入同一构建器：

```text
String / Expr / Array α / 自定义类型
  → 对应转换实例
  → RecordedData
```

`ParamCapture` 继续描述尚待执行的捕获任务、输出字段、上下文选择、失败策略和引用收集设置。构造任务不读取当时的表达式状态，执行任务时才捕获。

### 5.3 嵌入已经捕获的值

先捕获、执行 tactic、后提交的用法必须继续支持。转换已经存在的 `RecordedValue` 时：

1. 导入其节点数组。
2. 调整导入节点中的子节点引用。
3. 调整其数据树中的根引用。
4. 保留原捕获时的表达式结构，不重新 elaboration 或实例化。

以上图导入已经实现。先捕获、后执行 tactic、再 `record_value` 时，保存 `CaptureM.run` 返回的 `RecordedValue`，随后导入共享的结构化证明存储。最终统一导出 `0.1.0`，无需格式参数或旧快照。需要局部声明详情时须在有效上下文中显式捕获 Display，提交和导出均不重新推断。

### 5.4 构建缓存

同一次捕获内共享节点存储不等于可以无条件按原始 `Expr` 跨上下文缓存。表达式应在实例化之后按其实际捕获结构处理；缓存作用域和键必须考虑捕获语义。

初版可以使用保守缓存或暂不跨表达式去重。节点共享是可优化项，不是重构正确性的前提。

## 6. 提交与最终导出

### 6.1 一次导入整份节点数组

提交前，证明级节点数组已有 `N` 个节点时，局部节点 `i` 映射为 `N + i`。提交器统一调整：

- `ExprNode` 内的子节点引用。
- `RecordedData.expression` 内的根引用。

然后追加节点并写入当前录制步骤。无需解析字符串 `e42`，也无需扫描用户 JSON 中的 `$ref`。

节点追加、字段写入和引用收集必须属于同一个可回滚操作。重复字段、非法字段名、关闭的录制目标等错误保持当前检查语义。

### 6.2 录制存储层也使用结构化数据

若要真正做到最后才生成 JSON，录制步骤内部不能继续只保存已经编码的字段 JSON。需要调整录制槽和证明级存储，使其保存 `RecordedData`，并引用证明级的共享节点数组。

最终导出时统一编码：

```text
RecordedData.expression 42 → {"$ref": "e42"}
ExprNode                  → 对应表达式 JSON 节点
Array ExprNode            → 最终表达式节点表
```

第一阶段已确定保留 `e0` 格式和对象形式的节点表，目标录制版本升级为 `0.1.0`。这能减少编码迁移范围，但被删除的自动补充字段仍然构成输出行为变化。

保留 `$ref` 编码还需要明确解码边界。当前 `Output/Dependencies.lean` 会扫描步骤中的任意 `$ref`，PS4HTML 也会递归解析整份 `proof`；因此，内部不重写 `plain` 并不足以保证普通 JSON 在最终消费时不被误解。`0.1.0` 使用由 `RecordedData.expression` 自动生成的 `expressionRoots` 路径清单作为边界，并校验声明的表达式字段均已登记。不透明手写契约也使用同一清单，未登记的用户 JSON 不按外形猜测为表达式。具体规则见 [第一阶段契约第 3 节](Recording-Value-Contract-zh.md#3-输出边界expressionroots)。

第四阶段已将录制槽、分支和子证明迁移到结构化存储。过渡兼容只保留在最终导出：默认生成旧快照格式，显式 `.structural` 生成结构节点表及 `expressionRoots`。这一显式新格式出口用于分阶段验证，默认输出与消费方仍在第六阶段统一切换。

## 7. 常量引用收集

### 7.1 不再保存 `references` 字段

引用收集成为对 `RecordedData` 与节点数组的派生操作：

1. 找到数据树中的表达式根。
2. 沿表达式结构引用遍历可达节点。
3. 收集常量名字及常量收集语义要求的其他名称。
4. 去重后加入证明的引用状态。

应从根遍历，而不是扫描整个节点数组，以免将未被实际使用的节点纳入结果。实现应以 Lean 的 `Expr.getUsedConstants` 行为作为兼容性依据，特别核对投影等构造子，而不是仅收集 `.const` 就宣称完全等价。

当前使用的 Lean 4.32 对 `.proj typeName index expr` 只遍历 `expr`，不把 `typeName` 本身加入 `getUsedConstants`。新遍历应保留这个行为；投影的结构名称仍作为节点数据保存。

建议保持当前首次出现顺序：数据根按容器顺序遍历，app 为 fn → arg，lam/forall 为 type → body，let 为 type → value → body，proj 只遍历 expr，常量首次出现时加入结果。去重和节点访问缓存不能改变这一顺序。

### 7.2 不再混入自动查询的类型

例如原表达式为局部变量 `n`，即使其声明为 `n : Nat`，节点也只记录 `fvar id`，不会自动添加声明类型。因此引用收集不会因展示类型而额外得到 `Nat`。

若用户显式把类型记录为另一个表达式字段，则该字段按自身的 `collectReferences` 设置决定是否参与引用收集。

### 7.3 收集策略仍按字段应用

`collectReferences := false` 和全局引用开关继续有效。关闭收集只跳过常量遍历，不影响节点导入和字段写入。

不应对证明级共享节点数组做一次无差别的全局扫描，因为不同字段可能具有不同的引用收集策略。

## 8. 端到端示例

记录某条规则使用的表达式 `Nat.succ n`，结果可以在内存中表示为：

```text
RecordedValue
  data:
    object [
      ("reverse", plain false),
      ("expression", expression 2)
    ]

  nodes:
    0 → const Nat.succ []
    1 → fvar <n 的内部 ID>
    2 → app 0 1
```

如果证明级节点数组已有十个节点，提交后：

```text
10 → const Nat.succ []
11 → fvar <n 的内部 ID>
12 → app 10 11

字段数据：
  { reverse: false, expression: expression 12 }
```

最终 JSON 中的表达式字段为 `{"$ref": "e12"}`。常量引用从根 `12` 派生，得到 `Nat.succ`。

若前端还需要显示名字 `n` 或其类型，记录器必须额外输出对应信息；表达式节点不查询也不补齐这些信息。

## 9. 与重构前架构的对比

| 方面 | 重构前 | 重构后 |
| --- | --- | --- |
| 录制值 | 递归容器中嵌套独立快照 | 数据树与一份节点数组 |
| 节点表 | JSON 对象 | `Array ExprNode` |
| 表达式引用 | JSON 中的字符串 `$ref` | 内部 `Nat` 下标 |
| 表达式信息 | 结构和自动补充信息混合 | 只保存规范化后的表达式结构 |
| 局部声明、类型等 | 导出器自动查询 | 记录器显式查询 |
| 常量引用 | 捕获时保存数组 | 按字段从表达式根派生 |
| 表合并 | 扫描 JSON 并重写引用 | 按构造子映射节点下标 |
| JSON 编码 | 捕获阶段已经开始 | 最终导出边界 |
| 类型有效性 | JSON 结构检查较多 | 节点形状由类型保证，下标由接口保证 |
| 前端依赖 | 可消费自动补充字段 | 消费结构和记录器提供的显式字段 |

主要收益是职责清晰、引用处理明确、减少内部 JSON 往返，而不是预先承诺性能提升。实际内存和时间收益需要测量；数组合并仍需调整引用，也不会自动实现全局去重。

## 10. 评估结论与分阶段实施计划

### 10.1 评估结论

**方案合理，建议实施，但必须作为跨捕获、存储和输出契约的重构推进。** `RecordedData + Array ExprNode` 能消除递归快照各自携带 JSON 表的复杂性；按构造子调整下标、从表达式根派生引用，以及在隔离边界冻结结构，都与当前录制语义相容。使用 `Nat` 和直接使用数组也是可接受的取舍，前提是构建与导入接口维护有效性。

主要风险在迁移边界和展示信息契约，实施前的代码核对结果如下；表中旧依赖和行为现已随重构移除：

| 需要补齐的约束 | 迁移前实现依据 | 对实施的影响 |
| --- | --- | --- |
| 底层类型不能依赖录制运行时 | `Recording/Value.lean → ExprJSON.lean → Script/Core.lean → JsonBox.lean` | `JsonBox` 改存结构化数据前，先拆开类型、捕获和编码，避免 import 环 |
| 删除补充字段会改变实际展示 | `PS4HTML/schema.py` 强制要求 `isProp`；`Lean2TeX/semantic.py` 使用自由变量详情和参数显式性 | 先确定显式补充字段及其关联方式，再切换输出；仅让新 JSON 通过校验不算展示验收 |
| 所有步骤组装路径都要结构化 | `JsonBox.lean` 保存 `Array Json`，`Recording/Strategy.lean` 和 `Script/Embed.lean` 直接组装 JSON | 普通步骤、策略分支和嵌入证明都要迁移到最终编码边界 |
| 普通 `$ref` 需要贯穿消费链路保护 | `Output/Dependencies.lean` 和 `PS4HTML/schema.py` 递归解释引用 | 明确哪些路径是真正的表达式，不对任意用户 JSON 解引用 |
| 表达式导出器还有其他调用方 | `Script/Embed.lean`、`Page/Component/Computation.lean` 直接调用 `Expr2JSON` | 迁移这些入口或明确适配边界后，才能删除旧导出器 |
| 引用状态用途不同 | `Core/References.lean`、`Output/Dependencies.lean`、`Output/Theorem.lean` | 字段引用开关只影响录制引用；渲染依赖和最终证明依赖分别保持自身语义 |

这里的“最后才生成 JSON”针对录制数据与表达式节点的内部表示，不要求把独立的 Info 元数据 codec/schema 或 computation 执行 ABI 一并重写。

### 10.2 阶段划分与依赖

| 阶段 | 交付结果 | 前置条件 |
| --- | --- | --- |
| 一 | 固定结构语义、展示契约和切换策略 | 无 |
| 二 | 独立的类型、图操作和纯编码器 | 阶段一的结构语义 |
| 三 | 共用构建器的捕获与转换接口 | 阶段二 |
| 四 | 结构化提交、证明存储和最终导出 | 阶段三；阶段一的表达式边界约定 |
| 五 | 显式展示信息及全部生产入口迁移 | 阶段三；阶段一的展示契约 |
| 六 | 消费方迁移与新协议整体切换 | 阶段四、五；消费方开发可提前并行 |
| 七 | 删除旧路径并完成整体验收 | 阶段六 |

阶段四和五可在阶段三后并行；协议版本和默认输出在阶段六统一切换。每个阶段应保持可编译和相关测试通过。可以使用临时适配层，但新结构缺失的上下文信息不能在恢复 Lean 状态后交给旧导出器重新推断。

### 阶段一：固定语义、输出与验收基线

**状态：契约与基线产物已完成。** 具体决定、字段迁移表、示例和验证记录见 [第一阶段契约](Recording-Value-Contract-zh.md)。本阶段的新格式 schema/fixture 当时仅为后续实现目标；当时的普通构建与页面录制失败均已单独记录，并于第六阶段解决。

**任务：**

- 固定已赋值表达式及 universe 元变量的实例化、未赋值元变量保留、`mdata` 剥离、投影和 binder 的语义。
- 固定根和子节点下标校验、无环性、节点顺序及非法手工值的报错边界；明确节点编号只是导出内引用，不是稳定业务标识。
- 建立补充信息依赖清单，覆盖 `isProp`、`typeOf`、自由变量名字/类型/值、应用参数显式性、源位置。逐项决定显式提供、由结构推导或允许缺省的行为。
- 定义补充字段与根、内部节点或局部声明的关联方式、导入时的映射方式，以及字段级 `collectReferences` 设置。覆盖目标快照和嵌套表达式，不能只设计顶层表达式的类型字段。
- 明确普通 JSON 与表达式引用的输出边界，覆盖声明式 schema、嵌套容器和不透明手写契约。
- 保留外部 `eN` 节点表编码，将目标录制协议固定为 `0.1.0` 并要求重建旧缓存；列出 `Script/Contract.lean`、Info snapshot/输出协议、Python 校验器和静态 schema 的版本关联，分别判断是否需要升级。
- 选取已有录制、引用、目标展示、变量命名及嵌入/computation 用例，记录允许变化的字段和必须保持的行为。比较表达式结构时不依赖旧节点编号。

**完成条件：** 有明确的字段变化表、补充信息示例、引用边界示例和版本切换规则；每个现有展示依赖都有处理决定。尚未决定如何展示变量和筛选隐式参数时，不开始删除自动字段。

### 阶段二：建立独立的类型与图操作

**状态：已完成。** 底层实现位于 [Data.lean](../ProofScript/Script/Recording/Data.lean) 和 [Encoding.lean](../ProofScript/Script/Recording/Encoding.lean)，通过 `ProofScript.Script.Recording` 导出；`ExprNode.lean` 与 `Value.lean` 已于 2026-10-21 合并为 `Data.lean`。当时的 API 回归模块为 `RecordingValueGraphTest.lean`，已于第七阶段按用户要求删除。

**主要范围：** 新的底层类型模块、`Recording/Value.lean`、表达式纯编码模块。底层类型只依赖 Lean 及必要的纯数据模块，不能反向依赖 `ExprJSON`、`JsonBox` 或 tactic 捕获器。

**任务：**

- 实现 `ExprNode`、`RecordedData`、`RecordedValue`，保留普通 JSON 的原样承载能力。
- 实现按构造子处理的 `ExprNode.rebase`、`RecordedData.rebase`、整份值的导入/组合与有效性校验；组合值不经过 JSON。
- 实现根可达性遍历与常量收集，按第一阶段的 Lean 4.32 基线保持 `.proj` 等行为、首次出现去重和输出顺序。
- 实现不读取 Lean 环境、局部上下文或元变量状态的最终 JSON 编码器，包括 `Level`、`Literal` 和 `BinderInfo` 的编码。
- 明确未提交值与引用证明级节点数组的数据的接口边界，避免把局部下标错误用于证明级存储。无需为此额外引入 ID 包装类型。

**完成条件：** 多份值导入后所有根和边正确；bvar/投影索引和普通 JSON 不变；越界、循环等非法输入明确失败；纯编码不需要有效 tactic 上下文。

**本阶段实现的接口边界（历史记录）：** `RecordedValue.validate` 校验全部节点（含不可达节点）及数据根；`array/object` 组合独立值，保留捕获时的字段顺序；`importInto` 返回指向完整目标数组的 `(RecordedData, Array ExprNode)`，不能将其中的数据再次当作局部快照导入。`reachableNodes/references` 只从真实数据根遍历，保持常量首次出现顺序。当时可能失败的入口均返回 `Except String`。第七阶段之后删除未使用的组合便利函数，将引用遍历合并为 `references`，并在后续审查后移除内部校验及相应 `Except`。

`RecordedValue.encode` 输出自包含的 `{data, expressions, expressionRoots}`，路径相对整个输出并以 `"data"` 开始；它不是最终 proof 文档。`RecordedData.expressionRoots` 提供相对数据树的路径，第四阶段在最终 owner 组装时添加 `proof` 等前缀。没有新增 `ToJson RecordedValue` 实例；后续移除内部校验后，`encode` 直接返回 `Json`。

**本阶段的过渡层：** 旧递归快照曾移至 `LegacyValue.lean` 的 `ProofScript.Recording.Legacy` 命名空间，该模块已于第七阶段删除。第二阶段完成时捕获链路仍使用旧模型；第三阶段将 `RecordParam`、`ToRecordedValue` 和复合捕获迁入新图构建器。以下过渡说明保留当时状态。

**验证：** 新图操作测试的六组检查通过，覆盖独立根合并、共享/不可达节点、全部构造子、普通 JSON、路径及非法图拒绝；新纯模块与旧捕获链路均编译通过。22 项 Python 契约/旧行为检查通过。普通 `lake build` 中新的默认测试通过，其余失败仍为第一阶段记录的三个 `JsonPath.Part.field` 测试目标；`lake build TestPage:pageTests` 仍为第一阶段记录的 10 个失败目标。两次构建的错误诊断集合分别与第一阶段一致，没有新增诊断；日志为 `/private/tmp/recording-value-phase2-build.log` 和 `/private/tmp/recording-value-phase2-page-tests.log`。

### 阶段三：迁移共享构建器与捕获接口

**状态：已完成。** 新增 [Capture.lean](../ProofScript/Script/Recording/Capture.lean) 和临时适配层 `LegacyCapture.lean`；后者及本阶段的 `RecordingCaptureTest.lean` 已于第七阶段删除。

**主要范围：** `Recording/Codec.lean`、`Conversion.lean`、`Plan.lean`、`Complex.lean`、`Recorder.lean` 及 `Script/Basic.lean` 的复合值构造点；`Engine.lean`、`Runtime.lean` 仅调整捕获与旧提交之间的适配边界。

**任务：**

- 实现 `CaptureM` 及其运行边界：一次完整捕获创建一个构建器，成功后冻结 `{ data, nodes }`，成功和失败均恢复临时 Lean 状态。
- 将纯结构捕获与 elaboration、`inferType` 等显式查询分开；在实例化后捕获节点，不在提交时再次实例化。
- 迁移已有值转换和 `RecordParam`，让 `Array`、`List`、`Option`、对象等共用构建器。`ToRecordedValue` 名称可以暂留为外层入口。
- 迁移 location、rw/simp、config、calc 和 infer 链等复合捕获，保留字段/schema 形状、捕获时机及 `none → null` 行为。
- 导入已有 `RecordedValue` 时同时映射节点和数据根，支持捕获后执行 tactic、局部声明消失后再提交。
- 保持 `ParamCapture` 的延迟执行、before/after、上下文选择及 required/best-effort 策略；处理嵌套捕获和捕获内部失败时构建状态的清理。
- 保持每个参数独立隔离 Lean 状态，不把整个参数批次改成共享 elaboration 状态。`Complex.lean` 的 simp erase 路径会在嵌套 `tryCapture` 失败后继续，必须同时恢复子捕获的节点数组和缓存，或使用独立子构建器并只在成功后导入。
- 初版不做跨捕获去重；同次捕获内的缓存若启用，使用实例化后的结构并明确作用域。

**完成条件：** 捕获失败不改变证明和外层构建状态；捕获成功不提交临时 elaboration；后续元变量赋值、目标切换或局部声明消失不改变快照。复合值只携带一份节点数组。

**已实现的捕获边界：**

- `CaptureM.captureExpression` 按子节点先于父节点的顺序追加全部表达式构造子，实例化已赋值的表达式/universe 元变量，剥离所有 `mdata`；保留开放 bvar 和未赋值 ID，不执行类型推断或声明查询。初版不启用缓存或去重。
- `CaptureM.run` 每次创建独立构建器，校验并返回 `{ data, nodes }`；成功和失败均恢复目标、元变量、环境、消息及 elaboration 状态。嵌套在生产兼容捕获内的纯运行也不启用旧展示查询。
- `ToRecordedValue.capture`、`RecordParam.capture` 和 `ParamCapture.capture` 均返回 `CaptureM RecordedData`。Array/List/Option 与对象组合共享节点数组；`none` 仍为普通 `null`，用户 JSON 保持不透明。location、rw/simp、config、calc 和 infer 链均已迁移，schema、字段顺序、捕获时机和失败策略保持。
- `tryCapture` 共享外层构建器，但隔离临时 Lean 状态；成功仅保留捕获数据，失败同时回滚节点与兼容快照。每个参数仍分别运行隔离捕获，参数批次不共享临时 elaboration。

**临时生产兼容边界：** `isolatedCapture` 返回 `CapturedValue`，其中 `value : RecordedValue` 是纯图，`legacyExpressions` 是独立的旧展示快照映射。Codec 在当前上下文有效时显式观察表达式叶子；旧导出查询另行隔离，不能影响已冻结的结构或后续捕获。旧快照不进入 `RecordedValue`，提交只消费冻结结果，不再查询已经消失的局部上下文。引用已改为从纯图的字段根派生。

`CapturedValue` 可经 `ToRecordedValue` 导入新构建器，图下标和旧快照映射的根下标一起重定位，快照内部的旧局部表保持原编号。当前先捕获后提交的用法如下，局部声明随后消失也不影响提交：

```lean
let saved ← isolatedCapture (expression h.raw)
execute_recorded
record_value "hypothesis" saved
```

纯图用 `CaptureM.run (ToRecordedValue.capture value)` 获取。纯 `RecordedValue` 的导入不重新实例化、不查询旧上下文。第三阶段曾在兼容捕获时拒绝缺少旧快照的表达式；第四阶段将该检查推迟到最终 `0.0.0` 导出，允许纯值提交到新存储及显式结构化导出。兼容层将在显式展示和协议迁移后删除；第三阶段本身未切换生产协议或证明存储。

**定向验证：** 新增 10 组实际 `TacticM` 回归测试通过，覆盖结构和元变量冻结、导入校验、共享容器、成功/失败状态恢复、嵌套成功与失败回滚、纯运行边界、相邻参数隔离、best-effort，以及局部声明消失后兼容快照的重定位和真实提交。捕获链路与 `Script.Basic` 编译通过；22 项 Python 契约及旧行为检查通过。

**完整构建对照：** 普通 `lake build` 的新增默认测试通过，仍有此前的 3 个 `JsonPath.Part.field` 测试目标失败，共 11 条诊断；`lake build TestPage:pageTests` 仍有此前的 10 个目标失败，共 39 条诊断。失败目标与错误诊断集合均与第二阶段一致，无新增诊断。日志为 `/private/tmp/recording-value-phase3-build.log` 和 `/private/tmp/recording-value-phase3-page-tests.log`；这些基线失败尚未修复，因此本阶段不宣称全库或全部页面测试通过。

### 阶段四：迁移提交、证明存储与最终编码

**状态：已完成。** 共享存储及当前最终编码位于 [JsonBox.lean](../ProofScript/Script/JsonBox.lean)；当时的独立 `ProofEncoding.lean` 已在后续精简时合并到出口。当时新增的 `RecordingStorageTest.lean` 和 `RecordingProofEncodingTest.lean` 已于第七阶段删除。

**主要范围：** `Recording/Engine.lean`、`Runtime.lean`、`Script/JsonBox.lean`、`Recording/Strategy.lean`、`Page/Component/Declaration.lean`、`Output/Dependencies.lean`。

**任务：**

- 在可回滚的证明会话中保存共享 `Array ExprNode`；节点、录制槽与引用状态必须一起随回滚恢复，不使用无法被 Lean 状态恢复的全局可变存储。
- 将提交改为校验并一次导入整份数组，再写入映射后的 `RecordedData`；按该字段的数据根派生引用。
- 将 `RecordingState.boxes`、slot 读写、`takeBoxWithContracts`、子证明和策略分支组装迁移到结构化数据，保持稳定 slot 定位及 contract binding 路径。
- 保持字段名、重复字段和关闭步骤检查，以及单字段、参数批次、嵌套步骤与策略完成的事务边界。捕获总是恢复状态；提交仅失败时回滚，二者不能混用。
- 将 JSON 编码集中到 `recordedProofJson` 等完整输出边界；之后可以继续基于已编码 document 做契约校验、内容摘要和 artifact 登记。
- 修改渲染依赖遍历，使它只解释真实表达式根及显式展示信息，不扫描普通 JSON 中的 `$ref`；不让 `collectReferences := false` 隐藏渲染所需依赖。
- 更新 theorem/session 初始化和清理，保持连续证明、嵌套会话及 code-only 证明的行为。

**完成条件：** 录制槽和分支合成阶段不再将表达式编码为 JSON；任一提交或批次失败均不遗留节点、字段、引用或 binding；最终 document 的引用、路径及摘要自洽。

**已实现的存储与提交边界：** `RecordingState` 在同一个非持久化环境扩展中保存 `boxes : Array (String × Array RecordedData)`、共享 `nodes : Array ExprNode`、冻结的旧展示快照及 slot/contract/routing 状态。局部图导入校验后一次追加，节点子引用、数据根及旧快照的根索引统一重定位；普通 JSON 不参与映射。提交仅在失败时回滚，捕获仍在成功和失败时均恢复临时 Lean 状态。字段检查、批次提交、嵌套步骤及策略完成的原有事务边界保持；引用从被提交字段的局部图根派生，关闭收集时跳过常量遍历。

`takeBoxWithContracts`、slot 读写、策略分支和嵌入证明均传递 `RecordedData`，不再在组装阶段合并 JSON 表。子证明取出后仍引用同一份证明级节点数组，最终嵌套位置确定后才生成表达式根路径和 invocation 路径；slot 使用预留索引，后续嵌套录制不改变其位置。`withRecordingSession` 已推广到 tactic/command 可共用的作用域，退出后恢复此前会话，同时保留正常产生的声明。

**最终导出与兼容：** `recordedProofJson box code owner` 从当前会话取得所有数据，调用纯 `encodeProof`，随后校验 contract binding、收集渲染依赖、计算完整文档摘要并登记 artifact。默认 `.legacy` 输出 `0.0.0`，仅此时合并冻结的旧快照表；不再借助活跃的旧表达式导出器保存证明级表。显式 `(format := .structural)` 输出 `0.1.0` 的结构节点表与 owner-relative `expressionRoots`，无需旧快照。纯图现在可以提交；若最终选择旧格式且缺少兼容快照，则在导出边界明确报错。默认协议版本和消费方均未切换。

渲染依赖只沿编码器提供的真实表达式根与表达式构造子/展示字段遍历，普通 JSON 中合法或缺失的 `$ref` 均不参与依赖推断；字段引用收集关闭不影响渲染依赖。Invocation 校验也使用结构化组装产生的步骤路径，不把普通 JSON 内的 `_ruleId` 或 `proof` 误认为子证明。旧格式的路径清单仅在内部用于这两项校验，新格式才对外导出表达式根清单；消费端对普通 JSON 的完整保护仍由第六阶段完成。

**保留的独立边界：** `@computation` 的执行 ABI 与表达式导出暂沿旧路径保留，按第五阶段迁移。嵌入证明在本阶段仅完成结构化捕获/组装及整步事务适配，其显式展示契约仍属第五阶段。

**验证：** 新增 8 组实际 `TacticM` 存储测试和 5 组纯编码测试通过，原有 10 组捕获测试适配结构化提交后通过；三个测试目标联合构建成功。覆盖单字段/批次/嵌套步骤/策略失败后的节点、快照、字段、引用与 binding 回滚，稳定 slot、子证明路径、普通 JSON 和假子步骤的不透明性、缺少或非法旧快照、渲染依赖与引用开关、连续/嵌套会话及 code-only 输出。策略、嵌入、声明与 recorder DSL 目标构建通过。22 项 Python 契约及旧行为检查通过。

真实会话中的完整 `recordedProofJson ... (format := .structural)` 输出另经目标 `0.1.0` JSON Schema 校验通过，含 6 个节点、2 个表达式根；普通数据中的 `e0`、`e999` 引用原样保留且不进入根清单。产物为 `/private/tmp/recording-value-phase4-structural-smoke.json`，临时程序为 `/private/tmp/RecordingValuePhase4StructuralSmoke.lean`。

普通 `lake build` 仍只有此前的 3 个 `JsonPath.Part.field` 测试目标失败，共 11 条诊断；`lake build TestPage:pageTests` 仍只有此前的 10 个目标失败，共 39 条诊断。完整错误消息块及失败目标集合与第三阶段一致，没有新增诊断；不宣称全部测试通过。日志为 `/private/tmp/recording-value-phase4-build.log`、`/private/tmp/recording-value-phase4-page-tests.log`，定向测试日志为 `/private/tmp/recording-value-phase4-focused.log`。

### 阶段五：迁移显式展示信息与全部生产入口

**主要范围：** 默认/内置 recorder、目标快照、`Script/Basic.lean`、`Script/Embed.lean`、`Page/Component/Computation.lean`。

**任务：**

- 提供显式调用的类型、局部声明和应用参数信息捕获辅助函数；将仅服务录制的查询放在隔离捕获内，并在上下文失效前完成。
- 按阶段一的契约为内置 recorder 和目标快照补充展示字段；覆盖嵌套 fvar、binder、应用及局部定义值，验证伴随表达式导入后的关联。
- 为这些补充字段明确引用开关，防止展示类型无意增加引用；核心结构捕获仍只输出结构。
- 将 `embed` 的直接 `Expr2JSON` 调用、子证明回放、参数和目标字段接入新捕获/存储链路，保持子证明 contract binding 的路径。
- 迁移 `@computation` 的函数/实现表达式和节点表，使该入口也使用新捕获与输出编码；若独立协议尚未切换，标注适配层及删除条件。保持其执行 ABI 的独立边界。
- 更新手写 recorder 与自定义 `ToRecordedValue` 的迁移示例，说明如何显式获取补充信息和组合已有快照。

**完成条件：** 所有现有表达式生产入口均有新实现或明确的临时适配；所需展示信息已在有效上下文中冻结；无需恢复旧的隐式 annotations 才能展示。

**实施状态：已完成（2026-10-21）。**

- 新增 `Recording/Display.lean`：`displaySchema` 固定 marker 与对应字段 literal；`captureWithDisplay` 同时冻结主值、occurrence hints 及声明类型/局部值辅助表达式。应用显式性覆盖全部参数位置；开放项不做 Meta 推断，查询失败保留未知值；源范围显式启用，根 Syntax 优先。元变量的辅助类型使用其自身声明上下文；辅助查询设循环和规模上限。
- `CaptureState` 保存本次显式观察的冻结结果，使 `tryCapture` 成功时保留、失败时丢弃对应观察、节点及旧格式 sidecar。核心 `captureExpression` 不调用观察器，普通 `record_value` 和自定义转换不自动升级展示契约。
- `captureFieldWithDisplay` / `recordCapturedWithDisplay` 校验两个字段名及伴随字段归属，单次导入后原子写入。缺失或 best-effort 失败同时写入两个 `null`；引用只从主值的可达图收集，展示辅助表达式仍参与根清单及渲染依赖。
- 自动生成器依据 codec schema 显式启用伴随捕获；`withDisplayFields` 同步扩展输出契约，声明时检测伴随字段碰撞。`both` 使用最终字段名生成 `<field>_before_display` / `<field>_after_display`。Basic 的目标、cases_by、contra、latex、calc、infer 和嵌套复杂参数均接入同一路径。
- embed 显式声明并捕获目标、类型、参数、假设及表达式证明的展示；回放的子证明保持原 contract binding 路径，证明数组的 `proof_display` 为 `null`。computation 新增独立的 `ComputationEncoding`：函数与实现及辅助表达式共用函数自有节点表，`.structural` 输出 `recordingVersion = "0.1.0"` 和相对于 `function` 的根路径。
- README 中补充显式展示、先捕获后提交、嵌套自定义转换及 computation 边界示例。保存已有快照只重定位图，不会在提交时重查原声明。

**保留的临时边界：** 默认证明和 computation 导出仍为 `0.0.0`，只使用已冻结的兼容快照；computation 默认保留原有五个函数字段。组件/pending/bundle 版本及 `proofscript-json-v1` 执行 ABI 不变。生产入口中的直接 `Expr2JSON` 调用已收拢到 `LegacyCapture`；消费端统一切换前保留该适配，随后按第六、七阶段删除。新 Display 的生产与结构化导出已完成，尚未宣称现有页面消费者已使用新 hints 渲染。

**验证：** 新增 13 组 Display 语义/事务测试、5 组实际 producer 测试、3 组 embed 测试和 5 组 computation 检查，连同既有图、捕获、存储、纯编码测试均通过。producer 测试直接运行 recording session，覆盖 intro/exact、rw/simp、cases_by、calc/infer；computation 在测试内显式设置实际读取的页面选项，执行真实命令并检查新写出的 pending 文件，避免弱选项未生效时静默跳过。22 项 Python 检查通过。真实 `.structural` 证明通过目标 schema，两个伴随字段也独立通过 Display schema；共 35 个节点、3 个表达式根，普通 JSON 中的 `e0` / `e999` 原样保留。定向日志为 `/private/tmp/recording-value-phase5-focused.log`，结构化产物为 `/private/tmp/recording-value-phase5-structural.json`。

最终普通 `lake build` 仍为原有 3 个目标、11 条诊断；`lake build TestPage:pageTests` 仍为原有 10 个目标、39 条诊断。完整错误消息块及失败目标集合均与第四阶段一致，没有新增失败；不宣称全量构建通过。日志为 `/private/tmp/recording-value-phase5-build.log`、`/private/tmp/recording-value-phase5-page-tests.log`。

### 阶段六：迁移消费方并统一切换协议

**实现状态：已切换默认协议与消费入口。** `Script/Contract.lean`、Python recording 常量及正式录制 schema 同步为 `0.1.0`。`isolatedCapture` 的生产路径只运行纯构建器，不再查询或保存旧展示快照；proof、code-only 及 computation 函数默认使用结构编码。旧路径须显式选择 `isolatedLegacyCapture` / `.legacy`，暂留第七阶段清理。

**主要范围：** `tools/ps4html/PS4HTML/{schema,recording,info,render_rules}.py`、`Lean2TeX`、内置展示配置、录制及相关资源 schema、输出版本常量和文档。

**任务：**

- 更新表达式节点校验，移除对自动 `isProp` 等旧字段的强制要求，同时检查新构造子字段、根引用和无环性。
- 按明确的表达式边界解引用；普通 JSON 中即使有合法或不存在的 `eN`，也保持用户数据语义。
- 让 Lean2TeX 使用结构与显式展示信息；`headConstant` 和扁平应用参数可由结构派生，但参数显式性及局部声明详情不能仅靠结构臆造。
- 核对 `arguments := explicit` 等内置展示配置，验证隐式/实例参数筛选、自由变量名字、变量类型分类、hover、binder 和局部定义的行为。
- 更新步骤 schema、模板字段、嵌入证明、computation 表达式消费及相关文档示例；按阶段一确定的列表同步录制版本、契约/snapshot 校验和静态 schema。
- 一次切换默认输出与消费方；旧缓存按约定明确报错并要求重新导出，避免把新字段契约静默当成旧协议。

**完成条件：** 新导出能通过 schema、构建页面并正确渲染关键样例；旧缓存行为符合约定；普通 JSON 不被解引用；补充字段缺省时采用已约定的行为。

**已实现行为：** Python 严格检查连续节点 ID、构造子字段、仅向前序节点的子引用和根清单。只有注册路径解析为表达式；普通 JSON 的 `$ref/kind/isProp` 和 Display marker 均不触发解释。Display 按完整调用契约识别，验证结构边路径、辅助 view 引用与无环性；名字、类型、局部值、位置及参数 binder 信息按 occurrence 保存，不按节点 ID 共享。渲染依赖同样按完整 Display schema 读取显式信息。

Lean2TeX 从结构推导应用头与参数顺序，使用显式 hints 筛选隐式/实例参数、分类变量并生成声明类型/局部值的悬停提示。缺少完整 `appBinders` 时保留完整应用并报告 `L2T011`；缺少声明信息时不推断类型或名字。binder/bvar 联动、投影、let、策略分支和 embed 使用对应结构及实际 invocation 路径。

`InfoBundle`、ResourceLoader、页面和 computation provenance 都检查新录制版本；旧 proof/index/snapshot/contract 或缺失新函数版本时提示重新运行 `lake build <Library>:ps4html`，缓存命令不迁移内容。computation 的节点表及根路径相对于自己的 `function`；外层 component/pending/bundle 仍为 `0.0.0`，执行 ABI 仍为 `proofscript-json-v1`，finalizer 保留完整 function 数据。

**页面模式修正：** `pageBuild` 的注册使用明确的 `proofScript.pageBuild` 选项键，和读取器/Lake 保持一致；此前弱选项可能未实际启用页面模式。真实双包页面集成已通过新格式导出、渲染以及普通/页面编译产物隔离检查。旧页面测试中的 `headConstant` 断言改为结构应用头及显式 Display 检查；五处测试文件的 `JsonPath.Part.field` 引用同步为现有 `.key` API。

**验证记录（2026-10-21）：**

- `lake build` 全部通过（3104 jobs）；`lake build TestPage:pageTests` 全部通过（3127 jobs）。第一至第五阶段记录的旧失败不再作为本阶段的未解决基线。
- 七个 Python 测试文件共 72 项通过：契约形状、消费者语义、渲染、版本门禁、元数据作用域、未录制步骤及构建流程。真实双包页面模式集成另 1 项通过，验证页面与普通产物隔离、导出、渲染及返回验证模式。
- `node --test Test/test_computation_build_paths.mjs Test/test_computation_recording.mjs` 的 4 项通过，验证隔离路径、finalizer 完整保留 function，以及浏览器对旧函数录制版本的拒绝。
- `examples/site` 的 `lake build PS4HTMLDemo:ps4html` 完整通过，包含 Wasm 构建与 finalize；4 个页面、34 份证明均被新消费者接受，34 份证明另经正式 schema 校验。实际证明图共 2803 节点、795 根；这些是当前产物计数，不用于声称性能提升。Fibonacci 的资源完整性、真实执行及错误分支检查通过。
- Chrome 变量悬停回归通过 19 个实际字符位置，并验证新格式名字、类型/局部值提示及缺省行为；真实站点浏览器检查覆盖 34 个 theorem 区域及精确依赖边/跨页链接，独立定理导航交互回归通过。
- 示例渲染报告只有 `L2T001/L2T009`（各 108 条，未配置声明宏的可见回退），没有缺失参数 binder 信息的 `L2T011`。构建保留既有 Lean linter 及 Wasm linker 警告；Wasm 实际执行检查通过。

主要日志：`/private/tmp/recording-value-phase6-{build,page-tests,python,integration,site}.log`；最后的契约等价修正亦经完整页面复验通过，记录在 `/private/tmp/recording-value-phase6-page-final.log`。本阶段没有删除显式 legacy 适配器，第七阶段仍须完成旧实现和 API 清理及性能对照。

### 阶段七：清理旧实现并完成整体验收

**实施状态：已完成，清理及整体验收均通过（2026-10-21）。**

**任务：**

- 移除 `ExprSnapshot`、递归快照提交、JSON 表合并与字符串重写、旧自动补充逻辑和不再使用的转换/配置。确认 `embed` 与 computation 无遗留调用后再删除旧 `ExprJSON` 路径。
- 检查公开 `ToJson RecordedValue` 等旧 API：局部引用若未连同节点表导出会产生不完整数据，应移除或改成明确的完整导出入口，并更新调用方。
- 按用户最终要求删除本次重构新增的测试文件与 fixture，并移除对应构建 roots；保留原有测试及其新接口适配，通过已有语义检查、临时探针和真实页面验收覆盖第 11 节。
- 运行普通构建与 `lake build TestPage:pageTests`，分别验证原生证明和真实录制路径；仅普通 `lake build` 通过不足以验收录制重构。
- 运行 PS4HTML 相关 Python 检查、页面模式集成和示例站点构建，检查表达式渲染、变量 hover、策略、嵌入证明和依赖导航；必要时运行相应浏览器回归。
- 用阶段一选取的代表性样例对比节点数、导出大小、耗时和内存；只报告实测结果，不将全局去重或性能提升作为未经测量的结论。

**完成条件：** 新链路覆盖全部生产与消费入口，第 11 节验证通过；旧路径及过渡适配层已删除，或独立协议的保留原因和后续删除条件已明确记录。

**已完成的清理：**

- 删除 `Script/ExprJSON.lean`、`LegacySnapshot.lean`、`LegacyValue.lean`、`LegacyCapture.lean` 和 `CapturedValue.lean`。旧 `ExprJsonConfig`、自动推断导出、递归快照提交、JSON 合表及 `$ref` 字符串重写随模块删除。
- 删除 `RecordingFormat`、`.legacy`/`.structural` 选择参数、旧 snapshot sidecar 和 legacy capture hook。当前捕获入口统一为 `CaptureM.run`，直接返回 `RecordedValue`；嵌套捕获仅保留图和显式 Display observations。`RecordingStep.recordValue` 直接完成导入与引用收集，完整证明在 `recordedProofJson` 中检查步骤契约并编码，固定使用新协议。
- `RecordedValue.encode : Json` 是独立值的完整编码入口。`ComputationFunction` 只保存一份 `recording : RecordedValue`；函数和组件删除可能遗漏节点表的 `ToJson`，统一通过 `.encode : Except String Json` 检查函数协议字段并完整导出。独立的组件/pending/bundle 版本与执行 ABI 保持其自身协议。
- 渲染依赖收集删除 `typeOf`、旧扁平 `arguments`、mdata 及 fvar/mvar 内嵌声明的旧遍历。Lean2TeX 删除旧 mdata 解包、无调用别名、未用参数和不可达分支；名字与类型仍来自显式 occurrence Display。
- 删除本次新增的 9 个 Lean、4 个 Python、1 个 Node 测试源码及 1 个 fixture，移除默认 `Test` 中的 9 个 roots；保留全部原有测试。删除迁移期间重复的版本 schema，契约统一链接正式 schema。历史阶段的测试结果仅作为当时记录。
- 清除这些测试和旧模块遗留的构建产物、测试 pending 输出，以及本次重构的临时验证源码；原有 `RecorderDSLTest` 去掉旧表达式导出会话包装，使用当前录制会话。
- 补查默认导入闭包之外的可选 `Script.Embed`，删除残留的过渡包装字段访问。单独编译该模块，并以真实 Lean Info bundle 验证 script replay 与普通 expression 两条路径；中英文共 4 次实际 `ProofEngine` 渲染均无诊断，覆盖内层证明的契约分派、Nat 实参展示及嵌套渲染。

**清理后的验证记录（2026-10-21）：**

- `lake build` 全部通过（3089 jobs），`lake build TestPage:pageTests` 全部通过（3122 jobs）；可选 `ProofScript.Script.Embed` 独立构建通过（62 jobs）。
- 保留的 Python 元数据作用域、未录制步骤及构建流程测试共 29 项通过；真实双包页面模式集成另 1 项通过，验证普通/页面产物隔离、导出、渲染、返回验证模式及组合目标。既有 Node computation 构建路径检查 2 项通过。
- Chrome 变量悬停回归覆盖 19 个实际字符位置，并检查联动高亮、作用域、类型/局部值及缺省行为；独立定理导航交互回归通过。
- 删除临时源码前运行 5 组核心语义探针，覆盖元变量及宇宙冻结、成功/失败捕获隔离、嵌套捕获的节点与 Display observations 回滚、局部上下文消失后提交、普通 JSON、引用重定位和根清单，以及非法图/重复 key 的原子失败，全部通过。
- `examples/site` 的 `lake build PS4HTMLDemo:ps4html` 完整通过，包含页面编译、导出、Wasm 构建、finalize 与四页渲染。4 个页面的 34 份证明全部通过正式 schema 校验，实测共 2803 个节点、795 个根。真实 Wasm 资源 hash/byteSize、函数录制版本、Fibonacci `n = 10 → 55` 及错误分支检查均通过。
- 真实站点 Chrome 验收通过，覆盖 34 个 theorem 区域、精确直接/反向依赖、跨页链接、lemma 翻译、组件与证明的 snapshot 关联，以及唯一活动导航图。渲染报告仅有未配置声明宏时的 `L2T001/L2T009` 可见回退，各 108 条，没有 `L2T011`；构建保留既有 Lean linter 与 Wasm linker 警告，Wasm 实际执行检查通过。
- 最终只读审查确认新增测试、fixture、旧模块、对应构建缓存及 Lake roots 均已移除，生产 Lean/Python/JS/脚本没有已删除接口的引用；staged 与 unstaged 的 `git diff --check` 均通过。

主要日志：`/private/tmp/recording-value-phase7-{build,page-tests,python,integration,embed-build,hover,navigation,semantics,site,wasm,site-browser}.log`；可选 Embed 的实际渲染报告为 `/private/tmp/recording-value-phase7-embed-render-report.json`，整站 schema 计数与渲染诊断分别为 `/private/tmp/recording-value-phase7-site-schema-report.json`、`/private/tmp/recording-value-phase7-render-diagnostics.json`。临时验证源码和构建产物已删除，仅保留报告与日志。

**性能实测：** Lean 4.32.0，同一局部上下文中预先 elaboration 三类表达式，每份 envelope 捕获 8 个重复根，每类执行 20 轮捕获及紧凑 JSON 编码。旧列使用删除前保存的 `Expr2JSON` 与 `mergeExprJsonSnapshot`；新列分别使用纯结构捕获和生产所用的显式 Display 捕获，并包含结构引用收集。下表各格为「每份 envelope 节点数 / UTF-8 字节数 / 20 轮毫秒数」。

| 样例 | 旧自动补充及合表 | 新纯结构 | 新显式 Display |
| --- | ---: | ---: | ---: |
| `n + 0 = n` | 704 / 137567 / 465 | 248 / 15682 / 45 | 264 / 50890 / 252 |
| `fun x : Nat => let y := x + 1; y + n` | 656 / 130899 / 426 | 368 / 24026 / 60 | 376 / 71386 / 294 |
| `p.1 + n`，`p : Nat × Bool` | 648 / 126866 / 418 | 184 / 11530 / 30 | 232 / 43586 / 216 |

三种模式分别在新进程运行；包含 Lean 启动和导入的墙钟耗时为 7.671 / 4.823 / 5.015 秒，`wait4` 记录的进程峰值 RSS 为 1283686400 / 1295679488 / 1264566272 字节。进程内存主要包含 Lean 与依赖载入，本次测量不能证明内存下降。新旧导出语义和根清单开销不同，这也不是完整旧生产链或整站的统计基准；这里只报告这次本地实测，不能推广为全局性能或去重结论。原始结果保存在 `/private/tmp/recording-value-phase7-benchmark.json`，临时基准源码和旧导出器副本已删除。

**后续精简（2026-10-21）：** 删除 `isolatedCapture`、`commitValue`、`commitRecordedValue`、`EncodedProof` / `encodeProof` 及 `ProofEncoding.lean`，将写入和最终导出分别收敛到现有入口。删除生产代码未使用的 `RecordedValue.expression/array/object`；容器继续通过 `ToRecordedValue.capture` 组合。引用收集直接遍历数据树与可达节点，删除 `expressionIds/reachableNodes` 和中间数组；codec 叶子只实例化一次，再把同一冻结表达式交给显式 Display。保留单次写入、Display 成对写入及批次的事务，仅删除私有捕获路径上重复的回滚。当轮 `Value.lean` 从 153 行减至 102 行。

保留 `ExpressionObservation` 作为当前捕获的展示结果回滚状态；保留私有 `OutputFieldsValue`，因为 Lean 现有安全的配置解释入口不能直接求值一般计算得到的字段数组，替换会引入 `unsafe` 或更复杂的实例。没有用元组或新的包装类型替代已删接口。

精简后 `lake build`（3088 jobs）、`lake build TestPage:pageTests`（3121 jobs）及包含可选 Embed 和 computation 的定向构建（68 jobs）全部通过。临时语义检查验证捕获时的表达式/宇宙冻结、显式 Display、嵌套失败回滚、引用顺序、重定位、普通 JSON 边界和函数相对根路径；另 5 组事务探针覆盖单次写入失败后重试、捕获状态恢复、best-effort 重复字段、批次及 Display 成对写入的原子性，全部通过。日志为 `/private/tmp/recording-simplify-{default-build,page-tests,build,value,atomicity}.log` 和 `/private/tmp/recording-capture-simplification.log`；临时源码与已删模块的 16 个旧构建文件均已清理，没有新增永久测试。

**移除内部校验（2026-10-21）：** 重新审查全部表达式构造、容器、calc/infer/simp、图导入、证明分支、Display 及 embed/computation 的所属数组与字段组装，未发现生成或偏移错误。删除节点、数据树和完整值的校验及其调用，不新增替代检查；`importInto` 直接返回数据与节点数组，`references` 返回常量数组，`RecordedValue.encode` 返回 `Json`。`Value.lean` 从 102 行减至 66 行。配置字段检查、函数协议检查、事务和外部 JSON 解码继续承担各自职责。

本轮定向构建（68 jobs）、`lake build`（3088 jobs）和 `lake build TestPage:pageTests`（3121 jobs，39 个模块）全部通过。6 组临时正向语义测试覆盖 78 个生成表达式、容器及二次导入、冻结、回滚和 Display 偏移。正式 schema 与现有 PS4HTML 解码器验收本轮新生成的 136 份证明（107 份录制、29 份仅代码，共 3184 节点、1192 根）及 3 个 computation function（170 节点、6 根），全部通过；旧产物未计入。没有新增永久测试，临时源码已删除。日志为 `/private/tmp/recording-no-validation-{build,default-build,page-tests}.log`、`/private/tmp/recording-pure-construction-probe.log`，产物报告为 `/private/tmp/recording-no-validation-decode-report.json`。

## 11. 验证重点

验证应覆盖语义边界，而不只是构造子是否能输出 JSON：

1. **捕获时机**：已赋值元变量在捕获时冻结；后续赋值不改变已捕获值。
2. **上下文独立性**：局部上下文变化后，已捕获节点仍能提交；额外声明信息只由显式记录产生。
3. **引用映射**：组合多份值时节点下标正确，de Bruijn 索引和投影索引不被误改。
4. **普通 JSON**：用户数据中的 `$ref` 字段不参与内部节点映射。
5. **常量收集**：覆盖各表达式构造子、嵌套容器、重复节点和字段级开关，与确定的 Lean 常量收集语义对照。
6. **事务性**：捕获失败、提交失败和批次失败均不遗留节点、字段或引用。
7. **缺失与错误**：正常 `none`、缺失目标、best-effort 失败和 required 失败保持约定行为。
8. **端到端消费**：重写、simp、calc、推理链及目标展示在新字段契约下可以正确导出和渲染。
9. **图有效性**：验证捕获和重定位算法生成界内根、先子后父的结构边；外部解码拒绝不符合 wire 契约的 JSON。
10. **嵌套捕获**：simp erase 等允许内部捕获失败后继续的路径，不残留节点或缓存；参数之间不共享临时 elaboration 状态。
11. **输出边界**：普通 JSON 中合法和不存在的 `$ref` 均原样保留，渲染依赖收集、模板和 PS4HTML 不将其当作表达式。
12. **展示与协议**：自由变量命名/hover、隐式和实例参数筛选、投影、embed/computation 正确消费；旧版本产物按约定拒绝或兼容，重建后契约、快照和摘要一致。

现有行为基线主要包括 `RecordingAPITest` / `RecordingAPIRules`、`RecorderDSLTest`、`RecordingConfigTest`、`RecordingComplexTest`、`ReferencesOptionTest`、`RecordingReferencesTest` 和 `RecordingSessionTest`。`ExprJSONFieldsTest` 主要提供导出样例，不能单独证明新字段或渲染语义正确；还需要直接的节点/解析器检查和至少一条真实页面构建链路。

## 12. 总结

重构后的分工为：

- **表达式捕获器**：冻结捕获时的表达式结构，生成 `ExprNode`。
- **记录器**：决定捕获什么、何时捕获，以及是否额外记录类型、名字、上下文等信息。
- **录制值**：保存数据树与自包含的节点数组。
- **提交器**：导入节点、写入字段、按策略收集引用，并维护回滚语义。
- **导出器**：在输出边界把结构化数据编码成 JSON。
- **消费方**：按照明确的输出契约解释表达式结构和显式记录的补充字段。

这使 JSON 回到输出格式的角色，也使“表达式是什么”和“用户希望展示什么”成为两个可以独立维护的问题。
