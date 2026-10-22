# PS4HTML：ProofScript 官方站点构建器

PS4HTML 是 ProofScript 的 HTML 站点生成器。Lake 库级 facet 编译并导出页面、证明和资源，
构建所需计算，再渲染到 `.PS4HTML/build/<包名>/<库名>/`；`.PS4HTML/build/index.html` 是项目入口。

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
ps4html make --cache
ps4html serve
ps4html serve --lan --cert ./certificate.pem --key ./key.pem
ps4html clean
```

`MyLibrary` 是项目 `lean_lib` 名称，不是单个 Lean 模块。Python 命令也可通过
`python3 -m PS4HTML` 运行；`-c` 是 `--cache` 的短选项。

普通 `lake build` 和 IDE 默认只验证原生 theorem，不录制步骤或导出页面；六种 Info 命令也跳过字段解码、语义校验和配置登记，语法与模块模式一致性检查仍然生效。已有元数据目标和已知字段仍提供编辑器语义信息，未找到的元数据目标可以跳过。
页面 facet 自动启用 `proofScript.pageBuild`，只清理专用的
`.lake/ps4html/<包名>/<库名>/`，保留普通 `.lake/build/` 与自定义普通构建目录。
一次隔离的 Lake 构建生成所选库、所需用户源码依赖及 ProofScript 框架的 Lean 产物、页面、证明 JSON 和资源，
并在同一工作空间中运行 Info exporter；随后按需 build/finalize 计算资源并渲染 HTML。
页面源码包不恢复旧 artifact cache，以确保 JSON 实际生成。框架与提供 Info 的依赖必须重编译，以恢复默认 renderer、Lean2TeX 及用户配置；Mathlib 等不含所需页面或 Info 数据的基础支持依赖复用缓存。
计算工具读取 Lake 会话提供的真实 C/setup 路径，因此也支持隔离后的构建目录。
导出快照放在 `.PS4HTML/inputs/<包名>/<库名>/.ProofScript/`。输入与 HTML 经同一个版本指针原子发布，编译、导出或渲染失败时保留已发布版本。
`--cache` 只消费已有导出，不检查源码新旧，不执行 Lean、Wasm 构建或 finalize。
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
统一 Info 协议使用 `5.0.0`，录制协议使用 `0.1.0`，契约描述版本为 `1`。每个 script 步骤对应一个 JSON 对象，普通默认录制器提供 `goal_before` / `goal_after`，策略默认录制器只提供 `goal_before`。这些字段与其他字段一样按实际调用的输出契约校验，并可直接用作模板占位符。普通步骤没有剩余目标时，`goal_after` 为 `null`。旧缓存需要重新运行 `lake build MyLibrary:ps4html`；缓存命令不会自动执行 Lean。配置与导出接口见[统一 Info 配置](../../README-zh.md#统一-info-配置)。

命名 theorem/lemma 的 proof artifact 使用 manifest `5`，必需包含 `declaration`、非空字符串 `projectId`、无损 Lean 名称数组 `proofDependencies` 和 `proofFactsDigest`。依赖来自 Lean 最终证明及其创建位置的项目视图；空数组表示成功采集后的零依赖。摘要绑定 artifact ID、源证明摘要、快照 ID 与三个定理字段。页面和未命名录制 artifact 不携带这些证明事实字段。配置 snapshot payload 版本为 `4`，外层文档使用 `5.0.0`。每个页面组件还通过 `snapshotId` 关联自己的配置；页面模式下，`page_end` 只导出内容，不定义元信息边界，其后的配置仍对下游模块生效。

有步骤的 proof 同时提供结构节点表 `expressions`、`expressionRoots` 和 `proof`；code-only 文档只含 `schemaVersion/module/code`。只有根清单指定的位置是表达式，普通 JSON 的 `kind`、`$ref` 或 Display marker 不触发解释。Display 只有在调用契约声明完整展示结构时自动应用。computation 的独立 `function.recordingVersion` 为 `0.1.0`；外层组件、pending、bundle 及资源协议仍为 `0.0.0`，执行 ABI 仍为 `proofscript-json-v1`。

Python 通过 `InfoBundle.theorems[(project_id, name_key(declaration))]` 或 `InfoBundle.theorem(proof_path)` 取得同一份不可变 `TheoremRecord`，其中 `proof_dependencies` 为名称元组数组。该接口先校验整份 bundle，缺字段、重复/自依赖、项目与冻结元数据不一致或摘要错误均拒绝；旧缓存必须重新运行 Lean 构建，不能补成空数组。

定理导航由 `TheoremGraph` 统一生成：渲染前先读取整个 bundle，建立同项目的直接依赖与反向关系，再选择需要输出的页面。图的覆盖范围是 bundle 明确列出的模块及其定理产物，包含独立证明与 `page_end` 后的证明。没有页面的目标、或未包含在本次输出中的页面目标，会保留为无链接文本。依赖不再通过源码、短名或表达式表猜测，页面只通过显式 proof artifact 关联事实，并校验模块与冻结快照。

theorem 与 lemma 使用同一导航视图；中英文正文通过 `data-theorem-id` 共享逻辑身份，原有锚点保持不变。每条定理的图保存在 `<template>` 内，浏览器只向一个显示槽装载当前图，同一身份保留现有 DOM。

当前定理由鼠标实际命中的正文决定，包含标题、展开分支和源码面。进入当前导航时保持源定理，可点击依赖链接；进入其他定理立即切换。离开正文和导航后延迟 150 毫秒隐藏，便于跨过二者间的空隙；离开窗口、失焦或切到后台立即清空。初始没有鼠标坐标时不选择，URL hash 不指定当前定理，触摸输入也不会建立悬停选择。

滚动（包括内部容器）、窗口缩放和布局变化只按保存的鼠标视口坐标重新命中。语言、源码翻转、缩进和公式组件通过 `document` 的 `ps4html:layoutchange` 事件通知控制器，原生分支 `toggle`、内容 `ResizeObserver`、资源和字体加载补充通知；新增改变布局的组件也应发出该事件。控制器不观察导航自身。进度与验收见[重构方案](../../docs/Theorem-Navigation-Refactor-Plan-zh.md)。

当前不提供语言或外部规则的 CLI 配置参数。站点使用内置默认语言，页面内既有双语交互保留。

## 渲染规则

### Lean 声明宏

表达式渲染规则在 Lean 文件中声明，并按证明模块的导入关系生效：

```lean
def_info HAdd.hAdd { kind := operator, arguments := explicit, styles := [
  { name := "formula", template := "#0+#1", fixity := «infix»,
    precedence := 65, associativity := left }
] }
def_info Eq { calc_symbol := some "=" }
var_info "Real" { default := "x", names := ["x", "y", "z"] }
```

还支持 `alias`、`unwrap`、`phrase_info`、动态参数和有序样式。
Lean 负责导入合并并将消费配置冻结到 `.ProofScript/info/snapshots/`，Python 直接读取快照；
Python API 为 `Lean2TeX.load(export_root, proof_module, snapshot_id=...)`。模块所有产物共用一个快照时可省略 snapshot_id。
参见 [Lean2TeX 说明](Lean2TeX/README.md)。
模板可用 `@N`、`@@N` 等引用第 N 个显示参数的连续 lambda binder；
`binders := [(N, 2)]` 声明该参数至少需要两层，此时 `@@@N` 引用正文。
按配置顺序选第一个 binder 数量符合的样式；每个使用 `@` 的宏还需提供一个
不使用 `@` 的回退样式。变量引用来自同一个 DisplayTree，数量不足时不会猜测 binder。

### Tactic 与 Strategy

Lean 中的 `script_info <注册ID> { template := [{ lang := "zh", tag := "标题", content := "正文" }] }` 定义普通展示模板；按语言代码合并，缺少请求语言时使用首项；
特殊策略使用 `renderer := «calc»` 等已注册的 Python 渲染器标识；`calc`、`infer` 值需要 Lean 的 `«»` 转义。
Lean 在 `info/index.json` 中为每个 proof 绑定 snapshotId，并按完成后的 step 结构路径绑定实际调用契约；proof JSON 保留
`module`、每一步的 `_ruleId`、参数和真实分支。`PS4HTML/render_rules.py` 使用对应路径的契约与快照模板排版；同一个规则可以在一个证明中使用多个契约版本。隐藏步骤同样接受完整数据校验，缺失规则或所需字段会阻止发布。
Lean2TeX 的 `def_info` / `var_info` / `phrase_info` 控制数学表达式排版，
不属于 tactic/strategy 规则。

没有手写 recorder 且自动 recorder 无法生成时，Lean 发出警告并继续执行，步骤使用保留
`_ruleId: "ProofScript.Recording.unrecorded"`，`name` 保存原策略关键字。PS4HTML 复用“未知策略”的红色样式显示
“未导出数据”（英文为 “Data not exported”），并继续展示已录制的分支和后续步骤。

## 开发资源

未导出步骤的渲染回归测试：`PYTHONPATH=tools/ps4html python3 -m unittest Test/test_unrecorded.py`；Lean 端用 `lake build TestPage:pageTests` 检查警告、策略分支、continuation 和手写覆盖。

单次构建与失败发布的回归测试：`PYTHONPATH=tools/ps4html python3 -m unittest Test/test_ps4html_build.py`。

真实双用户包的模式切换与缓存隔离：`python3 -m unittest Test/test_page_mode_integration.py`。先完成普通 `lake build`；此检查使用本地依赖，验证跨包内联配置、定理依赖和 HTML 发布，不需要 LaTeX、Wasm 或联网。

依赖导航重构的六个阶段已全部完成。集成示例在 [`../../examples/site/`](../../examples/site/)。完整检查使用 `lake build proofscriptExport Test ProofScript` 和 `lake build TestPage:pageTests`，在示例项目执行 `lake build PS4HTMLDemo:ps4html`，再从仓库根目录执行 `node Test/test_theorem_navigation_browser.mjs` 和 `node Test/test_theorem_site_browser.mjs`。浏览器检查需要 Node 22+ 与 Chrome；真实站点检查加载页面正常使用的 KaTeX CDN 资源。

`@theorem` / `@lemma` 在声明时保存默认项目，并按创建时捕获的配置边界确定自身的归属和展示。请在声明前用 `project_info "P" { ... }` 选择活动项目，或在声明名之后、binders 之前写 `(info := { project := "P", name := "展示标题" })`。后置 `theorem_info T` 仅影响后续内容和导入模块，不能补改已有证明的标题或归属；`page_end` 不延后该边界。同一项目的多个模块应使用同一个字符串 ID；仅有相近命名空间不能建立项目关系。普通 Lean theorem 在被证明引用前也需要用 `theorem_info` 明确归属，才能成为项目内依赖。

从旧版迁移时先更新 ProofScript 和 PS4HTML，再执行 `lake build MyLibrary:ps4html` 重新导出。旧 bundle、缺失证明事实或混用协议版本会明确报错，`ps4html make --cache` 不迁移旧 JSON。若旧版在发布链接的位置使用普通目录，应先将该项目 `.PS4HTML` 归档后重建；现行发布结构的失败构建会保留已发布版本。页面构建模式与验收结果见[页面编译模式重构方案](../../docs/Page-Build-Mode-Refactor-Plan-zh.md)。
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
