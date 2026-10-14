import ProofScript.Lean2TeX.Registry

namespace ProofScript

open Lean Elab.Command
open Lean.Parser.Term

syntax lean2texField := ident " := " term
syntax (name := defInfoCmd) "def_info" ident "{" sepBy1(lean2texField, ", ") "}" : command
syntax (name := varInfoCmd) "var_info" str "{" sepBy1(lean2texField, ", ") "}" : command
syntax (name := phraseInfoCmd) "phrase_info" str "{" sepBy1(lean2texField, ", ") "}" : command

private def fieldsOf (value : TSyntax `term) (allowed required : List String) :
    CommandElabM (List (String × TSyntax `term)) := do
  let `(term| { $[$fields:structInstField],* }) := value
    | throwErrorAt value "expected a field object"
  let mut result : List (String × TSyntax `term) := []
  for field in fields do
    let `(structInstField| $key:ident := $entry:term) := field
      | throwErrorAt field "expected field := value"
    let name := key.getId.toString
    unless allowed.contains name do throwErrorAt field m!"unknown field `{name}`"
    if result.any (·.1 == name) then throwErrorAt field m!"duplicate field `{name}`"
    result := result ++ [(name, entry)]
  for name in required do
    unless result.any (·.1 == name) do throwErrorAt value m!"missing field `{name}`"
  return result

private def strValue (value : TSyntax `term) : CommandElabM String := do
  let `(term| $text:str) := value | throwErrorAt value "expected a string literal"
  return text.getString

private def natValue (value : TSyntax `term) : CommandElabM Nat := do
  let `(term| $number:num) := value | throwErrorAt value "expected a natural number"
  return number.getNat

private def boolValue (value : TSyntax `term) : CommandElabM Bool := do
  match value with
  | `(term| true) => return true
  | `(term| false) => return false
  | _ => throwErrorAt value "expected true or false"

