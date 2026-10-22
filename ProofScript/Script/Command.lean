import Lean.Elab.Command
import Lean.Elab.Tactic
import Lean.Parser.Term
import ProofScript.Utils.Syntax
import ProofScript.Script.Recording
import ProofScript.Script.Recording.Normalize
import ProofScript.Script.Registry
import ProofScript.Script.Recording.Metadata
import ProofScript.Script.Syntax

open Lean
open Parser (atomic darrow sepBy optional ppSpace many1 termParser withPosition
             nonReservedSymbol runParserCategory suppressInsideQuot)
open Parser.Term (ident doSeqItem doSeqIndent)
open Parser.Command (macroArg macroRhs docComment)
open Elab.Command (CommandElabM elabCommand liftIO expandMacroArg elabSyntax)


namespace ProofScript

/-- Prefixed execution entries retain the same editor identity as script calls. -/
def withScriptExecutionInfo (kind : Name) (action : Elab.Tactic.TacticM α) : Elab.Tactic.TacticM α := do
  if let some keyword := findFirstAtom (← getRef) then
    Elab.addConstInfo keyword kind
  withScriptMode action

elab (name := scriptMacroInfo) "_script_macro_info%" kind:ident source:term "=>" expanded:tactic : tactic => do
  if let some keyword := findFirstAtom source.raw then
    Elab.addConstInfo keyword kind.getId
  withScriptMode <| Elab.Tactic.evalTactic expanded

/-- Attach invocation info when a registered macro is called through its prefixed
entry, preserving the original token instead of manufacturing a source span. -/
def withScriptMacroInfo (kind : Name) (action : MacroM Syntax) : MacroM Syntax := do
  let source ← getRef
  let expanded ← action
  return mkNode ``scriptMacroInfo #[mkAtom "_script_macro_info%", mkIdent kind, source,
    mkAtom "=>", expanded]

/-! ### 语法级辅助：从 `macroArg` 节点构造录制版 elab（纯 antiquotation，不经字符串） -/

private def validateRegistrationId (id : TSyntax `ident) : CommandElabM Name := do
  let name := id.getId.eraseMacroScopes
  unless name.components.length == 1 do
    throwErrorAt id "script registration ID must be a single local identifier; the defining module supplies its namespace"
  return name

/-- Delay unsupported automatic-parameter diagnostics until a recorded invocation. -/
private def autoRecordingError (name : String)
    (args : Array (TSyntax ``macroArg)) (overrides : List String := []) : CommandElabM (Option String) := do
  for arg in args[1:] do
    match arg with
    | `(macroArg| $id:ident:$stx) =>
      match Recording.normalizeParam stx with
      | .error msg => return some s!"[script recorder] '{name}': 参数 '{id.getId}' {msg}；请定义 script_recorder"
      | .ok parser =>
        if overrides.contains id.getId.toString then continue
        let shape ← parser.shapeTerm
        let type ← `(term| ProofScript.Recording.RecordParam $shape)
        let available ← Lean.Elab.Command.liftTermElabM do
          let type ← Lean.Elab.Term.elabTerm type none
          match ← Lean.Meta.trySynthInstance type with
          | .some _ => return true
          | _ => return false
        unless available do
          return some s!"[script recorder] '{name}': 参数 '{id.getId}' 缺少 RecordParam 实例；请提供类别实例或定义 script_recorder"
    | _ => pure ()
  return none

open Lean.Parser.Syntax in
/-- 从完整策略名构造 `macroArg`（str 字面量，含引号）。 -/
def mkRawNameArg (name : String) : Syntax :=
  mkNode ``macroArg #[
    mkNullNode,
    mkNode ``atom #[mkNode `str #[Lean.mkAtom ("\"" ++ name ++ "\"")]]
  ]

def mkNameArg (name : String) : Syntax := mkRawNameArg ("_" ++ name)

def mkScriptNameArg (name : String) : Syntax := mkRawNameArg ("script_" ++ name)

/-- Script keywords must not reserve identifiers in native terms and tactics. -/
private partial def scriptKeywords (stx : Syntax) : Syntax :=
  if stx.getKind == ``Parser.Syntax.atom then
    mkNode ``Parser.Syntax.nonReserved #[mkAtom "&", stx[0]]
  else
    stx.modifyArgs (·.map scriptKeywords)

