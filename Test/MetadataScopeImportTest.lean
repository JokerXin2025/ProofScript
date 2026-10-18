import Test.MetadataScopeTest

open Lean Elab Command ProofScript ProofScript.Info

namespace MetadataScopeImport

project_info "MetadataScope.P" {}

@theorem importedUse : ∀ _ : Nat, True := script
  scope_exact (fun _ => True.intro)

@theorem importedDependency : True := by exact MetadataScope.referenceTarget

-- Even a later importer edit must not change either the imported proof or preceding local code.
script_info Test.MetadataScopeTest.scopeExact { display := false }
theorem_info MetadataScope.referenceTarget { project := "MetadataScope.Q" }

run_cmd do
  let env ← getEnv
  let owner := `Test.MetadataScopeTest
  let upstream ← match freezeModuleTheorems env owner with
    | .ok facts => pure facts
    | .error error => throwError error.render
  let some (_, early) := upstream.find? (·.2.value.declaration == `MetadataScope.earlyDependency)
    | throwError "imported proof facts are missing"
  unless early.value.projectId == "MetadataScope.P" &&
      early.value.proofDependencies == #[`MetadataScope.referenceTarget] do
    throwError "importing reinterpreted upstream content with final or importer-local metadata"
  let own ← match freezeModuleTheorems env env.mainModule with
    | .ok facts => pure facts
    | .error error => throwError error.render
  let some (_, dependency) := own.find? (·.2.value.declaration == `MetadataScopeImport.importedDependency)
    | throwError "importer dependency facts are missing"
  unless dependency.value.proofDependencies == #[`MetadataScope.referenceTarget] do
    throwError "an importer failed to inherit upstream final project metadata"
  let artifacts := Output.moduleArtifacts env env.mainModule
  let some artifact := artifacts.find? (·.declaration == some `MetadataScopeImport.importedUse)
    | throwError "importer artifact is missing"
  let snapshots ← match freezeModuleArtifacts env env.mainModule with
    | .ok snapshots => pure snapshots
    | .error error => throwError error.render
  let some (_, snapshot) := snapshots.find? (·.1 == artifact.key.id)
    | throwError "importer snapshot is missing"
  let read := fun (kind : String) (target : Name ⊕ String) => do
    let some record := snapshot.find? kind target
      | throwError m!"missing imported {kind} configuration"
    pure record.value
  let ruleInfo : ScriptInfo ← ofExcept <| fromJson? (← read "script" (.inl `Test.MetadataScopeTest.scopeExact))
  let variableInfo : VariableInfo ← ofExcept <| fromJson? (← read "variable" (.inl (Name.mkSimple "Nat")))
  let phrase : PhraseInfo ← ofExcept <| fromJson? (← read "phrase" (.inl (Name.mkSimple "forall")))
  let project : ProjectInfo ← ofExcept <| fromJson? (← read "project" (.inr "MetadataScope.P"))
  unless ruleInfo.display && ruleInfo.template.any (fun template => match template with
        | .ordinary value => value.lang == "en" && value.tag == "Imported rule"
        | .strategy _ => false) &&
      variableInfo.default == "z" && phrase.template.any (fun value => value.lang == "en" && value.content == "imported ${binder}") &&
      project.title == "Imported project" do
    throwError "upstream post-page configuration was omitted or later local configuration leaked backward"

page_end

end MetadataScopeImport
