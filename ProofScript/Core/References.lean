/-
    ProofScript.Core.References
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import Lean

open Lean


namespace ProofScript
variable {m : Type → Type} [Monad m] [MonadOptions m] [MonadEnv m]

-- References collected in async proofs must be visible to later commands.
initialize theoremRefsExt : EnvExtension (List Name) ←
  registerEnvExtension (pure []) (asyncMode := .sync)

def clearTheoremRefs : m Unit :=
  modifyEnv (theoremRefsExt.setState · [])

def getTheoremRefs : m (List Name) :=
  return theoremRefsExt.getState (← getEnv)

def addTheoremRef (name : Name) : m Unit := do
  modifyEnv fun env =>
    theoremRefsExt.modifyState env fun current =>
      if current.contains name then current
      else current.append [name]

register_option referenceCollection : Bool := {
  defValue := true,
  descr := "enable automatic theorem-reference collection during ProofScript recording"
}

def referencesEnabled : m Bool :=
  return (← getOptions).getBool ``referenceCollection true

end ProofScript
