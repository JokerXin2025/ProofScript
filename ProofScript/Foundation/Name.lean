import Lean

namespace ProofScript.Foundation

open Lean

scoped instance : ToJson Name where
  toJson name :=
    let rec parts : Name → List Json
      | .anonymous => []
      | .str parent text => parts parent ++ [.str text]
      | .num parent index => parts parent ++ [toJson index]
    .arr (parts name).toArray

scoped instance : FromJson Name where
  fromJson? value := do
    let parts ← value.getArr?
    if parts.isEmpty then throw "expected a nonempty qualified name"
    let mut name := Name.anonymous
    for part in parts do
      match part with
      | .str text =>
        if text.isEmpty then throw "name components must not be empty"
        name := .str name text
      | _ => name := .num name (← fromJson? part)
    return name

def qualifiedNameSchema := json% {
  type: "array",
  minItems: 1,
  items: {
    anyOf: [
      { type: "string", minLength: 1 },
      { type: "integer", minimum: 0 }
    ]
  }
}

end ProofScript.Foundation
