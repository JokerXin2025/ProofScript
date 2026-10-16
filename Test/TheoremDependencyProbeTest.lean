import Test.TheoremDependencyProbeSupport
import ProofScript.Info.TheoremProject
import ProofScript.Output.Theorem

/-! Compare the independent phase-one probe with the production declaration collector. -/

open Lean Elab Command Tactic Meta ProofScript.Info ProofScript.Output

namespace TheoremDependencyProbe

project_info "Other.demo" { title := "Other project" }
project_info "Dependency.demo" { title := "Dependency fixture" }

namespace A
theorem seed : True := True.intro
theorem_info seed { project := "Dependency.demo" }
theorem base : True := seed
theorem_info base { project := "Dependency.demo" }
end A

namespace B
theorem base : True := True.intro
theorem_info base { project := "Dependency.demo" }
end B

namespace Foreign
theorem base : True := True.intro
theorem_info base { project := "Other.demo" }
end Foreign

set_option linter.unusedTactic false in
probe_dependency byForm =>
@theorem byForm : True := by
  -- B.base appears in a discarded attempt as well as in this comment.
  first
  | have discarded := B.base
    fail "discard this proof attempt"
  | exact A.base

set_option referenceCollection false in
probe_dependency scriptForm =>
@theorem scriptForm : True := script
  exact A.base

probe_dependency recordedLemma =>
@lemma recordedLemma : True := by exact A.base

probe_dependency usesLemma =>
@theorem usesLemma : True := by exact recordedLemma

probe_dependency usesOtherBase =>
@theorem usesOtherBase : True := by exact B.base

probe_dependency crossProject =>
@theorem crossProject : True ∧ True := by exact ⟨A.base, Foreign.base⟩

probe_dependency empty =>
@theorem empty : True := by trivial

probe_dependency auxiliary =>
@theorem auxiliary : True := by dependency_aux

probe_dependency cachedAuxiliary =>
@theorem cachedAuxiliary : True := by dependency_aux

probe_dependency matching =>
@theorem matching (n : Nat) : True := by
  exact match n with
  | 0 => A.base
  | _ + 1 => A.base

probe_dependency usesInternalCheck =>
@theorem usesInternalCheck : True := by exact scriptcheck_byForm

run_cmd do
  let env ← getEnv
  let probes := probeExt.getState env
  for probe in probes do
    let some (.opaqueInfo _) := env.find? probe.declaration
      | throwError "@theorem and @lemma must be tested as opaque declarations"
    let some facts := declarationFacts? env probe.declaration
      | throwError "production collector did not register a declaration"
    unless facts.ownerModule == env.mainModule && facts.defaultProject == some "Dependency.demo" do
      throwError "production facts lost their defining context"
  for root in #[`TheoremDependencyProbe.byForm, `TheoremDependencyProbe.scriptForm] do
    let some probe := probes.find? (·.declaration == root) | throwError "missing fixture"
    unless probe.constants == #[`TheoremDependencyProbe.A.base] do
      throwError "the final proof must exclude discarded attempts, comments and transitive dependencies"
  let some first := probes.find? (·.declaration == `TheoremDependencyProbe.auxiliary)
    | throwError "missing auxiliary fixture"
  let some reused := probes.find? (·.declaration == `TheoremDependencyProbe.cachedAuxiliary)
    | throwError "missing cached auxiliary fixture"
  unless first.constants.size == 1 && first.constants == reused.constants &&
      first.introduced.contains first.constants[0]! &&
      !reused.introduced.contains first.constants[0]! do
    throwError "the fixture must exercise a generated helper reused across commands"
  for (root, expected) in #[
      (`TheoremDependencyProbe.byForm, #[`TheoremDependencyProbe.A.base]),
      (`TheoremDependencyProbe.scriptForm, #[`TheoremDependencyProbe.A.base]),
      (`TheoremDependencyProbe.recordedLemma, #[`TheoremDependencyProbe.A.base]),
      (`TheoremDependencyProbe.usesLemma, #[`TheoremDependencyProbe.recordedLemma]),
      (`TheoremDependencyProbe.usesOtherBase, #[`TheoremDependencyProbe.B.base]),
      (`TheoremDependencyProbe.crossProject, #[`TheoremDependencyProbe.A.base]),
      (`TheoremDependencyProbe.empty, #[]),
      (`TheoremDependencyProbe.auxiliary, #[`TheoremDependencyProbe.A.base]),
      (`TheoremDependencyProbe.cachedAuxiliary, #[`TheoremDependencyProbe.A.base]),
      (`TheoremDependencyProbe.matching, #[`TheoremDependencyProbe.A.base]),
      (`TheoremDependencyProbe.usesInternalCheck, #[`TheoremDependencyProbe.byForm])] do
    let candidates ← match dependencies env root with
      | .ok names => pure names
      | .error message => throwError message
    let mut localDependencies := #[]
    for candidate in candidates do
      -- This fixture has one recorded project; ordinary theorems have explicit project metadata.
      let defaultProject := if probes.any (·.declaration == candidate) then some "Dependency.demo" else none
      match resolveTheoremProject env { moduleName := env.mainModule } candidate defaultProject with
      | .ok (some "Dependency.demo") => localDependencies := localDependencies.push candidate
      | .ok _ => pure ()
      | .error error => throwError error.render
    let record ← match TheoremExport.create root "Dependency.demo" localDependencies with
      | .ok record => pure record
      | .error message => throwError message
    unless record.proofDependencies == expected do
      throwError m!"wrong dependencies for {root}: {record.proofDependencies}, expected {expected}"
    let actual ← match freezeTheoremFacts env { moduleName := env.mainModule } "probe" root with
      | .ok facts => pure facts.value
      | .error error => throwError error.render
    unless actual == record do
      throwError m!"production collector disagrees with independent probe for {root}"

page_end

end TheoremDependencyProbe
