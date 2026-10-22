import ProofScript.Script.Recording.Data

namespace ProofScript.Recording

open Lean Elab Tactic Meta

/-- A display observer's frozen result stays in builder state so nested attempts
    preserve it on success and discard it on failure with their graph nodes. -/
structure ExpressionObservation where
  observer : Nat
  root : Nat
  value : RecordedValue

/-- One parameter capture owns its node array. Containers share this state, while
    independent captures start with an empty array. No context-sensitive cache is kept. -/
structure CaptureState where
  nodes : Array ExprNode := #[]
  /-- Explicit display capture observes codec leaves without changing their
      structural capture. Ordinary captures leave these observers empty. -/
  expressionObservers : Array (Expr → Nat → TacticM RecordedValue) := #[]
  observations : Array ExpressionObservation := #[]
  deriving Inhabited

abbrev CaptureM := StateT CaptureState TacticM

namespace CaptureM

private def pushNode (node : ExprNode) : CaptureM Nat := do
  let index := (← get).nodes.size
  modify fun state => { state with nodes := state.nodes.push node }
  return index

/-- The expression has already had its assigned expression and universe
    metavariables instantiated. Metadata does not own a graph node. -/
private partial def captureFrozen (expr : Expr) : CaptureM Nat := do
  match expr with
  | .bvar index => pushNode (.bvar index)
  | .fvar id => pushNode (.fvar id)
  | .mvar id => pushNode (.mvar id)
  | .sort level => pushNode (.sort level)
  | .const name levels => pushNode (.const name levels)
  | .app fn arg =>
    let fn ← captureFrozen fn
    let arg ← captureFrozen arg
    pushNode (.app fn arg)
  | .lam name type body info =>
    let type ← captureFrozen type
    let body ← captureFrozen body
    pushNode (.lam name type body info)
  | .forallE name type body info =>
    let type ← captureFrozen type
    let body ← captureFrozen body
    pushNode (.forallE name type body info)
  | .letE name type value body nondep =>
    let type ← captureFrozen type
    let value ← captureFrozen value
    let body ← captureFrozen body
    pushNode (.letE name type value body nondep)
  | .lit value => pushNode (.lit value)
  | .mdata _ body => captureFrozen body
  | .proj typeName index expr =>
    let expr ← captureFrozen expr
    pushNode (.proj typeName index expr)

/-- Freeze only expression structure at the current capture point. This does not
    infer types, unfold terms, or inspect declarations. -/
def captureExpression (expr : Expr) : CaptureM RecordedData := do
  let frozen ← instantiateMVars expr
  return .expression (← captureFrozen frozen)

/-- Append a standalone value to this builder; plain JSON is opaque during relocation. -/
def importValue (value : RecordedValue) : CaptureM RecordedData := do
  let state ← get
  let (data, nodes) := value.importInto state.nodes
  set { state with nodes }
  return data

/-- Enter the main goal's local context without creating another node owner. -/
def withMainContext (action : CaptureM α) : CaptureM α :=
  fun state => Tactic.withMainContext (StateT.run action state)

/-- Enter a selected goal's local context without creating another node owner. -/
def withGoalContext (goal : MVarId) (action : CaptureM α) : CaptureM α :=
  fun state => goal.withContext (StateT.run action state)

/-- Run an isolated capture with a fresh builder. Both successful and failed
    captures restore elaboration, environment, messages, goals, assignments, and
    editor information. The frozen result is independent of the restored state. -/
def run (action : CaptureM RecordedData) : TacticM RecordedValue := do
  let saved ← Tactic.saveState
  try
    Term.withoutErrToSorry <| withoutRecover do
      let (data, state) ← StateT.run action {}
      return { data, nodes := state.nodes }
  finally
    saved.restore (restoreInfo := true)

end CaptureM

/-- Freeze a codec leaf once, then notify explicitly installed display observers
    with the same frozen expression. The pure structural entry point remains
    `CaptureM.captureExpression`, which never invokes these observers. -/
def snapshotExpression (expr : Expr) : CaptureM RecordedData := do
  let frozen ← instantiateMVars expr
  let root ← CaptureM.captureFrozen frozen
  let state ← get
  for index in [:state.expressionObservers.size] do
    let value ← state.expressionObservers[index]! frozen root
    modify fun state => { state with
      observations := state.observations.push { observer := index, root, value } }
  return .expression root

/-- A nested attempt shares the builder, while restoring temporary elaboration
    and editor information on success and failure. Failed attempts discard their
    nodes and observations. -/
def tryCapture (action : CaptureM RecordedData) : CaptureM (Except String RecordedData) :=
  fun initial => do
    let saved ← Tactic.saveState
    try
      let (data, state) ← Term.withoutErrToSorry <| withoutRecover <| StateT.run action initial
      saved.restore (restoreInfo := true)
      return (.ok data, state)
    catch ex =>
      let message ← ex.toMessageData.toString
      saved.restore (restoreInfo := true)
      return (.error message, initial)

end ProofScript.Recording
