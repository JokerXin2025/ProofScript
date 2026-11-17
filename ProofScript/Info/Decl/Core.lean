import ProofScript.Info.Merge

namespace ProofScript

open Lean Elab Command

/-- Native declaration facts shared by complete-application and alias checks.
    The freezer constructs this data from the declaration, never from configuration. -/
structure DefinitionArgumentFacts where
  binder_infos : Array BinderInfo := #[]
  explicit_indices : Array Nat := #[]

def DefinitionArgumentFacts.arity (facts : DefinitionArgumentFacts) : Nat :=
  facts.binder_infos.size

/-- Inspect the declaration's native telescope, reducing function type aliases as needed.
    Local constants keep dependent binder types closed during kernel reduction. -/
partial def definitionArgumentFacts (env : Environment) (target : Name) :
    Except String DefinitionArgumentFacts := do
  let some declaration := env.find? target
    | throw <| infoTargetError "decl" target.toString "unknown declaration"
  loop declaration.type {} {}
where
  loop (type : Expr) (context : LocalContext) (facts : DefinitionArgumentFacts) :
      Except String DefinitionArgumentFacts := do
    let type ← match type.consumeMData with
      | type@(.forallE ..) => pure type
      | type => (Kernel.whnf env context type).mapError fun _ =>
          infoTargetError "decl" target.toString "unable to reduce declaration parameter type"
    match type.consumeMData with
    | .forallE name domain body binderInfo =>
      let index := facts.arity
      let argumentId : FVarId := ⟨Name.num `_declInfoArgument index⟩
      let context := context.mkLocalDecl argumentId name domain binderInfo
      let facts := { facts with
        binder_infos := facts.binder_infos.push binderInfo
        explicit_indices := if binderInfo == .default then facts.explicit_indices.push index
          else facts.explicit_indices }
      loop (body.instantiate1 (.fvar argumentId)) context facts
    | _ => return facts

/-- Follow aliases through configured or defaulted declaration records. -/
partial def resolveDeclChain (env : Environment) (moduleName : Name) (declaration : Name) :
    Except String (Array (Name × DeclInfo)) :=
  loop declaration #[]
where
  loop (current : Name) (chain : Array (Name × DeclInfo)) :
      Except String (Array (Name × DeclInfo)) := do
    let fail := infoTargetError "decl" current.toString
    if chain.any (·.1 == current) then
      let names := (chain.map (·.1.toString)).push current.toString
      let error := infoFieldError "alias_target"
        ("alias cycle: " ++ String.intercalate " → " names.toList)
      throw (fail error)
    unless env.contains current do throw <| fail "unknown declaration in alias closure"
    let view ← resolveTypedDecl env moduleName current
    let info ← view.materialize
    let chain := chain.push (current, info)
    -- Native theorems display by name even if an inactive alias field is retained.
    if (env.find? current).any (fun declaration => match declaration with
        | .thmInfo _ => true
        | _ => false) then return chain
    if info.kind == .alias then
      let some reference := info.alias_target
        | throw <| fail (infoFieldError "alias_target" "alias_target is required for aliases")
      unless env.contains reference.name do
        throw <| fail (infoFieldError "alias_target" "unknown alias target")
      loop reference.name chain
    else return chain

private def constraint (field message : String) : String :=
  infoFieldError field message

/-- Lower structured fragments; no template string is scanned or reparsed. -/
def compileDefinitionInstructions (template : DefinitionTemplate) :
    Except String (Array DefinitionTemplateInstruction) := do
  let compileAtom := fun mode part => (do
    match part with
      | .literal text => pure (.literal text)
      | .argument index max => pure (.argument index mode max)
      | .binder index layer max => pure (.binder index layer mode max)
      | .body index depth max => pure (.body index depth mode max)
    : Except String DefinitionTemplateInstruction)
  let mut instructions : Array DefinitionTemplateInstruction := #[]
  for part in template.content.parts do
    let instruction ← match part with
      | .atom atom => compileAtom template.mode atom
      | .modeSwitch atoms => do
        let mode := template.mode.flip
        pure (.modeSwitch mode (← atoms.mapM (compileAtom mode)))
    match instruction, instructions.back? with
    | .literal text, some (.literal previous) =>
      instructions := instructions.set! (instructions.size - 1) (.literal (previous ++ text))
    | .literal "", _ => pure ()
    | _, _ => instructions := instructions.push instruction
  return instructions

/-- Reserved operator labels describe a single prefix/infix/postfix layout.
    Binder guards remain allowed; binder selectors and extra surrounding structure do not. -/
private def validateSymbolLayout (template : DefinitionTemplate)
    (instructions : Array DefinitionTemplateInstruction) : Except String Unit := do
  unless #["$prefix", "$infix", "$infixl", "$infixr", "$postfix"].contains template.label do return
  let mut operands : Array Nat := #[]
  let mut runs : Array String := #[""]
  for instruction in DefinitionTemplateInstruction.flatten instructions do
    match instruction with
    | .literal content =>
      let content := if template.mode == .text then content.replace "$" "" else content
      runs := runs.set! (runs.size - 1) (runs.back! ++ content)
    | .argument index .. =>
      operands := operands.push index
      runs := runs.push ""
    | .binder .. | .body .. =>
      throw <| constraint "content" s!"{template.label} cannot contain binder selectors"
    | .modeSwitch .. => throw <| constraint "content" "nested mode switch"
  let blank := fun (text : String) => text.trimAscii.toString.isEmpty
  let valid := match template.label with
    | "$prefix" => operands.size == 1 && !blank runs[0]! && blank runs[1]!
    | "$postfix" => operands.size == 1 && blank runs[0]! && !blank runs[1]!
    | "$infix" | "$infixl" | "$infixr" => operands.size == 2 && operands[0]! != operands[1]! &&
        blank runs[0]! && !blank runs[1]! && blank runs[2]!
    | _ => false
  unless valid do
    throw <| constraint "content" s!"invalid {template.label} layout: expected distinct operands and one symbol run"

def freezeDefinitionTemplate (facts : DefinitionArgumentFacts) (template : DefinitionTemplate)
    (active : Bool := true) : Except String Json := do
  let indices := if template.content.auto_arity then facts.explicit_indices else Array.range facts.arity
  let instructions ← compileDefinitionInstructions template
  if active then
    for instruction in DefinitionTemplateInstruction.flatten instructions do
      match instruction with
      | .argument index .. | .binder index .. | .body index .. =>
        if index >= indices.size then
          throw <| constraint "content" "template references a missing declaration argument"
      | .literal _ | .modeSwitch .. => pure ()
    validateSymbolLayout template instructions
  return json% {
    label: $(template.label), lang: $(template.lang), mode: $(template.mode),
    content: $(template.content.display),
    auto_arity: $(template.content.auto_arity),
    precedence: $(template.content.precedence.getD 60),
    argument_indices: $indices, instructions: $instructions }

private def binderName : BinderInfo → String
  | .default => "explicit"
  | .implicit => "implicit"
  | .strictImplicit => "strictImplicit"
  | .instImplicit => "instance"

/-- Freeze the local declaration fields. Alias closure validation is performed by the caller.
    Inactive fields are retained, while ignored wrapper/alias templates receive only basic checks. -/
def freezeDeclValue (env : Environment) (target : Name) (value : DeclInfo) :
    Except String Json :=
  (do
    let facts ← definitionArgumentFacts env target
    let nativeTheorem := (env.find? target).any (fun declaration => match declaration with
      | .thmInfo _ => true
      | _ => false)
    if value.kind == .theorem then
      unless nativeTheorem do
        throw <| constraint "kind" "theorem kind requires a native theorem declaration"
    if !nativeTheorem && value.kind == .wrapper then
      let some index := value.wrapper_index
        | throw <| constraint "wrapper_index" "wrapper_index is required for wrappers"
      if index >= facts.arity then
        throw <| constraint "wrapper_index" "wrapper_index references a missing native argument"
    if !nativeTheorem then
      if let some content := value.parameter_template then
        if (parameterTemplateReferences content).arguments.any (· >= facts.explicit_indices.size) then
          throw <| constraint "parameter_template" "parameter_template references a missing explicit type argument"
    let active := !nativeTheorem && value.kind != .wrapper && value.kind != .alias
    let templates ← value.templates.mapIdxM fun index template =>
      (freezeDefinitionTemplate facts template active).mapError fun error =>
        infoFieldError "templates" (infoIndexError index error)
    TypedInfoChange.validate (.decl target #[⟨.names, value.names⟩, ⟨.tags, value.tags⟩])
    let value : DeclInfo := { value with
      default_template := value.default_template.or ((value.templates[0]?).map (fun (template : DefinitionTemplate) => template.label)) }
    return json% {
      names: $(value.names),
      tags: $(value.tags), var_name: $(value.var_name), kind: $(value.kind),
      wrapper_index: $(value.wrapper_index), alias_target: $(value.alias_target),
      templates: $templates, default_template: $(value.default_template),
      calc_symbol: $(value.calc_symbol), parameter_template: $(value.parameter_template),
      extra: $(value.extra), arity: $(facts.arity),
      binder_infos: $(facts.binder_infos.map binderName),
      parameter_argument_indices: $(facts.explicit_indices) }
    : Except String Json).mapError (infoTargetError "decl" target.toString)

/-- Freeze a declaration and validate its alias closure. -/
def freezeDeclInfo (env : Environment) (moduleName target : Name) :
    Except String (Json × Array Name) := do
  unless env.contains target do
    throw <| infoTargetError "decl" target.toString "unknown declaration"
  let nativeTheorem := (env.find? target).any fun declaration => match declaration with
    | .thmInfo _ => true
    | _ => false
  let chain ← resolveDeclChain env moduleName target
  let some (_, info) := chain[0]? | throw "empty definition closure"
  let mut value : Option Json := none
  for (declaration, resolved) in chain do
    let frozenValue ← freezeDeclValue env declaration resolved
    if declaration == target then value := some frozenValue
  let some frozenValue := value | throw "empty definition closure"
  let dependencies := if nativeTheorem || info.kind != .alias then #[] else
    info.alias_target.toList.toArray.map (·.name)
  return (frozenValue, dependencies)

end ProofScript
