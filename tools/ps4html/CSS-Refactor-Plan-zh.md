# PS4HTML 样式与模版重构

## 已实施：按渲染组件组织

页面 `Templates/page.html` 依次加载 `layout.css`（页面布局、导航和基础变量）、`proof.css`（证明容器、缩进控件、通用标签和证明状态）、`proof-step.css`（普通步骤与 calc）、`proof-branch.css`（可折叠证明分支）、`proof-strategy.css`（策略及注释）、`proof-motion.css`（证明/引用展开动画），随后是图示、引用、正文、媒体、代码翻转、移动端提示、Lean2TeX 和计算组件的专用样式。`codicon.css` 继续作为独立字体资源。样例页 `theorem-css-sample.html` 使用相同的证明样式加载顺序。

旧文件到新文件的映射：`basic.css` → `layout.css`（证明组件规则移至 `proof.css`），`sundry.css` → `proof.css`，`step.css` → `proof-step.css`，`goal.css` → `proof-branch.css`（共用子容器规则移至 `proof.css`），`strategy.css` → `proof-strategy.css`，`animation.css` → `proof-motion.css`。构建时 `PS4HTML/assets` 发布整个 CSS 资源目录；更新模板后重新生成站点即可使用新路径，不能混用旧 HTML 与新 CSS。

### DOM 类名迁移

| 旧名 | 新名 | 使用位置 |
| --- | --- | --- |
| `step-block`, `step-tag`, `step-content` | `proof-step`, `proof-step-label`, `proof-step-content` | 普通步骤、引言、calc；动画/公式宽度 JS |
| `step-lhs`, `step-rel`, `step-rhs`, `step-cal-end` | `proof-calc-lhs`, `proof-calc-relation`, `proof-calc-rhs`, `proof-calc-end` | calc 模版、公式宽度 JS |
| `goal-block`, `goal-content` | `proof-branch`, `proof-children` | details 分支、策略和顶层证明 |
| `toggle-icon`, details 中的 `content` | `proof-branch-toggle`, `proof-branch-title` | details 摘要 |
| `strategy-block`, `script-renderer` | `proof-strategy`, `proof-rule-wrapper` | 策略/注释和带颜色的专用渲染器 |
| `tag`, `proof-mark`, `ref-link`, `qed` | `proof-tag`, `proof-status`, `proof-reference-link`, `proof-qed` | 标签、状态、示例链接、结尾符号 |

`with-line` 不再需要：只在 `.proof-branch > .proof-children` 绘制分支竖线。保留 `introducer`、`calc`、`unknown`、`remark`、`cause`、`diagram` 等类型修饰符，以及 `--rule-*` 配色变量，因为它们由现有规则数据/渲染器驱动；`default`、`pass`、`sorry`、`error` 仍表示状态。Python 动态生成的状态标记与规则 wrapper、浏览器动画和 calc 选择器、浏览器测试均同步更新。`page.html` 上误写成 HTML 属性的 `overflow-y: scroll;` 已清除，滚动样式保留在 CSS。

## 待确认：可合并或移除的候选

下面仅为当前仓库内部引用检查的结果，不代表第三方自定义页面没有依赖；**本次没有删除这些候选**。

| 候选 | 依据与建议 |
| --- | --- |
| `layout.css` 的 `.module-index` / `.module-index li` / `.module-index a` | 生成器只输出 `.module-index-tree`，未发现 `.module-index` DOM；确认旧站点无需兼容后可删除。 |
| `layout.css` 的 `.module-tree-root` | `engine.py` 输出这个类，但没有对应 CSS 选择器；确认无需根节点独立样式后可去掉 DOM 类。 |
| `proof.css` 的 `.proof-reference-link` | 仅静态样例页使用；正文中的引用由另一套引用渲染与样式负责。若样例不再需要装饰性链接，可一并移除。 |
| `proof-step.css` 的 `.proof-step.unknown:hover` | 与 `.proof-step:hover` 设置相同的边框颜色，可合并；`unknown` 的背景和标签警示色仍需保留。 |
| `proof-strategy.css` 的 `.proof-strategy.remark` / `.proof-strategy.cause` | padding 与 border-left 完全相同，背景各异；可抽出共同规则，保持各自背景/图标颜色。 |
| `proof-text.css` 的 `.code-theme-dark.*` 与 `.code-*` 两组高亮选择器 | 多处颜色相同，但强限定选择器与宽泛选择器可能服务于不同的代码标记；需根据实际高亮 HTML 决定是否合并。 |
| `layout.css` 的 `--decompose-color*`、`--proof-mark-*-dark`；`references.css` 的 `--reference-control-background`；`proof-text.css` 的 `--paper-accent-soft` / `--paper-line` | 当前 CSS/JS/Python 无消费者；确认无主题扩展或外部 CSS 依赖后可移除。 |

## 后续执行与验收

1. 对上表逐项确定保留、合并或删除，以及是否需要支持外部自定义 HTML/CSS 的旧类名；按决定清理后重新生成站点。
2. 使用 `node --check` 检查 JS；在示例项目执行 `lake build PS4HTMLDemo:ps4html` 和 `ps4html make --cache`，再从仓库根目录执行 `node Test/test_theorem_site_browser.mjs` 检查真实页面、导航及静态资源。阶段验收的内部 Python 脚本已清理。
3. 在浏览器确认展开/折叠、策略着色、calc 对齐、图示缩放及缩进滑块；如有浏览器测试环境，运行 `Test/test_diagram_browser.mjs`。
