import ProofScript.Script.Script
import ProofScript.Script.ScriptDB
import ProofScript.Page.Path
import ProofScript.Page.State
import ProofScript.Page.Component.Core
import ProofScript.Render.Registry
import ProofScript.Lean2TeX.Registry

open Lean Parser Elab Command Tactic


namespace ProofScript

initialize projectInfoExt : SimplePersistentEnvExtension ProjectInfo (Option ProjectInfo) ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.projectInfo
    addEntryFn := fun _ info => some info
    addImportedFn := fun entries =>
      entries.foldl (init := none) fun previous entry =>
        match entry.toList.getLast? with
        | some info => some info
        | none => previous
  }

def getProjectInfo (env : Environment) : ProjectInfo :=
  (projectInfoExt.getState env).getD {}

syntax stringList := "[" sepBy(str, ", ") "]"
syntax projectInfoValue := str <|> stringList
syntax projectInfoField := ident " := " projectInfoValue
syntax (name := projectInfoCmd) "project_info" "{" sepBy1(projectInfoField, ", ") "}" : command

private def stringTermValue (value : Syntax) : CoreM String :=
  match value with
  | `(projectInfoValue| $text:str) => pure text.getString
  | _ => throwErrorAt value "expected a string literal"

private def stringListValue (value : Syntax) : CoreM (List String) :=
  match value with
  | `(projectInfoValue| $list:stringList) =>
      match list with
      | `(stringList| [$[$items:str],*]) => pure (items.toList.map (·.getString))
      | _ => throwErrorAt value "expected a list of string literals"
  | _ => throwErrorAt value "expected a list of string literals"

private def setProjectField (info : ProjectInfo) (key : String) (value : Syntax) : CoreM ProjectInfo := do
  match key with
  | "title" => return { info with title := ← stringTermValue value }
  | "authors" => return { info with authors := ← stringListValue value }
  | "keywords" => return { info with keywords := ← stringListValue value }
  | "description" => return { info with description := ← stringTermValue value }
  | "year" => return { info with year := ← stringTermValue value }
  | "base_url" => return { info with base_url := ← stringTermValue value }
  | "license" => return { info with license := ← stringTermValue value }
  | other => return { info with extra := info.extra ++ [(other, (← stringTermValue value))] }

elab_rules : command
  | `(command| project_info%$_token { $[$fields:projectInfoField],* }) => do
      let mut info : ProjectInfo := {}
      for field in fields do
        match field with
        | `(projectInfoField| $key:ident := $value:projectInfoValue) =>
            info ← liftCoreM <| setProjectField info key.getId.toString value.raw
        | _ => pure ()
      if (projectInfoExt.getState (← getEnv)).isSome then
        throwError "project_info may only be configured once"
      modifyEnv fun env => projectInfoExt.addEntry env info
      let moduleName ← getMainModule
      let path ← liftM <| activeOutputPath (projectInfoOutputPath moduleName)
      liftM do
        ensureParentDir path
        IO.FS.writeFile path (Json.mkObj [
          ("module", Json.str moduleName.toString), ("ProjectInfo", toJson info)]).pretty


/-! ## `theorem_info` -/

syntax theoremInfoEntry := ident " := " projectInfoValue
syntax (name := theoremInfoCmd) "theorem_info" ident
  (ppSpace "{" sepBy1(theoremInfoEntry, ", ") "}")? : command

private def theoremInfoEntryToPair (entry : Syntax) : Option (String × Syntax) :=
  match entry with
  | `(theoremInfoEntry| $key:ident := $value:projectInfoValue) =>
      some (key.getId.toString, value.raw)
  | _ => none

private def buildTheoremInfo (entries : List (String × Syntax)) : CoreM TheoremInfo := do
  let project := getProjectInfo (← getEnv)
  let mut name := ""
  let mut tags : List String := []
  let mut extra : List (String × String) := []
  for (key, value) in entries do
    match key with
    | "name" => name ← stringTermValue value
    | "tags" => tags ← stringListValue value
    | other => extra := extra ++ [(other, ← stringTermValue value)]
  return { project, name, tags, extra }

