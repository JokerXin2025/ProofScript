# 统一 Info 系统设计提案

状态：设计提案；本文描述目标架构，示意 API、属性和语法尚未实现。

范围：`project_info`、`theorem_info`、`script_info`、`def_info`、`var_info`、`phrase_info`。目标是统一字段声明、解析、增量更新、环境存储、导入合并和导出，同时保留领域模型的强类型与各自的约束。

## 1. 核心决策

采用“强类型模型 + 结构体派生的 schema + 通用 patch 引擎”。

- 每种信息有独立的强类型结构体；嵌套模板、样式、枚举也有类型。
- 字段名和类型来自结构体声明；默认值、合并策略、值域约束随字段声明。通用 elaborator 不列举业务字段名。
- 六个命令仅负责识别信息种类、解析目标，随后调用同一个解析和注册入口。
- 持久化显式更新事件，以及首次建立对象所需的上下文绑定；查询时根据 schema 得到强类型有效配置。完整配置与增量事件是两种不同的数据。
- 重复命令合法；同一命令中重复赋值同一字段报错。
- 未知顶层字段自动进入 `extra`；已知字段的类型错误始终报错。
- Lean 负责导入合并、冲突诊断与配置完整性校验；Python 消费已合并快照。
- 页面采用 `page_end` 时的配置快照；同一页面的标题、引用与渲染配置使用同一份快照。

这次改造需要修改语义和数据协议，应作为一次明确的架构迁移发布。

## 2. 单一字段来源

定义以下领域模型：

| 命令 | 强类型模型 | 目标身份 |
| --- | --- | --- |
| `project_info` | `ProjectInfo` | 稳定的 `ProjectId` |
| `theorem_info` | `TheoremInfo` | 已解析的 Lean 声明名 |
| `script_info` | `ScriptInfo` | 已注册的脚本规则 ID |
| `def_info` | `DefinitionInfo` | 已解析的 Lean 声明名 |
| `var_info` | `VariableInfo` | 非空变量类别字符串 |
| `phrase_info` | `PhraseInfo` | 非空短语键 |

`ScriptInfo` 使用有类型的普通模板、策略模板和颜色；`DefinitionInfo` 使用有类型的 kind、arguments、style、fixity、associativity。特殊值如 `explicit`、`operator`、`some Eq` 由对应类型的 codec 解释。

声明引用、规则引用、颜色和语言代码使用 `DeclRef`、`RuleRef`、`HexColor`、`LanguageCode` 等小型封装类型，使 codec 由类型选择，避免靠字段名猜测某个 String/Name 的含义。

建议实现自定义 `deriving InfoSchema`。下面仅展示声明形式：

```lean
structure PhraseTemplate where
  lang : LanguageCode
  content : String
  deriving InfoSchema

structure PhraseInfo where
  @[info_merge keyedBy(lang)]
  template : Array PhraseTemplate := #[]
  extra : ExtraFields := {}
  deriving InfoSchema
```

派生器生成字段索引、类型化 getter/setter、codec 关联、默认值描述、JSON 编解码和 JSON Schema。新字段的常规修改只发生在结构体声明处；新增值类型时提供对应 codec。字段重命名可通过显式 wire-name/兼容别名属性管理；schema 注册时检查名称、别名与保留名碰撞。

`FieldSpec Record` 的概念组成如下，实际实现可使用依赖类型封装：

```text
FieldSpec Record
  name / aliases           从结构体字段生成
  Value                    字段值类型
  codec : InfoCodec Value  语法解析、规范化编码、JSON Schema
  get / set                Record 与 Value 的类型化访问
  default                  字段默认值或“必须提供”标记
  merge                    replace / keyedBy / extrasByKey
  validateValue            值自身的约束
```

`InfoSpec Record` 再提供目标解析、首次建立对象时的上下文默认值，以及整个记录的约束检查。例如项目归属的初始值需要上下文，`alias` 与 `unwrap` 的互斥需要跨字段检查。

