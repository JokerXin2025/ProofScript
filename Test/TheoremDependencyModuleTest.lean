import Test.TheoremDependencyFactsTest

open Lean Elab Command ProofScript.Info

namespace TheoremDependencyModule

project_info "Importer.project" { title := "Importer context" }
theorem_info TheoremDependencyFacts.ordinary { project := "Facts.main" }

@lemma standalone : True := by exact TheoremDependencyFacts.declarationDefault
theorem_info standalone { project := "Facts.other" }

run_cmd do
  let env ← getEnv
  let pageOwner := `Test.TheoremDependencyFactsTest
  let imported ← match freezeModuleTheorems env pageOwner with
    | .ok facts => pure facts
    | .error error => throwError error.render
  let some (_, original) := imported.find? (·.2.value.declaration == `TheoremDependencyFacts.declarationDefault)
    | throwError "imported page facts are missing"
  unless original.value.projectId == "Facts.main" &&
      original.value.proofDependencies == #[`TheoremDependencyFacts.ordinary] do
    throwError "importer reinterpreted a frozen page"
  let own ← match freezeModuleTheorems env env.mainModule with
    | .ok facts => pure facts
    | .error error => throwError error.render
  unless own.size == 1 && own[0]!.2.query.boundary == .endOfModule &&
      own[0]!.2.value.projectId == "Facts.other" &&
      own[0]!.2.value.proofDependencies == #[`TheoremDependencyFacts.declarationDefault] do
    throwError "standalone proof did not resolve at its owner's module-end boundary"

-- No page_end: the importer must use this module's metadata, not its own active project.
end TheoremDependencyModule
