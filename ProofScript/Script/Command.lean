import Lean.Elab.Command
import Lean.Elab.Tactic
import Lean.Parser.Term
import ProofScript.Utils.Linter
import ProofScript.Utils.Syntax
import ProofScript.Script.Recording
import ProofScript.Script.Recording.Binding
import ProofScript.Script.Registry

open Lean
open Parser (atomic sepBy termParser nonReservedSymbol)
open Parser.Term (ident doSeqItem doSeqIndent)
open Parser.Command (macroArg macroRhs docComment)
open Elab.Command (CommandElabM elabCommand liftIO expandMacroArg elabSyntax)


namespace ProofScript

/-! All generated script tactic declarations share this category.  It belongs
    here because `script_macro` and `script_elab` create syntax in it while
    elaborating their declarations; `Script.lean` consumes the same category
    for `run_script_step` after importing this module. -/
declare_syntax_cat scriptTactic (behavior := both)

/-! The declaration-time configuration parser lives next to the `elab` commands.
    Keeping these parser combinators in this module lets Lean compile the generated
    command parsers without importing parser declarations from `Syntax.lean`. -/

/-! Configuration values are syntax-level data. Identifier lists are kept as
    identifiers rather than elaborated terms so config references can later be
    attached to the generated rule body. -/
def scriptCfgIdents := leading_parser "[" >> sepBy ident ", " >> "]"

def scriptCfgBool := leading_parser nonReservedSymbol "true" <|> nonReservedSymbol "false"

/-! A continuation is a quoted Lean name (for example ``continuation := `rest``). -/
def scriptCfgName := leading_parser termParser

def scriptCfgValue := leading_parser
  atomic scriptCfgIdents <|> scriptCfgBool <|> scriptCfgName

def scriptCfgItem := leading_parser ident >> ":=" >> scriptCfgValue

def scriptCfg := leading_parser
  "(" >> sepBy scriptCfgItem ", " >> ")"

/-- Prefixed execution entries retain the same editor identity as script calls. -/
def withScriptExecutionInfo (kind : Name) (action : Elab.Tactic.TacticM α) : Elab.Tactic.TacticM α := do
  if let some keyword := findFirstAtom (← getRef) then
    Elab.addConstInfo keyword kind
  action

elab (name := scriptMacroInfo) "_script_macro_info%" kind:ident source:term "=>" expanded:tactic : tactic => do
  if let some keyword := findFirstAtom source.raw then
    Elab.addConstInfo keyword kind.getId
  Elab.Tactic.evalTactic expanded

/-- Attach invocation info when a registered macro is called through its prefixed
entry, preserving the original token instead of manufacturing a source span. -/
def withScriptMacroInfo (kind : Name) (action : MacroM Syntax) : MacroM Syntax := do
  let source ← getRef
  let expanded ← action
  return mkNode ``scriptMacroInfo #[mkAtom "_script_macro_info%", mkIdent kind, source,
    mkAtom "=>", expanded]

/-! ### 语法级辅助：从 `macroArg` 节点构造录制版 elab（纯 antiquotation，不经字符串） -/

private def validateRegistrationId (id : TSyntax `ident) : CommandElabM Name := do
  return removeRoot id.getId.eraseMacroScopes

