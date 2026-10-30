import Lean.Meta
import ProofScript.Output.Dependencies
import ProofScript.Script.Recording.Encoding

open Lean


namespace ProofScript


/-- Private box positions are converted to public structural paths only after assembly. -/
structure BoxContractBinding where
  box : String
  index : Nat
  binding : StepBinding
  deriving Inhabited

/-- Internal, stable positions reserved for one step. Public recorders use RecordingStep. -/
structure RecordingSlot where
  token : Name
  box : String
  recordIndex : Nat
  deriving Inhabited

/-- Internal completion data survives the public step callback. -/
structure PendingRecordingStrategy where
  slot : RecordingSlot
  childPrefix : String
  labels : List Name
  deriving Inhabited

/-! A strategy route retains the actual metavariable selected for each branch.
    Branch labels are export names; they are never used to rediscover a goal. -/
structure RecordingStrategyBranch where
  label : Name
  goal : MVarId

structure RecordingStrategyRoute where
  mainTag : String
  branches : List RecordingStrategyBranch

/-- Mutable data owned by a single proof recording. -/
structure RecordingState where
  statement : Option RecordedValue := none
  boxes : Array (String × Array RecordedValue) := #[]
  boxTags : List String := []
  strategyBranches : List RecordingStrategyRoute := []
  pendingStrategies : List PendingRecordingStrategy := []
  openSteps : List RecordingSlot := []
  selectedContract : Option RecordingContract := none
  contractBindings : Array BoxContractBinding := #[]
  deriving Inhabited

/-- Non-persistent environment state travels through command, tactic and term
    elaboration and follows Lean's ordinary environment backtracking. -/
initialize recordingSessionExt : Lean.EnvExtension (Option RecordingState) ←
  Lean.registerEnvExtension (pure none)

def withRecordingSession {m : Type → Type} [Monad m] [MonadEnv m] [MonadFinally m]
    (action : m α) : m α := do
  let previous := recordingSessionExt.getState (← Lean.getEnv)
  Lean.modifyEnv (recordingSessionExt.setState · (some {}))
  try
    action
  finally
    -- Preserve declarations made by `action`, removing only the transient session.
    Lean.modifyEnv (recordingSessionExt.setState · previous)

private def getRecordingState {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] : m RecordingState := do
  match recordingSessionExt.getState (← Lean.getEnv) with
  | some state => return state
  | none => liftM (throw (IO.userError "ProofScript: no active proof recording") : IO RecordingState)

