import ProofScript.Info.Decl.Commands
import Mathlib


/-!
# 声明模版配置 `template%` 语法指南

`template%` 是 `decl_info` 的配置字面量，由配置解码器读取。配置影响
ProofScript 的展示，不改变 Lean 的定义、记号、化简和证明行为。
-/

/-!
## 1. 最小配置：一个没有参数的数学对象

`template% ${ ... }$` 的外层模式是公式；`template% { ... }` 的外层模式是文本。
下例将自然数类型显示为 ℕ，不需要任何参数选择器。

`:100` 是整个模板的展示优先级，原子式数学符号通常适合最高优先级 100。
普通 Lean 字符串中的反斜线需要转义，所以 LaTeX 的 `\mathbb` 写成 `"\\mathbb"`。
-/

decl_info templates Nat + [{
  label := "formula", content :=
  template%:100 ${ "\\mathbb{N}" }$
}]


/-!
## 2. `arg(n)`：按显式参数编号插入表达式

编号从 0 开始，默认只数声明的显式参数，跳过隐式参数和实例参数。
例如 `Eq` 的形状为 `{α : Sort u} → α → α → Prop`：
`arg(0)` 是等号左边，`arg(1)` 是等号右边，不是类型 `α`。
如需使用隐式参数和实例参数请见第六章。

源码中片段之间的空格、换行不进入输出；需要输出的空格应写进字符串。
选择器可以重复、重排，也可以不引用某些参数，但不能引用不存在的编号。
忽略一个参数不等于忽略它在 Lean 中的数学意义，应确保展示没有歧义。

下面三种写法分别展示等式、交换左右顺序的文字描述，以及重复引用左端的描述。
每种语言下，同一个 `(label, lang)` 身份只能出现一次。
-/

decl_info templates Eq + [{
  label := "formula", content :=
  template%:50 ${ arg(0) " = " arg(1) }$
}, {
  label := "reverse", lang := zh, content :=
  template% { $ arg(1) $ "等于" $ arg(0) $ }
}, {
  label := "repeat", lang := zh, content :=
  template% { $ arg(0) $ "与" $ arg(1) $ "相等；左端是" $ arg(0) $ }
}]


/-!
## 3. 文本、公式及局部模式切换

外层文本模板中的 `$ ... $` 临时切换到公式；
外层公式模板中的 `$ ... $`临时切换到文本。
切换结束后回到外层模式。切换片段必须非空、成对闭合，不能嵌套。

`Set.Icc a b` 表示闭区间 `{x | a ≤ x ∧ x ≤ b}`，其显式参数就是两个端点。

注意：字符串内容中不应出现美元符号，即使写成 Lean 原始字符串也一样。
不要写 `"$...$"`；应使用字符串外的 `$ ... $`。
-/

decl_info templates Set.Icc + [{
  label := "formula", content :=
  template%:100 ${ "[" arg!(0) ", " arg!(1) "]" }$
}, {
  label := "description", lang := zh, content :=
  template% { "从" $ arg(0) $ "到" $ arg(1) $ "的闭区间" }
}, {
  label := "description", lang := en, content :=
  template% { "the closed interval from " $ arg(0) $ " to " $ arg(1) $ }
}]


/-!
## 4. 优先级与自动括号

`template%` 后可选的 `:数字` 用于表示模版优先级。
优先级只能是 0 到 100 的自然数字面量；此字段未提供时默认采用 60。
这个数字是展示优先级，不是 Lean parser 的记号优先级。

数值越大，绑定越紧。常见选择为：关系 50，加法 65，乘法 70，幂 80，
函数调用 90，原子或自带完整分组的表达式 100。这些是配置习惯，不是语法限制。
子表达式优先级较低时需要括号；普通模板在同级时也保守保留括号。
因此，自定义 label 下的 `arg(0) "+" arg(1)` 不会自动获得左结合性。
如需设定左右结合性，可将 `label` 设定为 `"$infixl"` 或 `"$infixr"`。

`(a + b) * c` 中的加法比乘法优先级低，展示时将保留必要分组。
-/

decl_info templates HAdd.hAdd + [{
  label := "formula", content :=
  template%:65 ${ arg(0) " + " arg(1) }$
}]

decl_info templates HMul.hMul + [{
  label := "formula", content :=
  template%:70 ${ arg(0) " \\cdot " arg(1) }$
}]


