import ProofScript.Info.Project

open Lean Elab.Command


namespace ProofScript

structure TheoremInfo where
  project : Option String := none
  name : String := ""
  tags : List String := []
  extra : ExtraFields := {}
  deriving Inhabited, InfoSchema

instance : InfoSchema TheoremInfo :=
  (inferInstance : InfoSchema TheoremInfo).withOverrides! {
    fields := #[TheoremInfo.infoFields.project.withCodec projectReferenceCodec] }

def theoremSpec : InfoSpec TheoremInfo := {
  kind := "theorem",
  dependencies := fun value => value.project.toList.toArray.map fun name => (projectSpec.kind, .inr name)
}

/-- A registered declaration inherits the default of its first registering module.
This also covers ordinary Lean theorems first annotated outside their defining module. -/
private def theoremDefaultProject (env : Environment) (query : Query) (declaration : Name) :
    Except Diagnostic (Option String) := do
  let events := (← queryEvents env query).filter fun event =>
    event.identity == { kind := theoremSpec.kind, target := .inl declaration }
  let graph := ModuleGraph.ofEnvironment env
  let mut owners : Array Name := #[]
  for event in events do
    if !owners.contains event.owner then owners := owners.push event.owner
  let roots := owners.filter fun owner => !owners.any fun ancestor =>
    owner != ancestor && graph.dependsOn owner ancestor
  let mut projects : Array String := #[]
  for owner in roots do
    let ownerQuery : Query := { moduleName := owner }
    if let some project ← moduleDefaultProject env ownerQuery then
      if !projects.contains project then projects := projects.push project
  if projects.size > 1 then
    throw {
      message := "conflicting default projects from independent theorem registrations; configure theorem_info.project explicitly"
      path := #[.key "project"]
      related := events.map fun event =>
        { owner := event.owner, sequence := event.sequence, source := event.source } }
  return projects[0]?

/-- Project assignments, including null/reset, take precedence over the module default. -/
def theoremProjectInView (env : Environment) (query : Query) (declaration : Name)
    (view : PartialView) : Except Diagnostic (Option String) := do
  let some unit := view.units.find? (·.key == .field "project")
    | throw { message := "theorem schema is missing the project field" }
  let project ← if unit.candidates.isEmpty then
      if view.created then theoremDefaultProject env query declaration else pure none
    else do
      let some value ← unit.value.mapError view.attach
        | throw ({ message := "missing project assignment", path := #[.key "project"] } : Diagnostic)
      (projectReferenceCodec.decode value).mapError fun error => view.attach (error.atField "project")
  if let some project := project then
    discard <| (resolveProjectInfo env query project).mapError fun error =>
      view.attach { error with path := #[.key "project"] }
  return project

def resolveTheoremInfo (env : Environment) (query : Query) (declaration : Name)
    : Except Diagnostic (ResolvedInfo TheoremInfo) :=
  (do
    unless env.contains declaration do throw { message := "unknown declaration" }
    let view ← resolvePartial theoremSpec env query declaration
    unless view.created do throw { message := "theorem metadata is not configured" }
    let info ← consumeView theoremSpec view
    let project ← theoremProjectInView env query declaration view
    let value := { info.value with project }
    return { info with value, dependencies := theoremSpec.dependencies value }
      : Except Diagnostic (ResolvedInfo TheoremInfo)).mapError fun error =>
      { error with kind := some theoremSpec.kind, target := some declaration.toString }

def updateTheoremInfo (id : TSyntax `ident) (fields : Array InputField)
    (ref : Syntax) : CommandElabM Unit := do
  let declaration ← resolveDeclaration id
  let patch ← parsePatch (inferInstance : InfoSchema TheoremInfo) fields
  commitInfoCommand theoremSpec declaration patch ref

end ProofScript
