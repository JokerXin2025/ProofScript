# PS4HTML：ProofScript HTML 渲染器

PS4HTML 消费 ProofScript 已完成的模块导出，构建 HTML 页面、导航及交互资源。它不编译 Lean、不固化 Info，也不构建 Wasm。页面、证明、固化的配置和资源由 ProofScript 的 Lake 导出任务提供。

## 安装与依赖

在 ProofScript 仓库根目录运行：

```sh
python3 -m pip install -e ./tools/ps4html
```

需要 Python 3.11+、Lean/Elan/Lake；Pygments 和 jsonschema 随 Python 包安装。`#page latex` 需要 `latex`、`dvisvgm`；计算组件在**导出阶段**需要 Node、Emscripten 和匹配项目 Lean 版本的 Wasm runtime，可通过 `PROOF_SCRIPT_LEAN_WASM_PREFIX` 设置其路径。

## 构建与预览

在使用 ProofScript 的 Lake 项目根目录运行：

```sh
lake build MyLibrary:proofscriptExport             # 只导出 JSON、图片和可执行 Wasm
lake build MyLibrary:ps4html                       # 全库导出成功后渲染
lake build +MyLibrary.Module:proofscriptExport     # 只导出一个模块
lake build +MyLibrary.Module:ps4html               # 单模块渲染
ps4html make --cache                               # 用已有完整库目标重新渲染
ps4html serve                                      # 本地 HTTP 预览
ps4html clean                                      # 清理 .ProofScript/ 和 .PS4HTML/
```

也可使用 `python3 -m PS4HTML` 调用 Python CLI；`-c` 是 `--cache` 的短选项。包级入口为 `.PS4HTML/build/index.html`，各库站点位于同级的 `.PS4HTML/build/<库名>/`，页面资源统一位于 `.PS4HTML/build/assets/`。单模块目标只导出该模块，imports 作为编译和配置依赖，不额外导出其页面。

普通 `lake build` 和 IDE 默认不记录页面数据。页面目标设置 `pageBuild = true`，在 `.lake/proofscript/<包名>/<库名>/` 中维护独立、可缓存的编译产物。关闭 `pageBuild` 时 Info 字段仍检查合法性，但 Info 写入和组件不记录；重新开启不会补录跳过的部分。页面模块可在任何合法命令位置添加组件；后置的 Info 更新在该模块导出时生效。

ProofScript 每个模块独立准备、校验和发布；编译、Info 固化、图片复制或 Wasm 构建失败时保留该模块最近一次成功导出的文件。其它已成功模块保持更新，但本次目标有失败时不会启动 PS4HTML。只有目标内所有模块都成功导出，Lake 才更新目标清单并开始 Python 渲染。`make --cache` 不检查 Lean 源码新旧，也不会重新运行 Wasm 工具；修改源码应重新运行 Lake facet。

## 输入协议

模块导出协议为 `14.0.0`，证明录制协议为 `0.4.0`，调用契约版本为 `2`。各类文件按 Lean 模块路径存放：

```text
.ProofScript/info/Project/A.json
.ProofScript/pages/Project/A.json
.ProofScript/proofs/Project/A/<声明路径>.json
.ProofScript/resources/Project/A/...
.ProofScript/manifests/modules/Project/A.json
.ProofScript/manifests/targets/<包名>/<库名>/library/<库名>.json
```

页面模块的 Info JSON 只包含组件通过公共接口请求、在所属模块的最终 imports 视图中固化的配置；未配置的对象直接使用默认值。`project_info` 也遵循 imports 可见性，同库无依赖关系的其它模块不会改变当前页面的配置。纯配置模块没有 Info 或页面 JSON，空页面不会生成 HTML。渲染器依据目标清单选择模块，并校验模块清单及文件的 SHA-256；旧 `info/index.json`、散列 snapshots 与 library 分区 bundle 不再受支持，须重新执行 Lake 导出。

页面使用 ProofText、标题、theorem/lemma、图片、LaTeX 和计算组件；Lean2TeX 读取该模块 Info 排版表达式，script 模板读取实际证明步骤与已固化的调用契约。定理导航依据 Lean 导出的证明事实，跨页面目标若不在本次渲染范围内则显示为无链接文本。Wasm 在导出阶段已生成，PS4HTML 仅复制所需运行文件。渲染完成后会提供 `assets/` 和 `lean2tex-report.json`。计算页面应通过 `ps4html serve` 等 HTTP(S) 服务打开。

普通 script 步骤可点击展开仪表盘，查看录制的上下文、目标变化和由 `script_info.board` 配置的字段。配置示例和缺失字段规则见[Info 命令参考](../../docs/Info-Commands-zh.md#普通步骤仪表盘board)。

详细协议与失败行为见[导出布局](../../docs/ProofScript-Export-Layout-zh.md)，Info 配置见[命令参考](../../docs/Info-Commands-zh.md)，表达式排版见 [Lean2TeX](Lean2TeX/README.md)，计算资源见[前端交接文档](../../docs/Frontend-Computation-Handoff-zh.md)。
