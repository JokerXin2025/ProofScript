/-
    ProofScript.Script.Recording.Data
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import Lean

open Lean


namespace ProofScript

/--
A recorded value, with Lean expressions stored directly in its data.

- `plain`: A plain JSON value, preserved literally even when it resembles an
  expression reference.
- `expression`: A Lean expression, including any `Expr.mdata` annotations
  supplied by its parameter reader or recorder.
- `array`: An array of recorded values.
- `object`: An ordered list of field names and recorded values.

Object keys must be unique. Fields are sorted lexically during export.
Recorded values do not collect literature references.
-/
inductive RecordedValue where
| plain (_ : Json)
| expression (_ : Expr)
| array (_ : Array RecordedValue)
| object (_ : List (String × RecordedValue))
deriving Inhabited

/-- An explicitly selected goal, or no goal selected by the caller. -/
abbrev RecordContext := Option MVarId

/-- Convert a value in a recording context. Parameter and ordinary-value
    instances live in separate scoped namespaces; shared container instances
    pass the context through to their elements. -/
class RecordValue (α : Type) where
  record : α → RecordContext → Lean.Elab.Tactic.TacticM RecordedValue

section
variable {α : Type}

namespace ValueRecorder

scoped instance : RecordValue RecordedValue where
  record value _ := pure value

scoped instance : RecordValue Json where
  record value _ := pure <| .plain value

scoped instance : RecordValue String where
  record value _ := pure <| .plain (toJson value)

scoped instance : RecordValue Bool where
  record value _ := pure <| .plain (toJson value)

scoped instance : RecordValue Nat where
  record value _ := pure <| .plain (toJson value)

scoped instance : RecordValue Int where
  record value _ := pure <| .plain (toJson value)

end ValueRecorder

instance [RecordValue α] : RecordValue (Array α) where
  record values context := return .array <| ← values.mapM (RecordValue.record · context)

instance [RecordValue α] : RecordValue (List α) where
  record values context := return .array <| ← values.toArray.mapM (RecordValue.record · context)

instance [RecordValue α] : RecordValue (Option α) where
  record value context := match value with
  | none       => return .plain .null
  | some item  => RecordValue.record item context

end

end ProofScript
