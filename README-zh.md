# ProofScript

ProofScript 是一个面向 [Lean 4](https://lean-lang.org/) 的编译期语言扩展.
它提供一套结构化、可扩展且语义增强的证明 DSL, 将 Lean 证明的实时目标、策略参数和分支结构录制并导出为 JSON,
同时, ProofScript 还集成了 ProofText 正文、定理表述、图片、LaTeX SVG 等页面组件, 页面构建会将这些数据编译并导出为 JSON, 供渲染器或其他下游工具消费.

ProofScript 内置 PS4HTML 站点工具，源码位于 [`tools/ps4html/`](tools/ps4html/)，无需另行下载 PS4HTML 仓库。
在仓库根目录安装（Python 3.11+，建议使用虚拟环境）：

```sh
python3 -m pip install -e ./tools/ps4html
```

在用户 Lean 项目中配置 ProofScript 依赖、执行 `lake update` 后，运行 `lake build MyLibrary:ps4html`（将 `MyLibrary` 替换为实际库名），输出为
`.PS4HTML/build/index.html`；`ps4html serve` 提供本地预览。完整示例位于 [`examples/site/`](examples/site/)，
其中计算页面另需 Node、Emscripten 和匹配的 Lean/Wasm runtime。
统一 Info 导出协议为 `5.0.0`，录制协议使用 `0.1.0`。每个 script 步骤对应一个对象，目标快照作为普通字段写入；配置及实际契约通过产物清单关联。旧缓存需重新运行 Lake facet 构建，详见[统一配置与导出说明](#统一-info-配置)。
详细使用说明见 [PS4HTML 文档](tools/ps4html/README.md)。

普通 `lake build` 和 IDE 默认只检查证明。`@theorem` / `@lemma` 生成原生 Lean theorem，
不录制步骤、不导出页面，也不启动 LaTeX 或计算资源构建；六种 Info 命令跳过配置工作。`lake build MyLibrary:ps4html`
自动启用页面模式，在 `.lake/ps4html/<包名>/<库名>/` 中编译所需用户源码、框架及配置依赖，保留普通 `.lake/build/` 缓存。

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

@theorem mainResult (info := { name := "Main Result" }) (P : Prop) (h : P) : P := script
  assumption


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

`import ProofScript` 通过 `ProofScript.Mathlib.Info` 加载 Mathlib 策略及其展示配置模块；展示配置只在页面构建中登记。只需 tactic 实现与注册时可以导入：

```lean
import ProofScript.Mathlib.Scripts
```

基础策略的 `ProofScript.Script.Basic` 提供执行与注册，`ProofScript.Builtin.Script` 另提供页面展示配置；公共 `ProofScript` 入口导入全部默认配置模块，其中的 Info 命令只在页面模式生效。模块职责见[统一 Info 配置](#统一-info-配置)。当前包装按字母顺序包括：

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

参数统一由 `RecordParam` 实例解释；叶子类别注册 `RecordParam (.category name)`，数组和 optional 输入自动组合这些实例。内置支持 `term`、`ident`、`str`、`num`、`location`、`rwRuleSeq`、`simpArgs`、`optConfig`，以及括号、`+`、`*`、`?`、`sepBy`、`sepBy1`。未命名的复合序列需要包装为命名类别或提供手写 recorder。数组在零、单、多元素时都保持数组；`num` 输出 JSON 数字，按 `term` 解析的数值仍输出 Lean 表达式引用。

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

对于已 elaboration 的 calc 结果或生成媒体等输出，可用 `script_recorder <id>` 提供字段契约，并通过自动录制也使用的录制器 DSL 编排执行顺序：

```lean
open ProofScript.Recording

script_recorder finishRule
  (fields := goalFields ++ #[{ name := "evidence", schema := .expression }])
  "finish" proof:term => recording_step do
    capture_params #[goalParam "goal_before", param (.category `term) "evidence" proof]
    execute_recorded
    capture_params #[goalParam "goal_after"]
```

ID 与策略关键字必须匹配原注册。缺少类别实例或参数 parser 不支持自动录制时，若没有绑定手写 recorder，实际录制只发出警告，策略仍正常执行。对应步骤导出保留 `_ruleId: "ProofScript.Recording.unrecorded"` 和原策略关键字 `name`；策略分支继续独立录制。PS4HTML 将该步骤显示为红色“未导出数据”框。手写 recorder 未声明 fields 时为不透明契约，导出 `recordedFields: null`。

`script_info` 的模板使用字段对象，配置在导入声明模块的证明模块生效，本模块内的更新供后续导入方使用。模板按语言合并，首项为语言缺失时的回退；导入后修改规则使用完整 ID，例如 `script_info MyRules.finishRule`。占位符使用实际输出字段名，`${rules.0.expression}`、`${loc_before.hypotheses}` 等嵌套路径会按 schema 校验。失败捕获显示 `—`，文本和结构化值均进行 HTML 转义。特定 renderer 使用最终合并配置；相同关键字的重载须使用不同 ID。

公共 DSL 与运行时接口由 `import ProofScript.Script.Recording` 导出；`import ProofScript` 还包含脚本声明命令。`recording_step do` 在主目标上下文中开启一个录制对象，块内是普通 Lean `TacticM` 代码，可以使用变量、条件、循环以及自定义执行逻辑。录制块本身不隐式添加目标快照或执行 tactic，也支持只记录元数据。

| 语句 | 含义 |
| --- | --- |
| `capture_params parameters` | 执行到此处时，按顺序捕获 `Array ParamCapture`。 |
| `record_value key value` | 通过 `ToRecordedValue` 转换已有值，并写入 `key`。 |
| `execute_recorded` | 使用本次调用选中的原始策略及原始参数执行。 |

例如，先捕获一个假设，写入已有元数据变量，清除假设后再尝试捕获：

```lean
open Lean ProofScript ProofScript.Recording

script_macro snapshotThenClear "snapshot_then_clear" h:ident => `(tactic| clear $h:ident)
script_recorder snapshotThenClear (fields := goalFields ++ #[
  { name := "evidence_before", schema := .expression, nullable := false },
  { name := "module", schema := .string, nullable := false },
  { name := "evidence_after", schema := .expression }])
  "snapshot_then_clear" h:ident => recording_step do
    capture_params #[
      goalParam "goal_before",
      { name := "evidence_before", onFailure := .required, capture := expression h.raw }
    ]
    let moduleName := toJson (← getEnv).mainModule
    record_value "module" moduleName
    execute_recorded
    capture_params #[
      goalParam "goal_after",
      { name := "evidence_after", onFailure := .bestEffort, capture := expression h.raw }
    ]
```

`ParamCapture` 和 `param` 只描述捕获操作，不安排执行时机。构造数组时不会捕获；`capture_params` 执行到各项时才读取当时状态。`onFailure` 默认为 `.bestEffort`，捕获失败写入 `null`；`.required` 则报错。每项捕获会恢复临时 elaboration 状态，再提交快照；一批捕获失败时，即使调用方捕获了异常，该批已经写入的字段也会回滚。设置 `collectReferences := false` 可关闭该字段的文献收集。`ParamCapture.field` 默认等于 `name`；修改它可以改变输出键名，同时保留用于诊断的逻辑名。手写前后快照应使用不同键名。

`record_value` 支持 `RecordedValue`、`Json`、`String`、`Bool`、`Nat`、`Int` 和 `Expr`，数组、列表、optional 会组合其元素的实例。`ToRecordedValue.capture` 返回 `CaptureM RecordedData`；`Expr` 在当前上下文中捕获，自定义类型也可以实现这个接口。转换过程隔离执行，失败时必须报错。若需在执行前捕获、执行后写入，应使用 `CaptureM.run` 保存 `RecordedValue`：

```lean
-- 放在 recording_step 或 recording_strategy 块内：
let saved ← CaptureM.run (expression h.raw)
execute_recorded
record_value "evidence" saved
```

`RecordedValue` 是 `CaptureM.run` 返回的纯 `{ data, nodes }`，没有 `ToJson` 实例；使用 `RecordedValue.encode : Json` 一起导出数据、表达式表和根路径。其中的表达式节点可以导入新的 builder 或提交到证明会话的共享节点数组，并重定位引用；步骤和分支在最终证明导出前一直保存结构化 `RecordedData`。通过 `record_value` 提交时，包括嵌套在容器内的值，都会保留结构图，无需重新查询原上下文。文献引用从纯图中收集。

录制格式为 `0.1.0`。`recordedProofJson` 直接导出纯结构图和显式 `expressionRoots`。PS4HTML 只解引用根清单注册的位置，按调用契约应用展示伴随字段；普通 JSON 保持用户数据语义。旧缓存须重新运行 `lake build MyLibrary:ps4html`，`ps4html make --cache` 不迁移旧数据。旧表达式导出器及兼容适配层已删除。

需要新格式的变量名字、声明类型/局部定义值、命题判断或应用参数显式性时，须显式捕获 `<field>_display` 伴随字段。`goalParamWithDisplay`、`paramWithDisplay`、`explicitParamWithDisplay` 和 `recordValueWithDisplay` 提供该入口；输出契约用 `withDisplayFields` 扩展。伴随字段是普通 `RecordedData`，辅助表达式与主字段共用节点表，但不增加文献引用；主字段缺失或 best-effort 失败时两项同时写入 `null`。普通 `record_value` 和自定义转换不会自动增加伴随字段。

```lean
-- 在有效上下文中成对保存，随后原子写入 evidence/evidence_display：
let saved ← CaptureM.run <| captureWithDisplay "evidence" (expression h.raw) (some h.raw)
execute_recorded
recordCapturedWithDisplay "evidence" saved
```

自定义转换仍只组合结构，例如下例中的表达式叶子使用 `snapshotExpression`。调用方需要展示信息时，显式用 `recordValueWithDisplay "evidence" value` 包裹整个转换，嵌套容器的每个表达式会得到相对于该字段的 occurrence 路径。导入已有快照只重定位节点，不会重新查询其声明；需要展示时应在最初捕获时一起保存。

```lean
structure Evidence where
  term : Lean.Expr
  label : String

instance : ToRecordedValue Evidence where
  capture value := do
    return .object [
      ("term", ← snapshotExpression value.term),
      ("label", .plain (Lean.toJson value.label))]
```

策略使用 `recording_strategy nodes do ...`，可以附加 `(continuation := some index)`。`nodes` 是描述 script 证明分支的 `List String`，复合表达式需要加括号。手写策略录制器通过额外的 `"_strategy_cases" strategyCases:str` parser 参数接收执行器传入的换行分隔标签：

```lean
script_macro rememberTrue (strategy := true, continuation := 1)
  "remember_true" h:ident => `(tactic| script_claim $h:ident : True)

script_recorder rememberTrue
  (fields := strategyGoalFields ++ #[
    { name := "hypothesis", schema := .expression, nullable := false }])
  "remember_true" h:ident "_strategy_cases" strategyCases:str =>
  recording_strategy (strategyCases.getString.splitOn "\n") (continuation := some 1) do
    capture_params #[goalParam "goal_before"]
    execute_recorded
    capture_params #[
      { (param (.category `ident) "hypothesis" h .required) with context := .continuation }
    ]
```

块在 body 成功后自动准备分支，body 提前 `return` 也不会跳过收尾。收尾会重新解析最终目标，并在关闭录制对象前调用 `prepareBranches`；异常时回滚整个块，不准备分支。之后由 script 执行器推进分支证明，并将其合并回父步骤。

每项 `ParamCapture.context` 都在该项捕获时解释：`.main` 使用当前主目标，策略块还支持 `.continuation` 和 `.branch "label"`。选择器读取当前目标，不缓存执行后的某次快照；缺失或无效的选定上下文按该项失败策略处理，在普通块中使用非 main 选择器也一样。策略执行前捕获主目标时，不要求分支已经存在。

普通自动录制器显式捕获 `goal_before` 和 `goal_after` 及其 `_display`，策略自动录制器只捕获执行前的这对字段；表达式参数也生成伴随字段，`both` 时名为 `<field>_before_display` / `<field>_after_display`。手写录制器通过 `goalParam` 或 `goalParamWithDisplay` 自行安排快照，并使用 `goalFields`、`strategyGoalFields`、`withDisplayFields` 或自定义字段声明匹配的契约；字段声明本身不会执行捕获。没有剩余目标时，目标及已启用的伴随字段写入 `null`，目标中的常量不自动加入文献。模板只能引用对应 recorder 实际提供的字段。

`timing` 只属于声明配置。自动生成时，`once` / `before` 的捕获位于执行前，`after` 位于执行后，`both` 生成 `<field>_before`、`<field>_after`。手写 DSL 则直接由语句位置决定时机。空键名、保留键（`_ruleId`、`branches`）和重复写入始终报错，包括捕获语句与值录制语句之间的冲突，`bestEffort` 不会吞掉这些错误。跨阶段冲突可能在执行 tactic 后才发现；声明阶段仍检查无效名称和 timing 展开后的字段冲突。

块成功时保留 tactic 执行结果，失败时回滚 Lean 状态、录制数据、表达式表和文献引用。嵌套块预留固定录制位置，内层结束后外层仍可继续写入；最后一个目标关闭后也可记录纯数据。LaTeX 编译、资源文件写入等外部 IO 不随 Lean 状态回滚。需要自定义执行时，直接用普通 `TacticM` 操作代替 `execute_recorded`；可复用的录制辅助函数声明 `[RecorderContext]`，使用调用方的录制作用域。

参见[直接录制示例](examples/recording/DirectRecorder.lean)和[类别扩展示例](examples/recording/Labels.lean)。新增类别只需定义 `RecordParam (.category name)` 实例，数组和 optional 输入自动组合该实例。

暂不支持使用像 `macro_rules` / `elab_rules` 一样的方式定义脚本策略.

### 导出证明树

使用 `@theorem` 或 `@lemma` 声明页面定理，再运行 `lake build MyLibrary:ps4html` 导出。两者在页面 JSON 中分别使用
`"theorem"` 和 `"lemma"` 标签。
发布后的证明数据位于 Lean 项目的 `.PS4HTML/inputs/<包名>/<库名>/.ProofScript/proofs/`。
每个证明树顶层都包含 `schemaVersion` 和完整 Lean 源码 `code`；脚本模式证明树还包含表达式表
`expressions`、根路径清单 `expressionRoots` 与录制的步骤数组 `proof`。数组中的每项都是一个步骤对象，包含 `_ruleId`、捕获字段和策略的 branches；每个分支的 proof 使用相同格式。普通默认录制器记录的 `goal_before` / `goal_after` 为表达式引用或 `null`；策略默认录制器只记录 `goal_before`。

`:= script` 中直接使用无前缀 DSL 名称，框架会自动补全 `script_` 前缀并检查每一步，在页面构建时录制；`:= by` 接受普通 Lean
策略，但不能使用 ProofScript 的脚本策略。后者只保留 `schemaVersion`、`module` 与完整 `code`，不输出
`expressions`、`expressionRoots` 或 `proof`。页面构建时，两种写法都会自动采集文献引用。

`@theorem` 和 `@lemma` 在普通模式与页面模式都生成原生 theorem，不再生成 `scriptcheck_<name>`。
普通模式复用执行版 `script` 或原生 `by`，保留 Lean 的异步证明检查；内联 `info` 和 `cite` 的展示配置校验留到页面模式。
页面模式通过构建选项 `proofScript.pageBuild` 同步执行录制器，再冻结配置并导出；同一模块不能中途切换模式。
六种独立 Info 命令在普通模式也跳过字段解码、语义校验和配置登记，但语法仍须合法；两种模式都会保留编辑器语义信息，包括尽力解析已有元数据目标。显式调用底层 recorder API 仍可录制。

仓库默认 `lake build` 运行验证测试；需要录制、页面组件或导出状态的测试使用
`lake build TestPage:pageTests`，它使用独立页面构建目录。`lake build MyLibrary:ps4html` 自动启用页面模式，重编译所需用户源码、ProofScript 框架及提供 Info 配置的依赖，恢复默认展示与用户配置。首版仍完整重录这些源码模块；Mathlib 等不含所需页面或 Info 数据的基础依赖复用缓存，普通 `.lake/build/` 保持不变。


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

页面模式下，`project_info` 配置并选择活动项目，持久化至页面构建的 `.olean`；验证模式跳过该命令。可写 `project_info "MyProject" { ... }` 指定稳定的项目身份；无目标时更新当前活动项目，无活动项目时以模块名建立项目。相同项目允许多次更新，多个项目可以共同进入站点。

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

普通 Lean theorem、`@theorem` 和 `@lemma` 声明之后可用 `theorem_info` 配置后续引用。若要设置录制定理自身的标题与归属，在声明名之后使用内联 `(info := { ... })`：

```lean
theorem referencedTheorem (P : Prop) (h : P) : P := h

theorem_info referencedTheorem {
  name := "Displayed theorem name",
  tags := ["algebra", "foundational"],
  customField := "custom value"
}
```

```lean
@theorem mainResult (info := { name := "主要结果", tags := ["algebra"] })
    (P : Prop) (h : P) : P := script
  assumption
```

后面的 `theorem_info mainResult` 只影响后续内容及下游模块，不会更改已创建的定理组件。`name`、`tags` 控制展示，`project` 直接保存 `String` 类型的项目名；首次配置默认绑定当时的活动项目，后续更新普通字段保持归属。未知字段进入 `extra` 对象。六种 Info 命令都允许重复更新，并支持已知字段检查、`none` 与 `reset`。定理引用和页面锚点使用 Lean 声明名，跨模块引用时使用完整限定名。

### 自动文献采集

在 `@theorem` 录制表达式参数时，ProofScript 收集其中使用的声明身份，按首次出现顺序去重。每份证明和每个页面组件保存创建时的本模块元数据边界；`@references` 使用该组件创建时可见的配置。上游模块提供其最终配置，本模块后面的修改不会影响前面的内容，即使修改位于 `page_end` 之前。

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

页面模块可以调用 `addPageComponent` 注册开放式 JSON 组件。自定义命令应使用
`whenPageBuild do` 包住整个构造动作，包括校验、JSON 构造和资源 IO，普通验证会跳过该动作。
`addPageComponent` 也会在注册前检查模式，但无法跳过调用方已经完成的工作。参见
[自定义组件示例](Test/CustomComponentTest.lean)。

需要嵌入式计算时，优先使用内置 `@computation`：它接收组件元数据、下游 renderer ID、Lean 函数声明和
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
详见 `docs/Frontend-Computation-Handoff-zh.md`。

函数来源信息通过独立的结构化捕获与纯编码边界生成。默认命令及 `ComputationFunction.encode` / `ComputationComponent.encode` 输出 `function.recordingVersion = "0.1.0"`、函数自有节点表、`expressionRoots` 和展示伴随字段；根路径相对于 `function`。消费者拒绝缺失或旧函数版本并提示重新构建页面。组件、pending manifest、bundle 版本仍为 `0.0.0`，`proofscript-json-v1` 执行 ABI 不变；finalizer 保留完整 function 数据。

`ComputationFunction` 只保存一份 `recording : RecordedValue`。函数和组件均通过返回 `Except String Json` 的 `.encode` 校验后完整导出，不提供绕过校验的 `ToJson` 实例。

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

当前计算构建流程与 renderer API 参见 `docs/Frontend-Computation-Handoff-zh.md`。

前端 renderer 可先使用 `docs/Embedded-Computation-Quickstart-zh.md` 中的 Fibonacci 示例做端到端测试。

## 统一 Info 配置

六种命令的全部保留字段、默认值、模板语法和完整示例见 [Info 命令使用手册](docs/Info-Commands-zh.md)。

六个命令只在页面模式执行配置工作。普通构建和 IDE 中不做字段解码与语义校验、不写入持久化配置事件；语法解析及模块模式一致性检查仍然生效。已有目标和已知字段仍支持跳转与引用联动，未找到的元数据目标可以跳过，详见 [IDE 与语言服务器支持](docs/IDE-Support-zh.md)。下列规则与示例均描述页面模式。

页面模式下，六个命令共用强类型模型、字段解析、增量更新和导出协议：

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

Lean 按实际导入图合并：同模块后写覆盖前写，后代覆盖祖先，独立分支的不同字段可合并；同字段不同值保留冲突及来源，消费前可由本地更新消解。未被消费的不完整配置可以保存。每份证明和每个页面组件只使用创建时已经提交的本模块配置，上游模块则提供全部最终配置。独立 proof 使用相同规则。`page_end` 只控制页面输出，不划分配置作用域；录制定理自身的配置用内联 `(info := { ... })` 写入。

### 模块与查询接口

`import ProofScript` 提供脚本、页面和全部默认展示模块，其中的 Info 配置只在页面构建时登记。按需导入可以使用 `ProofScript.Info`（六种模型及命令）、`ProofScript.Script.Registry`（纯注册）、`ProofScript.Script.Command`（脚本声明）、`ProofScript.Builtin.Script` / `Builtin.Lean2TeX`（基础展示）、`ProofScript.Mathlib.Info`（Mathlib 展示）、`ProofScript.Page.Command`（页面集成）。`Script.Basic` 和 `Mathlib.Scripts` 承载执行实现与注册，展示配置位于 Defaults 和 Mathlib.Info。

模型使用 `ProofScript.Info.ProjectInfo` 等完整名称；源码位置使用 `ProofScript.Foundation.SourceLocation`。模型、schema、codec、查询及显式底层录制 API 在两种模式均可用，但查询不能恢复普通模式跳过的配置。以下查询假定页面模式中已登记 `"Notes"` 项目；领域查询显式接受 `Info.Query`，不能借导出器自身的 mainModule 推断配置视图：

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

普通字段直接加到相应领域结构体，`deriving InfoSchema` 自动生成字段句柄、codec 关联、编码与 JSON Schema。特殊值类型实现 `InfoCodec`，它继承 Lean 的 `ToJson`，并通过结构化解码器自动提供 `FromJson`；普通 JSON 消费直接使用 `toJson` / `fromJson?`，Info 校验保留 `Diagnostic` 的字段路径和关联字段。`InfoSchema` 类型类直接保存字段规则；特殊合并/校验通过生成的 `Model.infoFields.field` 类型化句柄和 `withOverrides!` 注册为 `InfoSchema` 实例，让配置消费和 JSON 解码使用同一套最终规则。新增 info 种类还需定义保存种类名称和依赖查询的 `InfoSpec`、目标解析、薄命令和快照依赖消费入口；消费者通过 `InfoSchema` 实例取得字段规则；Python 按该种类的实际展示需求适配冻结值，不再维护第二份输入字段表。

派生器当前支持无参数、无继承、非递归、非依赖字段及独立默认值的普通结构体。自定义 Info 命令应把目标解析、全部字段处理及登记动作放在 `whenPageBuild do` 内；`commitInfo` 等显式底层 API 在两种模式仍可使用。InfoCodec 只解析配置；录制捕获继续使用 Recording API，`script_info` 不修改 recorder 或输出契约。注册声明保留在 Basic / Mathlib.Scripts，ruleId 由定义模块和本地 ID 组成；移动注册声明会改变身份。

公开接口检查为 `Test.InfoCoreAPITest`、`Test.InfoAPITest`，`Test.InfoSchemaTest` 检查配置消费和 JSON 解码使用相同规则；定理导航的真实页面检查见 `Test/test_theorem_site_browser.mjs`。阶段验收用的内部 Python 测试脚本已清理。

## 页面导出

页面模式下，`page_end` 按各组件保存的配置边界写出页面，之后的页面组件会被忽略；其后的 Info 命令仍供后续代码和导入模块使用。完整站点使用 `lake build MyLibrary:ps4html` 构建。Info 协议为 `5.0.0`，录制协议为 `0.1.0`；`info/index.json` 是包含文件摘要、schema、快照和调用契约关联的完成清单。配置可从页面构建的 `.olean` 重建，普通验证 `.olean` 中跳过的配置必须通过页面重编译恢复；page/proof/resources 内容由构建时生成。只读缓存使用 `ps4html make --cache`；不完整或版本不匹配的缓存会被拒绝，需要重新构建。

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
- 自动 recorder 只支持有限的 parser 参数形式；复杂策略需手写 `script_recorder` 才能完整导出数据，否则发出警告并显示“未导出数据”。
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
