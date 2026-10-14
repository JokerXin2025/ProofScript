import ProofScript.Page.Component.Computation

open Lean


namespace ProofScript.WasmSpike


structure Request where
  message : String
  count : Nat
deriving FromJson, ToJson

structure Response where
  text : String
  length : Nat
deriving FromJson, ToJson

def compute (request : Request) : Except String Response := do
  if request.count > 1000 then
    throw "count must not exceed 1000"
  let text := String.join (List.replicate request.count request.message)
  return { text, length := text.utf8ByteSize }

/-- JSON ABI entry point used to validate typed decoding and structured errors. -/
@[export proof_script_spike]
def invoke (input : String) : String :=
  Computation.invokeJson compute input


end ProofScript.WasmSpike
