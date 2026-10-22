import Lean

open Lean


namespace InfoJson

scoped instance : ToJson Name where
  toJson name :=
    let rec parts : Name → List Json
      | .anonymous => []
      | .str parent text => parts parent ++ [.str text]
      | .num parent index => parts parent ++ [toJson index]
    .arr (parts name).toArray

scoped instance : FromJson Name where
  fromJson? value := do
    let parts ← value.getArr?
    if parts.isEmpty then throw "expected a nonempty qualified name"
    let mut name := Name.anonymous
    for part in parts do
      match part with
      | .str text =>
        if text.isEmpty then throw "name components must not be empty"
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

private def litToJson : Literal → Json
| .natVal n =>
    json% { kind: "literal.nat", value: $n }
| .strVal s =>
    json% { kind: "literal.str", value: $s }

scoped instance : ToJson Literal := ⟨litToJson⟩

/-- Metadata keys use display names; values use their `reprStr` representation. -/
private def mdataToJson (data : MData) :=
  Json.mkObj <| data.entries.map fun (name, val) =>
    (name.toString, Json.str (reprStr val))

scoped instance : ToJson MData := ⟨mdataToJson⟩

end ExprJson