领域约束通过类型化字段访问实现，例如读取 `info.alias`，不使用 `getObjVal? "alias"`。最终模板排版仍然需要理解领域语义；schema 负责集中结构与校验规则。

派生器的第一版限制在这些模型需要的范围：非依赖的普通结构体、已注册 codec、明确默认值。先实现 `FieldSpec` 和解析引擎，再实现派生器并迁入生产模型；不以两份人工维护的结构体与字段表作为最终状态。

上面的字段属性是目标语法，需要原型验证 Lean 属性与 deriving 的执行时序。底层可先接受紧邻模型的 `SchemaOverrides`，通过生成的字段句柄指定合并策略与约束；它只补充特殊规则，不重复字段名、类型和普通解析器。依赖前序字段的复杂默认值不在第一版自动派生范围内。

## 3. 字段检查与附加字段

推荐默认规则：

1. 已知字段：使用字段 codec 解析，检查类型、枚举、范围和局部约束；失败立即报错。
2. 未知顶层字段：解析为 `ExtraValue`，保存在独立 `extra` 对象。
3. 与已知字段非常相似的未知名字：仍接收，但产生拼写提示；用户可以用显式 `extra` 表明意图。
4. 显式 `extra := { ... }`：按扩展键更新，允许带引号的任意字符串键。
5. 单个命令的重复内置字段、重复扩展键，以及简写与显式 `extra` 对同一键的重复赋值，均报错。
6. 顶层内置名、别名和 `extra` 为保留名；`extra` 内的名称属于独立命名空间，不覆盖内置字段。

例如：

```lean
theorem_info myLemma {
  name := "引理",
  difficulty := "introductory",
  extra := { "review.status" := "checked" }
}
```

`difficulty` 与 `review.status` 都进入 `extra`。`tags := 123` 会报类型错误；`tgas := ["analysis"]` 则作为扩展字段保存并提示可能想写 `tags`。

`ExtraValue` 支持字符串、数值、布尔、null、数组与对象；不把无法解释的任意 Lean term 转成字符串。附加字段有统一值语法和可序列化检查；只有声明了扩展 schema 的插件才检查其额外业务含义。

嵌套的内置对象默认严格检查字段，以免 `style.precednce` 一类错误被悄悄接收。确有扩展需要的嵌套对象，可在其模型中显式声明 `extra`。

Python 保留并透传 `extra`，内置渲染器默认忽略它；新增附加字段不需要修改核心字段白名单。

## 4. 重复配置与更新语义

| 输入 | 效果 |
| --- | --- |
| 未写某字段 | 保留已有值；不产生该字段的写入事件 |
| 再次写普通字段 | 覆盖该字段 |
| 再次写普通列表 | 整个列表替换，包括显式 `[]` |
| 更新按键合并的列表 | 只替换同键条目，其他条目保留 |
| 更新 `extra` | 逐键覆盖；不删除其他扩展键 |
| 可选字段 `:= none` | 显式设置为 `none` |
| 字段 `:= reset` | 显式屏蔽继承值，恢复 schema 默认值 |
| 扩展键 `:= reset` | 删除该扩展键，包括继承值 |

`reset` 是新增的上下文语法，不能与 null/`none` 混同；没有默认值的必填字段 reset 后回到未提供状态，在消费时报告缺失。

`script_info.template` 和 `phrase_info.template` 按 `lang` 合并；`styles`、`tags`、`authors` 等默认整体替换。新语言追加，同语言替换保留位置。策略属于 schema，合并引擎中不出现 `if field == "template"`。

按键集合的 `reset` 作用于整个字段。合并策略必须定义其冲突范围，使“重置整个 template”也能覆盖祖先对各语言的赋值。普通对象不做隐式递归深合并。

例如：

```lean
theorem_info myLemma { name := "引理", tags := ["analysis"] }
theorem_info myLemma { name := "连续性引理", difficulty := "basic" }
```

得到更新后的 name、保留的 tags，以及新增的 extra.difficulty。

