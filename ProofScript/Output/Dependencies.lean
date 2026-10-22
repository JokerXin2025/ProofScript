import ProofScript.Output.Manifest
import ProofScript.Script.Recording.DisplaySchema

namespace ProofScript.Output

open Lean

/-- Invert exported names, including numeric private-name components and quoted dots.
Term parsing cannot read a numeric private component without interpreting it as a projection.
-/
def printedName (_env : Environment) (text : String) : Except String Name := do
  let mut parts : Array (String × Bool) := #[]
  let mut part := ""
  let mut escaped := false
  let mut inside := false
  for char in text.toList do
    if char == '«' && !inside then
      unless part.isEmpty do throw "invalid printed name escape"
      escaped := true
      inside := true
    else if char == '»' && inside then inside := false
    else if char == '.' && !inside then
      if part.isEmpty then throw "empty printed name component"
      parts := parts.push (part, escaped)
      part := ""
      escaped := false
    else part := part.push char
  if inside || part.isEmpty then throw "invalid printed declaration name"
  parts := parts.push (part, escaped)
  let mut name := Name.anonymous
  for (component, quoted) in parts do
    name := if quoted then .str name component else match component.toNat? with
      | some number => .num name number
      | none => .str name component
  return name

private def add (dependencies : Array RenderDependency) (dependency : RenderDependency) : Array RenderDependency :=
  if dependencies.contains dependency then dependencies else dependencies.push dependency

private def dereference (table value : Json) : Json :=
  match value.getObjValAs? String "$ref" with
  | .ok id => (table.getObjVal? id).toOption.getD value
  | .error _ => value

private def variableTypeKey (table type : Json) : String :=
  let type := dereference table type
  match (type.getObjValAs? String "kind").toOption with
  | some "const" => (type.getObjValAs? String "name").toOption.getD ""
  | some "sort" =>
    if ((type.getObjVal? "level").toOption.bind fun level =>
      (level.getObjValAs? String "kind").toOption) == some "level.zero" then "Prop" else "Type"
  | some "forall" => "Function"
  | _ => ""

/-- Walk structural constructor fields and explicit local display projections.
    Arbitrary metadata is opaque, even if it contains `$ref` or `kind`. Recording
    and citation suppression cannot hide rendering use. -/
