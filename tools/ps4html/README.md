# PS4HTML：ProofScript 官方站点构建器

> **录制协议迁移至 0.4.0：** 所有 `#page theorem` / `#page lemma` 证明文档必须包含
> `statement`、`expressions`、`expressionRoots`；原生 `:= by` 只省略 `proof` 步骤数组。
> computation function 的共享录制版本也升级为 0.4.0，执行 ABI 不变。
> 下文 0.3.0 的旧协议说明以此更新为准，旧缓存须通过 Lake 页面构建重新生成。
> 详见[定理表述接入与迁移](../../docs/PS4HTML-Theorem-Statement-Integration-zh.md)。

PS4HTML 是 ProofScript 的 HTML 站点生成器。Lake facet 编译并导出页面、证明和资源，
构建所需计算，再生成完整库站点或单模块调试页面；`.PS4HTML/build/index.html` 是项目入口。

## 安装

在 ProofScript 仓库根目录执行：

```sh
python3 -m pip install -e ./tools/ps4html
```

也可以标准安装 `python3 -m pip install ./tools/ps4html`。Python 要求 3.11+，Pygments 与 jsonschema 自动安装。
模板、规则、CSS、JS 和字体均随 Python 包分发，无需 `~/.PS4HTML` 或兄弟仓库。
Lean 项目必须通过 Lake 依赖配置指向可用的 ProofScript；Python 安装不会修改 Lake 依赖。

构建需要 Lean/Elan/Lake；LaTeX 页面需要 `latex`、`dvisvgm` 及所用宏包。
计算页面额外需要 Node、Emscripten 与匹配 Lean commit 的 Wasm runtime：

```sh
export PROOF_SCRIPT_LEAN_WASM_PREFIX=/path/to/lean-wasm-prefix
```

计算脚本优先由 `PROOF_SCRIPT_ROOT` 显式指定，其次从项目及 Lake manifest 的 ProofScript
依赖定位，最后尝试当前开发 checkout。无需固定主目录安装位置。

## 命令

在用户 Lean 项目目录中运行：

```sh
lake build MyLibrary:ps4html
lake build +MyLibrary.Module:ps4html
ps4html make --cache
ps4html serve
ps4html serve --lan --cert ./certificate.pem --key ./key.pem
ps4html clean
```

`lake build MyLibrary:ps4html` 构建整个 `lean_lib`，输出到 `.PS4HTML/build/<包名>/<库名>/`。
`lake build +MyLibrary.Module:ps4html` 构建指定 Lean 模块的调试页面，`+` 用于明确选择模块，
即使模块与库同名也不会混淆。Python 命令也可通过 `python3 -m PS4HTML` 运行；
`-c` 是 `--cache` 的短选项。

单模块构建以目标模块及其传递 `import` 闭包为编译边界：所需源码依赖仍按页面模式编译，
不扫描整库或主动构建无关兄弟模块、导入目标的下游模块。Lake 显式声明的额外构建依赖、
插件与 Info exporter 自身的工具依赖仍按 Lake 依赖图构建。
Lean 会检查目标模块的完整源码；`#page end`
只结束页面内容，不截断模块编译，其后的错误仍会导致构建失败。导出清单和 HTML 页面只选择目标模块，
同时保留必要目录页与资源；导入模块提供的配置仍参与目标内容的快照解析。
Wasm 构建只处理目标页面引用的 pending 计算，不为导入模块的其他页面构建计算。
不在本次导出内的定理导航目标保留为无链接文本。
模块页面独立发布到 `.PS4HTML/build/<包名>/.modules/<模块名>/`，不会替换完整库站点。
这是一项缩小编译范围的调试功能；每次调用仍执行独立页面构建，不提供增量构建或 watch。

