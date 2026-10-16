import ProofScript.Info.Theorem
import ProofScript.Info.Definition
import ProofScript.Info.Variable
import ProofScript.Info.Phrase
import ProofScript.Info.Script
import ProofScript.Output.Manifest
import ProofScript.Info.TheoremDependencies

namespace ProofScript.Info

open Lean
open Output (RenderDependency)

def snapshotSchemaVersion : String := "3"

structure RendererDependencyEntry where
  renderer : ScriptRenderer
  dependencies : Array RenderDependency
  deriving Inhabited

initialize rendererDependencyExt : SimplePersistentEnvExtension RendererDependencyEntry Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.Info.rendererDependencies
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => () }

/-- Renderer integrations declare static configuration use; runtime-only access remains a backend check. -/
def declareRendererDependencies (env : Environment) (renderer : ScriptRenderer)
    (dependencies : Array RenderDependency) : Environment :=
  rendererDependencyExt.addEntry env { renderer, dependencies }

private def rendererDependencies (env : Environment) (query : Query) (renderer : ScriptRenderer) :
    Except Diagnostic (Array RenderDependency) := do
  let order ← (Foundation.ModuleGraph.ofEnvironment env).order query.moduleName
    |>.mapError fun message => { message }
  let entries := order.flatMap fun owner =>
    if owner == env.mainModule then (rendererDependencyExt.getEntries env).reverse.toArray
    else (env.getModuleIdx? owner).map (rendererDependencyExt.getModuleEntries env) |>.getD #[]
  return (entries.filter (·.renderer == renderer)).flatMap (·.dependencies)

structure SnapshotRecord where
  identity : InfoTarget
  schemaId : Name
  schemaVersion : String
  value : Json
  configured : Bool := true
  deriving Inhabited, ToJson, FromJson

structure Snapshot where
  schemaVersion : String := snapshotSchemaVersion
  recordingVersion : String := recordingProtocolVersion
  contractVersion : String := recordingContractVersion
  query : Query
  records : Array SnapshotRecord
  contracts : Array RecordingContract
  provenance : Array Json := #[]
  deriving Inhabited

open scoped Foundation in
def Snapshot.payload (snapshot : Snapshot) :=
  let contracts := snapshot.contracts.map fun contract => json% {
    id: $(contract.id),
    value: $(contract.toJson)
  }
  json% {
    schemaVersion: $(snapshot.schemaVersion),
    query: { module: $(snapshot.query.moduleName), boundary: $(snapshot.query.boundary) },
    recordingVersion: $(snapshot.recordingVersion),
    contractVersion: $(snapshot.contractVersion),
    records: $(snapshot.records),
    contracts: $contracts
  }

def Snapshot.id (snapshot : Snapshot) : String := snapshot.payload.sha256

def Snapshot.validateVersions (snapshot : Snapshot) : Except Diagnostic Unit := do
  unless snapshot.schemaVersion == snapshotSchemaVersion && snapshot.recordingVersion == recordingProtocolVersion &&
      snapshot.contractVersion == recordingContractVersion do
    throw { message := "unsupported persisted snapshot version; rebuild or migrate the artifact" }
  let schemas := #[
    (projectSpec.kind, projectSpec.schema.id, projectSpec.schema.version),
    (theoremSpec.kind, theoremSpec.schema.id, theoremSpec.schema.version),
    (scriptSpec.kind, scriptSpec.schema.id, scriptSpec.schema.version),
    (definitionSpec.kind, definitionSpec.schema.id, definitionSpec.schema.version),
    (variableSpec.kind, variableSpec.schema.id, variableSpec.schema.version),
    (phraseSpec.kind, phraseSpec.schema.id, phraseSpec.schema.version)]
  for record in snapshot.records do
    unless schemas.any (fun (kind, id, version) => record.identity.kind == kind && record.schemaId == id && record.schemaVersion == version) do
      throw { message := "unsupported persisted record schema; rebuild or migrate the artifact", kind := some record.identity.kind, target := some (toString record.identity.target) }
  for contract in snapshot.contracts do
    unless contract.contractVersion == recordingContractVersion && contract.recordingVersion == recordingProtocolVersion do
      throw { message := "unsupported persisted invocation contract version" }

def Snapshot.find? (snapshot : Snapshot) (kind : String) (target : Name ⊕ String) : Option SnapshotRecord :=
  snapshot.records.find? (fun record => record.identity.kind == kind && record.identity.target == target)

