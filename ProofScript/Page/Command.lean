import ProofScript.Info.Commands
import ProofScript.Info.Snapshot
import ProofScript.Page.Component.Declaration
import ProofScript.Page.Component.References

/-! Public page integration: resolve metadata and freeze configuration at page_end. -/

namespace ProofScript.Info

open Lean Elab Command

private def pageDependencies (components : Array ProofScript.Component) : Array Output.RenderDependency :=
  components.flatMap fun component =>
    (component.data.declaration.toList.toArray ++ component.data.references).map fun name =>
      { kind := theoremSpec.kind, target := .inl name }

private def theoremRecord (snapshot : Snapshot) (name : Name) : Except Diagnostic (SnapshotRecord × TheoremInfo) := do
  let some record := snapshot.find? theoremSpec.kind name
    | throw { message := "page declaration is absent from its snapshot", target := some name.toString }
  return (record, ← theoremSpec.schema.decode record.value)

def resolveSnapshotComponents (snapshot : Snapshot) (components : Array ProofScript.Component) :
    Except Diagnostic (Array ProofScript.Component) := do
  snapshot.validateVersions
  components.mapM fun component => do
    let mut value := component.data.value
    if let some name := component.data.declaration then
      let (_, info) ← theoremRecord snapshot name
      let title := if info.name.isEmpty then name.getString! else info.name
      let proof ← value.getObjVal? "proof" |>.mapError fun message => { message }
      let sorryAx ← value.getObjVal? "sorryAx" |>.mapError fun message => { message }
      value := json% { name: $title, proof: $proof, sorryAx: $sorryAx }
    if component.data.kind == "references" then
      let mut refs := #[]
      for name in component.data.references do
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
    return { component with data := { component.data with value } }

/-- Compute the entire close transaction before any writer or environment mutation runs. -/
def freezePage (env : Environment) (source : String) : Except Diagnostic (Environment × ProofScript.Page × Snapshot) := do
  let state := getPageState env
  if state.exported then throw { message := "page_end may only appear once in a module" }
  let query : Query := { moduleName := env.mainModule, boundary := currentBoundary env }
  let artifacts := (Output.moduleArtifacts env env.mainModule).filter (·.scope == .pendingPage)
  let mut dependencies := pageDependencies state.components
  if let .ok (some project) := activeProject env query then
    dependencies := dependencies.push { kind := projectSpec.kind, target := project, required := true }
  let snapshot ← freezeArtifacts env query artifacts dependencies
  let snapshotId := snapshot.id
  let theoremEnv ← freezePageTheorems env query snapshotId artifacts
  let components ← resolveSnapshotComponents snapshot state.components
  let page : ProofScript.Page := { module := env.mainModule, source, components }
  let nextEnv := snapshotExt.addEntry theoremEnv snapshot
  let nextEnv := Output.bindPageArtifacts nextEnv env.mainModule snapshotId
  let artifact : Output.Artifact := {
    key := { owner := env.mainModule, kind := .page, name := env.mainModule }
    path := (pageOutputPath env.mainModule).toString
    scope := .frozen snapshotId
    dependencies := dependencies
    contentDigest := (toJson page).sha256 }
  let nextEnv ← Output.registerArtifact nextEnv artifact |>.mapError fun message => { message }
  let nextEnv ← closePage nextEnv |>.mapError fun message => { message }
  return (nextEnv, page, snapshot)

@[command_elab ProofScript.scriptTheoremImpl, command_elab ProofScript.byTheoremImpl]
def elabDeclaration : CommandElab := fun _ => elaborateDeclaration

elab "page_end" : command => do
  let (env, page, _) ← match freezePage (← getEnv) (← getFileName) with
    | .ok result => pure result
    | .error error => throwError error.render
  let path ← liftIO <| activeOutputPath (pageOutputPath page.module)
  liftIO do
    ensureParentDir path
    IO.FS.writeFile path (toJson page).pretty
  setEnv env

end ProofScript.Info