private def identValue (value : TSyntax `term) (allowed : List String) : CommandElabM String := do
  let `(term| $id:ident) := value | throwErrorAt value "expected a single identifier"
  let name := id.getId.eraseMacroScopes.toString
  unless allowed.contains name do throwErrorAt value m!"invalid value `{name}`"
  return name

private def declaration (id : TSyntax `ident) : CommandElabM Name := do
  let resolved ← Lean.resolveGlobalConstNoOverload id.raw
  unless (← getEnv).contains resolved do
    throwErrorAt id m!"unknown declaration `{id.getId}`"
  return resolved

private def optionValue (value : TSyntax `term) (parse : TSyntax `term → CommandElabM Json) :
    CommandElabM Json := do
  match value with
  | `(term| none) => return Json.null
  | `(term| some $item:term) => parse item
  | _ => throwErrorAt value "expected none or some value"

private def arrayValue (value : TSyntax `term) (parse : TSyntax `term → CommandElabM Json) :
    CommandElabM Json := do
  let `(term| [$[$items],*]) := value | throwErrorAt value "expected an array"
  return Json.arr (← items.mapM parse)

private def binderValue (value : TSyntax `term) : CommandElabM Json := do
  let `(term| ($index, $count)) := value
    | throwErrorAt value "expected (argument index, binder count)"
  return toJson #[← natValue index, ← natValue count]

private def styleValue (value : TSyntax `term) : CommandElabM Json := do
  let fields ← fieldsOf value
    ["name", "mode", "template", "fixity", "precedence", "associativity",
      "separator", "binders", "isolated_arguments"] ["template"]
  let mut result : List (String × Json) := []
  for (key, item) in fields do
    let parsed ← if ["name", "template", "separator"].contains key then
        toJson <$> strValue item
      else if key == "mode" then
        toJson <$> identValue item ["formula", "text"]
      else if key == "fixity" then
        toJson <$> identValue item
          ["atom", "prefix", "postfix", "infix", "binder", "application", "custom"]
      else if key == "associativity" then
        toJson <$> identValue item ["left", "right", "none"]
      else if key == "precedence" then
        toJson <$> natValue item
      else if key == "binders" then
        arrayValue item binderValue
      else if key == "isolated_arguments" then
        arrayValue item fun entry => toJson <$> natValue entry
      else throwErrorAt item "invalid style field"
    result := result ++ [(key, parsed)]
  return Json.mkObj result

private def definitionValue (key : String) (value : TSyntax `term) : CommandElabM Json := do
  if key == "kind" then
    return toJson (← identValue value
      ["const", "operator", "relation", "logic", "projection", "constructor", "type"])
  else if key == "arguments" then
    match value with
    | `(term| explicit) => return toJson "explicit"
    | _ => return ← arrayValue value fun item => toJson <$> natValue item
  else if key == "dynamic_arity" then return toJson (← boolValue value)
  else if key == "styles" then return ← arrayValue value styleValue
  else if key == "calc_symbol" then
    return ← optionValue value fun item => toJson <$> strValue item
  else if key == "unwrap" then
    return ← optionValue value fun item => toJson <$> natValue item
  else if key == "alias" then
    return ← optionValue value fun item => do
      let `(term| $target:ident) := item
        | throwErrorAt item "alias must be a declaration identifier"
      return toJson (← declaration target).toString
  else throwErrorAt value m!"unknown def_info field `{key}`"

private def phraseEntry (value : TSyntax `term) : CommandElabM Json := do
  let fields ← fieldsOf value ["lang", "content"] ["lang", "content"]
  return Json.mkObj (← fields.mapM fun (key, item) => do
    return (key, toJson (← strValue item)))

private def addEvent (category target : String)
    (fields : Array (TSyntax ``lean2texField)) :
    CommandElabM Unit := do
  let mut assigned : List String := []
  let mut patch : List (String × Json) := []
  for field in fields do
    let `(lean2texField| $key:ident := $value:term) := field
      | throwErrorAt field "expected field := value"
    let key := key.getId.toString
    let allowed := match category with
      | "definition" => ["kind", "arguments", "dynamic_arity", "styles", "calc_symbol", "unwrap", "alias"]
      | "variable" => ["default", "names"]
      | _ => ["template"]
    unless allowed.contains key do throwErrorAt field m!"unknown {category} field `{key}`"
    if assigned.contains key then throwErrorAt field m!"duplicate field `{key}`"
    assigned := key :: assigned
    let parsed ← if category == "definition" then definitionValue key value
      else if category == "variable" then
        if key == "default" then toJson <$> strValue value
        else arrayValue value fun item => toJson <$> strValue item
      else arrayValue value phraseEntry
    patch := patch ++ [(key, parsed)]
  let env ← getEnv
  let owner ← getMainModule
  let fileName ← getFileName
  let sourceStx ← getRef
  let source := do
    let start ← sourceStx.getPos?
    let stop ← sourceStx.getTailPos?
    pure <| Json.mkObj [
      ("file", toJson fileName), ("start", toJson start.byteIdx),
      ("stop", toJson stop.byteIdx)]
  let env := addLean2TeXEvent env {
    owner, sequence := (localLean2TeXEvents env).size,
    category, target, fields := Json.mkObj patch, source
  }
  setEnv env
  liftIO <| exportLean2TeXEvents env

elab_rules : command
  | `(command| def_info%$_ $target:ident { $[$fields:lean2texField],* }) => do
      addEvent "definition" (← declaration target).toString fields
  | `(command| var_info%$_ $target:str { $[$fields:lean2texField],* }) => do
      if target.getString.isEmpty then throwErrorAt target "variable key must not be empty"
      addEvent "variable" target.getString fields
  | `(command| phrase_info%$_ $target:str { $[$fields:lean2texField],* }) => do
      if target.getString.isEmpty then throwErrorAt target "phrase key must not be empty"
      addEvent "phrase" target.getString fields

end ProofScript
