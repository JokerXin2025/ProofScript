import ProofScript.Output.Manifest

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

/-- Walk only committed reachable expression nodes; recording/citation suppression cannot hide rendering use. -/
partial def expressionDependencies (env : Environment) (table root : Json)
    (inlineExpression : Bool := false) : Except String (Array RenderDependency) := do
  return (← visit root inlineExpression #[] #[]).2
where
  visit (value : Json) (insideExpression : Bool) (seen : Array String) (dependencies : Array RenderDependency) :
      Except String (Array String × Array RenderDependency) := do
    if let .ok id := value.getObjValAs? String "$ref" then
      if seen.contains id then return (seen, dependencies)
      let node ← table.getObjVal? id
      return ← visit node true (seen.push id) dependencies
    let mut seen := seen
    let mut dependencies := dependencies
    let kind := (value.getObjValAs? String "kind").toOption.getD ""
    if insideExpression && kind == "const" then
      let name ← printedName env (← value.getObjValAs? String "name")
      dependencies := add dependencies { kind := "definition", target := name }
      if name == `Exists then dependencies := add dependencies { kind := "phrase", target := `exists }
    if insideExpression && kind == "forall" then
      dependencies := add dependencies { kind := "phrase", target := `forall }
    if insideExpression && #["fvar", "lam", "forall", "let"].contains kind then
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
    if (value.getObjVal? "_ruleId").isOk then
      if let .ok theoremName := value.getObjValAs? String "theorem" then
        let name ← printedName env theoremName
        dependencies := add dependencies { kind := "theorem", target := name }
    match value with
    | .arr values =>
      for value in values do
        (seen, dependencies) ← visit value insideExpression seen dependencies
    | .obj fields =>
      for (_, value) in fields.toList do
        (seen, dependencies) ← visit value insideExpression seen dependencies
    | _ => pure ()
    return (seen, dependencies)

/-- Bindings are checked against the completed structural positions, including branch and embedded proofs. -/
partial def validateStepBindings (proof : Array Json) (bindings : Array StepBinding) : Except String Unit := do
  let paths ← visit proof #[.field "proof"] #[]
  if paths.size != bindings.size then throw "recording contains orphan or duplicate contract bindings"
where
  visit (steps : Array Json) (parent : StepPath) (paths : Array StepPath) : Except String (Array StepPath) := do
    let mut paths := paths
    for index in [:steps.size] do
      let step := steps[index]!
      let path := parent.push (.index index)
      let ruleId ← step.getObjValAs? String "_ruleId"
      let matching := bindings.filter (·.path == path)
      unless matching.size == 1 && matching[0]!.contract.ruleId.toString == ruleId do
        throw s!"missing or mismatched invocation contract at {(pathJson path).compress}"
      paths := paths.push path
      if let .ok branches := step.getObjValAs? (Array Json) "branches" then
        for branchIndex in [:branches.size] do
          let children ← branches[branchIndex]!.getObjValAs? (Array Json) "proof"
          paths ← visit children (path ++ #[.field "branches", .index branchIndex, .field "proof"]) paths
      if let .ok children := step.getObjValAs? (Array Json) "proof" then
        if children.any (fun child => (child.getObjVal? "_ruleId").isOk) then
          paths ← visit children (path.push (.field "proof")) paths
    return paths

private def atPath (document : Json) (path : StepPath) : Except String Json :=
  path.foldlM (init := document) fun value part => match part with
    | .field name => value.getObjVal? name
    | .index index => do
      let array ← value.getArr?
      match array[index]? with
      | some value => pure value
      | none => throw "step path index is out of bounds"

/-- Typed expression fields also support inline handwritten JSON; open metadata is not treated as an expression. -/
partial def recordedDependencies (env : Environment) (table document : Json)
    (bindings : Array StepBinding) : Except String (Array RenderDependency) := do
  let mut dependencies ← expressionDependencies env table ((document.getObjVal? "proof").toOption.getD (json% null))
  for binding in bindings do
    if let some fields := binding.contract.fields then
      let step ← atPath document binding.path
      for field in fields do
        if let .ok value := step.getObjVal? field.name then
          for dependency in ← fromSchema field.schema value do
            dependencies := add dependencies dependency
  return dependencies
where
  fromSchema (schema : Recording.ParamSchema) (value : Json) : Except String (Array RenderDependency) := do
    match schema with
    | .expression => expressionDependencies env table value true
    | .array element =>
      if let .ok values := value.getArr? then
        return (← values.mapM (fromSchema element)).flatMap id
      return #[]
    | .object fields =>
      let mut dependencies := #[]
      for (name, schema) in fields do
        if let .ok child := value.getObjVal? name then
          dependencies := dependencies ++ (← fromSchema schema child)
      return dependencies
    | .optional schema => if value == (json% null) then pure #[] else fromSchema schema value
    | .union choices => return (← choices.toArray.mapM (fun schema => fromSchema schema value)).flatMap id
    | _ => pure #[]

end ProofScript.Output
