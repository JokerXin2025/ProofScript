import ProofScript.Page.Model

open Lean


namespace ProofScript


structure PageState where
  components : Array Component := #[]
  labels : Std.HashMap (ReferenceKind × String) Foundation.SourceLocation := {}
  exported : Bool := false
  deriving Inhabited

initialize pageStateExt : EnvExtension PageState ←
  registerEnvExtension (pure {}) (asyncMode := .sync)

def getPageState  (env : Environment) := pageStateExt.getState env

def modifyPageState (env : Environment)
                    (f : PageState → PageState)
                    : Environment :=
  pageStateExt.modifyState env f

def addComponent  (env : Environment)
                  (component : Component)
                  : Except String (Environment × Bool) := do
  let state := getPageState env
  if state.exported then
    return (env, false)
  let component := { component with boundary := Info.currentBoundary env }
  return (modifyPageState env (fun state =>
    { state with components := state.components.push component }), true)

def registerLabel (env : Environment)
                  (kind : ReferenceKind)
                  (label : String)
                  (source : Foundation.SourceLocation)
                  : Except String Environment := do
  let state := getPageState env
  if let some previous := state.labels.get? (kind, label) then
    throw s!"duplicate {repr kind} label '{label}' (first declared at {previous.file}:{previous.start})"
  return modifyPageState env fun state =>
    { state with labels := state.labels.insert (kind, label) source }

def closePage (env : Environment)
              : Except String Environment := do
  let state := getPageState env
  if state.exported then
    throw "page_end may only appear once in a module"
  return modifyPageState env fun state => { state with exported := true }


end ProofScript
