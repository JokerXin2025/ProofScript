import Lean.Meta

open Lean


namespace ProofScript

def proofSchemaVersion := "0.1.0"

/-- Mutable data owned by a single proof recording. -/
structure RecordingState where
  boxes : Array (String × Array Json) := #[]
  boxTags : List String := []
  strategyBranches : List (String × List String) := []
  resolvedBranches : List (List String) := []
  deriving Inhabited

/-- Non-persistent environment state travels through command, tactic and term
    elaboration and follows Lean's ordinary environment backtracking. -/
initialize recordingSessionExt : Lean.EnvExtension (Option RecordingState) ←
  Lean.registerEnvExtension (pure none)

def withRecordingSession (action : Lean.Elab.Command.CommandElabM α) : Lean.Elab.Command.CommandElabM α := do
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

def currentRecordingTag {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] : m String := do
  return (← getRecordingState).boxTags.headD ""

def pushRecordingTag {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (tag : String) : m Unit := do
  modifyRecordingState fun state => { state with boxTags := tag :: state.boxTags }

def popRecordingTag {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] : m Unit := do
  modifyRecordingState fun state => { state with boxTags := state.boxTags.drop 1 }

def pushResolvedBranches {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (branches : List String) : m Unit := do
  modifyRecordingState fun state =>
    { state with resolvedBranches := branches :: state.resolvedBranches }

def takeResolvedBranches {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (fallback : List String) : m (List String) := do
  let state ← getRecordingState
  modifyRecordingState fun _ => { state with resolvedBranches := state.resolvedBranches.drop 1 }
  return state.resolvedBranches.headD fallback

def beginStrategyBranches {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (mainTag : String) (remaining : List String) : m Unit := do
  modifyRecordingState fun state =>
    { state with strategyBranches := (mainTag, remaining) :: state.strategyBranches }

def hasStrategyBranches {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] : m Bool := do
  return !(← getRecordingState).strategyBranches.isEmpty

/-- Pop the active branch and return its next label, if one remains. -/
def nextStrategyBranch {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] : m (Option (String × String)) := do
  let state ← getRecordingState
  match state.strategyBranches with
  | [] => return none
  | (mainTag, nodes) :: rest =>
    match nodes with
    | [] =>
      modifyRecordingState fun _ => { state with strategyBranches := rest }
      return none
    | nextNode :: remaining =>
      modifyRecordingState fun _ => { state with strategyBranches := (mainTag, remaining) :: rest }
      return some (mainTag, nextNode)

def takeBox {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (box : String) : m (Array Json) := do
  let state ← getRecordingState
  match state.boxes.findIdx? (fun (b, _) => b == box) with
  | none => return #[]
  | some idx =>
    let items := state.boxes[idx]!.2
    modifyRecordingState fun _ => { state with boxes := state.boxes.set! idx (box, #[]) }
    return items

/-- Create an empty box if it does not exist. Never changes existing records. -/
def ensureBox {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (box : String) : m Unit := do
  modifyRecordingState fun state =>
    if state.boxes.any (fun (b, _) => b == box) then state
    else { state with boxes := state.boxes.push (box, #[]) }

/-- Append one item to an existing box; never creates a box or modifies earlier items. -/
def appendBoxItem {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (box : String) (item : Json) : m Unit := do
  let state ← getRecordingState
  let some idx := state.boxes.findIdx? (fun (b, _) => b == box)
    | liftM (throw (IO.userError s!"[ProofScript] Box '{box}' has not been initialized.") : IO Unit)
  let (_, items) := state.boxes[idx]!
  modifyRecordingState fun state =>
    { state with boxes := state.boxes.set! idx (box, items.push item) }

/-- Merge object fields into the last item of an existing, nonempty box. Later values win. -/
def mergeBoxLast {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (box : String) (updates : Json) : m Unit := do
  let state ← getRecordingState
  let some idx := state.boxes.findIdx? (fun (b, _) => b == box)
    | liftM (throw (IO.userError s!"[ProofScript] Box '{box}' has not been initialized.") : IO Unit)
  let (_, items) := state.boxes[idx]!
  let some previous := items.back?
    | liftM (throw (IO.userError s!"[ProofScript] Box '{box}' has no last item to merge.") : IO Unit)
  let .ok fields := previous.getObj?
    | liftM (throw (IO.userError s!"[ProofScript] Box '{box}' has a non-object last item.") : IO Unit)
  let .ok additions := updates.getObj?
    | liftM (throw (IO.userError "[ProofScript] Merged fields must be a JSON object.") : IO Unit)
  let merged := additions.toList.foldl (fun fields (key, value) => fields.insert key value) fields
  modifyRecordingState fun state =>
    { state with boxes := state.boxes.set! idx (box, items.set! (items.size - 1) (Json.mkObj merged.toList)) }

/-- Replace the first strategy placeholder, preserving later ordinary steps. -/
def replaceStrategyPlaceholder {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (box : String) (stepName : String) (merged : Json) : m Unit := do
  let state ← getRecordingState
  let some idx := state.boxes.findIdx? (fun (b, _) => b == box)
    | liftM (throw (IO.userError s!"[ProofScript] Box '{box}' has not been initialized.") : IO Unit)
  let (_, items) := state.boxes[idx]!
  let some itemIdx := items.findIdx? (fun item =>
      (item.getObjValAs? String "_pending_strategy_").toOption == some stepName)
    | liftM (throw (IO.userError s!"[ProofScript] Missing strategy placeholder '{stepName}' in box '{box}'.") : IO Unit)
  let fields := (items[itemIdx]!.getObj?.toOption.getD {}).toList.filter (·.1 != "_pending_strategy_")
  let updates := (merged.getObj?.toOption.getD {}).toList
  modifyRecordingState fun state =>
    { state with boxes := state.boxes.set! idx (box, items.set! itemIdx (Json.mkObj (fields ++ updates))) }

/-- Finish the recording without changing its state. The returned value owns all
    data needed by the file writer; a missing or empty root is an error. -/
def recordedProofJson {m : Type → Type} [Monad m] [Lean.MonadEnv m]
    [MonadLiftT IO m] (boxName : String) (code : String) (expressions : Json)
    (owner : Name) : m Json := do
  let boxes := (← getRecordingState).boxes
  let some (_, proof) := boxes.find? (fun (name, _) => name == boxName)
    | liftM (throw (IO.userError s!"[ProofScript] Box '{boxName}' has not been initialized.") : IO Json)
  if proof.isEmpty then
    return ← liftM (throw (IO.userError s!"[ProofScript] Box '{boxName}' is empty.") : IO Json)
  return Json.mkObj [
    ("schemaVersion", Json.str proofSchemaVersion),
    ("module", Json.str owner.toString),
    ("code", Json.str code),
    ("expressions", expressions),
    ("proof", Json.arr proof)
  ]

/-- Write a completed, immutable proof document. -/
def exportProofToFile (fileName : System.FilePath) (proof : Json) : CoreM Unit := do
  if let some parent := fileName.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile fileName proof.pretty

/-- Export a proof document containing only its complete source code. -/
def exportCodeOnlyProofToFile (fileName : System.FilePath) (code : String) : CoreM Unit := do
  if let some parent := fileName.parent then
    IO.FS.createDirAll parent
  let proofJson := Json.mkObj [
    ("schemaVersion", Json.str proofSchemaVersion),
    ("module", Json.str (← getEnv).mainModule.toString),
    ("code", Json.str code)
  ]
  IO.FS.writeFile fileName proofJson.pretty

end ProofScript
