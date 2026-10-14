import ProofScript.Script.JsonBox

open Lean


namespace ProofScript


/- The marker identifies the witness-producing goal created by `witness`. -/
def witnessDataGoalMDataKey : Name := `ProofScript.witnessDataGoal

def pushBoxTag {m : Type → Type} [Monad m] [MonadEnv m] [MonadLiftT IO m]
    (tag : String) : m Unit := pushRecordingTag tag
def popBoxTag {m : Type → Type} [Monad m] [MonadEnv m] [MonadLiftT IO m]
    : m Unit := popRecordingTag

/-! ## Strategy branch tracking -/

/-- Start a new strategy -/
def startStrategy {m : Type → Type} [Monad m] [MonadEnv m] [MonadLiftT IO m]
    (mainTag : String) (nodes : List String) : m Unit := do
  for node in nodes do
    let nodeTag := mainTag ++ "_" ++ node
    ensureBox nodeTag
  match nodes with
  | firstNode :: remaining =>
    pushBoxTag (mainTag ++ "_" ++ firstNode)
    beginStrategyBranches mainTag remaining
  | [] => pure ()

/-- Advance to the next branch -/
def advanceStrategyCase {m : Type → Type} [Monad m] [MonadEnv m] [MonadLiftT IO m]
    : m Unit := do
  if ← hasStrategyBranches then
    match ← nextStrategyBranch with
    | none =>
      -- The last branch also returns to its parent.
      popBoxTag
    | some (mainTag, nextNode) =>
      popBoxTag
      pushBoxTag (mainTag ++ "_" ++ nextNode)

end ProofScript
