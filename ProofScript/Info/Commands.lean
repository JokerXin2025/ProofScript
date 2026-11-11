import ProofScript.Info.Theorem
import ProofScript.Info.Definition
import ProofScript.Info.Script
import ProofScript.Info.Freeze
import ProofScript.Core.BuildMode
import ProofScript.Utils.Linter

open Lean
open ProofScript


elab "project_info" fields:infoFields : command => do
  let pageBuild ← pageBuild?
  addInfoFieldInfos (inferInstance : InfoSchema ProjectInfo) fields
  let patch ← parsePatch (inferInstance : InfoSchema ProjectInfo) (← readFields fields)
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

/-- Split root fields by schema: definition fields, kind-specific fields, then extensions.
The kind is fixed by the command, while omitted kind-specific fields use schema defaults. -/
private def specializedDefinitionFields (kind : DefinitionKind)
    (declaration : TSyntax `ident) (fields : TSyntax ``infoFields)
    : MacroM (TSyntax `command) := do
  let (kindName, specific) : String × Array String := match kind with
  | .concept =>
      ("concept", (inferInstance : InfoSchema ConceptInfo).fields.map (·.name))
  | .wrapper =>
      ("wrapper", (inferInstance : InfoSchema WrapperInfo).fields.map (·.name))
  | .relation =>
      ("relation", (inferInstance : InfoSchema RelationInfo).fields.map (·.name))
  | .operator =>
      ("operator", (inferInstance : InfoSchema OperatorInfo).fields.map (·.name))
  | .alias =>
      ("alias", (inferInstance : InfoSchema AliasInfo).fields.map (·.name))
  let common := (inferInstance : InfoSchema DefinitionInfo).fields.filter fun field =>
    field.name != "kind" && !field.name.endsWith "_info"
  let `(infoFields| { $[$entries:infoField],* }) := fields
  | Macro.throwErrorAt fields "expected field assignments"
  let mut root : Array (TSyntax ``infoField) := #[]
  let mut specialized : Array (TSyntax ``infoField) := #[]
  let mut extensions : Array (TSyntax ``infoField) := #[]
  for entry in entries do
    let `(infoField| $key:infoKey := $_:term) := entry
    | Macro.throwErrorAt entry "expected field := value"
    let name := match key with
    | `(infoKey| $id:ident) => id.getId.eraseMacroScopes.toString
    | `(infoKey| $text:str) => text.getString
    | _ => ""
    if name == "kind" then
      Macro.throwErrorAt key "kind is fixed by the specialized info command"
    else if common.any (·.name == name) then
      root := root.push entry
    else if specific.contains name then
      specialized := specialized.push entry
    else
      extensions := extensions.push entry
  let categoryKey ← `(infoKey| $(mkIdent (Name.mkSimple (kindName ++ "_info"))):ident)
  let nested ← `(infoField| $categoryKey:infoKey := { $[$specialized:infoField],* })
  let assignments := root ++ #[nested] ++ extensions
  let kindId := mkIdent (Name.mkSimple kindName)
  `(command| decl_info $declaration:ident { kind := $kindId, $[$assignments],* })

macro "wrapper_info" declaration:ident fields:infoFields : command => do
  specializedDefinitionFields .wrapper declaration fields

macro "relation_info" declaration:ident fields:infoFields : command => do
  specializedDefinitionFields .relation declaration fields

macro "operator_info" declaration:ident fields:infoFields : command => do
  specializedDefinitionFields .operator declaration fields

macro "concept_info" declaration:ident fields:infoFields : command => do
  specializedDefinitionFields .concept declaration fields

macro "alias_info" declaration:ident fields:infoFields : command => do
  specializedDefinitionFields .alias declaration fields

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
    let env ← getEnv
    resetInfo projectSpec env.mainModule.toString (← getRef)

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

open Elab.Command in section

private def previewInfo (identity : InfoTarget) : CommandElabM Unit := do
  let env ← getEnv
  match freezeInfo env { moduleName := env.mainModule } identity with
  | .error diagnostic => throwError diagnostic.render
  | .ok record =>
    logInfo m!"{record.identity.kind} {toString record.identity.target}: {record.value.pretty}"

elab "#preview" "project_info" : command => do
  allowHashCommandLint do
    let env ← getEnv
    let library := env.mainModule.components.head?.getD env.mainModule |>.toString
    let libraryPrefix := Name.mkSimple library
    match freezeInfo env { moduleName := env.mainModule }
        ⟨projectSpec.kind, .inr library⟩
        (some fun owner => owner == libraryPrefix || libraryPrefix.isPrefixOf owner) with
    | .error diagnostic => throwError diagnostic.render
    | .ok record => logInfo m!"project {library}: {record.value.pretty}"

elab "#preview" "theorem_info" target:ident : command => do
  allowHashCommandLint do
    previewInfo { kind := theoremSpec.kind, target := .inl (← resolveDeclaration target) }

elab "#preview" "decl_info" target:ident : command => do
  allowHashCommandLint do
    previewInfo { kind := definitionSpec.kind, target := .inl (← resolveDeclaration target) }

elab "#preview" "script_info" target:ident : command => do
  allowHashCommandLint do
    previewInfo { kind := scriptSpec.kind, target := .inl (← resolveScriptTarget target) }

end
