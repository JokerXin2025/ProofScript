# ProofScript 重构：第一阶段协议与构建设计

本文是第一至六阶段的**历史实施记录**，其中“过渡期”和“下一阶段”的表述只反映当时进度，不描述当前构建入口。当前协议、目录和命令以 [导出布局](ProofScript-Export-Layout-zh.md)、[README](../README-zh.md) 为准；旧版数据不得混合读取。

## 1. 责任和语义边界

1. Lean elaboration 只在 `pageBuild = true` 的命令中追加持久化 Info 更新、组件、Info 请求、证明录制数据和资源/计算描述；不写 `.ProofScript/`。`pageBuild = false` 的 Info 字段仍校验，但不录入，重新开启不会补录。
2. 页面是模块内按序追加的组件集合，没有 `#page end`。请求只记录目标、必要性和来源；模块导出时在该模块的最终 import 闭包中固化。`#preview` 在命令所在位置独立固化，不录入请求；固化绝不改变写入记录。
3. ProofScript 的模块导出任务负责配置合并/验证、页面/证明 JSON、资源复制和可执行 Wasm。允许无显式配置时采用 schema 默认值，不输出 `configured` 或“未配置”标记；存在但冲突或不合法的配置不能退回默认值。
4. PS4HTML 只读完整导出产物并渲染，不调用 Lake、不解析 Info 更新记录、不补建 Wasm、不改写 `.ProofScript/`。
5. 当前 Lean library 由 Lake 的 `(package, library)` 确认。`project_info` 只影响其对应的 library，读取时仅使用目标模块的 import 闭包；未导入的同库模块不影响结果。页面模式编译需由 Lake 向 Lean 传入该身份并随配置写入记录，不能在导出时依据声明名字推测；普通构建不录入这类记录。若相同源码参与多个 library，则按各自归属编译隔离的页面模式产物。

## 2. 持久化与配置请求契约

沿用现有 `InfoEvent` 的单次写入记录语义，包括 owner、模块内顺序、schema、reset 和 patch；增加可供诊断的来源信息与 project library 身份。环境扩展内的导入表必须保持独立，不能因为一次固化覆盖或合并原始记录。上游无依赖关系的冲突只在固化时检查。

统一请求结构至少含 `kind`、无损 `target`、`required`、组件/录制来源和模块内顺序；同一模块内合并重复目标，必需性取并集，保留所有错误诊断来源。所有组件（含第三方组件）必须调用同一接口。定理组件请求自身 theorem、表述和 script 参数的结构化表达式根内出现的常量，以及实际调用的 script；配置依赖和 renderer 声明的依赖按闭包继续展开。不得以遍历任意 JSON 文本代替表达式/参数的结构化依赖采集。

统一固化入口接受 `(environment, owner module, library identity, Info target)`，返回有效记录与直接依赖或诊断。缺省值属于正常记录值；已配置但无效始终是错误。循环依赖需要确定性的诊断。`#preview` 调用相同入口但使用当前位置环境，导出使用编译完成后的环境。证明调用契约仍固定为录制时的版本，不因展示配置的最终固化而改写。

## 3. 下一版物理布局和路径

以模块 `Project.A.A1` 为例，路径来自**Lean 模块名**而非源码的 `srcDir`、library 名或 package 名：

```text
.ProofScript/
├── info/Project/A/A1.json                   # 仅有组件请求时生成的有效配置
├── pages/Project/A/A1.json                  # 有无组件均可记录空页面
├── proofs/Project/A/A1/<声明路径>.json
├── resources/Project/A/A1/<资源 ID>.<扩展名>
├── manifests/modules/Project/A/A1.json     # 模块成功发布的完成清单
├── manifests/targets/<目标 ID>.json         # 当前目标模块清单，汇总阶段写入
└── staging/                                 # 构建及发布的临时数据
```

纯配置模块只需模块清单，不生成 Info JSON；没有组件的模块不由 PS4HTML 生成 HTML。`proofs/` 和 `resources/` 的所有权按**消费它们的模块**确定；同一内容在两个模块使用时可以复制两份，避免跨模块共享清理。当前目标按 Lake 清单选模块，绝不以扫描旧目录确定渲染范围。单模块导出只发布选定模块；依赖包只参与编译和 Info 读取。

