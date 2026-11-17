import ProofScript.Info.Script.Core
import ProofScript.Info.TypedElab
import ProofScript.Core.BuildMode
import ProofScript.Utils.Linter

namespace ProofScript

open Lean Elab Command

elab "script_info" target:ident fields:infoFields : command => do
  InputField.annotateFields (Field := ScriptField) ``ScriptInfo fields
  let ruleId ← resolveScriptTarget target
  let edits ← InputField.parseEdits (← InputField.readFields (Field := ScriptField) fields)
  if ← pageBuild? then
    TypedInfoChange.commit (.script ruleId edits) fields
  else
    TypedInfoChange.check (.script ruleId edits) fields

private def currentScriptTemplates (ruleId : Name) (ref : Syntax) :
    CommandElabM (Array ScriptTemplate) := do
  let env ← getEnv
  let view ← match resolveTypedScript env env.mainModule ruleId with
    | .ok view => pure view
    | .error error => throwErrorAt ref error
  match view.readTemplates with
  | .ok templates => return templates
  | .error error => throwErrorAt ref error

private def currentScriptBoard (ruleId : Name) (ref : Syntax) :
    CommandElabM ScriptBoardInput := do
  let env ← getEnv
  let view ← match resolveTypedScript env env.mainModule ruleId with
    | .ok view => pure view
    | .error error => throwErrorAt ref error
  match view.readBoard with
  | .ok board => return board
  | .error error => throwErrorAt ref error

private def scriptTemplateAdditions (entries : TSyntax `term) : CommandElabM (Array ScriptTemplate) := do
  liftCoreM <| InfoCodec.annotate (α := Array ScriptTemplate) entries
  let templates ← liftCoreM <| InfoCodec.decode (α := Array ScriptTemplate) entries
  return templates

private def scriptTemplateRemovals (entries : TSyntax `term) : CommandElabM (Array String) := do
  let `(term| [$[$languages:term],*]) := entries
    | throwErrorAt entries "expected a list of languages"
  let mut keys := #[]
  for language in languages do
    let lang ← liftCoreM <| InfoCodec.decode (α := Language) language
    if lang.code.isEmpty then throwErrorAt language "template language must not be empty"
    if keys.contains lang.code then throwErrorAt language s!"duplicate template language `{lang.code}`"
    keys := keys.push lang.code
  return keys

elab "script_info" &"templates" target:ident "+" entries:term : command => do
  let ruleId ← resolveScriptTarget target
  let additions ← scriptTemplateAdditions entries
  if ← pageBuild? then
    let previous ← currentScriptTemplates ruleId target
    for template in additions do
      if previous.any (·.lang == template.lang) then
        throwErrorAt entries m!"template language `{template.lang}` already exists"
    TypedInfoChange.commit (.script ruleId #[⟨.templates, previous ++ additions⟩]) entries
  else
    TypedInfoChange.check (.script ruleId #[⟨.templates, additions⟩]) entries

elab "script_info" &"templates" target:ident "-" entries:term : command => do
  let ruleId ← resolveScriptTarget target
  let removals ← scriptTemplateRemovals entries
  if ← pageBuild? then
    let previous ← currentScriptTemplates ruleId target
    for lang in removals do
      unless previous.any (·.lang == lang) do
        throwErrorAt entries m!"template language `{lang}` does not exist"
    let templates := previous.filter fun template => !removals.contains template.lang
    TypedInfoChange.commit (.script ruleId #[⟨.templates, templates⟩]) entries

elab "script_info" &"board" target:ident "+" entries:term : command => do
  let ruleId ← resolveScriptTarget target
  liftCoreM <| InfoCodec.annotate (α := ScriptBoardInput) entries
  let additions ← liftCoreM <| InfoCodec.decode (α := ScriptBoardInput) entries
  if ← pageBuild? then
    let previous ← currentScriptBoard ruleId target
    TypedInfoChange.commit (.script ruleId #[⟨.board, ⟨previous.value ++ additions.value⟩⟩]) entries
  else
    TypedInfoChange.check (.script ruleId #[⟨.board, additions⟩]) entries

elab "script_info" &"board" target:ident "-" entries:term : command => do
  let ruleId ← resolveScriptTarget target
  liftCoreM <| InfoCodec.annotate (α := ScriptBoardInput) entries
  let removals ← liftCoreM <| InfoCodec.decode (α := ScriptBoardInput) entries
  if ← pageBuild? then
    let mut board ← currentScriptBoard ruleId target
    for entry in removals.value do
      unless board.value.contains entry do
        throwErrorAt entries m!"board entry {repr entry} does not exist"
      board := ⟨board.value.erase entry⟩
    TypedInfoChange.commit (.script ruleId #[⟨.board, board⟩]) entries

elab "reset" "script_info" target:ident : command => do
  let pageBuild ← pageBuild?
  let ruleId ← resolveScriptTarget target
  if pageBuild then TypedInfoChange.commit (.resetScript ruleId) target

elab "#preview" "script_info" target:ident : command => do
  allowHashCommandLint do
    let ruleId ← resolveScriptTarget target
    let env ← getEnv
    let value ← match freezeScriptInfo env env.mainModule ruleId with
      | .ok value => pure value
      | .error diagnostic => throwErrorAt target diagnostic
    logInfo m!"script {ruleId}: {(toJson value).pretty}"

end ProofScript