普通 `lake build` 和 IDE 默认只验证原生 theorem，不录制步骤或导出页面；五种 Info 命令也跳过字段解码、语义校验和配置登记，语法与模块模式一致性检查仍然生效。已有元数据目标和已知字段仍提供编辑器语义信息，未找到的元数据目标可以跳过。
页面 facet 自动启用 `proofScript.pageBuild`，只清理所选目标的专用目录：库使用
`.lake/ps4html/<包名>/<库名>/`，模块使用 `.lake/ps4html/<包名>/.modules/<模块名>/`，
保留普通 `.lake/build/` 与自定义普通构建目录。
一次隔离的 Lake 构建生成所选目标、所需用户源码依赖及 ProofScript 框架的 Lean 产物、证明 JSON 和资源。
`#page end` 仅将页面草稿持久化到 `.olean`；随后在同一工作空间中运行 Info exporter，
按所属模块的最终配置生成页面 JSON，再按需 build/finalize 计算资源并渲染 HTML。
页面源码包不恢复旧 artifact cache，以确保 JSON 实际生成。框架与提供 Info 的依赖必须重编译，以恢复默认 renderer、Lean2TeX 及用户配置；Mathlib 等不含所需页面或 Info 数据的基础支持依赖复用缓存。
计算工具读取 Lake 会话提供的真实 C/setup 路径，因此也支持隔离后的构建目录。
库导出快照放在 `.PS4HTML/inputs/<包名>/<库名>/.ProofScript/`，模块快照放在
`.PS4HTML/inputs/<包名>/.modules/<模块名>/.ProofScript/`。输入与 HTML 经同一个版本指针原子发布，
编译、导出或渲染失败时保留该目标已发布的版本。
`--cache` 分别重渲染已发布的库和模块快照，保留各自的页面范围；只消费已有导出，
不检查源码新旧，不执行 Lean、Wasm 构建或 finalize。
`clean` 删除项目 `.ProofScript/` 与 `.PS4HTML/`，不删除 `.lake/`。

输出包含 `index.html`、按模块组织的页面、`assets/`、计算资源和 `lean2tex-report.json`。
计算页面必须通过 HTTP(S) 打开，`serve` 提供 Wasm MIME、COOP、COEP 和 CSP 响应头。
跨设备 pthread/SharedArrayBuffer 计算需要受信任 HTTPS。

## 页面与交互

- ProofText 标题、段落、列表、引用、字体、代码、公式和链接。
- theorem/lemma 结构化证明、源码卡片、源码翻转、分支展开与缩进控制。
- 正常渲染、`sorryAx`、JSON/结构错误状态；未记录步骤显示红色“未导出数据”提示。
- ProjectInfo、跨页标签、文献、模块与定理依赖导航。
- LaTeX SVG、图片、嵌入证明资源与共享表达式表。
- KaTeX 数学、关联变量高亮、中英文证明和引用面板切换。
- Lean/Wasm Worker runtime 及 Fibonacci、E8、公式实例 renderer。

