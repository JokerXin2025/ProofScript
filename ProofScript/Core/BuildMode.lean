/-
    ProofScript.Core.BuildMode
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import Lean

open Lean


namespace ProofScript

/-- Lean option: page-build mode. -/
register_option pageBuild : Bool := {
  defValue := false,
  descr := "page-build mode"
}

section
variable {m : Type → Type} [Monad m] [MonadOptions m]

/-- Return the value of option `pageBuild`. -/
def pageBuild? : m Bool := return pageBuild.get (← getOptions)

/-- Run an action when the option `pageBuild` is on. -/
def whenPageBuild (action : m Unit) : m Unit := do
  if ← pageBuild? then action

end

end ProofScript
