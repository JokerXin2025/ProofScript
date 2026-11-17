# Title Components

Import `ProofScript.Extensions.Title` (also included by `ProofScript`) to use independent page titles:

```lean
#page title (label := "introduction") "Introduction"
#page text "See @<details>."
#page sub title (label := "details") "A subtitle with *strong text* and $x^2$"
#page sub sub title "Level three"
```

Each `sub` before `title` adds one level, without a depth limit. Levels one through five use
progressively smaller type. Each level beyond five adds one `→` to the left while retaining the
level-five size. JSON retains the full `level`; HTML uses `aria-level` for levels beyond five.

An optional `(label := "name")` precedes the title string. Labels match `[A-Za-z][A-Za-z0-9_-]*`
and must be unique within the module. ProofText's `@<name>` resolves these components, including
forward and cross-page references. The existing `heading-name` anchors and reference JSON kind
are retained.

Title text is trimmed of surrounding ASCII whitespace and parsed with ProofText's inline rules,
including formatting, math, links, and references. Block syntax is not parsed inside a title.
ProofText no longer has heading blocks: `=` has no special block meaning, and normal paragraph
and inline rules apply.

Title parsing and registration run only during page builds. A title can appear at any valid command position.
