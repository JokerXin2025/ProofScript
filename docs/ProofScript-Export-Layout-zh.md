# ProofScript 模块导出布局

ProofScript 导出与 HTML 渲染是两个独立阶段。`lake build <库>:proofscriptExport` 编译页面模式模块，并在每个模块编译成功后导出其页面、证明、固化的 Info 和资源（包括可执行 Wasm）；`lake build <库>:ps4html` 等本次目标的全部模块导出成功，再调用 Python 渲染器。`lake build +<模块>:proofscriptExport` 和 `lake build +<模块>:ps4html` 只导出选定模块，imports 只用于编译及读取配置。

## 目录

以 Lean 模块 `Project.A.A1` 为例，模块名按分量映射目录；不额外添加库名或源码 `srcDir` 前缀：

```text
.ProofScript/
├── info/Project/A/A1.json
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
└── <包名>/<库名>/...
```

特殊 Lean 名称按无损规则编码（数值分量使用 `%N`，其它特殊字节使用 `%HH`）。Lake、Lean 导出器和 Python 都依据相同的编码路径；库身份使用 Lake 提供的 package/library 归属，而不是从模块名首段猜测。

## 文件与协议

模块协议版本为 `14.0.0`。页面模块各有一份 `info/<模块路径>.json` 和 `pages/<模块路径>.json`；`info` 包含最终固化的请求记录及证明调用契约。定理/引理组件的 `value` 包含 `declaration`（无损 Lean 名称）、`projectId`、展示标题 `name`、`proofRefs`（含 `name` 和 `isDependency`）、`proofDependencies`、`sorryAx` 和指向独立证明 JSON 的 `proof` 资源；组件键 `theorem` / `lemma` 表示声明类别。证明文件保存源码、陈述、表达式及步骤与 `bindings`，不再重复导出 `declaration` 或 `theoremFacts`。纯配置模块不生成 Info 或页面 JSON，但其配置写入仍保存在 `.olean`，供导入它的页面模块固化。无组件模块不生成页面；PS4HTML 也不会为它生成 HTML。

每份 `manifests/modules/<模块路径>.json` 标明 package、library、模块身份、是否有组件、文件清单和 SHA-256 摘要。`manifests/targets/` 指定本次目标包含的模块及其完成清单摘要；渲染器只读取目标内的模块，拒绝版本不兼容、缺失或摘要不匹配的文件。旧 `info/index.json`、散列 snapshots、按库重组的 bundle 均不是新协议输入，必须重新运行 Lake 导出目标。

## 增量、失败与缓存

模块先在私有临时目录生成并校验全部数据；Info 固化、图片复制、Wasm 构建均成功后才发布，旧模块过期文件由新清单清理。某模块失败时保留其最近一次完整导出，已成功发布的其它模块也保留；若本次目标有失败，不更新目标清单、不启动 PS4HTML。目标清单只在全部模块成功后发布。

页面模式编译产物与普通 `.lake/build/` 隔离，位于 `.lake/proofscript/<包名>/<库名>/`。导出缓存检查本模块及相关上游页面模式产物，避免上游 Info 更新后误用旧配置；外部图片单独变化不触发导出，但下次执行模块导出时会重新复制。删除导出文件会使相应模块重新导出。`ps4html make --cache` 只读取现有完整 library 目标清单重新渲染，不调用 Lean 或 Wasm 工具链。