路径编码采用现有 `Output/Path.lean` 的思路：逐个编码 Lean `Name` 组件，字符串组件按 UTF-8 字节转义，数字组件使用区别于字符串的标记；禁止 `.`、`..`、分隔符、控制字符和空路径组件穿透目录。实现时对 `%` 等特殊字节、保留文件名及大小写不敏感文件系统上的碰撞加检测；校验编码可逆性及从输出根目录逃逸的情况。模块页 `A.json` 与模块 `A.B` 的 `A/B.json` 不碰撞；证明名需要保留模块与声明的边界，避免匿名/局部名称互相覆盖。一个工作区中两个不同库若声明**同名 Lean 模块**，不得静默覆盖：导出前报告所有权冲突；跨包同名模块也同理。

内部引用统一使用 `.ProofScript/` 起始的逻辑路径；清单内文件路径相对于 `.ProofScript/`，必须通过规范化和根目录约束检查。协议版本整体提升，旧快照、library 物理分区、`configured`、单库虚拟根等不得隐式迁移。

## 4. JSON 文档与清单契约

下列字段为下一阶段实现时的**最低契约**；新协议计划由当前 `12.0.0` 提升为 `13.0.0`，持久化扩展各自的 schema 版本仍分别维护。字段的具体 JSON Schema 在实现阶段从类型定义生成并由 Python 端严格验证。`Name` 类型字段使用当前无损 Lean 名称编码（字符串/数字组件数组），展示字符串另存，不能反向解析普通显示文字作为身份。

| 文档 | 最低字段及约束 |
| --- | --- |
| `info/<module>.json` | `schemaVersion`, `module`, `library` (`package`, `library`), `records`（唯一 Info 身份、schema ID/版本、有效值）, `contracts`（实际使用的录制契约）；只包含页面请求及其依赖闭包，不能暴露整库事件表。 |
| `pages/<module>.json` | `schemaVersion`, `module`, `components`（源码顺序、组件种类、数据、稳定引用）；组件引用本模块 Info/证明/资源，零组件时 PS4HTML 跳过 HTML。 |
| `proofs/<module>/<declaration>.json` | `schemaVersion`, 无损声明身份、录制表述/步骤/表达式、契约绑定、引用事实；记录所属模块及内容摘要，不靠重新运行 tactic 生成。 |
| `manifests/modules/<module>.json` | `schemaVersion`, 无损模块身份、`package`, `library`, `complete: true`, `hasComponents`, 所有归属文件相对路径及内容摘要；最后发布，承担模块产物的成功标识。 |
| `manifests/targets/<target>.json` | `schemaVersion`, 目标 package/library/模块或单模块类型、当前模块身份清单和对应模块清单摘要；仅在目标全部导出成功后更新。 |

例如 `Project.A.A1` 使用的**模块完成清单**约定如下（摘要为文件内容的 SHA-256；`module` 是无损名称数组）：

```json
{
  "schemaVersion": "13.0.0",
  "module": ["Project", "A", "A1"],
  "package": "MyPackage",
  "library": "Project",
  "complete": true,
  "hasComponents": true,
  "files": [
    { "path": "pages/Project/A/A1.json", "sha256": "<64 位十六进制摘要>" },
    { "path": "info/Project/A/A1.json", "sha256": "<64 位十六进制摘要>" }
  ]
}
```

`files` 仅列内容文件，不包含清单自身；完整清单的 SHA-256 则由目标清单引用。未生成的 Info 或页面文件不允许留在 `files` 中；同一物理路径不得由不同模块清单共同拥有。目标清单的模块清单摘要固定本次渲染所读取的版本，读取中途出现不匹配须失败并重试或使用完整快照，不能拼接不同时刻的输入。

