# PS4HTML 定理表述前端渲染说明

本文档说明定理表述原型的 HTML 结构、CSS 类名和与现有证明翻转组件的接入方式，供后端导出定理参数、条件和目标时参考。

示例页面：[`examples/site/theorem-statement.html`](../examples/site/theorem-statement.html)

样式文件：[`tools/ps4html/PS4HTML/assets/css/theorem-statement.css`](../tools/ps4html/PS4HTML/assets/css/theorem-statement.css)

## 一、页面位置

定理表述应放在现有 `.proof-flip-front` 内、证明步骤之前：

```html
<div class="proof-flip">
  <div class="proof-flip-inner">
    <div class="proof-flip-front">
      <!-- 定理表述：放在证明步骤上方 -->
      <div class="theorem-statement" data-language="zh">
        ...
      </div>

      <h3 class="statement-proof-divider">证明</h3>
      <div class="proof-children">
        <!-- 现有证明步骤、分支和注释 -->
      </div>
    </div>

    <div class="proof-flip-back proof-source-card">
      <!-- 现有 Lean 源代码 -->
    </div>
  </div>
</div>
```

不要把表述放在 `.proof-flip` 外部。这样点击现有源码按钮时，表述会和证明一起翻转，源码背面只显示源代码。

## 二、推荐 HTML 模板

### 1. 参数区

参数区使用一个完整的顶部容器，每个参数单独作为 `span`：

```html
<div class="theorem-statement" data-language="zh" aria-label="定理表述">
  <div class="statement-parameters">
    <i class="statement-parameter-mark" aria-hidden="true"></i>
    <span>$f\colon D_f\subseteq\mathbb R\longrightarrow\mathbb R$</span>
    <span>$a\in\mathbb R$</span>
    <span>$b\in\mathbb R$</span>
  </div>

  ...
</div>
```

`statement-parameter-mark` 当前由 CSS 隐藏，保留这个节点是为了给后续主题或无障碍增强预留位置。参数的展示文本应该是面向读者的数学表达，不要直接输出 Lean 的 binder、实例名或内部字段名。

### 2. 条件区

每个条件占满一行，按后端导出的原始顺序排列：

```html
<div class="statement-implication">
  <ul class="statement-conditions" aria-label="条件">
    <li>$a<b$</li>
    <li>$[a,b]\subseteq D_f$</li>
    <li>$f$ 在 $[a,b]$ 上连续</li>
    <li>$f$ 在 $(a,b)$ 内可导</li>
  </ul>

  ...
</div>
```

当前样式不再渲染“条件”标题。`aria-label` 可以保留给辅助技术使用，但不应把它作为可见文本重复插入。

### 3. 目标区

目标位于所有条件之后，使用单独的 `.statement-conclusion`：

```html
<div class="statement-conclusion">
  $\exists\,\xi\in(a,b),$
  $f'(\xi)=\dfrac{f(b)-f(a)}{b-a}$
</div>
```

CSS 会在目标左侧自动添加 `⊢`。因此 HTML 数据本身不要再重复输出 `⊢`，避免出现两个符号。

复杂目标可以使用多个段落，但仍应保持在同一个目标卡片中：

```html
<div class="statement-conclusion">
  <p>$\exists\,\xi\in(a,b),$</p>
  <p>$f'(\xi)=\dfrac{f(b)-f(a)}{b-a}$</p>
</div>
```

## 三、CSS 视觉约定

### 参数

- `.statement-parameters` 是顶部参数带。
- 使用浅色边框、圆角和轻微渐变，与条件卡片区分。
- 每个直接子元素 `.statement-parameters > span` 是独立参数卡片。
- hover 时只改变边框、阴影和轻微位置，不改变信息内容。

### 条件

- `.statement-conditions` 使用单列 grid，因此每个条件占满可用宽度。
- `.statement-conditions li` 是条件卡片，默认白底和细边框。
- `::before` 生成左侧圆点；hover 时圆点变为蓝色并填充浅蓝。
- hover 不使用背景色切换，主要通过边框、阴影和轻微上移反馈。

### 目标

- `.statement-conclusion` 与条件行使用相同的基础高度和内边距。
- 目标使用略强的蓝色边框和柔和阴影，表达“阅读终点”，但不使用大面积背景色。
- `::before` 自动生成 `⊢`，不需要后端额外传入符号。

### 证明标题

```html
<h3 class="statement-proof-divider">证明</h3>
```

`.statement-proof-divider` 使用左侧蓝色竖条、较大字号和淡化横线，把定理表述自然接入现有证明步骤。英文页面可输出 `Proof`，并通过页面语言或 theorem 面板的语言机制切换。

## 四、数据到展示的建议

后端最好将定理表述整理为以下逻辑结构，而不是直接让前端解析 Lean 源代码：

```json
{
  "parameters": [
    {"display": "$f\\colon D_f\\subseteq\\mathbb R\\longrightarrow\\mathbb R$"},
    {"display": "$a\\in\\mathbb R"}
  ],
  "conditions": [
    {"display": "$a<b$"},
    {"display": "$f$ 在 $[a,b]$ 上连续"}
  ],
  "conclusion": [
    "$\\exists\\,\\xi\\in(a,b),$",
    "$f'(\\xi)=\\dfrac{f(b)-f(a)}{b-a}$"
  ]
}
```

建议遵循以下规则：

1. 保留参数、条件和目标的声明顺序。
2. 显式参数、隐式参数和类型类实例先在后端归并为读者可理解的数学对象；不要把 `inst`、binder 类型或内部名称传到页面。
3. 条件中的证明假设可以去掉 Lean 名称，但不能丢失数学内容。
4. 存在量词、区间、函数性质等结构应在后端转换为自然数学语言或稳定的数学表达。
5. HTML 文本必须转义；数学公式使用站点已有的 `$...$` / `$$...$$` 分隔符，以便 `katex.js` 自动渲染。
6. 不要在数据中重复添加 `⊢`；该符号由 `.statement-conclusion::before` 统一生成。

## 五、语言和无障碍

定理表述外层使用 `data-language="zh"` 或 `data-language="en"`，用于语言相关 CSS 和已有语言切换器。数学表达仍应保留可读的文本 fallback；条件列表使用 `<ul>` / `<li>`，目标使用普通块元素，避免把整段表述做成一张不可访问的图片。

当前页面中的 `aria-label` 只用于说明区域含义，不能代替实际的可见数学内容。后端若提供可读的纯文本描述，可进一步添加 `aria-describedby`，但不应让辅助文本重复朗读所有公式。

## 六、验收清单

- [ ] 表述位于 `.proof-flip-front` 内，并在 `.proof-children` 之前。
- [ ] 点击源码翻转按钮时，表述和证明一起翻转。
- [ ] 参数位于顶部参数带中，每个参数有独立 `span`。
- [ ] 条件位于 `.statement-conditions`，每项一个 `<li>`，每项占满一行。
- [ ] 目标位于所有条件之后，只有一个 `.statement-conclusion`。
- [ ] 目标没有重复写入 `⊢`。
- [ ] 没有输出 `inst`、Lean binder 格式或仅供内部使用的假设名称。
- [ ] 公式使用 `$...$` 或 `$$...$$`，并能被站点 KaTeX 脚本识别。
- [ ] 中英文 theorem 面板的表述结构一致，只切换面向读者的文字。
