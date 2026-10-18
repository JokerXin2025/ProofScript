import Lean

namespace ProofScript.Foundation

/-- One object field or array index in a JSON path. -/
inductive PathPart where
  | field (name : String)
  | index (value : Nat)
  deriving Inhabited, Repr, BEq

def PathPart.toJson : PathPart → Lean.Json
  | .field name => Lean.toJson name
  | .index value => Lean.toJson value

instance : Lean.ToJson PathPart := ⟨PathPart.toJson⟩

end ProofScript.Foundation
