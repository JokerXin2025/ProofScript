import ProofScript.Output.Protocol
import ProofScript.Build.Mode

namespace ProofScript.Output

open Lean Info System
open scoped Foundation

private def writeDocument (root : FilePath) (relative : String) (value : Json) : IO Json := do
  let path := root / relative
  path.ensureParentDir
  IO.FS.writeFile path value.pretty
  return json% { path: $relative, digest: $(value.sha256) }

private def artifactRelativePath (path : String) : IO String := do
  unless path.startsWith ".ProofScript/" do throw <| IO.userError s!"invalid artifact path: {path}"
  let relative := (path.drop ".ProofScript/".length).toString
  if relative.splitOn "/" |>.any (fun part => part == "..") then
    throw <| IO.userError s!"invalid artifact path: {path}"
  return String.intercalate "/" ((relative.splitOn "/").filter (!·.isEmpty))

private def checked [Inhabited α] (value : Except Diagnostic α) : IO α :=
  match value with | .ok value => pure value | .error error => throw <| IO.userError error.render

/-- Export only explicit owners. Importer/exporter local state cannot change their frozen views.
The completion index is written last; callers publish the entire directory atomically.
-/
def exportModules (env : Environment) (owners : Array Name) (root : FilePath) : IO Unit := do
  for owner in owners do
    match validateModuleBuildMode env owner with
    | .ok () => pure ()
    | .error message => throw <| IO.userError message
  let mut modules : Array Json := #[]
  let mut artifacts : Array Json := #[]
  let mut snapshots : Array Json := #[]
  let mut files : Array Json := #[]
  let mut seen : Array String := #[]
  for owner in owners do
    let events := moduleEvents env owner
    let eventPath := s!"info/modules/{moduleId owner}.json"
    let registrations := (scriptRegistrationsInModules env #[owner]).toArray.map fun registration =>
      let contract := RecordingContract.ofRegistration registration
      let parameters := registration.parameters.map fun (name, parser) =>
        json% { name: $name, shape: $(parser.shape?) }
      json% {
        owner: $(owner.toString), ruleId: $(registration.ruleId.toString),
        strategy: $(registration.strategy), contract: $contract, contractId: $(contract.id),
        parameters: $parameters,
        recordedFields: $(contract.fields) }
    let moduleDocument := json% {
      schemaVersion: $infoProtocolVersion,
      owner: $owner,
      module: $(owner.toString),
      events: $events,
      registrations: $registrations
    }
    files := files.push (← writeDocument root eventPath moduleDocument)
    let views ← checked <| freezeModuleArtifacts env owner
    let ownArtifacts := moduleArtifacts env owner
    let mut viewIds : Array String := #[]
    for (artifactId, snapshot) in views do
      let some artifact := ownArtifacts.find? (·.key.id == artifactId)
        | throw <| IO.userError "artifact view has no manifest entry"
      let relative ← artifactRelativePath artifact.path
      let value ← match Json.parse (← IO.FS.readFile (root / relative)) with
        | .ok value => pure value | .error message => throw <| IO.userError message
      unless value.sha256 == artifact.contentDigest do
        throw <| IO.userError s!"artifact content disagrees with .olean: {relative}; rebuild the outputs"
      files := files.push <| json% { path: $relative, digest: $(artifact.contentDigest) }
      let facts ← checked <| theoremFactsForArtifact env artifact snapshot.query snapshot.id
      let project := if facts.isSome then none else
        (activeProject env snapshot.query).toOption.getD none
      let published ← match artifact.exportJson snapshot facts project with
        | .ok value => pure value
        | .error message => throw <| IO.userError s!"{relative}: {message}"
      artifacts := artifacts.push <| published
        |>.setObjVal! "path" (.str (".ProofScript/" ++ relative))
      viewIds := viewIds.push snapshot.id
      unless seen.contains snapshot.id do
        seen := seen.push snapshot.id
        let path := s!"info/snapshots/{snapshot.id}.json"
        files := files.push (← writeDocument root path (snapshotDocument snapshot))
        snapshots := snapshots.push <| json% { id: $(snapshot.id), path: $path }
    -- Components such as references can consume views that no proof artifact uses.
    for snapshot in moduleSnapshots env owner do
      snapshot.validateVersions |> checked
      unless snapshot.query.moduleName == owner && snapshot.query.boundary != .endOfModule do
        throw <| IO.userError "component snapshot disagrees with its defining module/content boundary"
      viewIds := viewIds.push snapshot.id
      unless seen.contains snapshot.id do
        seen := seen.push snapshot.id
        let path := s!"info/snapshots/{snapshot.id}.json"
        files := files.push (← writeDocument root path (snapshotDocument snapshot))
        snapshots := snapshots.push <| json% { id: $(snapshot.id), path: $path }
    -- A public module-only load is unambiguous when one view is consumed by its artifacts.
    -- Config-only owners export events without demanding that all partial objects are complete.
    let defaultSnapshot := if viewIds.isEmpty then (json% null)
      else if viewIds.all (· == viewIds[0]!) then .str viewIds[0]! else (json% null)
    modules := modules.push <| json% {
      name: $owner,
      module: $(owner.toString),
      events: $eventPath,
      defaultSnapshot: $defaultSnapshot
    }
  files := files.push (← writeDocument root "info/schema/models.json" modelSchemas)
  files := files.push (← writeDocument root "info/schema/bundle.schema.json" protocolSchema)
  files := files.push (← writeDocument root "info/schema/snapshot.schema.json" snapshotSchema)
  let index := json% {
    schemaVersion: $infoProtocolVersion,
    recordingVersion: $recordingProtocolVersion,
    contractVersion: $recordingContractVersion,
    complete: true,
    modules: $modules,
    artifacts: $artifacts,
    snapshots: $snapshots,
    files: $files
  }
  let _ ← writeDocument root "info/index.json" index
  pure ()

end ProofScript.Output
