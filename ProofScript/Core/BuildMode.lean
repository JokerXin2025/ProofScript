import Lean

namespace ProofScript

open Lean Elab Command

initialize pageBuild : Lean.Option Bool ← Lean.Option.register `proofScript.pageBuild {
  defValue := false
  descr := "enable ProofScript page recording and export"
}

/-- Version of the persistent module build-mode marker. -/
def schemaModeVersion : Nat := 1

def buildModeVersion : Nat := schemaModeVersion

/-- Modules using page commands record the context that produced their Lean artifacts. -/
structure ModuleBuildMode where
  owner : Name
  pageBuild : Bool
  version : Nat := schemaModeVersion
  deriving Inhabited, Repr, BEq

private initialize moduleBuildModeExt :
    SimplePersistentEnvExtension ModuleBuildMode (NameMap ModuleBuildMode) ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.moduleBuildMode
    addEntryFn := fun state mode => state.insert mode.owner mode
    addImportedFn := fun modules => modules.foldl
      (fun state entries => entries.foldl
        (fun state mode => state.insert mode.owner mode) state) {}
  }

def moduleBuildMode? (env : Environment) (owner : Name) : Option ModuleBuildMode :=
  (moduleBuildModeExt.getState env).find? owner

def pageBuildEnabled {m : Type → Type} [Monad m] [MonadOptions m] : m Bool :=
  return (← getOptions).getBool `proofScript.pageBuild false

/-- Lock page commands in a module to one build mode, including skipped commands. -/
def recordModuleBuildMode : CommandElabM Bool := do
  let enabled ← pageBuildEnabled
  let env ← getEnv
  let owner := env.mainModule
  if let some previous := moduleBuildMode? env owner then
    unless previous.version == schemaModeVersion do
      throwError "ProofScript build-mode version mismatch in module `{owner}`; rebuild the module"
    unless previous.pageBuild == enabled do
      throwError "cannot change `proofScript.pageBuild` within module `{owner}`"
  else
    setEnv <| moduleBuildModeExt.addEntry env { owner, pageBuild := enabled }
  return enabled

/-- Run a page command only in page builds, after checking the module's mode. -/
def whenPageBuild (action : CommandElabM Unit) : CommandElabM Unit := do
  if ← recordModuleBuildMode then action

/-- Export may consume unmarked configuration modules, but never verification artifacts. -/
def validateModuleBuildMode (env : Environment) (owner : Name) : Except String Unit := do
  let some mode := moduleBuildMode? env owner | return
  unless mode.version == schemaModeVersion do
    throw s!"ProofScript build-mode version mismatch for module `{owner}`; rebuild its page artifacts"
  unless mode.pageBuild do
    throw s!"module `{owner}` was compiled without `proofScript.pageBuild`; rebuild it through the page build target"

end ProofScript