/-- Check only the parameter readers used by this automatic recorder. -/
private def validateAutoRecording (name : String) (args : Array (TSyntax ``macroArg))
    (isStrategy : Bool) (config : AutoRecordingConfig) : CommandElabM Unit := do
  for arg in args[1:] do
    if let `(macroArg| $id:ident:$stx) := arg then
      if isStrategy && config.intro.contains id.getId.eraseMacroScopes then continue
      let inputType ← match ← paramBindingTypeTerm stx with
        | .ok type => pure type
        | .error msg => throwErrorAt id m!"[script recorder] '{name}': 参数 '{id.getId}' {msg}"
      let type ← `(term| ProofScript.RecordValue $inputType:term)
      let available ← Elab.Command.withScope
          (fun scope => { scope with openDecls := OpenDecl.simple `ProofScript.ParamRecorder [] :: scope.openDecls }) do
        Lean.Elab.Command.liftTermElabM do
          Lean.pushScope
          try
            Lean.activateScoped `ProofScript.ParamRecorder
            let type ← Lean.Elab.Term.elabTerm type none
            match ← Lean.Meta.trySynthInstance type with
            | .some _ => return true
            | _ => return false
          finally
            Lean.popScope
      unless available do
        throwErrorAt id m!"[script recorder] '{name}': 参数 '{id.getId}' 缺少 RecordValue 实例"

open Lean.Parser.Syntax in
/-- 从完整策略名构造 `macroArg`（str 字面量，含引号）。 -/
def mkRawNameArg (name : String) : Syntax :=
  mkNode ``macroArg #[
    mkNullNode,
    mkNode ``atom #[mkNode `str #[Lean.mkAtom ("\"" ++ name ++ "\"")]]
  ]

def mkNameArg (name : String) : Syntax := mkRawNameArg ("_" ++ name)

def mkScriptNameArg (name : String) : Syntax := mkRawNameArg ("script_" ++ name)

private def recorderStrategyBinder : TSyntax `ident :=
  ⟨mkIdent `__proofScript_strategyCases⟩

/-- Replace only the strategy keyword and append the synthetic strategy payload
    used by the recording-call rewriter.  The user's declaration never needs to
    mention either synthetic argument. -/
private def recorderArguments (syntaxName : String)
    (args : Array (TSyntax ``macroArg)) (isStrategy : Bool) : CommandElabM (Array (TSyntax ``macroArg)) := do
  let mut recArgs := args.mapIdx fun i a =>
    if i == 0 then ⟨mkNameArg syntaxName⟩ else a
  if isStrategy then
    recArgs := recArgs.push (← `(macroArg| "_strategy_cases"))
    recArgs := recArgs.push (← `(macroArg| $recorderStrategyBinder:ident:str))
  return recArgs

/-- Install the hidden strategy payload as a scoped value before evaluating a
    recorder body.  This is shared by automatic and handwritten recorders. -/
private def recorderBody (rhs : TSyntax `term) (isStrategy : Bool) : CommandElabM (TSyntax `term) := do
  if isStrategy then
    `(term| ProofScript.withRecordingStrategyNodes
      ($recorderStrategyBinder:ident).getString $rhs)
  else
    pure rhs

private def executeKind (stx : Syntax) : Bool :=
  stx.getKind == ``doElemExecute || stx.getKind == ``doElemExecuteInit ||
    stx.getKind == `ProofScript.«doElemExecute(Label:=_)»

/-- Macro quotations carry quoted syntax, not a live invocation of a recorder. -/
private partial def nestedExecute? (stx : Syntax) : Option Syntax :=
  if stx.getKind == `Lean.Parser.Term.quoted then none
  else if executeKind stx then some stx
  else stx.getArgs.findSome? nestedExecute?

/-- Restrict delegation to one direct statement in the outer do block. -/
private def selectedExecute (rhs : TSyntax `term) : CommandElabM Syntax := do
  let `(term| do $seq:doSeq) := rhs
    | throwErrorAt rhs "script_recorder body must be a `do` block"
  let items := seq.raw[0].getArgs
  let mut selected : Option Syntax := none
  for item in items do
    let elem := item[0]
    if executeKind elem then
      if selected.isSome then throwErrorAt elem "script_recorder requires exactly one top-level `execute`"
      selected := some elem
    else if let some nested := nestedExecute? elem then
      throwErrorAt nested "`execute` must be a direct statement of the outer recorder `do` block"
  let some result := selected
    | throwErrorAt rhs "script_recorder requires exactly one top-level `execute`"
  return result

private def recorderSelection (registration : ScriptTacticRegistration)
    (selected : Syntax) : CommandElabM Name := do
  if selected.getKind == ``doElemExecuteInit then
    return registration.recorders[0]!.kind
  if selected.getKind == `ProofScript.«doElemExecute(Label:=_)» then
    let label := (⟨selected[4]⟩ : TSyntax `str).getString
    let some version := registration.recorders.find? (·.label == some label)
      | throwErrorAt selected m!"unknown recorder label `{label}` for `{registration.ruleId}`"
    return version.kind
  let some version := registration.recorders.back?
    | throwErrorAt selected m!"script registration `{registration.ruleId}` has no initial recorder"
  return version.kind

/-- Generate one entry and one directly callable body from the same raw parser
    pattern. The body takes the actual invocation and the shared recording step. -/
private def generateRecorderEntry
    (recArgs : Array (TSyntax ``macroArg)) (isStrategy : Bool) (ruleId sourceKind : Name)
    (rhs : TSyntax `term) (predecessor : String × String × Name × Bool)
    (previousBody : Option Name := none) (isInitial : Bool := false) : CommandElabM (Name × Name) := do
  let tacticCat : TSyntax `ident := ⟨mkIdent `tactic⟩
  let `(term| do $_:doSeq) := rhs
    | throwError "script_recorder body must be a `do` block"
  let (recParts, recPatArgs) := (← recArgs.mapM expandMacroArg).unzip
  let recKind ← elabSyntax (← `(syntax $[$recParts]* : $tacticCat))
  let recPat : TSyntax `term := ⟨mkNode recKind recPatArgs⟩
  let recKindId : TSyntax `ident := ⟨mkIdent recKind⟩
  let bodyId : TSyntax `ident := ⟨mkIdent (recorderBodyName recKind)⟩
  let (sourceName, targetName, targetKind, isRecorder) := predecessor
  let previous ← match previousBody with
    | some previousBody =>
      let previousId : TSyntax `ident := ⟨mkIdent previousBody⟩
      `(term| (ProofScript.recorderPredecessorCall call
        $(quote sourceName) $(quote targetName) $(quote targetKind)
         $(quote isRecorder) $(quote isStrategy)) >>= fun previousCall =>
          $previousId previousCall step)
    | none =>
      `(term| do
        let execution ← ProofScript.recorderPredecessorCall call
          $(quote sourceName) $(quote targetName) $(quote targetKind)
           $(quote isRecorder) $(quote isStrategy)
        Lean.Elab.Tactic.evalTactic execution)
  let body ← `(term| do
    letI : ProofScript.RecorderPredecessor := ⟨$previous⟩
    $rhs)
  let body ← if isInitial then `(term| do
      step.markInitialExecuted
      $body:term)
    else pure body
  let bodyCmd ← `(command| def $bodyId (call : Syntax) (step : ProofScript.RecordingStep) : Elab.Tactic.TacticM Unit := do
    match (⟨call⟩ : TSyntax `tactic) with
    | `($recPat) =>
      letI : ProofScript.RecordingStep := step
      $body
    | _ => throwError "invalid recorder call of kind `{call.getKind}`; expected `{$(quote recKind)}`")
  elabCommand (eraseMacroScopes bodyCmd.raw)
  let invokeBody ← `(term| $bodyId call step)
  let prepare ← `(term| do
    let nodes ← ProofScript.recordingStrategyNodes
    let config ← ProofScript.currentRecordingConfig
    ProofScript.withPreparedStrategyBranches step $invokeBody
      (ProofScript.resolveStrategyContexts nodes (config.bind (·.continuation))))
  let entry ← if isStrategy then
      `(term| Lean.Elab.Tactic.withMainContext <| do
        let call ← getRef
        ProofScript.withRecordingStep fun step => $prepare)
    else
      `(term| Lean.Elab.Tactic.withMainContext <| do
        let call ← getRef
        ProofScript.withRecordingStep fun step => $invokeBody)
  let entry ← recorderBody entry isStrategy
  let entry ← `(term| ProofScript.withRecordingRule $(quote ruleId) <| do
    if let some keyword := ProofScript.findFirstAtom (← getRef) then
      Lean.Elab.addConstInfo keyword $(quote sourceKind)
    Lean.Elab.Tactic.withTacticInfoContext (← getRef) $entry)
  let recCmd ← `(command| elab_rules (kind := $recKindId) : $tacticCat | `($recPat) => $entry)
  elabCommand (eraseMacroScopes recCmd.raw)
  return (recKind, bodyId.getId)

