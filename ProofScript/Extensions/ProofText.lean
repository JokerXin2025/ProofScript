import ProofScript.Page.Component.Core
import ProofScript.Extensions.ProofText.Inline

open Lean
open ProofScript
open ProofScript.ProofText


mutual

  private inductive Block where
  | paragraph (content : Array Inline)
  | code (language : Option String) (source : String)
  | orderedList (start : Nat) (items : Array ListItem)
  | unorderedList (items : Array ListItem)
  | quote (content : Array Block)
  | displayMath (latex : String)
  deriving Inhabited, Repr, ToJson, FromJson

  private structure ListItem where
    ordinal : Option Nat := none
    content : Array Block
  deriving Inhabited, Repr, ToJson, FromJson

end

private structure TextComponent where
  source : String
  blocks : Array Block
deriving Inhabited, Repr, ToJson, FromJson

private def stripIndent (source : String) : String :=
  let lines := source.splitOn "\n"
  let lines := if lines.head?.any (·.trimAscii.isEmpty) then lines.drop 1 else lines
  let lines := if lines.getLast?.any (·.trimAscii.isEmpty) then lines.dropLast else lines
  let indents := lines.filterMap fun line =>
    if line.trimAscii.isEmpty then none
    else some <| line.toList.takeWhile (· == ' ') |>.length
  let indent := indents.foldl Nat.min (indents.head?.getD 0)
  String.intercalate "\n" <| lines.map fun line => String.ofList (line.toList.drop indent)

private def orderedItem? (line : String) : Option (Nat × String) :=
  let digits := line.toList.takeWhile Char.isDigit
  if digits.isEmpty then none
  else
    let marker := String.ofList digits ++ ". "
    if line.startsWith marker then
      (String.ofList digits).toNat?.map fun n => (n, line.drop marker.length |>.toString)
    else none

private inductive ListKind where
| ordered
| unordered
deriving BEq

private structure ListMarker where
  indent : Nat
  kind : ListKind
  ordinal : Option Nat
  text : String

private def leadingSpaces (line : String) : Nat :=
  line.toList.takeWhile (· == ' ') |>.length

private def listMarker? (line : String) : Option ListMarker :=
  let indent := leadingSpaces line
  let body := line.drop indent |>.toString
  if body.startsWith "- " then
    some {
      indent := indent
      kind := .unordered
      ordinal := none
      text := body.drop 2 |>.toString
    }
  else if body.startsWith "+ " then
    some {
      indent := indent
      kind := .ordered
      ordinal := none
      text := body.drop 2 |>.toString
    }
  else match orderedItem? body with
    | some (ordinal, text) =>
        some {
          indent := indent
          kind := .ordered
          ordinal := some ordinal
          text := text
        }
    | none => none

private def sameListKind (left right : ListKind) : Bool :=
  match left, right with
  | .ordered, .ordered => true
  | .unordered, .unordered => true
  | _, _ => false

private def startsBlock (line : String) : Bool :=
  line.startsWith "```" || line == "$$" || line.startsWith "- " || line.startsWith "+ " ||
    line.startsWith "> " || (orderedItem? line).isSome

private partial def parse (rawSource : String) : Except String (Array Block) := do
  let source := stripIndent rawSource
  let lines := source.splitOn "\n" |>.toArray

  /- A list item keeps its first line as the existing paragraph block. Any
     more-indented list markers are parsed recursively and appended to that
     item's block content, which lets list kinds alternate at every depth. -/
  let rec parseList (index : Nat) (indent : Nat) (kind : ListKind) :
      Except String (Nat × Block) := do
    let rec collect (i : Nat) (items : Array ListItem) :
        Except String (Nat × Array ListItem) := do
      if i >= lines.size then return (i, items)
      let some marker := listMarker? lines[i]! | return (i, items)
      if marker.indent != indent || !sameListKind marker.kind kind then
        return (i, items)
      let inline ← parseInline marker.text
      let rec collectNested (j : Nat) (content : Array Block) :
          Except String (Nat × Array Block) := do
        if j >= lines.size then return (j, content)
        let nestedLine := lines[j]!
        if nestedLine.trimAscii.isEmpty then return (j, content)
        let some nested := listMarker? nestedLine | return (j, content)
        if nested.indent <= indent then return (j, content)
        let (next, block) ← parseList j nested.indent nested.kind
        collectNested next (content.push block)
      let (next, nested) ← collectNested (i + 1) #[]
      let item : ListItem := {
        ordinal := if kind == .ordered then marker.ordinal else none
        content := (#[.paragraph inline] ++ nested)
      }
      collect next (items.push item)
    let (next, items) ← collect index #[]
    let block := match kind with
      | .ordered =>
          let start := items[0]?.bind (·.ordinal) |>.getD 1
          .orderedList start items
      | .unordered => .unorderedList items
    return (next, block)

  let rec loop (index : Nat) (out : Array Block) : Except String (Array Block) := do
    if index >= lines.size then return out
    let line := lines[index]!
    if line.trimAscii.isEmpty then return ← loop (index + 1) out
    if line.startsWith "```" then
      let language := (line.drop 3).trimAscii.toString
      let rec findCodeClose (i : Nat) : Option Nat :=
        if i >= lines.size then none
        else if lines[i]!.startsWith "```" then some i else findCodeClose (i + 1)
      let some closeAt := findCodeClose (index + 1) | throw "unclosed code block"
      let code := String.intercalate "\n" <| (lines.extract (index + 1) closeAt).toList
      let language := if language.isEmpty then none else some language
      return ← loop (closeAt + 1) (out.push (.code language code))
    if line == "$$" then
      let rec findMathClose (i : Nat) : Option Nat :=
        if i >= lines.size then none
        else if lines[i]! == "$$" then some i else findMathClose (i + 1)
      let some closeAt := findMathClose (index + 1) | throw "unclosed display math"
      let latex := String.intercalate "\n" <| (lines.extract (index + 1) closeAt).toList
      return ← loop (closeAt + 1) (out.push (.displayMath latex))
    if let some marker := listMarker? line then
      if marker.indent == 0 then
        let (next, block) ← parseList index marker.indent marker.kind
        return ← loop next (out.push block)
    if line.startsWith "> " then
      let rec collectQuote (i : Nat) (quoted : Array String) : Nat × Array String :=
        if i < lines.size && lines[i]!.startsWith "> " then
          collectQuote (i + 1) (quoted.push (lines[i]!.drop 2 |>.toString))
        else (i, quoted)
      let (next, quoted) := collectQuote index #[]
      let content ← parse (String.intercalate "\n" quoted.toList)
      return ← loop next (out.push (.quote content))
    let rec collectParagraph (i : Nat) (paragraph : Array String) : Nat × Array String :=
      if i >= lines.size || lines[i]!.trimAscii.isEmpty || (i > index && startsBlock lines[i]!) then
        (i, paragraph)
      else collectParagraph (i + 1) (paragraph.push lines[i]!)
    let (next, paragraph) := collectParagraph index #[]
    let content ← parseInline (String.intercalate "\n" paragraph.toList)
    loop next (out.push (.paragraph content))
  loop 0 #[]

page_component "text" source:str => do
  when_page_build do
    let raw := source.getString
    match parse raw with
    | .ok blocks =>
        let value : TextComponent := {
          source := raw
          blocks := blocks
        }
        addPageComponent source.raw "text" (toJson value)
    | .error message => throwErrorAt source message
