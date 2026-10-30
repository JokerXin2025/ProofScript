import ProofScript.Script.Contract
import ProofScript.Utils.Json
import ProofScript.Utils.JsonPath
import ProofScript.Info.State

namespace ProofScript

open Lean
open scoped InfoJson

def manifestSchemaVersion : String := "9"

structure StepBinding where
  path : JsonPath
  contract : RecordingContract
  deriving Inhabited

def StepBinding.toJson (binding : StepBinding) := json% {
  path: $(binding.path),
  contractId: $(binding.contract.id)
}

instance : ToJson StepBinding := ⟨StepBinding.toJson⟩

/-- Configuration use is independent of citation collection. Optional entries retain backend fallbacks. -/
structure RenderDependency where
  kind : String
  target : Name ⊕ String
  required : Bool := false
  deriving Inhabited, Repr, BEq

instance : ToJson RenderDependency where
  toJson dependency :=
    let identity : InfoTarget := { kind := dependency.kind, target := dependency.target }
    (toJson identity).setObjVal! "required" (toJson dependency.required)

instance : FromJson RenderDependency where
  fromJson? value := do
    let identity : InfoTarget ← fromJson? value
    let required ← match value.getObjVal? "required" with
      | .ok field => fromJson? field
      | .error _ => pure false
    return { kind := identity.kind, target := identity.target, required }

inductive ArtifactKind where
  | page | proof
  deriving Inhabited, Repr, BEq, ToJson

structure ArtifactKey where
  owner : Name
  kind : ArtifactKind
  name : Name
  deriving Inhabited, Repr, BEq, ToJson

def ArtifactKey.id (key : ArtifactKey) : String := (toJson key).sha256

/-- No capture actions, slots, goal handles or proof contents are persisted here. -/
structure Artifact where
  schemaVersion : String := manifestSchemaVersion
  key : ArtifactKey
  path : String
  declaration : Option Name := none
  dependencies : Array RenderDependency := #[]
  bindings : Array StepBinding := #[]
  contentDigest : String
  deriving Inhabited

def Artifact.query (artifact : Artifact) : Query :=
  { moduleName := artifact.key.owner }

def Artifact.fingerprint (artifact : Artifact) : String := Json.sha256 <| json% {
  schemaVersion: $(artifact.schemaVersion),
  id: $(artifact.key.id), path: $(artifact.path), content: $(artifact.contentDigest),
  declaration: $(artifact.declaration),
  dependencies: $(artifact.dependencies), bindings: $(artifact.bindings) }

initialize artifactExt : SimplePersistentEnvExtension Artifact Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.artifacts
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => () }

def moduleArtifacts (env : Environment) (owner : Name) : Array Artifact := Id.run do
  let entries := if owner == env.mainModule then (artifactExt.getEntries env).reverse.toArray
    else (env.getModuleIdx? owner).map (artifactExt.getModuleEntries env) |>.getD #[]
  let mut artifacts := #[]
  for artifact in entries do
    artifacts := (artifacts.filter (·.key != artifact.key)).push artifact
  return artifacts

/-- Only recorded proof files are persisted. Page artifacts are built from closed drafts at export. -/
def registerProofArtifact (env : Environment) (artifact : Artifact) : Except String Environment := do
  unless artifact.schemaVersion == manifestSchemaVersion do throw "unsupported artifact manifest version"
  unless artifact.key.kind == .proof do throw "page artifacts are generated from closed page drafts"
  unless artifact.key.owner == env.mainModule do throw "artifacts must be committed by their defining module"
  let existing := moduleArtifacts env artifact.key.owner
  if let some previous := existing.find? (·.key == artifact.key) then
    if previous.fingerprint == artifact.fingerprint then return env
    throw s!"artifact identity already exists: {artifact.key.name}"
  return artifactExt.addEntry env artifact

end ProofScript
