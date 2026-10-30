import ProofScript.Info.Derive
import ProofScript.Info.Target

namespace ProofScript

open Lean Elab Command

structure ProjectInfo where
  title : String := ""
  authors : List String := []
  keywords : List String := []
  description : String := ""
  year : String := ""
  license : String := ""
  base_url : String := ""
  extra : ExtraFields := {}
  deriving Inhabited, InfoSchema

def projectSpec : InfoSpec ProjectInfo :=
  { kind := "project" }

/-- References never enter this table: only committed project configurations do. -/
def knownProjects (env : Environment) (query : Query) : Except Diagnostic (Array String) := do
  let mut projects := #[]
  for event in ← queryEvents env query do
    if event.identity.kind == projectSpec.kind then
      let .inr id := event.identity.target
        | throw { message := "project targets must be strings" }
      if !projects.contains id then projects := projects.push id
  return projects

def resolveProjectInfo (env : Environment) (query : Query) (name : String) :
    Except Diagnostic (ResolvedInfo ProjectInfo) :=
  (do
    let view ← resolvePartial projectSpec env query name
    unless view.created do throw { message := "project is not configured" }
    consumeView projectSpec view : Except Diagnostic (ResolvedInfo ProjectInfo)).mapError fun error =>
      { error with kind := some projectSpec.kind, target := some name }

def activeProjectBinding : String := "ProofScript.activeProject"

private def moduleProjectCandidates (env : Environment) (query : Query) :
    Except Diagnostic (Array String × Array InfoEvent) := do
  let projects := (← queryEvents env query).filter (·.identity.kind == projectSpec.kind)
  let localProjects := projects.filter (·.owner == query.moduleName)
  let candidates := if localProjects.isEmpty then projects else localProjects
  let mut names : Array String := #[]
  for event in candidates do
    let .inr name := event.identity.target
      | throw { message := "project targets must be strings" }
    if !names.contains name then names := names.push name
  return (names, candidates)

/-- A multi-project page has no default project; malformed configuration remains an error. -/
def unambiguousModuleProject (env : Environment) (query : Query) : Except Diagnostic (Option String) := do
  let (names, _) ← moduleProjectCandidates env query
  return if names.size > 1 then none else names[0]?

/-- Infer a module's project without choosing a source position. Local registrations
take precedence over inherited projects; multiple distinct candidates need explicit ownership. -/
def moduleDefaultProject (env : Environment) (query : Query) : Except Diagnostic (Option String) := do
  let (names, candidates) ← moduleProjectCandidates env query
  if names.size > 1 then
    throw {
      message := s!"ambiguous default project ({String.intercalate ", " names.toList}); configure theorem_info.project explicitly"
      path := #[.key "project"]
      related := candidates.map fun event =>
        { owner := event.owner, sequence := event.sequence, source := event.source } }
  return names[0]?

/-- The authoring context used by targetless project_info patches; renderers use moduleDefaultProject. -/
def activeProject (env : Environment) (query : Query) : Except Diagnostic (Option String) := do
  let unit ← resolveContext env query activeProjectBinding
  let value ← unit.value.mapError fun error => {
    error with message := "ambiguous active project; select one with `project_info \"P\" { ... }`"
               path := #[.key "project"] }
  value.mapM fun value => (fromJson? value).mapError fun message => { message }

/-- Project IDs are nonempty string literals, matched by their full text. -/
def resolveProjectTarget (stx : TSyntax `str) : CommandElabM String := do
  let name := stx.getString
  if name.isEmpty then throwErrorAt stx "project names must not be empty"
  return name

/-- Project references may precede their configuration; consumers validate their final view. -/
@[implicit_reducible] def projectReferenceCodec : InfoCodec (Option String) :=
  let _ : InfoCodec String := {
    parse := fun stx => do
      let `(term| $name:str) := stx
        | throwErrorAt stx "expected a string literal"
      resolveProjectTarget name
    toJson := toJson
    decode := fun value => do
      let name : String ← decodeJson value
      if name.isEmpty then throw { message := "project names must not be empty" }
      return name
    jsonSchema := InfoJson.nonemptyStringSchema }
  optionalInputCodec

def updateProjectInfo (target : Option (TSyntax `str)) (fields : Array InputField)
    (ref : Syntax) : CommandElabM Unit := do
  let patch ← parsePatch (inferInstance : InfoSchema ProjectInfo) fields
  let env ← getEnv
  let project ← match target with
    | some id => resolveProjectTarget id
    | none => match activeProject env { moduleName := env.mainModule } with
      | .ok project => pure (project.getD env.mainModule.toString)
      | .error error => throwErrorAt ref error.render
  let source := SourceLocation.ofSyntax (← getFileName) ref
  commitInfoCommand projectSpec project patch ref
    #[{ key := activeProjectBinding, value := toJson project, source }]

end ProofScript
