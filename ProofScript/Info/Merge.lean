import ProofScript.Info.TypedElab

namespace ProofScript

open Lean

private def queryTypedInfoChanges (env : Environment) (moduleName : Name) :
    Except String (Array (Name × TypedInfoChange)) := do
  let order ← (ModuleGraph.ofEnvironment env).modulesInDependencyOrder moduleName
  return order.flatMap fun owner => (moduleExtensionEntries typedInfoChangeExt env owner).map (owner, ·)

/-- A tombstone is an absent typed value; for a JSON field, JSON null remains a value. -/
private structure InfoCandidate (α : Type) where
  value : Option α
  module : Name

/-- Undominated writes for one field; defaults are supplied only when reading. -/
private abbrev InfoSlot (α : Type) := Array (InfoCandidate α)

private def InfoSlot.add (slot : InfoSlot α) (graph : ModuleGraph)
    (candidate : InfoCandidate α) : InfoSlot α :=
  if slot.any (fun old =>
       old.module != candidate.module && graph.dependsOn old.module candidate.module) then slot
  else (slot.filter fun old =>
    old.module != candidate.module && !graph.dependsOn candidate.module old.module).push candidate

private def InfoSlot.conflict? (slot : InfoSlot α) (label : String) : Option String := do
  if slot.size <= 1 then none else
    let origins := slot.map fun candidate => candidate.module.toString
    some (infoFieldError label ("conflicting independent writes: " ++
      String.intercalate ", " origins.toList))

/-- Callers supply defaults only at consumption; independent conflicts are never defaulted. -/
private def InfoSlot.value (slot : InfoSlot α) (label : String) (fallback : Option α) :
    Except String (Option α) :=
  match slot.conflict? label with
  | some error => .error error
  | none => .ok <| match slot[0]? with
    | some candidate => candidate.value.or fallback
    | none => fallback

/-- Extension keys remain independent, including keys written before a later reset. -/
private structure ExtraView where
  keys : Array (String × InfoSlot Json) := #[]

