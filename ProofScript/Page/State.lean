import ProofScript.Core.ModuleExtensionEntries
import ProofScript.Page.Model
import ProofScript.Info.Freeze

open Lean

namespace ProofScript

/-- Each component is committed immediately to the defining module's .olean. -/
initialize pageComponentExt : SimplePersistentEnvExtension Component Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.pageComponents
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => () }

initialize pageComponentLabelsExt : SimplePersistentEnvExtension (Array (ReferenceKind × String)) Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.pageComponentLabels
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => () }

def modulePageComponents (env : Environment) (owner : Name) : Array Component :=
  moduleExtensionEntries pageComponentExt env owner

/-- View of components and labels already committed to the current module. -/
structure PageState where
  components : Array Component := #[]
  labels : Std.HashSet (ReferenceKind × String) := {}

def getPageState (env : Environment) : PageState := Id.run do
  let components := modulePageComponents env env.mainModule
  let labels := (moduleExtensionEntries pageComponentLabelsExt env env.mainModule).foldl
    (fun seen entries => entries.foldl (fun seen label => seen.insert label) seen)
    ({} : Std.HashSet (ReferenceKind × String))
  return { components, labels }

/-- Commit one component and all its Info requests as one environment update. -/
def addComponent (env : Environment) (component : Component)
    (requests : InfoRequests := {})
    (labels : Array (ReferenceKind × String) := #[]) : Except String Environment := do
  let state := getPageState env
  let mut seen := state.labels
  for (kind, label) in labels do
    if seen.contains (kind, label) then
      throw s!"duplicate {repr kind} label '{label}'"
    seen := seen.insert (kind, label)
  let mut updated := env
  updated ← requestComponentInfos updated requests
  updated := pageComponentExt.addEntry updated component
  return pageComponentLabelsExt.addEntry updated labels

/-- A module with no components has no page, even if it has Info updates. -/
def modulePageDraft? (env : Environment) (owner : Name) (source : String := "") : Option Page :=
  let components := modulePageComponents env owner
  if components.isEmpty then none else some { module := owner, source, components }

end ProofScript
