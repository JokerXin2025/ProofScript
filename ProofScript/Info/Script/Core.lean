import ProofScript.Info.Merge
import ProofScript.Script.Registry

namespace ProofScript

open Lean Elab Command

def visibleScriptRegistrations (env : Environment) (moduleName : Name) :
    Except String (List ScriptTacticRegistration) := do
  let order ← (ModuleGraph.ofEnvironment env).modulesInDependencyOrder moduleName
    |>.mapError id
  return scriptRegistrationsInModules env order

def scriptRegistrationInView (env : Environment) (moduleName : Name) (ruleId : Name) :
    Except String ScriptTacticRegistration := do
  let some registration := (← visibleScriptRegistrations env moduleName).find? (·.ruleId == ruleId)
    | throw <| infoTargetError "script" ruleId.toString "unknown script registration"
  return registration

def resolveScriptTarget (target : TSyntax `ident) : CommandElabM Name := do
  let env ← getEnv
  let ruleId := removeRoot target.getId.eraseMacroScopes
  match scriptRegistrationInView env env.mainModule ruleId with
  | .ok registration =>
    addConstInfo target.raw registration.sourceKind
    return ruleId
  | .error _ => throwErrorAt target m!"unknown script_info registration ID `{ruleId}`"

def validateScriptContract (kind : ScriptKind) (value : ScriptInfo) :
    Except String Unit := do
  for index in [:value.templates.size] do
    let template := value.templates[index]!
    if template.isStrategy != (kind == .strategy) then
      throw <| infoFieldError "templates"
        (infoIndexError index "template kind does not match the script registration")

/-- Callers with an actual invocation's selected registration can validate that exact contract.
The default registry query below reconstructs module-end registration metadata; Info boundaries clip Info events only.
-/
def resolveScriptInfoWithRegistration (env : Environment) (moduleName : Name)
    (registration : ScriptTacticRegistration) : Except String ScriptInfo :=
  (do
    let view ← resolveTypedScript env moduleName registration.ruleId
    let result ← if view.isConfigured then view.materialize else do
      let fallback : ScriptInfo := if registration.config.isStrategy then
        { templates := #[
            .dynamicStrategy (DynamicStrategyScriptTemplate.mk .zh registration.name {}
              (DynamicScriptCase.mk "分支 ${index'}" "" {})),
            .dynamicStrategy (DynamicStrategyScriptTemplate.mk .en registration.name {}
              (DynamicScriptCase.mk "Branch ${index'}" "" {}))] } else
        { templates := #[.ordinary { lang := .zh, tag := registration.name, content := "" }] }
      pure fallback
    if result.display && result.renderer == .default && result.templates.isEmpty then
      throw <| infoFieldError "templates" "default script rendering requires a template"
    validateScriptContract registration.config.kind result
    return result : Except String ScriptInfo).mapError
       (infoTargetError "script" registration.ruleId.toString)

def resolveScriptInfo (env : Environment) (moduleName : Name) (ruleId : Name) :
    Except String ScriptInfo := do
  resolveScriptInfoWithRegistration env moduleName (← scriptRegistrationInView env moduleName ruleId)

/-- Freeze the final script configuration for export or preview. -/
def freezeScriptInfo (env : Environment) (moduleName ruleId : Name) :
    Except String ScriptInfo :=
  resolveScriptInfo env moduleName ruleId

end ProofScript
