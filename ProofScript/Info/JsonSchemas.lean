import Lean

open Lean


namespace InfoJson

def stringSchema :=
  json% { type: "string" }
def boolSchema :=
  json% { type: "boolean" }
def natSchema :=
  json% { type: "integer", minimum: 0 }
def intSchema :=
  json% { type: "integer" }
def numberSchema :=
  json% { type: "number" }
def nonemptyStringSchema :=
  json% { type: "string", minLength: 1 }
def digestSchema :=
  json% { type: "string", pattern: "^[0-9a-f]{64}$" }

/-- An object whose only permitted properties are listed explicitly. -/
def objectSchema (properties : List (String × Json)) (required : Array String) :=
  json% {
    type: "object",
    properties: $(Json.mkObj properties),
    required: $required,
    additionalProperties: false
  }

def arraySchema (items : Json) :=
  json% { type: "array", items: $items }
def nullableSchema (value : Json) :=
  json% { anyOf: [$value, { type: "null" }] }
def constantSchema (value : String) :=
  json% { const: $value }

/-- A nonempty name preserving both string and numeric components. -/
def qualifiedNameSchema := json% {
  type: "array",
  minItems: 1,
  items: {
    anyOf: [$nonemptyStringSchema, $natSchema]
  }
}

/-- Project IDs are literal strings; other metadata targets are qualified names. -/
def targetSchema (kind : String) : Json :=
  if kind == "project" then nonemptyStringSchema else qualifiedNameSchema

/-- Both reference fields are required on the wire; constructor defaults do not apply. -/
def referenceSchema : Json :=
  objectSchema [("name", qualifiedNameSchema), ("isDependency", boolSchema)] #["name", "isDependency"]

/-- Fixed theorem fields, also embedded in the completed-bundle artifact schema. -/
def theoremExportSchema : Json :=
  objectSchema [
    ("declaration", qualifiedNameSchema),
    ("declarationKind", json% { enum: ["theorem", "lemma"] }),
    ("projectId", nonemptyStringSchema),
    ("proofRefs", arraySchema referenceSchema),
    ("proofDependencies", (arraySchema qualifiedNameSchema).setObjVal! "uniqueItems" (toJson true))
  ] #[
    "declaration", "declarationKind", "projectId", "proofRefs", "proofDependencies"
  ]

end InfoJson
