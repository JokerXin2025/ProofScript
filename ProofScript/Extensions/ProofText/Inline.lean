import Lean

namespace ProofScript.ProofText

open Lean

inductive ReferenceKind where
| heading
| theorem
| figure
deriving Inhabited, Repr, BEq, Hashable, ToJson, FromJson

inductive Inline where
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
| reference (kind : ReferenceKind) (label : String)
| math (latex : String)
| softBreak
| hardBreak
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
      let (marker, kind) : String × ReferenceKind :=
        if rest.startsWith "@thm:" then ("@thm:", ReferenceKind.theorem)
        else ("@fig:", ReferenceKind.figure)
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

def parseInline (text : String) : Except String (Array Inline) :=
  parseInlineCore text

end ProofScript.ProofText
