import ProofScript.Info.Commands
import ProofScript.Info.Snapshot
import ProofScript.Page.Component.Declaration
import ProofScript.Page.Component.References

/-! Page export resolves every component at its own creation boundary. -/

namespace ProofScript.Info

open Lean Elab Command

private def pageDependencies (components : Array ProofScript.Component) : Array Output.RenderDependency :=
  components.flatMap fun component =>
    (component.declaration.toList.toArray ++ component.references).map fun name =>
      { kind := theoremSpec.kind, target := .inl name }

private def theoremRecord (snapshot : Snapshot) (name : Name) : Except Diagnostic (SnapshotRecord × TheoremInfo) := do
  let some record := snapshot.find? theoremSpec.kind name
    | throw { message := "page declaration is absent from its snapshot", target := some name.toString }
  return (record, ← (inferInstance : InfoSchema TheoremInfo).decode record.value)

def resolveSnapshotComponents (snapshot : Snapshot) (components : Array ProofScript.Component) :
    Except Diagnostic (Array ProofScript.Component) := do
  snapshot.validateVersions
  components.mapM fun component => do
    let mut value := component.value
    if let some name := component.declaration then
      let (_, info) ← theoremRecord snapshot name
      let title := if info.name.isEmpty then name.getString! else info.name
      let proof ← value.getObjVal? "proof" |>.mapError fun message => { message }
      let sorryAx ← value.getObjVal? "sorryAx" |>.mapError fun message => { message }
      value := json% { name: $title, proof: $proof, sorryAx: $sorryAx }
    if component.kind == "references" then
      let mut refs := #[]
      for name in component.references do
        let (record, info) ← theoremRecord snapshot name
        -- Preserve the existing display policy for declarations without theorem metadata.
        unless record.configured do continue
        let project ← match info.project with
          | none => pure (json% null)
          | some id =>
            let some project := snapshot.find? projectSpec.kind id
              | throw { message := "reference project is absent from its snapshot", target := some id }
            pure project.value
        refs := refs.push <| json% {
          name: $name,
          info: $(record.value),
          project: $project
        }
      value := .arr refs
    return { component with value }

/-- Export does not select a metadata boundary: each component already carries its own. -/
def freezePage (env : Environment) (source : String) : Except Diagnostic (Environment × ProofScript.Page × Snapshot) := do
  let state := getPageState env
  if state.exported then throw { message := "page_end may only appear once in a module" }
  let artifacts := Output.moduleArtifacts env env.mainModule
  let mut components := #[]
  let mut snapshots := #[]
  for component in state.components do
    let query : Query := { moduleName := env.mainModule, boundary := component.boundary }
    let snapshot ← match component.declaration with
      | some declaration => do
        let some artifact := artifacts.find? fun artifact =>
            artifact.key.kind == .proof && artifact.declaration == some declaration
          | throw { message := "page declaration has no proof artifact", target := some declaration.toString }
        freezeArtifacts env artifact.query #[artifact]
      | none => freezeSnapshot env query (pageDependencies #[component]) #[]
    let resolved ← resolveSnapshotComponents snapshot #[component]
    let component := { resolved[0]! with snapshotId := some snapshot.id }
    components := components.push component
    unless snapshots.any (·.id == snapshot.id) do snapshots := snapshots.push snapshot
  -- The page envelope represents the context in which the page starts. Component
  -- metadata above remains independent of this envelope and of the export command.
  let boundary := state.components[0]?.map (·.boundary) |>.getD (currentBoundary env)
  let query : Query := { moduleName := env.mainModule, boundary }
  let mut dependencies := #[]
  if let .ok (some project) := activeProject env query then
    dependencies := dependencies.push { kind := projectSpec.kind, target := project, required := true }
  let snapshot ← freezeSnapshot env query dependencies #[]
  let page : ProofScript.Page := { module := env.mainModule, source, components }
  let nextEnv := (snapshots.push snapshot).foldl snapshotExt.addEntry env
  let artifact : Output.Artifact := {
    key := { owner := env.mainModule, kind := .page, name := env.mainModule }
    path := (pageOutputPath env.mainModule).toString
    boundary
    dependencies := dependencies
    contentDigest := (toJson page).sha256 }
  let nextEnv ← Output.registerArtifact nextEnv artifact |>.mapError fun message => { message }
  let nextEnv ← closePage nextEnv |>.mapError fun message => { message }
  return (nextEnv, page, snapshot)

@[command_elab ProofScript.scriptTheoremImpl, command_elab ProofScript.byTheoremImpl]
def elabDeclaration : CommandElab := fun _ => elaborateDeclaration

elab "page_end" : command => whenPageBuild do
  let (env, page, _) ← match freezePage (← getEnv) (← getFileName) with
    | .ok result => pure result
    | .error error => throwError error.render
  let path ← liftIO <| activeOutputPath (pageOutputPath page.module)
  liftIO do
    path.ensureParentDir
    IO.FS.writeFile path (toJson page).pretty
  setEnv env

end ProofScript.Info
