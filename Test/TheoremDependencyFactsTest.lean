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

-- Imported raw facts and the exact internal-check mapping survive .olean serialization.
@theorem importedTarget : True := by exact TheoremDependencyProbe.byForm
theorem_info importedTarget { project := "Dependency.demo" }
@theorem importedCheck : True := by exact TheoremDependencyProbe.scriptcheck_byForm
theorem_info importedCheck { project := "Dependency.demo" }

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
expect_dependency_failure checkCollision =>
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
  for (root, expected) in #[
      (`TheoremDependencyFacts.declarationDefault, #[`TheoremDependencyFacts.ordinary]),
      (`TheoremDependencyFacts.lateProject, #[`TheoremDependencyFacts.lateMetadata]),
      (`TheoremDependencyFacts.excludesUnowned, #[]),
      (`TheoremDependencyFacts.excludesOpaque, #[]),
      (`TheoremDependencyFacts.excludesDefinition, #[]),
      (`TheoremDependencyFacts.byWithoutReferences, #[`TheoremDependencyFacts.ordinary]),
      (`TheoremDependencyFacts.scriptLemma, #[`TheoremDependencyFacts.ordinary]),
      (`TheoremDependencyFacts.importedTarget, #[`TheoremDependencyProbe.byForm]),
      (`TheoremDependencyFacts.importedCheck, #[`TheoremDependencyProbe.byForm]),
      (`TheoremDependencyFacts.usesUserNamedCheck, #[`TheoremDependencyFacts.scriptcheck_namedByUser])] do
    match freezeTheoremFacts env query "test" root with
    | .ok facts => unless facts.value.proofDependencies == expected do
        throwError m!"wrong frozen dependencies for {root}: {facts.value.proofDependencies}"
    | .error error => throwError error.render
  unless (resolveTheoremInfo env query `TheoremDependencyFacts.declarationDefault).toOption.any
      (·.value.project == some "Facts.main") do
    throwError "a title-only update changed declaration-time project ownership"
  -- Explicit removal of a source project must prevent freezing without altering real page state.
  let source : Foundation.SourceLocation := ⟨"dependency-test", 0, 0⟩
  let cleared ← match commitInfo theoremSpec env `TheoremDependencyFacts.declarationDefault
      #[TheoremInfo.infoFields.project.assignment none source] source with
    | .ok env => pure env
    | .error error => throwError error.render
  match freezePage cleared "dependency-test" with
  | .error error => unless error.path == #[.field "project"] do
      throwError "missing ownership lost its diagnostic path"
  | .ok _ => throwError "page froze with an unowned source theorem"
  if (frozenTheoremFacts? env `TheoremDependencyFacts.declarationDefault).isSome then
    throwError "failed freeze mutated the original environment"

@references
page_end

theorem_info ordinary { project := "Facts.other" }
theorem_info declarationDefault { project := "Facts.other" }

/-- warning: page component appears after page_end and was ignored -/
#guard_msgs in
@theorem afterPage : True := by exact declarationDefault
theorem_info afterPage { project := "Facts.other" }

run_cmd do
  let env ← getEnv
  let some frozen := frozenTheoremFacts? env `TheoremDependencyFacts.declarationDefault
    | throwError "page_end did not persist semantic theorem facts"
  unless frozen.value.projectId == "Facts.main" &&
      frozen.value.proofDependencies == #[`TheoremDependencyFacts.ordinary] do
    throwError "later metadata changed a frozen page's dependencies"
  let all ← match freezeModuleTheorems env env.mainModule with
    | .ok all => pure all
    | .error error => throwError error.render
  unless all.size == 11 && all.any (·.2 == frozen) do
    throwError "module export did not retain frozen page facts verbatim"
  let some (_, final) := all.find? (·.2.value.declaration == `TheoremDependencyFacts.afterPage)
    | throwError "a proof after page_end was omitted"
  unless final.query.boundary == .endOfModule && final.value.projectId == "Facts.other" &&
      final.value.proofDependencies == #[`TheoremDependencyFacts.declarationDefault] do
    throwError "a proof after page_end did not use the module-end boundary"

end TheoremDependencyFacts
