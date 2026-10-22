import ProofScript.Info.Theorem

namespace ProofScript.Info

open Lean

/-- Resolve only project ownership, at an explicit freeze boundary.
`defaultProject` is captured when a ProofScript declaration succeeds; ordinary Lean theorems
pass `none`. Never substitute the exporter's current active project for this argument. -/
def resolveTheoremProject (env : Environment) (query : Query) (declaration : Name)
    (defaultProject : Option String := none) : Except Diagnostic (Option String) :=
  (do
    unless env.contains declaration do throw { message := "unknown declaration" }
    let view ← resolvePartial theoremSpec env query declaration
    let some unit := view.units.find? (·.key == .field "project")
      | throw { message := "theorem schema is missing the project field" }
    -- JSON null/reset is an assignment. Only the absence of candidates permits the default.
    let project ← if unit.candidates.isEmpty then pure defaultProject else do
      let some value ← unit.value.mapError view.attach
        | throw ({ message := "missing project assignment", path := #[.key "project"] } : Diagnostic)
      (projectReferenceCodec.decode value).mapError fun error => view.attach (error.atField "project")
    if let some project := project then
      discard <| (resolveProjectInfo env query project).mapError fun error =>
        view.attach { error with path := #[.key "project"] }
    return project : Except Diagnostic (Option String)).mapError fun error =>
      { error with kind := some theoremSpec.kind, target := some declaration.toString }

/-- A source theorem without project ownership is an error, never a successful empty dependency list. -/
def requireTheoremProject (env : Environment) (query : Query) (declaration : Name)
    (defaultProject : Option String := none) : Except Diagnostic String := do
  let some project ← resolveTheoremProject env query declaration defaultProject
    | throw ({
        message := "cannot export proof dependencies without a project; configure theorem_info.project"
        kind := some theoremSpec.kind
        target := some declaration.toString
        path := #[.key "project"] } : Diagnostic)
  return project

end ProofScript.Info
