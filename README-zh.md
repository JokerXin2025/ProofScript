# ProofScript

ProofScript 是一个面向 [Lean 4](https://lean-lang.org/) 的编译期语言扩展.
它提供一套结构化、可扩展且语义增强的证明 DSL, 将 Lean 证明的实时目标、策略参数和分支结构录制并导出为 JSON,
同时, ProofScript 还集成了 ProofText 正文、定理表述、图片、LaTeX SVG 等页面组件, 这些数据将被自动编译并导出为 JSON, 供渲染器或其他下游工具消费.

ProofScript 内置 PS4HTML 站点工具，源码位于 [`tools/ps4html/`](tools/ps4html/)，无需另行下载 PS4HTML 仓库。
在仓库根目录安装（Python 3.11+，建议使用虚拟环境）：

```sh
python3 -m pip install -e ./tools/ps4html
```

在用户 Lean 项目中配置 ProofScript 依赖、执行 `lake update` 后，运行 `lake build MyLibrary:ps4html`（将 `MyLibrary` 替换为实际库名），输出为
`.PS4HTML/build/index.html`；`ps4html serve` 提供本地预览。完整示例位于 [`examples/site/`](examples/site/)，
其中计算页面另需 Node、Emscripten 和匹配的 Lean/Wasm runtime。
统一 Info 导出协议为 `4.0.0`，录制协议保持 `0.0.0`。每个 script 步骤对应一个对象，目标快照作为普通字段写入；配置及实际契约通过产物清单关联。旧缓存需重新运行 Lake facet 构建，详见[统一配置与导出说明](#统一-info-配置)。
详细使用说明见 [PS4HTML 文档](tools/ps4html/README.md)。

## 目录

- [快速开始](#快速开始)
- [形式化证明](#形式化证明)
- [ProofText](#prooftext)
- [自动文献管理系统](#自动文献管理系统)
- [其它页面组件](#其它页面组件)
- [统一 Info 配置](#统一-info-配置)
- [页面导出](#页面导出)
- [环境要求](#环境要求)
- [当前限制](#当前限制)
- [相关文档](#相关文档)
- [PS4HTML 站点生成器](#ps4html-站点生成器)

## 快速开始

在 `lakefile.toml` 中添加 ProofScript 作为依赖并执行 `lake update` 后, 即可在 Lean 项目中使用.

```lean
import ProofScript

project_info {
  title := "An Example Formal Paper",
  authors := ["Alice", "Bob"],
  description := "A small demonstration of ProofScript.",
  keywords := ["Lean", "formal proof", "structured proof"],
  year := "2026"
}

@text r#"
= Introduction <introduction>

This page contains a recorded theorem. See @thm:mainResult.
"#

@theorem mainResult (P : Prop) (h : P) : P := script
  assumption

theorem_info mainResult {name := "Main Result"}

@references

page_end
```

假设上述 Lean 文件为 `./Project/Module/Page.lean` , 则编译后证明和页面信息将分别导出至:

```text
./.ProofScript/pages/Project/Module/Page.json
./.ProofScript/proofs/Project/Module/Page/mainResult.json
```


## 形式化证明

### 脚本模式

ProofScript 中引入了由 `:= script` 引导的脚本模式来代替策略模式. 在 `:= script` 中，用户应使用不带前缀的脚本策略名；框架会自动将其改写为内部执行入口 `script_<name>`，录制时使用 `_script_<name>`. 其在语法上和策略模式一致 （并且实际上正是基于策略模式构建）, 脚本模式大致包含以下三类基本元素:

1. 步骤: `intro`、`apply` 等作为形式化证明中的逻辑单元, 它们相比一般的 Lean 策略具有更强的语义性.
2. 概略: `split_and`、`contra`、`induction` 等在宏观上确定了证明的结构, 并且具有统一的语法形式.
3. 元数据: `remark`、`latex` 等可在证明脚本嵌入解释性文本或图表等元数据.

以上三类元素可以统称为脚本策略. 这种约束使证明脚本更适合稳定地映射为自然语言或交互式展示, 同时兼备 Lean 形式化验证能力, 下面的代码提供了一个完整示例.

```lean
theorem implicationChain
    (P Q R : Prop) (hPQ : P → Q) (hQR : Q → R) : P → R := script
  intro hP
  infer
    P => Q := hPQ hP
    => R := hQR ?_
```

### ProofScript 内置脚本策略

#### 步骤

##### Lean 原生策略

核心模块包装了下列 Lean 策略。这里只支持列出的简化语法：

| 策略 | 作用 |
| :- | :- |
| `assumption` | 使用上下文中的匹配假设闭合目标 |
| `change t` | 将目标改写为定义等价的 `t` |
| `contradiction` | 从上下文矛盾闭合目标 |
| `exfalso` | 将当前命题目标改为 `False` |
| `omega` | 求解 Presburger 算术目标 |
| `rfl` | 用自反性闭合目标 |
| `simp only [l₁ l₂ ...]` / `simp only [l₁ l₂ ...] at h₁ h₂` / `simp only [l₁ l₂ ...] at *` / `simp only [l₁ l₂ ...] at ⊢` | 只使用空白分隔的指定标识符进行化简，可作用于指定假设、全部假设或目标 |
| `symm` | 交换对称关系两侧 |
| `trivial` | 求解简单目标 |
| `rw [h₁ h₂ ...]` / `rw [← h₁ h₂ ...]`，可加 `at h₁ h₂`、`at *` 或 `at ⊢` | 使用等式重写，并随后尝试原生 `rfl` |
| `unfold d₁ d₂ ...` | 展开一个或多个空白分隔的定义 |

##### 专属脚本策略

| 策略 | 作用 | 对应原生策略 | 限制 |
| :- | :- | :- |
| `intro x₁ ... xₙ` | 依次引入证明项或普通变量 | `intro` | 至少一个标识符；目标为 `… → False` 时仍需使用 `contra` |
| `provide ⟨h⟩` | 在 `witness.data` 中提供见证，或为存在目标提供见证 | `exact` / `exists` | 不是一般的 `exact`，只能用于这两种上下文 |
| `apply t` | 应用形如 `P → Q` 或 `P ↔ Q` 的命题，留下一个前提目标 | `apply` / `Iff.mp` / `Iff.mpr` | 最外层必须是蕴含或等价，且只能产生一个目标 |
| `funext x` | 将函数等式化为逐点等式 | `funext` | 等式两侧必须是同定义域函数 |
| `obtain_exist ⟨x, hx⟩ := h` | 解构局部存在性假设 | `cases` | `h` 必须证明存在命题 |
| `left` / `right` | 选择析取目标的左侧或右侧 | `apply Or.inl/inr` | 当前目标必须是析取命题 |
| `quot_induction q with a` | 商类型归纳 | `induction` |
| `unpack_and ⟨h₁, h₂⟩ := h` | 解构局部合取假设 | `cases` | `h` 必须证明合取命题 |
| `unpack_iff ⟨h₁, h₂⟩ := h` | 解构局部等价假设 | `cases` | `h` 必须证明等价命题 |

`apply` 接受一个最外层为蕴含或等价命题的项。它只应用最外层蕴含，因此 `P → Q → R` 只产生一个 `P` 目标，并保留剩余的蕴含结论。对于等价命题，它会根据当前目标选择对应的方向：

```lean
theorem compose (P Q R : Prop) (hPQ : P → Q) (hQR : Q → R) (hP : P) : R := script
  apply hQR
  apply hPQ
  assumption
```

#### 概略

概略策略将目标拆分为若干带有**语义化命名**的分支, 从而在宏观上确定证明的框架.
概略产生的目标分支可以使用 `| case => …` 或匿名分支 `·`，两者可以嵌套、混用。匿名分支聚焦下一个未完成目标，必须在分支内关闭该目标；录制时保留目标的语义标签（如 `left` / `right`），标签有歧义时需显式命名。`claim` 的第一个匿名分支证明 `proof`，之后的步骤或第二个匿名分支在包含新假设的上下文中继续证明。

当前概略和结构策略包括：

| 策略 | 作用或分支 |
| :- | :- |
| `claim h : P` | 产生后续目标和名为 `proof` 的断言证明目标 |
| `have h := t` | 行为与原生 `have` 一致；但 `t` 所使用的顶层函数类型不能包含命题类型参数 |
| `exact t` | 行为与原生 `exact` 一致；但 `t` 所使用的顶层函数类型不能包含命题类型参数 |
| `witness` | 存在性构造，产生 `data`、`proof` |
| `split_and` | 二元合取，产生 `left`、`right` |
| `split_and!` | 递归合取，产生 `goalI`、`goalII` 等 |
| `split_iff` | 等价证明，产生 `suffice`、`necess` |
| `cases_by h` | 对局部析取假设分类，产生 `left`、`right` |
| `cases_by! h` | 递归拆解局部析取，产生 `goalI`、`goalII` 等 |
| `cases_on t` | 对命题真假或数据构造子分类 |
| `contra h` | 反证，产生 `proof` |
| `induction n` | 自然数归纳 |
| `complete_induction n` | 自然数强归纳 |
| `constructor` | 应用目标归纳类型的默认构造器，并按构造器字段命名分支 |
| `constructor! c` | 显式应用指定的构造器 `c`，并按构造器字段命名分支 |

##### 存在性构造

`witness` 作用于形如 `∃ x, P x` 的存在性命题, 并将其拆分为两个分支:

- `data` : 构造符合条件的对象
- `proof` : 证明该对象满足 `P`

```lean
theorem demo_witness : ∃ n : Nat, n = 0 := script
  witness
  | data => provide 0
  | proof => trivial
```

`provide` 也可以直接构造存在命题，不必使用 `witness` 的两个分支；它不能作为一般的 `exact` 步骤使用:

```lean
theorem provide_witness : ∃ n : Nat, n = 0 := script
  provide 0
  rfl
```

##### 目标拆解 —— 合取

`split_and` 作用于形如 `P ∧ Q` 的合取命题, 并将其拆分为两个分支:

- `left` : 左分支
- `right` : 右分支

`split_and!` 会递归地拆解形如 `P₁ ∧ P₂ ∧ ... ∧ Pₙ` 的合取命题, 并将其拆分为分支 `goalI` , `goalII` 等.

```lean
variable {P Q R : Prop}
theorem demo_split_and (hP : P) (hQ : Q) : P ∧ Q := script
  split_and
  | left => assumption
  | right => assumption
theorem nestedAnd (hP : P) (hQ : Q) (hR : R) : P ∧ Q ∧ R := script
  split_and!
  | goalI => assumption
  | goalII => assumption
  | goalIII => assumption
```

##### 目标拆解 —— 等价

`split_iff` 作用于形如 `P ↔ Q` 的等价命题, 并将其拆分为两个分支:

- `suffice` : 充分性, 即 `P → Q`
- `necess` : 必要性, 即 `Q → P`

```lean
variable {P Q : Prop}
theorem demo_split_iff (hPQ : P → Q) (hQP : Q → P) : P ↔ Q := script
  split_iff
  | suffice h₁ =>
    apply hPQ
    assumption
  | necess h₂ =>
    apply hQP
    assumption
```

##### 反证法

在脚本模式中, `contra h` 可以:

1. 作用于形如 `¬ P` 的否定命题, 并产生一个分支 `proof` , 该分支中引入了 `P` 作为假设
2. 作用于其它命题, 并产生一个分支 `proof` , 该分支中引入了 `¬ P` 作为假设

在 `proof` 分支中, 目标被修改为 `False` , 即通过导出矛盾来完成证明.

```lean
theorem demo_by_contra_pos (P : Prop) (h : ¬ P → False) : P := script
  contra hnp
  | proof =>
    apply h
    assumption
theorem demo_by_contra_neg (P : Prop) : ¬ (P ∧ ¬ P) := script
  contra h
  | proof =>
    unpack_and ⟨hP, hNP⟩ := h
    apply hNP
    assumption
```

##### 数学归纳法

在脚本模式中, `induction n` 对自然数 `n` 作数学归纳, 并产生 `zero` / `succ k ih` 两个分支:

```lean
theorem demo_induction (n : Nat) : n + 0 = n := script
  induction n
  | zero => rfl
  | succ k ih => rfl
```

##### 强（完全）归纳法

`complete_induction n` 对自然数 `n` 作强归纳, 同样产生 `zero` / `succ k ih` 两个分支, 但 `succ` 分支的归纳假设 `ih : ∀ m < k + 1, P m` 覆盖所有更小的自然数:

```lean
theorem demo_complete_induction (n : Nat) : n + 0 = n := script
  complete_induction n
  | zero => rfl
  | succ k ih => rfl
```

##### 分类讨论 `cases_on`

`cases_on p` 对命题 `p` 按真假分类讨论, 产生 `true h` (`h : p`) 与 `false h` (`h : ¬p`) 两个分支:

```lean
theorem demo_cases_on (n : Nat) : n = 0 ∨ n ≠ 0 := script
  cases_on (n = 0)
  | true h =>
    left
    assumption
  | false h =>
    right
    assumption
```

##### 任意构造器

`constructor` 应用目标归纳类型的默认构造器；`constructor! c` 显式应用指定的构造器 `c`。
两者都会使用构造器字段名为产生的分支命名。对于 `∧`、`↔`、`∃` 和 `∨`，这两个策略会被
刻意拒绝；请分别使用 `split_and`、`split_iff`、`witness` 或 `left`/`right`。

```lean
inductive TwoPremises (P Q : Prop) : Prop where
  | first (left : P) (right : Q)
  | second (value : P)

example (P Q : Prop) (hP : P) (hQ : Q) : TwoPremises P Q := script
  constructor
  | left => assumption
  | right => assumption

example (P Q : Prop) (hP : P) : TwoPremises P Q := script
  constructor! TwoPremises.second
  | value => assumption
```

#### 元数据

核心模块提供以下元数据策略：

| 策略 | 作用 |
| :- | :- |
| `remark "text"` | 插入自然语言注解 |
| `svg "code"` | 插入原始 SVG 元数据 |
| `latex (title := "...", ...) "source"` | 编译并记录任意 LaTeX 源码及 SVG |
| `admit "reason"` | 使用 `sorry` 暂时闭合目标并记录原因 |
| `cite theorem` | 记录带有 `theorem_info` 的定理引用，不改变当前目标 |

##### 非正式证明

使用 `admit` 策略可以使用一段自然语言作为未形式化证明, 其使用 `sorry` 来临时填补证明, 例如:

```lean
theorem draft (P : Prop) : P := script
  admit "This result has not been formalized yet."
```

如需项形式，可使用普通项宏 `admit`，例如 `:= admit "尚未形式化"`；它不是可直接执行的脚本策略名。

##### 注解

使用 `remark` 策略可以插入一段自然语言注解, 从而帮助阅读者更好地理解证明中的某个部分, 例如:

```lean
@theorem demo_remark {P : Prop} (h_P : P) : P := script
  remark "这是一则简单的证明"
  assumption
```

##### LaTeX (SVG)

证明内部提供统一的 `latex` 元数据策略. 它与页面组件 `@latex` 一样接收 metadata 和任意
LaTeX 源码，在录制时调用本地 LaTeX 工具链生成 SVG，并把 metadata、源码和 SVG 一同写入
证明树。例如:

```lean
@theorem proofWithDiagram (P : Prop) (h : P) : P := script
  latex (title := "推导图", label := "proof-diagram") r#"
    \begin{tikzpicture}
      \draw[->] (0,0) -- (1,0);
    \end{tikzpicture}
  "#
  assumption
```

为了保证预编译器顺利工作，请确保 TeXLive 已本地安装。这里是证明内部策略；页面级任意
LaTeX 使用后文的 `@latex` 命令。

#### 连续计算 `calc`

ProofScript 将 `calc` 计算块包装为脚本策略，所以可以在脚本模式下使用.

#### 连续推导 `infer`

众所周知, `calc` 计算块可以很大程度上简化传递性关系的连续计算过程, 而连续推导 `infer` 则以类似的语法实现一般的连续推导过程简化, 例如:

```lean
theorem divisibility_chain {a b c d e : ℕ}
    (h_ab : a ∣ b) (h_bc : b ∣ c)
    (h_pos : 0 < c * d * e)
  : a ≤ c * d * e
:= script
  remark "这里我们通过整除性来证明不等式"
  infer
    (a ∣ b) => (a ∣ c)
                := dvd_trans h_ab h_bc
            => (a ∣ c * d)
                := dvd_mul_of_dvd_left ?_ d
            => (a ∣ c * d * e)
                := dvd_mul_of_dvd_left ?_ e
            => (a ≤ c * d * e)
                := Nat.le_of_dvd h_pos ?_
```

只有首步写出初始命题：`P => Q := ...`。后续步骤直接以 `=>` 开头，例如 `=> R := ...`，其前提自动取上一步的结论。Unicode 箭头 `⇒` 的用法相同。

每一步通过 `have` 添加结论。对于普通证明项，首步不能使用 `?_`，且必须使用初始命题的证明；后续每一步必须有且仅有一个 `?_`，直接替换为上一步结论的证明。

每一步也可以使用 `:= by ...`。在后续步骤中，`this` 表示上一步结论的证明，因此 `=> R := by exact hQR this` 不需要占位符。策略证明可以自行使用并解决证明空洞；首步仍须使用初始命题的证明。

结论可以选择命名，例如先写 `P => hQ : Q := hPQ hP`，再写 `=> hR : R := by exact hQR this`。这些名称可用于后续步骤；当 `infer` 作为策略使用时，也可用于其后的策略。

`infer` 可以

- 作为中间步骤使用，将所有新结论添加到上下文中（未命名时为匿名，类似 `claim`）.
- 作为终结策略闭合目标.
- 直接作为项使用（即写作 `:= infer`）；这里的 `infer` 是普通项宏，而不是无前缀的可执行脚本策略.

### Mathlib 脚本策略

`import ProofScript` 通过 `ProofScript.Mathlib.Info` 加载 Mathlib 策略及其展示配置。只需 tactic 实现与注册时可以导入：

```lean
import ProofScript.Mathlib.Scripts
```

基础策略的 `ProofScript.Script.Basic` 提供执行与注册，`ProofScript.Defaults.Script` 另加载展示配置；公共 `ProofScript` 入口加载全部默认配置。模块职责见[统一 Info 配置](#统一-info-配置)。当前包装按字母顺序包括：

| 策略 | 支持的简化形式 |
| :- | :- |
| `script_continuity` | 默认形式 |
| `script_exact_mod_cast` | `script_exact_mod_cast proof` |
| `script_field` | 默认、`script_field [lemmas...]` |
| `script_gcongr` | 默认、pattern、`with names...` 及两者组合 |
| `script_itaotu` / `script_itauto` | 默认、`*`、命题列表及 `!` 变体 |
| `linarith` | 默认、事实列表、`only` 及 `!` 变体 |
| `script_measurability` | 默认形式 |
| `script_nlinarith` | 默认、事实列表、`only` 及 `!` 变体 |
| `script_norm_cast` | 默认及 `at` 形式 |
| `norm_num` | 默认、lemma 列表、`only` 及对应 `at` 形式 |
| `script_positivity` | 默认、事实列表 |
| `script_push_cast` | 默认、lemma 列表、`only` 及对应 `at` 形式 |
| `qify` / `rify` / `zify` | 默认、lemma 列表及对应 `at` 形式 |
| `script_ring` | `script_ring`、`script_ring!` |
| `script_ring_nf` | 默认、`!` 及对应 `at` 形式 |
| `script_tauto` | 默认形式 |
| `script_wlog` | 默认、`generalizing`、`with`、两者组合及 `script_wlog!` |

为保持参数可稳定录制，包装只使用 `ident`、`term` 等基础类别。方括号中的参数使用空白分隔：

```lean
linarith [h₁ h₂]
qify [hab] at h ⊢
norm_num only [Nat.add_zero Nat.zero_add] at *
```

支持位置参数的策略可使用 `at h`、`at h₁ h₂`、`at *`、`at ⊢` 和
`at h₁ h₂ ⊢`。配置对象、自定义 discharger、任意 tactic block 以及仅输出建议的 `?`
变体没有包装。支持的语法参见 [Mathlib 策略定义](ProofScript/Mathlib/Scripts.lean)。

### 自定义脚本策略

使用 `script_macro <id>` / `script_elab <id>` 创建脚本策略。ID 必填，在定义模块内唯一，与策略起始关键字分开。用户在 `:= script` 中仍写无前缀的策略关键字，框架会自动改写到执行入口 `script_<关键字>`，录制时再改写到 `_script_<关键字>`；无前缀关键字不会成为普通 `:= by` 中可执行的策略。这些命令使用 tactic 语法，因此不需要 `: tactic` 后缀；需要提供项版本时，可使用普通 `macro` 将它包装为 `script` 证明。例如：

```lean
script_macro finishRule
"finish" proof:term => `(tactic| exact $proof:term)

script_elab introNamedRule (intro := [h])
"intro_named" h:ident => do
  Lean.Elab.Tactic.evalTactic (← `(tactic| intro $h:ident))

macro "finish" proof:term : term => `(script
  finish $proof:term)
```

参数由 `RecordCategory` 实例解释，容器由 `RecordParam` 自动组合。内置支持 `term`、`ident`、`str`、`num`、`location`、`rwRuleSeq`、`simpArgs`、`optConfig`，以及括号、`+`、`*`、`?`、`sepBy`、`sepBy1`。未命名的复合序列需要包装为命名类别或提供手写 recorder。数组在零、单、多元素时都保持数组；`num` 输出 JSON 数字，按 `term` 解析的数值仍输出 Lean 表达式引用。

声明配置包括：

| 选项 | 含义 |
| --- | --- |
| `intro`、`clear` | 参数只在执行后、执行前捕获。 |
| `strategy` | 标记有证明分支的策略。 |
| `continuation` | 执行后续接目标的索引，从零计数。 |
| `params` | 参数级 `codec`、`timing`、`context`、`failure`、`field`。 |

`timing` 为 once / before / after / both；both 输出 `<field>_before` 与 `<field>_after`。字符串默认 once，其他参数默认 both。`failure` 默认 bestEffort，失败写入 null；required 失败则回滚本次录制与策略状态。`context` 为 main、continuation 或分支名称。显式单项 codec 支持 expression、typeOf、name、`"syntax"`。

```lean
script_macro finishRule
  (params := [proof(timing := before, field := "evidence")])
  "finish" proof:term => `(tactic| exact $proof:term)

script_info finishRule {
  template := [{ lang := "zh", tag := "完成", content := "${evidence}" }]
}
```

对于已 elaboration 的 calc 结果或生成媒体等输出，可用 `script_recorder <id>` 提供字段契约和自定义捕获逻辑，与自动录制共用公共接口：

```lean
script_recorder finishRule
  (fields := ProofScript.Recording.goalFields ++ #[{ name := "evidence", schema := .expression }])
  "finish" proof:term => do
    recordStep (before := #[
      ProofScript.Recording.param (.category `term) "evidence" proof
    ])
```

ID 与策略关键字必须匹配原注册。缺少类别实例不影响普通执行，实际录制时会报错，或使用已绑定的手写覆盖。手写 recorder 未声明 fields 时为不透明契约，导出 `recordedFields: null`。

`script_info` 的模板使用字段对象，配置在导入声明模块的证明模块生效，本模块内的更新供后续导入方使用。模板按语言合并，首项为语言缺失时的回退；导入后修改规则使用完整 ID，例如 `script_info MyRules.finishRule`。占位符使用实际输出字段名，`${rules.0.expression}`、`${loc_before.hypotheses}` 等嵌套路径会按 schema 校验。失败捕获显示 `—`，文本和结构化值均进行 HTML 转义。特定 renderer 使用最终合并配置；相同关键字的重载须使用不同 ID。

需要自定义录制顺序时，使用公共步骤接口。`withRecordingStep` 预留一个步骤对象，回调结束后关闭句柄。下游选择字段及捕获位置，并显式执行 tactic：

```lean
open Lean ProofScript ProofScript.Recording

script_macro snapshotThenClear "snapshot_then_clear" h:ident => `(tactic| clear $h:ident)
script_recorder snapshotThenClear (fields := goalFields ++ #[
  { name := "evidence_before", schema := .expression, nullable := false },
  { name := "module", schema := .string, nullable := false },
  { name := "evidence_after", schema := .expression }])
  "snapshot_then_clear" h:ident => withRecordingStep fun step => do
    step.recordGoal "goal_before"
    step.captureField "evidence_before" (expression h.raw)
    step.recordJson "module" (toJson (← getEnv).mainModule)
    executeRecordedStep
    step.recordGoal "goal_after"
    step.captureField "evidence_after" (expression h.raw) { onFailure := .bestEffort }
```

`captureField` 恢复捕获过程中的临时 elaboration 状态，再提交自包含快照。直接捕获默认 required；bestEffort 失败时写入 null。`CaptureOptions.goal` 指定目标，`collectReferences := false` 关闭该字段的文献收集。普通环境数据使用 `recordJson`；已捕获的 `RecordedValue` 使用 `recordValue` 提交，嵌套容器中的表达式也会统一处理。分开捕获与写入时使用 `isolatedCapture`；`RecordedValue.toJson` 保留快照内部的引用，只用于查看。公共写入拒绝空名、保留字段和重复字段，也检查直接字段与 `step.capturePlan captures` 之间的冲突。

步骤范围成功时保留 tactic 执行结果；失败时回滚 Lean 状态、录制数据、表达式表和文献引用。嵌套步骤预留固定位置，外层可在内层结束后继续写入。句柄仅在回调期间有效；最后一个目标关闭后仍可捕获纯数据。目标快照保留表达式类型，不把目标中的常量自动加入文献。LaTeX 编译、资源文件写入等外部 IO 不随 Lean 状态回滚。

策略执行后使用 `resolveStrategyContexts labels (continuationIndex := some index)`，取得有序的 `branches` 及 `contexts.goal`，查询 main、continuation 或 `.branch label` 的实际目标。直接捕获应先确认目标存在，再传入 `CaptureOptions`；未指定 goal 表示使用当前主目标。批量捕获可用 `step.capturePlan after contexts.goal` 选择每项的上下文，之后调用 `step.prepareBranches contexts`。script 执行器负责推进分支，并在证明完成后写回预留的父步骤；下游无需管理 box 标签或表达式表。

`recordStep` 在执行前记录当前主目标为 `goal_before`，执行后记录剩余主目标为 `goal_after`；`recordStrategy` 还会准备分支。没有剩余目标时写入 `null`。策略的 goal_after 在 tactic 执行后、分支证明前捕获。目标快照与其他参数共用捕获、提交、字段校验和模板渲染路径。自动录制器在 recordedFields 中声明这两个字段，模板可直接使用 `${goal_before}` / `${goal_after}`。手写录制器可在字段契约中添加 goalFields，也可自行声明和记录其他目标字段名。直接步骤范围允许只记录环境元数据。

`recordStep (before := #[...]) (after := #[...])` 接收两个有序的 `Array ParamCapture`，默认均为空数组。ParamCapture 和 param 不再携带 timing，capturePlan 也直接接收数组，在调用位置执行传入的整组。手写前后快照须分别指定不同的输出字段名；ParamCapture.field 默认等于 name，也可另设输出名并保留用于诊断的逻辑名。自动录制器在生成代码时展开声明中的 timing：once/before 进入 before，after 进入 after，both 生成 `<field>_before`、`<field>_after`。validateCaptures 检查无效输出名和重名，执行 tactic 前统一检查两组之间的字段冲突。

运行时接口由 `ProofScript.Script.Recording` 导出，便捷编排位于 `ProofScript.Script.Record`，`import ProofScript` 包含两者。参见[直接录制示例](examples/recording/DirectRecorder.lean)和[类别扩展示例](examples/recording/Labels.lean)。新增类别只需定义 RecordCategory 实例，数组和 optional 输入自动组合该实例。

暂不支持使用像 `macro_rules` / `elab_rules` 一样的方式定义脚本策略.

### 导出证明树

要导出某个定理或引理，只需使用 `@theorem` 或 `@lemma`。两者在页面 JSON 中分别使用
`"theorem"` 和 `"lemma"` 标签。
ProofScript 会在目录 `.../.ProofScript/proofs/` 下存放这些数据, 其中 `.../` 代表 Lean 项目根目录.
每个证明树顶层都包含 `schemaVersion` 和完整 Lean 源码 `code`；脚本模式证明树还包含表达式表
`expressions` 与录制的步骤数组 `proof`。数组中的每项都是一个步骤对象，包含 `_ruleId`、捕获字段和策略的 branches；每个分支的 proof 使用相同格式。默认录制器记录的 goal_before / goal_after 为表达式引用或 null。

`:= script` 中直接使用无前缀 DSL 名称，框架会自动补全 `script_` 前缀并检查、记录每一步；`:= by` 接受普通 Lean
策略，但不能使用 ProofScript 的脚本策略。后者只保留 `schemaVersion` 与完整 `code`，不输出
`expressions` 或 `proof`。两种模式都会自动采集文献引用。

`@theorem` 和 `@lemma` 声明现在由 command macro 展开。`script_theorem_impl` 命令负责原有的录制工作，并将请求的名称定义为
不透明的证明声明；然后宏再生成标准的 `theorem scriptcheck_<name> : ... := <name>` 声明。
这个额外的标准声明用于保留 Lean 对 theorem 的分类以及 IDE 中的蓝勾，同时不会触发 `defProp` 警告。


## ProofText

`@text` 接受一个 Lean 字符串字面量, 并作为专属的轻量标记语言 ProofText 进行解析, 其在语法上与 Typst 大致相近.

````lean
@text r#"
= ProofText Overview <overview>

This paragraph contains *bold*, _emphasis_, *_bold emphasis_*,
~~deleted~~, __underlined__, ==highlighted==, x^2^, a~n~,
`inline code`, $x + y$, and [a link](https://example.com).

- First item
- Second item

+ First step
4. Forced fourth step
+ Automatically numbered fifth step

> A quoted paragraph.

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

```lean
theorem example : True := by
  trivial
```
"#
````

### 块级结构

- 1 至 4 级标题: 置于行首的 `= TITLE` / ... / `==== TITLE` , 其中 `TITLE` 为标题名称
- 自定义标签的标题: `== TITLE <label>` , 其中 `label` 为标签名称
- 普通段落
- 无序列表: 由行首的 `-` 引导
- 有序列表: 由行首的 `+` 引导
- 强制序号的有序列表: 由行首的 `n.` 引导, 其中 `n` 是任意自然数
- 引用块: 由行首的 `>` 引导
- 行间公式: 由独占整行的 `$$` 包裹
- 整段代码块: 由 <code>```</code> 包裹, 支持语言标注

### 行内结构

| 语法 | 含义 |
| --- | --- |
| `*text*` | 粗体 |
| `_text_` | 强调 |
| `*_text_*` | 粗体强调 |
| `~~text~~` | 删除线 |
| `__text__` | 下划线 |
| `==text==` | 高亮 |
| `x^2^` | 上标 |
| `a~n~` | 下标 |
| `` `code` `` | 行内代码 |
| `$x + y$` | 行内数学公式 |
| `[text](url)` | 链接 |
| `@<label>` | 标题引用 |
| `@thm:Lean.DeclarationName` | 定理引用（跨模块使用完整限定名） |
| `@fig:label` | 图片或 LaTeX 组件引用 |

ProofText 源代码和解析后的语义 AST 将由 ProofScript 统一导出至页面 JSON 文件中, 以下文档供参考:

- [ProofText 中文语法](docs/ProofText-Syntax-zh.md)
- [ProofText English syntax](docs/ProofText-Syntax.md)


## 自动文献管理系统

### 文献信息注册

`project_info` 配置并选择活动项目，持久化至 `.olean`。可写 `project_info "MyProject" { ... }` 指定稳定的项目身份；无目标时更新当前活动项目，无活动项目时以模块名建立项目。相同项目允许多次更新，多个项目可以共同进入站点。

```lean
project_info {
  title := "Project Title",
  authors := ["Alice", "Bob"],
  description := "项目简介",
  keywords := ["Lean", "logic"],
  year := "2026",
  base_url := "https://example.com",
  license := "..."
}
```



### 定理信息注册

普通 Lean theorem、`@theorem` 和 `@lemma` 均可在声明之后使用独立命令注册定理元数据：

```lean
theorem referencedTheorem (P : Prop) (h : P) : P := h

theorem_info referencedTheorem {
  name := "Displayed theorem name",
  tags := ["algebra", "foundational"],
  customField := "custom value"
}
```

`name`、`tags` 控制展示，`project` 直接保存 `String` 类型的项目名；首次配置默认绑定当时的活动项目，后续更新普通字段保持归属。未知字段进入 `extra` 对象。六种 Info 命令都允许重复更新，并支持已知字段检查、`none` 与 `reset`。定理引用和页面锚点使用 Lean 声明名，跨模块引用时使用完整限定名。

### 自动文献采集

在 `@theorem` 录制表达式参数时，ProofScript 收集其中使用的声明身份，按首次出现顺序去重。`page_end` 统一解析已配置的文献信息、标题与渲染配置，因此关闭前的元数据更新会一致生效；关闭后的更新不会修改该页面的冻结视图。

下面的命令可以用来局部关闭文献自动采集:

```lean
set_option referenceCollection false in
@theorem noReferences (P : Prop) (h : P) : P := script
  assumption
```

在页面的任何位置, 使用命令 `@references` 即可把当前暂存区中的全部文献信息作为页面组件
输出, 此操作将清空文献暂存区. 该命令不接受文件名, 也不会单独写出 references JSON.

## 其它页面组件

### 任意 LaTeX

`@latex` 接收任意 LaTeX 源码并在编译期生成 SVG. `title` 必填, `label` 可选, 其它字段会
保存在 metadata 的 `extra` 中:

```lean
@latex (
  title := "交换图",
  label := "commutative-diagram"
) r#"
\begin{tikzpicture}
  \draw[->] (0,0) -- (1,0);
\end{tikzpicture}
"#
```

### 图片资源

`@figure` 接收包含后缀的相对图片资源路径. ProofScript 只导出路径和扩展名, 不读取或复制文件:

```lean
@figure (
  title := "架构图",
  label := "architecture",
  width := "wide"
) "assets/architecture.png"
```

### 自定义页面组件

页面模块可以调用 `addPageComponent` 注册开放式 JSON 组件。需要嵌入式
计算时，优先使用内置 `@computation`：它接收组件元数据、下游 renderer ID、Lean 函数声明和
renderer 专用的 JSON manifest：

```lean
def chooseOffset (large : Bool) : Nat := if large then 128 else 112

@computation {
  metadata := (title := "有限计算", label := "finite-computation"),
  renderer := "my-renderer/table-v1",
  function := chooseOffset,
  payload := r#"{"execution":{"backend":"table"},"results":[112,128]}"#
}
```

输出包含声明全名、可读类型、函数实现体和结构化 Lean 表达式表。这些字段是来源信息和中间产物，
不承诺 Lean 编译器内部 IR 的浏览器 ABI；实际执行方式由版本化 renderer ID 和 manifest 共同决定。
详见 `docs/Embedded-Computation-Renderer-zh.md`。

计算入口必须形如 `α → β` 或 `α → Except String β`，并存在 `Lean.FromJson α` 与
`Lean.ToJson β`。命令会生成 `String → String` wrapper 和 pending build manifest；实际 Wasm
resource 由后续 bundler 阶段生成。

生成 pending manifests 后，可在项目根目录运行：

```bash
source "$HOME/Developer/emsdk/emsdk_env.sh"
PROOF_SCRIPT_LEAN_WASM_PREFIX=/path/to/lean-wasm-prefix \
  node /path/to/ProofScript/scripts/build-computations.mjs
```

该命令按模块生成多入口 bundle 到 `.ProofScript/computations/bundles/`。页面 resource 回填由
finalize 阶段完成：

```bash
node /path/to/ProofScript/scripts/finalize-computations.mjs
```

Finalize 将资源发布到内容寻址目录并把页面 execution 更新为 `ready`。前端实现参见
`docs/Frontend-Computation-Handoff-zh.md`。

当前计算构建流程与 renderer API 参见 `docs/Embedded-Computation-Renderer-zh.md`。

前端 renderer 可先使用 `docs/Embedded-Computation-Quickstart-zh.md` 中的 Fibonacci 示例做端到端测试。

## 统一 Info 配置

六种命令的全部保留字段、默认值、模板语法和完整示例见 [Info 命令使用手册](docs/Info-Commands-zh.md)。

六个命令共用强类型模型、字段解析、增量更新和导出协议：

| 命令 | 模型（`ProofScript.Info`） | 目标 |
| --- | --- | --- |
| `project_info` | `ProjectInfo` | 非空项目名字符串；省略目标时更新活动项目 |
| `theorem_info` | `TheoremInfo` | 已声明的 Lean 定理名 |
| `script_info` | `ScriptInfo` | 已注册的完整脚本 ruleId，或本模块的注册 ID |
| `def_info` | `DefinitionInfo` | 已声明的 Lean 常量 |
| `var_info` | `VariableInfo` | 非空类别字符串 |
| `phrase_info` | `PhraseInfo` | 非空短语键 |

命令可以重复执行，只更新写出的字段；已知字段的类型错误、同命令重复字段及未知嵌套字段会报错。未知顶层字段保存到 `extra`，支持字符串、数值、布尔、null、数组和对象。可显式写 `extra := { "review.status" := "checked" }`，其键不会覆盖内置字段。

```lean
project_info "课程笔记" { title := "Notes", authors := ["Alice"], edition := 1 }
project_info "课程笔记" { title := "Revised notes", edition := 2 }
script_info ProofScript.Script.Basic.«rfl» { display := true, reviewed := true }
var_info "Nat" { default := "n", names := ["n", "m", "k"] }
phrase_info "forall" { template := [{ lang := "en", content := "${body} for every ${binder}" }] }
```

项目 ID 统一使用非空字符串字面量，例如 `"课程笔记"`，按完整文本匹配；命名空间和 `open` 不改变项目 ID。定理通过 `project := "课程笔记"` 选择已配置的项目。

省略字段保留已有值；`none` 是 Option 字段的空值；`reset` 屏蔽继承值并恢复字段默认值，无默认的必填字段恢复为未提供。普通列表和 styles 整体替换；template 按语言合并，同语言替换保留位置，新语言追加。`extra` 按键更新，单键 `reset` 删除该键。

Lean 按实际导入图合并：同模块后写覆盖前写，后代覆盖祖先，独立分支的不同字段可合并；同字段不同值保留冲突及来源，消费前可由本地更新消解。未被消费的不完整配置可以保存。`page_end` 同时冻结标题、引用、项目和渲染配置；关闭后的配置仍可供下游使用。独立 proof 使用模块结束视图。

### 模块与查询接口

`import ProofScript` 提供脚本、页面和全部默认展示。按需导入可以使用 `ProofScript.Info`（六种模型及命令）、`ProofScript.Script.Registry`（纯注册）、`ProofScript.Script.Command`（脚本声明）、`ProofScript.Defaults.Script` / `Defaults.Lean2TeX`（基础展示）、`ProofScript.Mathlib.Info`（Mathlib 展示）、`ProofScript.Page.Command`（页面集成）。`Script.Basic` 和 `Mathlib.Scripts` 承载执行实现与注册，展示配置位于 Defaults 和 Mathlib.Info。

模型使用 `ProofScript.Info.ProjectInfo` 等完整名称；源码位置使用 `ProofScript.Foundation.SourceLocation`。领域查询显式接受 `Info.Query`，不能借导出器自身的 mainModule 推断配置视图：

```lean
open Lean Elab Command ProofScript.Info
run_cmd do
  let env ← getEnv
  let query : Query := { moduleName := env.mainModule }
  match resolveProjectInfo env query "Notes" with
  | .ok info => logInfo info.value.title
  | .error error => throwError error.render
```

### 扩展与维护

普通字段直接加到相应领域结构体，`deriving InfoSchema` 自动生成字段句柄、codec 关联、编码与 JSON Schema。特殊值类型实现 `InfoCodec`，它继承 Lean 的 `ToJson`，并通过结构化解码器自动提供 `FromJson`；普通 JSON 消费直接使用 `toJson` / `fromJson?`，Info 校验保留 `Diagnostic` 的字段路径和关联字段。特殊合并/校验通过生成的 `Model.infoFields.field` 类型化句柄配置 SchemaOverrides。新增 info 种类还需定义 InfoSpec、目标解析、薄命令和快照依赖消费入口；Python 按该种类的实际展示需求适配冻结值，不再维护第二份输入字段表。

派生器当前支持无参数、无继承、非递归、非依赖字段及独立默认值的普通结构体。InfoCodec 只解析配置；录制捕获继续使用 Recording API，`script_info` 不修改 recorder 或输出契约。注册声明保留在 Basic / Mathlib.Scripts，ruleId 由定义模块和本地 ID 组成；移动注册声明会改变身份。

公开接口检查为 `Test.InfoCoreAPITest`、`Test.InfoAPITest`；定理导航的真实页面检查见 `Test/test_theorem_site_browser.mjs`。阶段验收用的内部 Python 测试脚本已清理。

## 页面导出

`page_end` 写出页面并持久化其冻结配置，之后的页面组件会被忽略。完整站点使用 `lake build MyLibrary:ps4html` 构建。Info 协议为 `4.0.0`，录制协议为 `0.0.0`；`info/index.json` 是包含文件摘要、schema、快照和调用契约关联的完成清单。配置可从 `.olean` 重建，page/proof/resources 内容由构建时生成；只读缓存使用 `ps4html make --cache`。不完整或版本不匹配的缓存会被拒绝，需要重新构建。

## 环境要求

### 必需环境

已完整安装 Lean + Lake + Elan

### 可选 LaTeX 环境

如果需要使用页面组件 `@latex` , 系统 `PATH` 中还必须存在:

```bash
latex --version
dvisvgm --version
```

## 当前限制

- `script` 只允许带 `script_` 前缀的已注册策略，不支持任意 Lean tactic，也不支持 bullet `·`。
- 自动 recorder 只支持有限的 parser 参数形式；复杂策略必须手写 `script_recorder`。
- `complete_induction` 当前是自然数强归纳模板。
- 自动引用只扫描录制器接触到的表达式，并且只采集已注册 `theorem_info` 元数据的声明，不是完整依赖分析。
- ProofText 引用在 elaboration 时只检查语法，不验证引用目标一定存在；跨页面索引应由下游消费者建立。
- ProofText 是小型专用语言，不提供完整 Markdown/Typst 能力。
- 页面按单模块、一次导出模型工作；`page_end` 之后的组件会产生警告并被忽略。
- LaTeX 组件要求本机 `latex`、`dvisvgm` 和相应 TeX 宏包，且编译失败会中断 Lean elaboration。
- 页面 source 路径当前通常为绝对路径；源码位置使用 UTF-8 字节偏移。
- Lean 表达式 JSON 与 Lean 内部 AST 紧密相关，仍属于可扩展接口，跨 Lean 版本使用时应谨慎。
- 当前 universe level 的 `max`/`imax` 序列化实现存在重复键问题，不应依赖其左右操作数能够被完整区分。

## 相关文档

- [English README](README.md)
- [ProofText 中文语法](docs/ProofText-Syntax-zh.md)
- [ProofText English syntax](docs/ProofText-Syntax.md)
- [录制证明 JSON Schema](docs/schema/recording-proof.schema.json)
- Info 模型与快照 Schema 随完成导出生成到 `.ProofScript/info/schema/`。

## PS4HTML 站点生成器

PS4HTML 已作为站点生成工具集成在本仓库的 [`tools/ps4html/`](tools/ps4html/) 中。它消费 ProofScript 导出的页面、证明树和资源；证明本身仍由 Lean 检查。主要功能包括：

- 按 Lean 模块生成 HTML 页面、项目入口、模块导航、跨页引用、定理依赖导航和分组文献。
- 渲染 ProofText、定理与引理、结构化证明步骤和分支、源码视图、代码高亮、图片及 LaTeX 导出的 SVG；未知规则或资源错误有可见的回退与诊断。
- 通过 Lean2TeX 将表达式转换为 TeX，并配置声明宏和变量命名；支持中英文证明文本、KaTeX 公式显示及变量联动高亮。
  - 编排 Lean 和嵌入式 Lean/Wasm 计算构建，提供浏览器 Worker 组件、本地预览服务器与 `lean2tex-report.json` 诊断报告。策略用 `script_info` 设置展示，产物清单为 proof 选择冻结配置和实际调用契约；PS4HTML 据此排版，缓存渲染不执行 Lean。例如 `script_info ProofScript.Script.Basic.renderCalc { renderer := «calc» }` 选择计算链渲染器。

在仓库根目录执行 `python3 -m pip install -e ./tools/ps4html`（Python 3.11+），然后到 Lean 项目中运行 `lake build MyLibrary:ps4html`，使用 `ps4html serve` 预览 `.PS4HTML/build/`。`ps4html make --cache` 可直接渲染已有导出，不重新编译 Lean。计算工具链要求与现有限制详见 [PS4HTML 使用说明](tools/ps4html/README.md)和[完整示例](examples/site/README.md)。