/-- Script keywords must not reserve identifiers in native terms and tactics. -/
private partial def scriptKeywords (stx : Syntax) : Syntax :=
  if stx.getKind == ``Parser.Syntax.atom then
    mkNode ``Parser.Syntax.nonReserved #[mkAtom "&", stx[0]]
  else
    stx.modifyArgs (·.map scriptKeywords)

private def registerTacticRegistration (registration : ScriptTacticRegistration) :
    CommandElabM Unit := do
  let ruleId := registration.ruleId
  if ruleId == unrecordedRuleId then
    throwError m!"reserved script registration ID `{ruleId}`"
  if (scriptTacticRegistrations (← getEnv)).any (fun r => r.ruleId == ruleId) then
    throwError m!"duplicate script registration ID `{ruleId}`; give each overload a distinct explicit ID"
  let registration := { registration with ruleId }
  if registration.config.isMetadata then
    Lean.Elab.Command.allowUnusedTacticKinds <|
      #[registration.executionKind] ++ registration.recordingKind.toArray
  modifyEnv fun env => scriptRegistrationExt.addEntry env (.register registration)

/-- A rule's existing parser declaration is also its editor symbol. Registration
IDs need not be Lean declaration names and may collide with ordinary constants. -/
private def addRegistrationInfo (id : TSyntax `ident) (kind : Name)
    (doc? : Option (TSyntax ``docComment)) : CommandElabM Unit := do
  Elab.addDeclarationRangesFromSyntax kind (← getRef) id.raw
  let documentation ← match doc? with
    | some doc => getDocStringText doc
    | none => pure s!"ProofScript script registration `{id.getId.eraseMacroScopes}`."
  addDocStringCore kind documentation
  Elab.Command.liftTermElabM do
    Elab.Term.addTermInfo' id.raw (← mkConstWithLevelParams kind) (isBinder := true)

/-! An unqualified recorder ID belongs to this module; a qualified ID explicitly
    extends a registration imported from another module. The signature always
    comes from the original registration. -/
private def validateRecorderRegistration (id : TSyntax `ident) : CommandElabM
    (Name × ScriptTacticRegistration) := do
  let ruleId := removeRoot id.getId.eraseMacroScopes
  let registration ← match scriptRegistrationForRecorder (← getEnv) ruleId with
    | .ok registration => pure registration
    | .error message => throwError "{message}"
  return (ruleId, registration)