initialize snapshotExt : SimplePersistentEnvExtension Snapshot Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.Info.snapshots
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => () }

def moduleSnapshots (env : Environment) (owner : Name) : Array Snapshot :=
  if owner == env.mainModule then (snapshotExt.getEntries env).reverse.toArray
  else (env.getModuleIdx? owner).map (snapshotExt.getModuleEntries env) |>.getD #[]

private def entry (spec : InfoSpec Record) (target : Name ⊕ String) (info : ResolvedInfo Record) : SnapshotRecord :=
  { identity := { kind := spec.kind, target }, schemaId := spec.schema.id,
    schemaVersion := spec.schema.version, value := spec.schema.encode info.value }

private def sources (identity : InfoTarget) (info : ResolvedInfo Record) :=
  let fields := info.provenance.map fun (key, origins) =>
    let path := key.path.map fun (part : PathPart) => match part with
      | .field name => toJson name | .index index => toJson index
    let origins := origins.map fun (origin : Origin) =>
      json% {
        owner: $(origin.owner),
        sequence: $(origin.sequence),
        source: $(origin.source)
      }
    json% { path: $path, origins: $origins }
  json% { identity: $identity, fields: $fields }

private def dependencyRecords (env : Environment) (query : Query) (dependency : RenderDependency) :
    Except Diagnostic (SnapshotRecord × Array RenderDependency × Json) := do
  let kind := dependency.kind
  if let .inr project := dependency.target then
    unless kind == "project" do throw { message := "only project targets use strings" }
    let info ← resolveProjectInfo env query project
    let record := entry projectSpec project info
    return (record, #[], sources record.identity info)
  let .inl target := dependency.target | unreachable!
  match kind with
  | "theorem" =>
    let info ← resolveTheoremInfo env query target
    let record := entry theoremSpec target info
    return (record, info.dependencies.map fun (kind, target) => { kind, target, required := true }, sources record.identity info)
  | "definition" =>
    let info ← resolveDefinitionInfo env query target
    let normalized ← if info.value.alias.isSome || info.value.unwrap.isSome then pure info.value else do
      let display ← info.value.display
      pure { info.value with kind := some display.kind, arguments := some display.arguments, styles := some display.styles }
    let record := entry definitionSpec target { info with value := normalized }
    return (record, info.dependencies.map fun (kind, target) => { kind, target, required := true }, sources record.identity info)
  | "variable" =>
    let info ← resolveVariableInfo env query target
    let record := entry variableSpec target info
    return (record, #[], sources record.identity info)
  | "phrase" =>
    let info ← resolvePhraseInfo env query target
    let record := entry phraseSpec target info
    return (record, #[], sources record.identity info)
  | _ =>
    throw { message := s!"unsupported rendering dependency kind `{kind}`", kind := some kind, target := some (toString target) }

/-- Resolve only actual use at one explicit boundary and validate every invocation's pinned contract. -/
def freezeSnapshot (env : Environment) (query : Query) (dependencies : Array RenderDependency)
    (contracts : Array RecordingContract) : Except Diagnostic Snapshot := do
  let events ← queryEvents env query
  let mut records := #[]
  let mut provenance := #[]
  let mut pending := dependencies.toList
  let mut actualContracts : Array RecordingContract := #[]
  for contract in contracts do
    unless contract.contractVersion == recordingContractVersion && contract.recordingVersion == recordingProtocolVersion do
      throw { message := "unsupported invocation contract version; rebuild or migrate the artifact", target := some contract.ruleId.toString }
    if actualContracts.any (·.id == contract.id) then continue
    let info ← resolveScriptInfoWithRegistration env query contract.registration
    let record := entry scriptSpec contract.ruleId info
    unless records.any (·.identity == record.identity) do
      records := records.push record
      provenance := provenance.push (sources record.identity info)
    pending := pending ++ (← rendererDependencies env query info.value.renderer).toList
    actualContracts := actualContracts.push contract
  let mut visited : Array InfoTarget := #[]
  while !pending.isEmpty do
    let dependency := pending.head!
    pending := pending.tail!
    let identity : InfoTarget := { kind := dependency.kind, target := dependency.target }
    identity.validate |>.mapError fun message => { message }
    let configured := events.any (·.identity == identity)
    unless #[projectSpec.kind, theoremSpec.kind, definitionSpec.kind, variableSpec.kind, phraseSpec.kind, scriptSpec.kind].contains identity.kind do
      throw { message := "unsupported rendering dependency kind", kind := some identity.kind, target := some (toString identity.target) }
    if !configured && dependency.required then
      throw { message := "required rendering dependency is not configured", kind := some dependency.kind, target := some (toString dependency.target) }
    if visited.contains identity then continue
    visited := visited.push identity
    if identity.kind == scriptSpec.kind then
      let .inl target := identity.target | unreachable!
      let registration ← scriptRegistrationInView env query ⟨target⟩
      let info ← resolveScriptInfoWithRegistration env query registration
      let contract := RecordingContract.ofRegistration registration
      unless actualContracts.any (·.id == contract.id) do actualContracts := actualContracts.push contract
      let record := entry scriptSpec identity.target info
      unless records.any (·.identity == identity) do
        records := records.push record
        provenance := provenance.push (sources record.identity info)
      pending := pending ++ (← rendererDependencies env query info.value.renderer).toList
      continue
    if !configured then
      if identity.kind == theoremSpec.kind then
        let .inl name := identity.target | unreachable!
        unless env.contains name do throw { message := "unknown page declaration", kind := some theoremSpec.kind, target := some name.toString }
        let fallback : SnapshotRecord := {
          identity := identity
          schemaId := theoremSpec.schema.id
          schemaVersion := theoremSpec.schema.version
          value := theoremSpec.schema.encode {}
          configured := false }
        records := records.push fallback
      continue
    let (record, extra, origins) ← dependencyRecords env query dependency
    records := records.push record
    provenance := provenance.push origins
    pending := pending ++ extra.toList
  records := records.qsort fun a b =>
    if a.identity.kind != b.identity.kind then a.identity.kind < b.identity.kind
    else match a.identity.target, b.identity.target with
      | .inl left, .inl right => left.cmp right == .lt
      | .inr left, .inr right => left < right
      | .inl _, .inr _ => true
      | .inr _, .inl _ => false
  actualContracts := actualContracts.qsort (·.id < ·.id)
  return { query, records, contracts := actualContracts, provenance }

def freezeArtifacts (env : Environment) (query : Query) (artifacts : Array Output.Artifact)
    (additional : Array RenderDependency := #[]) : Except Diagnostic Snapshot :=
  freezeSnapshot env query (additional ++ artifacts.flatMap fun artifact =>
    artifact.dependencies ++ artifact.declaration.toList.toArray.map fun name =>
      { kind := theoremSpec.kind, target := .inl name })
    (artifacts.flatMap fun artifact => artifact.bindings.map (·.contract))

/-- Exporter API for independent proofs and modules without page_end; frozen pages are retained verbatim. -/
def freezeModuleArtifacts (env : Environment) (owner : Name) : Except Diagnostic (Array (String × Snapshot)) := do
  let artifacts := Output.moduleArtifacts env owner
  unless artifacts.all (·.schemaVersion == Output.manifestSchemaVersion) do
    throw { message := "unsupported persisted artifact manifest version; rebuild or migrate the artifact" }
  let snapshots := moduleSnapshots env owner
  let pending := artifacts.filter fun artifact => match artifact.scope with | .frozen _ => false | _ => true
  let final ← if pending.isEmpty then pure none else some <$> freezeArtifacts env { moduleName := owner } pending
  artifacts.mapM fun artifact => do
    let snapshot ← match artifact.scope with
      | .frozen id => match snapshots.find? (·.id == id) with
        | some snapshot => pure snapshot
        | none => throw { message := "artifact references a missing frozen snapshot" }
      | _ => match final with
        | some snapshot => pure snapshot
        | none => throw { message := "missing module-end snapshot" }
    snapshot.validateVersions
    discard <| theoremFactsForArtifact env artifact snapshot.query snapshot.id
    return (artifact.key.id, snapshot)

/-- Export-ready semantic theorem facts, including standalone proofs frozen at their owner's module end. -/
def freezeModuleTheorems (env : Environment) (owner : Name) :
    Except Diagnostic (Array (String × FrozenTheoremFacts)) := do
  let artifacts := Output.moduleArtifacts env owner
  let views ← freezeModuleArtifacts env owner
  let mut result := #[]
  for (id, snapshot) in views do
    let some artifact := artifacts.find? (·.key.id == id)
      | throw { message := "theorem view has no artifact" }
    if let some facts ← theoremFactsForArtifact env artifact snapshot.query snapshot.id then
      result := result.push (id, facts)
  return result

end ProofScript.Info
