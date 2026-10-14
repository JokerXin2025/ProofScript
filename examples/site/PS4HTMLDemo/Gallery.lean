import PS4HTMLDemo.Library

set_option linter.defProp false

open PS4HTMLDemo.Library

@text r#"
= PS4HTML 页面组件总览 <overview>

这个项目完全由 *ProofScript* 源码生成。PS4HTML 读取模块页面 JSON 和独立证明树，
再构建最终 HTML。这里同时展示 _斜体_、*_粗斜体_*、~~删除线~~、
__下划线__、==高亮文本==、上标 x^2^、下标 a~n~、`inline code`，
以及行内数学 $\forall n \in \mathbb{N},\; n + 0 = n$。

普通文本中的美元符号会保持为字面量：价格是 \$5，而不是数学公式。
你也可以访问 [ProofScript 仓库](https://github.com/JokerXin2025/ProofScript)，或跳转到
@<lists>、参考跨模块定理 @thm:PS4HTMLDemo.Library.andLeft，以及页面图片 @fig:component-preview。

源码中的普通换行会保留在同一个语义段落中，空行则开始一个新的段落。

== 二级标题 <typography>

=== 三级标题

==== 四级标题

不同级别的标题共同组成文档层次，带标签的标题可以成为跨页面引用目标。

== 列表系统 <lists>

无序列表使用实心圆点：

- 页面组件保持 Lean 源码中的顺序
- 所有页面加载完成后建立 label 索引
- 未解析的引用会保留明显提示

有序列表使用 `+`，也可以通过 `n.` 强制指定某一项的序号：

+ 首先由 Lake 编译 Lean 项目
+ 然后 ProofScript 写出页面和证明树 JSON
5. 这一项被强制指定为第五项
+ 下一项自然延续为第六项

== 引用、公式与代码 <rich-blocks>

> 形式化证明不仅应当能够被内核检查，也应当能够被人自然地阅读。
> PS4HTML 的目标是让证明结构、数学表达和项目元数据在同一个页面中协同工作。

$$
\sum_{k=1}^{n} k = \frac{n(n+1)}{2}
$$

```lean
@theorem demo (P Q : Prop) (h : P ∧ Q) : P := script
 unpack_and ⟨hP, hQ⟩ := h
 assumption
```

下面的 theorem component 使用另一个 Lean 文件中声明的定理，因此会自动产生
跨文件参考文献记录。
"#

@latex (
  title := "示例 LaTeX 表格",
  label := "example-table"
) r#"
  \begin{tabular}{cc}
    \toprule
    A & B \\
    \midrule
    1 & 2 \\
    \bottomrule
  \end{tabular}
"#

@figure (
  title := "ProofScript 到 PS4HTML 的构建流程",
  label := "component-preview",
  width := "wide"
) "assets/component-preview.svg"

@theorem galleryResult (P Q : Prop) (h : P ∧ Q) : P := by
  -- "调用参考定理库中已经形式化的结果"
  exact (andLeft P Q h)

theorem_info galleryResult {
  name := "跨模块合取投影",
  tags := ["demo", "cross-module"]
}

@text r#"
== 大型证明树展示 <large-proof>

下面的定理展示一个较大的组合单调性证明。我们从五个自然数之间的递增链出发，
依次把这条链送入三个单调函数，并证明原函数、二层复合、三层复合以及任意平移后的
结果仍然保持次序。证明以 `infer` 构造可复用的传递闭包，再用 `calc` 展开每一层
数学推导；全称量词、函数参数、中间证明和复合应用会在证明树中产生丰富的
free variable、bound variable、application argument 与 binder 信息。
"#

@theorem iteratedMonotoneChain
    (a b c d e : Nat)
    (F G H : Nat → Nat)
    (hab : a ≤ b) (hbc : b ≤ c) (hcd : c ≤ d) (hde : d ≤ e)
    (hF : ∀ ⦃x y : Nat⦄, x ≤ y → F x ≤ F y)
    (hG : ∀ ⦃x y : Nat⦄, x ≤ y → G x ≤ G y)
    (hH : ∀ ⦃x y : Nat⦄, x ≤ y → H x ≤ H y) :
    H (G (F a)) ≤ H (G (F e)) ∧
      ∀ n : Nat, n + F a ≤ n + F e := script
  split_and
  | left =>
    infer
      G (F a) ≤ G (F b) => G (F a) ≤ G (F c) :=
        Nat.le_trans (hG (hF hab)) (hG (hF hbc))
      => G (F a) ≤ G (F d) := Nat.le_trans ?_ (hG (hF hcd))
      => G (F a) ≤ G (F e) := Nat.le_trans ?_ (hG (hF hde))
    calc
      H (G (F a)) ≤ H (G (F b)) := hH (hG (hF hab))
      _ ≤ H (G (F c)) := hH (hG (hF hbc))
      _ ≤ H (G (F d)) := hH (hG (hF hcd))
      _ ≤ H (G (F e)) := hH (hG (hF hde))
  | right =>
    intro n
    infer
      F a ≤ F b => F a ≤ F c := Nat.le_trans (hF hab) (hF hbc)
      => F a ≤ F d := Nat.le_trans ?_ (hF hcd)
      => F a ≤ F e := Nat.le_trans ?_ (hF hde)
    calc
      n + F a ≤ n + F b := Nat.add_le_add_left (hF hab) n
      _ ≤ n + F c := Nat.add_le_add_left (hF hbc) n
      _ ≤ n + F d := Nat.add_le_add_left (hF hcd) n
      _ ≤ n + F e := Nat.add_le_add_left (hF hde) n

theorem_info iteratedMonotoneChain {
  name := "多层单调映射的链式传递",
  tags := ["demo", "order", "monotonicity", "calc", "infer"]
}

@text r#"
证明完成后，@thm:PS4HTMLDemo.Gallery.galleryResult 指向当前页面中的 theorem component。
大型证明可以通过 @thm:PS4HTMLDemo.Gallery.iteratedMonotoneChain 定位。
接下来的 references component 会把证明中实际使用的外部定理按项目分组展示。
"#

@references

@text r#"
== 组件顺序 <component-order>

参考文献之后仍然可以继续插入 ProofText。这个段落证明 PS4HTML 严格保持
`components` 数组的源文件顺序，而不是把参考文献强制移动到页面末尾。
"#

page_end
