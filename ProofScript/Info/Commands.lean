import ProofScript.Info.Theorem
import ProofScript.Info.Variable
import ProofScript.Info.Phrase
import ProofScript.Info.Definition
import ProofScript.Info.Script
import ProofScript.Core.BuildMode

open Lean Elab Command ProofScript Info


elab "project_info" target:(str)? fields:infoFields : command => do
  let pageBuild ← recordModuleBuildMode
  addInfoFieldInfos (inferInstance : InfoSchema ProjectInfo) fields
  if pageBuild then updateProjectInfo target (← readFields fields) (← getRef)

elab "theorem_info" id:ident fields:(infoFields)? : command => do
  let pageBuild ← recordModuleBuildMode
  for fields in fields do addInfoFieldInfos (inferInstance : InfoSchema TheoremInfo) fields
  if pageBuild then
    updateTheoremInfo id ((← fields.mapM readFields).getD #[]) (← getRef)
  else
    addDeclarationReferenceInfo id

elab "var_info" target:str fields:infoFields : command => do
  let pageBuild ← recordModuleBuildMode
  addInfoFieldInfos (inferInstance : InfoSchema VariableInfo) fields
  if pageBuild then updateLiteralInfo variableSpec target (← readFields fields) (← getRef)

elab "phrase_info" target:str fields:infoFields : command => do
  let pageBuild ← recordModuleBuildMode
  addInfoFieldInfos (inferInstance : InfoSchema PhraseInfo) fields
  if pageBuild then updateLiteralInfo phraseSpec target (← readFields fields) (← getRef)

elab "def_info" target:ident fields:infoFields : command => do
  let pageBuild ← recordModuleBuildMode
  addInfoFieldInfos (inferInstance : InfoSchema DefinitionInfo) fields
  if pageBuild then
    updateDeclarationInfo definitionSpec target (← readFields fields) (← getRef)
  else
    addDeclarationReferenceInfo target

elab "script_info" target:ident fields:infoFields : command => do
  let pageBuild ← recordModuleBuildMode
  addInfoFieldInfos (inferInstance : InfoSchema ScriptInfo) fields
  if pageBuild then
    updateScriptInfo target (← readFields fields) (← getRef)
  else
    addScriptTargetInfo target
