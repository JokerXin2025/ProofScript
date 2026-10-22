import ProofScript.Script.Script
import ProofScript.Script.ScriptDB
import ProofScript.Output.Path
import ProofScript.Page.State
import ProofScript.Page.Component.Core
import ProofScript.Info.Declaration
import ProofScript.Core.BuildMode

open Lean Parser Elab Command Tactic

namespace ProofScript

/-! ## `@theorem` and `@lemma` -/

syntax declarationKind := "@theorem" <|> "@lemma"
syntax declarationInfo := atomic("(" &"info" " := ") Info.infoFields ")"
syntax (docComment)? declarationKind ident (declarationInfo)? (bracketedBinder)* ":" term ":=" "script" scriptStmts : command
syntax (docComment)? declarationKind ident (declarationInfo)? (bracketedBinder)* ":" term ":=" "by " tacticSeqIndentGt : command
syntax scriptDeclarationKind := "theorem" <|> "lemma"
syntax (name := scriptTheoremImpl) (docComment)? "script_theorem_impl" scriptDeclarationKind
  ident (declarationInfo)? (bracketedBinder)* ":" term ":=" "script" scriptStmts : command
syntax (name := byTheoremImpl) (docComment)? "by_theorem_impl" scriptDeclarationKind
  ident (declarationInfo)? (bracketedBinder)* ":" term ":=" "by" tacticSeqIndentGt : command

open Info (RecordedDeclarationKind infoFields)

private def declarationKindOfSyntax (stx : Syntax) : RecordedDeclarationKind :=
  if syntaxContainsAtom "@lemma" stx || syntaxContainsAtom "lemma" stx then .lemma else .theorem

macro_rules
  | `(command| $[$doc?:docComment]? @theorem $name:ident
       $[$metadata:declarationInfo]? $[$binders:bracketedBinder]* : $type:term := script $statements:scriptStmts) => do
      `(command| $[$doc?:docComment]? script_theorem_impl theorem $name $[$metadata]? $[$binders]* : $type := script $statements)
  | `(command| $[$doc?:docComment]? @lemma $name:ident
       $[$metadata:declarationInfo]? $[$binders:bracketedBinder]* : $type:term := script $statements:scriptStmts) => do
      `(command| $[$doc?:docComment]? script_theorem_impl lemma $name $[$metadata]? $[$binders]* : $type := script $statements)

macro_rules
  | `(command| $[$doc?:docComment]? @theorem $name:ident
       $[$metadata:declarationInfo]? $[$binders:bracketedBinder]* : $type:term := by $sequence:tacticSeq) => do
      `(command| $[$doc?:docComment]? by_theorem_impl theorem $name $[$metadata]? $[$binders]* : $type := by $sequence)
  | `(command| $[$doc?:docComment]? @lemma $name:ident
       $[$metadata:declarationInfo]? $[$binders:bracketedBinder]* : $type:term := by $sequence:tacticSeq) => do
      `(command| $[$doc?:docComment]? by_theorem_impl lemma $name $[$metadata]? $[$binders]* : $type := by $sequence)

private partial def findScriptTacticAtom? (stx : Syntax) : Option Syntax :=
  if stx.isAtom then
    let value := stx.getAtomVal
    if value.startsWith "script_" || value.startsWith "_script_" then some stx else none
  else
    stx.getArgs.findSome? findScriptTacticAtom?

private inductive DeclarationProof where
  | script (statements : TSyntax ``scriptStmts)
  | byTactics (sequence : TSyntax ``tacticSeq)

private structure ParsedDeclaration where
  doc? : Option (TSyntax ``docComment)
  kind : RecordedDeclarationKind
  name : TSyntax `ident
  metadata : Option (TSyntax ``declarationInfo)
  binders : Array (TSyntax ``Lean.Parser.Term.bracketedBinder)
  type : TSyntax `term
  proof : DeclarationProof

private def readDeclaration : CommandElabM ParsedDeclaration := do
  match ← getRef with
  | `(command| $[$doc?:docComment]? by_theorem_impl $kind:scriptDeclarationKind $name:ident
      $[$metadata:declarationInfo]? $[$binders:bracketedBinder]* : $type:term := by $sequence:tacticSeq) => do
    if let some tacticName := findScriptTacticAtom? sequence.raw then
      throwErrorAt tacticName "`:= by` cannot use ProofScript tactics; use ordinary Lean tactics"
    else
      return {
        doc? := doc?
        kind := declarationKindOfSyntax kind.raw
        name := name
        metadata := metadata
        binders := binders
        type := type
        proof := .byTactics sequence
      }
  | `(command| $[$doc?:docComment]? script_theorem_impl $kind:scriptDeclarationKind $name:ident
      $[$metadata:declarationInfo]? $[$binders:bracketedBinder]* : $type:term := script $statements:scriptStmts) => do
    return {
      doc? := doc?
      kind := declarationKindOfSyntax kind.raw
      name := name
      metadata := metadata
      binders := binders
      type := type
      proof := .script statements
    }
  | _ => throwUnsupportedSyntax

/-- Both build modes publish the same native theorem declaration kind. -/
private def theoremSyntax (input : ParsedDeclaration) (proof : TSyntax `term) : CommandElabM Syntax := do
  let { doc?, name, binders, type, .. } := input
  return (← `(command| $[$doc?:docComment]? theorem $name $[$binders]* : $type := $proof)).raw

