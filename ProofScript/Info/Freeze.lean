import ProofScript.Info.Theorem
import ProofScript.Info.Definition
import ProofScript.Info.Script
import ProofScript.Output.Manifest
import ProofScript.Info.Elab
import ProofScript.Core.BuildMode

namespace ProofScript

open Lean
open Lean.Elab.Command

structure RendererDependencyEntry where
  renderer : ScriptRenderer
  dependencies : Array RenderDependency
  deriving Inhabited

initialize rendererDependencyExt : SimplePersistentEnvExtension RendererDependencyEntry Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.rendererDependencies
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => () }

def declareRendererDependencies (env : Environment) (renderer : ScriptRenderer)
    (dependencies : Array RenderDependency) : Environment :=
  rendererDependencyExt.addEntry env { renderer, dependencies }

def rendererDependencies (env : Environment) (query : Query) (renderer : ScriptRenderer) :
    Except Diagnostic (Array RenderDependency) := do
  let order ← (ModuleGraph.ofEnvironment env).modulesInDependencyOrder query.moduleName
    |>.mapError fun message => { message }
  let entries := order.flatMap (moduleExtensionEntries rendererDependencyExt env)
  return (entries.filter (·.renderer == renderer)).flatMap (·.dependencies)

/-- A page component records requirements, not a value frozen at the request site. -/
structure InfoRequest where
  identity : InfoTarget
  required : Bool := false
  origin : String := ""
  /-- Which component owns the request; stand-alone API calls may leave this unset. -/
  component : Option Nat := none
  deriving Inhabited

initialize infoRequestExt : SimplePersistentEnvExtension InfoRequest Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.infoRequests
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => () }

/-- The public entry point for page components. Only local requests are persisted. -/
def requestInfo (env : Environment) (identity : InfoTarget)
    (required : Bool := false) (origin : String := "") : Except Diagnostic Environment := do
  identity.validate |>.mapError fun message => { message }
  return infoRequestExt.addEntry env { identity, required, origin }

/-- Check all component requirements before publishing any of the updates. -/
def requestComponentInfos (env : Environment) (requests : Array InfoRequest)
    (componentIndex : Nat) : Except Diagnostic Environment := do
  for request in requests do
    request.identity.validate |>.mapError fun message => { message }
  return requests.foldl (fun updated request =>
    infoRequestExt.addEntry updated { request with component := some componentIndex }) env

/-- Component elaborators use this gated entry point; requests are never frozen here. -/
def requestInfoCommand (identity : InfoTarget) (required : Bool := false)
    (origin : String := "") : CommandElabM Unit := do
  if ← pageBuild? then
    match requestInfo (← getEnv) identity required origin with
    | .ok env => setEnv env
    | .error diagnostic => throwError diagnostic.render

def moduleInfoRequests (env : Environment) (owner : Name) : Array InfoRequest :=
  moduleExtensionEntries infoRequestExt env owner

/-- Project updates carry their source module until Lake supplies the library key.
    Rebind only the visible owners of the selected library; never scan siblings. -/
def freezeProjectInfo (env : Environment) (query : Query) (projectId : String)
    (belongsToProject : Name → Bool) : Except Diagnostic (ResolvedInfo ProjectInfo) := do
  let events ← queryEvents env query
  let identity : InfoTarget := ⟨projectSpec.kind, .inr projectId⟩
  let selected := events.filterMap fun event =>
    if event.identity.kind == projectSpec.kind && belongsToProject event.owner &&
        event.identity.target == .inr event.owner.toString then
      some { event with identity }
    else none
  let view ← resolveEvents projectSpec (ModuleGraph.ofEnvironment env) selected query identity.target
  consumeView projectSpec view

/-- Preserve the strongest requirement and all contributing origins. -/
def mergeInfoRequests (requests : Array InfoRequest) : Array InfoRequest := Id.run do
  let mut merged := #[]
  for request in requests do
    if let some index := merged.findIdx? (·.identity == request.identity) then
      let old := merged[index]!
      let origin := if old.origin.isEmpty then request.origin
        else if request.origin.isEmpty || old.origin == request.origin then old.origin
        else old.origin ++ ", " ++ request.origin
      let updated : InfoRequest := { old with required := (old.required || request.required) }
      let updated := { updated with origin := origin }
      merged := merged.set! index updated
    else merged := merged.push request
  return merged

/-- Keep every requesting component for diagnostics without changing the
    persisted single-request representation. -/
