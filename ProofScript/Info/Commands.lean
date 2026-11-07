import ProofScript.Info.Theorem
import ProofScript.Info.Definition
import ProofScript.Info.Script
import ProofScript.Core.BuildMode

open Lean Elab Command ProofScript


elab "project_info" fields:infoFields : command => do
  let pageBuild ← pageBuild?
  addInfoFieldInfos (inferInstance : InfoSchema ProjectInfo) fields
  let patch ← parsePatch (inferInstance : InfoSchema ProjectInfo) (← readFields fields)
  validateProjectInfo patch (← getRef)
  if pageBuild then
    updateProjectInfo patch (← getRef)

elab "theorem_info" id:ident fields:(infoFields)? : command => do
  let pageBuild ← pageBuild?
  for fields in fields do addInfoFieldInfos (inferInstance : InfoSchema TheoremInfo) fields
  let declaration ← resolveDeclaration id
  let patch ← parseTheoremInfo ((← fields.mapM readFields).getD #[])
  if pageBuild then
    commitInfoCommand theoremSpec declaration patch (← getRef)

elab "decl_info" target:ident fields:infoFields : command => do
  let pageBuild ← pageBuild?
  addInfoFieldInfos (inferInstance : InfoSchema DefinitionInfo) fields
  let declaration ← resolveDeclaration target
  let patch ← parsePatch (inferInstance : InfoSchema DefinitionInfo) (← readFields fields)
  if pageBuild then
    commitInfoCommand definitionSpec declaration patch (← getRef)

/-- Shorthands for the specialized definition display kinds. -/
private def specializedFields (fields : TSyntax ``infoFields) (expected : Array String) : MacroM (Array (TSyntax `term)) := do
  let `(infoFields| { $[$entries:infoField],* }) := fields
    | Macro.throwErrorAt fields "expected field assignments"
  let mut values := #[]
  for entry in entries do
    let `(infoField| $key:infoKey := $value:term) := entry
      | Macro.throwErrorAt entry "expected field := value"
    let name := match key with
      | `(infoKey| $id:ident) => id.getId.eraseMacroScopes.toString
      | `(infoKey| $text:str) => text.getString
      | _ => ""
    unless expected[values.size]? == some name do
      Macro.throwErrorAt key s!"expected `{(expected[values.size]?).getD "end of fields"}`"
    values := values.push value
  unless values.size == expected.size do
    Macro.throwErrorAt fields s!"expected fields: {String.intercalate ", " expected.toList}"
  return values

/-- Parse the command head as an identifier so field names remain usable as identifiers everywhere. -/
macro (name := specializedDefinitionInfo) (priority := low) commandName:ident declaration:ident
    fields:infoFields : command => do
  match commandName.getId.eraseMacroScopes.toString with
  | "wrapper_info" =>
    let values ← specializedFields fields #["index"]
    let index := values[0]!
    `(command| decl_info $declaration:ident {
      kind := wrapper, wrapper_info := { index := $index:term } })
  | "relation_info" =>
    let values ← specializedFields fields #["symbol"]
    let symbol := values[0]!
    `(command| decl_info $declaration:ident {
      kind := relation, relation_info := { symbol := $symbol:term } })
  | "operator_info" =>
    let values ← specializedFields fields #["symbol", "fixity", "precedence", "associativity"]
    let symbol := values[0]!
    let fixity := values[1]!
    let precedence := values[2]!
    let associativity := values[3]!
    `(command| decl_info $declaration:ident {
      kind := operator, operator_info := { symbol := $symbol:term, fixity := $fixity:term,
        precedence := $precedence:term, associativity := $associativity:term } })
  | "concept_info" =>
    let values ← specializedFields fields #["auto_arity", "templates", "default"]
    let arity := values[0]!
    let templates := values[1]!
    let default := values[2]!
    `(command| decl_info $declaration:ident {
      kind := concept, concept_info := { auto_arity := $arity:term,
        templates := $templates:term, default := $default:term } })
  | "alias_info" =>
    let values ← specializedFields fields #["target"]
    let aliasTarget := values[0]!
    `(command| decl_info $declaration:ident {
      kind := «alias», alias_info := { target := $aliasTarget:term } })
  | _ => Macro.throwErrorAt commandName "expected concept_info, wrapper_info, relation_info, operator_info or alias_info"

elab "script_info" target:ident fields:infoFields : command => do
  let pageBuild ← pageBuild?
  addInfoFieldInfos (inferInstance : InfoSchema ScriptInfo) fields
  let ruleId ← resolveScriptTarget target
  let patch ← parsePatch (inferInstance : InfoSchema ScriptInfo) (← readFields fields)
  if pageBuild then
    commitInfoCommand scriptSpec ruleId patch (← getRef)

elab "reset" "project_info" : command => do
  let pageBuild ← pageBuild?
  if pageBuild then
    resetInfo projectSpec (← getEnv).mainModule.toString (← getRef)

elab "reset" "theorem_info" target:ident : command => do
  let pageBuild ← pageBuild?
  let declaration ← resolveDeclaration target
  if pageBuild then resetInfo theoremSpec declaration (← getRef)

elab "reset" "decl_info" target:ident : command => do
  let pageBuild ← pageBuild?
  let declaration ← resolveDeclaration target
  if pageBuild then resetInfo definitionSpec declaration (← getRef)

elab "reset" "script_info" target:ident : command => do
  let pageBuild ← pageBuild?
  let ruleId ← resolveScriptTarget target
  if pageBuild then resetInfo scriptSpec ruleId (← getRef)
