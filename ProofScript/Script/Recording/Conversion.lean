import ProofScript.Script.Recording.Codec

namespace ProofScript.Recording

open Lean Elab Tactic

/-- Convert an existing value into a complete recording value in the current tactic
    context. Expression snapshots retain their reference tables until commit.
    The recording operation is responsible for isolating this capture. -/
class ToRecordedValue (α : Type) where
  capture : α → TacticM RecordedValue

instance : ToRecordedValue RecordedValue where
  capture value := pure value

instance : ToRecordedValue Json where
  capture value := pure (.scalar value)

instance : ToRecordedValue String where
  capture value := pure (.scalar (toJson value))

instance : ToRecordedValue Bool where
  capture value := pure (.scalar (toJson value))

instance : ToRecordedValue Nat where
  capture value := pure (.scalar (toJson value))

instance : ToRecordedValue Int where
  capture value := pure (.scalar (toJson value))

instance : ToRecordedValue Expr where
  capture := snapshotExpression

instance [ToRecordedValue α] : ToRecordedValue (Array α) where
  capture values := do
    return .array (← values.mapM ToRecordedValue.capture)

instance [ToRecordedValue α] : ToRecordedValue (List α) where
  capture values := do
    return .array (← values.toArray.mapM ToRecordedValue.capture)

instance [ToRecordedValue α] : ToRecordedValue (Option α) where
  capture
    | none => pure (.optional none)
    | some value => return .optional (some (← ToRecordedValue.capture value))

end ProofScript.Recording
