# 页面编译模式重构方案

本文记录 2026-10-18 的设计评估与实施结果。模式接口、原生 theorem 分流、页面隔离构建及同上下文导出均已实现；下文的调用链证据描述重构前行为，实施状态见文末。

## 结论与目标

方案可行。建议把 `@theorem` / `@lemma` 的形式验证与页面生产拆成两条路径，并由 Lake 页面构建自动选择后一条路径。

- 普通 `lake build`、`lake env lean` 和 IDE：生成原生 `theorem`，正常检查证明，不运行录制器、不导出页面数据。
- 页面构建：检查同一份证明，同时记录步骤、冻结元数据、生成资源和站点。
- 普通构建和页面构建使用独立的 Lean 产物目录；页面构建不删除普通构建缓存。

当前实际命令是 `lake build MyLibrary:ps4html`，对应 `lakefile.lean` 中的 `ps4html` facet。用户提到的 `pd4html` 目前不存在。建议保留 `ps4html` 名称；若需要支持 `pd4html`，添加调用同一实现的别名即可。

这里的“等效普通 theorem”指：声明本身使用原生 theorem，证明仍由 Lean 检查，页面设施不是完成证明的必要条件。ProofScript 的 `script` 仍保留其 DSL 语法与策略限制，不变成任意原生 tactic 语法。页面专有的录制、元数据完整性与资源错误可以只在页面构建时报出。

## 重构前实现与关键证据

| 位置 | 当前行为 | 对设计的影响 |
| --- | --- | --- |
| `ProofScript/Page/Component/Declaration.lean:127` | 同一个 elaborator 处理 script/by 声明 | 适合在此最早分流 |
| `Declaration.lean:141,179` | 实际生成 `opaque`，随后生成 `scriptcheck_` 定理 | 关闭录制并不自动得到原生 theorem |
| `Declaration.lean:173` | 进入 recording session、表达式表，再转换录制 tactic | 开关必须位于这些操作之前 |
| `ProofScript/Script/Script.lean:262` | 普通 `script` term 已展开到执行版策略 | 快路径可以直接复用，无需重写证明 DSL |
| `ProofScript/Script/Basic.lean:691` | 执行版 `cite` 仍查询展示元数据、收集引用 | 需要把展示校验与验证路径拆开 |
| `ProofScript/Page/Component/Latex.lean:60` | 注册组件前已调用 LaTeX/dvisvgm、写 SVG | 仅在组件入库处关闭为时已晚 |
| `ProofScript/Page/Component/Computation.lean:197` | 注册组件前已序列化表达式、编译 wrapper、写 pending 文件 | 计算组件也要在入口分流 |
| `ProofScript/Page/Command.lean:96` | `page_end` 冻结快照并写页面 JSON | 验证模式直接跳过 |
| `tools/ps4html/PS4HTML/make.py:69` | 每次删除所选包的普通构建目录 | 应改为清理页面专用构建目录 |
| `ProofScript/Output/Export.lean:59` | exporter 读取并校验编译时生成的文件 | 只复用 `.olean` 不能恢复完整页面输入 |

`Recording.Engine` / `Plan` 的开销只是流程的一部分。只关闭写文件，或者让每次 capture 返回空值，仍然会执行录制器、表达式处理及外部资源生成；自定义 recorder 还是任意 `TacticM`，不一定通过 `execute_recorded` 执行原策略。因此，应选择整条执行路径，保持低层录制 API 的职责清晰。

## 1. 构建模式接口

新增轻量模块，例如 `ProofScript/Build/Mode.lean`，注册统一选项：

```lean
register_option proofScript.pageBuild : Bool := {
  defValue := false
  descr := "enable ProofScript page recording and export"
}
```

提供 `pageBuildEnabled` 与接收延迟动作的 `whenPageBuild`。所有高层页面命令查询同一个选项；普通用户不需要修改源码或手动设置选项。

选项由内部页面构建的 Lake 上下文注入。当前 Lean 4.32 的 Lake 已有 `BuildConfig.leanOptOverrides`，可以按包覆盖 Lean options，其键使用 `package.baseName`。`Lake/Build/Module.lean` 的 setup 会应用它们，并将 `setup.options` 计入 Lean 模块 trace。也可以使用参与 trace 的正式 Lean 参数；不使用 `weakLeanArgs` 承载模式。

环境变量只传递输出目录等会话信息，不作为模式的唯一依据：环境变量本身不会使已有 `.olean` 失效。

