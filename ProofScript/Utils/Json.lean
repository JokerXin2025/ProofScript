import Lean

open Lean


namespace InfoJson

scoped instance (priority := high) : ToJson Name where
  toJson name :=
    let rec parts : Name → List Json
    | .anonymous => []
    | .str parent text => parts parent ++ [.str text]
    | .num parent index => parts parent ++ [toJson index]
    .arr (parts name).toArray

scoped instance (priority := high) : FromJson Name where
  fromJson? value := do
    let parts ← value.getArr?
    if parts.isEmpty then throw "Expected a nonempty qualified name"
    let mut name := Name.anonymous
    for part in parts do
      match part with
      | .str text =>
        if text.isEmpty then throw "Name components must not be empty"
        name := .str name text
      | _ => name := .num name (← fromJson? part)
    return name

end InfoJson

namespace ExprJson

scoped instance : ToJson BinderInfo where toJson
| .default        => "default"
| .implicit       => "implicit"
| .strictImplicit => "strictImplicit"
| .instImplicit   => "instImplicit"

/-- Preserve the constructors of a universe level. Names use their display spelling. -/
private def levelToJson : Level → Json
| .zero =>
    json% { kind: "level.zero"}
| .succ u =>
    json% { kind: "level.succ", level: $(levelToJson u) }
| .max u v =>
    json% { kind: "level.max", u: $(levelToJson u), v: $(levelToJson v) }
| .imax u v =>
    json% { kind: "level.imax", u: $(levelToJson u), v: $(levelToJson v) }
| .param name =>
    json% { kind: "level.param", name: $(name.toString) }
| .mvar lmvarId =>
    json% { kind: "level.mvar", id: $(lmvarId.name.toString) }

scoped instance : ToJson Level := ⟨levelToJson⟩

scoped instance : ToJson Literal where toJson
| .natVal n =>
    json% { kind: "literal.nat", value: $n }
| .strVal s =>
    json% { kind: "literal.str", value: $s }

/-- Metadata keys use display names and scalar values retain their JSON types.
    Syntax values are omitted; fields are ordered by their exported keys. -/

scoped instance : ToJson MData where
  toJson data :=
    let fields := data.entries.filterMap fun (name, value) => do
      let value ← match value with
      | .ofString value => some (toJson value)
      | .ofBool value => some (toJson value)
      | .ofName value => some (toJson value.toString)
      | .ofNat value => some (toJson value)
      | .ofInt value => some (toJson value)
      | .ofSyntax _ => none
      return (name.toString, value)
    Json.mkObj (fields.toArray.qsort fun a b => a.1 < b.1).toList

end ExprJson