/-- Parse and validate the single declaration-time recording configuration. -/
private def quotedName? (stx : Syntax) : Option Name :=
  let candidate := if stx.getKind == ``Parser.Term.quotedName then some stx else
    stx.getArgs[0]?.bind fun outer =>
      if outer.getKind == ``Parser.Term.quotedName then some outer else outer.getArgs[0]?
  match candidate with
  | some candidate =>
      let text := (candidate.reprint.getD "").trimAscii.toString
      if !text.startsWith "`" then none
      else
        let text := (text.drop 1).toString
        let parts : List String := text.splitOn "."
        if text.isEmpty || parts.any String.isEmpty then none
        else some <| List.foldl (fun acc part => Name.str acc part) Name.anonymous parts
  | none => none

private def parseScriptCfg (cfg : Syntax) : CommandElabM ScriptRecordingConfig := do
  let mut result : ScriptRecordingConfig := {}
  let mut assigned : List String := []
  for item in cfg.getArgs[1]!.getArgs do
    if item.isAtom then continue
    let some key := (collectIdentNames item).head? | throwErrorAt item "invalid script config field"
    if assigned.contains key then
      throwErrorAt item m!"duplicate script config field `{key}`"
    assigned := key :: assigned
    match key with
    | "intro" | "clear" =>
        throwErrorAt item "`intro` and `clear` belong to `script_recorder <id> auto`"
    | "kind" =>
        let names := collectIdentNames item
        let kind ← if names.contains "tactic" then pure .tactic
          else if names.contains "strategy" then pure .strategy
          else if names.contains "metadata" then pure .metadata
          else throwErrorAt item "script config `kind` requires tactic, strategy, or metadata"
        result := { result with kind }
    | "continuation" =>
        let some name := quotedName? item[2]
          | throwErrorAt item "continuation requires a quoted Lean name such as `rest"
        result := { result with continuation := some name }
    | _ => throwErrorAt item m!"unknown script config field `{key}`"
  return result

private def duplicateNames (names : Array Name) : Option Name := Id.run do
  let mut seen : List Name := []
  for name in names do
    if seen.contains name then return some name
    seen := name :: seen
  return none

