/-
    ProofScript.Script.Recording.ProofModel
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import ProofScript.Script.Recording.Data
import ProofScript.Script.Model

namespace ProofScript

open Lean

mutual

/-- A step owns its fields and its child proofs. Neither the step envelope nor
    strategy branches are values supplied by a script recorder. -/
structure RecordedProofStep where
  ruleId : Name
  fields : List (String × RecordedValue) := []
  branches : Array RecordedProofBranch := #[]
deriving Inhabited

/-- A strategy branch owns a named sequence of child proof steps. -/
structure RecordedProofBranch where
  name : String
  proof : Array RecordedProofStep
deriving Inhabited

end

end ProofScript