## 5. 校验分两个阶段

**提交 patch 时**检查语法、目标存在性、重复字段、值类型、局部范围、同一个输入列表中的重复键。例如负的参数下标、重复语言、非法颜色应直接定位到对应字段。

**消费有效配置时**检查必填字段与跨字段约束，例如 alias/unwrap 互斥、模板与策略分支一致、别名目标可用、renderer 与已记录数据兼容。

这样可以分多个命令补齐配置，也可以在一个配置模块中提供不完整 patch，再由下游模块补充。未完成的配置可以保存在事件日志中；实际被页面或渲染使用时必须完整有效。依赖关系中的 alias 目标等也属于需要验证的消费闭包。

消费集合有明确来源：页面引用声明、录制的规则 ID、表达式中的常量，以及已选择的变量/短语配置。每种 `InfoSpec` 提供类型化 `dependencies` 查询，例如从 alias 指向目标配置；注册的 renderer 声明其额外配置依赖。导出器据此计算闭包。自定义 renderer 的动态配置访问必须预先声明依赖；无法静态确定的访问保留明确的后端运行时错误，不能声称 Lean 已完整验证它。

一次命令先解析全部字段，成功后一次性提交事件。字段失败不能留下半条 patch。环境状态不使用跨 elaboration 的全局可变 IO 缓存。

## 6. 导入合并与冲突

所有六种命令共用同一规则：

- 同一模块内，后面的显式写入覆盖前面的对应写入。
- 导入关系中的后代模块可以覆盖祖先模块。
- 无依赖关系的两个模块修改不同字段或不同合并键，可同时生效。
- 无依赖关系的两个模块给同一合并单元写入不同值，保留冲突候选；汇总模块可以再显式赋值解决。
- 相同的规范化值可以合并，但必须保留全部来源，避免后续分支覆盖时丢失冲突依据。

引擎按字段或集合键保存尚未被后代覆盖的来源集合。应用本地 patch 后，才在消费边界检查剩余冲突，不能遍历第二个导入时就终止。

例如 A、B 分别设置同一规则的 `display` 为不同值；C 导入 A、B 后可以再设置 `display := true`。如果 C 没有解决冲突，则在使用该配置时报告 A、B 的字段位置。

钻石导入按模块和事件身份去重。模块遍历与新条目追加顺序必须确定；独立分支采用稳定的模块名次序，模块内部采用源码序号。同一 patch 中的有序列表保持输入顺序。

冲突信息包含 info 种类、目标、字段路径、双方模块与源码位置。跨字段约束引用所有相关字段的来源，不要求用户从一个最终 JSON 反推来源。

## 7. 生效范围、身份与快照

### 7.1 当前模块的更新可用

推荐统一为“传递导入 + 当前模块截至查询位置的更新”。这会改变当前 `script_info`/`def_info` 只在导入方生效的行为，应明确记录为迁移变化。

通用 API 显式接受模块与边界：

```text
resolveInfo(spec, environment, module, boundary, target) -> typed info + provenance
freezeInfo(environment, module, boundary, consumedTargets) -> immutable snapshot
```

边界只裁剪指定模块的本地事件；其传递导入使用各模块完整事件。批处理导出器不能用自身的 `env.mainModule` 代替待导出模块。

Lean 命令查询只能看见执行到当前位置的配置。页面展示统一采用 `page_end` 的视图，故在页面中较早出现的定理也使用关闭页面时的展示配置。

`page_end` 后仍可以继续登记 info 供下游模块使用，但已冻结页面不追溯改变。没有页面的配置模块无需添加 `page_end`，其事件随 `.olean` 正常导入。

### 7.2 定理归属使用项目引用

`TheoremInfo` 保存 `Option ProjectId`，不再拷贝整个 `ProjectInfo`。

建议支持可选的显式项目目标：

```lean
project_info MyProject { title := "分析讲义" }
project_info MyProject { authors := ["Alice"] }
theorem_info myLemma { project := MyProject, name := "连续性引理" }
```

