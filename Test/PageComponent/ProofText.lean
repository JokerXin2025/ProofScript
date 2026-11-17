import ProofScript
import ProofScript.Page.State

set_option pageBuild true

open Lean Elab Command ProofScript ProofScript.ProofText

-- Check the actual inline tree, including nested formatting and adjacent text merging.
run_cmd do
  let check (source : String) (expected : Array Inline) : CommandElabM Unit := do
    let actual ← ofExcept (parseInline source)
    unless toJson actual == toJson expected do
      throwError m!"ProofText inline mismatch for {source}: {toJson actual}"
  check "plain 中文 punctuation!" #[.text "plain 中文 punctuation!"]
  check "*bold* _em_ *_both_* ~~strike~~ __under__ ==mark== ^up^ ~down~"
    #[.strong #[.text "bold"], .text " ", .emphasis #[.text "em"], .text " ",
      .strongEmphasis #[.text "both"], .text " ", .strike #[.text "strike"],
      .text " ", .underline #[.text "under"], .text " ",
      .highlight #[.text "mark"], .text " ", .superscript #[.text "up"],
      .text " ", .subscript #[.text "down"]]
  check "*bold _nested_ and ==marked==*"
    #[.strong #[.text "bold ", .emphasis #[.text "nested"], .text " and ",
      .highlight #[.text "marked"]]]
  check "`*literal*` $x_1 + y^2$ [*link*](https://example.org/a?q=1)"
    #[.code "*literal*", .text " ", .math "x_1 + y^2", .text " ",
      .link #[.strong #[.text "link"]] "https://example.org/a?q=1"]
  check "@<proof-text> @thm:Nat.add_comm @fig:plot-1."
    #[.reference .heading "proof-text", .text " ",
      .reference .theorem "Nat.add_comm", .text " ",
      .reference .figure "plot-1", .text "."]
  check "\\*literal\\* \\@<not-a-ref> [brackets]"
    #[.text "*literal* @<not-a-ref> [brackets]"]
  check "first\nsecond" #[.text "first\nsecond"]
  check "" #[]

run_cmd do
  let checkError (source message : String) : CommandElabM Unit := do
    match parseInline source with
    | .error actual =>
        unless actual == message do
          throwError m!"expected {message}, got {actual} for {source}"
    | .ok _ => throwError m!"expected ProofText error for {source}"
  for (source, message) in #[("\\", "dangling ProofText escape"),
      ("*open", "unclosed ProofText delimiter '*'"),
      ("_open", "unclosed ProofText delimiter '_'"),
      ("*_open", "unclosed ProofText delimiter '*_'"),
      ("~~open", "unclosed ProofText delimiter '~~'"),
      ("__open", "unclosed ProofText delimiter '__'"),
      ("==open", "unclosed ProofText delimiter '=='"),
      ("^open", "unclosed ProofText delimiter '^'"),
      ("~open", "unclosed ProofText delimiter '~'"),
      ("`open", "unclosed inline code"),
      ("$open", "unclosed inline math"),
      ("[label](open", "unclosed ProofText link"),
      ("@<open", "unclosed heading reference"),
      ("@<2bad>", "invalid heading label '2bad'"),
      ("@<>", "invalid heading label ''"),
      ("@thm:", "invalid reference after '@thm:'"),
      ("@fig:", "invalid reference after '@fig:'")] do
    checkError source message

#page title (label := "proof-text") "ProofText gallery"

#page text r#"
  First paragraph: *strong*, _emphasis_, *_both_*, ~~strike~~, __underline__, ==highlight==.
  Nested *bold _emphasis_* and ^superscript^ plus ~subscript~.

  Code `x * y`, math $x_1 + y^2$, and a [formatted *link*](https://example.org).
  Heading @<proof-text>, theorem @thm:Nat.add_comm, figure @fig:plot-1.
  Escaped \*asterisks\* and literal [brackets].

  ```lean
  theorem sample : True := by
    trivial
  ```

  ```
  untyped <code> & characters
  ```

  $$
  \sum_{i=1}^{n} i = \frac{n(n+1)}{2}
  $$

  3. third item
  4. fourth item
    - nested unordered
      + nested ordered
  - unordered item
    7. nested numbered
  + implicit ordered item
  + another ordered item

  > Quoted *formatting*.
  > - quoted list
  > - second item

  Closing paragraph.
"#

#page text ""
#page text "   \n   "
#page text "one\ntwo\n\nthree"

-- A failed component must not be added to the page.
/-- error: unclosed code block -/
#guard_msgs in
#page text "```lean\nno closing fence"

/-- error: unclosed display math -/
#guard_msgs in
#page text "$$\nx + y"

/-- error: unclosed ProofText delimiter '*' -/
#guard_msgs in
#page text "text *unfinished"

run_cmd do
  let state := getPageState (← getEnv)
  let texts := state.components.filter (·.kind == "text")
  unless state.components.size == 6 && texts.size == 5 do
    throwError m!"failed or missing ProofText components: {state.components.size}"
  let blocks ← ofExcept <| texts[0]!.value.getObjValAs? (Array Json) "blocks"
  let source ← ofExcept <| texts[0]!.value.getObjValAs? String "source"
  unless source.startsWith "\n  First paragraph" do
    throwError "ProofText did not preserve its original source"
  let kinds := blocks.map fun block =>
    ((block.getObj? |>.toOption).map (fun obj => obj.toList[0]!.1)).getD "missing"
  unless kinds == #["paragraph", "paragraph", "code", "code", "displayMath",
      "orderedList", "unorderedList", "orderedList", "quote", "paragraph"] do
    throwError m!"unexpected ProofText block order: {kinds}"
  let ordered ← ofExcept <| blocks[5]!.getObjVal? "orderedList"
  unless (← ofExcept <| ordered.getObjValAs? Nat "start") == 3 do
    throwError "numbered list start was lost"
  let items ← ofExcept <| ordered.getObjValAs? (Array Json) "items"
  unless items.size == 2 &&
      (← ofExcept <| items[1]!.getObjValAs? (Option Nat) "ordinal") == some 4 do
    throwError "numbered list ordinals were lost"
  let nested ← ofExcept <| items[1]!.getObjValAs? (Array Json) "content"
  unless nested.size == 2 && (nested[1]!.getObjVal? "unorderedList").isOk do
    throwError "nested unordered list was lost"
  let quoted ← ofExcept <| blocks[8]!.getObjVal? "quote"
  unless (← ofExcept <| quoted.getObjValAs? (Array Json) "content").size == 2 do
    throwError "quoted paragraph and list were not parsed recursively"
  for index in #[1, 2] do
    unless (← ofExcept <| texts[index]!.value.getObjValAs? (Array Json) "blocks").isEmpty do
      throwError "empty or whitespace-only ProofText produced blocks"
  let multiline ← ofExcept <| texts[3]!.value.getObjValAs? (Array Json) "blocks"
  unless multiline.size == 2 do
    throwError "blank lines did not separate paragraphs"
  let oldHeading ← ofExcept <| texts[4]!.value.getObjValAs? (Array Json) "blocks"
  unless oldHeading.size == 1 && (oldHeading[0]!.getObjVal? "paragraph").isOk do
    throwError "former heading syntax is no longer ordinary paragraph text"
  unless state.labels.contains ("heading", "proof-text") do
    throwError "the heading reference target was not registered"
