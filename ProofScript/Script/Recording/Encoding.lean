import ProofScript.Script.Recording.Data
import ProofScript.Utils.Json
import ProofScript.Utils.JsonPath

namespace ProofScript.Recording

open Lean
open scoped ExprJson

/-- A reference within the expression table owned by the enclosing export. -/
private def expressionRef (index : Nat) : Json :=
  json% { "$ref": $(s!"e{index}") }

/-- Encode only the frozen constructor fields. This does not consult Lean state or
    infer declarations, types, application information, or source locations. -/
def ExprNode.toJson : ExprNode → Json
  | .bvar index => json% { kind: "bvar", index: $index }
  | .fvar id => json% { kind: "fvar", id: $(id.name.toString) }
  | .mvar id => json% { kind: "mvar", id: $(id.name.toString) }
  | .sort level => json% { kind: "sort", level: $level }
  | .const name levels =>
      json% { kind: "const", name: $(name.toString), levels: $levels }
  | .app fn arg =>
      json% { kind: "app", fn: $(expressionRef fn), arg: $(expressionRef arg) }
  | .lam name type body info =>
      json% { kind: "lam", name: $(name.toString), type: $(expressionRef type),
        body: $(expressionRef body), binderInfo: $info }
  | .forallE name type body info =>
      json% { kind: "forall", name: $(name.toString), type: $(expressionRef type),
        body: $(expressionRef body), binderInfo: $info }
  | .letE name type value body nondep =>
      json% { kind: "let", name: $(name.toString), type: $(expressionRef type),
        value: $(expressionRef value), body: $(expressionRef body), nondep: $nondep }
  | .lit value => json% { kind: "lit", lit: $value }
  | .proj typeName index expr =>
      json% { kind: "proj", typeName: $(typeName.toString), index: $index,
        expr: $(expressionRef expr) }

/-- Encode the captured node array with its array indices as reference names. -/
def encodeExpressionTable (nodes : Array ExprNode) : Json :=
  Json.mkObj <| nodes.toList.mapIdx fun index node => (s!"e{index}", node.toJson)

/-- Encode a data fragment. Plain JSON remains literal, including any `$ref` or
    `kind` fields; only explicit expression leaves become expression references.
    Use `RecordedValue.encode` to export a self-contained value. -/
partial def RecordedData.toJson : RecordedData → Json
  | .plain value => value
  | .expression root => expressionRef root
  | .array values => Json.arr (values.map RecordedData.toJson)
  | .object fields =>
      Json.mkObj (fields.map fun (name, value) => (name, value.toJson))

private partial def expressionRootsAt (data : RecordedData) (path : JsonPath)
    (roots : Array JsonPath) : Array JsonPath :=
  match data with
  | .plain _ => roots
  | .expression _ => roots.push path
  | .array values =>
      values.zipIdx.foldl (init := roots) fun roots (value, index) =>
        expressionRootsAt value (path.push (.index index)) roots
  | .object fields =>
      let sorted := fields.toArray.qsort fun a b => a.1 < b.1
      sorted.foldl (init := roots) fun roots (name, value) =>
        expressionRootsAt value (path.push (.key name)) roots

/-- Enumerate explicit expression leaves relative to this data root. Arrays use
    index order and objects use lexical key order, independently of capture and
    reference collection order. Plain JSON is never searched for references. -/
def RecordedData.expressionRoots (data : RecordedData) : Array JsonPath :=
  expressionRootsAt data #[] #[]

/-- Encode a self-contained value envelope. Paths are relative to
    this returned object, and therefore begin with `"data"`. This is not a proof
    document: the final proof/function owner assembles its own envelope and uses
    `RecordedData.expressionRoots` with the appropriate owner-relative prefix.
    Fragment encoding and complete value export remain separate operations. -/
def RecordedValue.encode (value : RecordedValue) : Json :=
  let roots := value.data.expressionRoots.map fun path => #[.key "data"] ++ path
  Json.mkObj [
    ("data", value.data.toJson),
    ("expressions", encodeExpressionTable value.nodes),
    ("expressionRoots", toJson roots)
  ]

end ProofScript.Recording
