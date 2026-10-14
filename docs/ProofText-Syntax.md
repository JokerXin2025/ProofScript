# ProofText Syntax

ProofText is the lightweight markup language parsed inside ProofScript's `@text` command. It
provides semantic blocks and inline markup for prose that is exported with a Lean module.

ProofText resembles Typst, but it is a distinct and deliberately small language. In particular,
`*text*` means strong text, headings begin with `=`, and unordered list items begin with `+`.

This document describes the syntax implemented by the current ProofText parser.

## 1. Using `@text`

The command takes exactly one Lean string literal:

```lean
@text "A paragraph."
```

Multiline raw strings are usually the most convenient form:

````lean
@text r#"
= Introduction <introduction>

This is *important* text with $x + y$ inline.
"#
````

The payload is decoded by Lean before ProofText parses it. Consequently, there are two possible
escape layers:

1. Lean string-literal escaping.
2. ProofText inline escaping.

In an ordinary Lean string, a backslash intended for ProofText must itself be escaped. These two
commands therefore produce the same ProofText content:

```lean
@text "\\*literal asterisk"
@text r"\*literal asterisk"
```

Raw Lean strings are recommended for multiline text, LaTeX, and text containing many ProofText
escapes. Increase the number of `#` characters around a raw string when its content contains the
current closing sequence.

Each successful `@text` command before `page_end` adds one text component to the current page.
Components after export are ignored with a warning.

## 2. Complete Example

````lean
@text r#"
= ProofText Overview <overview>

