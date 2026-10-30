import ProofScript.Output.Manifest

namespace ProofScript

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

/-- Follow structural edges and effective naming-type annotations from an
    explicit expression root. Ordinary JSON and unrelated metadata are not
    searched for declarations. Citation suppression cannot hide rendering use. -/
private partial def expressionDependencies (env : Environment) (table root : Json) :
    Except String (Array RenderDependency) := do
  return (← visit root #[] #[]).2
where
  -- Metadata belongs to an occurrence, even when its structural node is shared.
  -- Peel wrappers before deduplicating that node, retaining the outermost value.
  occurrence (value : Json) (reference : Option String := none)
      (type : Option Json := none) : Except String (Option String × Json × Option Json) := do
    if let .ok id := value.getObjValAs? String "$ref" then
      return ← occurrence (← table.getObjVal? id) (some id) type
    if (value.getObjValAs? String "kind").toOption == some "mdata" then
      let data ← value.getObjVal? "data"
      let type := type.orElse fun _ => (data.getObjVal? "ProofScript.type").toOption
      return ← occurrence (← value.getObjVal? "expr") none type
    return (reference, value, type)
  visit (value : Json) (seen : Array String) (dependencies : Array RenderDependency) :
      Except String (Array String × Array RenderDependency) := do
    let (reference, value, type) ← occurrence value
    let mut seen := seen
    let mut dependencies := dependencies
    if let some (.str descriptor) := type then
      if descriptor.startsWith "decl:" then
        let name ← printedName env (descriptor.drop 5).toString
        dependencies := add dependencies { kind := "definition", target := name }
    if let some id := reference then
      if seen.contains id then return (seen, dependencies)
      seen := seen.push id
    let kind := (value.getObjValAs? String "kind").toOption.getD ""
    if kind == "const" then
      let name ← printedName env (← value.getObjValAs? String "name")
      dependencies := add dependencies { kind := "definition", target := name }
      if name == `Exists then dependencies := add dependencies { kind := "phrase", target := `exists }
    if kind == "forall" then
      dependencies := add dependencies { kind := "phrase", target := `forall }
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
    let ruleId ← step.getObjValAs? String "$ruleId"
    let matching := bindings.filter (·.path == path)
    unless matching.size == 1 && matching[0]!.contract.ruleId.toString == ruleId do
      throw s!"missing or mismatched invocation contract at {(toJson path).compress}"

/-- Only the encoder's explicit expression roots may enter expression traversal.
    Contract-bound theorem steps independently contribute theorem rendering use;
    field schemas never reinterpret a plain JSON value as an expression. -/
def recordedDependencies (env : Environment) (table document : Json)
    (bindings : Array StepBinding) (expressionRoots : Array JsonPath) :
    Except String (Array RenderDependency) := do
  let mut dependencies := #[]
  for path in expressionRoots do
    let expression ← JsonPath.get? path document
    for dependency in ← expressionDependencies env table expression do
      dependencies := add dependencies dependency
  for binding in bindings do
    let step ← JsonPath.get? binding.path document
    if let .ok theoremName := step.getObjValAs? String "theorem" then
      let name ← printedName env theoremName
      dependencies := add dependencies { kind := "theorem", target := name }
  return dependencies

end ProofScript
