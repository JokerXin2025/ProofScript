import ProofScript.Info.Theorem
import ProofScript.Info.Definition
import ProofScript.Info.Script
import ProofScript.Output.Manifest
import ProofScript.Info.TheoremDependencies
import ProofScript.Core.ModuleExtensionEntries

namespace ProofScript

open Lean

def snapshotSchemaVersion : String := "9"

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
  let order ← (ModuleGraph.ofEnvironment env).modulesInDependencyOrder query.moduleName
    |>.mapError fun message => { message }
  let entries := order.flatMap (moduleExtensionEntries rendererDependencyExt env)
  return (entries.filter (·.renderer == renderer)).flatMap (·.dependencies)

structure SnapshotRecord where
  identity : InfoTarget
  schemaId : Name
  schemaVersion : String
  value : Json
  configured : Bool := true
  projectId : Option String := none
  deriving Inhabited, FromJson

instance : ToJson SnapshotRecord where
  toJson record :=
    let value := json% {
      identity: $(record.identity), schemaId: $(record.schemaId),
      schemaVersion: $(record.schemaVersion), value: $(record.value),
      configured: $(record.configured) }
    if record.identity.kind == theoremSpec.kind then
      value.setObjVal! "projectId" (toJson record.projectId)
    else value

structure Snapshot where
  schemaVersion : String := snapshotSchemaVersion
  recordingVersion : String := recordingProtocolVersion
  contractVersion : String := recordingContractVersion
  query : Query
  records : Array SnapshotRecord
  contracts : Array RecordingContract
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
    Except Diagnostic (SnapshotRecord × Array RenderDependency) := do
  let kind := dependency.kind
  if let .inr project := dependency.target then
    throw { message := s!"project dependency {project} must be resolved from the Lake registry" }
  let .inl target := dependency.target | unreachable!
  match kind with
  | "theorem" =>
    let info ← resolveTheoremInfo env query target
    let record := entry theoremSpec target info
    return (record, info.dependencies.map fun (kind, target) => { kind, target, required := true })
  | "definition" =>
    let info ← resolveDefinitionInfo env query target
    let normalizedInfo : DefinitionInfo ← if info.value.kind == .alias || info.value.kind == .wrapper then
      pure info.value
      else do
        validateDefinitionInfo info.value
        pure info.value
    let some declaration := env.find? target
      | throw { message := "unknown declaration", kind := some kind, target := some target.toString }
    let explicitIndices := explicitArgumentIndices declaration.type
    let argumentIndices := if normalizedInfo.kind == .concept && !normalizedInfo.concept_info.auto_arity then
      allArgumentIndices declaration.type else explicitIndices
    if let some template := normalizedInfo.parameter_template then
      if (argumentReferences template).arguments.any (· >= explicitIndices.size) then
        throw { message := "parameter_template references a missing type argument", kind := some kind, target := some target.toString }
    let record := entry definitionSpec target { info with value := normalizedInfo }
    let declarationKind : String := match declaration with
      | .axiomInfo _ => "axiom"
      | .defnInfo _ => "definition"
      | .thmInfo _ => "theorem"
      | .opaqueInfo _ => "opaque"
      | .quotInfo _ => "quotient"
      | .inductInfo _ => "inductive"
      | .ctorInfo _ => "constructor"
      | .recInfo _ => "recursor"
    -- Definition records are already deduplicated in the frozen view. Attach
    -- declaration-level facts here so alias targets are available even when
    -- they do not occur as structural constants in a proof expression.
    let details := Json.mkObj [
      ("kind", toJson declarationKind),
      ("type", toJson (toString declaration.type)),
      ("levelParams", toJson (declaration.levelParams.map toString)),
      ("unsafe", toJson declaration.isUnsafe),
      ("partial", toJson declaration.isPartial)]
    let value := record.value.setObjVal! "argument_indices" (toJson argumentIndices)
      |>.setObjVal! "parameter_argument_indices" (toJson explicitIndices)
    let record := { record with value := value.setObjVal! "declaration" details }
    return (record, info.dependencies.map fun (kind, target) => { kind, target, required := true })
  | _ =>
    throw { message := s!"unsupported rendering dependency kind `{kind}`", kind := some kind, target := some (toString target) }

