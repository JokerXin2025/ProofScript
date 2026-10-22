import Test.TheoremDependencyProbeTest

open Lean Elab Command ProofScript ProofScript.Info

namespace TheoremDependencyFacts

-- These fixtures intentionally fail or define a proposition as a user definition.
set_option linter.unusedTactic false
set_option linter.unreachableTactic false

project_info "Facts.other" { title := "Other project" }
project_info "Facts.main" { title := "Declaration project" }

theorem ordinary : True := True.intro
theorem_info ordinary { project := "Facts.main" }
theorem lateMetadata : True := True.intro
theorem unowned : True := True.intro
opaque plainOpaque : True := ordinary
set_option linter.defProp false in
def userDefinition : True := ordinary

@theorem declarationDefault : True := by exact ordinary
project_info "Facts.other" {}
theorem_info declarationDefault { name := "A later title" }
project_info "Facts.main" {}

@theorem lateProject : True := by exact lateMetadata
theorem_info lateMetadata { project := "Facts.main" }

@theorem excludesUnowned : True := by exact unowned
@theorem excludesOpaque : True := by exact plainOpaque
@theorem excludesDefinition : True := by exact userDefinition

set_option referenceCollection false in
@theorem byWithoutReferences : True := by exact ordinary
set_option referenceCollection false in
@lemma scriptLemma : True := script
  exact ordinary

-- Imported raw facts and native theorem identity survive .olean serialization.
@theorem importedTarget (info := { project := "Dependency.demo" }) : True := by exact TheoremDependencyProbe.byForm
@theorem importedTheorem (info := { project := "Dependency.demo" }) : True := by exact TheoremDependencyProbe.byForm

expect_dependency_failure badBy =>
@theorem badBy : False := by exact True.intro

expect_dependency_failure badScript =>
@theorem badScript : False := script
  exact True.intro

expect_dependency_failure badPrepare =>
reject_dependency_prepare badPrepare

-- An existing ordinary theorem with the generated spelling must not be classified by prefix.
theorem scriptcheck_namedByUser : True := ordinary
theorem_info scriptcheck_namedByUser { project := "Facts.main" }
@theorem usesUserNamedCheck : True := by exact scriptcheck_namedByUser

theorem scriptcheck_checkCollision : True := True.intro
@theorem checkCollision : True := by trivial

run_cmd do
  let env ← getEnv
  let query : Query := { moduleName := env.mainModule }
  let some imported := declarationFacts? env `TheoremDependencyProbe.auxiliary
    | throwError "raw proof facts were not imported"
  unless imported.proofConstants == #[`TheoremDependencyProbe.A.base] &&
      imported.ownerModule == `Test.TheoremDependencyProbeTest &&
      (declarationFacts? env `TheoremDependencyProbe.recordedLemma).any (·.declarationKind == .lemma) do
    throwError "import changed the normalized proof or declaration identity"
  let actual ← match freezeModuleTheorems env env.mainModule with
    | .ok facts => pure facts
    | .error error => throwError error.render
  for (root, expected) in #[
      (`TheoremDependencyFacts.declarationDefault, #[`TheoremDependencyFacts.ordinary]),
      (`TheoremDependencyFacts.lateProject, #[]),
      (`TheoremDependencyFacts.excludesUnowned, #[]),
      (`TheoremDependencyFacts.excludesOpaque, #[]),
      (`TheoremDependencyFacts.excludesDefinition, #[]),
      (`TheoremDependencyFacts.byWithoutReferences, #[`TheoremDependencyFacts.ordinary]),
      (`TheoremDependencyFacts.scriptLemma, #[`TheoremDependencyFacts.ordinary]),
      (`TheoremDependencyFacts.importedTarget, #[`TheoremDependencyProbe.byForm]),
      (`TheoremDependencyFacts.importedTheorem, #[`TheoremDependencyProbe.byForm]),
      (`TheoremDependencyFacts.checkCollision, #[]),
      (`TheoremDependencyFacts.usesUserNamedCheck, #[`TheoremDependencyFacts.scriptcheck_namedByUser])] do
    let some (_, facts) := actual.find? (·.2.value.declaration == root)
      | throwError m!"missing captured proof facts for {root}"
    unless facts.value.proofDependencies == expected && facts.query.boundary != .endOfModule do
      throwError m!"wrong captured dependencies for {root}: {facts.value.proofDependencies}"
  unless (resolveTheoremInfo env query `TheoremDependencyFacts.declarationDefault).toOption.any
      (·.value.project == some "Facts.main") do
    throwError "a title-only update changed declaration-time project ownership"
  -- A later removal is visible to explicit current queries, but cannot rewrite earlier proofs.
  let source : Foundation.SourceLocation := ⟨"dependency-test", 0, 0⟩
  let cleared ← match commitInfo theoremSpec env `TheoremDependencyFacts.declarationDefault
      #[TheoremInfo.infoFields.project.assignment none source] source with
    | .ok env => pure env
    | .error error => throwError error.render
  match freezeTheoremFacts cleared query "test" `TheoremDependencyFacts.declarationDefault with
  | .error error => unless error.path == #[.key "project"] do
      throwError "missing ownership lost its diagnostic path"
  | .ok _ => throwError "explicit current query ignored removed ownership"
  match freezePage cleared "dependency-test" with
  | .ok _ => pure ()
  | .error error => throwError m!"later metadata invalidated an earlier proof: {error.render}"
  if (ProofScript.getPageState env).exported then
    throwError "pure freeze changed the original page state"

@references
page_end

theorem_info ordinary { project := "Facts.other" }
theorem_info declarationDefault { project := "Facts.other" }

/-- warning: page component appears after page_end and was ignored -/
#guard_msgs in
@theorem afterPage (info := { project := "Facts.other" }) : True := by exact declarationDefault
theorem_info afterPage { project := "Facts.main" }

run_cmd do
  let env ← getEnv
  let all ← match freezeModuleTheorems env env.mainModule with
    | .ok all => pure all
    | .error error => throwError error.render
  let some (_, original) := all.find? (·.2.value.declaration == `TheoremDependencyFacts.declarationDefault)
    | throwError "captured proof facts are missing"
  unless original.value.projectId == "Facts.main" &&
      original.value.proofDependencies == #[`TheoremDependencyFacts.ordinary] do
    throwError "later metadata changed an earlier proof's dependencies"
  unless all.size == 12 do
    throwError "module export omitted a recorded proof"
  let some (_, afterPage) := all.find? (·.2.value.declaration == `TheoremDependencyFacts.afterPage)
    | throwError "a proof after page_end was omitted"
  unless afterPage.query.boundary != .endOfModule && afterPage.value.projectId == "Facts.other" &&
      afterPage.value.proofDependencies == #[`TheoremDependencyFacts.declarationDefault] do
    throwError "a proof after page_end lost its own captured boundary"

end TheoremDependencyFacts
