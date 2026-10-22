import Lean

/-! Frozen recording data and pure graph operations, independent of capture and encoding. -/

namespace ProofScript.Recording

open Lean

/-- Frozen expression structure. Natural-number children index the owning node array;
    variable, universe, binder, and projection information needs no local context. -/
inductive ExprNode where
| bvar (index : Nat)
| fvar (_ : FVarId)
| mvar (_ : MVarId)
| sort (_ : Level)
| const (_ : Name) (_ : List Level)
| app (fn arg : Nat)
| lam (_ : Name) (type body : Nat) (_ : BinderInfo)
| forallE (_ : Name) (type body : Nat) (_ : BinderInfo)
| letE (_ : Name) (type value body : Nat) (nondep : Bool)
| lit (_ : Literal)
| proj (_ : Name) (index : Nat) (expr : Nat)
deriving Inhabited, Repr, BEq

/-- Direct children in the same traversal order as `Expr.getUsedConstants`.
    A projection's type name and index are structural data, not child references. -/
def ExprNode.children : ExprNode → Array Nat
| .app fn arg               => #[fn, arg]
| .lam _ type body _
| .forallE _ type body _    => #[type, body]
| .letE _ type value body _ => #[type, value, body]
| .proj _ _ expr            => #[expr]
| _                         => #[]

/-- Move only child references when appending a graph to another node array.
    De Bruijn indices and projection indices remain unchanged. -/
def ExprNode.rebase (offset : Nat) : ExprNode → ExprNode
| .app fn arg =>
    .app (fn + offset) (arg + offset)
| .lam name type body info =>
    .lam name (type + offset) (body + offset) info
| .forallE name type body info =>
    .forallE name (type + offset) (body + offset) info
| .letE name type value body nondep =>
    .letE name (type + offset) (value + offset) (body + offset) nondep
| .proj typeName index expr =>
    .proj typeName index (expr + offset)
| node => node

/-- Output data with explicitly typed expression leaves. `plain` is opaque JSON:
    its contents are never interpreted as expression references. -/
inductive RecordedData where
| plain (data : Json)
| expression (index : Nat)
| array (_ : Array RecordedData)
| object (_ : List (String × RecordedData))
deriving Inhabited, BEq

/-- A self-contained, uncommitted value. Every expression index in `data` and
    `nodes` belongs to this array, independently of any proof's stored nodes. -/
structure RecordedValue where
  data : RecordedData
  nodes : Array ExprNode := #[]
deriving Inhabited, BEq

/-- Only explicit expression leaves receive an import offset. Object keys,
    ordinary JSON (including `$ref`), view indices and paths are untouched. -/
partial def RecordedData.rebase (offset : Nat) : RecordedData → RecordedData
| .plain value =>
    .plain value
| .expression root =>
    .expression (root + offset)
| .array values =>
    .array <| values.map fun elem => elem.rebase offset
| .object fields =>
    .object <| fields.map fun (key, value) => (key, value.rebase offset)

/-- Append a captured value, relocating its expression references. The returned
    data refers to the entire destination array; keep this pair together rather
    than re-importing the data as a local capture. No cross-capture deduplication. -/
def RecordedValue.importInto (value : RecordedValue) (destination : Array ExprNode)
    : RecordedData × Array ExprNode :=
  let offset := destination.size
  (value.data.rebase offset, destination ++ value.nodes.map (·.rebase offset))

/-- Visit reachable nodes directly in field and structural preorder, retaining
    constants in Lean's first-encounter order. Shared nodes are visited once;
    declarations, projection type names and plain JSON are never traversed. -/
def RecordedValue.references (value : RecordedValue) : Array Name := Id.run do
  let mut pending := [value.data]
  let mut visited : Std.HashSet Nat := {}
  let mut seen : NameSet := {}
  let mut result := #[]
  while !pending.isEmpty do
    let current := pending.head!
    pending := pending.tail!
    match current with
    | .plain _ => pure ()
    | .array values => pending := values.toList ++ pending
    | .object fields => pending := fields.map Prod.snd ++ pending
    | .expression root =>
        if visited.contains root then continue
        visited := visited.insert root
        let node := value.nodes[root]!
        if let .const name _ := node then
          unless seen.contains name do
            seen := seen.insert name
            result := result.push name
        pending := node.children.toList.map RecordedData.expression ++ pending
  return result

end ProofScript.Recording
