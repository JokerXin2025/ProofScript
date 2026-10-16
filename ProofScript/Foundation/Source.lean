import Lean

namespace ProofScript.Foundation

open Lean

/-- Byte offsets, independent of page components and serializable across `.olean` imports. -/
structure SourceLocation where
  file : String
  start : Nat
  stop : Nat
  deriving Inhabited, Repr, BEq, ToJson, FromJson

def SourceLocation.ofSyntax (file : String) (stx : Lean.Syntax) : SourceLocation :=
  let start := stx.getPos?.getD 0
  { file, start := start.byteIdx, stop := (stx.getTailPos?.getD start).byteIdx }

end ProofScript.Foundation
