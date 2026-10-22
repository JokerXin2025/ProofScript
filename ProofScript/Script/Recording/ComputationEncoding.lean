import ProofScript.Script.Recording.Display
import ProofScript.Script.Recording.Encoding
import ProofScript.Script.Contract

namespace ProofScript.Recording

open Lean

/-- Capture a computation's provenance in its own graph. The function reference,
    implementation and their explicit display queries observe the same context.
    This data never joins a proof session or an execution bundle. -/
def captureComputationFunction (declaration : Name) (type : String)
    (implementation : Expr) (source : Option Syntax := none) : CaptureM RecordedData := do
  let expression ← captureWithDisplay "expression" (snapshotExpression (mkConst declaration)) source
  let implementation ← captureWithDisplay "implementation" (snapshotExpression implementation)
  let .object expressionFields := expression
    | throwError "invalid computation expression capture"
  let .object implementationFields := implementation
    | throwError "invalid computation implementation capture"
  let some expression := expressionFields.lookup "value"
    | throwError "computation capture has no expression"
  let some expressionDisplay := expressionFields.lookup "display"
    | throwError "computation capture has no expression display"
  let some implementation := implementationFields.lookup "value"
    | throwError "computation capture has no implementation"
  let some implementationDisplay := implementationFields.lookup "display"
    | throwError "computation capture has no implementation display"
  return .object [
    ("declaration", .plain (toJson declaration.toString)), ("type", .plain (toJson type)),
    ("expression", expression), ("expression_display", expressionDisplay),
    ("implementation", implementation), ("implementation_display", implementationDisplay)]

/-- Export a complete frozen function owner without querying Lean. Expression
    root paths are relative to the function object. -/
def encodeComputationFunction (captured : RecordedValue) : Except String Json := do
  let .object fields := captured.data
    | throw "computation provenance must be an object"
  for field in fields do
    unless ["declaration", "type", "expression", "implementation",
        "expression_display", "implementation_display"].contains field.1 do
      throw s!"unknown computation provenance field `{field.1}`"
  for required in ["declaration", "type"] do
    let some (.plain (.str _)) := fields.lookup required
      | throw s!"computation provenance requires a string `{required}`"
  for required in ["expression", "implementation"] do
    let some (.expression _) := fields.lookup required
      | throw s!"computation provenance requires an expression `{required}`"
    let some (.object display) := fields.lookup (required ++ "_display")
      | throw s!"computation provenance requires a display for `{required}`"
    unless display.lookup "kind" == some (.plain (.str "expression-display-v1")) &&
        display.lookup "field" == some (.plain (.str required)) do
      throw s!"invalid computation display for `{required}`"
    let some (.array _) := display.lookup "views"
      | throw s!"computation display requires views for `{required}`"
  return Json.mkObj ((fields.map fun (name, value) => (name, value.toJson)) ++ [
    ("expressions", encodeExpressionTable captured.nodes),
    ("recordingVersion", toJson recordingProtocolVersion),
    ("expressionRoots", toJson captured.data.expressionRoots)])

end ProofScript.Recording
