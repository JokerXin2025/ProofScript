import ProofScript.Script.Script
import ProofScript.Script.ScriptDB
import ProofScript.Output.Path
import ProofScript.Page.State
import ProofScript.Page.Component.Command
import ProofScript.Info.Declaration
import ProofScript.Core.BuildMode

open Lean Parser Elab Command Tactic

namespace ProofScript


private partial def findScriptTacticAtom? (stx : Syntax) : Option Syntax :=
  if stx.isAtom then
    let value := stx.getAtomVal
    if value.startsWith "script_" || value.startsWith "_script_" then some stx else none
  else
    stx.getArgs.findSome? findScriptTacticAtom?

/-- Only direct `sorry` diagnostics from the helper should affect the native theorem's IDE marker. -/
private initialize sorryProofsExt : EnvExtension NameSet ←
  registerEnvExtension (pure {}) (asyncMode := .sync)

/-- Capture actual proof locals before any tactic can rename or clear them. -/
elab "_record_theorem_statement" : tactic => withMainContext do
  let mut parameters := #[]
  let mut conditions := #[]
  for decl in (← getLCtx) do
    if decl.isImplementationDetail then continue
    let type ← recordExpression decl.type
    if (← Meta.isProp decl.type) || decl.binderInfo == .instImplicit then
      conditions := conditions.push type
    else
      parameters := parameters.push <| .object [
        ("variable", ← recordExpression decl.toExpr), ("type", type),
        ("instance", .plain (toJson (decl.binderInfo == .instImplicit)))]
  setRecordingStatement <| .object [
    ("parameters", .array parameters), ("conditions", .array conditions),
    ("conclusion", ← recordExpression (← (← getMainGoal).getType))]