外部图像复制到本模块 `resources/`。计算资源含可执行 Wasm 及调用所需清单，由 ProofScript 独立工具生成；导出器确认资源齐全并计算摘要后才发布。资源内容改变不自动使 Lake 导出任务失效；再次执行导出时复制最新内容。纯配置模块没有组件请求，因而既无 `info/<module>.json`，也不要求所有 Info 都是完整最终值。

模块清单是清理自身旧产物的唯一授权来源；不能根据目录前缀清理其它模块文件。处理同一模块删除组件、证明、图片、计算的情况时，比较新旧清单并只替换/删除该模块所有的路径。删除或改名的整个模块不纳入当前目标清单；磁盘上的历史文件可以保留，不参与渲染。

## 5. Lake 作业依赖图

```text
页面模式模块 .olean（含正确的 imports） ─────┐
ProofScript 导出器/协议版本及工具链 ──────────┼─→ 模块导出作业 ─→ 模块完成清单
页面模式元数据与库归属 ──────────────────────┘                       │
                                          所有选定模块作业完成 ──────┼─→ 目标清单
                                                                      ├─→ proofscriptExport 完成
                                                                      └─→ ps4html 启动 Python 渲染
```

模块 facet 用 `mod.leanArts.fetch` 的作业依赖，而不是在源码结尾执行导出；library facet 用 `lib.modules.fetch` 取 owner，汇集每个 owner 的导出作业。模块目标只调度其自身导出，不把 imports 当作 owner。上游提供 Info 的模块仍需要页面模式 `.olean`，普通构建的 `.olean` 不能混入；保留页面模式产物隔离，但取消 Python 清空目录后嵌套调用 Lake 的构建编排。library 的项目归属来自 Lake 选定的 `mod.lib`，输入清单带入 exporter。库级目标汇集模块作业时不能依赖某个模块在源码中手动声明结束事件。

**第一阶段独立实验已验证**（Lean/Lake v4.32.0）：

- 模块 facet 等待 `mod.leanArts.fetch` 后可观察到 `.olean` 并写出本模块 JSON；
- 删除 JSON 而保留 `.olean`，重新 `lake build Probe:probeExport` 会重建 JSON，Lean 模块无需重新编译；
- 双模块 library facet 可汇集各自的模块导出作业；实验未改动项目 `lakefile.lean`，在临时目录进行。
- 模块作业还可并行依赖 `lean_exe`，使用 `getAugmentedEnv` 启动独立 exporter；exporter 成功 `importModules` 并读取该模块的 Lean 声明，无需 PS4HTML 环境变量。

该实验**尚未证明**正式方案的 trace/失效条件、隔离目录下的 exporter 搜索路径、并发发布或大规模页面模式缓存开销。正式任务需把 exporter/协议版本与页面模式构建输入纳入 trace，检查输出文件清单仍存在；图片内容按约定不自动入 trace。导出器通过 Lake 提供的环境/显式清单加载 `.olean`，不依赖 PS4HTML 会话变量。Wasm 协调器可继续使用 Python，但置于 ProofScript 自身工具目录，不引入 PS4HTML。

## 6. 发布、并发和失败

模块在私有 staging 中完成固化、JSON、图片、Wasm 和摘要校验；失败时不触碰旧模块清单及其产物。成功后获取发布锁，依据新旧清单替换该模块文件、清理不再使用的旧文件，最后写完成清单；实现跨目录回滚或可恢复日志。读取目标的 PS4HTML 需与模块发布使用一致的读写锁/快照机制，不能读到多个目录间的半成品。全局目标清单由汇总作业单独写入，模块作业不能竞争覆盖全局索引。

一个模块失败时其它模块已成功的导出保留；目标清单不更新，`ps4html` 不渲染。单独的重新渲染入口使用上次完成的目标清单；无法从旧文件自行推断新目标。两个构建目标并发请求同一模块时，使用相同所有权与锁/版本检查，不能让较早的构建覆盖较新的模块结果。

## 7. 阶段二至七的衔接与验收

