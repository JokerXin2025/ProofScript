import ProofScript.Info.Theorem
import ProofScript.Info.Definition
import ProofScript.Info.Phrase
import ProofScript.Info.Script
import ProofScript.Output.Manifest
import ProofScript.Info.TheoremDependencies

namespace ProofScript

open Lean

def snapshotSchemaVersion : String := "7"

structure RendererDependencyEntry where
  renderer : ScriptRenderer
  dependencies : Array RenderDependency
  deriving Inhabited

initialize rendererDependencyExt : SimplePersistentEnvExtension RendererDependencyEntry Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.rendererDependencies
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => () }

/-- Renderer integrations declare static configuration use; runtime-only access remains a backend check. -/
def declareRendererDependencies (env : Environment) (renderer : ScriptRenderer)
    (dependencies : Array RenderDependency) : Environment :=
  rendererDependencyExt.addEntry env { renderer, dependencies }

private def rendererDependencies (env : Environment) (query : Query) (renderer : ScriptRenderer) :
    Except Diagnostic (Array RenderDependency) := do
  let order ← (ModuleGraph.ofEnvironment env).order query.moduleName
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

open scoped InfoJson in
def Snapshot.payload (snapshot : Snapshot) :=
  let contracts := snapshot.contracts.map fun contract => json% {
    id: $(contract.id),
    value: $contract
  }
  json% {
    schemaVersion: $(snapshot.schemaVersion),
    query: { module: $(snapshot.query.moduleName) },
    recordingVersion: $(snapshot.recordingVersion),
    contractVersion: $(snapshot.contractVersion),
    records: $(snapshot.records),
    contracts: $contracts
  }

def Snapshot.id (snapshot : Snapshot) : String := snapshot.payload.sha256

def Snapshot.find? (snapshot : Snapshot) (kind : String) (target : Name ⊕ String) : Option SnapshotRecord :=
  snapshot.records.find? (fun record => record.identity.kind == kind && record.identity.target == target)

private def entry [InfoSchema Record] (spec : InfoSpec Record) (target : Name ⊕ String) (info : ResolvedInfo Record) : SnapshotRecord :=
  let schema : InfoSchema Record := inferInstance
  { identity := { kind := spec.kind, target }, schemaId := schema.id,
    schemaVersion := schema.version, value := schema.encode info.value }

private def sources (identity : InfoTarget) (info : ResolvedInfo Record) :=
  let fields := info.provenance.map fun (key, origins) =>
    json% { path: $(key.path), origins: $(origins.map Origin.related) }
  json% { identity: $identity, fields: $fields }

/-- Select explicit binders from the declaration's structural telescope. A
    dependent result may expose further binders after application; those require
    configured numeric indices rather than occurrence-specific type inference. -/
private def explicitArgumentIndices (type : Expr) : Array Nat := Id.run do
  let mut type := type.consumeMData
  let mut index := 0
  let mut selected := #[]
  while let .forallE _ _ body binderInfo := type do
    if binderInfo == .default then selected := selected.push index
    index := index + 1
    type := body.consumeMData
  return selected

private def allArgumentIndices (type : Expr) : Array Nat := Id.run do
  let mut type := type.consumeMData
  let mut index := 0
  let mut selected := #[]
  while let .forallE _ _ body _ := type do
    selected := selected.push index
    index := index + 1
    type := body.consumeMData
  return selected

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
    let normalizedInfo : DefinitionInfo ← if info.value.alias.isSome || info.value.unwrap.isSome then
      pure info.value
      else do
        let display ← info.value.display
        let normalized := { info.value with kind := some display.kind, styles := some display.styles }
        validateDefinitionInfo normalized
        pure normalized
    let some declaration := env.find? target
      | throw { message := "unknown declaration", kind := some kind, target := some target.toString }
    let argumentIndices := if normalizedInfo.auto_arity then explicitArgumentIndices declaration.type else allArgumentIndices declaration.type
    if let some template := normalizedInfo.parameter_template then
      if (argumentReferences template).arguments.any (· >= argumentIndices.size) then
        throw { message := "parameter_template references a missing type argument", kind := some kind, target := some target.toString }
    let record := entry definitionSpec target { info with value := normalizedInfo }
    let record := { record with value := record.value.setObjVal! "argument_indices" (toJson argumentIndices) }
    return (record, info.dependencies.map fun (kind, target) => { kind, target, required := true }, sources record.identity info)
  | "phrase" =>
    let info ← resolvePhraseInfo env query target
    let record := entry phraseSpec target info
    return (record, #[], sources record.identity info)
  | _ =>
    throw { message := s!"unsupported rendering dependency kind `{kind}`", kind := some kind, target := some (toString target) }

/-- Resolve actual configuration use in the owner's import closure and validate pinned contracts. -/
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
    unless #[projectSpec.kind, theoremSpec.kind, definitionSpec.kind, phraseSpec.kind, scriptSpec.kind].contains identity.kind do
      throw { message := "unsupported rendering dependency kind", kind := some identity.kind, target := some (toString identity.target) }
    if !configured && dependency.required then
      throw { message := "required rendering dependency is not configured", kind := some dependency.kind, target := some (toString dependency.target) }
    if visited.contains identity then continue
    visited := visited.push identity
    if identity.kind == scriptSpec.kind then
      let .inl target := identity.target | unreachable!
      let registration ← scriptRegistrationInView env query target
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
        let schema : InfoSchema TheoremInfo := inferInstance
        let fallback : SnapshotRecord := {
          identity := identity
          schemaId := schema.id
          schemaVersion := schema.version
          value := schema.encode {}
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

structure FrozenArtifact where
  artifact : Artifact
  snapshot : Snapshot
  facts : Option FrozenTheoremFacts
  projectId : Option String
  deriving Inhabited

/-- Resolve an artifact once, including its presentation, project and semantic proof facts. -/
def freezeArtifact (env : Environment) (artifact : Artifact) : Except Diagnostic FrozenArtifact := do
  unless artifact.schemaVersion == manifestSchemaVersion do
    throw { message := "unsupported persisted artifact manifest version; rebuild the defining module" }
  let projectId ← if artifact.declaration.isSome then pure none else
    unambiguousModuleProject env artifact.query
  let references ← match artifact.declaration with
    | none => pure #[]
    | some declaration => do
      let some facts := declarationFacts? env declaration
        | throw { message := "missing declaration reference facts; rebuild the defining module", target := some declaration.toString }
      pure <| facts.proofRefs.filterMap fun ref =>
        if ref.isDependency then some { kind := theoremSpec.kind, target := .inl ref.name : RenderDependency }
        else none
  let dependencies := artifact.dependencies ++
    references ++
    artifact.declaration.toList.toArray.map (fun name =>
      { kind := theoremSpec.kind, target := .inl name }) ++
    projectId.toList.toArray.map (fun id =>
      { kind := projectSpec.kind, target := .inr id, required := true })
  let snapshot ← freezeSnapshot env artifact.query dependencies (artifact.bindings.map (·.contract))
  let facts ← theoremFactsForArtifact env artifact snapshot.id
  return { artifact, snapshot, facts, projectId }

/-- Resolve each artifact in its defining module's final import closure.
The exporter's downstream or sibling modules cannot enter this view. -/
def freezeModuleArtifacts (env : Environment) (owner : Name) : Except Diagnostic (Array FrozenArtifact) :=
  (moduleArtifacts env owner).mapM (freezeArtifact env)

end ProofScript