def infoRequestOrigins (requests : Array InfoRequest) (identity : InfoTarget) : String :=
  let origins := requests.filter (·.identity == identity) |>.map fun request =>
    let label := if request.origin.isEmpty then "unspecified request" else request.origin
    match request.component with
    | some index => s!"{label} (component #{index})"
    | none => label
  String.intercalate ", " origins.toList

/-- Lake supplies the project identity when the owning module is exported. -/
def moduleProjectRequest (owner : Name) (projectId : String) : InfoRequest :=
  { identity := ⟨projectSpec.kind, .inr projectId⟩,
    origin := s!"module {owner}" }

structure FrozenInfo where
  identity : InfoTarget
  schemaId : Name
  schemaVersion : String
  value : Json
  dependencies : Array InfoTarget := #[]
  requiredDependencies : Array InfoTarget := #[]
  deriving Inhabited

private def frozen [InfoSchema Record] (spec : InfoSpec Record)
    (target : Name ⊕ String) (resolved : ResolvedInfo Record) : FrozenInfo :=
  let schema : InfoSchema Record := inferInstance
  { identity := { kind := spec.kind, target }, schemaId := schema.id,
    schemaVersion := schema.version, value := schema.encode resolved.value,
    dependencies := resolved.dependencies.map fun (kind, target) => { kind, target } }

private def argumentIndices (type : Expr) (explicitOnly : Bool) : Array Nat := Id.run do
  let mut type := type.consumeMData
  let mut index := 0
  let mut selected := #[]
  while let .forallE _ _ body binderInfo := type do
    if !explicitOnly || binderInfo == .default then selected := selected.push index
    index := index + 1
    type := body.consumeMData
  return selected

private def definitionFacts (env : Environment) (target : Name)
    (info : ResolvedInfo DefinitionInfo) : Except Diagnostic Json := do
  let value := info.value
  if value.kind != .alias && value.kind != .wrapper then validateDefinitionInfo value
  let some declaration := env.find? target
    | throw { message := "unknown declaration", kind := some "definition", target := some target.toString }
  let explicit := argumentIndices declaration.type true
  let all := if value.kind == .concept && !value.concept_info.auto_arity then
    argumentIndices declaration.type false else explicit
  if let some template := value.parameter_template then
    if (argumentReferences template).arguments.any (· >= explicit.size) then
      throw (⟨"parameter_template references a missing type argument", #[],
        some "definition", some target.toString⟩ : Diagnostic)
  let declarationKind : String := match declaration with
    | .axiomInfo _ => "axiom" | .defnInfo _ => "definition"
    | .thmInfo _ => "theorem" | .opaqueInfo _ => "opaque"
    | .quotInfo _ => "quotient" | .inductInfo _ => "inductive"
    | .ctorInfo _ => "constructor" | .recInfo _ => "recursor"
  let details := Json.mkObj [
    ("kind", toJson declarationKind),
    ("type", toJson (toString declaration.type)),
    ("levelParams", toJson (declaration.levelParams.map toString)),
    ("unsafe", toJson declaration.isUnsafe),
    ("partial", toJson declaration.isPartial)]
  return ((inferInstance : InfoSchema DefinitionInfo).encode
    { value with name := if value.name.isEmpty then target.toString else value.name })
    |>.setObjVal! "argument_indices" (toJson all)
    |>.setObjVal! "parameter_argument_indices" (toJson explicit)
    |>.setObjVal! "declaration" details

/-- Read-only materialization shared by previews and the future module exporter.
    Project identity is supplied by Lake during export, rather than inferred from module names. -/
