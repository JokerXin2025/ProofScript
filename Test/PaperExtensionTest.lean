import ProofScript

@text r#"
= ProofText Overview <overview>

This paragraph contains *bold*, _italic_, *_bold italic_*, ~~deleted~~,
__underlined__, ==highlighted==, x^2^, a~n~, `code`, $x + y$, and
[a link](https://example.com). See @<overview>, @thm:Test.PaperExtensionTest.paperMain,
and @fig:diagram.

- First item
- Second item

+ First step
4. Fourth step
+ Fifth step

> A quoted paragraph.

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

```lean
theorem example : True := by
  trivial
```
"#

@theorem paperMain (P : Prop) (h : P) : P := script
  assumption
theorem_info paperMain {name := "Paper Main"}

@theorem defaultDisplayName : True := script
  trivial

@theorem incompleteResult : True := script
  admit "pending"
theorem_info incompleteResult {name := "Incomplete Result"}

page_end

@text "This component is intentionally ignored after export."
