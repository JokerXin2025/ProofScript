/-
    ProofScript.Script.Recording.Encoding
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import ProofScript.Script.Recording.ProofModel
import ProofScript.Script.ExpressionEncoding

open Lean

namespace ProofScript

private abbrev EncodingM := ExpressionEncodingM

mutual

/-- Only explicit recorded expression leaves register owner-relative roots. -/
private partial def encodeValue (value : RecordedValue) (path : JsonPath)
    : EncodingM Json := do
  match value with
  | .plain data => return Json.mkObj [("kind", toJson "plain"), ("value", data)]
  | .expression expr =>
      return Json.mkObj [("kind", toJson "expression"),
        ("value", ← encodeNativeExpression expr (path.push (.key "value")))]
  | .array values =>
      let values ← values.zipIdx.mapM fun (value, index) =>
        encodeValue value (path ++ #[.key "value", .index index])
      return Json.mkObj [("kind", toJson "array"), ("value", .arr values)]

private partial def encodeFields (fields : List (String × RecordedValue)) (path : JsonPath)
    : EncodingM (List (String × Json)) := do
  let sorted := fields.toArray.qsort fun a b => a.1 < b.1
  let fields ← sorted.mapM fun (name, value) => do
    return (name, ← encodeValue value (path.push (.key name)))
  return fields.toList

end

/-- Assemble one graph owner from separately encoded, typed fields. -/
private def encodeDocument := encodeExpressionDocument

private def encodeStatement (statement : RecordedTheoremStatement)
    (path : JsonPath) : EncodingM Json := do
  let conclusion ← encodeNativeExpression statement.conclusion (path.push (.key "conclusion"))
  let conditions ← statement.conditions.zipIdx.mapM fun (condition, index) =>
    encodeNativeExpression condition (path ++ #[.key "conditions", .index index])
  let parameters ← statement.parameters.zipIdx.mapM fun (parameter, index) => do
    let root := path ++ #[.key "parameters", .index index]
    let type ← encodeNativeExpression parameter.typeExpr (root.push (.key "type"))
    let variableRef ← encodeNativeExpression parameter.variableExpr (root.push (.key "variable"))
    return Json.mkObj [("variable", variableRef), ("type", type),
      ("instance", toJson parameter.isInstance)]
  return Json.mkObj [("parameters", .arr parameters), ("conditions", .arr conditions),
    ("conclusion", conclusion)]

private partial def encodeProofSteps (steps : Array RecordedProofStep)
    (path : JsonPath) : EncodingM Json := do
  let items ← steps.zipIdx.mapM fun (step, index) => do
    let root := path.push (.index index)
    -- Interleave structural branches with recorder fields by key so expression
    -- IDs and root paths retain the owner's original lexical traversal order.
    let entries := step.fields.map fun (name, value) => (name, some value)
    let entries := if step.branches.isEmpty then entries else ("$branches", none) :: entries
    let sorted := entries.toArray.qsort fun a b => a.1 < b.1
    let fields ← sorted.mapM fun (name, value) => do
      let encoded ← match value with
        | some value => encodeValue value (root.push (.key name))
        | none => do
            let branches ← step.branches.zipIdx.mapM fun (branch, branchIndex) => do
              let proof ← encodeProofSteps branch.proof
                (root ++ #[.key "$branches", .index branchIndex, .key "proof"])
              return Json.mkObj [("name", toJson branch.name), ("proof", proof)]
            pure (.arr branches)
      return (name, encoded)
    return Json.mkObj <| ("$ruleId", toJson step.ruleId.toString) :: fields.toList
  return .arr items

/-- Proof and statement share a graph, but neither is a RecordedValue. -/
def encodeProofDocument (owner : Name) (code : String)
    (statement : RecordedTheoremStatement) (proof : Option (Array RecordedProofStep)) : Json :=
  encodeDocument do
    let mut fields := [("code", toJson code), ("module", toJson owner.toString)]
    if let some steps := proof then
      fields := fields ++ [("proof", ← encodeProofSteps steps #[.key "proof"])]
    fields := fields ++ [("statement", ← encodeStatement statement #[.key "statement"])]
    return fields

end ProofScript
