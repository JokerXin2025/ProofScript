# 表达式 hover 性能分析与回归

## 复现与根因

在 `Test.PageScriptBoard` 的实际生成页面上，用 headless Chrome / Playwright
与 Chrome DevTools CPU profiler 检查。页面渲染后有 17,125 个 DOM 元素、
2,136 个表达式 fragment、412 个 render root、2,424 个语义 occurrence。

主要阻塞链路不是高亮框绘制，而是：

1. hover 改变样式，触发后代元素的 CSS transition。
2. `transitionend` 冒泡到 `.proof-flip-inner`。
3. `code-flip.js` 无条件发出 `ps4html:layoutchange`。
4. `lean2tex.js` 对每次通知执行 `refreshIndex()`，全页重建索引。
5. 每个 fragment/occurrence 的 `hasChoices()` 都通过 `catalogsFor()` 扫描所有 render root。

一次 hover 产生了 10 次错误布局通知，加上数学尺寸组件的合并通知，共 11 次。
CPU profiler 的主要热点是 `catalogsFor`，其次是语言读取、`hasChoices` 与索引重建。
该路径具有“过渡事件数 × 表达式关联数 × render root 数”的放大效应。

另一个独立问题：当浏览器命中结果不在 render root 内时，`fragmentAt()`
遍历全页表达式并读取几何。侧栏和页面空白处移动也付出了这个代价。

## 修复后的职责

- **翻转事件**：只接收翻转容器自身的 `height` / `transform` transitionend。
- **语义索引**：初始渲染、正文 DOM 内容变化、语言/显示选项变化时更新。
  正文 MutationObserver 合并同一批 DOM 替换；普通布局通知只使几何缓存失效。
- **模板查询**：不可变 catalog 按 entity key 一次性建索引；模板可选性按语言缓存。
  occurrence 类型和字符串 HTML 资格仍在每次调用时检查，不混入共享缓存。
- **命中检测**：浏览器命中测试确定局部 render root，局部 fragment 列表缓存；
  非表达式空白立即返回，不再扫描整页。保留 KaTeX 拉伸箭头的叶子几何检测。
- **调度**：pointermove 合并到每帧一次，保持同步点击和滚轮命中检测；同一 anchor
  不重复计算语义层级。高亮绘制复用待执行帧，不先清空再重建。
- **几何失效**：滚动、resize、字体加载、布局通知、仪表盘切换及其尺寸过渡结束
  均使几何缓存失效；仪表盘过渡不会再触发全页语义索引更新。

## 实测

同一台机器、同一页面、1440×1000 viewport，30 次 pointermove，每次等待一个
animation frame。KaTeX 0.16.9 使用本地文件响应 CDN 请求，排除网络波动。

| 指标 | 修复前 | 修复后 |
| --- | ---: | ---: |
| 侧栏 30 次移动的几何 API 读取 | 11,640 | 0 |
| 空白 30 次移动的几何 API 读取 | 11,640 | 0 |
| 公式 hover 的布局通知 | 11 | 0 |
| 公式 30 次移动的脚本 CPU 时间 | 约 614 ms | 约 8.5 ms |
| 公式采样中最长帧等待 | 约 573 ms | 约 17 ms |

帧等待时间包括浏览器 vsync，不等同于单个函数耗时。这些是本机采样，不是跨设备
延迟保证。回归测试优先约束“零无关读取、零错误布局通知、零 hover 索引重建”，
避免以不稳定的毫秒阈值代替结构性保证。

## 回归命令

```sh
lake build +Test.PageScriptBoard:ps4html
node scripts/test-expression-highlight.mjs
node scripts/test-code-flip-events.mjs
node scripts/test-template-long-press.mjs
node scripts/test-proof-dashboard-interaction.mjs
node scripts/test-expression-performance.mjs
```

最后一项需要 Playwright 和 Chrome；可用 `PLAYWRIGHT_MODULE` 指向外部安装的
Playwright `index.mjs`，用 `KATEX_DIST` 指向本地 KaTeX 0.16.9 的 `dist/`。
浏览器测试使用实际鼠标事件并等待 CSS 过渡完成，也检查高亮、点击固定详情和
仪表盘键盘展开/收起。已有几何测试覆盖高箭头、异常 SVG 原点、跨片段合并、
关联高亮及折叠仪表盘；新增覆盖空白命中、pointermove 合并和布局/语义索引隔离。

此次没有将大页面初次 KaTeX 排版、所有折叠内容的初次渲染或超大单公式的几何遍历
作为优化对象；如后续扩大页面规模，应分别采样，不能将本次 hover 数据视为这些
路径的性能结论。
