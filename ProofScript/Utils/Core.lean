/-
    ProofScript.Utils.Core
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import Lean


namespace Lean.Elab

def resolveDeclaration (id : TSyntax `ident) : CoreM Name := do
  -- for code completion
  addCompletionInfo <| .id id.raw id.getId false {} none
  let declaration ← realizeGlobalConstNoOverloadWithInfo id.raw
  unless (← getEnv).contains declaration do
    throwErrorAt id "unknown declaration `{id.getId}`"
  return declaration

end Lean.Elab