def freezeInfo (env : Environment) (query : Query) (identity : InfoTarget)
    (projectOwners : Option (Name → Bool) := none) :
    Except Diagnostic FrozenInfo := do
  identity.validate |>.mapError fun message => { message }
  match identity.kind, identity.target with
  | "theorem", .inl target =>
    unless env.contains target do
      throw { message := "unknown declaration", kind := some identity.kind, target := some target.toString }
    return frozen theoremSpec target (← resolveInfo theoremSpec env query target)
  | "definition", .inl target =>
    unless env.contains target do
      throw { message := "unknown declaration", kind := some identity.kind, target := some target.toString }
    let view ← resolvePartial definitionSpec env query target
    let info ← if view.created then resolveDefinitionInfo env query target
      else resolveInfo definitionSpec env query target
    let record := frozen definitionSpec target info
    return { record with value := ← definitionFacts env target info }
  | "script", .inl target =>
    let info ← if target == unrecordedRuleId then
      pure ({ value := { renderer := .unrecorded }, dependencies := #[] } : ResolvedInfo ScriptInfo)
    else resolveScriptInfo env query target
    let extra ← rendererDependencies env query info.value.renderer
    let record := frozen scriptSpec target info
    let dependencies := record.dependencies ++ extra.map (fun dependency =>
      (⟨dependency.kind, dependency.target⟩ : InfoTarget))
    return { record with dependencies, requiredDependencies := extra.filterMap fun item =>
      if item.required then some ⟨item.kind, item.target⟩ else none }
  | "project", .inr target =>
    let owners := projectOwners.getD (fun owner =>
      let library := match Json.parse target with
        | .ok value => (value.getObjValAs? String "library").toOption.getD target
        | .error _ => target
      owner == Name.mkSimple library || (Name.mkSimple library).isPrefixOf owner)
    let info ← freezeProjectInfo env query target owners
    let library := match Json.parse target with
      | .ok value => (value.getObjValAs? String "library").toOption.getD target
      | .error _ => target
    let value := if info.value.title.isEmpty then { info.value with title := library }
      else info.value
    let record := frozen projectSpec target { info with value }
    return record
  | _, _ =>
    let diagnostic : Diagnostic := ⟨"unsupported Info kind", #[], some identity.kind,
      some (toString identity.target)⟩
    throw diagnostic

/-- Check whether an already discovered dependency path reaches a target. -/
private partial def dependencyReaches (edges : Array (InfoTarget × InfoTarget))
    (source target : InfoTarget) (seen : Array InfoTarget := #[]) : Bool :=
  if source == target then true
  else if seen.contains source then false
  else edges.any (fun (parent, child) =>
    parent == source && dependencyReaches edges child target (seen.push source))

/-- Freeze exactly the requested set and its declared Info dependencies. -/
def freezeRequestedInfo (env : Environment) (query : Query)
    (requests : Array InfoRequest) (projectOwners : Option (Name → Bool) := none)
    (projectId : Option String := none) :
    Except Diagnostic (Array FrozenInfo) := do
  let requests := requests.map fun request =>
    if request.identity.kind == projectSpec.kind then
      match projectId with
      | some id => { request with identity := ⟨projectSpec.kind, .inr id⟩ }
      | none => request
    else request
  let originalRequests := requests
  let requests := mergeInfoRequests requests
  let requestOrigin (identity : InfoTarget) (fallback : String) : String :=
    let origin := infoRequestOrigins originalRequests identity
    if origin.isEmpty then fallback else origin
  let mut pending := requests.toList.map fun request => (request.identity, request.required, request.origin)
  let mut frozenRecords := #[]
  let mut processed : Array InfoTarget := #[]
  let mut graphEdges : Array (InfoTarget × InfoTarget) := #[]
  let events ← if requests.isEmpty then pure #[] else queryEvents env query
  while !pending.isEmpty do
    let (identity, required, origin) := pending.head!
    pending := pending.tail!
    let origin := requestOrigin identity origin
    if required then
      let configured := if identity.kind == projectSpec.kind then
        events.any (fun event => event.identity.kind == projectSpec.kind &&
          (projectOwners.getD (fun owner =>
            (moduleEvents env owner).any (·.identity == identity))) event.owner &&
          event.identity.target == .inr event.owner.toString)
        else events.any (·.identity == identity)
      unless configured do
        throw ⟨s!"required Info is not configured (requested by {origin})", #[],
          some identity.kind, some (toString identity.target)⟩
    if processed.contains identity then continue
    processed := processed.push identity
    let record ← (freezeInfo env query identity projectOwners).mapError fun error =>
      if origin.isEmpty then error else
        { error with message := s!"{error.message} (requested by {origin})" }
    frozenRecords := frozenRecords.push record
    for dependency in record.dependencies do
      if dependencyReaches graphEdges dependency identity then
        throw ⟨s!"cyclic Info dependency through {identity.kind} {toString identity.target}", #[],
          some dependency.kind, some (toString dependency.target)⟩
      graphEdges := graphEdges.push (identity, dependency)
      -- Most dependencies admit defaults; explicit required edges do not.
      pending := pending ++ [(dependency, record.requiredDependencies.contains dependency,
        s!"{identity.kind} {toString identity.target}")]
  return frozenRecords

/-- The eventual module exporter uses this entry point after compiling the owner. -/
def freezeModuleRequests (env : Environment) (owner : Name) (projectId : String) :
    Except Diagnostic (Array FrozenInfo) :=
  freezeRequestedInfo env { moduleName := owner }
    (moduleInfoRequests env owner |>.push (moduleProjectRequest owner projectId))

end ProofScript
