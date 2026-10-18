import ProofScript.Info.Snapshot
import ProofScript.Output.Path

namespace ProofScript.Output

open Lean Info
open scoped Foundation

def infoProtocolVersion : String := "5.0.0"

/-- File names use the digest of the lossless name, independently of display spelling. -/
def moduleId (name : Name) : String := (toJson name).sha256

private def Artifact.baseJson (artifact : Artifact) (snapshotId : String) := json% {
  schemaVersion: $(artifact.schemaVersion),
  id: $(artifact.key.id),
  owner: $(artifact.key.owner),
  module: $(artifact.key.owner.toString),
  kind: $(artifact.key.kind),
  name: $(artifact.key.name),
  path: $(artifact.path),
  snapshotId: $snapshotId,
  declaration: $(artifact.declaration),
  contentDigest: $(artifact.contentDigest),
  dependencies: $(artifact.dependencies),
  bindings: $(artifact.bindings)
}

/-- Bind semantic facts to this artifact's source content and exact configuration boundary. -/
def Artifact.proofFactsDigest (artifact : Artifact) (snapshotId : String) (value : TheoremExport) : String :=
  Json.sha256 <| json% {
    schemaVersion: $(artifact.schemaVersion), artifactId: $(artifact.key.id),
    snapshotId: $snapshotId, contentDigest: $(artifact.contentDigest), "theorem": $value }

/-- The only publication boundary for proof facts. Pages and unnamed recordings have no theorem fields. -/
def Artifact.exportJson (artifact : Artifact) (snapshot : Snapshot)
    (facts : Option FrozenTheoremFacts) (projectId : Option String := none) : Except String Json := do
  unless artifact.schemaVersion == manifestSchemaVersion && artifact.query == snapshot.query &&
      artifact.boundary != .endOfModule do
    throw "artifact version/boundary disagrees with its export snapshot; rebuild the defining module"
  let base := artifact.baseJson snapshot.id
  if artifact.key.kind == .proof && artifact.declaration.isSome then
    let some facts := facts | throw "missing theorem proof facts; rebuild the defining module"
    let value := facts.value
    value.validate
    unless artifact.declaration == some value.declaration && artifact.key.name == value.declaration &&
        facts.ownerModule == artifact.key.owner && facts.query == snapshot.query && facts.snapshotId == snapshot.id do
      throw "theorem proof facts disagree with their artifact identity or snapshot"
    let some source := snapshot.find? theoremSpec.kind (.inl value.declaration)
      | throw "theorem proof facts have no source metadata in their snapshot"
    unless source.configured && (source.value.getObjValAs? (Option String) "project").toOption == some (some value.projectId) do
      throw "theorem proof facts disagree with their frozen project metadata"
    unless (snapshot.find? projectSpec.kind (.inr value.projectId)).any (·.configured) do
      throw "theorem proof facts reference an unconfigured project"
    return base.setObjVal! "projectId" (toJson value.projectId)
      |>.setObjVal! "proofDependencies" (toJson value.proofDependencies)
      |>.setObjVal! "proofFactsDigest" (toJson (artifact.proofFactsDigest snapshot.id value))
  unless facts.isNone && artifact.declaration.isNone do
    throw "only named proof artifacts may carry theorem proof facts"
  return base.setObjVal! "projectId" (toJson projectId)

def snapshotDocument (snapshot : Snapshot) := json% {
  schemaVersion: $infoProtocolVersion,
  id: $(snapshot.id),
  payload: $(snapshot.payload),
  provenance: $(snapshot.provenance)
}

def modelSchemas := json% {
  project: $((inferInstance : InfoSchema ProjectInfo).jsonSchema),
  "theorem": $((inferInstance : InfoSchema TheoremInfo).jsonSchema),
  script: $((inferInstance : InfoSchema ScriptInfo).jsonSchema),
  definition: $((inferInstance : InfoSchema DefinitionInfo).jsonSchema),
  "variable": $((inferInstance : InfoSchema VariableInfo).jsonSchema),
  phrase: $((inferInstance : InfoSchema PhraseInfo).jsonSchema)
}

private def objectSchema (properties : List (String × Json)) (required : Array String) :=
  json% {
    type: "object",
    properties: $(Json.mkObj properties),
    required: $required,
    additionalProperties: false
  }

private def stringSchema := json% { type: "string" }
private def digestSchema := json% { type: "string", pattern: "^[0-9a-f]{64}$" }
private def arraySchema (items : Json) := json% { type: "array", items: $items }
private def nullableSchema (value : Json) := json% { anyOf: [$value, { type: "null" }] }
private def constantSchema (value : String) := json% { const: $value }

private def targetSchema (kind : String) : Json :=
  if kind == "project" then json% { type: "string", minLength: 1 }
  else Foundation.qualifiedNameSchema

