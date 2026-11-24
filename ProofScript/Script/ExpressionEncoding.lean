import ProofScript.Utils.Json
import ProofScript.Utils.JsonPath

open Lean
open scoped ExprJson

namespace ProofScript

/-- The graph and typed owner-relative expression occurrences shared by all exporters. -/
structure ExpressionEncodingState where
  nodes : Array (String × Json) := #[]
  roots : Array JsonPath := #[]

abbrev ExpressionEncodingM := StateM ExpressionEncodingState

private def expressionRef (index : Nat) : Json :=
  json% { "$ref": $(s!"e{index}") }

private def appendNode (fields : List (String × Json)) : ExpressionEncodingM Json := do
  let state ← get
  let index := state.nodes.size
  set { state with nodes := state.nodes.push (s!"e{index}", Json.mkObj fields) }
  return expressionRef index

/-- Encode native expression structure in postorder, without deduplication.
    Export all scalar metadata; omit empty metadata wrappers. -/
private partial def encodeExpression : Expr → ExpressionEncodingM Json
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
| .lit value => appendNode [("kind", toJson "lit"), ("lit", toJson value)]
| .mdata data expr => do
    let data := toJson data
    let expr ← encodeExpression expr
    if data == Json.mkObj [] then return expr
    appendNode [("kind", toJson "mdata"), ("data", data), ("expr", expr)]
| .proj typeName index expr => do
    let expr ← encodeExpression expr
    appendNode [("kind", toJson "proj"), ("typeName", toJson typeName.toString),
      ("index", toJson index), ("expr", expr)]

/-- Register a native expression occurrence at an owner-relative path. -/
def encodeNativeExpression (expr : Expr) (path : JsonPath) : ExpressionEncodingM Json := do
  modify fun state => { state with roots := state.roots.push path }
  encodeExpression expr

/-- Finish an independently owned expression graph. -/
def encodeExpressionDocument (action : ExpressionEncodingM (List (String × Json))) : Json :=
  let (data, state) := action.run {}
  Json.mkObj <| data ++ [
    ("recordingProtocol", toJson (2 : Nat)),
    ("expressions", Json.mkObj state.nodes.toList),
    ("expressionRoots", toJson state.roots)]

end ProofScript