private def ExtraView.include (view : ExtraView) (key : String) : ExtraView :=
  if view.keys.any (·.1 == key) then view
  else { keys := view.keys.push (key, #[]) }

private def ExtraView.write (view : ExtraView) (graph : ModuleGraph) (module : Name)
    (key : String) (value : Json) : ExtraView := Id.run do
  let view := view.include key
  return { keys := view.keys.map fun (name, slot) =>
    if name == key then (name, slot.add graph { value := some value, module }) else (name, slot) }

private def ExtraView.reset (view : ExtraView) (graph : ModuleGraph) (module : Name) : ExtraView :=
  { keys := view.keys.map fun (name, slot) =>
    (name, slot.add graph { value := none, module }) }

private def ExtraView.conflicts (view : ExtraView) : Array String :=
  view.keys.filterMap fun (key, slot) => slot.conflict? s!"extra.{key}"

private def ExtraView.read (view : ExtraView) : Except String ExtraFields := do
  let mut values : Std.TreeMap String Json := {}
  for (key, slot) in view.keys do
    if let some value ← slot.value s!"extra.{key}" none then
      values := values.insert key value
  return { values }

/-- The common merge kernel has no knowledge of field names or defaults. -/
private def writeField (slot : InfoSlot α) (graph : ModuleGraph)
    (module : Name) (value : α) : InfoSlot α :=
  slot.add graph { value := some value, module }

private def clearField (slot : InfoSlot α) (graph : ModuleGraph)
    (module : Name) : InfoSlot α :=
  slot.add graph { value := none, module }

private def readField (slot : InfoSlot α) (name : String) (fallback : α) : Except String α := do
  let some value ← slot.value name (some fallback)
  | throw <| infoFieldError name "required field is missing"
  return value

private def attachField (kind : String) (target : Name) (result : Except String α) :
    Except String α :=
  result.mapError (infoTargetError kind target.toString)

/-- Intermediate merge state: each declaration field retains its own typed candidates. -/
private structure DeclMergeState where
  target : Name
  names : InfoSlot (List InternationalName) := #[]
  tags : InfoSlot (List InternationalName) := #[]
  varName : InfoSlot String := #[]
  kind : InfoSlot DeclKind := #[]
  wrapperIndex : InfoSlot (Option Nat) := #[]
  aliasTarget : InfoSlot (Option DeclarationRef) := #[]
  templates : InfoSlot (Array DefinitionTemplate) := #[]
  defaultTemplate : InfoSlot (Option String) := #[]
  calcSymbol : InfoSlot (Option String) := #[]
  parameterTemplate : InfoSlot (Option String) := #[]
  extra : ExtraView := {}

private def DeclMergeState.reset (state : DeclMergeState) (graph : ModuleGraph)
    (module : Name) : DeclMergeState :=
  { state with
    names := clearField state.names graph module
    tags := clearField state.tags graph module
    varName := clearField state.varName graph module
    kind := clearField state.kind graph module
    wrapperIndex := clearField state.wrapperIndex graph module
    aliasTarget := clearField state.aliasTarget graph module
    templates := clearField state.templates graph module
    defaultTemplate := clearField state.defaultTemplate graph module
    calcSymbol := clearField state.calcSymbol graph module
    parameterTemplate := clearField state.parameterTemplate graph module
    extra := state.extra.reset graph module }

private def DeclMergeState.apply (state : DeclMergeState) (graph : ModuleGraph)
    (module : Name) : DeclEdit → DeclMergeState
| ⟨.names, value⟩ => { state with names := writeField state.names graph module value }
| ⟨.tags, value⟩ => { state with tags := writeField state.tags graph module value }
| ⟨.varName, value⟩ => { state with varName := writeField state.varName graph module value }
| ⟨.kind, value⟩ => { state with kind := writeField state.kind graph module value }
| ⟨.wrapperIndex, value⟩ => { state with wrapperIndex := writeField state.wrapperIndex graph module value.value }
| ⟨.aliasTarget, value⟩ => { state with aliasTarget := writeField state.aliasTarget graph module value.value }
| ⟨.templates, value⟩ => { state with templates := writeField state.templates graph module value }
| ⟨.defaultTemplate, value⟩ => { state with defaultTemplate := writeField state.defaultTemplate graph module value.value }
| ⟨.calcSymbol, value⟩ => { state with calcSymbol := writeField state.calcSymbol graph module value.value }
| ⟨.parameterTemplate, value⟩ => { state with parameterTemplate := writeField state.parameterTemplate graph module value.value }
| ⟨.extra key, value⟩ => { state with extra := state.extra.write graph module key value }

/-- Template list commands consume this slot without resolving unrelated conflicts. -/
def DeclMergeState.readTemplates (state : DeclMergeState) : Except String (Array DefinitionTemplate) :=
  attachField "decl" state.target <| readField state.templates "templates" #[]

def DeclMergeState.readNames (state : DeclMergeState) : Except String (List InternationalName) :=
  attachField "decl" state.target <| readField state.names "names" []

def DeclMergeState.readTags (state : DeclMergeState) : Except String (List InternationalName) :=
  attachField "decl" state.target <| readField state.tags "tags" []

private def DeclMergeState.conflicts (state : DeclMergeState) : Array String :=
  let builtin := #[state.names.conflict? "names", state.tags.conflict? "tags",
    state.varName.conflict? "var_name", state.kind.conflict? "kind",
    state.wrapperIndex.conflict? "wrapper_index", state.aliasTarget.conflict? "alias_target",
    state.templates.conflict? "templates", state.defaultTemplate.conflict? "default_template",
    state.calcSymbol.conflict? "calc_symbol", state.parameterTemplate.conflict? "parameter_template"]
  (builtin.filterMap id ++ state.extra.conflicts).map (infoTargetError "decl" state.target.toString)

def DeclMergeState.materialize (state : DeclMergeState) : Except String DeclInfo := do
  if let some conflict := state.conflicts[0]? then throw conflict
  attachField "decl" state.target do
    let value : DeclInfo := {
      names := ← readField state.names "names" []
      tags := ← readField state.tags "tags" []
      var_name := ← readField state.varName "var_name" ""
      kind := ← readField state.kind "kind" .concept
      wrapper_index := ← readField state.wrapperIndex "wrapper_index" none
      alias_target := ← readField state.aliasTarget "alias_target" none
      templates := ← readField state.templates "templates" #[]
      default_template := ← readField state.defaultTemplate "default_template" none
      calc_symbol := ← readField state.calcSymbol "calc_symbol" none
      parameter_template := ← readField state.parameterTemplate "parameter_template" none
      extra := ← state.extra.read }
    return value

/-- Intermediate merge state for script configuration. -/
private structure ScriptMergeState where
  target : Name
  created : Bool := false
  renderer : InfoSlot ScriptRenderer := #[]
  templates : InfoSlot (Array ScriptTemplate) := #[]
  display : InfoSlot Bool := #[]
  color : InfoSlot ScriptColor := #[]
  board : InfoSlot ScriptBoardInput := #[]
  extra : ExtraView := {}

private def ScriptMergeState.reset (state : ScriptMergeState) (graph : ModuleGraph)
    (module : Name) : ScriptMergeState :=
  { state with
    renderer := clearField state.renderer graph module
    templates := clearField state.templates graph module
    display := clearField state.display graph module
    color := clearField state.color graph module
    board := clearField state.board graph module
    extra := state.extra.reset graph module }

private def ScriptMergeState.apply (state : ScriptMergeState) (graph : ModuleGraph)
    (module : Name) : ScriptEdit → ScriptMergeState
| ⟨.renderer, value⟩ => { state with renderer := writeField state.renderer graph module value }
| ⟨.templates, value⟩ => { state with templates := writeField state.templates graph module value }
| ⟨.display, value⟩ => { state with display := writeField state.display graph module value }
| ⟨.color, value⟩ => { state with color := writeField state.color graph module value }
| ⟨.board, value⟩ => { state with board := writeField state.board graph module value }
| ⟨.extra key, value⟩ => { state with extra := state.extra.write graph module key value }

def ScriptMergeState.readTemplates (state : ScriptMergeState) : Except String (Array ScriptTemplate) :=
  attachField "script" state.target <| readField state.templates "templates" #[]

def ScriptMergeState.readBoard (state : ScriptMergeState) : Except String ScriptBoardInput :=
  attachField "script" state.target <| readField state.board "board" {}

def ScriptMergeState.isConfigured (state : ScriptMergeState) : Bool := state.created

private def ScriptMergeState.conflicts (state : ScriptMergeState) : Array String :=
  let builtin := #[state.renderer.conflict? "renderer", state.templates.conflict? "templates",
    state.display.conflict? "display", state.color.conflict? "color",
    state.board.conflict? "board"]
  (builtin.filterMap id ++ state.extra.conflicts).map (infoTargetError "script" state.target.toString)

