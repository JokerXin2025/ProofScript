import ProofScript.Info.Snapshot
import ProofScript.Page.State
import ProofScript.Output.Path

/-! Finalize a closed page using only its owner's completed module and imports. -/

namespace ProofScript

open Lean

private def theoremRecord (snapshot : Snapshot) (name : Name) : Except Diagnostic (SnapshotRecord × TheoremInfo) := do
  let some record := snapshot.find? theoremSpec.kind name
    | throw { message := "page declaration is absent from its snapshot", target := some name.toString }
  return (record, ← (inferInstance : InfoSchema TheoremInfo).decode record.value)

private def resolveComponent (snapshot : Snapshot) (component : ProofScript.Component) :
    Except Diagnostic ProofScript.Component := do
    let mut value := component.value
    if let some name := component.declaration then
      let (_, info) ← theoremRecord snapshot name
      let title := if info.name.isEmpty then name.getString! else info.name
      let proof ← value.getObjVal? "proof" |>.mapError fun message => { message }
      let sorryAx ← value.getObjVal? "sorryAx" |>.mapError fun message => { message }
      value := json% { name: $title, proof: $proof, sorryAx: $sorryAx }
    if component.kind == "references" then
      let mut refs := #[]
      for ref in component.references do
        let (record, info) ← theoremRecord snapshot ref.name
        -- Preserve the existing display policy for declarations without theorem metadata.
        unless record.configured do continue
        let project ← match info.project with
          | none => pure (json% null)
          | some id =>
            let some project := snapshot.find? projectSpec.kind id
              | throw { message := "reference project is absent from its snapshot", target := some id }
            pure project.value
        refs := refs.push <| json% {
          name: $(ref.name),
          isDependency: $(ref.isDependency),
          info: $(record.value),
          project: $project
        }
      value := .arr refs
    return { component with value, snapshotId := some snapshot.id }

structure FinalizedPage where
  page : ProofScript.Page
  view : FrozenArtifact
  componentSnapshots : Array Snapshot
  deriving Inhabited

/-- Rebuild presentation from the persisted page draft after module compilation.
The proof's own snapshot is reused exactly; recording data is never replayed here. -/
def finalizePage (env : Environment) (draft : ProofScript.Page) (proofs : Array FrozenArtifact) :
    Except Diagnostic FinalizedPage := do
  let query : Query := { moduleName := draft.module }
  let mut components := #[]
  let mut snapshots := #[]
  for component in draft.components do
    let snapshot ← match component.declaration with
      | some declaration => do
        let some view := proofs.find? fun view =>
            view.artifact.key.kind == .proof && view.artifact.declaration == some declaration
          | throw { message := "page declaration has no proof artifact", target := some declaration.toString }
        unless view.snapshot.query == query do
          throw { message := "page proof belongs to another module", target := some declaration.toString }
        pure view.snapshot
      | none => do
        let dependencies := component.references.map fun ref =>
          { kind := theoremSpec.kind, target := .inl ref.name : RenderDependency }
        freezeSnapshot env query dependencies #[]
    components := components.push (← resolveComponent snapshot component)
    unless snapshots.any (·.id == snapshot.id) do snapshots := snapshots.push snapshot
  let page := { draft with components }
  let view ← freezeArtifact env {
    key := { owner := draft.module, kind := .page, name := draft.module }
    path := (pageOutputPath draft.module).toString
    contentDigest := (toJson page).sha256 }
  return { page, view, componentSnapshots := snapshots }

end ProofScript
