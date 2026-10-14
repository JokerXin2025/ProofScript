import ProofScript.Script.Recording.Codec

namespace ProofScript.Recording

open Lean Elab Tactic

instance termRecordCategory : RecordCategory `term where
  schema := .expression
  capture value := expression value.raw

instance identRecordCategory : RecordCategory `ident where
  schema := .expression
  capture value := expression value.raw

instance strRecordCategory : RecordCategory `str where
  schema := .string
  capture value := pure (.scalar (Json.str value.getString))

instance numRecordCategory : RecordCategory `num where
  schema := .number
  capture value := do
    return .scalar (toJson value.getNat)

end ProofScript.Recording