private def modifyRecordingState {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (f : RecordingState → RecordingState) : m Unit := do
  let state ← getRecordingState
  Lean.modifyEnv (recordingSessionExt.setState · (some (f state)))

def setRecordingStatement {m : Type → Type} [Monad m] [MonadEnv m]
    [MonadLiftT IO m] (statement : RecordedValue) : m Unit :=
  modifyRecordingState fun state => { state with statement := some statement }

def requireRecordingStatement {m : Type → Type} [Monad m] [MonadEnv m]
    [MonadLiftT IO m] : m RecordedValue := do
  let some statement := (← getRecordingState).statement
    | liftM (throw (IO.userError "ProofScript: missing reserved statement field; capture the initial theorem context before export") : IO RecordedValue)
  return statement

def selectedRecordingContract {m : Type → Type} [Monad m] [MonadEnv m]
    [MonadLiftT IO m] : m (Option RecordingContract) :=
  return (← getRecordingState).selectedContract

def selectRecordingContract {m : Type → Type} [Monad m] [MonadEnv m]
    [MonadLiftT IO m] (contract : Option RecordingContract) : m Unit :=
  modifyRecordingState fun state => { state with selectedContract := contract }

def currentRecordingTag {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] : m String := do
  return (← getRecordingState).boxTags.headD ""

def pushRecordingTag {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (tag : String) : m Unit := do
  modifyRecordingState fun state => { state with boxTags := tag :: state.boxTags }

def popRecordingTag {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] : m Unit := do
  modifyRecordingState fun state => { state with boxTags := state.boxTags.drop 1 }

def registerRecordingStrategy {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (pending : PendingRecordingStrategy) : m Unit := do
  let state ← getRecordingState
  if state.pendingStrategies.any (·.slot.token == pending.slot.token) then
    return ← liftM (throw (IO.userError "[ProofScript] Recording step already has branches.") : IO Unit)
  modifyRecordingState fun state =>
    { state with pendingStrategies := pending :: state.pendingStrategies }

def takeRecordingStrategy {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] : m PendingRecordingStrategy := do
  let state ← getRecordingState
  let pending :: rest := state.pendingStrategies
    | liftM (throw (IO.userError "[ProofScript] No recording strategy to finish.") : IO PendingRecordingStrategy)
  unless state.boxTags.headD "" == pending.slot.box do
    return ← liftM (throw (IO.userError "[ProofScript] Strategy branches have not returned to their parent.") : IO PendingRecordingStrategy)
  modifyRecordingState fun state => { state with pendingStrategies := rest }
  return pending

def beginStrategyBranches {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (mainTag : String) (branches : List RecordingStrategyBranch) : m Unit := do
  modifyRecordingState fun state =>
    { state with strategyBranches := { mainTag, branches } :: state.strategyBranches }

def hasStrategyBranches {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] : m Bool := do
  return !(← getRecordingState).strategyBranches.isEmpty

def strategyBranchForGoal {m : Type → Type} [Monad m] [MonadEnv m]
    [MonadLiftT IO m] (goal : MVarId) : m (Option (String × Name)) := do
  let state ← getRecordingState
  match state.strategyBranches with
  | route :: _ =>
      pure <| route.branches.find? (·.goal == goal) |>.map fun branch => (route.mainTag, branch.label)
  | [] => pure none

def activateStrategyBranch {m : Type → Type} [Monad m] [MonadEnv m]
    [MonadLiftT IO m] (label : Name) : m Unit := do
  let state ← getRecordingState
  let some route := state.strategyBranches.head?
    | liftM (throw (IO.userError "[ProofScript] no active strategy route") : IO Unit)
  unless route.branches.any (·.label == label) do
    return ← liftM (throw (IO.userError s!"[ProofScript] unknown strategy branch '{label}'") : IO Unit)
  let tag := route.mainTag ++ "_" ++ label.toString
  unless state.boxTags.headD "" == tag do
    pushRecordingTag tag

/-! Complete the active branch and either select the route's next target or
    return to its parent. The caller resolves the next target by MVarId. -/
def advanceStrategyCase {m : Type → Type} [Monad m] [MonadEnv m]
    [MonadLiftT IO m] (next : Option (String × Name)) : m Unit := do
  let state ← getRecordingState
  let some route := state.strategyBranches.head?
    | pure ()
  let current := state.boxTags.headD ""
  if current.startsWith (route.mainTag ++ "_") then
    popRecordingTag
  match next with
  | some (mainTag, label) => pushRecordingTag (mainTag ++ "_" ++ label.toString)
  | none => modifyRecordingState fun state => { state with strategyBranches := state.strategyBranches.drop 1 }

def takeBoxWithContracts {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (box : String) : m (Array RecordedValue × Array StepBinding) := do
  let state ← getRecordingState
  match state.boxes.findIdx? (fun (b, _) => b == box) with
  | none => return (#[], #[])
  | some idx =>
    let items := state.boxes[idx]!.2
    let bindings := (state.contractBindings.filter (·.box == box)).map fun entry =>
      { entry.binding with path := #[.index entry.index] ++ entry.binding.path }
    modifyRecordingState fun _ => { state with
      boxes := state.boxes.set! idx (box, #[])
      contractBindings := state.contractBindings.filter (·.box != box) }
    return (items, bindings)

private def bindCurrentContract (state : RecordingState) (box : String) (index : Nat)
    (children : Array StepBinding := #[]) : RecordingState := Id.run do
  let mut bindings := state.contractBindings ++ children.map fun binding => { box := box, index := index, binding := binding }
  if let some contract := state.selectedContract then
    bindings := bindings.push { box, index, binding := { path := #[], contract } }
  return { state with contractBindings := bindings }

/-- Create an empty box if it does not exist. Never changes existing records. -/
def ensureBox {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (box : String) : m Unit := do
  modifyRecordingState fun state =>
    if state.boxes.any (fun (b, _) => b == box) then state
    else { state with boxes := state.boxes.push (box, #[]) }

/-- Append one item to an existing box; never creates a box or modifies earlier items. -/
def appendBoxItem {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (box : String) (item : RecordedValue) (children : Array StepBinding := #[]) : m Unit := do
  let state ← getRecordingState
  let some idx := state.boxes.findIdx? (fun (b, _) => b == box)
    | liftM (throw (IO.userError s!"[ProofScript] Box '{box}' has not been initialized.") : IO Unit)
  let (_, items) := state.boxes[idx]!
  modifyRecordingState fun state =>
    bindCurrentContract { state with boxes := state.boxes.set! idx (box, items.push item) } box items.size children

/-- Reserve one step object before nested recording can append entries. -/
def reserveRecordingSlot {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (box : String) (token ruleId : Name) : m RecordingSlot := do
  let state ← getRecordingState
  let some idx := state.boxes.findIdx? (fun (b, _) => b == box)
    | liftM (throw (IO.userError s!"[ProofScript] Box '{box}' has not been initialized.") : IO RecordingSlot)
  let items := state.boxes[idx]!.2
  let slot : RecordingSlot := { token, box, recordIndex := items.size }
  modifyRecordingState fun state => bindCurrentContract { state with
    boxes := state.boxes.set! idx (box, items.push (.object [("$ruleId", .plain (.str ruleId.toString))]))
    openSteps := slot :: state.openSteps } box items.size
  return slot

def recordingSlotIsOpen {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (slot : RecordingSlot) : m Bool := do
  return (← getRecordingState).openSteps.any (·.token == slot.token)

def getRecordingSlotItem {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (slot : RecordingSlot) : m RecordedValue := do
  let state ← getRecordingState
  let some (_, items) := state.boxes.find? (fun (b, _) => b == slot.box)
    | liftM (throw (IO.userError "[ProofScript] Recording step has no box.") : IO RecordedValue)
  let some item := items[slot.recordIndex]?
    | liftM (throw (IO.userError "[ProofScript] Recording step has no entry.") : IO RecordedValue)
  return item

def setRecordingSlotItem {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (slot : RecordingSlot) (item : RecordedValue) : m Unit := do
  let state ← getRecordingState
  let some idx := state.boxes.findIdx? (fun (b, _) => b == slot.box)
    | liftM (throw (IO.userError "[ProofScript] Recording step has no box.") : IO Unit)
  let items := state.boxes[idx]!.2
  let index := slot.recordIndex
  unless index < items.size do
    return ← liftM (throw (IO.userError "[ProofScript] Recording step has no entry.") : IO Unit)
  modifyRecordingState fun state =>
    { state with boxes := state.boxes.set! idx (slot.box, items.set! index item) }

private def bindingUnderField (binding : BoxContractBinding) (field : String) : Bool :=
  match binding.binding.path[0]? with
  | some (JsonPath.Part.key name) => name == field
  | _ => false

/-- Replace fields in update order. Replacing a field also removes contract
    bindings below that field, since the old nested value no longer exists. The
    root invocation binding remains attached to the step itself. -/
def mergeRecordingSlotFields {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (slot : RecordingSlot) (updates : List (String × RecordedValue)) : m Unit := do
  let state ← getRecordingState
  let some idx := state.boxes.findIdx? (fun (b, _) => b == slot.box)
    | liftM (throw (IO.userError "[ProofScript] Recording step has no box.") : IO Unit)
  let (_, items) := state.boxes[idx]!
  let some (.object fields) := items[slot.recordIndex]?
    | liftM (throw (IO.userError "[ProofScript] Recording step is not an object.") : IO Unit)
  let fields := updates.foldl (init := fields) fun fields (key, value) =>
    if fields.any (·.1 == key) then
      fields.map fun (existing, previous) => (existing, if existing == key then value else previous)
    else fields ++ [(key, value)]
  let updateKeys := updates.map Prod.fst
  let bindings := state.contractBindings.filter fun binding =>
    !(binding.box == slot.box && binding.index == slot.recordIndex &&
      updateKeys.any (bindingUnderField binding))
  modifyRecordingState fun state =>
    { state with
      boxes := state.boxes.set! idx (slot.box, items.set! slot.recordIndex (.object fields))
      contractBindings := bindings }

def attachRecordingSlotContracts {m : Type → Type} [Monad m] [MonadEnv m]
    [MonadLiftT IO m] (slot : RecordingSlot) (children : Array StepBinding) : m Unit :=
  modifyRecordingState fun state =>
    let paths := children.map (·.path)
    { state with
      contractBindings :=
        (state.contractBindings.filter fun existing =>
          !(existing.box == slot.box && existing.index == slot.recordIndex &&
            paths.contains existing.binding.path)) ++
        children.map fun binding => { box := slot.box, index := slot.recordIndex, binding } }

def closeRecordingSlot {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (slot : RecordingSlot) : m Unit := do
  modifyRecordingState fun state =>
    { state with openSteps := state.openSteps.filter (·.token != slot.token) }

/-- Actual invocation positions come only from structured proof data. Plain
    metadata cannot manufacture a child invocation or a binding obligation. -/
private partial def structuredStepPaths (steps : Array RecordedValue) (parent : JsonPath) :
    Array JsonPath := Id.run do
  let mut paths := #[]
  for index in [:steps.size] do
    let .object fields := steps[index]! | continue
    let path := parent.push (.index index)
    paths := paths.push path
    if let some (.array branches) := fields.lookup "$branches" then
      for branchIndex in [:branches.size] do
        let .object branch := branches[branchIndex]! | continue
        if let some (.array children) := branch.lookup "proof" then
          paths := paths ++ structuredStepPaths children
            (path ++ #[.key "$branches", .index branchIndex, .key "proof"])
    if let some (.array children) := fields.lookup "proof" then
      -- A typed proof field becomes an embedded proof only when a structured
      -- child declares a rule; arrays of ordinary metadata remain opaque.
      let containsStep := children.any fun child => match child with
        | .object fields => fields.any (·.1 == "$ruleId")
        | _ => false
      if containsStep then
        paths := paths ++ structuredStepPaths children (path.push (.key "proof"))
  return paths

/-- Finish the recording without changing its state. The returned value owns all
    data needed by the file writer; a missing or empty root is an error. -/
def recordedProofJson {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (boxName : String) (code : String)
    (owner : Name) (artifactKey : Option ArtifactKey := none) (path : String := "") : m Json := do
  unless (← getRecordingState).openSteps.isEmpty do
    return ← liftM (throw (IO.userError "[ProofScript] Cannot export an unfinished recording step.") : IO Json)
  unless (← getRecordingState).pendingStrategies.isEmpty &&
      (← getRecordingState).strategyBranches.isEmpty do
    return ← liftM (throw (IO.userError "[ProofScript] Cannot export an unfinished recording strategy.") : IO Json)
  let boxes := (← getRecordingState).boxes
  let some (_, proof) := boxes.find? (fun (name, _) => name == boxName)
    | liftM (throw (IO.userError s!"[ProofScript] Box '{boxName}' has not been initialized.") : IO Json)
  if proof.isEmpty then
    return ← liftM (throw (IO.userError s!"[ProofScript] Box '{boxName}' is empty.") : IO Json)
  let state ← getRecordingState
  let stepPaths := structuredStepPaths proof #[.key "proof"]
  let statement ← requireRecordingStatement
  let document := encodeOwner <| [
      ("schemaVersion", .plain (toJson recordingProtocolVersion)),
      ("module", .plain (toJson owner.toString)),
      ("code", .plain (toJson code)),
      ("proof", .array proof), ("statement", statement)]
  let proof ← match document.getObjValAs? (Array Json) "proof" with
    | .ok proof => pure proof
    | .error message => liftM (throw (IO.userError message) : IO (Array Json))
  let expressions ← match document.getObjVal? "expressions" with
    | .ok expressions => pure expressions
    | .error message => liftM (throw (IO.userError message) : IO Json)
  let expressionRoots ← match document.getObjValAs? (Array JsonPath) "expressionRoots" with
    | .ok roots => pure roots
    | .error message => liftM (throw (IO.userError message) : IO (Array JsonPath))
  if state.contractBindings.any (·.box != boxName) then
    return ← liftM (throw (IO.userError "[ProofScript] Cannot export unassembled child recording contracts.") : IO Json)
  let bindings := (state.contractBindings.filter (·.box == boxName)).map fun entry =>
    { entry.binding with path := #[.key "proof", .index entry.index] ++ entry.binding.path }
  if let .error message := validateStepBindings proof bindings stepPaths then
    return ← liftM (throw (IO.userError message) : IO Json)
  let dependencies ← match recordedDependencies (← getEnv) expressions document bindings expressionRoots with
    | .ok dependencies => pure dependencies
    | .error message => liftM (throw (IO.userError message) : IO (Array RenderDependency))
  let key := artifactKey.getD { owner, kind := .proof, name := boxName.toName }
  let artifact : Artifact := {
    key, path, dependencies, bindings, contentDigest := document.sha256
    declaration := if (← getEnv).contains key.name then some key.name else none }
  match registerProofArtifact (← getEnv) artifact with
  | .ok env => setEnv env
  | .error message => return ← liftM (throw (IO.userError message) : IO Json)
  return document

/-- Write a completed, immutable proof document. -/
def exportProofToFile (fileName : System.FilePath) (proof : Json) : CoreM Unit := do
  if let some parent := fileName.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile fileName proof.pretty

/-- Native tactic proofs retain their statement graph but have no recorded steps. -/
def codeOnlyProofJson (owner : Name) (code : String) (statement : RecordedValue) :=
  encodeOwner [
    ("schemaVersion", .plain (toJson recordingProtocolVersion)),
    ("module", .plain (toJson owner.toString)),
    ("code", .plain (toJson code)), ("statement", statement)]

end ProofScript
