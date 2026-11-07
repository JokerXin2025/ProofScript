# 内置表达式样式：第一阶段契约

此文档固定内置样式身份和行为，供 Python 初次渲染、浏览器重排和 URL 状态共用。字符串字面量在安全的线性位置提供 HTML 样式。常量键 `["constant", "Lean声明名"]` 和现有 `ps4html-templates` URL 参数保持兼容。下列键统一使用 `RenderTarget("builtin", key).as_key()` 的 JSON 字符串形式；浏览器按完整字符串匹配，不从显示文字推断键。

| 键 `["builtin", key]` | 默认 label | 其他 label | 输入 / 停止条件 |
| --- | --- | --- | --- |
| `lambda` | `mapsto` | `fun`, `typed` | 连续 lambda 的 binder、类型及末尾正文；遇非 lambda 停止。 |
| `application` | `call` | `juxtaposed` | 仅转换后确属通用 application 的头及已有参数；常量宏匹配成功和 wrapper 解包不走此键。 |
| `forall.dependent` | `phrase` | `symbol` | 每层均引用其自身 binder 的连续 forall；依赖性变化时停止。 |
| `forall.arrow` | `implies` | `arrow` | 每层均不引用其自身 binder 的连续 forall；依赖性变化时停止。 |
| `let` | `where` | `inline`, `stacked` | 连续 let 的 binder、值及末尾正文；遇非 let 停止。`where` 先显示正文，再列出“其中/where”与各条定义；`stacked` 用 TeX `aligned` 将各条定义与正文分行展示。 |
| `sort.level.zero` | `prop` | `sort` | `.zero`，即 `Prop`。 |
| `sort.level.succ` | `compact` | `structural` | 最外层 `.succ`；完整 level 树作为数据。 |
| `sort.level.max` | `compact` | `structural` | 最外层 `.max`；完整 level 树作为数据。 |
| `sort.level.imax` | `compact` | `structural` | 最外层 `.imax`；完整 level 树作为数据。 |
| `sort.level.param` | `compact` | `structural` | 最外层 `.param`；完整 level 树作为数据。 |
| `sort.level.mvar` | `compact` | `structural` | 最外层 `.mvar`；完整 level 树作为数据；不同于表达式 `metavariable`。 |
| `metavariable` | `question` | `unknown` | 固定 `?` / `未知` 文案；不插入元变量 ID。 |
| `literal.nat` | `decimal` | `chinese-simplified`, `chinese-traditional`, `greek-ionian`, `roman` | 非负整数原值；样式是转换程序，不是逐位替换模板。 |
| `literal.str` | `plain` | `strong`, `code` | 安全 HTML 文本节点，分别用受控的 `span`、`strong`、`code` 标签。 |

## 链、作用域和括号

原生 `mdata` 在语义转换时已经并入 occurrence，不影响识别链；若 body 经过一个仍保有独立 occurrence 的透明展示 wrapper，则本阶段在 wrapper 处中断链，以免吞掉交互范围。内层节点和绑定身份都保留。连续 lambda 和 let 沿 body 收集；连续 forall 逐层用现有 `isArrow` 分类，**只有相同分类才合并**。例如 `dependent → arrow → dependent` 是三段；下一段是上一段的正文。let 的后续值仍处在之前 binder 的作用域内。样式函数分别接收有序条目和最终正文，而不是拼接后再反解析的 TeX。链内层 occurrence 会保留独立片段；菜单预览从整条链的头部开始。`let.stacked` 的内层 let 片段目前锚定在对应声明行，而不是完整后缀。

符号运算符采用冻结的 `decl_info.operator_info` 优先级与结合性；内置 application、binder 等使用同一布局标度的固定优先级并按父子关系加括号。原生 `Expr` 不提供 parser 源码的运算符优先级。`juxtaposed` 也必须保护复合函数头和参数；其选择不得改变“是否匹配常量宏”的判定。

## 数字体系与范围