该选项按模块构建使用，不支持同一模块中途切换。实现时记录模块使用的模式及构建协议版本，拒绝混合模式产物；测试可以显式设置选项。避免用进程级可变全局引用保存模式，以免并发任务相互影响。

## 2. 定理命令分流

先把现有命令解析为共享的声明描述，保留 doc comment、名称、binder、类型、原始 body 与源位置，然后选择执行路径：

```text
@theorem / @lemma
        │
        ├─ verify → 原生 theorem + 执行版 script/by
        │
        └─ page   → 原生 theorem + 录制版 script/by
                    → facts / snapshot / artifact / export
```

### 普通验证路径

直接交给原生命令 elaborator：

```lean
theorem name binders : type := script statements
-- 或
theorem name binders : type := by tactics
```

其中 `script` 使用已有 `run_script_step` / `registration.executionKind` 执行原策略。保留当前 by 分支对 ProofScript 专属策略的边界限制。

此路径不调用现有 `completeDeclaration`，也不进入 `elabCommandAtomic` 的强制同步包装，从而保留原生 theorem 的异步 elaboration 行为。同时绕开现有 `elaborateDeclaration` 按累计错误消息回滚的外层事务，让原生 elaborator 处理验证路径的失败；页面路径保留其事务要求。跳过：

- recording session、录制语法转换、表达式 JSON 表和参数快照。
- `scriptcheck_`、证明依赖提取、`collectAxioms`、ScriptDB 登记。
- 内联展示 Info 的解析和项目解析、page component、artifact、snapshot。
- proof/page/resources/pending computation 等文件生成。

内联 `(info := ...)` 仍按现有语法被解析，但其展示语义留到页面模式处理。独立 `project_info`、`theorem_info`、`script_info` 等声明可以继续维护其持久化配置；它们本身不导出文件。它们的显式配置诊断也继续保留，因此不承诺整个包含这些命令的文件与删去所有页面命令后的文件具有完全相同的诊断。

### 页面路径

两种模式共享原生 theorem 声明生成器；页面路径为 script body 选择录制版策略，by body 保留现有 code-only proof 输出。

页面路径继续同步 elaboration，以便命令结束时读取录制会话、表达式表和完整证明。随后执行原有 facts、内联 Info、快照、组件和导出流程，保持组件创建边界、元数据作用域和失败回滚语义。

录制器应观察并执行标准执行版的证明步骤，不能成为证明成功所必需的额外逻辑。现有 `calc` 等自行执行插桩代码的 recorder 需要做两模式回归检查；任意第三方 `TacticM` recorder 的一致性不能由布尔开关自动保证。

### 原生 theorem 的契约迁移

当前成功声明本就必须通过内部 theorem 的命题类型检查，不能凭 `opaque` 定义任意非 Prop 数据。改为原生 theorem 不减少这一能力，但会改变 `ConstantInfo` 类别和生成的辅助声明。

建议采用严格路线：两种模式都生成原生 theorem。不要让同一个名字在普通模式是 theorem、页面模式却是 opaque。

- 将 `Info.registerDeclarationFacts` 改为支持原生 theorem，不再硬要求新声明存在 check theorem。
- 证明体读取使用的 `value? (allowOpaque := true)`、`collectAxioms` 可以继续支持两种类别。
- 保留读取历史 check → 原声明映射的能力，新声明不再生成 `scriptcheck_`。
- 迁移显式断言 opaque、引用 `scriptcheck_`、检查其命名冲突的测试和文档。
- 需要保留的旧别名应作为显式迁移措施；不能把“新声明继续产生 check”作为验证快路径的永久前提。

如果只希望先快速降低成本，可以暂时让两种模式都保留 opaque＋check，并仅关闭录制；该阶段只能称“关闭页面工作”，不能称已经实现原生 theorem 契约。推荐最终落到上述严格路线。

## 3. 页面命令和引用的边界

| 功能 | 验证模式 | 页面模式 |
| --- | --- | --- |
| `@theorem` / `@lemma` | 原生证明检查 | 同一声明类别，附加录制和导出 |
| `script_macro/elab/recorder` 定义 | 正常注册语法和执行/录制入口 | 相同；不因模式改变规则定义 |
| `remark/svg/latex` 脚本注释 | 使用已有执行版空操作 | 记录展示数据，按需生成资源 |
| `cite` | 保留 Lean 引用项的 elaboration、现有常量形状检查；不消费展示 Info、不收集引用 | 保留完整元数据校验和引用收集 |
| 页面文本、图表、自定义组件 | 跳过组件构造动作 | 正常生成与注册 |
| `@latex` | 不调用外部工具、不写资源 | 正常生成 SVG |
| `@computation` | 原函数仍由其普通 Lean 定义验证；不生成 wrapper/JSON/Wasm | 完整组件校验和构建 |
| `page_end` | 空操作 | 冻结并导出页面 |
| 独立 Info 配置声明 | 保留配置登记，无文件导出 | 相同；在消费时完成页面校验 |

