import ProofScript
import ProofScript.Script.ScriptDB

open Lean Elab Command ProofScript

namespace VerificationMode

set_option linter.unusedTactic false
set_option linter.unreachableTactic false

/-- Page metadata is not needed to verify this native theorem. -/
@theorem byForm (info := { name := 123, project := "NotConfigured" }) : True := by
  trivial

@theorem scriptForm (info := { name := "Verification only" }) (P : Prop) (h : P) : P := script
  cite byForm
  exact h

@lemma identity (n : Nat) : n = n := script
  rfl

section
variable (P : Prop)

@theorem sectionBinder (h : P) : P := by
  exact h

end

-- A recorder must never run merely because its tactic is used in a verification proof.
script_macro verifyStep "verify_step" => `(tactic| trivial)
script_recorder verifyStep "verify_step" => do
  throwError "verification executed a page recorder"

@theorem noRecorder : True := script
  verify_step

-- These deliberately invalid page payloads must not start resource work or consume metadata.
@text "*Unclosed page formatting"
@latex (title := "Skipped LaTeX") "\\thisCommandMustNotBeCompiled"
@figure (title := "Skipped figure") "/invalid-absolute-path"
@computation { function := missingComputationFunction }
@references
page_end
page_end

elab "verification_custom_component" : command => whenPageBuild do
  throwError "verification executed a component constructor"

verification_custom_component

/-- Synchronize negative fixtures so the harness observes the actual proof error. -/
elab "expect_verification_failure " command:command : command => do
  let saved ← get
  modify fun state => { state with messages := {} }
  let mut failed := false
  try
    withScope (fun scope => { scope with opts := scope.opts.setBool `Elab.async false }) do
      elabCommand command
    failed := (← get).messages.hasErrors
  catch _ => failed := true
  set saved
  unless failed do throwError "an invalid verification declaration was accepted"

expect_verification_failure
@theorem invalidProof : False := by exact True.intro

expect_verification_failure
@theorem invalidScriptProof : False := script
  exact True.intro

expect_verification_failure
@theorem dataIsNotATheorem : Nat := by exact 0

expect_verification_failure
@theorem invalidByBoundary : True := by script_trivial

expect_verification_failure
set_option proofScript.pageBuild true in
@theorem mixedMode : True := by trivial

run_cmd do
  unless !(← pageBuildEnabled) do throwError "verification tests require the default build mode"
  let env ← getEnv
  for name in #[`VerificationMode.byForm, `VerificationMode.scriptForm,
      `VerificationMode.identity, `VerificationMode.sectionBinder, `VerificationMode.noRecorder] do
    let some (.thmInfo _) := env.find? name
      | throwError m!"verification did not create a native theorem: {name}"
    let check := name.getPrefix ++ Name.mkSimple ("scriptcheck_" ++ name.getString!)
    unless !env.contains check && (Info.declarationFacts? env name).isNone &&
        (findScript env name).isNone do
      throwError "verification created a check theorem, page facts or a replay script"
    let path ← liftIO <| activeOutputPath (proofOutputPath env.mainModule name)
    if ← liftIO path.pathExists then throwError "verification exported a proof file"
  unless (Output.moduleArtifacts env env.mainModule).isEmpty &&
      (getPageState env).components.isEmpty && !(getPageState env).exported &&
      (Info.moduleEvents env env.mainModule).isEmpty && (← getTheoremRefs).isEmpty do
    throwError "verification produced page, metadata, artifact or citation state"
  let documentation ← liftIO <| findDocString? env `VerificationMode.byForm
  unless documentation.any (·.trimAscii.toString ==
      "Page metadata is not needed to verify this native theorem.") do
    throwError m!"native theorem lost its documentation: {repr documentation}"
  unless (← findDeclarationRanges? `VerificationMode.byForm).isSome do
    throwError "native theorem lost its source range"
  let some mode := moduleBuildMode? env env.mainModule
    | throwError "verification did not record its module build mode"
  unless !mode.pageBuild && mode.version == buildModeVersion do
    throwError "verification has an invalid build-mode marker"
  if (validateModuleBuildMode env env.mainModule).isOk then
    throwError "the exporter accepted verification artifacts"
  for name in #[`VerificationMode.invalidProof, `VerificationMode.invalidScriptProof,
      `VerificationMode.dataIsNotATheorem, `VerificationMode.invalidByBoundary,
      `VerificationMode.mixedMode] do
    if env.contains name then throwError "an invalid declaration survived the test harness"

end VerificationMode
