import Lean

namespace ProofScript

open Lean

/-- Find the first atom in left-to-right depth-first order. -/
partial def findFirstAtom (stx : Syntax) : Option Syntax :=
  if stx.isAtom then some stx
  else stx.getArgs.findSome? findFirstAtom

/-- Return the first atom's text; it need not be an identifier or tactic name. -/
def firstAtomName (stx : Syntax) : Option String :=
  (findFirstAtom stx).map (·.getAtomVal)

/-- Collect printed identifier names in source order, keeping duplicates. -/
partial def collectIdentNames (stx : Syntax) : List String :=
  if stx.isIdent then [stx.getId.toString]
  else stx.getArgs.toList.flatMap collectIdentNames

/-- Collect atom text in source order, including punctuation and duplicates. -/
partial def collectAtomValues (stx : Syntax) : List String :=
  if stx.isAtom then [stx.getAtomVal]
  else stx.getArgs.toList.flatMap collectAtomValues

/-- Check whether any atom has exactly the given text. -/
partial def syntaxContainsAtom (value : String) (stx : Syntax) : Bool :=
  (stx.isAtom && stx.getAtomVal == value) || stx.getArgs.any (syntaxContainsAtom value)

/-- Check for a synthetic hole (`?_` or `?name`), including nested syntax. -/
partial def containsSyntheticHole (stx : Syntax) : Bool :=
  stx.isOfKind ``Parser.Term.syntheticHole || stx.getArgs.any containsSyntheticHole

/-- Replace a node's kind and children, preserving its head source information. -/
def changeNodeKind (stx : Syntax) (newKind : Name) (args : Array Syntax) : Syntax :=
  Syntax.node stx.getHeadInfo newKind args

/-- Build an unpositioned `do` sequence, retaining the original element syntax. -/
def mkDoSeq (elems : Array Syntax) : Syntax :=
  let items := elems.map fun e => mkNode ``Parser.Term.doSeqItem #[e, mkNullNode]
  mkNode ``Parser.Term.doSeqIndent #[mkNullNode items]

/-- Build a semicolon-separated tactic sequence, positioned at its first tactic. -/
def buildTacticSeq (tactics : Array Syntax) : Syntax := Id.run do
  let headInfo := tactics[0]?.map Syntax.getHeadInfo |>.getD SourceInfo.none
  let mut parts := #[]
  for tactic in tactics do
    if !parts.isEmpty then
      parts := parts.push (mkAtomFrom tactic ";")
    parts := parts.push tactic
  let seq := Syntax.node headInfo ``Parser.Tactic.tacticSeq1Indented #[mkNullNode parts]
  return Syntax.node headInfo ``Parser.Tactic.tacticSeq #[seq]

/-- Erase identifier macro scopes recursively; preserve source info and preresolution.
Use only when generated binders and references intentionally resolve without hygiene. -/
partial def eraseMacroScopes (stx : Syntax) : Syntax :=
  match stx with
  | .ident info raw val pre => .ident info raw val.eraseMacroScopes pre
  | .node info kind args => .node info kind (args.map eraseMacroScopes)
  | _ => stx

end ProofScript
