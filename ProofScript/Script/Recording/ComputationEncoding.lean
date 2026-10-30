import ProofScript.Script.Recording.RecordEngine
import ProofScript.Script.Recording.Expression
import ProofScript.Script.Recording.Encoding
import ProofScript.Script.Contract

namespace ProofScript

open Lean Elab Tactic

/-- Read computation provenance in the declaration's current context. The function
    and implementation retain native expressions independently of proof sessions
    and execution bundles. Only the caller's syntax can supply a root source. -/
def recordComputationFunction (declaration : Name) (type : String)
    (implementation : Expr) (source : Option Syntax := none) : TacticM RecordedValue :=
  recordValueFrom "function" do
    let source ← match source with
      | some raw => trustedSyntaxSource? raw
      | none => pure none
    let expression ← recordExpression (← mkConstWithLevelParams declaration) source
    let implementation ← recordExpression implementation
    return .object [
      ("declaration", .plain (toJson declaration.toString)), ("type", .plain (toJson type)),
      ("expression", expression), ("implementation", implementation)]

/-- Export one complete function owner without querying Lean. Root paths are
    relative to the function object, and both expressions share its node table. -/
def encodeComputationFunction (recorded : RecordedValue) : Except String Json := do
  let .object fields := recorded
  | throw "computation provenance must be an object"
  for field in fields do
    unless ["declaration", "type", "expression", "implementation"].contains field.1 do
      throw s!"unknown computation provenance field `{field.1}`"
  for required in ["declaration", "type"] do
    let some (.plain (.str _)) := fields.lookup required
    | throw s!"computation provenance requires a string `{required}`"
  for required in ["expression", "implementation"] do
    let some (.expression _) := fields.lookup required
    | throw s!"computation provenance requires an expression `{required}`"
  return encodeOwner (fields ++ [("recordingVersion", .plain (toJson recordingProtocolVersion))])

end ProofScript
