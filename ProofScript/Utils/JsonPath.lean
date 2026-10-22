/-
    ProofScript.Utils.JsonPath
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import Lean

open Lean


/-- An object key or array index in a JSON path. -/
inductive JsonPath.Part where
| key (name : String)
| index (num : Nat)
deriving Inhabited, Repr, BEq

instance : ToJson JsonPath.Part where toJson
| .key name => toJson name
| .index num => toJson num

/-- A path relative to a JSON root, with object keys and array indices in traversal
    order. The empty path denotes the root. -/
abbrev JsonPath := Array JsonPath.Part

namespace JsonPath
variable (path : JsonPath)

/-- Render object keys with dots and array indices with brackets. -/
def render : String :=
  path.foldl (init := "") fun text part =>
    match part with
    | .key name => if text.isEmpty then name else text ++ "." ++ name
    | .index num => text ++ s!"[{num}]"

/-- Read a value relative to a JSON root. -/
def get? (document : Json) : Except String Json :=
  path.foldlM (init := document) fun value part =>
    match part with
    | .key name => value.getObjVal? name
    | .index num => do
      let array ← value.getArr?
      match array[num]? with
      | some value => pure value
      | none => throw "JSON path index is out of bounds"

end JsonPath
