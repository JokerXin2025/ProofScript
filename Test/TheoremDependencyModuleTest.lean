import Test.TheoremDependencyFactsTest

open Lean Elab Command ProofScript.Info

namespace TheoremDependencyModule

project_info "Importer.project" { title := "Importer context" }
theorem_info TheoremDependencyFacts.ordinary { project := "Facts.main" }

@lemma standalone (info := { project := "Facts.other" }) : True := by exact TheoremDependencyFacts.declarationDefault

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
  unless own.size == 1 && own[0]!.2.query.boundary != .endOfModule &&
      own[0]!.2.value.projectId == "Facts.other" &&
      own[0]!.2.value.proofDependencies == #[`TheoremDependencyFacts.declarationDefault] do
    throwError "standalone proof did not preserve its captured owner boundary"

-- No page_end: the importer must preserve the declaration's captured local boundary.
end TheoremDependencyModule