private def registerTacticRegistration (registration : ScriptTacticRegistration) :
    CommandElabM Unit := do
  let owner ← getMainModule
  let ruleId := owner ++ registration.ruleId
  if ruleId == unrecordedRuleId then
    throwError m!"reserved script registration ID `{ruleId}`"
  if (scriptTacticRegistrations (← getEnv)).any (fun r => r.ruleId == ruleId) then
    throwError m!"duplicate script registration ID `{ruleId}`; give each overload a distinct explicit ID"
  let registration := { registration with ruleId }
  modifyEnv fun env => scriptRegistrationExt.addEntry env (.register registration)

/-- A rule's existing parser declaration is also its editor symbol. Registration
IDs need not be Lean declaration names and may collide with ordinary constants. -/
private def addRegistrationInfo (id : TSyntax `ident) (kind : Name)
    (args : Array (TSyntax ``macroArg)) (doc? : Option (TSyntax ``docComment)) : CommandElabM Unit := do
  Elab.addDeclarationRangesFromSyntax kind (← getRef) id.raw
  let documentation ← match doc? with
    | some doc => getDocStringText doc
    | none => pure s!"ProofScript script registration `{(← getMainModule) ++ id.getId.eraseMacroScopes}`."
  addDocStringCore kind documentation
  Elab.Command.liftTermElabM do
    Elab.Term.addTermInfo' id.raw (← mkConstWithLevelParams kind) (isBinder := true)
  if let some first := args.toList.head? then
    if let `(macroArg| $keyword:str) := first then
      Elab.addConstInfo keyword.raw kind

/-- Check signatures before generating parser/elaborator declarations for an override. -/
private def validateRecorderRegistration (id : Name) (name : String)
    (parameters : Array (String × Recording.ParamParserSignature)) : CommandElabM Name := do
  unless id.components.length == 1 do
    throwError "script_recorder requires the registration's local ID"
  let ruleId := (← getMainModule) ++ id
  let registration ← match scriptRegistrationForRecorder (← getEnv) ruleId with
    | .ok registration => pure registration
    | .error message => throwError "{message}"
  if registration.name != name then
    throwError m!"[script recorder] `{ruleId}` uses tactic `{registration.name}`, not `{name}`"
  let parameters := if registration.strategy &&
      parameters.size == registration.parameters.size + 1 &&
      parameters.back? == some ("strategyCases", .normalized (.category `str)) then
    parameters.pop else parameters
  let compatible := registration.parameters.size == parameters.size &&
    (registration.parameters.toList.zip parameters.toList).all fun ((sourceName, sourceParser), (recName, recParser)) =>
      (sourceName == recName || sourceName.startsWith "_") && sourceParser == recParser
  unless compatible do
    throwError m!"[script recorder] parameters of `{ruleId}` do not match its registration"
  return ruleId

/-- 参数录制配置在声明时解析；codec 与 parser 类别独立。 -/
structure ParamCfg where
  timing : Option Recording.CaptureTiming := none
  codec : Recording.ParamCodec := .default
  context : Recording.ContextSelector := .main
  failure : Recording.FailurePolicy := .bestEffort
  field : Option String := none
  deriving Inhabited

structure ScriptCfg where
  intro : List String := []
  clear : List String := []
  strategy : Bool := false
  params : List (String × ParamCfg) := []
  /-- 执行后目标列表中的 continuation 索引；此前目标是待证明的策略分支。 -/
  continuation : Option Nat := none

def emptyScriptCfg : ScriptCfg := {}

/-- 声明校验与代码生成共用时机规则，避免校验的字段名与实际输出不一致。
    intro/clear 是 after/before 的语法糖；字符串默认 once，其他参数默认 both。 -/
private def parameterTiming (cfg : ScriptCfg) (name : String)
    (shape : Option Recording.ParamShape) : Recording.CaptureTiming :=
  ((cfg.params.lookup name).bind (·.timing)).getD <|
    if cfg.intro.contains name then .after
    else if cfg.clear.contains name then .before
    else if shape == some (.category `str) then .once
    else .both

private def recordingFields (args : Array (TSyntax ``macroArg)) (cfg : ScriptCfg) :
    CommandElabM (Array Recording.OutputField) := do
  let mut fields := if cfg.strategy then Recording.strategyGoalFields else Recording.goalFields
  for arg in args[1:] do
    match arg with
    | `(macroArg| $id:ident:$stx) =>
      let pname := id.getId.toString
      let .ok parser := Recording.normalizeParam stx | throwErrorAt stx "unsupported parameter parser"
      let options := (cfg.params.lookup pname).getD {}
      let schema ← match options.codec with
        | .default => do
          let shape ← parser.shapeTerm
          Recording.evalSchema (← `(term| ProofScript.Recording.RecordParam.schema $shape))
        | .expression | .typeOf => pure Recording.ParamSchema.expression
        | .name => pure .name
        | .syntax => pure .syntax
      fields := fields ++ Recording.emittedFields (options.field.getD pname) schema
        (parameterTiming cfg pname (some parser.shape)) options.failure
    | _ => pure ()
  return Recording.withDisplayFields fields

/-- 声明时解析实例及 timing，直接生成捕获、执行和策略收尾的录制 DSL。 -/
private def genRecording (syntaxName : String)
    (args : Array (TSyntax ``macroArg)) (cfg : ScriptCfg) : CommandElabM Lean.Name := do
  let tacticCat : TSyntax `ident := ⟨mkIdent `tactic⟩
  -- Rename both pattern bindings and references to avoid the generated elaborator's binders.
  let mut recArgs := args.mapIdx fun i a => if i == 0 then ⟨mkNameArg syntaxName⟩ else a
  for i in [1:recArgs.size] do
    match recArgs[i]! with
    | `(macroArg| $id:ident:$stx) =>
      let renamed := mkIdent (Name.mkSimple ("__recordParam_" ++ id.getId.toString))
      recArgs := recArgs.set! i (← `(macroArg| $renamed:ident:$stx))
    | _ => pure ()
  let strategyCasesId : TSyntax `ident := ⟨mkIdent `strategyCases⟩
  if cfg.strategy then
    recArgs := recArgs.push (← `(macroArg| "_strategy_cases"))
    recArgs := recArgs.push (← `(macroArg| strategyCases:str))
  let goalBefore ← `(term| ProofScript.Recording.goalParamWithDisplay "goal_before")
  let mut beforeCaptures : Array (TSyntax `term) := #[goalBefore]
  let mut afterCaptures : Array (TSyntax `term) := #[]
  if !cfg.strategy then
    afterCaptures := afterCaptures.push (← `(term| ProofScript.Recording.goalParamWithDisplay "goal_after"))
  for arg in args[1:] do
    match arg with
    | `(macroArg| $id:ident:$stx) =>
      let pname := id.getId.toString
      let id : TSyntax `ident := ⟨mkIdent (Name.mkSimple ("__recordParam_" ++ pname))⟩
      let parser ← match Recording.normalizeParam stx with
        | .ok parser => pure parser
        | .error message => throwErrorAt id "parameter `{pname}`: {message}"
      let options := (cfg.params.lookup pname).getD {}
      let timing := parameterTiming cfg pname (some parser.shape)
      let context ← match options.context with
        | .main => `(term| ProofScript.Recording.ContextSelector.main)
        | .continuation => `(term| ProofScript.Recording.ContextSelector.continuation)
        | .branch label => `(term| ProofScript.Recording.ContextSelector.branch $(quote label))
      let failure ← match options.failure with
        | .required => `(term| ProofScript.Recording.FailurePolicy.required)
        | .bestEffort => `(term| ProofScript.Recording.FailurePolicy.bestEffort)
      let field := options.field.getD pname
      let capture ← if options.codec == .default then
          let shape ← parser.shapeTerm
          let input ← parser.inputTerm ⟨id.raw⟩
          `(term| { (ProofScript.Recording.paramWithDisplay $shape $(quote field) $input $failure)
            with context := $context })
        else
          let codec ← match options.codec with
            | .default => `(term| ProofScript.Recording.ParamCodec.default)
            | .expression => `(term| ProofScript.Recording.ParamCodec.expression)
            | .typeOf => `(term| ProofScript.Recording.ParamCodec.typeOf)
            | .name => `(term| ProofScript.Recording.ParamCodec.name)
            | .syntax => `(term| ProofScript.Recording.ParamCodec.syntax)
          let .category _ := parser.shape
            | throwErrorAt id "explicit codec requires a single syntax parameter `{pname}`"
          let raw ← `(term| Lean.TSyntax.raw $id:ident)
          `(term| ProofScript.Recording.explicitParamWithDisplay $(quote field)
            $codec $raw $context $failure)
      match timing with
      | .once | .before => beforeCaptures := beforeCaptures.push capture
      | .after => afterCaptures := afterCaptures.push capture
      | .both =>
        beforeCaptures := beforeCaptures.push (← `(term| { $capture with field := $(quote (field ++ "_before")) }))
        afterCaptures := afterCaptures.push (← `(term| { $capture with field := $(quote (field ++ "_after")) }))
    | _ => pure ()
  let recCall ← if cfg.strategy then
      `(doElem| recording_strategy (($strategyCasesId:ident).getString.splitOn "\n")
          (continuation := $(quote cfg.continuation)) do
        capture_params #[$beforeCaptures,*]
        execute_recorded
        capture_params #[$afterCaptures,*])
    else
      `(doElem| recording_step do
        capture_params #[$beforeCaptures,*]
        execute_recorded
        capture_params #[$afterCaptures,*])
  -- Register the recording syntax once and reuse its actual kind for elab_rules.
  let (recStxParts, recPatArgs) := (← recArgs.mapM expandMacroArg).unzip
  let recKind ← elabSyntax (← `(syntax $[$recStxParts]* : $tacticCat))
  let recPat := ⟨mkNode recKind recPatArgs⟩
  let recKindId : TSyntax `ident := ⟨mkIdent recKind⟩
  let doSeq : TSyntax ``doSeqIndent := ⟨mkDoSeq #[recCall.raw]⟩
  let recCmd ← `(command| elab_rules (kind := $recKindId) : $tacticCat | `($recPat) => do $doSeq:doSeqIndent)
  elabCommand (eraseMacroScopes recCmd.raw)
  return recKind

/-! ### 参数配置、时机语法糖和策略上下文 -/

private def parseParamCfg (stx : Syntax) : CommandElabM (String × ParamCfg) := do
  let name := stx[0].getId.toString
  let mut cfg : ParamCfg := {}
  let mut assigned : List String := []
  for entry in stx[1][1].getArgs do
    if entry.isAtom then continue
    let key := entry[0].getId.toString
    if assigned.contains key then throwErrorAt entry "duplicate parameter option `{key}`"
    assigned := key :: assigned
    let value := if entry[2].isIdent then entry[2].getId.toString
      else (⟨entry[2]⟩ : TSyntax `str).getString
    match key with
    | "timing" =>
      let timing ← match value with
        | "once" => pure Recording.CaptureTiming.once
        | "before" => pure .before
        | "after" => pure .after
        | "both" => pure .both
        | _ => throwErrorAt entry "unknown capture timing `{value}`"
      cfg := { cfg with timing := some timing }
    | "codec" =>
      let codec ← match value with
        | "default" => pure Recording.ParamCodec.default
        | "expression" => pure .expression
        | "typeOf" => pure .typeOf
        | "name" => pure .name
        | "syntax" => pure .syntax
        | _ => throwErrorAt entry "unknown parameter codec `{value}`"
      cfg := { cfg with codec }
    | "context" =>
      let context := if value == "main" then Recording.ContextSelector.main
        else if value == "continuation" then .continuation
        else .branch value
      cfg := { cfg with context }
    | "failure" =>
      let failure ← match value with
        | "required" => pure Recording.FailurePolicy.required
        | "bestEffort" => pure .bestEffort
        | _ => throwErrorAt entry "unknown capture failure policy `{value}`"
      cfg := { cfg with failure }
    | "field" => cfg := { cfg with field := some value }
    | _ => throwErrorAt entry "unknown parameter option `{key}`"
  return (name, cfg)

/-- 直接解析声明配置的语法树，不在编译期求值用户表达式。 -/
private def parseScriptCfg  (cfg : Syntax)
                            : CommandElabM ScriptCfg := do
  let mut result : ScriptCfg := {
    intro := [],
    clear := [],
    strategy := false
  }
  let mut assigned : List String := []
  for item in cfg.getArgs[1]!.getArgs do
    if item.isAtom then continue
    let some key := (collectIdentNames item).head? | throwErrorAt item "invalid script config field"
    if assigned.contains key then throwErrorAt item m!"duplicate script config field `{key}`"
    assigned := key :: assigned
    let atoms := collectAtomValues item
    let names := (collectIdentNames item).drop 1
    match key with
    | "intro" | "clear" =>
        unless atoms.contains "[" do
          throwErrorAt item m!"script config `{key}` requires a list of identifiers"
        if key == "intro" then result := { result with intro := names }
        else result := { result with clear := names }
    | "strategy" =>
        unless atoms.contains "true" || atoms.contains "false" do
          throwErrorAt item "script config `strategy` requires true or false"
        result := { result with strategy := atoms.contains "true" }
    | "params" =>
        let list := item[2][0][1].getArgs
        let mut parsed := []
        for entry in list do
          if entry.isAtom then continue
          let param ← parseParamCfg entry
          if parsed.any (·.1 == param.1) then
            throwErrorAt entry "duplicate parameter configuration `{param.1}`"
          parsed := parsed ++ [param]
        result := { result with params := parsed }
    | "continuation" =>
        let some index := item[2].reprint.bind String.toNat?
          | throwErrorAt item "continuation requires a natural-number goal index"
        result := { result with continuation := some index }
    | _ => throwErrorAt item m!"unknown script config field `{key}`"
  pure result

/-- 在生成入口前检查参数、codec 适用性和最终输出字段。 -/
private def validateCfgParams (name : String)
                              (cfg : ScriptCfg)
                              (args : Array (TSyntax ``macroArg))
                              : CommandElabM Unit := do
  let paramNames : List String := (args.filterMap fun
    | `(macroArg| $id:ident:$_) => some id.getId.toString
    | _ => none).toList
  for p in cfg.intro ++ cfg.clear ++ cfg.params.map (·.1) do
    unless paramNames.contains p do
      throwError m!"[script config] '{name}': 配置里的参数 '{p}' 不在 syntax 参数 {paramNames} 中"
  if !cfg.strategy && cfg.continuation.isSome then
    throwError "[script config] continuation requires strategy := true"
  for p in cfg.intro do
    if cfg.clear.contains p then
      throwError "[script config] '{name}': `{p}` sets both intro and clear"
  for (p, opt) in cfg.params do
    if (cfg.intro.contains p || cfg.clear.contains p) && opt.timing.isSome then
      throwError "[script config] '{name}': `{p}` sets both intro/clear and timing"
    let arg? := args.find? fun arg => match arg with
      | `(macroArg| $id:ident:$_) => id.getId.toString == p
      | _ => false
    if let some arg := arg? then
      match arg with
      | `(macroArg| $_:ident:$stx) =>
        if let .ok parser := Recording.normalizeParam stx then
          if opt.codec != .default then
            match parser.shape with
            | .category _ => pure ()
            | _ => throwError "[script config] '{name}': explicit codec requires a single syntax parameter `{p}`"
          if parser.shape != .category `ident && opt.codec == .name then
            throwError "[script config] '{name}': name codec requires ident parameter `{p}`"
          if (parser.shape != .category `term && parser.shape != .category `ident) &&
              (opt.codec == .typeOf || opt.codec == .expression) then
            throwError "[script config] '{name}': expression codec requires a single term/ident parameter `{p}`"
      | _ => pure ()
    if opt.field == some "" then
      throwError "[script config] '{name}': output field for `{p}` must not be empty"
    if !cfg.strategy && opt.context != .main then
      throwError "[script config] '{name}': non-main context requires strategy := true"
  let fields := args.toList.filterMap fun (arg : TSyntax ``macroArg) => match arg with
    | `(macroArg| $id:ident:$stx) =>
      let pname := id.getId.toString
      let field := ((cfg.params.lookup pname).bind (·.field)).getD pname
      some (field, parameterTiming cfg pname ((Recording.normalizeParam stx).toOption.map (·.shape)))
    | _ => none
  let goalFields := if cfg.strategy then Recording.strategyGoalFields else Recording.goalFields
  if let .error message := Recording.validateOutputFields
      (goalFields.toList.map (fun field => (field.name, .once)) ++ fields) then
    throwError "[script config] '{name}': {message}"
  -- Full semantic schemas are available only for supported automatic codecs;
  -- unsupported registrations keep their existing delayed recorder diagnostic.
  if (← autoRecordingError name args (cfg.params.filterMap fun (name, opt) =>
      if opt.codec == .default then none else some name)).isNone then
    let emitted ← recordingFields args cfg
    if let .error message := Recording.validateOutputFields
        (emitted.toList.map fun field => (field.name, .once)) then
      throwError "[script config] '{name}': {message}"

private def registrationParameters (args : Array (TSyntax ``macroArg)) :
    Array (String × Recording.ParamParserSignature) :=
  (args.extract 1 args.size).filterMap fun arg =>
    match arg with
    | `(macroArg| $id:ident:$stx) => some (id.getId.toString, Recording.paramParserSignature stx)
    | _ => none

/-! ### `script_macro` / `script_elab` 命令 -/

/-- 提取策略名（首个字符串字面量）。 -/
private def extractName (args : Array Syntax)
                        : CommandElabM String := do
  match args[0]! with
  -- Parser atoms discard surrounding whitespace from syntax string literals.
  | `(macroArg| $s:str) => pure s.getString.trimAscii.toString
  | _ => throwError "script_macro/script_elab/script_recorder: 第一个参数必须是字符串字面量（策略名）"

private def addConfigFieldInfo (structureName : Name) (key : Syntax) : CommandElabM Unit := do
  if !key.isIdent then return
  Elab.addCompletionInfo <| .fieldId key key.getId {} structureName
  if let some projection := getProjFnForField? (← getEnv) structureName key.getId then
    Elab.addConstInfo key projection

/-- Configuration keys refer to their typed fields; enum spellings refer to the
actual constructors chosen by the config parser, including renamed spellings. -/
private def addScriptConfigInfo (cfg : Option (TSyntax ``scriptCfg)) : CommandElabM Unit := do
  unless (← Elab.getInfoState).enabled do return
  let some cfg := cfg | return
  for item in cfg.raw[1].getArgs do
    if item.isAtom then continue
    addConfigFieldInfo ``ScriptCfg item[0]
    if item[0].getId == `strategy then
      if let some token := findFirstAtom item[2] then
        let constant := if token.getAtomVal == "true" then ``Bool.true else ``Bool.false
        Elab.addConstInfo token constant
    if item[0].getId != `params then continue
    for entry in item[2][0][1].getArgs do
      if entry.isAtom then continue
      for option in entry[1][1].getArgs do
        if option.isAtom then continue
        addConfigFieldInfo ``ParamCfg option[0]
        let value := option[2]
        if !value.isIdent then continue
        let constant? := match option[0].getId, value.getId with
          | `timing, `once => some ``Recording.CaptureTiming.once
          | `timing, `before => some ``Recording.CaptureTiming.before
          | `timing, `after => some ``Recording.CaptureTiming.after
          | `timing, `both => some ``Recording.CaptureTiming.both
          | `codec, `default => some ``Recording.ParamCodec.default
          | `codec, `expression => some ``Recording.ParamCodec.expression
          | `codec, `typeOf => some ``Recording.ParamCodec.typeOf
          | `codec, `name => some ``Recording.ParamCodec.name
          | `codec, `syntax => some ``Recording.ParamCodec.syntax
          | `context, `main => some ``Recording.ContextSelector.main
          | `context, `continuation => some ``Recording.ContextSelector.continuation
          | `failure, `required => some ``Recording.FailurePolicy.required
          | `failure, `bestEffort => some ``Recording.FailurePolicy.bestEffort
          | _, _ => none
        if let some constant := constant? then Elab.addConstInfo value constant

private partial def configIdents (stx : Syntax) : Array Syntax :=
  if stx.isIdent then #[stx]
  else stx.getArgs.flatMap configIdents

/-- Keep config identifiers as ordinary references to the generated rule's
pattern variables. Lean then records their exact binding, context and source
span alongside references in the user-written body. No config is evaluated. -/
private def withConfigReferences (cfg : Option (TSyntax ``scriptCfg))
    (body : TSyntax `term) : CommandElabM (TSyntax `term) := do
  let some cfg := cfg | return body
  let mut references : Array Syntax := #[]
  for item in cfg.raw[1].getArgs do
    if item.isAtom then continue
    match item[0].getId with
    | `intro | `clear =>
      references := references ++ configIdents item[2]
    | `params =>
      for entry in item[2][0][1].getArgs do
        if !entry.isAtom && entry[0].isIdent then
          references := references.push entry[0]
    | _ => pure ()
  let mut body := body
  for reference in references.reverse do
    let id : TSyntax `ident := ⟨reference⟩
    body ← `(let _ := $id:ident; $body)
  return body

open Lean.Elab.Command in
elab_rules : command
  | `(command| $[$doc?:docComment]? script_macro%$_tk $id:ident $[$cfg:scriptCfg]? $args:macroArg* => $rhs) => do
    addScriptConfigInfo cfg
    let tacticCat : TSyntax `ident := ⟨mkIdent `tactic⟩
    let name ← extractName args
    let cfg' ← match cfg with
      | some c => parseScriptCfg c
      | none => pure emptyScriptCfg
    validateCfgParams name cfg' args
    let (stxParts, _) := (← args.mapM expandMacroArg).unzip
    let stxParts := stxParts.map fun s => ⟨scriptKeywords s.raw⟩
    let kind ← elabSyntax (← `(syntax $[$stxParts]* : scriptTactic))
    let prefixedArgs : Array (TSyntax ``macroArg) := args.mapIdx fun i a => if i == 0 then (⟨mkScriptNameArg name⟩ : TSyntax ``macroArg) else a
    let (prefixedParts, prefixedPatArgs) := (← prefixedArgs.mapM expandMacroArg).unzip
    let prefixedKind ← elabSyntax (← `(syntax $[$prefixedParts]* : $tacticCat))
    let prefixedPat : TSyntax `term := ⟨mkNode prefixedKind prefixedPatArgs⟩
    let rhsRaw := rhs.raw
    let rhsTerm ←
      if rhsRaw.getArgs.size == 1 then
        pure (⟨rhsRaw[0]⟩ : TSyntax `term)
      else
        let rhsBody := ⟨rhsRaw[1]⟩
        `(`($rhsBody))
    let rhsTerm ← withConfigReferences cfg rhsTerm
    let rhsTerm ← `(ProofScript.withScriptMacroInfo $(quote kind) $rhsTerm)
    let macroRulesCmd ← `(macro_rules | `($prefixedPat) => $rhsTerm)
    -- The generated name is prefixed, so this cannot shadow Lean's native
    -- tactic even when `name` itself is a native tactic.
    elabCommand macroRulesCmd
    let autoError ← autoRecordingError name args (cfg'.params.filterMap fun (n, c) =>
      if c.codec != .default then some n else none)
    let recordingKind ← if autoError.isNone then
      some <$> genRecording ("script_" ++ name) args cfg'
    else pure none
    let recordedFields ← if autoError.isNone then some <$> recordingFields args cfg' else pure none
    let registrationId ← validateRegistrationId id
    registerTacticRegistration {
      ruleId := registrationId,
      name := name
      sourceKind := kind
      executionKind := prefixedKind
      recordingKind := recordingKind
      autoRecordingError := autoError
      «strategy» := cfg'.strategy
      continuation := cfg'.continuation
      recordedFields
      parameters := registrationParameters args
    }
    addRegistrationInfo id kind args doc?

open Lean.Elab.Command in
elab_rules : command
  | `(command| $[$doc?:docComment]? script_elab%$_tk $id:ident $[$cfg:scriptCfg]? $args:macroArg* => $rhs) => do
    addScriptConfigInfo cfg
    let tacticCat : TSyntax `ident := ⟨mkIdent `tactic⟩
    let name ← extractName args
    let cfg' ← match cfg with
      | some c => parseScriptCfg c
      | none => pure emptyScriptCfg
    validateCfgParams name cfg' args
    -- 定义仅带 `script_` 前缀的执行版 elaborator。
    let (stxParts, _) := (← args.mapM expandMacroArg).unzip
    let stxParts := stxParts.map fun s => ⟨scriptKeywords s.raw⟩
    let kind ← elabSyntax (← `(syntax $[$stxParts]* : scriptTactic))
    let prefixedArgs : Array (TSyntax ``macroArg) := args.mapIdx fun i a => if i == 0 then (⟨mkScriptNameArg name⟩ : TSyntax ``macroArg) else a
    let (prefixedParts, prefixedPatArgs) := (← prefixedArgs.mapM expandMacroArg).unzip
    let prefixedKind ← elabSyntax (← `(syntax $[$prefixedParts]* : $tacticCat))
    let prefixedPat : TSyntax `term := ⟨mkNode prefixedKind prefixedPatArgs⟩
    let rhs ← withConfigReferences cfg rhs
    elabCommand (← `(elab_rules : $tacticCat | `($prefixedPat) => ProofScript.withScriptExecutionInfo $(quote kind) $rhs))
    let autoError ← autoRecordingError name args (cfg'.params.filterMap fun (n, c) =>
      if c.codec != .default then some n else none)
    let recordingKind ← if autoError.isNone then
      some <$> genRecording ("script_" ++ name) args cfg'
    else pure none
    let recordedFields ← if autoError.isNone then some <$> recordingFields args cfg' else pure none
    let registrationId ← validateRegistrationId id
    registerTacticRegistration {
      ruleId := registrationId,
      name := name
      sourceKind := kind
      executionKind := prefixedKind
      recordingKind := recordingKind
      autoRecordingError := autoError
      «strategy» := cfg'.strategy
      continuation := cfg'.continuation
      recordedFields
      parameters := registrationParameters args
    }
    addRegistrationInfo id kind args doc?

open Lean.Elab.Command in
elab_rules : command
  | `(command| $[$doc?:docComment]? script_recorder%$_tk $id:ident $[$cfg:scriptRecorderCfg]? $args:macroArg* => $rhs) => do
    let tacticCat : TSyntax `ident := ⟨mkIdent `tactic⟩
    let name ← extractName args
    let fields ← match cfg with
      | none => pure none
      | some cfg =>
        let `(scriptRecorderCfg| (fields := $fields:term)) := cfg | throwErrorAt cfg "invalid recorder fields"
        let fields ← Recording.evalOutputFields fields
        if let .error message := Recording.validateOutputFields
            (fields.toList.map fun field => (field.name, .once)) then
          throwErrorAt cfg "{message}"
        pure (some fields)
    let ruleId ← validateRecorderRegistration id.getId.eraseMacroScopes name (registrationParameters args)
    let some registration := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == ruleId)
      | throwErrorAt id "unknown script registration `{ruleId}`"
    Elab.addConstInfo id.raw registration.sourceKind
    if let some first := args.toList.head? then
      if let `(macroArg| $keyword:str) := first then
        Elab.addConstInfo keyword.raw registration.sourceKind
    let recArgs : Array (TSyntax ``macroArg) := args.mapIdx fun i a =>
      if i == 0 then (⟨mkNameArg ("script_" ++ name)⟩ : TSyntax ``macroArg) else a
    let (recParts, recPatArgs) := (← recArgs.mapM expandMacroArg).unzip
    let recKind ← elabSyntax (← `(syntax $[$recParts]* : $tacticCat))
    let recPat : TSyntax `term := ⟨mkNode recKind recPatArgs⟩
    elabCommand (← `(elab_rules : $tacticCat | `($recPat) => $rhs))
    modifyEnv fun env => scriptRegistrationExt.addEntry env (.setRecorder ruleId recKind fields)

end ProofScript