private def recordSchema [InfoSchema Record] (spec : InfoSpec Record) : Json :=
  let schema : InfoSchema Record := inferInstance
  objectSchema [
    ("identity", objectSchema [("kind", constantSchema spec.kind), ("target", targetSchema spec.kind)] #["kind", "target"]),
    ("schemaId", constantSchema schema.id.toString), ("schemaVersion", constantSchema schema.version),
    ("configured", json% { type: "boolean" }), ("value", schema.jsonSchema)]
    #["identity", "schemaId", "schemaVersion", "configured", "value"]

private def contractSchema : Json := objectSchema [
  ("contractVersion", constantSchema recordingContractVersion), ("recordingVersion", constantSchema recordingProtocolVersion),
  ("ruleId", Foundation.qualifiedNameSchema), ("name", stringSchema),
  ("strategy", json% { type: "boolean" }),
  ("continuation", nullableSchema (json% { type: "integer", minimum: 0 })),
  ("fields", nullableSchema (arraySchema (json% { type: "object" })))]
  #["contractVersion", "recordingVersion", "ruleId", "name", "strategy", "continuation", "fields"]

def snapshotSchema : Json :=
  let records := json% { oneOf: [
    $(recordSchema projectSpec), $(recordSchema theoremSpec),
    $(recordSchema scriptSpec), $(recordSchema definitionSpec),
    $(recordSchema variableSpec), $(recordSchema phraseSpec)] }
  let boundary := objectSchema [
    ("before", objectSchema [("sequence", json% { type: "integer", minimum: 0 })] #["sequence"])] #["before"]
  let payload := objectSchema [
    ("schemaVersion", constantSchema snapshotSchemaVersion),
    ("recordingVersion", constantSchema recordingProtocolVersion), ("contractVersion", constantSchema recordingContractVersion),
    ("query", objectSchema [("module", Foundation.qualifiedNameSchema), ("boundary", boundary)] #["module", "boundary"]),
    ("records", arraySchema records),
    ("contracts", arraySchema (objectSchema [("id", digestSchema), ("value", contractSchema)] #["id", "value"]))]
    #["schemaVersion", "recordingVersion", "contractVersion", "query", "records", "contracts"]
  (objectSchema [("schemaVersion", constantSchema infoProtocolVersion), ("id", digestSchema),
    ("payload", payload), ("provenance", arraySchema (json% { type: "object" }))]
    #["schemaVersion", "id", "payload", "provenance"]).setObjVal! "$schema" (json% "https://json-schema.org/draft/2020-12/schema")

private def dependencySchema : Json :=
  let variants := #["project", "theorem", "definition", "script", "variable", "phrase"].map fun kind =>
    objectSchema [
      ("kind", constantSchema kind), ("target", targetSchema kind),
      ("required", json% { type: "boolean" })] #["kind", "target", "required"]
  json% { oneOf: $variants }

private def artifactSchema : Json := (objectSchema [
  ("schemaVersion", constantSchema manifestSchemaVersion), ("id", digestSchema),
  ("owner", Foundation.qualifiedNameSchema), ("module", stringSchema),
  ("kind", json% { enum: ["page", "proof"] }), ("name", Foundation.qualifiedNameSchema),
  ("path", stringSchema), ("snapshotId", digestSchema), ("contentDigest", digestSchema),
  ("declaration", nullableSchema Foundation.qualifiedNameSchema),
  ("projectId", nullableSchema (targetSchema "project")),
  ("proofDependencies", arraySchema Foundation.qualifiedNameSchema), ("proofFactsDigest", digestSchema),
  ("dependencies", arraySchema dependencySchema),
  ("bindings", arraySchema (objectSchema [
    ("path", arraySchema (json% { anyOf: [$stringSchema, { type: "integer", minimum: 0 }] })),
    ("contractId", digestSchema)] #["path", "contractId"])),
  ("publishedDigest", digestSchema), ("transform", constantSchema "finalize-computations")]
  #["schemaVersion", "id", "owner", "module", "kind", "name", "path", "snapshotId", "contentDigest", "declaration", "projectId", "dependencies", "bindings"])
  |>.setObjVal! "oneOf" (json% [
    { properties: { kind: { const: "proof" } },
      required: ["proofFactsDigest"],
      allOf: [$(theoremExportSchema.setObjVal! "additionalProperties" (toJson true))] },
    { properties: { declaration: { type: "null" }, proofDependencies: false, proofFactsDigest: false } }
  ])

/-- All domain field schemas come from InfoSchema; consumers only adapt this wire format. -/
def protocolSchema : Json :=
  let file := json% { oneOf: [
    $(objectSchema [("path", stringSchema), ("digest", digestSchema)] #["path", "digest"]),
    $(objectSchema [("path", stringSchema), ("sha256", digestSchema)] #["path", "sha256"])] }
  (objectSchema [
    ("schemaVersion", constantSchema infoProtocolVersion), ("recordingVersion", constantSchema recordingProtocolVersion),
    ("contractVersion", constantSchema recordingContractVersion), ("complete", json% { const: true }),
    ("modules", arraySchema (objectSchema [
      ("name", Foundation.qualifiedNameSchema), ("module", stringSchema), ("events", stringSchema),
      ("defaultSnapshot", nullableSchema digestSchema)] #["name", "module", "events", "defaultSnapshot"])),
    ("artifacts", arraySchema artifactSchema),
    ("snapshots", arraySchema (objectSchema [("id", digestSchema), ("path", stringSchema)] #["id", "path"])),
    ("files", arraySchema file)]
    #["schemaVersion", "recordingVersion", "contractVersion", "complete", "modules", "artifacts", "snapshots", "files"])
    |>.setObjVal! "$schema" (json% "https://json-schema.org/draft/2020-12/schema")
    |>.setObjVal! "title" (json% "ProofScript completed Info bundle")

end ProofScript.Output