1. **Info**：先实现只读固化、请求记录和 `#preview`，移除全库 `project_info` 扫描；验证下游覆盖、独立冲突、默认值和 imports 可见性。
2. **持久化**：删除 `#page end`；页面、证明及资源数据可从 `.olean` 重建，编译不写 `.ProofScript/`。
3. **导出**：实现新协议、模块目录、Wasm 独立构建、逐模块发布及旧文件清理；失败保留旧清单。
4. **Lake**：用真正的模块作业替换现有 Python→Lake→exporter 回路；验证缓存命中、单模块范围、并发和失败隔离。
5. **PS4HTML**：直接消费新协议及目标清单；删除 Info 解析、补建资源、库分区组装和回调编译逻辑。
6. **迁移**：替换旧版布局文档，更新 README、示例与集成测试；明确 `pageBuild = false` 区间不录入数据，旧数据需重新构建。

## 8. 第二阶段的过渡接口（实施记录）

`Info/Freeze.lean` 提供 `requestInfo` / `requestInfoCommand`、`moduleInfoRequests`、`freezeInfo`、`freezeProjectInfo` 和 `freezeRequestedInfo`。请求作为独立持久化扩展写入 `.olean`，不会当场固化；`#preview project_info`、`#preview theorem_info <声明>`、`#preview decl_info <声明>`、`#preview script_info <注册 ID>` 使用当前位置的环境只读固化。模块导出器可通过 `freezeModuleRequests` 在完成时固化。项目配置解析按照模块 imports 和 Lake 提供的 owner 过滤，排除其它 library 及未导入模块；编辑器没有 Lake registry 时，预览暂以模块名的首个组件识别同库导入。自定义 roots 或多库共享模块的精确归属仍需在后续阶段由 Lake 提供。`Test/InfoFreezePreview.lean`、`Test/InfoFreezeProjectView.lean` 及 `Test/InfoRefactorRegression.lean` 覆盖这些行为。

旧导出协议的 `configured`、`SnapshotRecord`、Python 配置消费和全库 JSON 清单仍为**现行格式**。新接口不输出 `configured`，但删除旧协议字段需与后续 Output 和 PS4HTML 输入格式同时切换。第三阶段应让组件调用 `requestInfoCommand` 并在页面编译结束时消费请求；第四至六阶段替换旧快照协议、项目聚合出口及下游逻辑。阶段二的请求 API 尚未被组件调用，因此现有渲染结果仍采用旧快照模型。

## 9. 第三阶段的过渡实现（实施记录）

已删除 `#page end` 和页面关闭状态。每个组件、标签及其 Info 请求在同一环境更新中持久化；定理证明 JSON、生成的 SVG 文本及计算待构建描述分别记录于 `.olean`。普通编译不再向 `.ProofScript/` 写入证明、SVG 或计算清单；当前 exporter 从模块扩展恢复它们。`Test/PagePersistence*.lean` 和 `Test/PageResourcePersistence*.lean` 验证后置 `theorem_info`、`pageBuild` 切换、证明/资源以及跨模块重新载入 `.olean`。旧的记录器测试改为直接检查持久化的证明 JSON。

过渡期的 exporter 仍生成第 12 版 snapshot 和单库 bundle，并运行新请求的额外固化检查；Wasm 打包、外部图片复制、模块级独立发布及目录迁移属于第四、五阶段。现有 `:proofscriptExport` 仍采用 Python 回调 Lake 的旧作业，不能用这一入口判断新模块作业是否已完成。旧版 README 和 PS4HTML 用户文档中关于 `#page end` 的描述需随第四至七阶段的协议切换统一更新。

## 10. 第四阶段的实施记录

`Output/Module.lean` 和 `Output/ModuleMain.lean` 已提供独立于旧版 snapshot bundle 的模块导出器：从页面模式 `.olean` 读取组件、证明与请求，在模块最终 imports 视图固化有效 Info，生成版本 `13.0.0` 的 `info/`、`pages/`、`proofs/` 内容。配置模块只生成完成清单。`tools/proofscript/module_export.py` 在私有 staging 中复制图片、运行 ProofScript 自身的 Node Wasm 构建及终结器、验证资源和摘要，随后按模块完成清单替换归属文件。发布时获取 `.ProofScript/publish.lock`，跨目录替换有持久化日志及恢复入口；下次模块发布会先恢复被进程中断的旧产物。旧文件只依据该模块上次完成清单清理，不清理其它模块的文件。