`cite` 是必须单独处理的耦合：若只跳过内联 Info，却保留当前执行版的 `resolveTheoremInfo`，验证模式可能报“not a literature theorem”。应将这一检查划归页面模式，而不是为了它让整个验证路径继续消费展示元数据。

自动页面引用入口组合页面模式与现有 `referenceCollection`，以免普通执行路径仍写引用状态。不要直接改变所有调用共用的 `referencesEnabled` 含义：它也被低层 `commitCapturedValue` 使用。显式 recorder API 继续尊重 `referenceCollection`；自动入口另加页面模式判断。这样低层录制 DSL 保持现有能力，也无需把 Engine/Plan 的每个 primitive 都改成隐式空操作。

统一组件 API 应接受延迟动作，例如 `whenPageBuild do ...`，检查发生在表达式导出、LaTeX 编译和资源 IO 之前。仅在 `addPageComponent stx kind value` 内 return 无法避免调用方已经构造 `value` 的成本。自定义组件文档也要说明这一边界；用户任意命令中自行执行的 IO 不能被框架的开关自动拦截。

## 4. 页面专用 Lake 构建上下文

### 保留调度结构，隔离全部 Lean 产物

保留当前“外层 facet → Python staging → 新 Lake 子进程内部 facet”的结构。页面子进程创建独立 workspace，上下文中的源码包使用专用 `buildDir`，例如：

```text
.lake/build/                                      # 普通验证缓存
.lake/ps4html/<site-package>/<library>/<pkg-key>/   # 页面 Lean/IR/trace 产物
.PS4HTML/staging/<session>/session.json           # 内部会话，不参与发布
.PS4HTML/staging/<session>/release/.ProofScript/   # 尚未发布的导出文件
.PS4HTML/releases/...                             # 现有原子发布机制
```

页面构建首版每次只清自己的专用构建目录，彻底移除对普通 `pkg.buildDir` 的删除。清理在外层持有项目锁时、启动页面构建 jobs 之前完成，路径由构建会话推导并验证；内部 facet 要求有效会话，避免直接调用绕过这一顺序，也不重复获取外层已持有的锁。页面 Lean 产物不要放进现有发布 staging：当前发布流程会哈希并复制整个 staging，导致 `.olean`、C 等进入站点 release。

内部 facet 必须先建立页面 workspace，再从中重新查询目标库与模块，之后才能 fetch 构建任务。应一致重建包映射、依赖包引用以及库/模块配置，使 setup、imports、`.olean`、`.ilean`、IR、trace、dynlib 使用相符的路径。不能仅在某个 `leanArts` 回调里替换 `mod.pkg`。

保留新的 Lake 子进程也有实际作用：Lake 的 BuildStore memo key 不含自定义页面模式；在同一进程先创建普通 jobs，再切换 reader/workspace，可能继续复用先前 jobs。

### 编译范围与发布范围分开

页面模式必须覆盖所选库的实际 import 闭包中需要 ProofScript 附加资料的用户源码，包括同包的其他库、其他用户包。

推荐自动分类采用保守规则：所选包，以及其依赖图中依赖 ProofScript 的用户包，都作为页面源码包；Lean、mathlib、作为独立依赖的 ProofScript 框架及其基础依赖复用普通构建。纯规则扩展包默认可以按源码包处理，再允许显式声明为只提供支持的依赖以减少重编译。混有 `@theorem` 页面资料的包不能作为这种只读支持依赖复用。

原因是验证模式的 theorem 不包含内联配置、声明时默认项目、原始 script 和页面 facts。事后从证明项无法完整重建；复用这种 `.olean` 还可能静默漏掉同项目定理依赖。

实现时区分：

- 编译集合：页面源码包中的实际传递导入模块。
- 发布 owners：用户选中的库模块，继续由目标库确定，不自动发布依赖包全部页面。

无法取得源码的依赖可以作为外部普通 theorem，使用独立 `theorem_info` 配置引用信息；若用户需要导出其完整证明页面，应明确报缺少页面资料，不能静默降级为完整导出。

