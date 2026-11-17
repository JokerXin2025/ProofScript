import ProofScript.Script.Contract
import ProofScript.Utils.Json
import ProofScript.Utils.JsonPath
import ProofScript.Core.ModuleExtensionEntries

namespace ProofScript

open Lean
open scoped InfoJson

structure StepBinding where
  path : JsonPath
  contract : RecordingContract
  deriving Inhabited

def StepBinding.toJson (binding : StepBinding) := json% {
  path: $(binding.path),
  contractId: $(binding.contract.id)
}

instance : ToJson StepBinding := ⟨StepBinding.toJson⟩

inductive ArtifactKind where
  | page | proof
  deriving BEq, ToJson

structure ArtifactKey where
  owner : Name
  kind : ArtifactKind
  name : Name
  deriving BEq, ToJson

def ArtifactKey.id (key : ArtifactKey) : String := (toJson key).sha256

/-- No capture actions, slots, goal handles or proof contents are persisted here. -/
structure Artifact where
  key : ArtifactKey
  path : String
  declaration : Option Name := none
  dependencies : Array Name := #[]
  bindings : Array StepBinding := #[]
  contentDigest : String

def Artifact.fingerprint (artifact : Artifact) : String := Json.sha256 <| json% {
  id: $(artifact.key.id), path: $(artifact.path), content: $(artifact.contentDigest),
  declaration: $(artifact.declaration),
  dependencies: $(artifact.dependencies), bindings: $(artifact.bindings) }

initialize artifactExt : SimplePersistentEnvExtension Artifact Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.artifacts
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => () }

structure ProofDocument where
  key : ArtifactKey
  value : Json

initialize proofDocumentExt : SimplePersistentEnvExtension ProofDocument Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.proofDocuments
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => () }

def moduleProofDocuments (env : Environment) (owner : Name) : Array ProofDocument :=
  moduleExtensionEntries proofDocumentExt env owner

/-- Recorder keys may be relative to their module; public theorem names are qualified. -/
def moduleProofDocument? (env : Environment) (owner declaration : Name) : Option Json :=
  (moduleProofDocuments env owner).find? (fun entry =>
    entry.key.name == declaration || (entry.key.name.getPrefix == .anonymous &&
      owner ++ entry.key.name == declaration)) |>.map (·.value)

def registerProofDocument (env : Environment) (artifact : Artifact) (value : Json) :
    Except String Environment := do
  unless artifact.key.owner == env.mainModule && artifact.key.kind == .proof &&
      artifact.contentDigest == value.sha256 do
    throw "proof document disagrees with its artifact"
  if let some previous := (moduleProofDocuments env env.mainModule).find? (·.key == artifact.key) then
    if previous.value.sha256 == value.sha256 then return env
    throw "duplicate proof document"
  return proofDocumentExt.addEntry env { key := artifact.key, value }

def moduleArtifacts (env : Environment) (owner : Name) : Array Artifact := Id.run do
  let entries := moduleExtensionEntries artifactExt env owner
  let mut artifacts := #[]
  for artifact in entries do
    artifacts := (artifacts.filter (·.key != artifact.key)).push artifact
  return artifacts

/-- Only recorded proof files are persisted. Page artifacts are built from components at export. -/
def registerProofArtifact (env : Environment) (artifact : Artifact) : Except String Environment := do
  unless artifact.key.kind == .proof do throw "page artifacts are generated from persisted components"
  unless artifact.key.owner == env.mainModule do throw "artifacts must be committed by their defining module"
  let existing := moduleArtifacts env artifact.key.owner
  if let some previous := existing.find? (·.key == artifact.key) then
    if previous.fingerprint == artifact.fingerprint then return env
    throw s!"artifact identity already exists: {artifact.key.name}"
  return artifactExt.addEntry env artifact

end ProofScript
