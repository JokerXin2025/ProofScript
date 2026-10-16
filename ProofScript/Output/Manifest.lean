import ProofScript.Script.Contract
import ProofScript.Foundation.Name
import ProofScript.Info.State

namespace ProofScript.Output

open Lean
open scoped Foundation

def manifestSchemaVersion : String := "4"

inductive PathPart where
  | field (name : String)
  | index (value : Nat)
  deriving Inhabited, Repr, BEq

abbrev StepPath := Array PathPart

def pathJson (path : StepPath) : Json := .arr <| path.map fun part => match part with
  | .field name => .str name
  | .index index => toJson index

structure StepBinding where
  path : StepPath
  contract : RecordingContract
  deriving Inhabited

def StepBinding.toJson (binding : StepBinding) := json% {
  path: $(pathJson binding.path),
  contractId: $(binding.contract.id)
}

/-- Configuration use is independent of citation collection. Optional entries retain backend fallbacks. -/
structure RenderDependency where
  kind : String
  target : Name ⊕ String
  required : Bool := false
  deriving Inhabited, Repr, BEq

instance : ToJson RenderDependency where
  toJson dependency :=
    let identity : Info.InfoTarget := { kind := dependency.kind, target := dependency.target }
    (toJson identity).setObjVal! "required" (toJson dependency.required)

instance : FromJson RenderDependency where
  fromJson? value := do
    let identity : Info.InfoTarget ← fromJson? value
    let required ← match value.getObjVal? "required" with
      | .ok field => fromJson? field
      | .error _ => pure false
    return { kind := identity.kind, target := identity.target, required }

inductive ArtifactKind where
  | page | proof
  deriving Inhabited, Repr, BEq

structure ArtifactKey where
  owner : Name
  kind : ArtifactKind
  name : Name
  deriving Inhabited, Repr, BEq

def ArtifactKey.id (key : ArtifactKey) : String := Json.sha256 <| json% {
  owner: $(key.owner),
  kind: $(if key.kind == .page then "page" else "proof"),
  name: $(key.name) }

/-- Until a page closes, proofs are candidates for that page; otherwise the exporter freezes module-end. -/
inductive ArtifactScope where
  | pendingPage | moduleFinal | frozen (snapshotId : String)
  deriving Inhabited, Repr, BEq

/-- No capture actions, slots, goal handles or proof contents are persisted here. -/
structure Artifact where
  schemaVersion : String := manifestSchemaVersion
  key : ArtifactKey
  path : String
  scope : ArtifactScope := .pendingPage
  declaration : Option Name := none
  dependencies : Array RenderDependency := #[]
  bindings : Array StepBinding := #[]
  contentDigest : String
  deriving Inhabited

def Artifact.fingerprint (artifact : Artifact) : String := Json.sha256 <| json% {
  schemaVersion: $(artifact.schemaVersion),
  id: $(artifact.key.id), path: $(artifact.path), content: $(artifact.contentDigest),
  declaration: $(artifact.declaration),
  dependencies: $(artifact.dependencies), bindings: $(artifact.bindings.map StepBinding.toJson) }

initialize artifactExt : SimplePersistentEnvExtension Artifact Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.Output.artifacts
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => () }

def moduleArtifacts (env : Environment) (owner : Name) : Array Artifact := Id.run do
  let entries := if owner == env.mainModule then (artifactExt.getEntries env).reverse.toArray
    else (env.getModuleIdx? owner).map (artifactExt.getModuleEntries env) |>.getD #[]
  let mut artifacts := #[]
  for artifact in entries do
    artifacts := (artifacts.filter (·.key != artifact.key)).push artifact
  return artifacts

def registerArtifact (env : Environment) (artifact : Artifact) : Except String Environment := do
  unless artifact.schemaVersion == manifestSchemaVersion do throw "unsupported artifact manifest version"
  unless artifact.key.owner == env.mainModule do throw "artifacts must be committed by their defining module"
  let existing := moduleArtifacts env artifact.key.owner
  if let some previous := existing.find? (·.key == artifact.key) then
    if previous.fingerprint == artifact.fingerprint then return env
    throw s!"artifact identity already exists: {artifact.key.name}"
  let scope := if artifact.scope == .pendingPage && existing.any (·.key.kind == .page) then
    .moduleFinal else artifact.scope
  return artifactExt.addEntry env { artifact with scope }

/-- All pending proofs use the same close boundary as the page itself. -/
def bindPageArtifacts (env : Environment) (owner : Name) (snapshotId : String) : Environment :=
  (moduleArtifacts env owner).foldl (init := env) fun env artifact =>
    if artifact.scope == .pendingPage then
      artifactExt.addEntry env { artifact with scope := .frozen snapshotId }
    else env

end ProofScript.Output