private def registerTheoremInfo (declarationId : TSyntax `ident)
    (entries : Array Syntax) : CommandElabM Unit := do
  let declaration ← resolveGlobalConstNoOverload declarationId.raw
  unless (← getEnv).contains declaration do
    throwErrorAt declarationId m!"unknown declaration '{declarationId.getId}'"
  let env ← getEnv
  if (findTheoremInfo env declaration).isSome then
    throwErrorAt declarationId m!"theorem_info for '{declarationId.getId}' is already registered"
  let info ← liftCoreM <| buildTheoremInfo (entries.toList.filterMap theoremInfoEntryToPair)
  setEnv (theoremInfoExt.insert env declaration info)

/-- Resolve presentation metadata only when the page is exported, after `theorem_info`. -/
def resolveTheoremComponents (env : Environment) (components : Array Component) : Array Component :=
  components.map fun component => Id.run do
    let some declaration := component.data.declaration | return component
    let info := findTheoremInfo env declaration
    let name := info.map (·.name) |>.filter (!·.isEmpty) |>.getD declaration.getString!
    let value := component.data.value
    let .ok proof := value.getObjVal? "proof" | return component
    let .ok sorryAx := value.getObjVal? "sorryAx" | return component
    return { component with data := { component.data with value := Json.mkObj [
      ("name", toJson name),
      ("proof", proof), ("sorryAx", sorryAx)] } }

elab_rules : command
  | `(command| theorem_info $declarationId:ident) =>
      registerTheoremInfo declarationId #[]
  | `(command| theorem_info $declarationId:ident { $[$entries:theoremInfoEntry],* }) =>
      registerTheoremInfo declarationId (entries.map (·.raw))


/-! ## `@theorem` and `@lemma` -/

syntax declarationKind := "@theorem" <|> "@lemma"
syntax (docComment)? declarationKind ident (bracketedBinder)* ":" term ":=" "script" scriptStmts : command
syntax (docComment)? declarationKind ident (bracketedBinder)* ":" term ":=" "by " tacticSeqIndentGt : command
syntax scriptDeclarationKind := "theorem" <|> "lemma"
syntax (docComment)? "script_theorem_impl" scriptDeclarationKind
  ident (bracketedBinder)* ":" term ":=" "script" scriptStmts : command
syntax (docComment)? "by_theorem_impl" scriptDeclarationKind
  ident (bracketedBinder)* ":" term ":=" "by" tacticSeqIndentGt : command

private inductive RecordedDeclarationKind where
  | theorem
  | lemma

private def RecordedDeclarationKind.toString : RecordedDeclarationKind → String
  | .theorem => "theorem"
  | .lemma => "lemma"

private partial def syntaxContainsAtom (value : String) (stx : Syntax) : Bool :=
  (stx.isAtom && stx.getAtomVal == value) || stx.getArgs.any (syntaxContainsAtom value)

private def declarationKindOfSyntax (stx : Syntax) : RecordedDeclarationKind :=
  if syntaxContainsAtom "@lemma" stx || syntaxContainsAtom "lemma" stx then .lemma else .theorem

private def scriptCheckName (name : TSyntax `ident) : TSyntax `ident :=
  mkIdentFrom name.raw ("scriptcheck_" ++ name.getId.toString).toName

macro_rules
  | `(command| $[$doc?:docComment]? @theorem $name:ident
       $[$binders:bracketedBinder]* : $type:term := script $statements:scriptStmts) => do
      let checkName := scriptCheckName name
       let impl ← `(command| $[$doc?:docComment]? script_theorem_impl theorem $name $[$binders]* : $type := script $statements)
      let check ← `(command| theorem $checkName : ∀ $[$binders]*, $type := $name)
      `($impl:command $check:command)
  | `(command| $[$doc?:docComment]? @lemma $name:ident
       $[$binders:bracketedBinder]* : $type:term := script $statements:scriptStmts) => do
      let checkName := scriptCheckName name
       let impl ← `(command| $[$doc?:docComment]? script_theorem_impl lemma $name $[$binders]* : $type := script $statements)
      let check ← `(command| theorem $checkName : ∀ $[$binders]*, $type := $name)
      `($impl:command $check:command)

macro_rules
  | `(command| $[$doc?:docComment]? @theorem $name:ident
       $[$binders:bracketedBinder]* : $type:term := by $sequence:tacticSeq) => do
      let checkName := scriptCheckName name
       let impl ← `(command| by_theorem_impl theorem $name $[$binders]* : $type := by $sequence)
      let check ← `(command| theorem $checkName : ∀ $[$binders]*, $type := $name)
      `($impl:command $check:command)
  | `(command| $[$doc?:docComment]? @lemma $name:ident
       $[$binders:bracketedBinder]* : $type:term := by $sequence:tacticSeq) => do
      let checkName := scriptCheckName name
       let impl ← `(command| by_theorem_impl lemma $name $[$binders]* : $type := by $sequence)
      let check ← `(command| theorem $checkName : ∀ $[$binders]*, $type := $name)
      `($impl:command $check:command)

private partial def findScriptTacticAtom? (stx : Syntax) : Option Syntax :=
  if stx.isAtom then
    let value := stx.getAtomVal
    if value.startsWith "script_" || value.startsWith "_script_" then some stx else none
  else
    stx.getArgs.findSome? findScriptTacticAtom?

private def elabCommandAtomic (definition : Syntax) : CommandElabM Bool := do
  let savedState ← get
  elabCommand definition
  let state ← get
  if state.messages.hasErrors then
    set { savedState with messages := state.messages }
    return false
  return true

private def addRecordedDeclaration (kind : RecordedDeclarationKind)
    (name : TSyntax `ident) (declaration : Name) (proofPath : System.FilePath)
    : CommandElabM Unit := do
  let location : SourceLocation := {
    file := ← getFileName
    start := (name.raw.getPos?.getD 0).byteIdx
    stop := (name.raw.getTailPos?.getD (name.raw.getPos?.getD 0)).byteIdx
  }
  let sorryAx := (← collectAxioms declaration).contains ``sorryAx
  let value := Json.mkObj [
    ("proof", Json.str proofPath.toString),
    ("sorryAx", Json.bool sorryAx)
  ]
  let component : Component := { source := location, data := {
    kind := kind.toString, value, declaration := some declaration } }
  let (nextEnv, added) ← match addComponent (← getEnv) component with
    | .ok result => pure result
    | .error message => throwErrorAt name message
  unless added do
    logWarningAt name "page component appears after page_end and was ignored"
  setEnv nextEnv

