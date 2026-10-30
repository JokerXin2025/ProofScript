/-
    ProofScript.Utils.Linter
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import Lean
import Mathlib.Tactic.Linter.UnusedTacticExtension
--===============================================================================--

namespace Lean.Elab.Command
variable {α : Type}

/-- Run a command elaboration action with the unused-variable linter disabled.

This is useful for generated command declarations whose syntax variables are
consumed indirectly by elaboration code and therefore cannot be recognized by the
linter as explicit references. -/
def withoutUnusedVariableLint (action : CommandElabM α) : CommandElabM α :=
  withScope (x := action) fun scope =>
    { scope with opts := scope.opts.set `linter.unusedVariables false }

/-- Allow metadata scripts to leave the tactic state unchanged.

This is useful for metadata scripts such as `remark`, which deliberately preserve
the goal state while recording presentation data. Registering their syntax kinds
here keeps Mathlib's unused-tactic linter from reporting them. -/
def allowUnusedTacticKinds (kinds : Array SyntaxNodeKind) : CommandElabM Unit := do
  modifyEnv fun env => kinds.foldl (init := env) fun env kind =>
    Mathlib.Linter.UnusedTactic.allowedUnusedTacticExt.addEntry env kind

end Lean.Elab.Command
