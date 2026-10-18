import ProofScript

open Lean Elab Command ProofScript ProofScript.Info

namespace RendererDependencyScope

project_info "RendererDependencyScope" { title := "Renderer dependencies" }
phrase_info "rendererScopeOnly" { template := [{ lang := "en", content := "renderer dependency" }] }

script_macro scopeExact "renderer_scope_exact" proof:term => `(tactic| exact $proof:term)
script_info scopeExact { template := [{ lang := "en", tag := "Exact", content := "" }] }

@theorem beforeRegistration : True := script
  renderer_scope_exact True.intro

page_end

run_cmd do
  let env ← getEnv
  let owner := env.mainModule
  let before ← match freezeModuleArtifacts env owner with
    | .ok snapshots => pure snapshots
    | .error error => throwError error.render
  let dependency : Output.RenderDependency := {
    kind := "phrase", target := .inl (Name.mkSimple "rendererScopeOnly"), required := true }
  let next := declareRendererDependencies env .automatic #[dependency]
  unless currentBoundary next != currentBoundary env &&
      (moduleEvents next owner).size == (moduleEvents env owner).size do
    throwError "renderer dependency registration must advance the clock without inventing an Info event"
  let after ← match freezeModuleArtifacts next owner with
    | .ok snapshots => pure snapshots
    | .error error => throwError error.render
  unless before.size == after.size && (before.zip after).all (fun (old, new) =>
      old.1 == new.1 && old.2.id == new.2.id) do
    throwError "a renderer registration after page_end changed an existing page or proof snapshot"
  let some proof := (Output.moduleArtifacts env owner).find?
      (·.declaration == some `RendererDependencyScope.beforeRegistration)
    | throwError "missing earlier proof artifact"
  let some (_, oldSnapshot) := before.find? (·.1 == proof.key.id)
    | throwError "missing earlier proof snapshot"
  unless (moduleSnapshots next owner).any (·.id == oldSnapshot.id) do
    throwError "exported proof snapshot disagrees with the snapshot persisted for its page component"
  if (oldSnapshot.find? "phrase" (.inl (Name.mkSimple "rendererScopeOnly"))).isSome then
    throwError "a later renderer dependency leaked into an earlier proof"
  -- Simulate an imported entry's owner and sequence. A local boundary of zero
  -- must retain upstream registrations, while excluding the later local entry.
  let some binding := proof.bindings[0]? | throwError "missing invocation contract"
  let imported := rendererDependencyExt.addEntry next {
    owner := `ProofScript.Defaults.Lean2TeX, sequence := 1000000,
    renderer := .automatic,
    dependencies := #[{ kind := "phrase", target := .inl (Name.mkSimple "forall"), required := true }] }
  let importedSnapshot ← match freezeSnapshot imported { moduleName := owner, boundary := .before 0 }
      #[] #[binding.contract] with
    | .ok snapshot => pure snapshot
    | .error error => throwError error.render
  unless (importedSnapshot.find? "phrase" (.inl (Name.mkSimple "forall"))).isSome &&
      (importedSnapshot.find? "phrase" (.inl (Name.mkSimple "rendererScopeOnly"))).isNone do
    throwError "local boundaries must retain all upstream renderer dependencies and exclude later local ones"
  setEnv next

/-- warning: page component appears after page_end and was ignored -/
#guard_msgs in
@theorem afterRegistration : True := script
  renderer_scope_exact True.intro

run_cmd do
  let env ← getEnv
  let some artifact := (Output.moduleArtifacts env env.mainModule).find?
      (·.declaration == some `RendererDependencyScope.afterRegistration)
    | throwError "missing later proof artifact"
  let snapshot ← match freezeArtifacts env artifact.query #[artifact] with
    | .ok snapshot => pure snapshot
    | .error error => throwError error.render
  unless (snapshot.find? "phrase" (.inl (Name.mkSimple "rendererScopeOnly"))).isSome do
    throwError "subsequent local content did not receive the new renderer dependency"

end RendererDependencyScope