private def elabDeclaration (kind : RecordedDeclarationKind) (name helper : TSyntax `ident)
    (binders : Array (TSyntax ``Lean.Parser.Term.bracketedBinder))
    (type proof : TSyntax `term) : CommandElabM Unit := do
  beginPageComponent
  let saved ← get
  modify fun state => { state with messages := {} }
  try
    let pageBuild ← recordModuleBuildMode
    let statements? ← match proof with
      | `(term| script $statements:scriptStmts) => pure (some statements)
      | `(term| by $sequence:tacticSeq) => do
          if let some tacticName := findScriptTacticAtom? sequence.raw then
            throwErrorAt tacticName "`:= by` cannot use ProofScript tactics; use ordinary Lean tactics"
          pure none
      | _ => throwErrorAt proof "expected a `script` or `by` proof"
    let declaration := (← getCurrNamespace) ++ name.getId
    let helperName := (← getCurrNamespace) ++ helper.getId
    let before ← getEnv
    if before.contains declaration || before.contains helperName then
      throwErrorAt name "declaration name is already in use"
    let source ← getRef
    let check (body : TSyntax `term) : CommandElabM Unit := do
      elabCommand (← `(command| def $helper $[$binders]* : $type := $body))
      if (← get).messages.hasErrors then throwAbortCommand
      let some (.defnInfo definition) := (← getEnv).find? helperName
        | throwAbortCommand
      unless ← liftTermElabM <| Meta.isProp definition.type do throwAbortCommand
    let (prepared?, stagedReferences) ← withIsolatedTheoremRefs do
      if !pageBuild then do
        check proof
        pure (none : Option (Json × Artifact))
      else do
        let moduleName ← getMainModule
        let code := String.Pos.Raw.extract (← getFileMap).source
          (source.getPos?.getD 0) (source.getTailPos?.getD (source.getPos?.getD 0))
        let key : ArtifactKey := { owner := moduleName, kind := .proof, name := declaration }
        let path := (proofOutputPath moduleName declaration).toString
        let (document, artifact) ← match statements? with
          | none => withRecordingSession do
              let `(term| by $sequence:tacticSeq) := proof
                | throwError "expected native tactic proof"
              let capture ← `(tactic| _record_theorem_statement)
              let wrapped : TSyntax ``tacticSeq := ⟨buildTacticSeq #[capture.raw, sequence.raw]⟩
              check (← `(term| by $wrapped:tacticSeq))
              let document := codeOnlyProofJson moduleName code (← requireRecordingStatement)
              let expressions ← ofExcept <| document.getObjVal? "expressions"
              let roots ← ofExcept <| document.getObjValAs? (Array JsonPath) "expressionRoots"
              let dependencies ← ofExcept <| recordedDependencies (← getEnv) expressions document #[] roots
              let artifact : Artifact := {
                key, path, dependencies, declaration := some declaration, contentDigest := document.sha256 }
              pure (document, artifact)
          | some statements => withRecordingSession do
              let label := name.getId.toString
              pushRecordingTag label
              ensureBox label
              let tactics ← collectRecordTactics (scriptStmtsToArray statements)
              let capture ← `(tactic| _record_theorem_statement)
              let sequence : TSyntax ``tacticSeq := ⟨buildTacticSeq (#[capture.raw] ++ tactics)⟩
              check (← `(term| by $sequence:tacticSeq))
              let beforeDocument ← getEnv
              let document ← recordedProofJson label code moduleName
                (artifactKey := some key) (path := path)
              let some artifact := (moduleArtifacts (← getEnv) moduleName).find? (·.key == key)
                | throwError "missing proof artifact"
              setEnv beforeDocument
              pure (document, { artifact with declaration := some declaration })
        pure (some (document, artifact))
    let citations := stagedReferences.filter (!·.isDependency)
    let messages := (← get).messages
    if messages.hasErrors then throwAbortCommand
    if messages.reportedPlusUnreported.any (fun message => message.data.hasTag (· == `hasSorry)) then
      modifyEnv fun env => sorryProofsExt.modifyState env (·.insert helperName)
    if let some (document, artifact) := prepared? then
      let location := SourceLocation.ofSyntax (← getFileName) name.raw
      let dependencies ← withRef name <| liftTermElabM <|
        registerDeclarationFacts before declaration kind location citations (proofSource := some helperName)
      if let some statements := statements? then
        modifyEnv fun env => registerScript env declaration type.raw (scriptStmtsToArray statements)
      match registerProofArtifact (← getEnv) artifact with
      | .ok env => setEnv env
      | .error message => throwError message
      let moduleName ← getMainModule
      let proofPath ← liftIO <| activeOutputPath (proofOutputPath moduleName declaration)
      let proofRef ← liftIO <| resourceReferencePath proofPath
      let sorryAx := (← collectAxioms helperName).contains ``sorryAx
      let component : Component := {
        source := location, kind := toString kind, declaration := some declaration
        value := json% { proof: $(proofRef.toString), sorryAx: $sorryAx } }
      let (env, added) ← match addComponent (← getEnv) component with
        | .ok result => pure result
        | .error message => throwErrorAt name message
      setEnv env
      unless added do logWarningAt name "page component appears after #page end and was ignored"
      liftCoreM <| exportProofToFile proofPath document
      for reference in stagedReferences do stageTheoremRef reference
      for dependency in dependencies do stageTheoremRef dependency
    modify fun state => { state with messages := saved.messages ++ state.messages }
  catch error =>
    set saved
    if error.isRuntime then throw error
    -- The native proof reports one error at the user's declaration, without leaking helper diagnostics.

elab "script_theorem_impl " name:ident helper:ident binders:bracketedBinder*
    ":" type:term ":=" proof:term : command =>
  elabDeclaration .«theorem» name helper binders type proof

elab "script_lemma_impl " name:ident helper:ident binders:bracketedBinder*
    ":" type:term ":=" proof:term : command =>
  elabDeclaration .«lemma» name helper binders type proof

elab "scriptProof% " helper:ident : term <= expectedType => do
  let helperName := (← getCurrNamespace) ++ helper.getId
  unless ((← getEnv).find? helperName).any (fun info => match info with
      | .defnInfo _ => true
      | _ => false) do
    throwError "proof unfinished"
  if (sorryProofsExt.getState (← getEnv)).contains helperName then
    logAt (← getRef) (.tagged `hasSorry m!"declaration uses 'sorry'")
      (severity := .information) (isSilent := true)
  let context ← getLCtx
  let mut value ← Meta.mkConstWithFreshMVarLevels helperName
  let mut used : FVarIdSet := {}
  while !(← Meta.isDefEq (← Meta.inferType value) expectedType) do
    let .forallE binderName binderType _ _ ← Meta.whnf (← Meta.inferType value)
      | throwError "proof unfinished"
    let findArgument (byName : Bool) := context.findDeclM? fun localDecl => do
      if used.contains localDecl.fvarId || (byName && localDecl.userName != binderName) then return none
      if ← Meta.isDefEq localDecl.type binderType then return some localDecl
      return none
    let argument? ← findArgument true
    let some argument ← if argument?.isSome then pure argument? else findArgument false
      | throwError "proof unfinished"
    used := used.insert argument.fvarId
    value := mkApp value argument.toExpr
  return value

private def elaboratePageDeclaration (kind : RecordedDeclarationKind)
    (doc? : Option Syntax) (name : TSyntax `ident)
    (binders : Array (TSyntax ``Lean.Parser.Term.bracketedBinder))
    (type proof : TSyntax `term) : CommandElabM Unit := do
  let helper := mkIdent <| ← liftMacroM <| Macro.addMacroScope (name.getId.appendBefore "scriptcheck_")
  let implementation ← if kind == .«theorem» then
    `(command| script_theorem_impl $name $helper $[$binders]* : $type := $proof)
  else
    `(command| script_lemma_impl $name $helper $[$binders]* : $type := $proof)
  let declaration ← liftMacroM do
    match doc? with
    | some doc =>
        let doc : TSyntax ``docComment := ⟨doc⟩
        `(command| $doc:docComment theorem $name $[$binders]* : $type := scriptProof% $helper)
    | none =>
        `(command| theorem $name $[$binders]* : $type := scriptProof% $helper)
  let info := SourceInfo.fromRef (← getRef) (canonical := true)
  let implementation : TSyntax `command := ⟨implementation.raw.setInfo info⟩
  let declaration : TSyntax `command := ⟨declaration.raw.setInfo info
    |>.modifyArg 1 (·.setInfo info)⟩
  elabCommand implementation
  elabCommand declaration

page_component "theorem"
    name:ident binders:bracketedBinder* ":" type:term ":=" proof:term => do
  elaboratePageDeclaration .«theorem» none name binders type proof

page_component "theorem" doc:docComment
    name:ident binders:bracketedBinder* ":" type:term ":=" proof:term => do
  elaboratePageDeclaration .«theorem» (some doc.raw) name binders type proof

page_component "lemma"
    name:ident binders:bracketedBinder* ":" type:term ":=" proof:term => do
  elaboratePageDeclaration .«lemma» none name binders type proof

page_component "lemma" doc:docComment
    name:ident binders:bracketedBinder* ":" type:term ":=" proof:term => do
  elaboratePageDeclaration .«lemma» (some doc.raw) name binders type proof

macro doc:docComment "#page" "theorem"
    name:ident binders:bracketedBinder* ":" type:term ":=" proof:term : command => do
  return (← `(command| #page theorem $doc:docComment $name $[$binders]* : $type := $proof))

macro doc:docComment "#page" "lemma"
    name:ident binders:bracketedBinder* ":" type:term ":=" proof:term : command => do
  return (← `(command| #page lemma $doc:docComment $name $[$binders]* : $type := $proof))

end ProofScript
