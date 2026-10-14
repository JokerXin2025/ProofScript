import Lean
import ProofScript.Page.Path
import ProofScript.Script.Recording.Shape

namespace ProofScript

open Lean

/-- A registration is owned by precisely one module and is never identified by its display name. -/
structure RenderRegistration where
  id : Name
  owner : Name
  tactic : String
  strategy : Bool
  /-- Structural input shapes; unsupported compound parsers have no automatic shape. -/
  parameters : Array (String × Option Recording.ParamShape)
  recordedFields : Option (Array Recording.OutputField) := none
  deriving Inhabited

/-- Only fields explicitly assigned by one command are persisted in this event. -/
structure RenderUpdate where
  owner : Name
  sequence : Nat
  ruleId : Name
  fields : Json
  deriving Inhabited

initialize renderRegistrationExt : SimplePersistentEnvExtension RenderRegistration (Array RenderRegistration) ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.renderRegistrations
    addEntryFn := fun state entry => (state.filter (·.id != entry.id)).push entry
    addImportedFn := fun entries => entries.foldl (fun state entries =>
      entries.foldl (fun state entry => (state.filter (·.id != entry.id)).push entry) state) #[]
  }

initialize renderUpdateExt : SimplePersistentEnvExtension RenderUpdate (Array RenderUpdate) ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.renderUpdates
    addEntryFn := fun state entry => state.push entry
    addImportedFn := fun entries => entries.foldl (· ++ ·) #[]
  }

def localRenderUpdates (env : Environment) : Array RenderUpdate :=
  (renderUpdateExt.getEntries env).reverse.toArray

def importedRenderEvents (env : Environment) : Array (Name × Array RenderUpdate) := Id.run do
  let mut output := #[]
  for i in [:env.header.moduleNames.size] do
    let owner := env.header.moduleNames[i]!
    let events := renderUpdateExt.getModuleEntries env i
    if !events.isEmpty then output := output.push (owner, events)
  return output

def incomingRenderUpdates (env : Environment) : Array RenderUpdate :=
  (importedRenderEvents env).foldl (fun acc (_, entries) => acc ++ entries) #[]

/-- Postorder traversal of the actual import graph. A descendant can explicitly
    override its ancestor; unrelated imports assigning the same field conflict. -/
def renderImportOrder (env : Environment) : Array Name := Id.run do
  let mut ordered := #[]
  let mut pending := env.header.imports.toList.map fun imp => (imp.module, false)
  while !pending.isEmpty do
    let (moduleName, visited) := pending.head!
    pending := pending.tail!
    if ordered.contains moduleName then continue
    if visited then
      ordered := ordered.push moduleName
    else if let some idx := env.getModuleIdx? moduleName then
      pending := (env.header.moduleData[idx]!.imports.toList.map fun imp =>
        (imp.module, false)) ++ ((moduleName, true) :: pending)
  return ordered

def moduleImportsModule (env : Environment) (moduleName ancestor : Name) : Bool := Id.run do
  let mut pending := [moduleName]
  let mut visited := #[]
  while !pending.isEmpty do
    let current := pending.head!
    pending := pending.tail!
    if current == ancestor then return true
    if visited.contains current then continue
    visited := visited.push current
    if let some idx := env.getModuleIdx? current then
      pending := (env.header.moduleData[idx]!.imports.toList.map (·.module)) ++ pending
  return false

/-- A template is an ordered list. Replacing a language keeps its first position;
    newly introduced languages are appended in declaration order. -/
def mergeRenderTemplate (previous update : Json) : Except String Json := do
  let .ok old := previous.getArr? | throw "template must be an array"
  let .ok fresh := update.getArr? | throw "template must be an array"
  let mut result := old
  for item in fresh do
    let language ← item.getObjValAs? String "lang"
    if language.isEmpty then throw "template language must not be empty"
    if let some index := result.toList.findIdx? (fun entry =>
        (entry.getObjValAs? String "lang").toOption == some language) then
      result := result.set! index item
    else
      result := result.push item
  return Json.arr result