def ScriptMergeState.materialize (state : ScriptMergeState) : Except String ScriptInfo := do
  if let some conflict := state.conflicts[0]? then throw conflict
  attachField "script" state.target do
    return {
      renderer := ← readField state.renderer "renderer" .default
      templates := ← readField state.templates "templates" #[]
      display := ← readField state.display "display" true
      color := ← readField state.color "color" {}
      board := ← readField state.board "board" {}
      extra := ← state.extra.read
    }

/-- Process each module's transactions in its original array order. -/
private def selectTypedChanges (graph : ModuleGraph) (changes : Array (Name × TypedInfoChange))
    (moduleName : Name) : Except String (Array (Name × TypedInfoChange)) := do
  let order ← graph.modulesInDependencyOrder moduleName
  let mut selected : Array (Name × TypedInfoChange) := #[]
  for module in order do
    for (owner, change) in changes do
      if owner == module then
        selected := selected.push (owner, change)
  return selected

/-- Register extension keys before resets, including keys from independent branches. -/
private inductive MergeChange (Field : Type) [InputField Field] where
  | edits (values : Array ((field : Field) × InputField.Value field))
  | reset

private def applyTypedEdits {Field State : Type} [InputField Field]
    (graph : ModuleGraph) (state : State)
    (changes : Array (Name × MergeChange Field))
    (includeExtra : State → String → State)
    (reset : State → ModuleGraph → Name → State)
    (apply : State → ModuleGraph → Name → ((field : Field) × InputField.Value field) → State) : State := Id.run do
  let mut state := state
  for (_, change) in changes do
    if let .edits edits := change then
      for edit in edits do
        if let some key := InputField.extensionKey edit.1 then
          state := includeExtra state key
  for (owner, change) in changes do
    match change with
    | .reset => state := reset state graph owner
    | .edits edits =>
      for edit in edits do state := apply state graph owner edit
  return state

/-- Select one target; register every extension key before applying resets so
    a reset from an independent branch still conflicts with its write. -/
def resolveTypedDecl (env : Environment) (moduleName target : Name) : Except String DeclMergeState := do
  let graph := ModuleGraph.ofEnvironment env
  let selected ← selectTypedChanges graph (← queryTypedInfoChanges env moduleName) moduleName
  let relevant : Array (Name × MergeChange DeclField) := selected.filterMap fun (owner, change) =>
    match change with
    | .decl name edits => if name == target then some (owner, .edits edits) else none
    | .resetDecl name => if name == target then some (owner, .reset) else none
    | .script .. | .resetScript .. => none
  return applyTypedEdits graph { target } relevant
    (fun state key => { state with extra := state.extra.include key })
    DeclMergeState.reset DeclMergeState.apply

def resolveTypedScript (env : Environment) (moduleName target : Name) : Except String ScriptMergeState := do
  let graph := ModuleGraph.ofEnvironment env
  let selected ← selectTypedChanges graph (← queryTypedInfoChanges env moduleName) moduleName
  let relevant : Array (Name × MergeChange ScriptField) := selected.filterMap fun (owner, change) =>
    match change with
    | .script name edits => if name == target then some (owner, .edits edits) else none
    | .resetScript name => if name == target then some (owner, .reset) else none
    | .decl .. | .resetDecl .. => none
  return applyTypedEdits graph { target, created := !relevant.isEmpty } relevant
    (fun state key => { state with extra := state.extra.include key })
    ScriptMergeState.reset ScriptMergeState.apply

end ProofScript