显式 `project_info P { ... }` 同时将 P 选为本模块后续新对象的默认项目。选择是一条单独记录的上下文绑定，不是 ProjectInfo 的可渲染字段；选择操作与字段 patch 一起原子提交。

已有的无目标写法可以保留：使用本模块已选择的项目，或唯一继承的活动项目绑定；没有绑定时以首次配置模块建立稳定 ID。已知项目表与活动绑定分开；仅作为引用出现的外部项目不参与默认选择。多个继承活动绑定存在歧义时要求显式选择，不能取最后一个导入的项目。

首次建立 theorem info 时可以从当前项目上下文取得默认 ProjectId；没有项目则保存 none。之后更新 name/tags 时必须保持项目归属，只有显式修改 project 才改变归属。这样导入方补充 tags 不会把外部定理归到自己的项目。

首次创建的 ProjectId/none 决定需要随创建记录持久化，导入后不按新的上下文重新计算。两个独立模块首次标注同一声明时，如果项目绑定不同，应产生可被汇总模块显式消解的归属冲突。

引用组件以 ProjectId 分组，展示时从当前冻结视图解析项目内容。更新项目标题不改变项目身份。站点首页明确选择根模块视图中的 projectId；多个项目可以共存，不再靠“只能找到一个项目 JSON 文件”来判断合法性。

### 7.3 延迟解析页面元数据

`@references` 先保存声明名列表；标题、tags、项目内容在 `page_end` 与其他定理组件一起解析。引用收集与“是否已经注册 theorem_info”解耦，导出时再决定如何展示无元数据的声明。

页面与 proof 使用显式 `snapshotId`，不只根据模块名查找一份可被后来更新的配置。`page_end` 冻结所需配置及其渲染契约，并通过持久化扩展保存可导出的快照。

`snapshotId` 由规范化配置内容、所属模块/边界、schemaVersion 与契约版本的摘要生成，不能仅使用模块名和序号，因为源码编辑后同一序号可能对应不同内容。冻结数据自身携带协议版本；后续 exporter 应拒绝或明确迁移不支持的版本，不能给旧 payload 直接盖上新版本号。

脚本注册和 `recordedFields` 也会影响模板解释。录制产物必须绑定实际使用的规则/录制契约版本，快照收录其描述；不能按旧 info 序号配上后来更新的 registration。这里应版本化录制契约，保持规则的逻辑 ID 稳定。

## 8. 存储与导出

### 8.1 通用事件存储

使用一个持久化事件扩展，事件包括：

```text
InfoEvent
  schemaId / schemaVersion  对应模型及协议版本
  kind           稳定的信息种类 ID
  target         规范化的目标身份
  owner          产生更新的模块
  sequence       模块内序号
  assignments    显式 set/reset 操作与已校验的规范化值
  source         命令位置及各字段的位置
```

环境扩展还记录对象初始化和模块活动项目绑定。初始化只记录不可从固定 schema 默认值重建的上下文决定，例如首次 theorem info 的项目归属；后续普通 patch 不重复这些决定。扩展键与内置字段在更新路径中分开编码，避免未来新增内置字段时误解释旧 extra。

schema 的函数保存在编译后的声明/类型类实例中；事件仅存可序列化数据，不把 parser、setter、闭包放进环境扩展。导入后通过 schema 解码并应用更新。业务查询返回 `ProjectInfo`、`ScriptInfo` 等类型，不到处读取动态 JSON。

事件是事实来源；有效配置是可重建视图。可以缓存解析结果，但缓存必须随环境和边界变化，不能把某个模块的最终配置直接当作另一个模块的配置。

### 8.2 统一协议

建议导出目录：

```text
.ProofScript/
  info/
    modules/<模块路径>.json
    events/<模块路径>.json
    snapshots/<快照ID>.json
    index.json
  pages/...
  proofs/...
  resources/...
```