This paragraph contains *strong text*, _emphasis_, *_strong emphasis_*,
~~struck text~~, __underlined text__, ==highlighted text==, x^2^, a~n~,
`inline code`, $x + y$, and [a link](https://example.com).
See @<overview>, @thm:Paper.Main.mainResult, and @fig:diagram.

- First item
- Second item

+ First step
4. Forced fourth step
+ Automatic fifth step

> A quoted paragraph with _inline markup_.

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

```lean
theorem example : True := by
  trivial
```
"#
````

## 3. Source Normalization and Blocks

ProofText first normalizes indentation so a multiline string can be aligned with surrounding Lean
code:

- One blank first line and one blank last line are removed when present.
- The smallest number of leading ASCII spaces among nonblank lines is removed from every line.
- Tabs do not count toward this common indentation.
- Blank lines separate blocks and do not create output nodes.
- An empty or whitespace-only string is valid and produces no blocks.

For example, the following heading and paragraph are parsed at column zero after normalization:

```lean
namespace Example

  @text r#"
    = Heading

    A paragraph.
  "#

end Example
```

After common indentation is removed, block markers are column-sensitive. Any remaining spaces or
tabs before a marker normally cause the line to be parsed as paragraph text.

The original decoded string is retained in exported page JSON, while its normalized form is used
to construct the semantic block tree.

## 4. Block Syntax

### 4.1 Paragraphs

Consecutive ordinary lines form one paragraph:

```text
This is one paragraph
continued on another source line.
```

Source newlines inside a paragraph are preserved as newline characters. They are not converted to
spaces, and the current parser does not generate separate soft-break or hard-break nodes.

A paragraph ends at a blank line or before another recognized block. Inline syntax is parsed
across the complete paragraph.

### 4.2 Headings

Headings have one through four `=` characters followed by one literal space:

```text
= Level 1
== Level 2
=== Level 3
==== Level 4
```

Heading text supports all inline syntax. Leading and trailing ASCII whitespace in the heading body
is removed.

An optional reference label may appear at the end:

```text
== Main Result <main-result>
```

Labels must start with a letter and then contain only letters, digits, hyphens, or underscores:

```text
[A-Za-z][A-Za-z0-9_-]*
```

Examples of valid labels are `overview`, `chapter-2`, `result_1`, and `A`. Spaces, dots, and a
leading digit or punctuation mark are not allowed.

Heading labels are registered when the command is elaborated. Reusing a heading label in the same
page/module is an error. A heading reference uses `@<label>` as described in Section 5.7.

A line beginning with `=` in block position is an error if it has more than six `=` characters,
omits the required space, or ends with a malformed label.

### 4.3 Unordered Lists

Consecutive lines beginning with `- ` form an unordered list:

```text
- First item
- Second item with *strong text*
```

Each item is one line and is parsed as one paragraph with inline markup. Multiline items,
continuation lines, and nested lists are not supported.

The marker `*` does not create an unordered list.

### 4.4 Ordered Lists

An automatically numbered ordered item begins with `+ `:

```text
+ First item
+ Second item
```

The `n. ` form forces the ordinal of that item. A following `+ ` item continues after the forced
ordinal:

```text
+ First item
4. Forced fourth item
+ Automatic fifth item
```

Each ordered list item has `ordinal : null | Nat` in JSON. The `+ ` form produces `null`, while
`n. ` preserves the explicit number. Every item is a single inline-parsed line; multiline and
nested items are not supported.

### 4.5 Block Quotes

Consecutive lines beginning with `> ` form a quote:

```text
> This is a quoted paragraph.
> It continues on the next source line.
```

After one `> ` prefix is removed from every line, the quote body is parsed recursively as complete
ProofText. It may therefore contain paragraphs, headings, lists, code blocks, display math, and
nested quotes. For example:

```text
> == A Heading in a Quote
> 
> + A quoted list item
> + Another item
```

Every physical line belonging to the outer quote must have the `> ` prefix. An unmarked blank line
ends the quote. A line containing only `>` is not a quote marker because the space is required.

### 4.6 Display Math

A display-math block is enclosed by lines equal to `$$`:

```text
$$
\sum_{i=1}^{n} i = \frac{n(n+1)}{2}
$$
```

The opening and closing lines must contain exactly `$$`, without leading or trailing whitespace.
The body is retained verbatim: inline syntax and ProofText escapes are not processed. The first
later `$$` line closes the block. A missing closing line is an error.

For inline mathematics, use `$...$` instead.

### 4.7 Fenced Code Blocks

A code block starts with three backticks and ends at the next line beginning with three backticks:

````text
```lean
theorem example : True := by
  trivial
```
````

Text after the opening backticks is trimmed and stored as the optional language name. A bare fence
creates a code block without a language:

````text
```
verbatim text
```
````

The body is retained verbatim and is not parsed as inline ProofText. Closing-fence recognition is
prefix-based: a line beginning with three backticks closes the block even if more characters follow
on that line. Nested fences are not supported, and a missing closing fence is an error.

## 5. Inline Syntax

Inline constructs are recognized from left to right. No word-boundary or surrounding-whitespace
rules apply, so constructs such as `x^2^` work inside ordinary text.

### 5.1 Formatting

| Syntax | Meaning | Example |
| --- | --- | --- |
| `*text*` | Strong | `This is *important*.` |
| `_text_` | Emphasis | `This is _emphasized_.` |
| `*_text_*` | Strong emphasis | `This is *_very important_*.` |
| `~~text~~` | Strikethrough | `This is ~~obsolete~~.` |
| `__text__` | Underline | `This is __underlined__.` |
| `==text==` | Highlight | `This is ==highlighted==.` |
| `^text^` | Superscript | `x^2^` |
| `~text~` | Subscript | `a~n~` |

Formatting bodies are recursively parsed, so different constructs may be nested:

```text
*strong text containing _emphasis_*
```

Delimiter matching is intentionally simple. A construct ends at the first literal occurrence of
its closing delimiter; delimiters are not balanced, and the search does not skip escaped
characters. Same-delimiter nesting is therefore unsupported, and complex nesting that contains an
outer closing delimiter may close earlier than expected.

Every recognized opener must have a closer. An unclosed formatting span is an error rather than
ordinary text.

### 5.2 Escapes

A backslash makes exactly the next character ordinary text:

```text
\*literal asterisk
\_literal underscore
\@literal at sign
\\literal backslash
```

Any character may be escaped, not only punctuation. A backslash at the end of the input is an
error.

ProofText escaping applies only during inline parsing. It is not processed inside inline code,
inline math, link URLs, fenced code, or display math. It also does not participate in the parser's
initial search for a closing delimiter, so an escaped character cannot reliably hide an outer
span's closer.

When an ordinary Lean string is used, remember to escape the backslash for Lean as well. Raw Lean
strings avoid this extra layer.

### 5.3 Inline Code

One backtick pair creates verbatim inline code:

```text
Use `assumption` to close a script goal.
```

The first later backtick closes the code span. Its body is not parsed for markup or escapes.
Multiple-backtick delimiters are not supported, and a missing closing backtick is an error.

### 5.4 Inline Math

One dollar-sign pair creates inline LaTeX:

```text
The identity $x + 0 = x$ holds.
```

The first later `$` closes the span. Its body is retained verbatim and does not process ProofText
markup or escapes. A missing closing `$` is an error.

### 5.5 Links

Links use the following form:

```text
[ProofScript repository](https://github.com/example/ProofScript)
```

The label is recursively parsed as inline ProofText; the URL is retained verbatim and is not
validated. Empty labels and URLs are accepted by the parser.

The first `](` after `[` separates the label from the URL, and the first following `)` closes the
link. Parentheses in URLs are not balanced, and ProofText escapes are not processed in URLs. A `[`
without a later `](` remains ordinary text, but a recognized link opener without a closing `)` is
an error.

### 5.6 Labels

Heading and figure labels use the following form:

```text
[A-Za-z][A-Za-z0-9_-]*
```

For portability with the exported JSON Schema, use ASCII letters and digits. Labels are
case-sensitive. Examples:

| Label | Valid | Reason |
| --- | --- | --- |
| `main-result` | Yes | Starts with a letter; hyphens are allowed. |
| `result_2` | Yes | Digits and underscores are allowed after the first letter. |
| `2-result` | No | Starts with a digit. |
| `main.result` | No | Dots are not allowed. |
| `main result` | No | Spaces are not allowed. |

### 5.7 References

ProofText has four reference forms:

| Syntax | Target kind |
| --- | --- |
| `@<label>` | Heading |
| `@thm:Lean.DeclarationName` | Theorem (fully qualified Lean declaration name) |
| `@fig:label` | Figure or TikZ component |

Examples:

```text
See @<introduction> and @thm:Paper.Main.mainResult.
See @fig:overview-diagram.
```

Heading references have a closing `>`. Figure references consume letters, digits, hyphens and
underscores. Theorem references also accept dots for qualified Lean declaration names; trailing
dots are treated as punctuation. Thus `@thm:Paper.Main.result.` refers to `Paper.Main.result`.

Malformed reference syntax is an error once a recognized marker has been encountered. Unknown
forms such as `@eq:result` remain ordinary text.

Parsing a reference does not verify that its target exists. References may point forward, and
cross-page validity is handled later by the renderer or consumer.

## 6. Recognition Rules and Precedence

When several forms could begin at the same location, ProofText uses fixed recognition order.

At the start of a block line, the effective order is:

1. Blank line.
2. Fenced code block beginning with three backticks.
3. Display math when the line equals `$$`.
4. Heading, including rejection of malformed block-position lines beginning with `=`.
5. Unordered list item beginning with `- `.
6. Ordered list item beginning with `+ ` or decimal digits and `. `.
7. Quote line beginning with `> `.
8. Paragraph.

At an inline position, the order is:

1. Backslash escape.
2. Strong emphasis, `*_..._*`.
3. Strikethrough, `~~...~~`.
4. Underline, `__...__`.
5. Highlight, `==...==`.
6. Strong, `*...*`.
7. Emphasis, `_..._`.
8. Superscript, `^...^`.
9. Subscript, `~...~`.
10. Inline code, `` `...` ``.
11. Inline math, `$...$`.
12. Link, `[...](...)`.
13. Heading reference, `@<...>`.
14. Theorem, figure, or table reference.
15. Ordinary text.

This is operational precedence, not balanced-delimiter precedence. Closing delimiters are located
before their bodies are recursively parsed.

## 7. Errors

The `@text` command fails during elaboration for these malformed forms:

| Condition | Typical diagnostic |
| --- | --- |
| Trailing inline backslash | `dangling ProofText escape` |
| Unclosed formatting span | `unclosed ProofText delimiter '...'` |
| Unclosed inline code | `unclosed inline code` |
| Unclosed inline math | `unclosed inline math` |
| Recognized link without `)` | `unclosed ProofText link` |
| Heading reference without `>` | `unclosed heading reference` |
| Invalid heading-reference label | `invalid heading label '...'` |
| Invalid label after `@thm:` or `@fig:` | `invalid reference after '...'` |
| Unclosed fenced code block | `unclosed code block` |
| Unclosed display math | `unclosed display math` |
| Malformed heading in block position | `invalid heading or heading label; labels must match ...` |
| Duplicate heading label | `duplicate heading label '...'` |

Diagnostics currently point to the complete Lean string literal rather than an exact offset inside
the ProofText payload.

## 8. Current Limitations

The current parser does not implement:

- multiline or nested list items;
- balanced or same-delimiter inline nesting;
- escape-aware closing-delimiter search;
- multiple-backtick inline code;
- URL validation or balanced parentheses in URLs;
- reference-target validation during `@text` elaboration;
- Markdown hard-break syntax or generated soft/hard-break nodes;
- images, HTML, horizontal rules, footnotes, or ProofText table syntax.

## 9. Compact Reference

### Blocks

| Construct | Syntax |
| --- | --- |
| Paragraph | Consecutive ordinary nonblank lines |
| Heading | `={1,6} Title` |
| Labeled heading | `={1,6} Title <label>` |
| Unordered item | `- text` |
| Automatic ordered item | `+ text` |
| Forced-ordinal ordered item | `n. text` |
| Quote | `> text` |
| Display math | Exact `$$` lines around the body |
| Code block | Lines beginning with ` ``` ` around the body |

### Inline Forms

| Construct | Syntax |
| --- | --- |
| Strong | `*text*` |
| Emphasis | `_text_` |
| Strong emphasis | `*_text_*` |
| Strikethrough | `~~text~~` |
| Underline | `__text__` |
| Highlight | `==text==` |
| Superscript | `^text^` |
| Subscript | `~text~` |
| Code | `` `code` `` |
| Math | `$latex$` |
| Link | `[label](url)` |
| Heading reference | `@<label>` |
| Theorem reference | `@thm:Lean.DeclarationName` |
| Figure reference | `@fig:label` |
| Escape | `\character` |
