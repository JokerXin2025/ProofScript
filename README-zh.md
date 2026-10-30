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
统一 Info 导出协议为 `9.0.0`，artifact manifest 版本为 `9`，snapshot payload 版本为 `7`，录制协议使用 `0.3.0`。每个 script 步骤对应一个对象，框架字段使用 `$ruleId`、`$goal_before`、`$goal_after` 和 `$branches`；配置及实际契约通过产物清单关联。旧缓存需重新运行 Lake facet 构建，详见[统一配置与导出说明](#统一-info-配置)。
详细使用说明见 [PS4HTML 文档](tools/ps4html/README.md)。

普通 `lake build` 和 IDE 默认只检查证明。`#page theorem` / `#page lemma` 生成原生 Lean theorem，
不录制步骤、不导出页面，也不启动 LaTeX 或计算资源构建；五种 Info 命令跳过配置工作。`lake build MyLibrary:ps4html`
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

#page text r#"
= Introduction <introduction>

This page contains a recorded theorem. See @thm:mainResult.
"#

#page theorem mainResult (P : Prop) (h : P) : P := script
  assumption
theorem_info mainResult { name := "Main Result" }

#page references

#page end
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
| `let x := value` / `let x : T := value` | 引入局部定义，并在该步骤记录类型和值 | `let` | 提供类型注解时，值必须具有该类型 |
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
概略产生的目标分支可以使用 `| case => …` 或匿名分支 `·`，两者可以嵌套、混用。匿名分支聚焦下一个未完成目标，必须在分支内关闭该目标；录制时保留目标的完整标签（如 `left` / `right`），必要时为匿名分支分配唯一导出标签。`claim` 的第一个匿名分支证明 `proof`，之后的步骤或第二个匿名分支在包含新假设的上下文中继续证明。

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
| `cite proof` | 从命题的证明中收集证明常量引用，不改变当前目标 |

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
#page theorem demo_remark {P : Prop} (h_P : P) : P := script
  remark "这是一则简单的证明"
  assumption
```

##### LaTeX (SVG)

证明内部提供统一的 `latex` 元数据策略. 它与页面组件 `#page latex` 一样接收 metadata 和任意
LaTeX 源码，在录制时调用本地 LaTeX 工具链生成 SVG，并把 metadata、源码和 SVG 一同写入
证明树。例如:

```lean
#page theorem proofWithDiagram (P : Prop) (h : P) : P := script
  latex (title := "推导图", label := "proof-diagram") r#"
    \begin{tikzpicture}
      \draw[->] (0,0) -- (1,0);
    \end{tikzpicture}
  "#
  assumption
```

为了保证预编译器顺利工作，请确保 TeXLive 已本地安装。这里是证明内部策略；页面级任意
LaTeX 使用后文的 `#page latex` 命令。

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

基础策略的 `ProofScript.Builtin.Script` 集中提供执行、注册、记录器与页面展示配置；公共 `ProofScript` 入口导入全部默认配置模块，其中的 Info 命令只在页面模式生效。模块职责见[统一 Info 配置](#统一-info-配置)。当前包装按字母顺序包括：

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

参数统一由 `RecordValue α` 实例解释，其中 `α` 就是宏绑定的实际 Lean 类型。内置支持 `TSyntax \`term`、`TSyntax \`ident`、`TSyntax \`str`、`TSyntax \`num`、`location`、`rwRuleSeq`、`simpArgs`、`optConfig`；`Array`、`Option` 和 `Syntax.TSepArray` 会自动组合元素实例。自定义语法类别只需为自己的 `TSyntax` 类型定义实例。匿名且未支持的语法会保持自动录制不可用，应改用手写 recorder，不会静默转换成文本；`num` 输出 JSON 数字，按 `term` 解析的数值仍输出 Lean 表达式引用。

声明配置包括：

| 选项 | 含义 |
| --- | --- |
| `intro`、`clear` | 标记参数在执行后或执行前可用。 |
| `strategy` | 标记有证明分支的策略。 |
| `continuation` | 使用目标名称指定回到父录制流程的目标，例如 ``continuation := `rest``。 |

不再提供 `params`、逐参数时机、上下文选择或字段重命名。需要自定义读取顺序或字段名时，使用手写 recorder。参数直接使用实际绑定类型的 `RecordValue α` 实例读取。

```lean
script_macro finishRule
  "finish" proof:term => `(tactic| exact $proof:term)

script_recorder finishRule => do
  record_param "evidence" proof
  execute_tactic
```

对于已 elaboration 的 calc 结果或生成媒体等输出，可用 `script_recorder <id> => ...` 自定义捕获逻辑。录制器直接获得原 `script_macro` 或 `script_elab` 声明中的参数绑定：

```lean
open ProofScript

script_recorder finishRule => do
  Lean.Elab.Tactic.withRollback do
    record_goal "$goal_before"
    record_param "evidence" proof
  execute_tactic
  record_goal "$goal_after"
```

ID 选择对应注册；参数绑定和策略关键字都来自原注册声明。实际写入决定可用的输出字段，不再使用单独的输出字段声明或 schema；自定义参数读取器和已有值的转换统一实现 `RecordValue.record`。缺少类别实例或参数 parser 不支持自动录制时，若没有绑定手写 recorder，实际录制只发出警告，策略仍正常执行。对应步骤导出保留 `$ruleId: "ProofScript.unrecorded"` 和原策略关键字 `name`；策略分支继续独立录制。PS4HTML 将该步骤显示为红色“未导出数据”框。

`script_info` 的模板使用字段对象，配置读取证明所属模块及其传递导入模块的最终状态。证明或 `#page end` 后的本地更新也作用于本模块证明；下游覆盖作用于下游内容。模板按语言合并，首项为语言缺失时的回退；导入后修改规则使用完整 ID，例如 `script_info MyRules.finishRule`。渲染端读取实际输出字段名，支持 `${rules_before.0.expression}`、`${loc_before.hypotheses}` 等嵌套路径。Lean 原样保存模板字符串，包括未知路径、`${}` 和未闭合的 `${...`；仍检查模板外层结构及其与普通/策略注册的类型是否相符。占位符解释与错误处理由渲染端决定。PS4HTML 在消费实际步骤时检查缺失字段和无效路径，包括 bundle 加载时的数据校验；空或未闭合占位符作为文本显示。缺失的 optional 参数导出为 `null`，捕获错误会中止步骤。文本和结构化值均进行 HTML 转义。特定 renderer 使用最终合并配置；相同关键字的重载须使用不同 ID。

公共 DSL 与运行时接口由 `import ProofScript.Script.Recording` 导出；`import ProofScript` 还包含脚本声明命令。`script_recorder foo => do ...` 自动在主目标上下文中开启一个录制对象，块内是普通 Lean `TacticM` 代码，可以使用变量、条件、循环以及自定义执行逻辑。录制器本身不隐式添加目标快照或执行 tactic，也支持只记录元数据。

| 语句 | 含义 |
| --- | --- |
| `record_param "field" value` | 在 `ProofScript.ParamRecorder` 实例 scope 中记录语法参数。 |
| `record_param "field" value (goal := name)` | 解析 `Name` 类型的目标名称，并在该目标上下文中记录参数。 |
| `record_value key value` | 在 `ProofScript.ValueRecorder` 实例 scope 中记录已有值，始终不收集引用。 |
| `record_goal "field"` / `record_goal "field" (goal := name)` | 记录主目标或按名称解析的指定目标。 |
| `execute_tactic` | 使用本次调用选中的原始策略及原始参数执行。 |

例如，先捕获一个假设，写入已有元数据变量，清除假设后再尝试捕获：

```lean
open Lean ProofScript

script_macro snapshotThenClear "snapshot_then_clear" h:ident => `(tactic| clear $h:ident)
script_recorder snapshotThenClear => do
  Lean.Elab.Tactic.withRollback do
    record_goal "$goal_before"
    record_param "evidence_before" h
  let moduleName := toJson (← getEnv).mainModule
  record_value "module" moduleName
  execute_tactic
  Lean.Elab.Tactic.withRollback do
    record_goal "$goal_after"
    record_param "evidence_after" h
```

`record_param` 和 `record_value` 共用内部写入函数，但各自仅为该次调用打开不同的实例 scope：`ProofScript.ParamRecorder` 提供语法参数读取器，`ProofScript.ValueRecorder` 提供已有值转换。共享的 `Array`、`List`、`Option` 实例由元素所属 scope 决定是否可用。这只是默认实例可见性约定，并非严格的类型限制；显式打开 scope 或提供其他实例会改变可接受的类型。语句顺序决定读取到的 Lean 状态。真正的读取或转换失败会附带字段名报错并继续向外抛出，不会伪装成 `null`；缺失的 `Option` 值属于正常结果，仍记录为 `null`。每项记录会恢复临时 elaboration 状态，再提交值。若后续记录失败时需要回滚整个语句序列的字段，请用 `withRollback` 包住这段序列。录制只保存值，包含定理常量的表达式及嵌套容器也不收集文献引用；`dependencyCollection` 不影响这些操作。字段名直接传给录制语句；前后快照应使用不同字段名。

`script_recorder` 统一使用 `script_recorder foo => do ...`。生成器读取原始 script 注册的 `strategy` 配置，自动管理录制对象，并为 strategy 在 body 成功后准备分支。

`record_value` 支持 `RecordedValue`、`Json`、`String`、`Bool`、`Nat`、`Int` 和 `Expr`，数组、列表、optional 会组合其元素的实例。`RecordValue.record value context` 返回 `TacticM RecordedValue`，由实例决定记录哪些事实；容器把上下文传给元素，纯值实例可忽略它。`none` 保留调用处上下文，显式目标在转换期间成为当前目标；带名称的 `record_param` 宏先解析名称，再把目标传给内部写入函数。特殊需求由手写 `script_recorder` 选择捕获逻辑和时机。转换过程隔离执行，失败时必须报错。若需在执行前捕获、执行后写入，使用 `recordValueFrom` 保存完整值：

```lean
-- 放在 script_recorder 的 do 块内：
let saved ← recordValueFrom "evidence" (expression h.raw)
execute_tactic
record_value "evidence" saved
```

这段代码保留执行前读取的值，再在执行后写入。文献引用通过独立于录制值的路径收集。

`RecordedValue` 是纯数据，有普通 JSON、原生 `Lean.Expr`、数组和对象四种形式。`RecordedValue.expression expr` 原样保存表达式及其已有元数据，不查询上下文。默认 `Expr` 转换调用 `recordExpression`，实例化已赋值的表达式及 universe 元变量，再沿原结构始终将自由变量名称、命名类型描述和可获得的可信源码位置添加为原生标量 `MData`。完整声明类型、局部定义值及应用 binder 描述不再收集。容器组合元素的转换结果；已有 `RecordedValue` 原样通过。

录制格式为 `0.3.0`。`recordedProofJson` 在最终证明导出时统一分配节点编号，输出节点表及显式 `expressionRoots`；其他独立数据主体使用相同的纯编码入口 `encodeOwner`。标量元数据导出为 `mdata.data`，唯一结构子项为 `mdata.expr`；语法值及空包装不导出。PS4HTML 仅从根清单进入表达式图，普通 JSON 保持用户数据语义。渲染配置依赖沿原生表达式结构和有效的命名类型注解解析，不展开声明；录制参数和值不写入文献引用暂存区。结构见[证明 JSON Schema](docs/schema/recording-proof.schema.json)。旧缓存须重新运行 `lake build MyLibrary:ps4html`，`ps4html make --cache` 不迁移旧数据。

自定义转换在捕获时决定输出；需要默认表达式读取时使用 `recordExpression`：

```lean
structure Evidence where
  term : Lean.Expr
  label : String

namespace ProofScript.ValueRecorder
scoped instance : RecordValue Evidence where
  record value _ := do
    return .object [
      ("term", ← recordExpression value.term),
      ("label", .plain (Lean.toJson value.label))]
end ProofScript.ValueRecorder
```

自行提供表达式和原生 `MData` 时，直接返回 `RecordedValue.expression expr`。`record_value "term" expr` 使用默认 `Expr` 实例，`record_value "term" (RecordedValue.expression expr)` 保留给定表达式。默认读取器添加 `ProofScript.userName`、`ProofScript.type` 及可获得的 `ProofScript.sourceFile/sourceStart/sourceStop`。命名类型描述是自由变量和绑定节点上的字符串；其中 `decl:<声明名>` 还会冻结该声明的 `def_info` 以供命名，不增加文献引用。所有标量元数据（包括自定义键）始终导出，没有启用开关。嵌套同名键由外层优先；源码范围只属于对应出现位置，不继承给结构子项。专用 `let` recorder 在引入定义时输出 `name`、`type`、`value`，后续变量引用不复制这些字段或生成声明悬停提示。

`def_info.auto_arity := true` 在 Lean 冻结配置时按声明的原生 binder 转成数字索引，渲染器只消费这些索引。使用 `auto_arity := false` 时，模板索引直接对应完整的原始应用参数。动态 `#*` 模板不再支持。

策略也使用 `script_recorder foo => do ...`。证明分支标签由执行器提供，命名 continuation 来自注册信息，手写 recorder 无需读取或重复传入这些路由信息：

```lean
script_macro rememberTrue (kind := strategy, continuation := `rest)
  "remember_true" h:ident => `(tactic| script_claim $h:ident : True)

script_recorder rememberTrue => do
  record_goal "$goal_before"
  execute_tactic
  record_param "hypothesis" h (goal := `rest)
