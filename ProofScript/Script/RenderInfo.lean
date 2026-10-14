import ProofScript.Script.Config
import ProofScript.Render.Registry

namespace ProofScript

open Lean Elab.Command
open Lean.Parser.Term

syntax scriptInfoField := ident " := " term
syntax (name := scriptInfoCmd) "script_info" ident "{" sepBy1(scriptInfoField, ", ") "}" : command

private def allowedRenderFields : List String :=
  ["renderer", "template", "display", "color"]

private def parseFields (value : TSyntax `term) (allowed required : List String) :
    CommandElabM (List (String × TSyntax `term)) := do
  let `(term| { $[$fields:structInstField],* }) := value
  | throwErrorAt value "expected a field object"
  let mut result := []
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

private def stringField (fields : List (String × TSyntax `term)) (name : String) :
    CommandElabM String := do
  let some value := fields.lookup name | throwError m!"missing field `{name}`"
  let `(term| $text:str) := value | throwErrorAt value m!"`{name}` must be a string"
  return text.getString

private def boolValue (value : TSyntax `term) : CommandElabM Bool := do
  match value with
  | `(term| true) => return true
  | `(term| false) => return false
  | _ => throwErrorAt value "expected true or false"

private def optionalColor (value : TSyntax `term) : CommandElabM Json := do
  match value with
  | `(term| none) => return Json.null
  | `(term| some $text:str) =>
    let color := text.getString
    let digits := color.toList.drop 1
    unless color.startsWith "#" && [3, 4, 6, 8].contains digits.length &&
        digits.all (fun digit => digit.isDigit || ('a' ≤ digit && digit ≤ 'f') ||
          ('A' ≤ digit && digit ≤ 'F')) do
      throwErrorAt value "color must be a hexadecimal CSS color (#RGB, #RGBA, #RRGGBB or #RRGGBBAA)"
    return toJson color
  | _ => throwErrorAt value "expected none or some color string"

private def parseColor (value : TSyntax `term) : CommandElabM Json := do
  let `(term| ($tag, $border, $background)) := value
  | throwErrorAt value "color expects (Option String, Option String, Option String)"
  return toJson #[← optionalColor tag, ← optionalColor border, ← optionalColor background]

private def parseIntroducer (value : TSyntax `term) : CommandElabM Json := do
  let fields ← parseFields value ["tag", "content"] ["tag", "content"]
  return Json.mkObj [("tag", toJson (← stringField fields "tag")),
    ("content", toJson (← stringField fields "content"))]

