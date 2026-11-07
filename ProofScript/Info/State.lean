import ProofScript.Info.Patch
import ProofScript.Core.ModuleGraph
import ProofScript.Core.ModuleExtensionEntries

namespace ProofScript

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

structure Query where
  moduleName : Name
  deriving Inhabited, Repr, BEq, ToJson, FromJson

/-- Context selections are separate from renderable configuration fields. -/
structure ContextBinding where
  key : String
  value : Json
  deriving Inhabited, ToJson, FromJson

/-- One atomic metadata update. -/
structure InfoEvent where
  schemaId : Name
  schemaVersion : String
  identity : InfoTarget
  owner : Name
  sequence : Nat
  assignments : Patch := #[]
  reset : Bool := false
  bindings : Array ContextBinding := #[]
  deriving Inhabited, ToJson, FromJson

/-- Imported payloads stay in the extension's module tables. The local count
orders updates within each module. -/
initialize infoEventExt : SimplePersistentEnvExtension InfoEvent Nat ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.events
    addEntryFn := fun count _ => count + 1
    addImportedFn := fun _ => 0
  }

def moduleEvents (env : Environment) (moduleName : Name) : Array InfoEvent :=
  moduleExtensionEntries infoEventExt env moduleName

/-- Read only the requested module's closure, rather than the exporter's full environment. -/
def queryEvents (env : Environment) (query : Query) : Except Diagnostic (Array InfoEvent) := do
  let order ← (ModuleGraph.ofEnvironment env).modulesInDependencyOrder query.moduleName
    |>.mapError fun message => { message }
  return order.flatMap (moduleEvents env)

/-- Validation at the wire/commit boundary does not demand a complete record. -/
def validatePatch (schema : InfoSchema Record) (patch : Patch) : Except Diagnostic Patch := do
  let mut assigned : Array FieldKey := #[]
  let mut result := #[]
  for assignment in patch do
    if assigned.contains assignment.key then
      throw { message := "duplicate assignment in event" }
    assigned := assigned.push assignment.key
    let value ← match assignment.key with
      | .builtin name =>
        let some field := schema.fields.find? (fun field => field.name == name && !field.handle.isExtra)
          | throw { message := s!"unknown builtin field `{name}`" }
        let _ : ToJson field.Value := field.codec.toToJson
        let value ← (field.decode assignment.value).mapError (Diagnostic.atField name)
        pure (toJson value)
      | .extra _ =>
        unless schema.extraField?.isSome do
          throw { message := "this schema does not support extension fields" }
        pure assignment.value
    result := result.push { assignment with value }
  return result

/-- Construct the entire new environment before the elaborator installs it once. -/
def commitInfo [InfoSchema Record] (spec : InfoSpec Record) (env : Environment) (target : Name ⊕ String)
    (patch : Patch)
    (bindings : Array ContextBinding := #[]) (reset : Bool := false) :
    Except Diagnostic Environment := do
  let schema : InfoSchema Record := inferInstance
  schema.validateDefinition
  let patch ← validatePatch schema patch
  let identity := { kind := spec.kind, target : InfoTarget }
  identity.validate |>.mapError fun message => { message }
  let mut keys : Array String := #[]
  for binding in bindings do
    if binding.key.isEmpty || keys.contains binding.key then
      throw { message := s!"empty or duplicate context binding `{binding.key}`" }
    keys := keys.push binding.key
  let event : InfoEvent := {
    schemaId := schema.id, schemaVersion := schema.version, identity
    owner := env.mainModule, sequence := infoEventExt.getState env
    assignments := patch, reset, bindings }
  return infoEventExt.addEntry env event

end ProofScript
