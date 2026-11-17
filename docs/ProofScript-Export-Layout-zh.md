# ProofScript 模块导出布局

ProofScript 导出与 HTML 渲染是两个独立阶段。`lake build <库>:proofscriptExport` 编译页面模式模块，并在每个模块编译成功后导出其页面、证明、固化的 Info 和资源（包括可执行 Wasm）；`lake build <库>:ps4html` 等本次目标的全部模块导出成功，再调用 Python 渲染器。`lake build +<模块>:proofscriptExport` 和 `lake build +<模块>:ps4html` 只导出选定模块，imports 只用于编译及读取配置。

## 目录

以 Lean 模块 `Project.A.A1` 为例，模块名按分量映射目录；不额外添加库名或源码 `srcDir` 前缀：

```text
.ProofScript/
├── info/Project/A/A1.json
├── info/<库名>.json                 # 库目标成功时的全量已配置 Info
├── pages/Project/A/A1.json
├── proofs/Project/A/A1/<声明路径>.json
├── resources/Project/A/A1/<类型>/<文件>
├── computations/...
├── manifests/
│   ├── modules/Project/A/A1.json
│   └── targets/<包名>/<库名>/library/<库名>.json
├── publish.lock
└── staging/

.PS4HTML/build/
├── index.html
├── assets/...
└── <库名>/
    ├── verso/{highlighting.css,highlighting.js,popper.js,tippy.js,marked.js,...}
    ├── verso/manifest.json
    └── ...
```

特殊 Lean 名称按无损规则编码（数值分量使用 `%N`，其它特殊字节使用 `%HH`）。Lake、Lean 导出器和 Python 都依据相同的编码路径；库身份使用 Lake 提供的 package/library 归属，而不是从模块名首段猜测。

## 文件与协议

模块、Info、浏览器交互和证明录制数据不携带版本字段；Verso 源码语义资源单独携带格式与生产者版本。页面模块各有一份 `info/<模块路径>.json` 和 `pages/<模块路径>.json`；`info` 包含最终固化的声明、脚本请求记录及证明调用契约，不再包含项目元数据记录。所有声明（包括定理）均使用 `identity.kind = "decl"` 的唯一记录，值中的 `names` 和 `tags` 均为带有 `lang`（字符串或 null）及 `value` 的有序对象列表。定理/引理组件的 `value` 包含 `declaration`（无损 Lean 名称）、`projectId`、`proofRefs`（含 `name` 和 `isDependency`）、`proofDependencies`、`sorryAx` 和指向独立证明 JSON 的 `proof` 资源；组件键 `theorem` / `lemma` 表示声明类别。标题由渲染器按语言从 Info 中选取，不在组件内固化。证明文件保存源码、陈述、表达式及步骤与 `bindings`，以及 `semanticCode` 资源引用，不再重复导出 `declaration` 或 `theoremFacts`。语义资源是 JSON 外壳（`format = proofscript.verso.highlighted.v1`、`sourceHash`、`declaration`、`producer` 和不透明的 `highlighted` 字符串），由本次页面编译的原始命令与 InfoTree 生成；Python 只验证外壳与原 `code` 的 SHA-256 一致，不解析 SubVerso 内部编码。纯配置模块不生成 Info 或页面 JSON，但其配置写入仍保存在 `.olean`，供导入它的页面模块固化。无组件模块不生成页面；PS4HTML 也不会为它生成 HTML。项目标题等站点信息由 PS4HTML 在渲染时读取根目录的 `ps4html-config.toml`。

每份 `manifests/modules/<模块路径>.json` 标明 package、library、模块身份、是否有组件、文件清单和 SHA-256 摘要。`manifests/targets/` 指定本次目标包含的模块及其完成清单摘要；库目标清单还记录库级 Info 的路径与 SHA-256。渲染器只读取目标内的模块与库级 Info，拒绝缺失或摘要不匹配的文件。站点级 Verso 前端资源是渲染产物，记录在库内的 `verso/manifest.json`（文件路径、SHA-256 和含渲染器可执行程序摘要的缓存键），不重复写进 Lean 模块导出清单。旧 `info/index.json`、散列 snapshots、按库重组的 bundle 均不是当前输入格式，格式变化后须重新运行 Lake 导出目标；发布器和渲染器不迁移旧数据。

库目标在所有模块导出成功后，将本库所有显式写入或重置过的声明与脚本配置（以及别名依赖）置于共同导入视图中固化，生成 `info/<库名>.json`，包含 `library` 和 `records`；未被页面请求的配置也会校验，冲突或无效配置使库目标失败且不发布新快照。单模块目标不更新库级快照。

## 增量、失败与缓存

模块先在私有临时目录生成并校验全部数据；Info 固化、图片复制、Wasm 构建均成功后才发布，旧模块过期文件由新清单清理。某模块失败时保留其最近一次完整导出，已成功发布的其它模块也保留；若本次目标有失败，不更新目标清单、不启动 PS4HTML。目标清单只在全部模块成功后发布。

页面模式编译产物与普通 `.lake/build/` 隔离，位于 `.lake/proofscript/<包名>/<库名>/`。导出缓存检查本模块及相关上游页面模式产物和 Verso 采集适配器，避免上游 Info 更新后误用旧配置；外部图片单独变化不触发导出，但下次执行模块导出时会重新复制。删除导出文件会使相应模块重新导出。`ps4html make --cache` 从现有完整 library 清单重新渲染，需可用的 `.lake/build/bin/proofscriptVersoRender`（或环境变量 `PROOF_SCRIPT_VERSO_RENDERER` 指向兼容的已编译程序）；它运行只读的 Lean 片段程序，不重新 elaboration 证明，也不再保证纯 Python 离线重渲染。每次渲染都检查程序退出状态、实例数、语义资源和前端资产哈希；阶段 2/3 渲染的 `verso/manifest.json` 中的缓存键包含实例/链接计划、语义数据、资源版本及渲染器可执行文件摘要。任何富源码资源缺失、格式/摘要不匹配或采集失败都会阻止本次目标发布，不降级为 Pygments。