private def verificationProof : DeclarationProof → CommandElabM (TSyntax `term)
  | .script statements => `(term| script $statements:scriptStmts)
  | .byTactics sequence => `(term| by $sequence:tacticSeq)

private def elabCommandAtomic (definition : Syntax) : CommandElabM Bool := do
  let savedState ← get
  -- Page recording must finish before its state can be consumed by this command.
  withScope (fun scope => { scope with opts := scope.opts.setBool `Elab.async false }) <|
    elabCommand definition
  let state ← get
  if state.messages.hasErrors then
    set { savedState with messages := state.messages }
    return false
  return true

/-- Common page completion path for script/by and their semantic fact registry. -/
private def completeDeclaration (before : Environment) (kind : RecordedDeclarationKind)
    (name : TSyntax `ident) (declaration : Name)
    (metadata : Option (TSyntax ``declarationInfo)) : CommandElabM Bool := do
  let fields ← match metadata with
    | none => pure #[]
    | some stx => do
      let `(declarationInfo| (info := $fields:infoFields)) := stx
        | throwUnsupportedSyntax
      Info.readFields fields
  -- An explicit inline project resolves an ambiguous imported default as well.
  let project ← if fields.any (·.key == "project") then pure none else
    match Info.activeProject before { moduleName := before.mainModule } with
    | .ok project => pure project
    | .error error => throwErrorAt name error.render
  let source := Foundation.SourceLocation.ofSyntax (← getFileName) name.raw
  let env ← match Info.registerDeclarationFacts before (← getEnv) declaration kind project source with
    | .ok env => pure env
    | .error error => throwErrorAt name error.render
  setEnv env
  if let some stx := metadata then
    Info.updateTheoremInfo name fields stx.raw
  addDeclarationRangesFromSyntax declaration (← getRef) name.raw
  return true

private def addRecordedDeclaration (kind : RecordedDeclarationKind)
    (name : TSyntax `ident) (declaration : Name) (proofPath : System.FilePath)
    : CommandElabM Unit := do
  let location : Foundation.SourceLocation := {
    file := ← getFileName
    start := (name.raw.getPos?.getD 0).byteIdx
    stop := (name.raw.getTailPos?.getD (name.raw.getPos?.getD 0)).byteIdx
  }
  let sorryAx := (← collectAxioms declaration).contains ``sorryAx
  let value := json% { proof: $(proofPath.toString), sorryAx: $sorryAx }
  let component : Component := {
    source := location, kind := kind.toString, value, declaration := some declaration }
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

private def elaborateDeclarationCore (input : ParsedDeclaration)
    (prepare : CommandElabM Unit) : CommandElabM Unit := do
  let { kind, name, metadata, type, .. } := input
  let declaration := (← getCurrNamespace) ++ name.getId
  let commandStx ← getRef
  let code := String.Pos.Raw.extract (← getFileMap).source
    (commandStx.getPos?.getD 0) (commandStx.getTailPos?.getD (commandStx.getPos?.getD 0))
  match input.proof with
  | .byTactics sequence => do
      let definition ← theoremSyntax input (← `(term| by $sequence:tacticSeq))
      let before ← getEnv
      unless ← elabCommandAtomic definition do return
      unless ← completeDeclaration before kind name declaration metadata do return
      collectDeclarationReferences declaration
      let moduleName ← getMainModule
      let proofPath ← liftIO <| activeOutputPath (proofOutputPath moduleName declaration)
      let document := codeOnlyProofJson moduleName code
      let artifact : Output.Artifact := {
        key := { owner := moduleName, kind := .proof, name := declaration }
        path := (proofOutputPath moduleName declaration).toString
        declaration := some declaration
        contentDigest := document.sha256 }
      match Output.registerArtifact (← getEnv) artifact with
      | .ok env => setEnv env
      | .error message => throwError message
      let proofRef ← liftIO <| resourceReferencePath proofPath
      addRecordedDeclaration kind name declaration proofRef
      liftCoreM <| exportProofToFile proofPath document

  | .script statements => do
      let declarationName := name.getId.toString
      withRecordingSession do
        pushRecordingTag declarationName
        ensureBox declarationName
        let tactics ← collectRecordTactics (scriptStmtsToArray statements)
        let sequence : TSyntax ``tacticSeq := ⟨buildTacticSeq tactics⟩
        let definition ← theoremSyntax input (← `(term| by $sequence:tacticSeq))
        let before ← getEnv
        unless ← elabCommandAtomic definition do return
        unless ← completeDeclaration before kind name declaration metadata do return
        let moduleName ← getMainModule
        let proofPath ← liftIO <| activeOutputPath (proofOutputPath moduleName declaration)
        prepare
        let proof ← recordedProofJson declarationName code moduleName
          (artifactKey := some { owner := moduleName, kind := .proof, name := declaration })
          (path := (proofOutputPath moduleName declaration).toString)
        modifyEnv fun env => registerScript env declaration type.raw (scriptStmtsToArray statements)
        let proofRef ← liftIO <| resourceReferencePath proofPath
        addRecordedDeclaration kind name declaration proofRef
        liftCoreM <| exportProofToFile proofPath proof

/-- Verification follows native theorem elaboration; page state commits atomically on success. -/
def elaborateDeclaration (prepare : CommandElabM Unit := pure ()) : CommandElabM Unit := do
  let pageBuild ← recordModuleBuildMode
  let input ← readDeclaration
  for metadata in input.metadata do
    if let `(declarationInfo| (info := $fields:infoFields)) := metadata then
      Info.addInfoFieldInfos (inferInstance : Info.InfoSchema Info.TheoremInfo) fields
  unless pageBuild do
    elabCommand (← theoremSyntax input (← verificationProof input.proof))
    return
  let saved ← get
  try
    elaborateDeclarationCore input prepare
    let state ← get
    if state.messages.hasErrors then set { saved with messages := state.messages }
  catch error =>
    let state ← get
    set { saved with messages := state.messages }
    throw error

end ProofScript
