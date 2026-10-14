import Lean.Elab.Tactic

namespace ProofScript.Recording

/-- Semantic parameter category and container shape. Parser extraction is a separate concern:
    both `ident+` and `sepBy1(ident, ...)` can produce `.array (.category `ident)`. -/
inductive ParamShape where
  | category (name : Lean.Name)
  | array (element : ParamShape)
  | optional (element : ParamShape)
  deriving Inhabited, Repr, BEq

/-- Input metadata is independent of the codec's emitted-value schema. -/
def ParamShape.toJson : ParamShape → Lean.Json
  | .category name => .mkObj [("kind", "category"), ("name", .str name.toString)]
  | .array element => .mkObj [("kind", "array"), ("element", element.toJson)]
  | .optional element => .mkObj [("kind", "optional"), ("element", element.toJson)]

/-- The typed input passed to a recorder after parser-specific extraction. -/
def ParamInput : ParamShape → Type
  | .category name => Lean.TSyntax name
  | .array element => Array (ParamInput element)
  | .optional element => Option (ParamInput element)

/-- A schema describes the *stable* output shape, independently of the number of values. -/
inductive ParamSchema where
  | expression
  | string
  | number
  | boolean
  | name
  | syntax
  | literal (value : String)
  | object (fields : List (String × ParamSchema))
  | union (options : List ParamSchema)
  /-- Open JSON supplied by a component/resource producer, rather than a Lean expression. -/
  | json
  | array (element : ParamSchema)
  | optional (element : ParamSchema)
  deriving Inhabited, Repr, BEq

partial def ParamSchema.toJson : ParamSchema → Lean.Json
  | .array element => .mkObj [("kind", "array"), ("element", element.toJson)]
  | .optional element => .mkObj [("kind", "optional"), ("element", element.toJson)]
  | .object fields => .mkObj [("kind", "object"), ("fields", .arr <| fields.toArray.map fun (fieldName, schema) =>
      .mkObj [("name", .str fieldName), ("schema", schema.toJson)])]
  | .union options => .mkObj [("kind", "union"), ("options", .arr (options.toArray.map ParamSchema.toJson))]
  | .literal value => .mkObj [("kind", "literal"), ("value", .str value)]
  | .expression => .mkObj [("kind", "expression")]
  | .string => .mkObj [("kind", "string")]
  | .number => .mkObj [("kind", "number")]
  | .boolean => .mkObj [("kind", "boolean")]
  | .name => .mkObj [("kind", "name")]
  | .syntax => .mkObj [("kind", "syntax")]
  | .json => .mkObj [("kind", "json")]

/-- Persist only the output contract; invocation closures never enter the environment. -/
structure OutputField where
  name : String
  schema : ParamSchema
  /-- Best-effort capture may fail even when the schema itself is not optional. -/
  nullable : Bool := true
  deriving Inhabited, Repr, BEq

def OutputField.toJson (field : OutputField) : Lean.Json :=
  .mkObj [("name", .str field.name), ("schema", field.schema.toJson),
    ("nullable", Lean.toJson field.nullable)]

/-- Expression internals are private to the expression resolver; template paths
    traverse only declared objects and numeric array indices. -/
partial def ParamSchema.hasPath (schema : ParamSchema) (parts : List String) : Bool :=
  if parts.isEmpty then true else
  match schema, parts with
  | .json, _ => true
  | .optional element, _ => element.hasPath parts
  | .union options, _ => options.any (·.hasPath parts)
  | .array element, index :: rest => index.toNat?.isSome && element.hasPath rest
  | .object fields, field :: rest => fields.any fun (fieldName, schema) =>
      fieldName == field && schema.hasPath rest
  | _, _ => false

def validateTemplateText (fields : Array OutputField) (text : String) : Except String Unit := do
  for fragment in (text.splitOn "${").drop 1 do
    let pieces := fragment.splitOn "}"
    if pieces.length < 2 then throw "unclosed template slot"
    let slot := pieces.head!
    if slot == "goal" || fields.any (·.name == slot) then continue
    let parts := slot.splitOn "."
    let root := parts.head!
    unless fields.any (fun field => field.name == root && field.schema.hasPath parts.tail!) do
      throw s!"unknown recorded template field `{slot}`"

partial def validateTemplateFields (fields : Array OutputField) : Lean.Json → Except String Unit
  | .str text => validateTemplateText fields text
  | .arr values => values.forM (validateTemplateFields fields)
  | .obj values => values.toList.forM fun (_, value) => validateTemplateFields fields value
  | _ => pure ()

end ProofScript.Recording
