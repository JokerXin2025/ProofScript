/-
    ProofScript.Script.Recording.Encoding
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import ProofScript.Script.Recording.Data
import ProofScript.Utils.Json
import ProofScript.Utils.JsonPath

open Lean
open scoped ExprJson

namespace ProofScript

private structure EncodingState where
  nodes : Array (String × Json) := #[]
  roots : Array JsonPath := #[]

private abbrev EncodingM := StateM EncodingState

private def expressionRef (index : Nat) : Json :=
  json% { "$ref": $(s!"e{index}") }

/-- The owner assigns an ID only after encoding every outgoing edge. -/
private def appendNode (fields : List (String × Json)) : EncodingM Json := do
  let state ← get
  let index := state.nodes.size
  set { state with nodes := state.nodes.push (s!"e{index}", Json.mkObj fields) }
  return expressionRef index

/-- Encode native expression structure in postorder, without deduplication.
    All scalar metadata is exported without a field-selection switch.
    Metadata wrappers with no exported scalar fields are omitted. -/
private partial def encodeExpression : Expr → EncodingM Json
| .bvar index =>
    appendNode [("kind", toJson "bvar"), ("index", toJson index)]
| .fvar id =>
    appendNode [("kind", toJson "fvar"), ("id", toJson id.name.toString)]
| .mvar id =>
    appendNode [("kind", toJson "mvar"), ("id", toJson id.name.toString)]
| .sort level =>
    appendNode [("kind", toJson "sort"), ("level", toJson level)]
| .const name levels =>
    appendNode [("kind", toJson "const"), ("name", toJson name.toString),
    ("levels", toJson levels)]
| .app fn arg => do
    let fn ← encodeExpression fn
    let arg ← encodeExpression arg
    appendNode [("kind", toJson "app"), ("fn", fn), ("arg", arg)]
| .lam name type body binderInfo => do
    let type ← encodeExpression type
    let body ← encodeExpression body
    appendNode [("kind", toJson "lam"), ("name", toJson name.toString),
      ("type", type), ("body", body), ("binderInfo", toJson binderInfo)]
| .forallE name type body binderInfo => do
    let type ← encodeExpression type
    let body ← encodeExpression body
    appendNode [("kind", toJson "forall"), ("name", toJson name.toString),
      ("type", type), ("body", body), ("binderInfo", toJson binderInfo)]
| .letE name type value body nondep => do
    let type ← encodeExpression type
    let value ← encodeExpression value
    let body ← encodeExpression body
    appendNode [("kind", toJson "let"), ("name", toJson name.toString),
      ("type", type), ("value", value), ("body", body), ("nondep", toJson nondep)]
| .lit value => appendNode [
    ("kind", toJson "lit"), ("lit", toJson value)]
| .mdata data expr => do
    let data := toJson data
    let expr ← encodeExpression expr
    if data == Json.mkObj [] then return expr
    appendNode [("kind", toJson "mdata"), ("data", data), ("expr", expr)]
| .proj typeName index expr => do
    let expr ← encodeExpression expr
    appendNode [("kind", toJson "proj"), ("typeName", toJson typeName.toString),
      ("index", toJson index), ("expr", expr)]

mutual

/-- Only explicit recorded expression leaves register owner-relative roots. -/
private partial def encodeValue (value : RecordedValue) (path : JsonPath)
    : EncodingM Json := do
  match value with
  | .plain data => return data
  | .expression expr =>
      modify fun state => { state with roots := state.roots.push path }
      encodeExpression expr
  | .array values =>
      let values ← values.zipIdx.mapM fun (value, index) =>
        encodeValue value (path.push (.index index))
      return .arr values
  | .object fields =>
      return Json.mkObj (← encodeFields fields path)

private partial def encodeFields (fields : List (String × RecordedValue)) (path : JsonPath)
    : EncodingM (List (String × Json)) := do
  let sorted := fields.toArray.qsort fun a b => a.1 < b.1
  let fields ← sorted.mapM fun (name, value) => do
    return (name, ← encodeValue value (path.push (.key name)))
  return fields.toList

end

/-- Export a complete owner with its own expression table and typed root paths.
    Fields are traversed lexically; opaque JSON is preserved literally. Callers
    supply unique field names excluding `expressions` and `expressionRoots`,
    which are added by the encoder. No fragment-encoding API exposes ownerless
    expression references. -/
def encodeOwner (fields : List (String × RecordedValue)) : Json :=
  let (data, state) := (encodeFields fields #[]).run {}
  Json.mkObj <| data ++ [
    ("expressions", Json.mkObj state.nodes.toList),
    ("expressionRoots", toJson state.roots)
  ]

end ProofScript
