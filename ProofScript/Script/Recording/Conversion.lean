import ProofScript.Script.Recording.Codec

open Lean


namespace ProofScript
open Recording

/-- Convert existing values inside the current builder. A complete capture is
    frozen and isolated by CaptureM.run. -/
class ToRecordedValue (α : Type) where
  capture : α → CaptureM RecordedData

instance : ToRecordedValue RecordedValue where
  capture := CaptureM.importValue

instance : ToRecordedValue Json where
  capture value := pure <| .plain value

instance : ToRecordedValue String where
  capture value := pure <| .plain (toJson value)

instance : ToRecordedValue Bool where
  capture value := pure <| .plain (toJson value)

instance : ToRecordedValue Nat where
  capture value := pure <| .plain (toJson value)

instance : ToRecordedValue Int where
  capture value := pure <| .plain (toJson value)

instance : ToRecordedValue Expr where
  capture := snapshotExpression

instance [ToRecordedValue α] : ToRecordedValue (Array α) where
  capture values := do
    return .array <| ← values.mapM ToRecordedValue.capture

instance [ToRecordedValue α] : ToRecordedValue (List α) where
  capture values := do
    return .array <| ← values.toArray.mapM ToRecordedValue.capture

instance [ToRecordedValue α] : ToRecordedValue (Option α) where
  capture
    | none => pure <| .plain Json.null
    | some value => ToRecordedValue.capture value

end ProofScript