private def parseCase (value : TSyntax `term) : CommandElabM Json := do
  let fields ← parseFields value ["name", "tag", "title", "introducer"] ["name", "tag", "title"]
  let name ← stringField fields "name"
  if name.isEmpty then throwErrorAt value "case name must not be empty"
  let mut result := [("name", toJson name), ("tag", toJson (← stringField fields "tag")),
    ("title", toJson (← stringField fields "title"))]
  if let some intro := fields.lookup "introducer" then
    result := result ++ [("introducer", ← parseIntroducer intro)]
  return Json.mkObj result

private def parseTemplateEntry (value : TSyntax `term) (strategy : Bool) : CommandElabM Json := do
  let fields ← if strategy then
      parseFields value ["lang", "tag", "inline", "introducer", "cases"] ["lang", "tag", "cases"]
    else parseFields value ["lang", "tag", "content"] ["lang", "tag", "content"]
  let lang ← stringField fields "lang"
  if lang.isEmpty then throwErrorAt value "template language must not be empty"
  let mut result := [("lang", toJson lang), ("tag", toJson (← stringField fields "tag"))]
  if strategy then
    if let some inline := fields.lookup "inline" then
      result := result ++ [("inline", toJson (← boolValue inline))]
    if let some intro := fields.lookup "introducer" then
      result := result ++ [("introducer", ← parseIntroducer intro)]
    let some cases := fields.lookup "cases" | throwErrorAt value "missing cases"
    let `(term| [$[$items],*]) := cases | throwErrorAt cases "cases expects an array"
    if items.isEmpty then throwErrorAt cases "cases must not be empty"
    let mut parsed : Array Json := #[]
    for item in items do
      let entry ← parseCase item
      let name := (entry.getObjValAs? String "name").toOption.getD ""
      if parsed.any (fun old => (old.getObjValAs? String "name").toOption == some name) then
        throwErrorAt item "duplicate case name"
      parsed := parsed.push entry
    let inline ← match fields.lookup "inline" with
    | some flag => boolValue flag
    | none => pure false
    if inline && parsed.size != 1 then
      throwErrorAt cases "inline requires exactly one case"
    if inline then
      let only := parsed[0]!
      if (only.getObjValAs? String "tag").toOption.getD "" != "" ||
          (only.getObjValAs? String "title").toOption.getD "" != "" then
        throwErrorAt cases "inline case must have empty tag and title"
    result := result ++ [("cases", Json.arr parsed)]
  else
    result := result ++ [("content", toJson (← stringField fields "content"))]
  return Json.mkObj result

private def parseRenderTemplate (value : TSyntax `term) (strategy : Bool) : CommandElabM Json := do
  match value with
  | `(term| [$[$items],*]) =>
      let mut result : Array Json := #[]
      for item in items do
        let entry ← parseTemplateEntry item strategy
        let lang := (entry.getObjValAs? String "lang").toOption.getD ""
        if result.any (fun old => (old.getObjValAs? String "lang").toOption == some lang) then
          throwErrorAt item "duplicate language in script_info field"
        result := result.push entry
      if result.isEmpty then throwErrorAt value "template must not be empty"
      return Json.arr result
  | _ => throwErrorAt value "template expects a nonempty array"

elab_rules : command
  | `(command| script_info%$_ $target:ident { $[$fields:scriptInfoField],* }) => do
      let env ← getEnv
      let moduleName ← getMainModule
      let targetName := target.getId.eraseMacroScopes
      let rules := renderRegistrationExt.getState env
      let ruleId := if targetName.components.length == 1 then moduleName ++ targetName else targetName
      let some rule := rules.find? (·.id == ruleId)
        | throwErrorAt target m!"unknown script_info registration ID `{ruleId}`; use its full module-qualified ID for imported rules"
      let mut assigned : List String := []
      let mut patch : List (String × Json) := []
      if fields.isEmpty then throwErrorAt target "script_info requires at least one field"
      for field in fields do
        match field with
        | `(scriptInfoField| $key:ident := $value:term) =>
          let key := key.getId.toString
          unless allowedRenderFields.contains key do
            throwErrorAt field m!"unknown script_info field `{key}`"
          if assigned.contains key then
            throwErrorAt field m!"duplicate script_info field `{key}`"
          assigned := key :: assigned
          if key == "renderer" then
            match value with
            | `(term| $name:ident) =>
              let name := name.getId.eraseMacroScopes.toString
              if name.isEmpty || name.contains '.' then
                throwErrorAt value "renderer must be a single registered identifier"
              patch := patch ++ [(key, toJson name)]
            | _ => throwErrorAt value "renderer must be a single registered identifier"
           else if key == "display" then
             patch := patch ++ [(key, toJson (← boolValue value))]
           else if key == "color" then
             patch := patch ++ [(key, ← parseColor value)]
           else
             let template ← parseRenderTemplate value rule.strategy
             if let some recorded := rule.recordedFields then
               if let .error message := Recording.validateTemplateFields recorded template then
                 throwErrorAt value "{message}"
             patch := patch ++ [(key, template)]
        | _ => throwErrorAt field "invalid script_info field"
      let sequence := (localRenderUpdates env).size
      let env := addRenderUpdate (← getEnv) {
        owner := moduleName, sequence, ruleId := rule.id, fields := Json.mkObj patch
      }
      setEnv env
      liftIO <| exportRenderEvents env
      match ← liftIO <| exportEffectiveRenderRules env with
      | .ok () => pure ()
      | .error message => throwError "{message}"

end ProofScript