PS4HTML 不重新验证证明；LaTeX 编译发生在 Lean 导出阶段。
项目 ID 统一使用非空字符串字面量，例如 `project_info "课程笔记" { title := "课程笔记" }`；定理可通过 `project := "课程笔记"` 指定归属。
统一 Info 协议使用 `9.0.0`，录制协议使用 `0.3.0`，契约描述版本为 `2`。每个 script 步骤对应一个 JSON 对象，框架字段为 `$ruleId`、`$goal_before`、`$goal_after` 和 `$branches`；普通默认录制器提供 `$goal_before` / `$goal_after`，策略默认录制器只提供 `$goal_before`。模板直接读取实际录制的字段，表达式由 `expressionRoots` 标明；调用契约与注册元数据不再声明输出字段。普通步骤没有剩余目标时，`$goal_after` 为 `null`。旧缓存需要重新运行 `lake build MyLibrary:ps4html`；缓存命令不会自动执行 Lean。协议迁移和模板示例见[第六阶段迁移说明](../../docs/Script-Binding-Phase6-zh.md)，配置与导出接口见[统一 Info 配置](../../README-zh.md#统一-info-配置)。

Lean 录制器用 `record_param` 立即记录参数，用 `record_value` 记录已有或计算所得的值；两者共用内部写入函数，分别打开 `ProofScript.ParamRecorder` 和 `ProofScript.ValueRecorder` 的 scoped `RecordValue` 实例。转换使用 `RecordValue.record value context`，上下文为 `Option MVarId`；带名称的参数宏先解析目标再传入录制入口。`record_goal "field"` 记录主目标，`record_goal "field" (goal)` 则传入 `MVarId` 记录指定目标。录制只保存数据，包含定理常量的表达式及嵌套数组、对象也不写入文献引用暂存区，`dependencyCollection` 不影响这些操作。目标快照、`cases_by.subject`、`contra.hypothesis` 继续使用普通值写入；失败时保留原有的录制回滚边界。渲染配置依赖仍沿 `expressionRoots` 指定的表达式结构和有效类型注解解析，定理导航继续使用独立的最终证明事实。自定义录制示例见 [RecordingAPI.lean](../../examples/recording/RecordingAPI.lean)。

`cite` 检查完整参数是命题证明，再仅收集声明类型为命题的常量，不要求 `theorem_info`，也不受 `dependencyCollection false` 影响。手动引用以 `isDependency := false` 进入页面暂存区和页面定理事务，成功后保存到 `.olean` 的 `DeclarationFacts.proofRefs`；同名自动引用将标记提升为 `true`。`#page references` 使用最终元数据展示已配置的引用，保留该标记；单独的手动引用不产生定理导航边。

命名 theorem/lemma 的 proof artifact 使用 manifest `9`，必需包含 `declaration`、`declarationKind`（`theorem` 或 `lemma`）、非空字符串 `projectId`、完整引用数组 `proofRefs`、导航名称数组 `proofDependencies` 和 `proofFactsDigest`。`proofRefs` 每项包含必需的无损 Lean 名称 `name` 和布尔值 `isDependency`，保留手动及跨项目引用。`proofDependencies` 仅保留标记为自动依赖且最终项目与源定理相同的目标，证明定义也可成为目标；`dependencyCollection false` 会关闭这些自动导航边。空数组表示成功采集后的零引用或零导航依赖。摘要绑定 artifact ID、源证明摘要、快照 ID 与五个定理字段。页面和未命名录制 artifact 不携带这些证明事实字段。配置 snapshot payload 版本为 `7`，外层文档使用 `9.0.0`。查询只包含所属模块 `query.module`，不提供历史配置查询字段。每个页面组件通过 `snapshotId` 关联配置；所属模块及全部传递导入模块提供最终 Info，包括本模块 `#page end` 后的更新。下游模块不能反向修改上游产物的快照。导出器从 `.olean` 中的草稿直接生成页面，可重复导出覆盖已有页面。

有步骤的 proof 同时提供原生表达式节点表 `expressions`、`expressionRoots` 和 `proof`；code-only 文档只含 `schemaVersion/module/code`。只有根清单指定的位置是表达式，普通 JSON 的 `kind` 或 `$ref` 不触发解释。标量元数据保存在 `mdata.data` 中，`mdata.expr` 是唯一子引用；声明快照和应用 binder 描述已删除。Lean2TeX 穿过包装并读取当前 occurrence 的标量注解，参数筛选只使用配置快照的数字索引；局部定义由专用 `let` 步骤展示。computation 的独立 `function.recordingVersion` 为 `0.3.0`；外层组件、pending、bundle 及资源协议仍为 `0.0.0`，执行 ABI 仍为 `proofscript-json-v1`。结构分别见 [proof Schema](../../docs/schema/recording-proof.schema.json)、[function Schema](../../docs/schema/recording-function.schema.json)。

Python 通过 `InfoBundle.theorems[(project_id, name_key(declaration))]` 或 `InfoBundle.theorem(proof_path)` 取得同一份不可变 `TheoremRecord`。`proof_refs` 保存不可变 `RefInfo(name, is_dependency)` 元组，`proof_dependencies` 保存导航名称元组。该接口先校验整份 bundle，缺字段、重复引用名、重复/自依赖、引用标记及项目与导航投影不一致或摘要错误均拒绝；旧缓存必须重新运行 Lean 构建，不能补成空数组。

定理导航由 `TheoremGraph` 统一生成：渲染前先读取整个 bundle，建立同项目的直接依赖与反向关系，再选择需要输出的页面。图的覆盖范围是 bundle 明确列出的模块及其定理产物，包含独立证明与 `#page end` 后的证明。没有页面的目标、或未包含在本次输出中的页面目标，会保留为无链接文本。依赖不再通过源码、短名或表达式表猜测，页面只通过显式 proof artifact 关联事实，并校验模块与冻结快照。

theorem 与 lemma 使用同一导航视图；中英文正文通过 `data-theorem-id` 共享逻辑身份，原有锚点保持不变。每条定理的图保存在 `<template>` 内，浏览器只向一个显示槽装载当前图，同一身份保留现有 DOM。

当前定理由鼠标实际命中的正文决定，包含标题、展开分支和源码面。进入当前导航时保持源定理，可点击依赖链接；进入其他定理立即切换。离开正文和导航后延迟 150 毫秒隐藏，便于跨过二者间的空隙；离开窗口、失焦或切到后台立即清空。初始没有鼠标坐标时不选择，URL hash 不指定当前定理，触摸输入也不会建立悬停选择。

滚动（包括内部容器）、窗口缩放和布局变化只按保存的鼠标视口坐标重新命中。语言、源码翻转、缩进和公式组件通过 `document` 的 `ps4html:layoutchange` 事件通知控制器，原生分支 `toggle`、内容 `ResizeObserver`、资源和字体加载补充通知；新增改变布局的组件也应发出该事件。控制器不观察导航自身。

当前不提供语言或外部规则的 CLI 配置参数。站点使用内置默认语言，页面内既有双语交互保留。

## 渲染规则

### Lean 声明宏

表达式渲染规则在 Lean 文件中声明，并按证明模块的导入关系生效：

```lean
def_info HAdd.hAdd { kind := operator, styles := [
  { name := "formula", template := "#0+#1", fixity := «infix»,
    precedence := 65, associativity := left }
] }
def_info Eq { calc_symbol := some "=" }
def_info Real { var_name := "x" }
```

还支持 `alias`、`unwrap`、`phrase_info`、动态参数和有序样式。
Lean 负责导入合并并将消费配置冻结到 `.ProofScript/info/snapshots/`，Python 直接读取快照；
Python API 为 `Lean2TeX.load(export_root, proof_module, snapshot_id=...)`。模块所有产物共用一个快照时可省略 snapshot_id。
`auto_arity := true` 在冻结时按声明的原生 binder 标注转为数字索引，后端只使用这些索引；`auto_arity := false` 时模板索引直接对应完整原始应用参数。动态 `#*` 模板不再支持。
参见 [Lean2TeX 说明](Lean2TeX/README.md)。
模板可用 `@N`、`@@N` 等引用第 N 个显示参数的连续 lambda binder；
`binders := [(N, 2)]` 声明该参数至少需要两层，此时 `@@@N` 引用正文。
按配置顺序选第一个 binder 数量符合的样式；每个使用 `@` 的宏还需提供一个
不使用 `@` 的回退样式。变量引用来自同一个 DisplayTree，数量不足时不会猜测 binder。

### Tactic 与 Strategy

Lean 中的 `script_info <注册ID> { template := [{ lang := "zh", tag := "标题", content := "正文" }] }` 定义普通展示模板；按语言代码合并，缺少请求语言时使用首项；
特殊策略使用 `renderer := «calc»` 等已注册的 Python 渲染器标识；`calc`、`infer` 值需要 Lean 的 `«»` 转义。
Lean 原样保存模板字符串，不解释 `${...}`，仍检查模板外层结构和普通/策略注册类型。PS4HTML 解释非空闭合占位符并读取实际字段路径：消费实际步骤时（包括 bundle 加载时的数据校验）发现缺失字段或无效路径会报错，`${}` 和未闭合的 `${unclosed` 作为文本显示；占位符以外的文本进行 HTML 转义。
Lean 在 `info/index.json` 中为每个 proof 绑定 snapshotId，并按完成后的 step 结构路径绑定实际调用契约；proof JSON 保留
`module`、每一步的 `$ruleId`、参数和真实分支。`PS4HTML/render_rules.py` 使用对应路径的契约与快照模板排版；同一个规则可以在一个证明中使用多个契约版本。Python 根据实际字段检查 renderer 所需结构，并在渲染模板时读取占位符路径；隐藏策略仍检查分支结构，所有步骤共用的表达式图与根清单检查保持生效。缺失规则或展示所需字段会阻止发布。
Lean2TeX 的 `def_info` / `phrase_info` 控制数学表达式排版，
不属于 tactic/strategy 规则。

没有手写 recorder 且自动 recorder 无法生成时，Lean 发出警告并继续执行，步骤使用保留
`$ruleId: "ProofScript.unrecorded"`，`name` 保存原策略关键字。PS4HTML 复用“未知策略”的红色样式显示
“未导出数据”（英文为 “Data not exported”），并继续展示已录制的分支和后续步骤。

## 开发资源

`#page theorem` / `#page lemma` 的展示与项目归属在最终导出时确定，统一通过声明后的独立 `theorem_info` 配置。例如 `theorem_info T { project := "P", name := "展示标题" }`，也可放在 `#page end` 后。原生文档注释保留供 Lean 和编辑器使用。显式 `project` 优先，否则选择首次登记模块本地唯一项目，本地无项目时选择该模块传递导入闭包中的唯一项目；多项目时必须明确归属。录制定理在定义模块登记，普通 Lean theorem 在首次 `theorem_info` 所在模块登记。同一项目的多个模块应使用同一个字符串 ID，仅有相近命名空间不能建立项目关系。普通 Lean theorem 也按最终配置确定项目归属，属于同项目时才纳入项目内依赖。

从旧版迁移时先更新 ProofScript 和 PS4HTML，再执行 `lake build MyLibrary:ps4html` 重新导出。旧 bundle、缺失证明事实或混用协议版本会明确报错，`ps4html make --cache` 不迁移旧 JSON。若旧版在发布链接的位置使用普通目录，应先将该项目 `.PS4HTML` 归档后重建；现行发布结构的失败构建会保留已发布版本。页面构建与缓存入口见[命令](#命令)。
录制 Schema 在 [`../../docs/schema/`](../../docs/schema/)，Info Schema 随导出生成到 `info/schema/`。浏览器源文件位于 `PS4HTML/assets/js/`，
样式和字体位于 `PS4HTML/assets/css/`，模板位于 `PS4HTML/Templates/`。

## 当前限制

尚无完整 custom component 插件协议、自动编号、watch/增量构建或完全离线 KaTeX。
复杂 Lake workspace/srcDir 支持有限；figure 路径相对于项目根目录。
图片/SVG 默认内嵌可能增大 HTML；`metadata.extra` 保留但无通用布局语义。
不是所有 Mathlib 常量或任意 tactic 都有语义宏。核心校验不等于完整 JSON Schema 校验。
证明内 figure/table 没有完整专用 renderer。Pygments Lean lexer 也不等于 Lean 4 parser。

## 许可证

ProofScript 与 PS4HTML/Lean2TeX 统一使用 Apache License 2.0，采用标准许可证全文。
参见仓库根目录 `LICENSE`；Python 包内的 `PS4HTML/LICENSE-APACHE-2.0.txt`
是随独立安装包分发的同一许可文本。第三方依赖与资源仍遵循各自许可证。