def effectiveIncomingRenderFields (env : Environment) : Except String (Array (Name × Json)) := do
  let mut values : Array (Name × Json) := #[]
  let mut owners : Array (Name × String × Name) := #[]
  for moduleName in renderImportOrder env do
    let some idx := env.getModuleIdx? moduleName | continue
    for event in renderUpdateExt.getModuleEntries env idx do
      let .ok fields := event.fields.getObj? | throw "script_info fields must be an object"
      let mut merged := (values.find? (·.1 == event.ruleId)).map (·.2) |>.getD (Json.mkObj [])
      for (key, value) in fields.toList do
        let keys ← if key == "template" then do
          let .ok entries := value.getArr? | throw "template must be an array"
          entries.mapM fun entry => do
            let language ← entry.getObjValAs? String "lang"
            return s!"template.{language}"
        else pure #[key]
        for conflictKey in keys do
          let mut obsolete := #[]
          for (ruleId, field, previous) in owners do
            if ruleId == event.ruleId && field == conflictKey && previous != event.owner &&
                !moduleImportsModule env event.owner previous &&
                !moduleImportsModule env previous event.owner then
              throw s!"conflicting script_info `{event.ruleId}.{conflictKey}` in independent imports `{previous}` and `{event.owner}`"
            if ruleId == event.ruleId && field == conflictKey && previous != event.owner &&
                moduleImportsModule env event.owner previous then
              obsolete := obsolete.push previous
          owners := owners.filter fun (ruleId, field, owner) =>
            ruleId != event.ruleId || field != conflictKey || !obsolete.contains owner
          owners := owners.push (event.ruleId, conflictKey, event.owner)
        let next ← if key == "template" then
          mergeRenderTemplate ((merged.getObjVal? key).toOption.getD (Json.arr #[])) value
          else pure value
        merged := merged.setObjVal! key next
      values := (values.filter (·.1 != event.ruleId)).push (event.ruleId, merged)
  return values

private def encodeModulePath (owner : Name) : String :=
  String.intercalate "/" (owner.components.map fun part =>
    let text := part.toString
    String.intercalate "" (text.toList.map fun c =>
      if c == '/' || c == '%' || c == '\\' || c == ':' || c == '.' then
        s!"%{c.toNat}X"
      else String.singleton c))

def renderSchemaVersion : String := "0.1.0"

private def recordedFieldsJson (rule : RenderRegistration) : Json :=
  match rule.recordedFields with
  | none => Json.null
  | some fields => Json.arr (fields.map Recording.OutputField.toJson)

/-- Resolve imports at the proof module boundary. Local updates take effect only in importing modules. -/
def effectiveRenderRulesJson (env : Environment) : Except String Json := do
  let fields ← effectiveIncomingRenderFields env
  let mut rules := #[]
  for registration in renderRegistrationExt.getState env do
    if !(fields.any (·.1 == registration.id)) then
      let fallback := if registration.strategy then
        Json.mkObj [("renderer", "strategy")]
      else Json.mkObj [("template", toJson #[Json.mkObj [
        ("lang", "zh"), ("tag", toJson registration.tactic), ("content", "")]])]
      rules := rules.push <| Json.mkObj [
        ("ruleId", toJson registration.id.toString),
        ("strategy", toJson registration.strategy),
        ("recordedFields", recordedFieldsJson registration),
        ("fields", fallback)]
  for (id, config) in fields.qsort (fun a b => a.1.toString < b.1.toString) do
    let some registration := (renderRegistrationExt.getState env).find? (·.id == id)
      | throw s!"missing render registration `{id}`"
    let renderer? := (config.getObjValAs? String "renderer").toOption
    if (config.getObjVal? "renderer").isOk && renderer?.isNone then
      throw s!"script_info `{id}` renderer must be a string"
     for (key, _) in (config.getObj?.toOption.getD {}).toList do
        unless ["renderer", "template", "display", "color"].contains key do
         throw s!"unsupported script_info field `{key}` for `{id}`"
     if renderer?.getD "none" == "none" && !(config.getObjVal? "template").isOk then
       throw s!"automatic script_info `{id}` requires template"
    if let some recorded := registration.recordedFields then
      if let .ok template := config.getObjVal? "template" then
        Recording.validateTemplateFields recorded template
    rules := rules.push <| Json.mkObj [
      ("ruleId", toJson id.toString), ("strategy", toJson registration.strategy),
      ("recordedFields", recordedFieldsJson registration),
      ("fields", config)]
  return Json.mkObj [
    ("schemaVersion", toJson renderSchemaVersion), ("module", toJson env.mainModule.toString),
    ("imports", toJson (env.header.imports.map (·.module.toString))),
    ("rules", Json.arr rules)]