```

块在 body 成功后自动准备分支，body 提前 `return` 也不会跳过收尾。收尾会重新解析最终目标，并在关闭录制对象前调用 `prepareBranches`；异常时回滚整个块，不准备分支。之后由 script 执行器推进分支证明，并将其合并回父步骤。

省略目标时使用调用处的上下文。`record_param` 和 `record_goal` 统一通过 `(goal := name)` 指定 `Name` 类型的目标名称，例如 ``record_param "h_after" h (goal := `rest)`` 或 ``record_goal "rest_goal" (goal := `rest)``。名称先做完整匹配，再做唯一后缀匹配。目标不存在或名称有歧义都会报错。

普通自动录制器写入 `$goal_before` 和 `$goal_after`，策略自动录制器只写入 `$goal_before`；每个表达式字段保存原生表达式及其读取函数选定的注解。手写录制器通过 `record_goal` 写入目标。没有剩余目标时，返回 `null`；普通值写入始终不添加文献。模板路径应与对应 recorder 实际提供的字段匹配。

内置 `cases_by` 在执行前记录 `subject`，`contra` 在执行后记录 `hypothesis`。这两个展示值使用 `record_value`，其 `h` 参数使用 `record_param`。`embed` 记录实际参数和目标快照，回放时由内部 recorder 记录证明数据；这些录制操作都不收集文献引用。

默认执行前捕获使用 `<参数名>_before` 字段名，内置模板相应使用 `change.equation_before`、`exact_proj.value_before` 和 `provide.data_before`。`let` 从新引入的局部定义读取 `value` 作为参数捕获，`name`、`type` 作为普通值写入；`calc` 和 `infer` 在各自的捕获时机组装 `init`、`chain` 并作为同一事务提交。字段和验证样例见[第六阶段迁移说明](docs/Script-Binding-Phase6-zh.md)。

普通自动录制器对普通参数在执行前后分别捕获；`intro` 参数只在执行后捕获，`clear` 参数只在执行前捕获。strategy 自动录制器在执行前捕获非 `intro` 参数，并跳过 `intro` 参数。手写 DSL 直接由语句位置决定时机。用户参数名和录制键名必须非空，且不能以 `$` 开头；其他自定义字段允许写入，展示所需字段及值结构由 PS4HTML 检查。同一步骤内后一次成功写入同名字段会覆盖前一次值；写入失败时保留此前的值。声明阶段检查无效名称以及 `intro` / `clear` 冲突。

块成功时保留 tactic 执行结果，失败时回滚 Lean 状态、录制值和文献引用。嵌套块预留固定录制位置，内层结束后外层仍可继续写入；最后一个目标关闭后也可记录纯数据。LaTeX 编译、资源文件写入等外部 IO 不随 Lean 状态回滚。需要自定义执行时，直接用普通 `TacticM` 操作代替 `execute_tactic`；可复用的录制辅助函数声明 `[RecordingStep]`，使用调用方的录制作用域。

参见可运行的[录制 API 示例](examples/recording/RecordingAPI.lean)。新增类别在 `ProofScript.ParamRecorder` 命名空间中定义 `RecordValue (TSyntax \`categoryName)` 的 `scoped instance`，数组和 optional 输入自动组合该实例。

暂不支持使用像 `macro_rules` / `elab_rules` 一样的方式定义脚本策略.

### 导出证明树

使用 `#page theorem` 或 `#page lemma` 声明页面定理，再运行 `lake build MyLibrary:ps4html` 导出。两者在页面 JSON 中分别使用
`"theorem"` 和 `"lemma"` 标签。
发布后的证明数据位于 Lean 项目的 `.PS4HTML/inputs/<包名>/<库名>/.ProofScript/proofs/`。
每个证明树顶层都包含 `schemaVersion` 和完整 Lean 源码 `code`；脚本模式证明树还包含表达式表
`expressions`、根路径清单 `expressionRoots` 与录制的步骤数组 `proof`。数组中的每项都是一个步骤对象，包含 `$ruleId`、捕获字段和策略的 `$branches`；每个分支的 proof 使用相同格式。普通默认录制器记录的 `$goal_before` / `$goal_after` 为表达式引用或 `null`；策略默认录制器只记录 `$goal_before`。

`:= script` 中直接使用无前缀 DSL 名称，框架会自动补全 `script_` 前缀并检查每一步，在页面构建时录制；`:= by` 接受普通 Lean
策略，但不能使用 ProofScript 的脚本策略。后者只保留 `schemaVersion`、`module` 与完整 `code`，不输出
`expressions`、`expressionRoots` 或 `proof`。文献引用收集独立于录制，参见[自动文献采集](#自动文献采集)。

`#page theorem` 和 `#page lemma` 在所有模式下都先通过 `script_theorem_impl` / `script_lemma_impl` 生成不同名的内部 `def`，同步执行一次证明，再用原生 theorem 直接引用它，保留 IDE 的编译通过标记。证明失败统一提示“证明存在错误”。页面元数据、录制文件和依赖身份仍使用公开定理名。
普通模式复用执行版 `script` 或原生 `by`，跳过录制和页面导出；两种模式都会检查 `cite` 的完整参数是否为命题证明，不要求预先配置 `theorem_info`。
页面模式通过构建选项 `proofScript.pageBuild` 在内部 `def` 中执行录制器，再按模块最终配置导出；同一模块不能中途切换模式。
五种独立 Info 命令在普通模式也跳过字段解码、语义校验和配置登记，但语法仍须合法；两种模式都会保留编辑器语义信息，包括尽力解析已有元数据目标。显式调用底层 recorder API 仍可录制。

定理依赖图的上半部分可以包含 `#page lemma`，每个 lemma 也有自己的依赖图；下半部分仅列出使用当前声明的 theorem，不列出 lemma。真实依赖数据仍完整保留。

仓库默认 `lake build` 构建 ProofScript 库。`lake build MyLibrary:ps4html` 自动启用页面模式，重编译所需用户源码、ProofScript 框架及提供 Info 配置的依赖，恢复默认展示与用户配置。首版仍完整重录这些源码模块；Mathlib 等不含所需页面或 Info 数据的基础依赖复用缓存，普通 `.lake/build/` 保持不变。


## ProofText

`#page text` 接受一个 Lean 字符串字面量, 并作为专属的轻量标记语言 ProofText 进行解析, 其在语法上与 Typst 大致相近.

````lean
#page text r#"
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

定理元数据统一通过 `theorem_info` 配置，目标须为已经存在的普通 Lean theorem、`#page theorem` 或 `#page lemma` 声明。它也设置录制定理自身的标题与归属，可以放在 `#page end` 之后：

```lean
theorem referencedTheorem (P : Prop) (h : P) : P := h

theorem_info referencedTheorem {
  name := "Displayed theorem name",
  tags := ["algebra", "foundational"],
  customField := "custom value"
}
```

```lean
#page theorem mainResult (P : Prop) (h : P) : P := script
  assumption
theorem_info mainResult { name := "主要结果", tags := ["algebra"] }
```

定理声明与元数据更新是独立命令。原生 `/-- ... -/` 文档注释仍供 Lean 和编辑器使用。`name`、`tags` 控制展示，`project` 直接保存 `String` 类型的项目名；显式项目赋值优先，否则在最终消费时选择首次登记模块本地唯一项目，本地无项目时选择该模块传递导入闭包中的唯一项目。录制定理在定义模块登记，普通 Lean 声明在首次 `theorem_info` 所在模块登记。多个候选项目要求显式指定 `project`；`none` 或 `reset` 明确解除归属。未知字段进入 `extra` 对象。五种 Info 命令都允许重复更新，并支持已知字段检查、`none` 与 `reset`。定理引用和页面锚点使用 Lean 声明名，跨模块引用时使用完整限定名。

### 自动文献采集

`record_param` 和 `record_value` 都只保存值，包含定理常量的表达式及嵌套容器也不增加文献引用；`dependencyCollection` 不影响参数和值的录制。渲染配置依赖单独解析，定理导航读取最终证明事实。

页面构建时，`#page theorem` 和 `#page lemma` 在证明完成后统一收集自动引用，`script` 与 `by` 使用同一套扫描。扫描展开生成的 helper 和 compiler auxiliary proof，保留用户声明作为依赖边界，并且只保留声明类型满足 `Meta.isProp info.type` 的常量，生成 `isDependency := true` 的引用。`def MyProp : Prop := ...` 会被排除，类型本身是命题的证明定义会被保留。`dependencyCollection false` 关闭自动引用收集。

`cite` 始终先检查完整参数的类型 `Meta.isProp (inferType expression)`，再按相同的声明类型规则过滤表达式中的常量。参数可以是证明定义、应用、lambda 或局部证明，不要求预先配置 `theorem_info`。收集结果带有 `isDependency := false`，在 `dependencyCollection false` 下也写入动态暂存区。页面定理事务还会将其独立保存到 `DeclarationFacts.proofRefs`，清空页面暂存区不会丢失这些持久化引用。同名引用合并时自动依赖优先；事务失败时恢复此前引用和事实。

命名 proof artifact 导出完整 `proofRefs` 数组，包含手动引用及源项目之外的引用，每项都有无损 Lean 名称 `name` 和必需的布尔字段 `isDependency`。导航字段 `proofDependencies` 仅保留自动引用中最终项目与源定理相同的名称，证明定义与定理适用相同规则；`dependencyCollection false` 因而也会关闭自动导航边。`proofFactsDigest` 同时覆盖两个数组，消费端按冻结的目标元数据校验导航投影。manifest `9` 要求这些字段，旧缓存须通过 `lake build MyLibrary:ps4html` 重建。

每份证明和页面组件读取所属模块及全部传递导入模块的最终元数据；`#page references` 在组件位置收集声明身份，在最终导出时解析展示信息。本模块后置的 Info 命令同样影响前面的内容，包括 `#page end` 后的更新。复用上游证明产物时保留上游模块快照，下游覆盖不会反向修改它。

下面的命令局部关闭自动采集，同时保留手动引用：

```lean
theorem citedResult : True := True.intro
theorem_info citedResult { name := "引用结果" }

set_option dependencyCollection false in
#page theorem manualReference (P : Prop) (h : P) : P := script
  cite citedResult
  exact h

#page references
```

在页面的任何位置, 使用命令 `#page references` 即可把当前暂存区中的全部文献信息作为页面组件
输出, 此操作将清空文献暂存区. 该命令不接受文件名, 也不会单独写出 references JSON.
没有配置定理元数据的引用仍会被收集，但不会出现在该展示组件中。

[录制示例](examples/recording/README.md) 展示仅用于展示的定理参数和显式引用，[站点依赖页](examples/site/PS4HTMLDemo/Dependencies.lean) 展示自动引用与关闭自动收集后的手动文献。这里的文献引用与 Lean 编辑器的符号引用分别处理，参见 [IDE 支持](docs/IDE-Support-zh.md)。

## 其它页面组件

### 任意 LaTeX

`#page latex` 接收任意 LaTeX 源码并在编译期生成 SVG. `title` 必填, `label` 可选, 其它字段会
保存在 metadata 的 `extra` 中:

```lean
#page latex (
  title := "交换图",
  label := "commutative-diagram"
) r#"
\begin{tikzpicture}
  \draw[->] (0,0) -- (1,0);
\end{tikzpicture}
"#
```

### 图片资源

`#page figure` 接收包含后缀的相对图片资源路径. ProofScript 只导出路径和扩展名, 不读取或复制文件:

```lean
#page figure (
  title := "架构图",
  label := "architecture",
  width := "wide"
) "assets/architecture.png"
```

### 自定义页面组件

使用 `page_component` 定义页面组件命令（由 `import ProofScript` 或
`import ProofScript.Page.Component.Command` 提供）：

```lean
open Lean ProofScript

page_component "myWidget" source:str => do
  when_page_build
    let value := json% { "text": $(source.getString) }
    addPageComponent source.raw "myWidget" value

#page myWidget "Hello"
```

首个字符串是 `#page` 后的组件名称，`end` 保留给 `#page end`，不能注册为组件。
其后支持原生 `elab` 的语法参数，包括可选参数、重复参数和 `sepBy`。组件名不会额外成为普通
Lean 标识符的保留字；相同或重叠的语法仍沿用原生 `elab` 的重载和解析规则。

`=>` 后的代码类型为 `CommandElabM Unit`，会在两种模式下执行。`when_page_build` 是组件
定义上下文专用的 `doElem` 语句，只有它的缩进块在页面模式下执行，退回外层缩进后继续普通代码。
块内开头的纯计算也会被延迟；块内局部变量不能在块外使用。可在其前后登记 IDE 信息，例如：

```lean
page_component "myFigure" metadata:componentMeta path:str => do
  addComponentMetadataInfo metadata.raw
  when_page_build
    let value := json% { path: $(path.getString) }
    addPageComponent path.raw "myFigure" value
```

校验、JSON 构造和资源 IO 应放进 `when_page_build`，组件 JSON、标签及登记动作由组件作者决定。
`#page end` 在两种模式下都会关闭当前模块的页面；其后的组件在入口立刻报错，不执行任何组件代码，
包括 `when_page_build` 外的部分。页面模式额外持久化页面草稿；普通验证不生成草稿。后续普通 Lean
声明和 Info 命令仍可执行，Info 继续参与最终导出。关闭状态不会通过 `import` 传播到下游模块。

`figure`、`latex`、`text`、`references`、`#page computation`、`#page theorem` 和 `#page lemma`
都使用统一的页面组件入口与页面关闭检查，各自保留必要的字段校验和证明/计算逻辑。旧的 `@figure`、
`@latex`、`@text`、`@references`、`@computation`、`@theorem`、`@lemma` 和 `page_end` 不再提供别名。
底层 `addPageComponent` 仍可直接使用，但不能代替命令入口
对整段动作的保护。参见[命令定义](ProofScript/Page/Component/Command.lean)和
[组件接口](ProofScript/Page/Component/Core.lean)。

需要嵌入式计算时，优先使用内置 `#page computation`：它接收组件元数据、下游 renderer ID、Lean 函数声明和
renderer 专用的 JSON manifest：

```lean
def chooseOffset (large : Bool) : Nat := if large then 128 else 112

#page computation {
  metadata := (title := "有限计算", label := "finite-computation"),
  renderer := "my-renderer/table-v1",
  function := chooseOffset,
  payload := r#"{"execution":{"backend":"table"},"results":[112,128]}"#
}
```

输出包含声明全名、可读类型、函数实现体和结构化 Lean 表达式表。这些字段是来源信息和中间产物，
不承诺 Lean 编译器内部 IR 的浏览器 ABI；实际执行方式由版本化 renderer ID 和 manifest 共同决定。
详见 `docs/Frontend-Computation-Handoff-zh.md`。

函数来源信息使用带标量 `MData` 的原生表达式和独立的纯编码边界。默认命令及 `ComputationFunction.encode` / `ComputationComponent.encode` 输出 `function.recordingVersion = "0.3.0"`、函数自有表达式节点表及 `expressionRoots`；根路径相对于 `function`。声明名称和可读类型是该 recorder 明确输出的普通字段。消费者拒绝缺失或旧函数版本并提示重新构建页面。组件、pending manifest、bundle 版本仍为 `0.0.0`，`proofscript-json-v1` 执行 ABI 不变；finalizer 保留完整 function 数据。

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

前端 renderer 可先使用 [Fibonacci 示例](examples/site/PS4HTMLDemo/Fibonacci.lean)做端到端测试。

## 统一 Info 配置

五种命令的全部保留字段、默认值、模板语法和完整示例见 [Info 命令使用手册](docs/Info-Commands-zh.md)。

五个命令只在页面模式执行配置工作。普通构建和 IDE 中不做字段解码与语义校验、不写入持久化配置事件；语法解析及模块模式一致性检查仍然生效。已有目标和已知字段仍支持跳转与引用联动，未找到的元数据目标可以跳过，详见 [IDE 与语言服务器支持](docs/IDE-Support-zh.md)。下列规则与示例均描述页面模式。

页面模式下，五个命令共用强类型模型、字段解析、增量更新和导出协议：

| 命令 | 模型（`ProofScript`） | 目标 |
| --- | --- | --- |
| `project_info` | `ProjectInfo` | 非空项目名字符串；省略目标时更新活动项目 |
| `theorem_info` | `TheoremInfo` | 已声明的 Lean 定理名 |
| `script_info` | `ScriptInfo` | 已注册的完整脚本 ruleId，或本模块的注册 ID |
| `def_info` | `DefinitionInfo` | 已声明的 Lean 常量 |
| `phrase_info` | `PhraseInfo` | 非空短语键 |

命令可以重复执行，只更新写出的字段；已知字段的类型错误、同命令重复字段及未知嵌套字段会报错。未知顶层字段保存到 `extra`，支持字符串、数值、布尔、null、数组和对象。可显式写 `extra := { "review.status" := "checked" }`，其键不会覆盖内置字段。

```lean
project_info "课程笔记" { title := "Notes", authors := ["Alice"], edition := 1 }
project_info "课程笔记" { title := "Revised notes", edition := 2 }
 script_info «rfl» { display := true, reviewed := true }
def_info Nat { var_name := "n" }
phrase_info "forall" { template := [{ lang := "en", content := "${body} for every ${binder}" }] }
```

项目 ID 统一使用非空字符串字面量，例如 `"课程笔记"`，按完整文本匹配；命名空间和 `open` 不改变项目 ID。定理通过 `project := "课程笔记"` 选择已配置的项目。

`def_info` 没有必填字段：`{}` 保留已有设置，`var_name` 控制该声明类型下匿名变量的前缀。前缀为空时取声明名最后一个分量的首字母。内置配置为 `Nat/Int → n`、`Rat → q`，Mathlib 配置为 `Real → x`。证明变量固定使用 `h`，不读取 `theorem_info`。可用名称始终保留；自动名称按前缀共享计数、从 1 开始，显示为 `\textcolor{gray}{n_{1}}`；未赋值元变量显示为 `\textcolor{gray}{?}`。类型描述、绑定身份和模板消费方式详见[变量系统说明](tools/ps4html/Variable-System.md)。

省略字段保留已有值；`none` 是 Option 字段的空值；`reset` 屏蔽继承值并恢复字段默认值，无默认的必填字段恢复为未提供。普通列表和 styles 整体替换；template 按语言合并，同语言替换保留位置，新语言追加。`extra` 按键更新，单键 `reset` 删除该键。

Lean 按实际导入图合并：同模块后写覆盖前写，后代覆盖祖先，独立分支的不同字段可合并；同字段不同值保留冲突及来源，消费前可由本地更新消解，不能依靠调整导入顺序选值。未被消费的不完整配置可以保存。每份证明和页面组件使用所属模块及全部传递导入模块的最终配置，独立 proof 使用相同规则。`#page end` 关闭页面内容收集，后面的 Info 仍参与最终导出。

### 模块与查询接口

`import ProofScript` 提供脚本、页面和全部默认展示模块，其中的 Info 配置只在页面构建时登记。按需导入可以使用 `ProofScript.Info`（五种模型及命令）、`ProofScript.Script.Registry`（纯注册）、`ProofScript.Script.Command`（脚本声明）、`ProofScript.Builtin.Script`（基础策略的执行、注册、记录器与展示）、`ProofScript.Mathlib.Info`（Mathlib 展示）、`ProofScript.Page.Command`（页面集成）。`Mathlib.Scripts` 承载 Mathlib 策略的执行实现与注册，展示配置位于 Mathlib.Info。

模型使用 `ProofScript.ProjectInfo` 等完整名称；源码位置使用 `ProofScript.SourceLocation`。模型、schema、codec、查询及显式底层录制 API 在两种模式均可用，但查询不能恢复普通模式跳过的配置。声明命名空间与模块路径相互独立：`ProofScript.Info` 仍是导入模块，其声明直接位于 `ProofScript` 下。以下查询假定页面模式中已登记 `"Notes"` 项目；领域查询显式接受 `ProofScript.Query`，不能借导出器自身的 mainModule 推断配置视图：

```lean
open Lean Elab Command ProofScript
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



## 页面导出

页面模式下，`#page end` 关闭页面内容收集并将草稿持久化到 `.olean`，不写页面 JSON；之后的页面组件在两种模式下都会在执行前报错。最终导出直接根据草稿与所属模块的完整 Info 生成页面 JSON，包括 `#page end` 后的配置，可重复导出覆盖页面而不读取旧页面文件。完整站点使用 `lake build MyLibrary:ps4html` 构建。Info 协议为 `9.0.0`，artifact manifest 版本为 `9`，snapshot payload 版本为 `7`，录制协议为 `0.3.0`，调用契约版本为 `2`，不再包含输出字段声明；`info/index.json` 是包含文件摘要、schema、快照和调用契约关联的完成清单。配置和页面草稿可从页面构建的 `.olean` 重建；快照查询仅包含所属模块 `module`，拒绝旧的历史边界字段。普通验证 `.olean` 中跳过的配置必须通过页面重编译恢复；proof/resources 在编译时生成，页面 JSON 在导出时生成。旧 manifest 也须通过 Lean 重新构建。只读缓存使用 `ps4html make --cache`；不完整或版本不匹配的缓存会被拒绝，需要重新构建。

## 环境要求

### 必需环境

已完整安装 Lean + Lake + Elan

### 可选 LaTeX 环境

如果需要使用页面组件 `#page latex` , 系统 `PATH` 中还必须存在:

```bash
latex --version
dvisvgm --version
```

## 当前限制

- `script` 只允许带 `script_` 前缀的已注册策略，不支持任意 Lean tactic，也不支持 bullet `·`。
- 自动 recorder 只支持有限的 parser 参数形式；复杂策略需手写 `script_recorder` 才能完整导出数据，否则发出警告并显示“未导出数据”。
- `complete_induction` 当前是自然数强归纳模板。
- 文献列表展示已注册 `theorem_info` 元数据的声明。自动引用来自完成后的证明；参数和值的录制不产生文献引用。
- ProofText 引用在 elaboration 时只检查语法，不验证引用目标一定存在；跨页面索引应由下游消费者建立。
- ProofText 是小型专用语言，不提供完整 Markdown/Typst 能力。
- 每个模块保留一份页面草稿；`#page end` 之后的组件在两种模式下都会在执行前报错。最终页面可重复导出。
- LaTeX 组件要求本机 `latex`、`dvisvgm` 和相应 TeX 宏包，且编译失败会中断 Lean elaboration。
- 页面 source 路径当前通常为绝对路径；源码位置使用 UTF-8 字节偏移。
- Lean 表达式 JSON 与 Lean 内部 AST 紧密相关，仍属于可扩展接口，跨 Lean 版本使用时应谨慎。
- 当前 universe level 的 `max`/`imax` 序列化实现存在重复键问题，不应依赖其左右操作数能够被完整区分。

## 相关文档

- [English README](README.md)
- [ProofText 中文语法](docs/ProofText-Syntax-zh.md)
- [ProofText English syntax](docs/ProofText-Syntax.md)
- [录制 API 简化方案](docs/Recording-API-Simplification-Plan-zh.md)
- [Recording 模块结构](docs/Recording-Architecture-zh.md)
- [脚本绑定重构第五阶段](docs/Script-Binding-Phase5-zh.md)
- [录制证明 JSON Schema](docs/schema/recording-proof.schema.json)
- [录制函数 JSON Schema](docs/schema/recording-function.schema.json)
- Info 模型与快照 Schema 随完成导出生成到 `.ProofScript/info/schema/`。

## PS4HTML 站点生成器

PS4HTML 已作为站点生成工具集成在本仓库的 [`tools/ps4html/`](tools/ps4html/) 中。它消费 ProofScript 导出的页面、证明树和资源；证明本身仍由 Lean 检查。主要功能包括：

- 按 Lean 模块生成 HTML 页面、项目入口、模块导航、跨页引用、定理依赖导航和分组文献。
- 渲染 ProofText、定理与引理、结构化证明步骤和分支、源码视图、代码高亮、图片及 LaTeX 导出的 SVG；未知规则或资源错误有可见的回退与诊断。
- 通过 Lean2TeX 将表达式转换为 TeX，并配置声明宏和变量命名；支持中英文证明文本、KaTeX 公式显示及变量联动高亮。
  - 编排 Lean 和嵌入式 Lean/Wasm 计算构建，提供浏览器 Worker 组件、本地预览服务器与 `lean2tex-report.json` 诊断报告。策略用 `script_info` 设置展示，产物清单为 proof 选择冻结配置和实际调用契约；PS4HTML 据此排版，缓存渲染不执行 Lean。例如 `script_info «renderCalc» { renderer := «calc» }` 选择计算链渲染器。

在仓库根目录执行 `python3 -m pip install -e ./tools/ps4html`（Python 3.11+），然后到 Lean 项目中运行 `lake build MyLibrary:ps4html`，使用 `ps4html serve` 预览 `.PS4HTML/build/`。`ps4html make --cache` 可直接渲染已有导出，不重新编译 Lean。计算工具链要求与现有限制详见 [PS4HTML 使用说明](tools/ps4html/README.md)和[完整示例](examples/site/README.md)。