数字转换以**规范化十进制数字串**为输入（`0` 或首位非零的非空 ASCII 数字串），不经 JavaScript `Number`。Python 负责转换算法；页面只序列化实际出现的字面量的候选显示结果供浏览器切换，避免双端算法分歧。以字符串长度和字典序比较范围。输出长度仍受现有页面/TeX 资源限额约束，不设整数类型上限。当前录制格式的 `literal.nat.value` 是 JSON 数字；证明读取使用分块整型解析，转展示树时再分块转为十进制字符串；浏览器只接收该字符串及 Python 预计算的显示结果，不以 JS `Number` 重读原数字。录制 wire 格式保持不变。

| label | 计数体系与确定范围 | 零 | 超范围 |
| --- | --- | --- | --- |
| `decimal` | 十进制原值；没有记法上限 | `0` | 不适用 |
| `chinese-simplified` | 简体汉字**计数读法**，`102 → 一百零二`；每四位一组，最高组单位为 `载`（10⁴⁴），覆盖 `0 … 10⁴⁸−1` | `零` | `>` 后接 `10⁴⁸−1` 的完整简体写法 |
| `chinese-traditional` | 繁体汉字计数读法，同样采用万进分组、最高组单位 `載`，覆盖 `0 … 10⁴⁸−1` | `零` | `>` 后接 `10⁴⁸−1` 的完整繁体写法 |
| `greek-ionian` | 希腊爱奥尼亚数字：个位、十位、百位使用各自字母，千位使用左下千位记号 `͵`，末尾使用数字记号 `ʹ`；范围 `1 … 9999` | 非历史数字记号的文字 `μηδέν` | `>` 后接 `9999` 的爱奥尼亚记法，即 `͵θϡϟθʹ` |
| `roman` | 标准减法记法（IV、IX、XL、XC、CD、CM）；范围 `1 … 3999` | 非古典罗马数字的 `N` | `>` 后接 `3999` 的罗马记法 `MMMCMXCIX` |

汉字组单位固定为 `万/萬、亿/億、兆、京、垓、秭、穰、沟/溝、涧/澗、正、载/載`，依次表示 10⁴ 至 10⁴⁴；组内使用十、百、千，按组间/组内缺位补零；最高有效组以十开头时省去「一」，例如 `100000 → 十万`，非最高组保留「一」，例如 `10010 → 一万零一十`。最高单位以上不再拓展。简体 `二`、繁体 `二`，不自动替换成口语 `两/兩`。爱奥尼亚记法采用 ϛ（6）、ϟ（90）、ϡ（900）等字母数字，千位记号在千数字母前；十进制零使用上述明确的文字回退。上述上限是**样式定义**，不是输入长度限制。

sort 的 `compact/structural` 分别强调简洁阅读与原生 `Sort` 层级：`.zero` 是 `Prop` 或 `Sort 0`；`.succ u` 是 `Type u` 或 `Sort (u+1)`；`.max/.imax` 的简洁式使用 `Type ?`，结构式展示 `max/imax` 两个操作数；`.param` 与 `.mvar` 的结构式保留经过 TeX 转义的参数/元变量名。表达式 `metavariable` 的 `unknown` 样式只显示固定「未知」，不泄露 ID。

## 公式文本与字符串边界

当前混合布局在有交互根的文本环境中对顶层字符串和直接插入简单 `#N` 线性公式模板的字符串开放：排版器以固定字形和十六进制 Unicode 标量编码的片段标记保留原文，页面边界将其拆为数学—HTML—数学片段并转义／建立受控标签。各数学段仍携带父表达式 occurrence，浏览器重排后也能悬停。仅在所选常量模板与同语言的其他 label 均不会改变线性布局时开放该类子项；分式、上下标、通用应用括号、文字模板及公式环境中的字符串尚无能保留布局的混合容器，菜单按 occurrence 禁用 HTML 字体切换，并保持原有文本排版。不能无损拆出的场合不得静默切换成其他字体。任意用户 TeX 中的 `\text{…}` 不是 Lean `literal.str`，不获得字符串字面量的键。

同一输入在 Python 初次渲染和浏览器切换后应有一致的可见结果；常量模板、别名、wrapper、关系与变量联动不因新增内置键而改变。URL 的字符串选择只影响标记为 `htmlEligible` 的出现位置；其他出现位置维持原样。未来扩展嵌套混合容器时需同步更新 Python 与浏览器的适用性判断。
