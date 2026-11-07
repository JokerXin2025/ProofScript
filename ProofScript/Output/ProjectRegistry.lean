import ProofScript.Output.Dependencies
import ProofScript.Info.Project

namespace ProofScript

open Lean System

/-- A Lake library is identified together with its package. -/
structure ProjectKey where
  package : String
  library : String
  deriving Inhabited, BEq, Repr, ToJson, FromJson

/-- The package inventory and the ownership of this export's modules. -/
structure ProjectRegistry where
  selected : ProjectKey
  projects : Array ProjectKey
  roots : Array Name
  /-- Complete selected-library inventory, not just this module's import closure. -/
  libraryModules : Array Name
  modules : Array (Name × ProjectKey)
  closure : Array (Name × ProjectKey)
  /-- Page-mode build paths for selected-library modules in the compiled closure. -/
  libraryOleas : Array (Name × FilePath)
  deriving Inhabited

def ProjectRegistry.projectFor? (registry : ProjectRegistry) (moduleName : Name) : Option ProjectKey :=
  (registry.closure.find? (·.1 == moduleName)).map (·.2)

/-- Resolve a declaration by its defining module, never by the location of theorem_info. -/
def ProjectRegistry.declarationProject? (registry : ProjectRegistry) (env : Environment)
    (declaration : Name) : Option ProjectKey := do
  let idx ← env.getModuleIdxFor? declaration
  let moduleName ← env.header.moduleNames[idx]?
  registry.projectFor? moduleName

def ProjectKey.projectId (project : ProjectKey) : String :=
  (toJson project).compress

/-- Read the one project declaration in the imported library view. -/
def ProjectRegistry.metadata (registry : ProjectRegistry) (env : Environment) :
    Except Diagnostic ProjectInfo := do
  let mut events := #[]
  for owner in registry.libraryModules do
    events := events ++ (moduleEvents env owner).filter (·.identity.kind == projectSpec.kind)
  let declarations := events.filter (!·.reset)
  if declarations.size > 1 then
    let error : Diagnostic := {
      message := s!"project_info may only appear once in {registry.selected.library}" }
    throw error
  let some declaration := declarations[0]? | return { title := registry.selected.library }
  let schema : InfoSchema ProjectInfo := inferInstance
  let mut json := json% {}
  let updates := (events.filter (·.owner == declaration.owner)).qsort (·.sequence < ·.sequence)
  for event in updates do
    if event.reset then json := json% {}
    json ← applyPatch schema json event.assignments
  schema.decode json

private def field [FromJson α] (value : Json) (key : String) : IO α :=
  match value.getObjValAs? α key with
  | .ok result => pure result
  | .error message => throw <| IO.userError s!"invalid ProofScript registry field {key}: {message}"

def ProjectRegistry.fromSession (value : Json) (owners : Array Name) : IO ProjectRegistry := do
  let parseEnv ← mkEmptyEnvironment
  let selected : ProjectKey ← field value "selectedProject"
  let projects : Array ProjectKey ← field value "projects"
  unless !selected.package.isEmpty && !selected.library.isEmpty && projects.contains selected do
    throw <| IO.userError "selected ProofScript project is missing from the package inventory"
  let mut seen : Array ProjectKey := #[]
  for project in projects do
    unless project.package == selected.package && !project.library.isEmpty && !seen.contains project do
      throw <| IO.userError "invalid or duplicate ProofScript library in package inventory"
    seen := seen.push project
  let rootNames : Array String ← field value "projectRoots"
  let mut roots := #[]
  for text in rootNames do
    let root ← match printedName parseEnv text with
      | .ok root => pure root
      | .error message => throw <| IO.userError s!"invalid ProofScript library root {text}: {message}"
    if roots.contains root then throw <| IO.userError s!"duplicate ProofScript library root {text}"
    roots := roots.push root
  let libraryNames : Array String ← field value "libraryModules"
  let mut libraryModules := #[]
  for text in libraryNames do
    let moduleName ← match printedName parseEnv text with
      | .ok name => pure name
      | .error message => throw <| IO.userError s!"invalid ProofScript library module {text}: {message}"
    if libraryModules.contains moduleName then throw <| IO.userError s!"duplicate ProofScript library module {text}"
    libraryModules := libraryModules.push moduleName
  let assignments : Array Json ← field value "moduleProjects"
  let mut modules := #[]
  for assignment in assignments do
    let moduleText : String ← field assignment "module"
    let project : ProjectKey ← match fromJson? assignment with
      | .ok project => pure project
      | .error message => throw <| IO.userError s!"invalid ProofScript module assignment: {message}"
    let some module := owners.find? (·.toString == moduleText) | throw <| IO.userError s!"unknown ProofScript module {moduleText}"
    unless project == selected && !modules.any (·.1 == module) do
      throw <| IO.userError s!"duplicate or mismatched ProofScript module assignment {moduleText}"
    modules := modules.push (module, project)
  unless modules.size == owners.size do
    throw <| IO.userError "ProofScript project assignments omit exported modules"
  let closureEntries : Array Json ← field value "closureProjects"
  let mut closure := #[]
  for assignment in closureEntries do
    let moduleText : String ← field assignment "module"
    let module ← match printedName parseEnv moduleText with
      | .ok module => pure module
      | .error message => throw <| IO.userError s!"invalid ProofScript closure module {moduleText}: {message}"
    let project : ProjectKey ← match fromJson? assignment with
      | .ok project => pure project
      | .error message => throw <| IO.userError s!"invalid ProofScript closure assignment: {message}"
    unless !moduleText.isEmpty && !project.package.isEmpty && !project.library.isEmpty &&
        !closure.any (·.1 == module) do
      throw <| IO.userError s!"invalid or duplicate ProofScript closure module {moduleText}"
    closure := closure.push (module, project)
  for (owner, project) in modules do
    unless closure.any (fun entry => entry.1 == owner && entry.2 == project) do
      throw <| IO.userError s!"ProofScript closure omits selected module {owner}"
  for root in roots do
    if let some (_, project) := closure.find? (·.1 == root) then
      unless project == selected do
        throw <| IO.userError s!"ProofScript library root {root} belongs to another project"
  unless owners.all libraryModules.contains do
    throw <| IO.userError "selected ProofScript modules are missing from their library inventory"
  let buildEntries : Array Json ← field value "modules"
  let mut libraryOleas := #[]
  for entry in buildEntries do
    let name : String ← field entry "name"
    if let some moduleName := libraryModules.find? (·.toString == name) then
      let pkg : String ← field entry "package"
      let olean : String ← field entry "olean"
      unless pkg == selected.package && !olean.isEmpty &&
          !libraryOleas.any (·.1 == moduleName) do
        throw <| IO.userError s!"invalid ProofScript olean for {name}"
      libraryOleas := libraryOleas.push (moduleName, FilePath.mk olean)
  for owner in owners do
    unless libraryOleas.any (·.1 == owner) do
      throw <| IO.userError s!"ProofScript build manifest omits selected module {owner}"
  return { selected, projects, roots, libraryModules, modules, closure, libraryOleas }

end ProofScript
