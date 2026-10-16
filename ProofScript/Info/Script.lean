import ProofScript.Info.Derive
import ProofScript.Info.Target
import ProofScript.Script.Registry

open Lean Elab Command


namespace ProofScript.Info

structure ScriptRuleId where
  name : Name
  deriving Inhabited, Repr, BEq

def visibleScriptRegistrations (env : Environment) (moduleName : Name) :
    Except Diagnostic (List ScriptTacticRegistration) := do
  let order ← (Foundation.ModuleGraph.ofEnvironment env).order moduleName
    |>.mapError fun message => { message }
  return scriptRegistrationsInModules env order

def scriptRegistrationInView (env : Environment) (query : Query) (id : ScriptRuleId) :
    Except Diagnostic ScriptTacticRegistration := do
  let some registration := (← visibleScriptRegistrations env query.moduleName).find? (·.ruleId == id.name)
    | throw { message := "unknown script registration", kind := some "script", target := some id.name.toString }
  return registration

def resolveScriptTarget (target : TSyntax `ident) : CommandElabM ScriptRuleId := do
  let env ← getEnv
  let name := removeRoot target.getId.eraseMacroScopes
  let id : ScriptRuleId := ⟨if name.components.length == 1 then env.mainModule ++ name else name⟩
  match scriptRegistrationInView env { moduleName := env.mainModule } id with
  | .ok _ => return id
  | .error _ => throwErrorAt target m!"unknown script_info registration ID `{id.name}`; use its full module-qualified ID for imported rules"

open scoped Foundation in
instance : InfoCodec ScriptRuleId where
  parse stx := do
    let `(term| $id:ident) := stx | throwErrorAt stx "expected a script registration identifier"
    resolveScriptTarget id
  toJson id := Lean.toJson id.name
  decode value := (ScriptRuleId.mk <$> fromJson? value).mapError fun message => { message }
  jsonSchema := Foundation.qualifiedNameSchema

structure HexColor where
  value : String
  deriving Inhabited, Repr, BEq

def HexColor.ofString (value : String) : Except String HexColor :=
  let digits := value.toList.drop 1
  if value.startsWith "#" && [3, 4, 6, 8].contains digits.length && digits.all Char.isHexDigit then
    .ok ⟨value⟩
  else .error "expected a hexadecimal CSS color (#RGB, #RGBA, #RRGGBB or #RRGGBBAA)"

instance : InfoCodec HexColor := checkedCodec HexColor.ofString (·.value)

structure ScriptColor where
  tag : Option HexColor := none
  border : Option HexColor := none
  background : Option HexColor := none
  deriving Inhabited, InfoSchema

instance (priority := high) : InfoCodec ScriptColor :=
  let ordinary := schemaCodec InfoSchema.schema
  { ordinary with parse := fun stx => do
      if let `(term| ($tag:term, $border:term, $background:term)) := stx then
        return ScriptColor.mk (← InfoCodec.parse tag) (← InfoCodec.parse border) (← InfoCodec.parse background)
      ordinary.parse stx }

/-- The renderers currently provided by the backend. Their implementation stays in Python. -/
inductive ScriptRenderer where
  | automatic | strategy | calc | infer | media | diagram | remark | admit | embed
  deriving Inhabited, Repr, BEq

instance : InfoCodec ScriptRenderer := enumCodec #[
  ("none", .automatic), ("strategy", .strategy), ("calc", .calc), ("infer", .infer),
  ("media", .media), ("diagram", .diagram), ("remark", .remark), ("admit", .admit), ("embed", .embed)]

def ScriptRenderer.requiredFields : ScriptRenderer → Array String
  | .automatic | .strategy => #[] -- Branches are supplied by the strategy engine.
  | .calc | .infer => #["init", "chain"]
  | .media => #["metadata", "svg", "source"]
  | .diagram => #["code"]
  | .remark => #["text"]
  | .admit => #["reason"]
  | .embed => #["theorem", "args", "argKinds", "proof", "h", "type"]

structure ScriptIntroducer where
  tag : String
  content : String
  deriving Inhabited, InfoSchema

instance (priority := high) : InfoCodec (Option ScriptIntroducer) := optionalInputCodec

structure ScriptCase where
  name : String
  tag : String
  title : String
  introducer : Option ScriptIntroducer := none
  deriving Inhabited, InfoSchema

def scriptCaseSchema : Schema ScriptCase :=
  InfoSchema.schema.withOverrides! {
    fields := #[ScriptCase.infoFields.name.withValidation fun name =>
      if name.isEmpty then .error "case name must not be empty" else .ok ()] }

instance (priority := high) : InfoCodec ScriptCase := schemaCodec scriptCaseSchema

structure OrdinaryScriptTemplate where
  lang : String
  tag : String
  content : String
  deriving Inhabited, InfoSchema

private def nonemptyLanguage (language : String) : Except String Unit :=
  if language.isEmpty then .error "template language must not be empty" else .ok ()

instance (priority := high) : InfoCodec OrdinaryScriptTemplate := schemaCodec <|
  InfoSchema.schema.withOverrides! {
    fields := #[OrdinaryScriptTemplate.infoFields.lang.withValidation nonemptyLanguage] }

structure StrategyScriptTemplate where
  lang : String
  tag : String
  inline : Bool := false
  introducer : Option ScriptIntroducer := none
  cases : Array ScriptCase
  deriving Inhabited, InfoSchema

def strategyScriptTemplateSchema : Schema StrategyScriptTemplate :=
  InfoSchema.schema.withOverrides! {
    fields := #[StrategyScriptTemplate.infoFields.lang.withValidation nonemptyLanguage,
      StrategyScriptTemplate.infoFields.cases.withValidation fun cases => do
        if cases.isEmpty then throw "cases must not be empty"
        if (cases.toList.map (·.name)).eraseDups.length != cases.size then throw "duplicate case name"]
    validateRecord := fun value => do
      if value.inline then
        if value.cases.size != 1 then
          let error : Diagnostic := {
            message := "inline requires exactly one case"
            path := #[.field StrategyScriptTemplate.infoFields.inline.name]
            relatedPaths := #[#[.field StrategyScriptTemplate.infoFields.cases.name]] }
          throw error
        if value.cases[0]!.tag != "" || value.cases[0]!.title != "" then
          throw { message := "inline case must have empty tag and title", path := #[.field StrategyScriptTemplate.infoFields.cases.name] } }

instance (priority := high) : InfoCodec StrategyScriptTemplate := schemaCodec strategyScriptTemplateSchema

inductive ScriptTemplate where
  | ordinary (value : OrdinaryScriptTemplate)
  | strategy (value : StrategyScriptTemplate)
  deriving Inhabited

def ScriptTemplate.lang : ScriptTemplate → String
  | .ordinary value => value.lang
  | .strategy value => value.lang

def ScriptTemplate.isStrategy : ScriptTemplate → Bool
  | .ordinary _ => false
  | .strategy _ => true

instance : InfoCodec ScriptTemplate where
  parse stx := do
    let fields ← readObject stx
    if fields.any (·.key == StrategyScriptTemplate.infoFields.cases.name) then
      return .strategy (← InfoCodec.parse stx)
    return .ordinary (← InfoCodec.parse stx)
  toJson
  | .ordinary value => json% { kind: "ordinary", value: $value }
  | .strategy value => json% { kind: "strategy", value: $value }
  decode json := do
    let object ← json.getObj?.mapError fun message => { message }
    unless object.toList.all (fun (key, _) => #["kind", "value"].contains key) do
      throw { message := "unknown template envelope field" }
    let kind ← decodeField (Value := String) json "kind"
    match kind with
    | "ordinary" => .ordinary <$> decodeField json "value"
    | "strategy" => .strategy <$> decodeField json "value"
    | _ => throw { message := "unknown script template kind", path := #[.field "kind"] }
  jsonSchema :=
    let alternatives := #[
      ("ordinary", InfoCodec.jsonSchema OrdinaryScriptTemplate),
      ("strategy", InfoCodec.jsonSchema StrategyScriptTemplate)].map fun (kind, schema) => json% {
        type: "object",
        properties: {
          kind: { const: $kind },
          value: $schema
        },
        required: ["kind", "value"],
        additionalProperties: false
      }
    json% { oneOf: $alternatives }

structure ScriptInfo where
  renderer : ScriptRenderer := .automatic
  template : Array ScriptTemplate := #[]
  display : Bool := true
  color : ScriptColor := {}
  extra : ExtraFields := {}
  deriving Inhabited, InfoSchema

def scriptSpec : InfoSpec ScriptInfo := {
  kind := "script"
  schema := InfoSchema.schema.withOverrides! {
    fields := #[ScriptInfo.infoFields.template.withMerge (keyedArray ScriptTemplate.lang)]
    validateRecord := fun value => do
      if value.renderer == .automatic && value.template.isEmpty then
        let error : Diagnostic := {
          message := "automatic script rendering requires a template"
          path := #[.field ScriptInfo.infoFields.template.name]
          relatedPaths := #[#[.field ScriptInfo.infoFields.renderer.name]] }
        throw error } }

private def introducerTexts (value : ScriptIntroducer) : Array (FieldPath × String) := #[
  (#[.field ScriptIntroducer.infoFields.tag.name], value.tag),
  (#[.field ScriptIntroducer.infoFields.content.name], value.content)]

def ScriptTemplate.texts : ScriptTemplate → Array (FieldPath × String)
  | .ordinary value => #[
      (#[.field OrdinaryScriptTemplate.infoFields.tag.name], value.tag),
      (#[.field OrdinaryScriptTemplate.infoFields.content.name], value.content)]
  | .strategy value => Id.run do
    let mut texts := #[(#[.field StrategyScriptTemplate.infoFields.tag.name], value.tag)]
    if let some intro := value.introducer then
      texts := texts ++ (introducerTexts intro).map fun (path, text) =>
        (#[.field StrategyScriptTemplate.infoFields.introducer.name] ++ path, text)
    for index in [:value.cases.size] do
      let item := value.cases[index]!
      let casePath := #[.field StrategyScriptTemplate.infoFields.cases.name, .index index]
      texts := texts ++ #[(casePath.push (.field ScriptCase.infoFields.tag.name), item.tag),
        (casePath.push (.field ScriptCase.infoFields.title.name), item.title)]
      if let some intro := item.introducer then
        texts := texts ++ (introducerTexts intro).map fun (path, text) =>
          (casePath ++ #[.field ScriptCase.infoFields.introducer.name] ++ path, text)
    return texts

def validateScriptContract (registration : ScriptTacticRegistration) (value : ScriptInfo) :
    Except Diagnostic Unit := do
  if value.renderer == .strategy && !registration.strategy then
    throw { message := "strategy renderer requires a strategy registration", path := #[.field ScriptInfo.infoFields.renderer.name] }
  for index in [:value.template.size] do
    let template := value.template[index]!
    if template.isStrategy != registration.strategy then
      throw { message := "template kind does not match the script registration", path := #[.field ScriptInfo.infoFields.template.name, .index index] }
    for (path, text) in template.texts do
      let check := match registration.recordedFields with
        | some recorded => Recording.validateTemplateText recorded text
        | none => Recording.templateSlots text *> pure ()
      check.mapError fun message => {
          message, path := #[.field ScriptInfo.infoFields.template.name, .index index] ++ path }
  if let some recorded := registration.recordedFields then
    for field in value.renderer.requiredFields do
      unless recorded.any (·.name == field) do
        throw { message := s!"renderer requires recorded field `{field}`", path := #[.field ScriptInfo.infoFields.renderer.name] }

/-- Callers with an actual invocation's selected registration can validate that exact contract.
The default registry query below reconstructs module-end registration metadata; Info boundaries clip Info events only.
-/
def resolveScriptInfoWithRegistration (env : Environment) (query : Query)
    (registration : ScriptTacticRegistration) : Except Diagnostic (ResolvedInfo ScriptInfo) :=
  (do
    let view ← resolvePartial scriptSpec env query registration.ruleId
    let result ← if view.created then consumeView scriptSpec view else do
      let fallback : ScriptInfo := if registration.strategy then { renderer := .strategy } else
        { template := #[.ordinary { lang := "zh", tag := registration.name, content := "" }] }
      pure { value := fallback, provenance := view.provenance, dependencies := scriptSpec.dependencies fallback }
    (validateScriptContract registration result.value).mapError view.attach
    return result : Except Diagnostic (ResolvedInfo ScriptInfo)).mapError fun error =>
      { error with kind := some scriptSpec.kind, target := some registration.ruleId.toString }

def resolveScriptInfo (env : Environment) (query : Query) (id : ScriptRuleId) :
    Except Diagnostic (ResolvedInfo ScriptInfo) := do
  resolveScriptInfoWithRegistration env query (← scriptRegistrationInView env query id)

def updateScriptInfo (target : TSyntax `ident) (fields : Array InputField) (ref : Syntax) : CommandElabM Unit := do
  elaborateInfo scriptSpec (← resolveScriptTarget target).name fields ref

end ProofScript.Info