/-- Resolve actual configuration use in the owner's import closure and validate pinned contracts. -/
def freezeSnapshot (env : Environment) (registry : ProjectRegistry) (projectInfo : ProjectInfo) (query : Query)
    (dependencies : Array RenderDependency) (contracts : Array RecordingContract) : Except Diagnostic Snapshot := do
  let events ← queryEvents env query
  let mut records := #[]
  let projectDependency : RenderDependency :=
    ⟨projectSpec.kind, .inr registry.selected.projectId, true⟩
  let mut pending := projectDependency :: dependencies.toList
  let mut actualContracts : Array RecordingContract := #[]
  for contract in contracts do
    unless contract.contractVersion == recordingContractVersion && contract.recordingVersion == recordingProtocolVersion do
      throw { message := "unsupported invocation contract version; rebuild or migrate the artifact", target := some contract.ruleId.toString }
    if actualContracts.any (·.id == contract.id) then continue
    let info ← resolveScriptInfoWithRegistration env query contract.registration
    let record := entry scriptSpec contract.ruleId info
    unless records.any (·.identity == record.identity) do
      records := records.push record
    pending := pending ++ (← rendererDependencies env query info.value.renderer).toList
    actualContracts := actualContracts.push contract
  let mut visited : Array InfoTarget := #[]
  while !pending.isEmpty do
    let dependency := pending.head!
    pending := pending.tail!
    let identity : InfoTarget := { kind := dependency.kind, target := dependency.target }
    identity.validate |>.mapError fun message => { message }
    let configured := if identity.kind == projectSpec.kind then
      identity.target == .inr registry.selected.projectId else events.any (·.identity == identity)
    unless #[projectSpec.kind, theoremSpec.kind, definitionSpec.kind, scriptSpec.kind].contains identity.kind do
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
          configured := false
          projectId := (registry.declarationProject? env name).map ProjectKey.projectId }
        records := records.push fallback
      continue
    let (record, extra) ← if identity.kind == projectSpec.kind then do
      let schema : InfoSchema ProjectInfo := inferInstance
      let record : SnapshotRecord := {
        identity, schemaId := schema.id, schemaVersion := schema.version, value := schema.encode projectInfo }
      pure (record, #[])
    else dependencyRecords env query dependency
    let record := if identity.kind == theoremSpec.kind then
      match identity.target with
      | .inl name => { record with projectId := (registry.declarationProject? env name).map ProjectKey.projectId }
      | .inr _ => record
      else record
    records := records.push record
    pending := pending ++ extra.toList
  records := records.qsort fun a b =>
    if a.identity.kind != b.identity.kind then a.identity.kind < b.identity.kind
    else match a.identity.target, b.identity.target with
      | .inl left, .inl right => left.cmp right == .lt
      | .inr left, .inr right => left < right
      | .inl _, .inr _ => true
      | .inr _, .inl _ => false
  actualContracts := actualContracts.qsort (·.id < ·.id)
  return { query, records, contracts := actualContracts }

structure FrozenArtifact where
  artifact : Artifact
  snapshot : Snapshot
  facts : Option FrozenTheoremFacts
  projectId : Option String
  deriving Inhabited

/-- Resolve an artifact once, including its presentation, project and semantic proof facts. -/
def freezeArtifact (env : Environment) (registry : ProjectRegistry) (projectInfo : ProjectInfo)
    (artifact : Artifact) : Except Diagnostic FrozenArtifact := do
  unless artifact.schemaVersion == manifestSchemaVersion do
    throw { message := "unsupported persisted artifact manifest version; rebuild the defining module" }
  let projectId := if artifact.key.kind == .page then some registry.selected.projectId else none
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
      { kind := theoremSpec.kind, target := .inl name })
  let snapshot ← freezeSnapshot env registry projectInfo artifact.query dependencies (artifact.bindings.map (·.contract))
  let facts ← theoremFactsForArtifact env registry artifact snapshot.id
  return { artifact, snapshot, facts, projectId }

/-- Resolve each artifact in its defining module's final import closure.
The exporter's downstream or sibling modules cannot enter this view. -/
def freezeModuleArtifacts (env : Environment) (registry : ProjectRegistry) (projectInfo : ProjectInfo)
    (owner : Name) : Except Diagnostic (Array FrozenArtifact) :=
  (moduleArtifacts env owner).mapM (freezeArtifact env registry projectInfo)

end ProofScript
