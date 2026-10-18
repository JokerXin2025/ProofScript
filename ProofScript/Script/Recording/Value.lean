import ProofScript.Script.Recording.Shape
import ProofScript.Script.ExprJSON

namespace ProofScript.Recording

open Lean

/-- A complete expression export; references are computed while its local context exists. -/
structure ExprSnapshot where
  json : Json
  /-- Export-local reference table; kept with the snapshot because isolated capture rolls
      back the shared export table. `RecordingStep.recordValue` merges these tables. -/
  table : Json
  references : Array Name

/-- Keep container shapes and missing values distinct from capture failures. -/
inductive RecordedValue where
  | scalar (json : Json)
  | expression (snapshot : ExprSnapshot)
  | array (values : Array RecordedValue)
  | object (fields : List (String × RecordedValue))
  | optional (value : Option RecordedValue)

/-- Inspect a value before commit. Expression references still belong to the snapshot's
    local table; use `RecordingStep.recordValue` when writing to a proof export. -/
partial def RecordedValue.toJson : RecordedValue → Json
  | .scalar json => json
  | .expression snapshot => snapshot.json
  | .array values => Json.arr (values.map RecordedValue.toJson)
  | .object fields => Json.mkObj (fields.map fun (name, value) => (name, value.toJson))
  | .optional none => (json% null)
  | .optional (some value) => value.toJson

instance : ToJson RecordedValue := ⟨RecordedValue.toJson⟩

partial def RecordedValue.references : RecordedValue → Array Name
  | .scalar _ => #[]
  | .expression snapshot => snapshot.references
  | .array values => values.foldl (fun acc value => acc ++ value.references) #[]
  | .object fields => fields.foldl (fun acc (_, value) => acc ++ value.references) #[]
  | .optional none => #[]
  | .optional (some value) => value.references

end ProofScript.Recording
