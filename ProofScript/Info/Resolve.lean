import ProofScript.Info.State

namespace ProofScript

open Lean

structure Origin where
  owner : Name
  sequence : Nat
  source : SourceLocation
  deriving Inhabited, Repr, BEq

def Origin.related (origin : Origin) : RelatedSource :=
  { owner := origin.owner, sequence := origin.sequence, source := origin.source }

inductive UnitKey where
  | field (name : String)
  | presence (name : String)
  | keyed (field key : String)
  | extra (key : String)
  | binding (key : String)
  deriving Inhabited, Repr, BEq

def UnitKey.path : UnitKey → JsonPath
  | .field name | .presence name => #[.key name]
  | .keyed name key => #[.key name, .key key]
  | .extra key => #[.key "extra", .key key]
  | .binding key => #[.key "context", .key key]

structure Candidate where
  /-- none is a tombstone/missing value; JSON null remains an ordinary value. -/
  value : Option Json
  origin : Origin
  deriving Inhabited

/-- Equal values deliberately retain every independent origin. -/
structure UnitState where
  key : UnitKey
  fallback : Option Json := none
  candidates : Array Candidate := #[]
  deriving Inhabited

private def dominates (graph : ModuleGraph) (later earlier : Origin) : Bool :=
  if later.owner == earlier.owner then
    later.sequence > earlier.sequence
  else graph.dependsOn later.owner earlier.owner

def UnitState.add (state : UnitState) (graph : ModuleGraph) (candidate : Candidate) : UnitState :=
  if state.candidates.any (fun old => dominates graph old.origin candidate.origin) then state
  else { state with candidates := (state.candidates.filter fun old =>
    old.origin != candidate.origin && !dominates graph candidate.origin old.origin).push candidate }

private def UnitState.hasValue (state : UnitState) : Bool :=
  if state.candidates.isEmpty then state.fallback.isSome else state.candidates.any (·.value.isSome)

def UnitState.conflict? (state : UnitState) : Option Diagnostic := do
  let first ← state.candidates[0]?
  if state.candidates.all (·.value == first.value) then none else
    some {
      message := "conflicting independent writes"
      path := state.key.path
      related := state.candidates.map (·.origin.related) }

def UnitState.value (state : UnitState) : Except Diagnostic (Option Json) :=
  match state.conflict? with
  | some error => .error error
  | none => .ok <| match state.candidates[0]? with
    | some candidate => candidate.value
    | none => state.fallback

structure PartialView where
  identity : InfoTarget
  created : Bool
  units : Array UnitState
  keyOrder : Array (String × Array String) := #[]
  deriving Inhabited

def PartialView.conflicts (view : PartialView) : Array Diagnostic :=
  view.units.filterMap fun unit => unit.conflict?.map fun error =>
    { error with kind := some view.identity.kind, target := some (toString view.identity.target) }

def PartialView.provenance (view : PartialView) : Array (UnitKey × Array Origin) :=
  view.units.map fun unit => (unit.key, unit.candidates.map (·.origin))

private def PartialView.unit (view : PartialView) (key : UnitKey) : UnitState :=
  (view.units.find? (·.key == key)).getD { key }

/-- Select the requested module's complete import closure and order its updates. -/
def selectEvents (graph : ModuleGraph) (events : Array InfoEvent) (query : Query) :
    Except Diagnostic (Array InfoEvent) := do
  let order ← (graph.order query.moduleName).mapError fun message => { message }
  let mut selected : Array InfoEvent := #[]
  for owner in order do
    let localEvents := (events.filter (·.owner == owner)).qsort (fun a b => a.sequence < b.sequence)
    for event in localEvents do
      if let some old := selected.find? (fun old => old.owner == event.owner && old.sequence == event.sequence) then
        unless toJson old == toJson event do
          throw ({
            message := s!"inconsistent event identity `{owner} #{event.sequence}`"
            source := some event.source } : Diagnostic)
      else selected := selected.push event
  return selected

private def writes (events : Array InfoEvent) : Array (Assignment × Origin) :=
  events.flatMap fun event =>
    event.assignments.map fun assignment =>
      (assignment, { owner := event.owner, sequence := event.sequence, source := assignment.source })