/-- Check configuration references against the original named macro arguments. -/
private def validateCfgParams (name : String) (cfg : ScriptRecordingConfig)
    (args : Array (TSyntax ``macroArg)) : CommandElabM Unit := do
  for arg in args do
    if let `(macroArg| $id:ident:$_) := arg then
      let parameter := id.getId.eraseMacroScopes.toString (escape := false)
      if parameter.startsWith "$" then
        throwErrorAt id m!"[script config] '{name}': invalid parameter name `{parameter}`: field names starting with `$` are reserved"
  if !cfg.isStrategy && cfg.continuation.isSome then
    throwError "[script config] continuation requires kind := strategy"

private def parseAutoCfg (cfg : Option (TSyntax ``scriptCfg))
    (registration : ScriptTacticRegistration) : CommandElabM AutoRecordingConfig := do
  let mut result : AutoRecordingConfig := {}
  let mut assigned : List String := []
  let some cfg := cfg | return result
  for item in cfg.raw[1].getArgs do
    if item.isAtom then continue
    let some key := (collectIdentNames item).head?
      | throwErrorAt item "invalid auto recorder config field"
    if assigned.contains key then
      throwErrorAt item m!"duplicate auto recorder config field `{key}`"
    assigned := key :: assigned
    unless key == "intro" || key == "clear" do
      throwErrorAt item m!"unknown auto recorder config field `{key}`"
    unless collectAtomValues item |>.contains "[" do
      throwErrorAt item m!"auto recorder config `{key}` requires a list of identifiers"
    let names := (collectIdentNames item).drop 1 |>.toArray.map Name.mkSimple
    match key with
    | "intro" => result := { result with intro := names }
    | "clear" => result := { result with clear := names }
    | _ => pure ()
  let paramNames : Array Name := registration.arguments.filterMap fun
    | `(macroArg| $id:ident:$_) => some id.getId.eraseMacroScopes
    | _ => none
  for (field, configured) in [("intro", result.intro), ("clear", result.clear)] do
    for p in configured do
      unless paramNames.contains p do
        throwError m!"[script recorder] '{registration.name}': 参数 '{p}' 不在 syntax 参数中"
    if let some duplicate := duplicateNames configured then
      throwError m!"[script recorder] '{registration.name}': `{field}` 中重复配置参数 `{duplicate}`"
  if let some duplicate := result.intro.find? (result.clear.contains ·) then
    throwError m!"[script recorder] '{registration.name}': `{duplicate}` sets both intro and clear"
  if registration.config.isStrategy && assigned.contains "clear" then
    throwError "[script recorder] strategy automatic recording cannot specify clear"
  return result

