import ProofScript.Page.Component.Core

open Lean
open ProofScript


private inductive ProofTextReferenceKind where
| heading
| theorem
| figure
deriving Inhabited, Repr, BEq, Hashable, ToJson, FromJson

private inductive Inline where
| text (value : String)
| strong (content : Array Inline)
| emphasis (content : Array Inline)
| strongEmphasis (content : Array Inline)
| code (value : String)
| strike (content : Array Inline)
| underline (content : Array Inline)
| highlight (content : Array Inline)
| superscript (content : Array Inline)
| subscript (content : Array Inline)
| link (content : Array Inline) (url : String)
| reference (kind : ProofTextReferenceKind) (label : String)
| math (latex : String)
| softBreak
| hardBreak
deriving Inhabited, Repr, ToJson, FromJson

mutual

  private inductive Block where
  | paragraph (content : Array Inline)
  | heading (level : Nat) (label : Option String) (content : Array Inline)
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

private def validLabel (label : String) : Bool :=
  match label.toList with
  | [] => false
  | first :: rest =>
      first.isAlpha && rest.all fun c => c.isAlphanum || c == '-' || c == '_'

private def appendText (out : Array Inline) (text : String) : Array Inline :=
  if text.isEmpty then out
  else
    match out.back? with
    | some (.text previous) => out.pop.push (.text (previous ++ text))
    | _ => out.push (.text text)

private def findFrom (text needle : String) (start : Nat) : Option Nat :=
  let tail := text.drop start |>.toString
  match tail.splitOn needle with
  | before :: _ :: _ => some (start + before.length)
  | _ => none

private partial def parseInlineCore (text : String)
                                    : Except String (Array Inline) := do
  let rec loop  (rest : String)
                (out : Array Inline)
                : Except String (Array Inline) := do
    if rest.isEmpty then return out
    if rest.startsWith "\\" then
      let escaped := rest.drop 1 |>.toString
      if escaped.isEmpty then throw "dangling ProofText escape"
      return ← loop (escaped.drop 1 |>.toString) (appendText out (escaped.take 1 |>.toString))
    let parseDelimited (opener closer : String) (ctor : Array Inline → Inline) :
        Except String (Array Inline) := do
      let bodyStart := opener.length
      let some closeAt := findFrom rest closer bodyStart
        | throw s!"unclosed ProofText delimiter '{opener}'"
      let body := rest.drop bodyStart |>.take (closeAt - bodyStart) |>.toString
      let parsed ← parseInlineCore body
      loop (rest.drop (closeAt + closer.length) |>.toString) (out.push (ctor parsed))
    if rest.startsWith "*_" then
      parseDelimited "*_" "_*" Inline.strongEmphasis
    else if rest.startsWith "~~" then
      parseDelimited "~~" "~~" Inline.strike
    else if rest.startsWith "__" then
      parseDelimited "__" "__" Inline.underline
    else if rest.startsWith "==" then
      parseDelimited "==" "==" Inline.highlight
    else if rest.startsWith "*" then
      parseDelimited "*" "*" Inline.strong
    else if rest.startsWith "_" then
      parseDelimited "_" "_" Inline.emphasis
    else if rest.startsWith "^" then
      parseDelimited "^" "^" Inline.superscript
    else if rest.startsWith "~" then
      parseDelimited "~" "~" Inline.subscript
    else if rest.startsWith "`" then
      let some closeAt := findFrom rest "`" 1
        | throw "unclosed inline code"
      let code := rest.drop 1 |>.take (closeAt - 1) |>.toString
      loop (rest.drop (closeAt + 1) |>.toString) (out.push (.code code))
    else if rest.startsWith "$" then
      let some closeAt := findFrom rest "$" 1
        | throw "unclosed inline math"
      let latex := rest.drop 1 |>.take (closeAt - 1) |>.toString
      loop (rest.drop (closeAt + 1) |>.toString) (out.push (.math latex))
    else if rest.startsWith "[" then
      let some labelEnd := findFrom rest "](" 1
        | return ← loop (rest.drop 1 |>.toString) (appendText out "[")
      let some urlEnd := findFrom rest ")" (labelEnd + 2)
        | throw "unclosed ProofText link"
      let labelText := rest.drop 1 |>.take (labelEnd - 1) |>.toString
      let url := rest.drop (labelEnd + 2) |>.take (urlEnd - labelEnd - 2) |>.toString
      let label ← parseInlineCore labelText
      loop (rest.drop (urlEnd + 1) |>.toString) (out.push (.link label url))
    else if rest.startsWith "@<" then
      let some closeAt := findFrom rest ">" 2
        | throw "unclosed heading reference"
      let label := rest.drop 2 |>.take (closeAt - 2) |>.toString
      unless validLabel label do throw s!"invalid heading label '{label}'"
      loop (rest.drop (closeAt + 1) |>.toString) (out.push (.reference .heading label))
    else if rest.startsWith "@thm:" || rest.startsWith "@fig:" then
      let (marker, kind) : String × ProofTextReferenceKind :=
        if rest.startsWith "@thm:" then ("@thm:", ProofTextReferenceKind.theorem)
        else ("@fig:", ProofTextReferenceKind.figure)
      let tail := rest.drop marker.length |>.toString
      let label := String.ofList <| tail.toList.takeWhile fun c =>
        c.isAlphanum || c == '_' ||
          (kind == .theorem && c == '.') || (kind == .figure && c == '-')
      let label := if kind == .theorem then
        String.ofList ((label.toList.reverse.dropWhile (· == '.')).reverse)
      else label
      unless (if kind == .theorem then
        !label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '_' || c == '.') &&
          (label.splitOn ".").all (!·.isEmpty)
      else validLabel label) do
        throw s!"invalid reference after '{marker}'"
      loop (tail.drop label.length |>.toString) (out.push (.reference kind label))
    else
      loop (rest.drop 1 |>.toString) (appendText out (rest.take 1 |>.toString))
  loop text #[]