private def collectDeclarationReferences (declaration : Name) : CommandElabM Unit := do
  unless ← referencesEnabled do return
  let env ← getEnv
  let some value := (env.find? declaration).bind (·.value? (allowOpaque := true))
    | return
  for constant in value.getUsedConstants do
    addTheoremRef constant

/-- Elaborate a `by` implementation, then elaborate its ordinary theorem check. -/
elab_rules : command
  | `(command|
       $[$doc?:docComment]? by_theorem_impl $kind:scriptDeclarationKind $name:ident
      $[$binders:bracketedBinder]* : $type:term := by $sequence:tacticSeq
    ) => do
      let kind := declarationKindOfSyntax kind.raw
      let declaration := (← getCurrNamespace) ++ name.getId
      if let some tacticName := findScriptTacticAtom? sequence.raw then
        throwErrorAt tacticName "`:= by` cannot use ProofScript tactics; use ordinary Lean tactics"
      let commandStx ← getRef
      let code := String.Pos.Raw.extract (← getFileMap).source
        (commandStx.getPos?.getD 0) (commandStx.getTailPos?.getD (commandStx.getPos?.getD 0))
      let definition ← `(command|
         $[$doc?:docComment]? opaque $name $[$binders]* : $type := by $sequence:tacticSeq)
      unless ← elabCommandAtomic definition.raw do return
      addDeclarationRangesFromSyntax declaration (← getRef) name.raw
      collectDeclarationReferences declaration
      let moduleName ← getMainModule
      let proofPath ← liftIO <| activeOutputPath (proofOutputPath moduleName declaration)
      liftCoreM <| exportCodeOnlyProofToFile proofPath code
      let proofRef ← liftIO <| resourceReferencePath proofPath
      addRecordedDeclaration kind name declaration proofRef

/-- Internal elaborator used by the `@theorem`/`@lemma := script` macros. -/
elab_rules : command
  | `(command|
       $[$doc?:docComment]? script_theorem_impl $kind:scriptDeclarationKind $name:ident
        $[$binders:bracketedBinder]* : $type:term := script $statements:scriptStmts
    ) => do
      let kind := declarationKindOfSyntax kind.raw
      let declarationName := name.getId.toString
      let declaration := (← getCurrNamespace) ++ name.getId
      let commandStx ← getRef
      let code := String.Pos.Raw.extract (← getFileMap).source
        (commandStx.getPos?.getD 0) (commandStx.getTailPos?.getD (commandStx.getPos?.getD 0))
      withRecordingSession <| withExprJsonExport do
        pushBoxTag declarationName
        ensureBox declarationName
        let tactics ← collectRecordTactics (scriptStmtsToArray statements)
        let sequence : TSyntax ``tacticSeq := ⟨buildTacticSeq tactics⟩
        let definition ← `(command|
           $[$doc?:docComment]? opaque $name $[$binders]* : $type := by $sequence:tacticSeq
        )
        unless ← elabCommandAtomic definition.raw do return
        addDeclarationRangesFromSyntax declaration (← getRef) name.raw
        let moduleName ← getMainModule
        let proofPath ← liftIO <| activeOutputPath (proofOutputPath moduleName declaration)
        let expressions ← getExprJsonTable
        let env ← getEnv
        liftIO <| exportRenderEvents env
        liftIO <| exportLean2TeXEvents env
        match ← liftIO <| exportEffectiveRenderRules env with
        | .ok () => pure ()
        | .error message => throwError "{message}"
        let proof ← recordedProofJson declarationName code expressions moduleName
        liftCoreM <| exportProofToFile proofPath proof
        modifyEnv fun env => registerScript env declaration type.raw (scriptStmtsToArray statements)
        let proofRef ← liftIO <| resourceReferencePath proofPath
        addRecordedDeclaration kind name declaration proofRef

end ProofScript