def exportEffectiveRenderRules (env : Environment) : IO (Except String Unit) := do
  let document ← match effectiveRenderRulesJson env with
    | .ok document => pure document
    | .error message => return .error message
  let file ← activeOutputPath <| outputRoot / "rendering" / "effective" /
    s!"{encodeModulePath env.mainModule}.json"
  ensureParentDir file
  IO.FS.writeFile file document.pretty
  return .ok ()

def registerRenderRule (env : Environment) (rule : RenderRegistration) : Environment :=
  renderRegistrationExt.addEntry env rule

def setRenderRecordingFields (env : Environment) (id : Name)
    (fields : Option (Array Recording.OutputField)) : Environment :=
  match (renderRegistrationExt.getState env).find? (·.id == id) with
  | none => env
  | some rule => registerRenderRule env { rule with recordedFields := fields }

def addRenderUpdate (env : Environment) (event : RenderUpdate) : Environment :=
  renderUpdateExt.addEntry env event

def RenderUpdate.toJson (event : RenderUpdate) : Json := Json.mkObj [
  ("sequence", Lean.toJson event.sequence), ("ruleId", Lean.toJson event.ruleId.toString),
  ("fields", event.fields)]

def RenderRegistration.toJson (rule : RenderRegistration) : Json := Json.mkObj [
  ("ruleId", Lean.toJson rule.id.toString), ("owner", Lean.toJson rule.owner.toString),
  ("name", Lean.toJson rule.tactic), ("strategy", Lean.toJson rule.strategy),
  ("recordedFields", recordedFieldsJson rule),
  ("parameters", Lean.toJson (rule.parameters.map fun (name, shape) => Json.mkObj [
    ("name", Lean.toJson name), ("shape", shape.map Recording.ParamShape.toJson |>.getD Json.null)]))]

/-- Export imported .olean events as well as the current module, under each owning module's path. -/
def exportRenderEvents (env : Environment) : IO Unit := do
  let events := (importedRenderEvents env).foldl (fun acc (_, entries) => acc ++ entries)
    (localRenderUpdates env)
  let owners := events.foldl (fun acc event =>
    if acc.contains event.owner then acc else acc.push event.owner) (#[] : Array Name)
  for owner in owners do
    for (strategy, directory) in [(false, "tactics"), (true, "strategys")] do
      let selected := events.filter fun event =>
        event.owner == owner &&
        (renderRegistrationExt.getState env).any (fun rule =>
          rule.id == event.ruleId && rule.strategy == strategy)
      let relative := encodeModulePath owner
      let file ← activeOutputPath <| outputRoot / directory / s!"{relative}.json"
      ensureParentDir file
      IO.FS.writeFile file <| (Json.mkObj [
        ("schemaVersion", toJson renderSchemaVersion), ("module", Lean.toJson owner.toString),
        ("events", Lean.toJson (selected.map RenderUpdate.toJson))]).pretty

  let modules := env.header.moduleNames.push env.mainModule
  for owner in modules do
    let imports := if owner == env.mainModule then env.header.imports
      else (env.getModuleIdx? owner).map (fun idx => env.header.moduleData[idx]!.imports) |>.getD #[]
    let relative := encodeModulePath owner
    let file ← activeOutputPath <| outputRoot / "rendering" / "modules" / s!"{relative}.json"
    ensureParentDir file
    IO.FS.writeFile file <| (Json.mkObj [
      ("schemaVersion", toJson renderSchemaVersion), ("module", Lean.toJson owner.toString),
      ("imports", Lean.toJson (imports.map (·.module.toString))),
      ("registrations", Lean.toJson ((renderRegistrationExt.getState env).filter
        (·.owner == owner) |>.map RenderRegistration.toJson))
    ]).pretty

  -- Even when this module has no surviving updates, export an empty file for
  -- each category so a successful recompile replaces previously cached events.
  let localOwner := env.mainModule
  for (strategy, directory) in [(false, "tactics"), (true, "strategys")] do
    let selected := (localRenderUpdates env).filter fun event =>
      (renderRegistrationExt.getState env).any fun rule =>
        rule.id == event.ruleId && rule.strategy == strategy
    let relative := encodeModulePath localOwner
    let file ← activeOutputPath <| outputRoot / directory / s!"{relative}.json"
    ensureParentDir file
    IO.FS.writeFile file <| (Json.mkObj [
      ("schemaVersion", toJson renderSchemaVersion), ("module", Lean.toJson localOwner.toString),
      ("events", Lean.toJson (selected.map RenderUpdate.toJson))]).pretty

end ProofScript
