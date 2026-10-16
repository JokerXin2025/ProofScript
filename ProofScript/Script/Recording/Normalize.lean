import ProofScript.Script.Recording.Parser
import Lean.Elab.Command
import Lean.Parser.Syntax

namespace ProofScript.Recording
open Lean Elab Command

partial def normalizeParam (stx : Syntax) : Except String ParamParser := do
  let kind := stx.getKind
  if kind == ``Parser.Syntax.cat then
    return .category stx[0].getId
  if kind == ``Parser.Syntax.paren then
    return ← normalizeSequence stx[1].getArgs
  if kind == Name.mkSimple "stx_+" || kind == Name.mkSimple "stx_*" then
    return .array (← normalizeParam stx[0]) false
  if kind == Name.mkSimple "stx_?" then
    return .optional (← normalizeParam stx[0])
  if kind == ``Parser.Syntax.sepBy || kind == ``Parser.Syntax.sepBy1 then
    return .array (← normalizeSequence stx[1].getArgs) true
  throw s!"unsupported parameter parser `{kind}`; define a named category or script_recorder"
where
  normalizeSequence (parts : Array Syntax) : Except String ParamParser := do
    let parts := parts.filter fun part =>
      !(part.getKind == ``Parser.Syntax.cat &&
        [`colGt, `colGe, `colEq, `ppSpace, `ppLine].contains part[0].getId)
    if parts.size != 1 then
      throw "compound parameter sequence requires a named category and recorder instance"
    normalizeParam parts[0]!

def paramParserSignature (stx : Syntax) : ParamParserSignature :=
  match normalizeParam stx with
  | .ok parser => .normalized parser
  | .error _ => .unsupported stx

partial def ParamParser.shapeTerm : ParamParser → CommandElabM (TSyntax `term)
  | .category name => `(term| ProofScript.Recording.ParamShape.category $(quote name))
  | .array element _ => do
    let inner ← element.shapeTerm
    `(term| ProofScript.Recording.ParamShape.array $inner)
  | .optional element => do
    let inner ← element.shapeTerm
    `(term| ProofScript.Recording.ParamShape.optional $inner)

/-- Normalize quotation binders; sepBy binders carry separators, many binders do not. -/
partial def ParamParser.inputTerm (parser : ParamParser) (value : TSyntax `term) :
    CommandElabM (TSyntax `term) := do
  match parser with
  | .category _ => `(term| ⟨($value).raw⟩)
  | .array inner separated =>
    let x : TSyntax `term := ⟨mkIdent `captureElement⟩
    let body ← inner.inputTerm x
    if separated then
      `(term| ($value).getElems.map (fun captureElement => $body))
    else
      `(term| ($value).map (fun captureElement => $body))
  | .optional inner =>
    let x : TSyntax `term := ⟨mkIdent `captureElement⟩
    let body ← inner.inputTerm x
    `(term| ($value).map (fun captureElement => $body))

end ProofScript.Recording