统一使用 `schemaVersion`。快照包含所属模块、消费边界、各类有效信息、明确的 extra、所需注册契约与来源索引。模块清单和事件用于重建、检查与诊断；渲染端直接读取有效快照。

从 schema 生成 JSON Schema，Python 检查协议版本和结构，然后转成渲染模型。Python 仍负责实际 renderer 是否安装、资源是否可读等运行时检查；字段合并、导入冲突和结构字段白名单不再由 Python 重新定义。

### 8.3 不依赖未经验证的文件结束钩子

info elaborator 只更新环境，不在每次配置后重写所有导入模块的 JSON。

新增独立 Lean 配置导出工具，由现有 Lake `ps4html` 构建流程在 Lean 编译完成后调用。它使用 Lake 提供的模块列表和搜索路径导入 `.olean`，按明确的 owner 读取事件与已冻结快照，再导出完整配置文件。无 `page_end` 的配置模块也能导出事件；只有被消费的配置才要求完整。

同时持久化最小产物清单：当前模块产生的页面/proof ID、路径、所属页面会话或 module-final 标记，以及实际使用的录制契约版本。内容仍可保存在文件中。导出器依据清单关联快照和清理过期产物，避免扫描目录时把旧 proof 当作本次产物。

对于页面边界，优先导出 `page_end` 持久化保存的快照，避免用模块结束时的新配置覆盖旧页面视图。无页面的独立产物在构建阶段绑定其模块结束视图。

配置导出使用 staging 目录，全部校验成功后发布完整版本清单，并以原子方式切换指向该版本的入口；不靠逐个替换 JSON 保证跨文件一致性。包含空事件输出，避免删除命令后残留旧配置。缓存模式只读已完成协议文件，无需执行 Lean。

当前 PageState 不持久化，proof/resources 也有文件副作用。这一方案只保证配置可以从 `.olean` 重建。现有页面/资源生成流程先继续使用；若后续希望所有产物都从 `.olean` 重建，需要另行持久化页面与资源清单。

## 9. 文件结构调整

按“公共基础、配置框架、领域执行、输出”划分职责：

```text
ProofScript/
  Foundation/
    Source.lean              # 通用源码位置
    ModuleGraph.lean         # 模块闭包、祖先关系、确定性顺序
  Info/
    Value.lean               # ExtraValue、规范化更新值
    Codec.lean               # 基础类型、Option、列表、结构体、枚举
    Schema.lean              # FieldSpec、InfoSpec、合并策略描述
    Derive.lean              # deriving InfoSchema
    Syntax.lean              # 共享字段语法、reset、extra
    Patch.lean               # set/reset、来源、合并单元
    State.lean               # 持久化事件和冻结快照
    Resolve.lean             # 导入合并、冲突、强类型查询
    Elab.lean                # 解析字段、校验、一次性提交
    Project.lean             # ProjectInfo、项目目标和领域约束
    Theorem.lean             # TheoremInfo、声明目标和项目引用
    Script.lean              # ScriptInfo、模板和策略约束
    Definition.lean          # DefinitionInfo 与 style 模型
    Variable.lean
    Phrase.lean
    Command.lean             # 六个薄命令入口
  Output/
    Path.lean                # 输出根、模块路径与资源定位
    Info.lean                # 统一配置协议编码
    Manifest.lean            # 页面/proof/快照关联
    Main.lean                # 构建阶段配置导出工具
  Script/
    Registry.lean            # 脚本身份、执行/录制注册描述
    Syntax.lean              # 脚本语法与注册命令
    Execute.lean             # 执行语义
    Recording/...            # 保留现有录制子系统的边界
    Builtins/...             # 从庞大的 Basic 按领域拆分
  Page/
    Model.lean
    State.lean
    Command.lean             # 页面关闭、快照边界、输出协调
    Component/...            # 仅页面组件
  Defaults/
    Script.lean              # 基础脚本展示配置
    Lean2TeX.lean            # 基础表达式展示配置
  Mathlib/
    Script.lean              # Mathlib tactic 集成
    Info.lean                # Mathlib 默认展示配置
```

