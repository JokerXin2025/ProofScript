import ProofScript.Script.Script
import ProofScript.Script.ScriptDB
import ProofScript.Output.Path
import ProofScript.Page.State
import ProofScript.Page.Component.Core
import ProofScript.Info.Declaration

open Lean Parser Elab Command Tactic

namespace ProofScript

/-! ## `@theorem` and `@lemma` -/

syntax declarationKind := "@theorem" <|> "@lemma"
syntax (docComment)? declarationKind ident (bracketedBinder)* ":" term ":=" "script" scriptStmts : command
syntax (docComment)? declarationKind ident (bracketedBinder)* ":" term ":=" "by " tacticSeqIndentGt : command
syntax scriptDeclarationKind := "theorem" <|> "lemma"
syntax (name := scriptTheoremImpl) (docComment)? "script_theorem_impl" scriptDeclarationKind
  ident (bracketedBinder)* ":" term ":=" "script" scriptStmts : command
syntax (name := byTheoremImpl) (docComment)? "by_theorem_impl" scriptDeclarationKind
  ident (bracketedBinder)* ":" term ":=" "by" tacticSeqIndentGt : command

open Info (RecordedDeclarationKind)

private partial def syntaxContainsAtom (value : String) (stx : Syntax) : Bool :=
  (stx.isAtom && stx.getAtomVal == value) || stx.getArgs.any (syntaxContainsAtom value)

private def declarationKindOfSyntax (stx : Syntax) : RecordedDeclarationKind :=
  if syntaxContainsAtom "@lemma" stx || syntaxContainsAtom "lemma" stx then .lemma else .theorem

private def scriptCheckName (name : TSyntax `ident) : TSyntax `ident :=
  -- Prefix the first component without parsing printed names: quoted dots must stay literal.
  let rec addPrefix : Name → Name
    | .anonymous => .str .anonymous "scriptcheck_"
    | .str .anonymous text => .str .anonymous ("scriptcheck_" ++ text)
    | .num .anonymous index => .str .anonymous ("scriptcheck_" ++ toString index)
    | .str parent text => .str (addPrefix parent) text
    | .num parent index => .num (addPrefix parent) index
  mkIdentFrom name.raw (addPrefix name.getId)

macro_rules
  | `(command| $[$doc?:docComment]? @theorem $name:ident
       $[$binders:bracketedBinder]* : $type:term := script $statements:scriptStmts) => do
      `(command| $[$doc?:docComment]? script_theorem_impl theorem $name $[$binders]* : $type := script $statements)
  | `(command| $[$doc?:docComment]? @lemma $name:ident
       $[$binders:bracketedBinder]* : $type:term := script $statements:scriptStmts) => do
      `(command| $[$doc?:docComment]? script_theorem_impl lemma $name $[$binders]* : $type := script $statements)

macro_rules
  | `(command| $[$doc?:docComment]? @theorem $name:ident
       $[$binders:bracketedBinder]* : $type:term := by $sequence:tacticSeq) => do
      `(command| $[$doc?:docComment]? by_theorem_impl theorem $name $[$binders]* : $type := by $sequence)
  | `(command| $[$doc?:docComment]? @lemma $name:ident
       $[$binders:bracketedBinder]* : $type:term := by $sequence:tacticSeq) => do
      `(command| $[$doc?:docComment]? by_theorem_impl lemma $name $[$binders]* : $type := by $sequence)

private partial def findScriptTacticAtom? (stx : Syntax) : Option Syntax :=
  if stx.isAtom then
    let value := stx.getAtomVal
    if value.startsWith "script_" || value.startsWith "_script_" then some stx else none
  else
    stx.getArgs.findSome? findScriptTacticAtom?

private def elabCommandAtomic (definition : Syntax) : CommandElabM Bool := do
  let savedState ← get
  -- Both declarations must finish in this transaction, including their error diagnostics.
  withScope (fun scope => { scope with opts := scope.opts.setBool `Elab.async false }) <|
    elabCommand definition
  let state ← get
  if state.messages.hasErrors then
    set { savedState with messages := state.messages }
    return false
  return true

/-- Common completion path for script/by, including the internal check and semantic fact registry. -/
private def completeDeclaration (before : Environment) (kind : RecordedDeclarationKind)
    (name : TSyntax `ident) (declaration : Name) (checkSyntax : Syntax) : CommandElabM Bool := do
  unless ← elabCommandAtomic checkSyntax do return false
  let project ← match Info.activeProject before { moduleName := before.mainModule } with
    | .ok project => pure project
    | .error error => throwErrorAt name error.render
  let source := Foundation.SourceLocation.ofSyntax (← getFileName) name.raw
  let check := (← getCurrNamespace) ++ (scriptCheckName name).getId
  let env ← match Info.registerDeclarationFacts before (← getEnv) declaration check kind project source with
    | .ok env => pure env
    | .error error => throwErrorAt name error.render
  setEnv env
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

private def elaborateDeclarationCore (prepare : CommandElabM Unit) : CommandElabM Unit := do
  match ← getRef with
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
      let checkName := scriptCheckName name
      let check ← `(command| theorem $checkName : ∀ $[$binders]*, $type := $name)
      let before ← getEnv
      unless ← elabCommandAtomic definition.raw do return
      unless ← completeDeclaration before kind name declaration check.raw do return
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
        pushRecordingTag declarationName
        ensureBox declarationName
        let tactics ← collectRecordTactics (scriptStmtsToArray statements)
        let sequence : TSyntax ``tacticSeq := ⟨buildTacticSeq tactics⟩
        let definition ← `(command|
           $[$doc?:docComment]? opaque $name $[$binders]* : $type := by $sequence:tacticSeq
        )
        let checkName := scriptCheckName name
        let check ← `(command| theorem $checkName : ∀ $[$binders]*, $type := $name)
        let before ← getEnv
        unless ← elabCommandAtomic definition.raw do return
        unless ← completeDeclaration before kind name declaration check.raw do return
        let moduleName ← getMainModule
        let proofPath ← liftIO <| activeOutputPath (proofOutputPath moduleName declaration)
        let expressions ← getExprJsonTable
        prepare
        let proof ← recordedProofJson declarationName code expressions moduleName
          (artifactKey := some { owner := moduleName, kind := .proof, name := declaration })
          (path := (proofOutputPath moduleName declaration).toString)
        modifyEnv fun env => registerScript env declaration type.raw (scriptStmtsToArray statements)
        let proofRef ← liftIO <| resourceReferencePath proofPath
        addRecordedDeclaration kind name declaration proofRef
        liftCoreM <| exportProofToFile proofPath proof

  | _ => throwUnsupportedSyntax

/-- Opaque, check, facts, metadata, recording and page state commit together on success. -/
def elaborateDeclaration (prepare : CommandElabM Unit := pure ()) : CommandElabM Unit := do
  let saved ← get
  try
    elaborateDeclarationCore prepare
    let state ← get
    if state.messages.hasErrors then set { saved with messages := state.messages }
  catch error =>
    let state ← get
    set { saved with messages := state.messages }
    throw error

end ProofScript
