import ProofScript.Page.Model

open Lean


namespace ProofScript


structure PageState where
  components : Array Component := #[]
  labels : Std.HashMap (ReferenceKind × String) SourceLocation := {}
  closed : Bool := false
  deriving Inhabited

initialize pageStateExt : EnvExtension PageState ←
  registerEnvExtension (pure {}) (asyncMode := .sync)

def getPageState  (env : Environment) := pageStateExt.getState env

def modifyPageState (env : Environment)
                    (f : PageState → PageState)
                    : Environment :=
  pageStateExt.modifyState env f

/-- The page boundary applies to component commands in both build modes. -/
def ensurePageOpen (env : Environment) : Except String Unit := do
  if (getPageState env).closed then
    throw "page component appears after #page end"

def addComponent  (env : Environment)
                  (component : Component)
                  : Except String (Environment × Bool) := do
  let state := getPageState env
  if state.closed then
    return (env, false)
  return (modifyPageState env (fun state =>
    { state with components := state.components.push component }), true)

/-- Mark the current module's page collection as closed without persisting a
    page draft. Verification uses this marker so later page commands can be
    rejected before their elaboration actions run. -/
def markPageClosed (env : Environment) : Except String Environment := do
  let state := getPageState env
  if state.closed then throw "#page end may only appear once in a module"
  return modifyPageState env fun state => { state with closed := true }

def registerLabel (env : Environment)
                  (kind : ReferenceKind)
                  (label : String)
                  (source : SourceLocation)
                  : Except String Environment := do
  let state := getPageState env
  if let some previous := state.labels.get? (kind, label) then
    throw s!"duplicate {repr kind} label '{label}' (first declared at {previous.file}:{previous.start})"
  return modifyPageState env fun state =>
    { state with labels := state.labels.insert (kind, label) source }

/-- The closed page retains component identities in the .olean. Metadata is
resolved by the exporter after the owner's complete module is available. -/
initialize pageDraftExt : SimplePersistentEnvExtension Page Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.pageDrafts
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => () }

def modulePageDraft? (env : Environment) (owner : Name) : Option Page :=
  let entries := if owner == env.mainModule then (pageDraftExt.getEntries env).reverse.toArray
    else (env.getModuleIdx? owner).map (pageDraftExt.getModuleEntries env) |>.getD #[]
  entries.find? (·.module == owner)

/-- Close collection and persist its only intermediate representation. -/
def closePage (env : Environment) (source : String) : Except String Environment := do
  let state := getPageState env
  let page : Page := { module := env.mainModule, source, components := state.components }
  return pageDraftExt.addEntry (← markPageClosed env) page


end ProofScript
