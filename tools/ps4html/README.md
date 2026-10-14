# PS4HTML：ProofScript 官方站点构建器

PS4HTML 是 ProofScript 的 HTML 站点生成器。Lake 库级 facet 编译并导出页面、证明和资源，
构建所需计算，再渲染到 `.PS4HTML/build/<包名>/<库名>/`；`.PS4HTML/build/index.html` 是项目入口。

## 安装

在 ProofScript 仓库根目录执行：

```sh
python3 -m pip install -e ./tools/ps4html
```

也可以标准安装 `python3 -m pip install ./tools/ps4html`。Python 要求 3.11+，Pygments 自动安装。
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

Lake facet 编译整个库、重新导出所需模块、按需 build/finalize 计算资源，然后渲染 HTML。
导出快照放在 `.PS4HTML/inputs/<包名>/<库名>/.ProofScript/`；不会复用旧 `.Mitar` 数据。
`--cache` 只消费已有导出，不检查源码新旧，不执行 Lean、Wasm 构建或 finalize。
`clean` 删除项目 `.ProofScript/` 与 `.PS4HTML/`，不删除 `.lake/`。

输出包含 `index.html`、按模块组织的页面、`assets/`、计算资源和 `lean2tex-report.json`。
计算页面必须通过 HTTP(S) 打开，`serve` 提供 Wasm MIME、COOP、COEP 和 CSP 响应头。
跨设备 pthread/SharedArrayBuffer 计算需要受信任 HTTPS。

## 页面与交互

- ProofText 标题、段落、列表、引用、字体、代码、公式和链接。
- theorem/lemma 结构化证明、源码卡片、源码翻转、分支展开与缩进控制。
- 正常渲染、`sorryAx`、JSON/结构错误状态；未知 tactic 可见 fallback。
- ProjectInfo、跨页标签、文献、模块与定理依赖导航。
- LaTeX SVG、图片、嵌入证明资源与共享表达式表。
- KaTeX 数学、关联变量高亮、中英文证明和引用面板切换。
- Lean/Wasm Worker runtime 及 Fibonacci、E8、公式实例 renderer。

PS4HTML 不重新验证证明；LaTeX 编译发生在 Lean 导出阶段。
页面、proof、computation component、pending、bundle、published bundle 和 index 的
证明与渲染清单的 `schemaVersion` 为 `0.1.0`；页面、计算及 Lean2TeX 协议仍为 `0.0.0`。消费者兼容旧版 `0.0.0` 证明/渲染输出，在入口适配旧单元素数组。新版字段按 `recordedFields` 契约校验；请重新构建以获得复杂参数数据，不要手工修改版本号。

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
Lean 将显式赋值导出到 `.ProofScript/lean2tex/events/`，Python 根据导入图合并；
Python API 为 `Lean2TeX.load(export_root, proof_module)`。
参见 [Lean2TeX 说明](Lean2TeX/README.md)。
模板可用 `@N`、`@@N` 等引用第 N 个显示参数的连续 lambda binder；
`binders := [(N, 2)]` 声明该参数至少需要两层，此时 `@@@N` 引用正文。
按配置顺序选第一个 binder 数量符合的样式；每个使用 `@` 的宏还需提供一个
不使用 `@` 的回退样式。变量引用来自同一个 DisplayTree，数量不足时不会猜测 binder。

### Tactic 与 Strategy

Lean 中的 `script_info <注册ID> { template := [("zh", "标题", "正文"), ...] }` 定义普通展示模板；按语言代码合并，缺少请求语言时使用首项；
特殊策略使用 `renderer := «calc»` 等已注册的 Python 渲染器标识；`calc`、`infer` 值需要 Lean 的 `«»` 转义。
Lean 为每个证明模块导出 `rendering/effective/<module>.json`，同时在 proof JSON 中记录
`module`、每一步的 `_ruleId`、参数和真实分支。`PS4HTML/render_rules.py` 根据 ID 和当前
模块的规则取出录制数据并排版；缺失规则或所需字段时报错，不按策略关键字猜测。
Lean2TeX 的 `def_info` / `var_info` / `phrase_info` 控制数学表达式排版，
不属于 tactic/strategy 规则。

## 开发资源

集成示例在 [`../../examples/site/`](../../examples/site/)，Schema 在
[`../../docs/schema/`](../../docs/schema/)。浏览器源文件位于 `PS4HTML/assets/js/`，
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
