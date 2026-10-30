import ProofScript.Output.Protocol
import ProofScript.Core.BuildMode
import ProofScript.Page.Finalize

namespace ProofScript

open Lean System
open scoped InfoJson

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
      json% {
        owner: $(owner.toString), ruleId: $(registration.ruleId.toString),
        kind: $(match registration.config.kind with
          | .tactic => "tactic"
          | .strategy => "strategy"
          | .metadata => "metadata"),
        contract: $contract, contractId: $(contract.id) }
    let moduleDocument := json% {
      schemaVersion: $infoProtocolVersion,
      owner: $owner,
      module: $(owner.toString),
      events: $events,
      registrations: $registrations
    }
    files := files.push (← writeDocument root eventPath moduleDocument)
    let mut views ← checked <| freezeModuleArtifacts env owner
    let mut viewIds : Array String := #[]
    let mut consumed : Array Snapshot := #[]
    if let some draft := modulePageDraft? env owner then
      let finalized ← checked <| finalizePage env draft views
      let relative ← artifactRelativePath finalized.view.artifact.path
      files := files.push (← writeDocument root relative (toJson finalized.page))
      views := views.push finalized.view
      consumed := finalized.componentSnapshots
    for view in views do
      let artifact := view.artifact
      let snapshot := view.snapshot
      let relative ← artifactRelativePath artifact.path
      if artifact.key.kind == .proof then
        let value ← match Json.parse (← IO.FS.readFile (root / relative)) with
          | .ok value => pure value | .error message => throw <| IO.userError message
        unless value.sha256 == artifact.contentDigest do
          throw <| IO.userError s!"artifact content disagrees with .olean: {relative}; rebuild the outputs"
        files := files.push <| json% { path: $relative, digest: $(artifact.contentDigest) }
      let published ← match artifact.exportJson snapshot view.facts view.projectId with
        | .ok value => pure value
        | .error message => throw <| IO.userError s!"{relative}: {message}"
      artifacts := artifacts.push <| published
        |>.setObjVal! "path" (.str (".ProofScript/" ++ relative))
      consumed := consumed.push snapshot
    -- Components such as references can consume views that no proof artifact uses.
    for snapshot in consumed do
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

end ProofScript