先使用单个领域文件；领域规模增大后才拆成目录，避免为六个薄入口机械建立大量空层级。

具体迁移关系：

- 根 `Data.lean` 拆入 `Info/Project.lean`、`Info/Theorem.lean`；数据声明不再顺带初始化跨领域状态。
- `Page/Component/Theorem.lean` 移出 project/theorem info 命令，仅保留定理录制和页面组件逻辑。
- `Script/RenderInfo.lean` 的字段 parser 由通用 elab/codec 取代，领域模型进入 `Info/Script.lean`。
- `Lean2TeX/Command.lean` 的三个命令共用 `Info/Command.lean`，各自领域模型独立。
- 两个 `Registry.lean` 的配置事件、合并与 IO 移入 Info/Output；脚本注册信息归 `Script/Registry.lean`。
- `Page/Path.lean` 移到 Output，底层配置不再为了导出路径依赖 Page。
- `Script/Config.lean` 拆分注册模型与语法实现，减少仅查询注册信息时拉入整个执行/录制系统。
- References 分开“收集声明身份”和“渲染元数据”，collector 不依赖 Page 或 Output。

依赖方向：Foundation/轻量 Output.Path → Info 通用核心与脚本注册 → Info 领域模型 → 命令与页面集成 → Output.Main 构建编排。箭头表示后者可以依赖前者；Output.Path 是基础工具，不依赖 Output.Main。公共核心不反向依赖具体页面或 Python。

`Script/Registry` 如需录制字段描述，只依赖录制契约的轻量数据模块，不依赖录制引擎。共享描述可下移到 `Script/Contract.lean`，避免新循环。

旧 Lean 导入路径在过渡期保留薄 re-export；生成文件直接迁移到一个明确的新协议版本，不长期维护两套合并器。

## 10. 落地顺序与验收

详细任务、依赖和完成条件见 [重构实施计划](Info-Refactor-Plan-zh.md)。实施划分为阶段 0–7：

0. 记录当前构建基线，固定行为矩阵、迁移契约和兼容边界。
1. 实现 schema/codec、共享语法与结构体派生，验证字段只有一个定义来源。
2. 实现持久化 patch、来源、导入合并和强类型查询。
3. 在独立入口迁入六种领域模型与命令，验证重复配置、输入检查和 extra。
4. 集成 ProjectId、延迟引用解析、page_end 快照及录制契约/产物关联。
5. 完成 Lean 导出工具与 Python 快照消费，联合验收后同时切换默认生产与消费入口。
6. 完成目录重组和兼容导入，清理旧实现及临时桥接。
7. 完成全量回归、迁移指南和维护文档。

新命令在页面快照和后端适配完成前保持独立入口；必要的基础依赖抽取可提前进行，大规模目录整理集中在新链路打通后进行。

核心测试应覆盖行为边界：

- 六个命令连续更新；未写字段保留；none、reset、空列表的区别。
- 已知字段错误、相似拼写提示、任意 extra、嵌套值和重复键。
- 钻石导入去重、祖先覆盖、独立字段合并、不同值冲突、汇总模块显式消解。
- 同一页面在较晚配置后标题、引用与渲染一致；page_end 后更新不修改旧快照。
- 外部定理仅更新 tags 时项目归属不变；多个项目按 ID 分组。
- partial 配置可导入，消费时检查完整性；alias 目标、脚本录制字段等依赖也被验证。
- 无 page_end 模块能从 .olean 导出配置；导出空事件可清理旧结果。
- 编译失败不发布新快照；缓存模式无需 Lean；不同导出根与已有资源流程仍工作。
- schema 生成的协议与 Python 适配一致，包括 extra 和规则契约版本。

迁移前先记录当前构建基线；工作区已有的大量未提交修改与协议版本差异需要单独识别，避免把它们混入这次重构的回归判断。