### 构建、导出、计算使用同一组路径

对页面源码包通过 `leanOptOverrides` 注入 `weak.proofScript.pageBuild=true`。`weak.` 是 Lean 正式选项名的前缀：基础模块尚未导入选项注册模块时忽略该选项，导入后使用正式的 `proofScript.pageBuild` 值；它仍写入 `setup.options` 并参与 Lake trace，不是 `weakLeanArgs`。首版继续禁用源码包的 artifact-cache restore，保证编译时副作用确实执行。支持依赖保留正常缓存。

内部 facet 完成目标构建后，在同一页面 workspace 下运行 exporter，使用对应的 augmented environment。删除 Python 当前额外启动的普通 `lake env exporter`，否则 exporter 可能重新导入普通验证 `.olean`。

Lake 额外生成内部会话 manifest，记录 owners、源码包集合、模式/协议版本、每个模块实际 C 与 setup 路径。`scripts/build-computations.mjs:76` 当前写死 `.lake/build/ir`，应改为消费这些路径，连同依赖产物路径一起验证。保留现有 `LAKE_RESTORE_ARTIFACTS=true` 或等效机制，确保支持依赖命中缓存时所需 C/setup 也实际恢复，不能只记录尚未落盘的路径。该 manifest 是构建工具间接口，不进入证明内容摘要。

沿用已有 staging、完成索引和原子发布：编译、导出、资源或渲染任一步失败，都保留上一次成功发布的站点。

## 5. 页面增量构建留作后续阶段

首版承诺减少日常验证成本，不承诺页面构建不再重跑证明。记录 tactic 过程仍需执行这些 tactic；普通验证 `.olean` 不能提供完整记录。

隔离缓存解决模式互相干扰，并不自动解决页面增量导出。当前每次使用新的空 staging；如果 Lake 命中 `.olean` 后跳过 elaboration，相应 proof/page/resources 不会出现。

后续若实现增量，应为每个模块保存可恢复的页面输出包，与对应 Lean 产物一同缓存、校验和恢复到当前 staging。缓存身份至少覆盖模式/协议、工具链、源码及依赖、录制规则和资源生成配置。缺失或摘要不符时重建该模块，而不是靠关闭完整性校验继续发布。

这一阶段可以保持高层开关和定理执行路径不变，单独改造输出的存储与恢复机制。

## 6. 实施顺序与验收

### 第一步：验证构建隔离原型

用一个本地双用户包样例验证：页面 workspace 的所有 import/setup/exporter 路径一致；上游包仅有内联项目信息，下游能导出正确标题与依赖；Wasm 能读取隔离 IR。确认 Lake workspace 重建方式后再接入主流程，避免先改定理命令却无法可靠启用页面模式。

### 第二步：引入模式与声明分流

新增 Mode 模块，抽取共享声明描述与原生 theorem 生成器。迁移 facts 的 check 依赖，拆分 cite、引用收集和所有内置页面组件入口。公开低层 recorder API 保持现有行为。

### 第三步：接通完整页面流水线

改造 `ps4htmlInputs`、Python 构建调度、会话 manifest 和 computation bundler；实现源码包闭包、同上下文导出。保留旧发布行为，按需添加 `pd4html` 别名。

### 第四步：迁移测试与说明

把依赖自动录制、page state、facts、snapshot 以及 cite 展示诊断的测试明确放到页面模式运行；普通验证测试保持默认关闭。建议拆分默认验证测试目标与非默认页面测试目标，后者复用页面专用构建上下文，避免默认 `lake build` 因测试再次触发大量录制。直接测试 recorder API 的用例不必因为默认模式改变而失去覆盖。更新 README 中 opaque/check、普通 build 导出行为及自定义组件接入说明。

核心验收条件：

1. 默认编译的声明是 `ConstantInfo.thmInfo`，正确证明通过、错误证明失败，doc comment、名称、binder 和源位置保持正确；正常异步检查能力保留。
2. 默认编译不生成新的 `.ProofScript` 输出，不启动 LaTeX/dvisvgm/Wasm，不调用 recorder；包含内联 Info 与 cite 的证明仍可验证。
3. `ps4html` 自动启用页面模式，script 和 by 两种形式、`@lemma`、跨模块和跨用户包引用均正确导出。
4. 先普通构建再页面构建、先页面构建再普通构建，两种顺序都不会错用缓存；普通 `.lake/build` 的既有产物不被删除或覆盖。
5. 页面连续构建在首版允许完整重录；所有必需文件齐全，不因 `.olean` 缓存命中而漏导出。
6. 现有元数据边界、导入作用域、依赖图、`referenceCollection`、录制失败回滚和原子发布测试继续通过。
7. 页面资源/录制错误只影响页面构建；中断或失败不覆盖上次成功站点。普通模式没有新增全局同步瓶颈。

