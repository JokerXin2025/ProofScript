import ProofScript.Info.Patch
import ProofScript.Foundation.ModuleGraph

namespace ProofScript.Info

open Lean

structure InfoTarget where
  kind : String
  target : Name ⊕ String
  deriving Inhabited, Repr, BEq

def InfoTarget.validate (identity : InfoTarget) : Except String Unit :=
  match identity.target with
  | .inr name =>
    if identity.kind != "project" then .error "only project targets use strings"
    else if name.isEmpty then .error "project names must not be empty"
    else .ok ()
  | .inl _ =>
    if identity.kind == "project" then .error "project targets must be strings" else .ok ()

open scoped InfoJson in
instance : ToJson InfoTarget where
  toJson identity := json% {
    kind: $(identity.kind),
    target: $(identity.target.elim toJson toJson)
  }

open scoped InfoJson in
instance : FromJson InfoTarget where
  fromJson? value := do
    let kind ← value.getObjValAs? String "kind"
    let target ← if kind == "project" then
      Sum.inr <$> value.getObjValAs? String "target"
    else
      Sum.inl <$> value.getObjValAs? Name "target"
    let identity := { kind, target : InfoTarget }
    identity.validate
    return identity

/-- The exclusive limit is a committed transaction count, not a source offset. -/
inductive Boundary where
  | endOfModule
  | before (sequence : Nat)
  deriving Inhabited, Repr, BEq, ToJson, FromJson

structure Query where
  moduleName : Name
  boundary : Boundary := .endOfModule
  deriving Inhabited, Repr, BEq, ToJson, FromJson

def Query.includes (query : Query) (owner : Name) (sequence : Nat) : Bool :=
  owner != query.moduleName || match query.boundary with
    | .endOfModule => true
    | .before limit => sequence < limit

/-- Context selections are separate from renderable configuration fields. -/
structure ContextBinding where
  key : String
  value : Json
  source : Foundation.SourceLocation
  deriving Inhabited, ToJson, FromJson

/-- One atomic transaction. Initialization stores decisions made in the defining context. -/
structure InfoEvent where
  schemaId : Name
  schemaVersion : String
  identity : InfoTarget
  owner : Name
  sequence : Nat
  initialization : Option Patch := none
  assignments : Patch := #[]
  bindings : Array ContextBinding := #[]
  source : Foundation.SourceLocation
  deriving Inhabited, ToJson, FromJson

/-- Imported payloads stay in the extension's module tables. The state is the local
metadata clock; integrations can advance it without adding an Info event. -/
initialize infoEventExt : SimplePersistentEnvExtension InfoEvent Nat ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.Info.events
    addEntryFn := fun count _ => count + 1
    addImportedFn := fun _ => 0
  }

/-- Reserve an ordered metadata transaction without manufacturing a renderable Info event.
The state change rolls back with the Environment and need not persist: entries carry their
own sequence, and every importing module starts its own clock at zero. -/
def advanceBoundary (env : Environment) : Environment :=
  infoEventExt.modifyState env (· + 1)

def currentBoundary (env : Environment) : Boundary :=
  .before (infoEventExt.getState env)

def moduleEvents (env : Environment) (moduleName : Name) : Array InfoEvent :=
  if moduleName == env.mainModule then (infoEventExt.getEntries env).reverse.toArray
  else match env.getModuleIdx? moduleName with
    | some index => infoEventExt.getModuleEntries env index
    | none => #[]

/-- Read only the requested module's closure, rather than the exporter's full environment. -/
def queryEvents (env : Environment) (query : Query) : Except Diagnostic (Array InfoEvent) := do
  let order ← (Foundation.ModuleGraph.ofEnvironment env).order query.moduleName
    |>.mapError fun message => { message }
  return order.flatMap fun owner => (moduleEvents env owner).filter fun event =>
    query.includes event.owner event.sequence

/-- Validation at the wire/commit boundary does not demand a complete record. -/
def validatePatch (schema : InfoSchema Record) (patch : Patch) : Except Diagnostic Patch := do
  let mut assigned : Array FieldKey := #[]
  let mut result := #[]
  for assignment in patch do
    if assigned.contains assignment.key then
      throw { message := "duplicate assignment in event", source := some assignment.source }
    assigned := assigned.push assignment.key
    let operation ← match assignment.key with
      | .builtin name =>
        let some field := schema.fields.find? (fun field => field.name == name && !field.handle.isExtra)
          | throw { message := s!"unknown builtin field `{name}`", source := some assignment.source }
        match assignment.operation with
        | .reset => pure .reset
        | .set value =>
          let _ : ToJson field.Value := field.codec.toToJson
          let value ← (field.decode value).mapError fun error =>
            { (error.atField name) with source := some assignment.source }
          pure (.set (toJson value))
      | .extra _ =>
        unless schema.extraField?.isSome do
          throw { message := "this schema does not support extension fields", source := some assignment.source }
        pure assignment.operation
    result := result.push { assignment with operation }
  return result

/-- Construct the entire new environment before the elaborator installs it once. -/
def commitInfo [InfoSchema Record] (spec : InfoSpec Record) (env : Environment) (target : Name ⊕ String)
    (patch : Patch) (source : Foundation.SourceLocation)
    (initialization : Option Patch := none) (bindings : Array ContextBinding := #[]) :
    Except Diagnostic Environment := do
  let schema : InfoSchema Record := inferInstance
  schema.validateDefinition
  let patch ← validatePatch schema patch
  let initialization ← initialization.mapM fun initial => do
    let initial ← validatePatch schema initial
    if initial.any (fun assignment => match assignment.operation with | .reset => true | _ => false) then
      throw { message := "initialization must store explicit values, not reset operations" }
    return initial
  let identity := { kind := spec.kind, target : InfoTarget }
  identity.validate |>.mapError fun message => { message, source := some source }
  if initialization.isSome then
    let incoming ← queryEvents env { moduleName := env.mainModule }
    if incoming.any (·.identity == identity) then
      throw { message := s!"{spec.kind} `{target}` is already initialized", source := some source }
  let mut keys : Array String := #[]
  for binding in bindings do
    if binding.key.isEmpty || keys.contains binding.key then
      throw { message := s!"empty or duplicate context binding `{binding.key}`", source := some binding.source }
    keys := keys.push binding.key
  let event : InfoEvent := {
    schemaId := schema.id, schemaVersion := schema.version, identity
    owner := env.mainModule, sequence := infoEventExt.getState env
    initialization, assignments := patch, bindings, source }
  return infoEventExt.addEntry env event

end ProofScript.Info