/-!
## 5. `arg!`：子表达式强制最高优先级

变体 `arg!` 表示在插入该子表达式时假定最大优先级，从而始终不会添加括号。
即使父子优先级都为 100，`arg!` 也不会自动加括号。

适合使用 `!` 变体的位置包括：分式的分子、分母，根号内部，以及已经分组的指数。
例如 `(a + b) / (c + d)` 的分子和分母已由 `\\frac{...}{...}` 包住，
如果模版中已经包含括号，应使用 `!` 变体来避免被重复添加括号。

-/

decl_info templates HDiv.hDiv + [{
  label := "fraction", content :=
  template%:70 ${ r"\frac{" arg!(0) "}{" arg!(1) "}" }$
}]

decl_info templates HPow.hPow + [{
  label := "power", content :=
  template%:80 ${ "{" arg(0) "}^{" arg!(1) "}" }$
}]

decl_info templates Real.sqrt + [{
  label := "root", content :=
  template%:100 ${ r"\sqrt{" arg!(0) "}" }$
}]


/-!
## 6. `raw`：使用全部原始参数的编号

`raw` 改变该模板的参数编号方式：隐式、严格隐式、实例参数都占位置。

以笛卡尔积的有序对构造器 `Prod.mk` 为例：

    默认编号：arg(0) = 第一个分量，arg(1) = 第二个分量。
    raw 编号：arg(0) = α，arg(1) = β，arg(2) = 第一个分量，arg(3) = 第二个分量。

下面同一个声明的两个模板分别使用这两种编号方式。
`typed` 用下标标出所属类型。例如自然数对的类型是 `ℕ × ℕ`。
写 raw 模板前，可以用 `#check @Prod.mk` 查看参数顺序；实例参数也必须计数。
-/

decl_info templates Prod.mk + [{
  label := "pair", content :=
  template%:100 ${ "(" arg!(0) ", " arg!(1) ")" }$
}, {
  label := "typed", content :=
  template%:100 raw ${ "(" arg!(2) ", " arg!(3) ")_{" arg!(0) r"\times " arg!(1) "}" }$
}]


/-!
## 7. `binder(m, n)` 与 `body(m, n)`：展示 lambda 参数

这两个选择器用于“参数本身是一个函数表达式”的情形，从而支持在模版中添加与子表达式一致的 binder：

* `binder(m, n)` 取参数 m 的第 n 层 lambda 的绑定变量。
* `body(m, n)` 去掉前 n 层连续 lambda，取剩余正文（可能仍然是 lambda 函数）。
* 可使用 `binder!` 和 `body!` 变体，规则和 `arg!` 相同。

例如参数为 `fun x => fun y => x + y` 时，第一层 binder 是 x，第二层是 y；
深度 1 的 body 是 `fun y => x + y`，深度 2 的 body 是 `x + y`。
绑定变量的最终显示名由渲染器处理，应使用 binder 选择器而不是硬编码 `"x"`。

模板要求的最少 lambda 层数，由该参数全部 binder/body 引用的最大深度决定。
语法接受一个层号，不等于应用时的参数一定具备这些 lambda 层；层数不足时渲染器将回退其他模版。

### 7.1 有限求和

`Finset.sum` 的显式参数 0 是有限集合，参数 1 是求和函数。
对 `Finset.sum s (fun i => i + 1)`，可用 `binder(1, 1)` 取 i，
用 `body(1, 1)` 取 `i + 1`。下标已经分组，因此使用 `binder!` 和 `arg!`；
求和正文保留普通 `body`，让它按优先级处理括号。
-/

decl_info templates Finset.sum + [{
  label := "sum", content :=
  template%:60 ${ r"\sum_{" binder!(1, 1) r"\in " arg!(0) "} " body(1, 1) }$
}, {
  label := "call", content :=
  template%:90 ${ r"\operatorname{sum}(" arg!(0) ", " arg!(1) ")" }$
}]

/-!
### 7.2 集合描述式

`setOf (fun x => P x)` 的唯一显式参数是谓词。
模板可把 lambda 展开成 `{x | P x}`；整个集合表达式由花括号包围。
这里 `body!` 对已处于集合定界符内部的谓词关闭额外括号。
-/

decl_info templates setOf + [{
  label := "set-builder", content :=
  template%:100 ${ r"\{" binder!(0, 1) r"\mid " body!(0, 1) r"\}" }$
}]
