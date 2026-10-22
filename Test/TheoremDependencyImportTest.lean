import Test.TheoremDependencyModuleTest
import Test.TheoremDependencyConflict

open Lean Elab Command ProofScript.Info

project_info "Export.context" { title := "Exporter context" }
theorem_info TheoremDependencyModule.standalone { project := "Export.context" }

@theorem conflictConsumer : True := by exact TheoremDependencyFacts.ordinary

run_cmd do
  let env ← getEnv
  let owner := `Test.TheoremDependencyModuleTest
  let facts ← match freezeModuleTheorems env owner with
    | .ok facts => pure facts
    | .error error => throwError error.render
  unless facts.size == 1 && facts[0]!.2.query.moduleName == owner &&
      facts[0]!.2.value.projectId == "Facts.other" &&
      facts[0]!.2.value.proofDependencies == #[`TheoremDependencyFacts.declarationDefault] do
    throwError "exporter's metadata changed an imported standalone proof's owner view"
  let query : Query := { moduleName := env.mainModule }
  match freezeTheoremFacts env query "test" `conflictConsumer with
  | .error error =>
    unless error.path == #[.key "project"] &&
        error.related.any (·.owner == `Test.TheoremDependencyModuleTest) &&
        error.related.any (·.owner == `Test.TheoremDependencyConflict) do
      throwError "conflicting target projects lost their independent origins"
  | .ok _ => throwError "conflicting target ownership was silently ignored"
  let source : ProofScript.Foundation.SourceLocation := ⟨"conflict-resolution", 0, 0⟩
  let resolved ← match commitInfo theoremSpec env `TheoremDependencyFacts.ordinary
      #[TheoremInfo.infoFields.project.assignment (some "Export.context") source] source with
    | .ok env => pure env
    | .error error => throwError error.render
  match freezeTheoremFacts resolved query "test" `conflictConsumer with
  | .ok facts => unless facts.value.proofDependencies == #[`TheoremDependencyFacts.ordinary] do
      throwError "explicit descendant ownership did not resolve the conflict"
  | .error error => throwError error.render
