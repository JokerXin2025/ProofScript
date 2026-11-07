import ProofScript.Utils.Linter
import ProofScript.Core.BuildMode
import ProofScript.Core.ModuleExtensionEntries
import ProofScript.Page.Model

open Lean


namespace ProofScript

structure PageState where
  components : Array Component := #[]
  labels : Std.HashSet (ReferenceKind × String) := {}
  closed : Bool := false
deriving Inhabited

initialize pageStateExt : EnvExtension PageState ←
  registerEnvExtension (pure {}) (asyncMode := .sync)

section
variable (env : Environment)

def getPageState := pageStateExt.getState env

def modifyPageState (f : PageState → PageState) : Environment :=
  pageStateExt.modifyState env f

/-- The page boundary applies to component commands in both build modes. -/
def ensurePageOpen : Except String Unit := do
  if (getPageState env).closed then
    throw "page component appears after #page end"

def addComponent (component : Component) : Except String (Environment × Bool) := do
  let state := getPageState env
  if state.closed then
    return (env, false)
  return (modifyPageState env (fun state =>
    { state with components := state.components.push component }), true)

def registerLabel (kind : ReferenceKind) (label : String)
    : Except String Environment := do
  let state := getPageState env
  if state.labels.contains (kind, label) then
    throw s!"duplicate {repr kind} label '{label}'"
  return modifyPageState env fun state =>
    { state with labels := state.labels.insert (kind, label) }

/-- The closed page retains component identities in the .olean. Metadata is
resolved by the exporter after the owner's complete module is available. -/
initialize pageDraftExt : SimplePersistentEnvExtension Page Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.pageDrafts
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => ()
  }

def modulePageDraft? (owner : Name) : Option Page :=
  let entries := moduleExtensionEntries pageDraftExt env owner
  entries.find? (·.module == owner)

end

open Elab.Command in
elab "#page" "end" : command => allowHashCommandLint do
  let env ← getEnv
  if (getPageState env).closed then
    throwError "#page end may only appear once in a module"
  let env := modifyPageState env fun state => { state with closed := true }
  if ← pageBuild? then setEnv <|
    pageDraftExt.addEntry env {
      module := env.mainModule,
      source := ← getFileName,
      components := (getPageState env).components
    }
  else setEnv env

end ProofScript
