# Verso 片段渲染器（阶段 2）

构建：`lake build proofscriptVersoRender`。调用：

```text
.lake/build/bin/proofscriptVersoRender INPUT.json OUTPUT.json ASSET_DIR
```

程序只读取输入 JSON 和阶段 1 已导出的语义数据，不导入用户模块，也不 elaboration 用户证明。一次请求包含多个页面、多个源码实例；调用者在发布页面之前检查进程退出码及输出清单。任何解码、身份、源码摘要或实例 ID 错误均非零退出；不使用 Pygments 降级。

## 输入 `proofscript.verso.render.v1`

```json
{
  "protocol": "proofscript.verso.render.v1",
  "pages": [{
    "id": "page-Test-A",
    "links": [{
      "name": ["Project", "theoremName"],
      "targets": [{"short": "本站", "long": "定理页面", "href": "../A.html#theorem-Project.theoremName"}]
    }],
    "instances": [{
      "id": "code-page-Test-A-theoremName-0-zh",
      "context": "code-page-Test-A-theoremName-0-zh",
      "declaration": ["Project", "theoremName"],
      "code": "#page theorem theoremName : True := by\n  trivial",
      "resource": "{...阶段 1 semanticCode 资源的完整 UTF-8 JSON 文本...}",
      "visibleStates": []
    }]
  }]
}
```

`resource` 为资源**内容**而不是路径：Python 先根据完成清单和 `$resource.hash` 验证路径、字节与摘要，再传入程序。Lean 严格检查格式、生产者、声明、`code` 的 JSON-string SHA-256 和 `Highlighted.toString`；不会执行代码。链接由 Python 计算相对于当前页面的目标；未列出的站外常量不产生链接。`links` 同时作用于常量引用与定义 token。`id` 在整批页面中唯一；`context` 控制局部变量联动作用域，建议每个实例唯一，跨语言共享语义对象仍分别渲染。`visibleStates` 是源码绝对字节范围 `[start, stop]` 的列表，空数组表示默认关闭状态。

## 输出

```json
{
  "protocol": "proofscript.verso.render.v1",
  "pages": [{"id": "page-Test-A", "instances": [{"id": "...", "html": "<code class=...>...</code>"}], "hover": {"0": "<code>...</code>"}}],
  "assets": {"version": "verso-v4.32.0", "files": [{"path": "highlighting.css", "hash": "..."}]},
  "cacheKey": "..."
}
```

每页的 hover 表在其全部实例间去重，ID 从 0 开始；页面间各自独立。Verso 生成的 tactic-toggle/goal 控件 ID 在本批次跨页面唯一，输出的 `html` 是完整 `<code class="hl lean block">` 片段，不从 HTML 提取复制文本；复制仍使用输入证明 JSON 的原始 `code`。调用方须给每页提供对应的 `hover` 数据并部署 `assets` 中的文件。输出缓存键覆盖输入实例计划、语义资源、链接与 CSS/JS 清单；应用侧若缓存，还须将**渲染器可执行文件摘要**纳入缓存键。

`ASSET_DIR` 包含同版本 `highlighting.css`、`highlighting.js`、`popper.js`、`tippy.js`、`tippy-border.css` 和 `marked.js`，清单哈希采用 `ProofScript.contentHash`（UTF-8 字符串的 JSON 编码 SHA-256）。Verso 的 `highlighting.js` 初始化入口被接线层重命名为 `window.ProofScriptVersoInit`，源码选择器限定于 `.verso-source`；PS4HTML 在该入口执行前设置本页的 `window.ProofScriptVersoHoverData`，并在语言切换、翻面和布局更新时关闭隐藏面板的悬浮窗。

对与原始 `scriptTactic*` 语法**完全同范围**、并在本次 InfoTree 中有 `tactic_script_*` 完成记录的单步策略补投影，展示 Verso 自身的 `All goals completed!`。其他状态继续遵循 SubVerso 已产生的状态，不虚构未记录的目标内容。可通过 `lake build proofscriptVersoRender` 构建批量渲染程序。
