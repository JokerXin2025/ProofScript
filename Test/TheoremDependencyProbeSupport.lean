import ProofScript

/-! Independent capture probe and failure harness for the production declaration collector. -/

open Lean Elab Command Tactic Meta

namespace TheoremDependencyProbe

structure Probe where
  declaration : Name
  constants : Array Name
  introduced : Array Name
  deriving Inhabited

initialize probeExt : EnvExtension (Array Probe) ← registerEnvExtension (pure #[])

private def proofConstants (env : Environment) (declaration : Name) : Except String (Array Name) := do
  let some info := env.find? declaration | throw s!"missing declaration {declaration}"
  let some value := info.value? (allowOpaque := true) | throw s!"missing proof {declaration}"
  return value.getUsedConstants

elab "probe_dependency " name:ident " => " command:command : command => do
  let before ← getEnv
  elabCommand command
  let after ← getEnv
  let declaration := (← getCurrNamespace) ++ name.getId
  let constants ← match proofConstants after declaration with
    | .ok constants => pure constants
    | .error message => throwError message
  -- Reading the completed root above synchronizes its elaboration before inspecting constants.
  let introduced := after.constants.foldStage2 (fun names name _ =>
    if before.contains name then names else names.push name) (#[] : Array Name)
  modifyEnv fun env => probeExt.modifyState env (·.push { declaration, constants, introduced })

/-- Force the real Lean auxiliary-lemma cache, including reuse in a subsequent command. -/
elab "dependency_aux" : tactic => do
  let goal ← getMainGoal
  let name ← mkAuxLemma [] (← goal.getType) (mkConst `TheoremDependencyProbe.A.base)
  goal.assign (mkConst name)
  replaceMainGoal []

/-- Deliberately fail after proof checking and fact initialization, before artifact publication. -/
elab "reject_dependency_prepare " name:ident : command => do
  let command ← `(command| script_theorem_impl theorem $name : True := script
    trivial)
  withRef command <| ProofScript.elaborateDeclaration (throwError "forced prepare failure")

elab "expect_dependency_failure " name:ident " => " command:command : command => do
  let saved ← get
  let declaration := (← getCurrNamespace) ++ name.getId
  let before ← getEnv
  modify fun state => { state with messages := {} }
  let mut failed := false
  try
    elabCommand command
    failed := (← get).messages.hasErrors
  catch _ => failed := true
  let after ← getEnv
  let uncommitted := !after.contains declaration &&
    (ProofScript.Info.declarationFacts? after declaration).isNone &&
    ProofScript.Info.currentBoundary before == ProofScript.Info.currentBoundary after &&
    (ProofScript.Output.moduleArtifacts before before.mainModule).size ==
      (ProofScript.Output.moduleArtifacts after after.mainModule).size &&
    (ProofScript.getPageState before).components.size == (ProofScript.getPageState after).components.size
  let path ← liftIO <| ProofScript.activeOutputPath (ProofScript.proofOutputPath after.mainModule declaration)
  let written ← liftIO path.pathExists
  set saved
  unless failed && uncommitted && !written do
    throwError "failed declaration leaked facts, metadata, an artifact, a page component or a proof file"

def dependencies (env : Environment) (root : Name) : Except String (Array Name) := do
  let probes := probeExt.getState env
  let roots := probes.map (·.declaration)
  -- Expand only helpers introduced by a proof transaction, never by a name-prefix test.
  let introduced := probes.flatMap (·.introduced) |>.filter (!roots.contains ·)
  -- A cache hit need not introduce any constant in this command. Cache membership is provenance.
  let cached := (auxLemmasExt.getState env).lemmas.foldl
    (fun names _ entry => names.push entry.1) (#[] : Array Name)
  let mut pending ← proofConstants env root
  let mut seen : NameSet := {}
  let mut found := #[]
  while let some name := pending.back? do
    pending := pending.pop
    if seen.contains name then continue
    seen := seen.insert name
    if roots.contains name then
      found := found.push name
    else if introduced.contains name || cached.contains name then
      pending := pending ++ (← proofConstants env name)
    else if (env.find? name).any (·.isTheorem) then
      found := found.push name
  return found

end TheoremDependencyProbe