完整性能验收可进一步测量原生 theorem、默认 `@theorem`、页面 `@theorem` 的冷/热构建与 IDE 修改反馈。本轮完成了文末的小样例对照；预期减少的是录制、序列化、元数据消费和资源生成成本，Lean 证明本身的开销仍然存在。

## 7. 实施状态

四步主线均已落地：

- `ProofScript/Build/Mode.lean` 提供默认关闭的选项、模块模式锁定及导出校验。普通声明直接交给原生 theorem elaborator；页面声明继续同步录制与事务处理。新声明不生成 `scriptcheck_`，facts 仍可读取历史映射。
- 内置组件与 `page_end` 在入口跳过页面工作，`cite` 分离 Lean 引用检查和展示配置消费。自定义组件示例使用 `whenPageBuild do`；底层显式 recorder API 保持原有能力。
- Lake 页面 workspace 重建覆盖包映射与依赖包引用，自动纳入用户源码依赖。Python 只清理页面目录；内部 facet 在同一 workspace 构建并导出，Wasm 工具消费会话中的真实 C/setup 路径。会话文件不进入发布内容。
- 默认 `Test` 与显式 `TestPage:pageTests` 分离。页面测试产物位于 `.lake/ps4html-tests/<包名>/<库名>/`，测试入口也使用新 Lake 进程，避免与同一命令中的普通目标共享 jobs。README、Info 文档、自定义组件说明及 CI 已同步。

已完成的验收：

| 检查 | 结果 |
| --- | --- |
| `lake build` | 通过，默认验证路径与形式化检查正常 |
| `lake build TestPage:pageTests`；`lake build Test TestPage:pageTests` | 均通过，页面套件 3115 个构建任务，覆盖录制、组件、配置边界与定理依赖 |
| Python 构建、未录制步骤及配置边界测试 | 29 项通过 |
| `Test/test_page_mode_integration.py` | 真实双用户包普通→页面→普通及同次普通/`pageTests` 构建通过；两包普通 olean 的摘要/mtime、支持依赖 olean 的 mtime/size 保持不变 |
| `Test/test_computation_build_paths.mjs` | 2 项通过，验证隔离目录与支持依赖 C 路径 |
| `examples/site` 的 `PS4HTMLDemo:ps4html` | 通过，完成 4 个页面和 Fibonacci Wasm 构建与发布 |
| `scripts/test-finalized-computation.mjs` | 通过，资源摘要与实际 Wasm 调用正常 |
| `ps4html make --cache` | 通过，完整页面产物可独立校验并重新渲染 |

双包测试使用本地依赖，无 mock、无联网，确认了上下游原生 theorem、页面模式标记、内联标题和项目恢复、跨包 `proofDependencies`、真实 Python HTML 发布，以及编译闭包与发布 owners 的区分。

### 小型耗时对照

Lean 4.32.0 下，三组均使用相同 imports、项目配置与规则定义，分别检查 10 个相同命题的四步证明。每组启动 3 次全新 Lean 进程，轮换模式顺序，复用已构建依赖；页面运行各自使用独立输出目录。wall time 包含导入、当前文件检查，以及页面模式的录制与 proof JSON 写入。

| 模式 | 三次耗时 / 秒 | 中位数 / 秒 |
| --- | --- | ---: |
| 原生 theorem | 11.798、10.579、14.196 | 11.798 |
| 默认 `@theorem` | 6.975、15.737、10.617 | 10.617 |
| 页面 `@theorem` | 20.310、20.894、18.407 | 20.310 |

原生和默认模式每次均零导出；页面模式每次生成 10 份证明 JSON 和 20 个测试 recorder marker。默认 recorder 被调用会直接报错，因此成功运行也验证了执行路径隔离。该测量不含 `page_end`、Info bundle、Lake 调度、HTML、LaTeX 或 Wasm。样本较少且导入耗时波动明显，不据此声称默认模式比原生 theorem 更快，也不提供普遍提速比例。

首版仍会完整重录所需用户模块；页面输出缓存恢复与增量导出保持为后续工作。