/-- Version zero executes the script and records its identity and monotonic timestamps. -/
private def genInitialRecording (name : String) (executionKind ruleId sourceKind : Name)
    (args : Array (TSyntax ``macroArg)) (cfg : ScriptRecordingConfig) : CommandElabM Name := do
  let recArgs ← recorderArguments ("script_" ++ name) args cfg.isStrategy
  let rhs ← `(term| do
    record_value "$ruleId" $(quote ruleId.toString)
    record_value "$time_before" (← IO.monoNanosNow)
    execute
    record_value "$time_after" (← IO.monoNanosNow))
  let (kind, _) ← generateRecorderEntry recArgs cfg.isStrategy ruleId sourceKind rhs
    ("_script_" ++ name, "script_" ++ name, executionKind, false) none true
  return kind

/-- Build the body of an explicitly requested automatic recorder. -/
private def autoRecorderBody (registration : ScriptTacticRegistration)
    (cfg : AutoRecordingConfig) : CommandElabM (TSyntax `term) := do
  let mut beforeRecords : Array (TSyntax `doElem) := #[]
  let mut afterRecords : Array (TSyntax `doElem) := #[]
  for arg in registration.arguments[1:] do
    if let `(macroArg| $id:ident:$_) := arg then
      let pname := id.getId.eraseMacroScopes
      if registration.config.isStrategy && cfg.intro.contains pname then continue
      let beforeField := pname.toString ++ "_before"
      let afterField := pname.toString ++ "_after"
      let beforeRecord ← `(doElem| record_param $(quote beforeField) $id:ident)
      let afterRecord ← `(doElem| record_param $(quote afterField) $id:ident)
      if registration.config.isStrategy then
        beforeRecords := beforeRecords.push beforeRecord
      else if cfg.intro.contains pname then
        afterRecords := afterRecords.push afterRecord
      else if cfg.clear.contains pname then
        beforeRecords := beforeRecords.push beforeRecord
      else
        beforeRecords := beforeRecords.push beforeRecord
        afterRecords := afterRecords.push afterRecord
  let emptyRecord : TSyntax `doElem ← `(doElem| pure ())
  let beforeSeq : TSyntax ``doSeqIndent := ⟨mkDoSeq <|
    (if beforeRecords.isEmpty then #[emptyRecord] else beforeRecords).map (·.raw)⟩
  let afterSeq : TSyntax ``doSeqIndent := ⟨mkDoSeq <|
    (if afterRecords.isEmpty then #[emptyRecord] else afterRecords).map (·.raw)⟩
  if registration.config.isStrategy then
    `(term| do
      Lean.Elab.Tactic.withRollback do
        record_goal "$goal_before"
        record_context "$context_before"
        do $beforeSeq:doSeqIndent
      execute)
  else
    `(term| do
      Lean.Elab.Tactic.withRollback do
        record_goal "$goal_before"
        record_context "$context_before"
        do $beforeSeq:doSeqIndent
      execute
      Lean.Elab.Tactic.withRollback do
        record_goal "$goal_after"
        record_context "$context_after"
        do $afterSeq:doSeqIndent)

/-! ### `script_macro` / `script_elab` 命令 -/

/-- 提取策略名（首个字符串字面量）。 -/
private def extractName (args : Array Syntax)
                        : CommandElabM String := do
  match args[0]! with
  -- Parser atoms discard surrounding whitespace from syntax string literals.
  | `(macroArg| $s:str) => pure s.getString.trimAscii.toString
  | _ => throwError "script_macro/script_elab: 第一个参数必须是字符串字面量（策略名）"

private def addConfigFieldInfo (structureName : Name) (key : Syntax) : CommandElabM Unit := do
  if !key.isIdent then return
  Elab.addCompletionInfo <| .fieldId key key.getId {} structureName
  if let some projection := getProjFnForField? (← getEnv) structureName key.getId then
    Elab.addConstInfo key projection

/-- Configuration keys refer to the unified registration config fields. -/
private def addScriptConfigInfo (cfg : Option (TSyntax ``scriptCfg)) : CommandElabM Unit := do
  unless (← Elab.getInfoState).enabled do return
  let some cfg := cfg | return
  for item in cfg.raw[1].getArgs do
    if item.isAtom then continue
    addConfigFieldInfo ``ScriptRecordingConfig item[0]
    if item[0].getId == `kind then
      if let some token := findFirstAtom item[2] then
        let constant? := match token.getAtomVal with
          | "tactic" => some ``ScriptKind.tactic
          | "strategy" => some ``ScriptKind.strategy
          | "metadata" => some ``ScriptKind.metadata
          | _ => none
        if let some constant := constant? then Elab.addConstInfo token constant

elab doc?:(docComment)? "script_macro" id:ident
    cfg:(scriptCfg)? args:(macroArg)+ " => " rhs:macroRhs : command => do
  addScriptConfigInfo cfg
  let tacticCat : TSyntax `ident := ⟨mkIdent `tactic⟩
  let name ← extractName args
  let cfg' ← match cfg with
    | some c => parseScriptCfg c
    | none => pure {}
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
  let rhsTerm ← `(ProofScript.withScriptMacroInfo $(quote kind) $rhsTerm)
  let macroRulesCmd ← `(macro_rules | `($prefixedPat) => $rhsTerm)
  -- The generated name is prefixed, so this cannot shadow Lean's native
  -- tactic even when `name` itself is a native tactic.
  elabCommand macroRulesCmd
  let registrationId ← validateRegistrationId id
  let ruleId := registrationId
  let initialKind ← genInitialRecording name prefixedKind ruleId kind args cfg'
  registerTacticRegistration {
    ruleId := registrationId,
    name := name
    sourceKind := kind
    executionKind := prefixedKind
    recorders := #[{ kind := initialKind }]
    config := cfg'
    arguments := args
  }
  addRegistrationInfo id kind doc?

