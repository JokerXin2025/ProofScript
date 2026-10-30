import Lean.Elab.Command
import Lean.Elab.Syntax
import Lean.Parser.Syntax

namespace ProofScript
open Lean Elab Command

private def resolveParserKind (stx : Syntax) : CommandElabM (Except String Name) := do
  let id : TSyntax `ident := ⟨stx⟩
  match ← Lean.Elab.Command.liftTermElabM do Elab.Term.elabParserName? id with
  | some (.parser name _) =>
    return .ok <| if name == ``Parser.ident || name == ``Parser.Term.ident then `ident
      else if name == ``Parser.strLit then `str else name
  | some (.category category) => return .ok category
  | some (.alias _) =>
    match ← Lean.Elab.Command.liftIO (Parser.getSyntaxKindOfParserAlias? id.getId.eraseMacroScopes) with
    | some kind => return .ok kind
    | none => return .error s!"parser alias `{id.getId}` has no syntax kind"
  | none => return .error s!"unknown parser declaration/category/alias `{id.getId}`"

private def singleBindingParser (parts : Array Syntax) : Except String Syntax := do
  let parts := parts.filter fun part =>
    !(part.getKind == ``Parser.Syntax.cat &&
      [`colGt, `colGe, `colEq, `ppSpace, `ppLine].contains part[0].getId)
  if parts.size == 1 then return parts[0]!
  throw "compound parameter sequence produces an anonymous syntax type"

/-- Match Lean's scalar antiquotation binding. A combinator nested inside a
    container is anonymous syntax, rather than another typed container. -/
private partial def scalarBindingKind (stx : Syntax) : CommandElabM (Except String Name) := do
  if stx.getKind == ``Parser.Syntax.cat then return ← resolveParserKind stx[0]
  if stx.getKind == ``Parser.Syntax.paren then
    match singleBindingParser stx[1].getArgs with
    | .ok inner => return ← scalarBindingKind inner
    | .error message => return .error message
  return .error "parameter parser produces an anonymous syntax type"

/-- Generate only Lean type syntax for the automatic recorder's instance check.
    Recorder bindings themselves always come from the original `macroArg` nodes.
    Anonymous compound bindings are left to a handwritten recorder. -/
partial def paramBindingTypeTerm (stx : Syntax) : CommandElabM (Except String (TSyntax `term)) := do
  let kind := stx.getKind
  if kind == ``Parser.Syntax.cat || kind == ``Parser.Syntax.paren then
    match ← scalarBindingKind stx with
    | .error message => return .error message
    | .ok category => return .ok (← `(term| TSyntax $(quote category)))
  -- Prefix combinators and their postfix spellings produce the same Lean types.
  let combinator := if kind == ``Parser.Syntax.unary then stx[0].getId else Name.anonymous
  if combinator == `withPosition then
    match singleBindingParser stx[2].getArgs with
    | .error message => return .error message
    | .ok inner => return ← paramBindingTypeTerm inner
  let optional := kind == Name.mkSimple "stx_?" || combinator == `optional
  let repeated := kind == Name.mkSimple "stx_+" || kind == Name.mkSimple "stx_*" ||
    combinator == `many || combinator == `many1
  if optional || repeated then
    let inner := if kind == ``Parser.Syntax.unary then singleBindingParser stx[2].getArgs
      else .ok stx[0]
    match inner with
    | .error message => return .error message
    | .ok inner =>
      match ← scalarBindingKind inner with
      | .error message => return .error message
      | .ok category =>
        let type ← if optional then `(term| Option (TSyntax $(quote category)))
          else `(term| Array (TSyntax $(quote category)))
        return .ok type
  if kind == ``Parser.Syntax.sepBy || kind == ``Parser.Syntax.sepBy1 then
    match singleBindingParser stx[1].getArgs with
    | .error message => return .error message
    | .ok inner =>
      match ← scalarBindingKind inner with
      | .error message => return .error message
      | .ok category =>
        let separator := (⟨stx[3]⟩ : TSyntax `str).getString
        return .ok (← `(term| Syntax.TSepArray $(quote category) $(quote separator)))
  return .error "parameter parser produces an anonymous syntax type"

end ProofScript
