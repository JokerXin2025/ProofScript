/-
    ProofScript.Core.References
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import ProofScript.Utils.Json

open Lean


namespace ProofScript
open scoped InfoJson

/-- A collected reference. -/
structure RefInfo where
  name : Name
  /-- Whether this reference is a theorem dependency. Automatic proof dependencies
  take precedence over manual citations. -/
  isDependency : Bool := true
deriving Repr, BEq, ToJson, FromJson

namespace RefInfo

/-- Merge one reference into a list by name, preserving first-occurrence order.
For matching names, `isDependency` becomes true if either reference has it true. -/
def mergeRef (refs : List RefInfo) (ref : RefInfo) : List RefInfo :=
  match refs with
  | [] => [ref]
  | current :: rest =>
      if current.name == ref.name then
        ⟨current.name, current.isDependency || ref.isDependency⟩ :: rest
      else current :: mergeRef rest ref

/-- Return deduplicated proposition constants as references. -/
def collectConstantRefs (consts : Array Name) (isDependency : Bool)
    : MetaM (Array RefInfo) := do
  let env ← getEnv
  let mut refs := []
  for name in consts do
    let some info := env.find? name
    | throwError "Unknown constant `{name}`"
    if ← Meta.isProp info.type then
      refs := mergeRef refs ⟨name, isDependency⟩
  return refs.toArray

end RefInfo


section
variable {α : Type} {m : Type → Type} [Monad m] [MonadEnv m] [MonadFinally m]

/-- The page's reference staging area. -/
-- References collected in async proofs must be visible to later commands.
private initialize theoremRefsExt : EnvExtension (List RefInfo) ←
  registerEnvExtension (pure []) (asyncMode := .sync)

def clearTheoremRefs : m Unit := modifyEnv (theoremRefsExt.setState · [])
def getTheoremRefs : m (List RefInfo) := return theoremRefsExt.getState (← getEnv)

/-- Merge a reference into the page's reference staging area. -/
def stageTheoremRef (ref : RefInfo) : m Unit := do
  modifyEnv fun env =>
    theoremRefsExt.modifyState env (RefInfo.mergeRef · ref)

/-- Lean option: automatic collection of dependencies in the proofs. -/
register_option dependencyCollection : Bool := {
  defValue := true,
  descr := "automatic collection of dependencies in the proofs"
}

/-- Run an action with an isolated reference staging area. Return its staged
references and restore the outer staging area on success or failure. -/
def withIsolatedTheoremRefs (action : m α) : m (α × List RefInfo) := do
  let previous ← getTheoremRefs
  clearTheoremRefs
  try return (← action, ← getTheoremRefs)
  finally modifyEnv (theoremRefsExt.setState · previous)

end

end ProofScript