elab doc?:(docComment)? "script_elab" id:ident
    cfg:(scriptCfg)? args:(macroArg)+ " => " rhs:term : command =>
  Lean.Elab.Command.withoutUnusedVariableLint do
  addScriptConfigInfo cfg
  let tacticCat : TSyntax `ident := ⟨mkIdent `tactic⟩
  let name ← extractName args
  let cfg' ← match cfg with
    | some c => parseScriptCfg c
    | none => pure {}
  validateCfgParams name cfg' args
  -- 定义仅带 `script_` 前缀的执行版 elaborator。
  let (stxParts, _) := (← args.mapM expandMacroArg).unzip
  let stxParts := stxParts.map fun s => ⟨scriptKeywords s.raw⟩
  let kind ← elabSyntax (← `(syntax $[$stxParts]* : scriptTactic))
  let prefixedArgs : Array (TSyntax ``macroArg) := args.mapIdx fun i a => if i == 0 then (⟨mkScriptNameArg name⟩ : TSyntax ``macroArg) else a
  let (prefixedParts, prefixedPatArgs) := (← prefixedArgs.mapM expandMacroArg).unzip
  let prefixedKind ← elabSyntax (← `(syntax $[$prefixedParts]* : $tacticCat))
  let prefixedPat : TSyntax `term := ⟨mkNode prefixedKind prefixedPatArgs⟩
  elabCommand (← `(set_option linter.unusedVariables false in
    elab_rules : $tacticCat | `($prefixedPat) => ProofScript.withScriptExecutionInfo $(quote kind) $rhs))
  let registrationId ← validateRegistrationId id
  let ruleId := registrationId
  let initialKind ← genInitialRecording name prefixedKind ruleId kind args cfg'
  registerTacticRegistration {
    ruleId := registrationId,
    name := name
    sourceKind := kind
    executionKind := prefixedKind
    recorders := #[{ kind := initialKind }]
    config := cfg'
    arguments := args
  }
  addRegistrationInfo id kind doc?

elab _doc?:(docComment)? "script_recorder" id:ident
    label:("(" &"label" " := " str ")")?
    " => " rhs:term : command => do
  let (ruleId, registration) ← validateRecorderRegistration id
  Elab.addConstInfo id.raw registration.sourceKind
  if let some first := registration.arguments.toList.head? then
    if let `(macroArg| $keyword:str) := first then
      Elab.addConstInfo keyword.raw registration.sourceKind
  let recArgs ← recorderArguments ("script_" ++ registration.name)
    registration.arguments registration.config.isStrategy
  let labelSyntax := (← getRef)[3]
  let label := if labelSyntax.getArgs.isEmpty then none
    else some (⟨labelSyntax[3]⟩ : TSyntax `str).getString
  if let some value := label then
    if value.isEmpty then throwErrorAt id "recorder label must not be empty"
    if registration.recorders.any (·.label == some value) then
      throwErrorAt id m!"duplicate recorder label `{value}` for `{ruleId}`"
  let selected ← selectedExecute rhs
  let parentKind ← recorderSelection registration selected
  let predecessor := ("_script_" ++ registration.name, "_script_" ++ registration.name,
    parentKind, true)
  let inheritedBody := some (recorderBodyName parentKind)
  let (recKind, _) ← generateRecorderEntry recArgs registration.config.isStrategy ruleId
    registration.sourceKind rhs predecessor inheritedBody
  modifyEnv fun env =>
    scriptRegistrationExt.addEntry env (.addRecorder ruleId { kind := recKind, label })

/-- Automatic recording is an ordinary recorder declaration with a generated body. -/
elab "script_recorder" id:ident
    label:("(" &"label" " := " str ")")?
    " auto " cfg:(scriptCfg)? : command => do
  let (_, registration) ← validateRecorderRegistration id
  let autoCfg ← parseAutoCfg cfg registration
  validateAutoRecording registration.name registration.arguments
    registration.config.isStrategy autoCfg
  let body ← autoRecorderBody registration autoCfg
  let labelSyntax := (← getRef)[2]
  let declaration ← if labelSyntax.getArgs.isEmpty then
      `(command| script_recorder $id:ident => $body:term)
    else
      let labelValue : TSyntax `str := ⟨labelSyntax[3]⟩
      `(command| script_recorder $id:ident (label := $labelValue:str) => $body:term)
  elabCommand declaration

end ProofScript