private partial def expressionDependencies (env : Environment) (table root : Json) :
    Except String (Array RenderDependency) := do
  return (← visit root #[] #[]).2
where
  visit (value : Json) (seen : Array String) (dependencies : Array RenderDependency) :
      Except String (Array String × Array RenderDependency) := do
    if let .ok id := value.getObjValAs? String "$ref" then
      if seen.contains id then return (seen, dependencies)
      let node ← table.getObjVal? id
      return ← visit node (seen.push id) dependencies
    let mut seen := seen
    let mut dependencies := dependencies
    let kind := (value.getObjValAs? String "kind").toOption.getD ""
    if kind == "const" then
      let name ← printedName env (← value.getObjValAs? String "name")
      dependencies := add dependencies { kind := "definition", target := name }
      if name == `Exists then dependencies := add dependencies { kind := "phrase", target := `exists }
    if kind == "forall" then
      dependencies := add dependencies { kind := "phrase", target := `forall }
    if #["fvar", "lam", "forall", "let"].contains kind then
      let rawName := (value.getObjValAs? String "name").toOption.getD ""
      -- Named variables reserve their spelling; only generated names consult var_info.
      let anonymous := rawName.isEmpty || rawName == "[anonymous]" ||
        rawName.startsWith "_uniq." || (rawName.splitOn "._hyg.").length > 1 ||
        (rawName.splitOn "._@.").length > 1
      -- Match the backend: fvars reserve "_", while let bindings reserve any nonempty name except "_".
      let generated := if kind == "let" then rawName.isEmpty || rawName == "_"
        else anonymous || (kind != "fvar" && rawName == "_")
      if generated then
        let type := dereference table ((value.getObjVal? "type").toOption.getD (json% null))
        let key := if kind == "fvar" then
            if (value.getObjValAs? Bool "isProp").toOption == some true then "Prop"
            else if (type.getObjValAs? Bool "isProp").toOption == some true then "Proof"
            else let key := variableTypeKey table type; if key.isEmpty then "Expr" else key
          else variableTypeKey table type
        if !key.isEmpty then dependencies := add dependencies { kind := "variable", target := Name.mkSimple key }
    let fields : Array String := match kind with
      | "app" => #["fn", "arg"]
      | "lam" | "forall" => #["type", "body"]
      | "let" => #["type", "value", "body"]
      | "proj" => #["expr"]
      | _ => #[]
    for field in fields do
      (seen, dependencies) ← visit (← value.getObjVal? field) seen dependencies
    return (seen, dependencies)

/-- Check completed invocation positions supplied by the structured assembler.
    Encoded ordinary JSON is never searched for apparent nested proof steps. -/
def validateStepBindings (proof : Array Json) (bindings : Array StepBinding)
    (paths : Array JsonPath) : Except String Unit := do
  if paths.size != bindings.size then throw "recording contains orphan or duplicate contract bindings"
  let document := Json.mkObj [("proof", .arr proof)]
  for index in [:proof.size] do
    unless paths.contains #[.key "proof", .index index] do
      throw "recording contains an unstructured root proof step"
  let mut seen := #[]
  for path in paths do
    if seen.contains path then throw "recording contains duplicate invocation positions"
    seen := seen.push path
    let step ← JsonPath.get? path document
    let ruleId ← step.getObjValAs? String "_ruleId"
    let matching := bindings.filter (·.path == path)
    unless matching.size == 1 && matching[0]!.contract.ruleId.toString == ruleId do
      throw s!"missing or mismatched invocation contract at {(toJson path).compress}"

private def eraseMatching? (predicate : α → Bool) : List α → Option (List α)
  | [] => none
  | value :: rest =>
    if predicate value then some rest else (value :: ·) <$> eraseMatching? predicate rest

private def unorderedEquivalent (equivalent : α → α → Bool) : List α → List α → Bool
  | [], right => right.isEmpty
  | value :: rest, right => match eraseMatching? (equivalent value) right with
    | some remaining => unorderedEquivalent equivalent rest remaining
    | none => false

/-- Object fields and union alternatives have no semantic ordering. Matching
    consumes each item once, so repeated fields/options cannot forge coverage. -/
private partial def equivalentSchema : Recording.ParamSchema → Recording.ParamSchema → Bool
  | .object left, .object right => unorderedEquivalent
      (fun (name, schema) (otherName, otherSchema) =>
        name == otherName && equivalentSchema schema otherSchema) left right
  | .union left, .union right => unorderedEquivalent equivalentSchema left right
  | .array left, .array right | .optional left, .optional right => equivalentSchema left right
  | left, right => left == right

/-- Recognition uses the complete declared contract, never the shape of open JSON. -/
private partial def displaySubject : Recording.ParamSchema → Option String
  | .optional schema => displaySubject schema
  | schema@(.object fields) => do
    let .literal "expression-display-v1" ← fields.lookup "kind" | none
    let .literal field ← fields.lookup "field" | none
    if equivalentSchema schema (Recording.displaySchema field) then some field else none
  | _ => none

private def displayPath (value : Json) : Except String JsonPath := do
  (← value.getArr?).mapM fun part => match part with
    | .str field => pure (.key field)
    | _ => return .index (← fromJson? part)

/-- A local rendering projection supplies only explicitly frozen hints to the
    dependency walk. It never changes the structural table or reinterprets user
    JSON; auxiliary declarations remain owned by their declared display view. -/
private def displayViewRoot (subject : Json) (views : Array Json) (index : Nat) :
    Except String (Json × Array Json) := do
  let some view := views[index]? | throw "expression display view is out of bounds"
  let root ← view.getObjVal? "root"
  let expression ← match ← root.getObjValAs? String "kind" with
    | "field" => JsonPath.get? (← displayPath (← root.getObjVal? "path")) subject
    | "auxiliary" => root.getObjVal? "expression"
    | _ => throw "invalid expression display root"
  return (expression, ← view.getObjValAs? (Array Json) "hints")

/-- Classification needs only the auxiliary type's head and its root hint.
    Its complete structure is traversed independently via its registered root. -/
private def displayTypeSummary (table subject : Json) (views : Array Json) (index : Nat) :
    Except String Json := do
  let (expression, hints) ← displayViewRoot subject views index
  let node ← table.getObjVal? (← expression.getObjValAs? String "$ref")
  let kind ← node.getObjValAs? String "kind"
  let fields := match kind with
    | "const" => ["kind", "name"]
    | "sort" => ["kind", "level"]
    | "forall" => ["kind"]
    | _ => []
  let mut summary := Json.mkObj (← fields.mapM fun field => do
    return (field, ← node.getObjVal? field))
  if let some hint := hints.find? (fun hint =>
      (hint.getObjValAs? (Array String) "path").toOption == some #[]) then
    if let .ok (.bool proposition) := hint.getObjVal? "isProp" then
      summary := summary.setObjVal! "isProp" (.bool proposition)
  return summary

private partial def displayProjection (table subject : Json) (views : Array Json)
    (index : Nat) : Except String Json := do
  let (expression, hints) ← displayViewRoot subject views index
  visit expression #[] hints
where
  visit (expression : Json) (path : Array String) (hints : Array Json) : Except String Json := do
    let relevant := hints.any fun hint => match hint.getObjValAs? (Array String) "path" with
      | .ok hintPath => path.size ≤ hintPath.size && hintPath.extract 0 path.size == path
      | .error _ => false
    unless relevant do return expression
    let id ← expression.getObjValAs? String "$ref"
    let node ← table.getObjVal? id
    let kind ← node.getObjValAs? String "kind"
    let edges : Array String := match kind with
      | "app" => #["fn", "arg"]
      | "lam" | "forall" => #["type", "body"]
      | "let" => #["type", "value", "body"]
      | "proj" => #["expr"]
      | _ => #[]
    let mut node := node
    for edge in edges do
      node := node.setObjVal! edge (← visit (← node.getObjVal? edge) (path.push edge) hints)
    let some hint := hints.find? (fun hint =>
        (hint.getObjValAs? (Array String) "path").toOption == some path)
      | return node
    if let .ok (.bool proposition) := hint.getObjVal? "isProp" then
      node := node.setObjVal! "isProp" (.bool proposition)
    if kind == "fvar" || kind == "mvar" then
      if let .ok declaration := hint.getObjVal? "declaration" then
        if let .ok name := declaration.getObjValAs? String "name" then
          node := node.setObjVal! "name" (toJson name)
        if let .ok target := declaration.getObjValAs? Nat "typeView" then
          node := node.setObjVal! "type" (← displayTypeSummary table subject views target)
    return node

private def displayProjections (table document : Json) (bindings : Array StepBinding)
    (roots : Array JsonPath) : Except String (Array (JsonPath × Json)) := do
  let mut result := #[]
  for binding in bindings do
    let step ← JsonPath.get? binding.path document
    for output in binding.contract.fields.getD #[] do
      let some subjectName := displaySubject output.schema | continue
      let display ← step.getObjVal? output.name
      if display == Json.null then continue
      let subject ← step.getObjVal? subjectName
      let views ← display.getObjValAs? (Array Json) "views"
      for index in [:views.size] do
        let root ← views[index]!.getObjVal? "root"
        let path ← match ← root.getObjValAs? String "kind" with
          | "field" => pure (binding.path ++ #[.key subjectName] ++
              (← displayPath (← root.getObjVal? "path")))
          | "auxiliary" => pure (binding.path ++ #[.key output.name, .key "views", .index index,
              .key "root", .key "expression"])
          | _ => throw "invalid expression display root"
        unless roots.contains path do throw "expression display refers to an unregistered root"
        result := result.push (path, ← displayProjection table subject views index)
  return result

/-- Only the encoder's explicit expression roots may enter expression traversal.
    Contract-bound theorem steps independently contribute theorem rendering use;
    field schemas never reinterpret a plain JSON value as an expression. -/
def recordedDependencies (env : Environment) (table document : Json)
    (bindings : Array StepBinding) (expressionRoots : Array JsonPath) :
    Except String (Array RenderDependency) := do
  let mut dependencies := #[]
  let projections ← displayProjections table document bindings expressionRoots
  for path in expressionRoots do
    let expression ← match projections.find? (·.1 == path) with
      | some (_, expression) => pure expression
      | none => JsonPath.get? path document
    for dependency in ← expressionDependencies env table expression do
      dependencies := add dependencies dependency
  for binding in bindings do
    let step ← JsonPath.get? binding.path document
    if let .ok theoremName := step.getObjValAs? String "theorem" then
      let name ← printedName env theoremName
      dependencies := add dependencies { kind := "theorem", target := name }
  return dependencies

end ProofScript.Output
