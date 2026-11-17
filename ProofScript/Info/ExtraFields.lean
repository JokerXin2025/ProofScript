import ProofScript.Core.Codec

open Lean


namespace ProofScript

/-- A separate namespace for extension keys; builtin fields never read from this object. -/
structure ExtraFields where
  values : Std.TreeMap String Json := {}

instance : ToJson ExtraFields := ⟨(Json.mkObj ·.values.toList)⟩

/-- Parse extension fields as a JSON object without evaluating Lean terms. -/
instance : InfoCodec ExtraFields where
  decode stx := do
    match (← parseExtraValue stx).getObj? with
    | .ok object => return ⟨Std.TreeMap.ofList object.toList⟩
    | .error message => throwErrorAt stx message

end ProofScript