`scripts/test-module-export-lean.py` 已从实际 `.olean` 重建页面与纯配置模块，并在本机 Emscripten/Lean-Wasm 工具链上构建 Wasm、执行函数 `41 ↦ 42`；图片复制同样经过实际模块导出。`scripts/test-module-export.py` 覆盖旧文件清理、缺失图片/资源、无效 Info、Wasm 构建失败、进程内回滚、进程强制退出后恢复以及不同模块并发发布。本阶段未改变 Lake facets：`lake build <库>:proofscriptExport` 仍走旧版第 12 版 Python 回调编排；将新模块导出器接入这些 facets、生成目标清单和协调渲染是第五阶段的工作。旧版 PS4HTML 对图片仍读取源文件，第六阶段须切换为消费页面所引用的已复制资源，并与模块发布共享读取锁或稳定快照。

## 11. 第五阶段实施记录

公开的 `:proofscriptExport` module/library facets 已由 Lake 直接构建隔离的页面模式 `.olean`，并逐模块调用 `proofscriptModuleExport`；不再经过 PS4HTML Python 重新启动 Lake。页面模式构建目录在同一 library 的单模块和全库目标之间复用。模块完成清单的输入指纹包含选定库上下文、owner `.olean`、导出器和计算构建脚本；缓存命中时跳过模块导出，文件损坏或缺失时可从 `.olean` 重建。图片内容按约定不单独触发重新导出。模块成功发布后，库级作业写入当前目标的模块清单与摘要；失败时保留上一次完成的目标清单。

`:ps4html` facet 现在依赖上述导出作业，只有全部模块编译、固化和发布成功之后才调用 `_render-target` Python 入口。`scripts/test-lake-export.py` 验证单模块范围、重复构建、缺失输出的重建、纯配置模块和渲染启动顺序；`scripts/test-target-manifest.py` 验证目标发布失败保留旧清单。`lake build Test:proofscriptExport` 也通过全库实际构建与导出。新协议渲染入口在第六阶段接入，见下一节。

## 12. 第六阶段实施记录

`_render-target` 已实现新协议消费：在 ProofScript 发布共享锁下校验目标清单、模块完成清单和每个文件摘要，并将本次目标的输入复制成独立快照；渲染不扫描旧 `info/index.json`，也不修改 `.ProofScript/`。逐模块 Info 的冻结记录供 Lean2TeX 和录制规则使用，页面的证明资源描述符连接独立证明文件和定理依赖图；证明导出补充了步骤绑定。图片从已复制资源读取，Wasm 运行文件由目标清单选定后复制到站点。渲染成功才在 HTML 构建锁下替换站点，失败保留原页面。单模块目标仅提供该模块页面和导航，全库目标包含全部选定模块；无组件模块不产生 HTML。

`lake build +Test.ModuleFigure:ps4html`、`lake build +Test.RecorderVersions:ps4html`、`lake build +Test.ModuleComputation:ps4html` 和 `lake build Test:ps4html` 已完成实际渲染。`scripts/test-module-render.py` 覆盖单模块范围、证明展示、Wasm 资源、全库页面和损坏清单时旧 HTML 保留；旧版 bundle 的清理与文档迁移仍属第七阶段。

第六阶段验收补充了 `scripts/test-render-snapshot.py`：在模块发布临界区并发请求渲染快照，确认读取等待写锁，旧目标清单在更新后因摘要不匹配而失败，重新发布目标后才读取完整新文件。已将 `scripts/test-page-components.py` 与 `scripts/test-theorem-statements.py` 的过时前提改为当前无 `#page end` 的页面模式及独立模块导出：两项测试现在分别覆盖普通/页面编译录入，以及实际导出的录制和原生定理语句。以上测试、模块发布与目标清单回归、`scripts/test-lake-export.py` 及全库 `Test:ps4html` 均通过。
