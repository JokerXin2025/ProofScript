# 标题组件

`ProofScript.Extensions.Title` 使用 `page_component` 定义独立的页面标题，`import ProofScript`
也会导入此模块。标题位于 ProofText 字符串之外：

```lean
#page title (label := "introduction") "引言"
#page text "正文参见 @<details>。"
#page sub title (label := "details") "包含 *粗体* 和 $x^2$ 的二级标题"
#page sub sub title "三级标题"
```

`title` 前每增加一个 `sub`，层级增加一；没有 `sub` 时为一级，不限制层数。
第一至第五级使用逐渐减小的字号；第六级开始保持第五级字号，左侧显示 `层级 - 5` 个 `→`。
导出的 JSON 保留完整 `level`，深层标题的 HTML 使用 `aria-level` 保留真实层级。

标签是可选的，放在标题字符串之前，格式为 `(label := "名称")`，须满足
`[A-Za-z][A-Za-z0-9_-]*`。同一模块中重复的标题标签会报错。ProofText 中的 `@<名称>`
引用该组件，支持向前引用和跨页面引用；既有 `heading-名称` 锚点及引用 JSON 种类保持不变。

标题正文去除首尾 ASCII 空白，并使用与 ProofText 相同的行内格式、公式、链接和引用规则。
列表、引用块、代码块等块级语法不在标题中解析。`#page text` 内的 `=` 不再创建标题或标签，
只遵循普通段落及行内格式规则。

与其他页面组件相同，标题在页面构建时解析、登记并导出；普通验证跳过内容校验。
两种模式下，`#page end` 之后的标题命令都会报错。

[专用测试模块](../Test/PageTitle.lean)展示第一至第八级、六十四级标题、行内格式、标签和引用，
并检查错误及页面关闭规则。构建可预览的测试页面：

```sh
lake build +Test.PageTitle:ps4html
```

页面位于 `.PS4HTML/build/ProofScript/.modules/Test.PageTitle/Test/PageTitle.html`。
自动回归检查：

```sh
lake build ProofScript Test
python3 Test/test_page_title.py
```