private def parseInline (text : String) : Except String (Array Inline) :=
  parseInlineCore text

private def stripIndent (source : String) : String :=
  let lines := source.splitOn "\n"
  let lines := if lines.head?.any (·.trimAscii.isEmpty) then lines.drop 1 else lines
  let lines := if lines.getLast?.any (·.trimAscii.isEmpty) then lines.dropLast else lines
  let indents := lines.filterMap fun line =>
    if line.trimAscii.isEmpty then none
    else some <| line.toList.takeWhile (· == ' ') |>.length
  let indent := indents.foldl Nat.min (indents.head?.getD 0)
  String.intercalate "\n" <| lines.map fun line => String.ofList (line.toList.drop indent)

private def headingLine? (line : String) : Option (Nat × String × Option String) :=
  let level := line.toList.takeWhile (· == '=') |>.length
  if level == 0 || level > 4 || !(line.drop level |>.startsWith " ") then none
  else
    let body := (line.drop (level + 1)).trimAscii.toString
    if body.endsWith ">" then
      match body.toList.reverse.findIdx? (· == '<') with
      | some idxFromEnd =>
          let openAt := body.length - idxFromEnd - 1
          let label := body.drop (openAt + 1) |>.take (body.length - openAt - 2) |>.toString
          if validLabel label then
            some (level, (body.take openAt).trimAscii.toString, some label)
          else none
      | none => some (level, body, none)
    else some (level, body, none)

private def orderedItem? (line : String) : Option (Nat × String) :=
  let digits := line.toList.takeWhile Char.isDigit
  if digits.isEmpty then none
  else
    let marker := String.ofList digits ++ ". "
    if line.startsWith marker then
      (String.ofList digits).toNat?.map fun n => (n, line.drop marker.length |>.toString)
    else none

private def startsBlock (line : String) : Bool :=
  line.startsWith "```" || line == "$$" || line.startsWith "- " || line.startsWith "+ " ||
    line.startsWith "> " || (headingLine? line).isSome || (orderedItem? line).isSome

private partial def parse (rawSource : String) : Except String (Array Block) := do
  let source := stripIndent rawSource
  let lines := source.splitOn "\n" |>.toArray
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
    if line.startsWith "=" && (headingLine? line).isNone then
      throw "invalid heading or heading label; labels must match [A-Za-z][A-Za-z0-9_-]*"
    if let some (level, title, label) := headingLine? line then
      let title ← parseInline title
      return ← loop (index + 1) (out.push (.heading level label title))
    if line.startsWith "- " then
      let rec collectUnordered  (i : Nat)
                                (items : Array ListItem)
                                : Except String (Nat × Array ListItem) := do
        if i < lines.size && lines[i]!.startsWith "- " then
          let content ← parseInline (lines[i]!.drop 2 |>.toString)
          collectUnordered (i + 1) (items.push { content := #[.paragraph content] })
        else return (i, items)
      let (next, items) ← collectUnordered index #[]
      return ← loop next (out.push (.unorderedList items))
    if line.startsWith "+ " || (orderedItem? line).isSome then
      let start := match orderedItem? line with
        | some (ordinal, _) => ordinal
        | none => 1
      let rec collectOrdered  (i : Nat)
                              (items : Array ListItem)
                              : Except String (Nat × Array ListItem) := do
        if i < lines.size then
          if lines[i]!.startsWith "+ " then
            let content ← parseInline (lines[i]!.drop 2 |>.toString)
            collectOrdered (i + 1) (items.push { content := #[.paragraph content] })
          else match orderedItem? lines[i]! with
          | some (ordinal, text) =>
              let content ← parseInline text
              collectOrdered (i + 1) (items.push {
                ordinal := some ordinal
                content := #[.paragraph content]
              })
          | none => return (i, items)
        else return (i, items)
      let (next, items) ← collectOrdered index #[]
      return ← loop next (out.push (.orderedList start items))
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

private partial def headingLabels (blocks : Array Block) : Array String := Id.run do
  let mut labels := #[]
  for block in blocks do
    match block with
    | .heading _ (some label) _ => labels := labels.push label
    | .quote content => labels := labels ++ headingLabels content
    | .orderedList _ items | .unorderedList items =>
        for item in items do labels := labels ++ headingLabels item.content
    | _ => pure ()
  return labels

elab "@""text" source:str : command => whenPageBuild do
  let raw := source.getString
  let blocks ←
    match parse raw with
    | .ok blocks => pure blocks
    | .error message => throwErrorAt source message
  let labels := (headingLabels blocks).map fun label => ("heading", label)
  addPageComponent source.raw "text" (toJson (⟨raw, blocks⟩ : TextComponent)) labels