private def keyedValues (field : FieldSpec Record) (value : Json) :
    Except Diagnostic (Array (String × Json)) := do
  let decoded ← field.decode value
  match field.handle.merge with
  | .keyed split _ => split decoded
  | .replace => throw { message := "expected a keyed field" }

private def resolveKeyed (graph : ModuleGraph) (field : FieldSpec Record)
    (assignments : Array (Assignment × Origin)) : Except Diagnostic (Array UnitState × Array String) := do
  let defaults ← field.defaultJson.mapM (keyedValues field)
  let defaults := defaults.getD #[]
  -- The universe includes later and independent keys. A reset writes a tombstone to every key,
  -- including keys not present in its default value or in its own import branch.
  let mut keys := defaults.map (·.1)
  for (assignment, _) in assignments do
    if let .set value := assignment.operation then
      for (key, _) in ← keyedValues field value do
        if !keys.contains key then keys := keys.push key
  let mut units : Array UnitState := keys.map fun key =>
    { key := .keyed field.name key, fallback := (defaults.find? (·.1 == key)).map (·.2) }
  let mut presence : UnitState := {
    key := .presence field.name, fallback := field.defaultJson.map fun _ => json% true }
  let mut order := defaults.map (·.1)
  for (assignment, origin) in assignments do
    match assignment.operation with
    | .set value =>
      presence := presence.add graph { value := some (json% true), origin }
      for (key, value) in ← keyedValues field value do
        let some index := keys.findIdx? (· == key) | unreachable!
        units := units.set! index (units[index]!.add graph { value := some value, origin })
        if !order.contains key && units[index]!.hasValue then order := order.push key
    | .reset =>
      -- Discard ancestor positions too: after reset, reintroduced keys append in fresh input order.
      order := order.filter fun key =>
        let unit := units[(keys.findIdx? (· == key)).getD 0]!
        unit.candidates.any fun candidate =>
          candidate.value.isSome && !dominates graph origin candidate.origin
      presence := presence.add graph { value := field.defaultJson.map fun _ => json% true, origin }
      units := units.map fun unit =>
        let value := match unit.key with
          | .keyed _ key => (defaults.find? (·.1 == key)).map (·.2)
          | _ => none
        unit.add graph { value, origin }
      for (key, _) in defaults do
        if !order.contains key then order := order.push key
  return (#[presence] ++ units, order)

/-- Resolve candidates without rejecting incomplete records or unresolved independent writes. -/
def resolveEvents [InfoSchema Record] (spec : InfoSpec Record) (graph : ModuleGraph)
    (events : Array InfoEvent) (query : Query) (target : Name ⊕ String) : Except Diagnostic PartialView := do
  let schema : InfoSchema Record := inferInstance
  schema.validateDefinition
  let selected ← selectEvents graph events query
  let identity : InfoTarget := { kind := spec.kind, target }
  let selected := selected.filter (·.identity == identity)
  for event in selected do
    if event.schemaId != schema.id || event.schemaVersion != schema.version then
      throw ({
        message := s!"unsupported schema `{event.schemaId}@{event.schemaVersion}`; expected `{schema.id}@{schema.version}`"
        kind := some spec.kind, target := some (toString target), source := some event.source } : Diagnostic)
    discard <| validatePatch schema event.assignments
  let allWrites := writes selected
  let mut units := #[]
  let mut keyOrder := #[]
  for field in schema.fields do
    if field.handle.isExtra then
      let defaults ← match field.defaultJson with
        | some value => value.getObj?.mapError fun message => { message }
        | none => pure {}
      let mut extra := defaults.toList.toArray.map fun (key, value) =>
        ({ key := .extra key, fallback := some value } : UnitState)
      for (assignment, origin) in allWrites do
        if let .extra key := assignment.key then
          let index := extra.findIdx? (·.key == .extra key)
          let unit := index.map (extra[·]!) |>.getD { key := .extra key }
          let value := match assignment.operation with | .set value => some value | .reset => none
          let unit := unit.add graph { value, origin }
          extra := match index with | some index => extra.set! index unit | none => extra.push unit
      units := units ++ extra
    else
      let assignments := allWrites.filter (fun (assignment, _) => assignment.key == .builtin field.name)
      match field.handle.merge with
      | .replace =>
        let mut unit : UnitState := { key := .field field.name, fallback := field.defaultJson }
        for (assignment, origin) in assignments do
          let value := match assignment.operation with
            | .set value => some value
            | .reset => field.defaultJson
          unit := unit.add graph { value, origin }
        units := units.push unit
      | .keyed .. =>
        let (fieldUnits, order) ← resolveKeyed graph field assignments
        units := units ++ fieldUnits
        keyOrder := keyOrder.push (field.name, order)
  return { identity, created := !selected.isEmpty, units, keyOrder }

def resolvePartial [InfoSchema Record] (spec : InfoSpec Record) (env : Environment) (query : Query) (target : Name ⊕ String) :
    Except Diagnostic PartialView := do
  resolveEvents spec (ModuleGraph.ofEnvironment env) (← queryEvents env query) query target

/-- Domain checks performed after materialization retain the same field provenance. -/
def PartialView.attach (view : PartialView) (error : Diagnostic) : Diagnostic := Id.run do
  let paths := if error.relatedPaths.isEmpty && error.related.isEmpty then #[]
    else error.relatedPaths.push error.path
  let relevant := view.units.filter fun unit => paths.isEmpty || paths.any fun path =>
    path.isPrefixOf unit.key.path || unit.key.path.isPrefixOf path
  let mut related := error.related
  for unit in relevant do
    for candidate in unit.candidates do
      let source := candidate.origin.related
      if !related.contains source then related := related.push source
  return { error with kind := some view.identity.kind, target := some (toString view.identity.target), related }

/-- Materialization is the consumption boundary: conflicts and combined-value checks happen here. -/
def PartialView.materialize (view : PartialView) (schema : InfoSchema Record) : Except Diagnostic Json :=
  (do
    if let some error := view.conflicts[0]? then throw error
    let mut values : List (String × Json) := []
    for field in schema.fields do
      if field.handle.isExtra then
        let mut extra : List (String × Json) := []
        for unit in view.units do
          if let .extra key := unit.key then
            if let some value ← unit.value then extra := extra ++ [(key, value)]
        if field.defaultJson.isSome || view.units.any (fun unit => match unit.key with
            | .extra _ => !unit.candidates.isEmpty | _ => false) then
          values := values ++ [(field.name, Json.mkObj extra)]
      else match field.handle.merge with
      | .replace =>
        if let some value ← (view.unit (.field field.name)).value then
          values := values ++ [(field.name, value)]
      | .keyed _ join =>
        let _ : ToJson field.Value := field.codec.toToJson
        if (← (view.unit (.presence field.name)).value).isSome then
          let order := (view.keyOrder.find? (·.1 == field.name)).map (·.2) |>.getD #[]
          let mut entries := #[]
          for key in order do
            if let some value ← (view.unit (.keyed field.name key)).value then entries := entries.push (key, value)
          let value ← join entries
          values := values ++ [(field.name, toJson value)]
    return Json.mkObj values : Except Diagnostic Json).mapError view.attach

structure ResolvedInfo (Record : Type) where
  value : Record
  provenance : Array (UnitKey × Array Origin)
  dependencies : Array (String × (Name ⊕ String))

def consumeView [InfoSchema Record] (spec : InfoSpec Record) (view : PartialView) : Except Diagnostic (ResolvedInfo Record) := do
  let schema : InfoSchema Record := inferInstance
  let json ← view.materialize schema
  let value ← (schema.decode json).mapError view.attach
  return { value, provenance := view.provenance, dependencies := spec.dependencies value }

def resolveInfo [InfoSchema Record] (spec : InfoSpec Record) (env : Environment) (query : Query) (target : Name ⊕ String) :
    Except Diagnostic (ResolvedInfo Record) := do
  consumeView spec (← resolvePartial spec env query target)

/-- Context ambiguity is checked when a caller actually asks for that binding. -/
def resolveContextEvents (graph : ModuleGraph) (events : Array InfoEvent)
    (query : Query) (key : String) : Except Diagnostic UnitState := do
  let mut state : UnitState := { key := .binding key }
  for event in ← selectEvents graph events query do
    for binding in event.bindings do
      if binding.key == key then
        state := state.add graph { value := some binding.value, origin := {
          owner := event.owner, sequence := event.sequence, source := binding.source } }
  return state

def resolveContext (env : Environment) (query : Query) (key : String) : Except Diagnostic UnitState := do
  resolveContextEvents (ModuleGraph.ofEnvironment env) (← queryEvents env query) query key

end ProofScript
