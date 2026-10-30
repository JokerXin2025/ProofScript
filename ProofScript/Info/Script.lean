import ProofScript.Info.Derive
import ProofScript.Info.Target
import ProofScript.Script.Registry

open Lean Elab Command


namespace ProofScript

def visibleScriptRegistrations (env : Environment) (moduleName : Name) :
    Except Diagnostic (List ScriptTacticRegistration) := do
  let order ← (ModuleGraph.ofEnvironment env).order moduleName
    |>.mapError fun message => { message }
  return scriptRegistrationsInModules env order

def scriptRegistrationInView (env : Environment) (query : Query) (ruleId : Name) :
    Except Diagnostic ScriptTacticRegistration := do
  let some registration := (← visibleScriptRegistrations env query.moduleName).find? (·.ruleId == ruleId)
    | throw { message := "unknown script registration", kind := some "script", target := some ruleId.toString }
  return registration

def resolveScriptTarget (target : TSyntax `ident) : CommandElabM Name := do
  let env ← getEnv
  let ruleId := removeRoot target.getId.eraseMacroScopes
  match scriptRegistrationInView env { moduleName := env.mainModule } ruleId with
  | .ok registration =>
    addConstInfo target.raw registration.sourceKind
    return ruleId
  | .error _ => throwErrorAt target m!"unknown script_info registration ID `{ruleId}`"

/-- Registration IDs have the same editor identity as their source parser declaration.
Verification mode does not require the ID or its metadata to be valid.
-/
def addScriptTargetInfo (target : TSyntax `ident) : CommandElabM Unit := do
  unless (← getInfoState).enabled do return
  let env ← getEnv
  let ruleId := removeRoot target.getId.eraseMacroScopes
  if let .ok registration := scriptRegistrationInView env { moduleName := env.mainModule } ruleId then
    addConstInfo target.raw registration.sourceKind

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
  let ordinary := schemaCodec inferInstance
  { ordinary with parse := fun stx => do
      if let `(term| ($tag:term, $border:term, $background:term)) := stx then
        return ScriptColor.mk (← InfoCodec.parse tag) (← InfoCodec.parse border) (← InfoCodec.parse background)
      ordinary.parse stx }

/-- The renderers currently provided by the backend. Their implementation stays in Python. -/
inductive ScriptRenderer where
  | automatic | strategy | calc | infer | media | diagram | remark | admit | embed | unrecorded
  deriving Inhabited, Repr, BEq

instance : InfoCodec ScriptRenderer := enumCodec #[
  ("none", .automatic), ("strategy", .strategy), ("calc", .calc), ("infer", .infer),
  ("media", .media), ("diagram", .diagram), ("remark", .remark), ("admit", .admit), ("embed", .embed),
  ("unrecorded", .unrecorded)]

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

instance : InfoSchema ScriptCase :=
  (inferInstance : InfoSchema ScriptCase).withOverrides! {
    fields := #[ScriptCase.infoFields.name.withValidation fun name =>
      if name.isEmpty then .error "case name must not be empty" else .ok ()] }

structure OrdinaryScriptTemplate where
  lang : String
  tag : String
  content : String
  deriving Inhabited, InfoSchema

private def nonemptyLanguage (language : String) : Except String Unit :=
  if language.isEmpty then .error "template language must not be empty" else .ok ()

instance : InfoSchema OrdinaryScriptTemplate :=
  (inferInstance : InfoSchema OrdinaryScriptTemplate).withOverrides! {
    fields := #[OrdinaryScriptTemplate.infoFields.lang.withValidation nonemptyLanguage] }

structure StrategyScriptTemplate where
  lang : String
  tag : String
  inline : Bool := false
  introducer : Option ScriptIntroducer := none
  cases : Array ScriptCase
  deriving Inhabited, InfoSchema

instance : InfoSchema StrategyScriptTemplate :=
  (inferInstance : InfoSchema StrategyScriptTemplate).withOverrides! {
    fields := #[StrategyScriptTemplate.infoFields.lang.withValidation nonemptyLanguage,
      StrategyScriptTemplate.infoFields.cases.withValidation fun cases => do
        if cases.isEmpty then throw "cases must not be empty"
        if (cases.toList.map (·.name)).eraseDups.length != cases.size then throw "duplicate case name"]
    validateRecord := fun value => do
      if value.inline then
        if value.cases.size != 1 then
          let error : Diagnostic := {
            message := "inline requires exactly one case"
            path := #[.key StrategyScriptTemplate.infoFields.inline.name]
            relatedPaths := #[#[.key StrategyScriptTemplate.infoFields.cases.name]] }
          throw error
        if value.cases[0]!.tag != "" || value.cases[0]!.title != "" then
          throw { message := "inline case must have empty tag and title", path := #[.key StrategyScriptTemplate.infoFields.cases.name] } }

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
    | _ => throw { message := "unknown script template kind", path := #[.key "kind"] }
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
  annotate stx := do
    if let some fields ← readInfoObject? stx then
      if fields.any (·.key == StrategyScriptTemplate.infoFields.cases.name) then
        annotateInfoFields (inferInstance : InfoSchema StrategyScriptTemplate) fields
      else
        annotateInfoFields (inferInstance : InfoSchema OrdinaryScriptTemplate) fields

structure ScriptInfo where
  renderer : ScriptRenderer := .automatic
  template : Array ScriptTemplate := #[]
  display : Bool := true
  color : ScriptColor := {}
  extra : ExtraFields := {}
  deriving Inhabited, InfoSchema

instance : InfoSchema ScriptInfo :=
  (inferInstance : InfoSchema ScriptInfo).withOverrides! {
    fields := #[ScriptInfo.infoFields.template.withMerge (keyedArray ScriptTemplate.lang)]
    validateRecord := fun value => do
      if value.renderer == .automatic && value.template.isEmpty then
        let error : Diagnostic := {
          message := "automatic script rendering requires a template"
          path := #[.key ScriptInfo.infoFields.template.name]
          relatedPaths := #[#[.key ScriptInfo.infoFields.renderer.name]] }
        throw error }

def scriptSpec : InfoSpec ScriptInfo := {
  kind := "script" }

def validateScriptContract (registration : ScriptTacticRegistration) (value : ScriptInfo) :
    Except Diagnostic Unit := do
  if value.renderer == .strategy && !registration.config.isStrategy then
    throw { message := "strategy renderer requires a strategy registration", path := #[.key ScriptInfo.infoFields.renderer.name] }
  for index in [:value.template.size] do
    let template := value.template[index]!
    if template.isStrategy != registration.config.isStrategy then
      throw { message := "template kind does not match the script registration", path := #[.key ScriptInfo.infoFields.template.name, .index index] }

/-- Callers with an actual invocation's selected registration can validate that exact contract.
The default registry query below reconstructs module-end registration metadata; Info boundaries clip Info events only.
-/
def resolveScriptInfoWithRegistration (env : Environment) (query : Query)
    (registration : ScriptTacticRegistration) : Except Diagnostic (ResolvedInfo ScriptInfo) :=
  (do
    let view ← resolvePartial scriptSpec env query registration.ruleId
    let result ← if view.created then consumeView scriptSpec view else do
      let fallback : ScriptInfo := if registration.ruleId == unrecordedRuleId then { renderer := .unrecorded }
        else if registration.config.isStrategy then { renderer := .strategy } else
        { template := #[.ordinary { lang := "zh", tag := registration.name, content := "" }] }
      pure { value := fallback, provenance := view.provenance, dependencies := scriptSpec.dependencies fallback }
    (validateScriptContract registration result.value).mapError view.attach
    return result : Except Diagnostic (ResolvedInfo ScriptInfo)).mapError fun error =>
      { error with kind := some scriptSpec.kind, target := some registration.ruleId.toString }

def resolveScriptInfo (env : Environment) (query : Query) (ruleId : Name) :
    Except Diagnostic (ResolvedInfo ScriptInfo) := do
  resolveScriptInfoWithRegistration env query (← scriptRegistrationInView env query ruleId)

def updateScriptInfo (target : TSyntax `ident) (fields : Array InputField) (ref : Syntax) : CommandElabM Unit := do
  elaborateInfo scriptSpec (← resolveScriptTarget target) fields ref

end ProofScript
