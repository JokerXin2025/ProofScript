import ProofScript.Info.Value

namespace ProofScript

open Lean Elab Command Parser.Term

syntax infoKey := ident <|> str
syntax infoField := infoKey " := " term
syntax infoFields := "{" sepBy(infoField, ", ") "}"

/-- Lower priority preserves ordinary Lean structure terms; quoted keys use this literal parser. -/
syntax (name := infoObject) (priority := low) "{" sepBy(infoField, ", ") "}" : term
syntax (name := resetValue) "reset" : term

structure InputField where
  key : String
  ref : Syntax
  value : TSyntax `term

def readFields (stx : TSyntax ``infoFields) : CommandElabM (Array InputField) := do
  let `(infoFields| { $[$fields:infoField],* }) := stx
    | throwErrorAt stx "expected a field object"
  fields.mapM fun field => do
    match field with
    | `(infoField| $key:infoKey := $value:term) =>
      let name ← match key with
        | `(infoKey| $id:ident) => pure id.getId.eraseMacroScopes.toString
        | `(infoKey| $text:str) => pure text.getString
        | _ => throwErrorAt key "expected a field name"
      return { key := name, ref := key.raw, value }
    | _ => throwErrorAt field "expected field := value"

def readObject (stx : TSyntax `term) : CommandElabM (Array InputField) := do
  if let `(term| { $[$fields:infoField],* }) := stx then
    let object ← `(infoFields| { $[$fields:infoField],* })
    return ← readFields object
  let `(term| { $[$fields:structInstField],* }) := stx
    | throwErrorAt stx "expected a field object"
  fields.mapM fun field => do
    match field with
    | `(structInstField| $key:ident := $value:term) =>
      return { key := key.getId.eraseMacroScopes.toString, ref := key.raw, value }
    | _ => throwErrorAt field "expected field := value"

def isReset (stx : TSyntax `term) : Bool := stx.raw.isOfKind ``resetValue

/-- Parse JSON literals directly; no elaboration or evaluation of arbitrary Lean code. -/
partial def parseExtraValue (stx : TSyntax `term) : CommandElabM ExtraValue := do
  match stx with
  | `(term| $text:str) => return .str text.getString
  | `(term| $number:num) => return .num (JsonNumber.fromNat number.getNat)
  | `(term| true) => return json% true
  | `(term| false) => return json% false
  | `(term| null) => return json% null
  | `(term| none) => return json% null
  | `(term| - $value:term) =>
    let .num number ← parseExtraValue value
      | throwErrorAt stx "expected a numeric literal after '-'"
    return .num (-number)
  | `(term| [$[$items:term],*]) => return .arr (← items.mapM parseExtraValue)
  | _ =>
    if stx.raw.isOfKind ``infoObject || stx.raw.isOfKind ``Lean.Parser.Term.structInst then
      let fields ← readObject stx
      let mut result : List (String × Json) := []
      for field in fields do
        if result.any (·.1 == field.key) then
          throwErrorAt field.ref m!"duplicate extension key `{field.key}`"
        result := result ++ [(field.key, ← parseExtraValue field.value)]
      return Json.mkObj result
    if stx.raw.isOfKind scientificLitKind then
      let text := stx.raw[0].getAtomVal.replace "_" ""
      match Json.parse text with
      | .ok (.num number) => return .num number
      | _ => throwErrorAt stx "invalid numeric literal"
    throwErrorAt stx "expected a JSON literal (string, number, boolean, null, array or object)"

end ProofScript
