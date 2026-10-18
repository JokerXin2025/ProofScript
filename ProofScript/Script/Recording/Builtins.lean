import ProofScript.Script.Recording.Codec

namespace ProofScript.Recording

open Lean Elab Tactic

instance termRecordParam : RecordParam (.category `term) where
  schema := .expression
  capture value := expression value.raw

instance identRecordParam : RecordParam (.category `ident) where
  schema := .expression
  capture value := expression value.raw

instance strRecordParam : RecordParam (.category `str) where
  schema := .string
  capture value := pure (.scalar (Json.str value.getString))

instance numRecordParam : RecordParam (.category `num) where
  schema := .number
  capture value := do
    return .scalar (toJson value.getNat)

end ProofScript.Recording
