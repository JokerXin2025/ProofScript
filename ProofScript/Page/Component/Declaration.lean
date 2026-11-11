import ProofScript.Script.Script
import ProofScript.Script.ScriptDB
import ProofScript.Output.Path
import ProofScript.Page.State
import ProofScript.Page.Component.Core
import ProofScript.Info.Declaration
import ProofScript.Core.BuildMode

open Lean Parser Elab Command Tactic

namespace ProofScript


/-! The theorem body may elaborate inside the declaration's namespace prefix.
    Reattach the helper's relative name to the part of the current namespace
    that is outside that prefix. -/
private def resolveHelperName (helper : TSyntax `ident) (currentNamespace : Name) : Name :=
  let helperId := helper.getId
  let helperComponents := helperId.eraseMacroScopes.components
  let helperPrefix := helperComponents.dropLast
  let namespaceComponents := currentNamespace.eraseMacroScopes.components
  let maximum := Nat.min helperPrefix.length namespaceComponents.length
  let overlap := (List.range (maximum + 1)).foldl (init := 0) fun best size =>
    if helperPrefix.take size |>.isSuffixOf namespaceComponents then size else best
  let base := (namespaceComponents.take (namespaceComponents.length - overlap)).foldl
    Name.append Name.anonymous
  base ++ helperId


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
  let saved ← get
  modify fun state => { state with messages := {} }
  try
    let pageBuild ← pageBuild?
    let statements? ← match proof with
      | `(term| script $statements:scriptStmts) => pure (some statements)
      | `(term| by $sequence:tacticSeq) => do
          if let some tacticName := findScriptTacticAtom? sequence.raw then
            throwErrorAt tacticName "`:= by` cannot use ProofScript tactics; use ordinary Lean tactics"
          pure none
      | _ => throwErrorAt proof "expected a `script` or `by` proof"
    let declaration := (← getCurrNamespace) ++ name.getId
    let helperName := resolveHelperName helper (← getCurrNamespace)
    let before ← getEnv
    if before.contains declaration || before.contains helperName then
      throwErrorAt name "declaration name is already in use"
    let source ← getRef
    let check (body : TSyntax `term) : CommandElabM Unit := do
      -- `abbrev` keeps the checked proof as a definition while avoiding the
      -- `defProp` warning for this generated proposition-valued helper.
      elabCommand (← `(command| abbrev $helper $[$binders]* : $type := $body))
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
              let (document, artifact) ← recordedProofJson label code moduleName
                (artifactKey := some key) (path := path)
              pure (document, { artifact with declaration := some declaration })
        pure (some (document, artifact))
    let citations := stagedReferences.filter (!·.isDependency)
    let messages := (← get).messages
    if messages.hasErrors then throwAbortCommand
    if messages.reportedPlusUnreported.any (fun message => message.data.hasTag (· == `hasSorry)) then
      modifyEnv fun env => sorryProofsExt.modifyState env (·.insert helperName)
    if let some (document, artifact) := prepared? then
      let dependencies ← withRef name <| liftTermElabM <|
        registerDeclarationFacts before declaration kind citations (proofSource := some helperName)
      if let some statements := statements? then
        modifyEnv fun env => registerScript env declaration type.raw (scriptStmtsToArray statements)
      let moduleName ← getMainModule
      let proofRef := proofOutputPath moduleName declaration
      let sorryAx := (← collectAxioms helperName).contains ``sorryAx
      let component : Component := {
        kind := toString kind, declaration := some declaration
        value := json% {
          proof: $(resourceJson proofRef document.pretty "application/vnd.proofscript.proof+json"),
          sorryAx: $sorryAx } }
      let requests := artifact.dependencies.map fun dependency =>
        (⟨⟨dependency.kind, dependency.target⟩, dependency.required,
          s!"theorem {declaration}", none⟩ : InfoRequest)
      let requests := requests.push ⟨⟨"theorem", .inl declaration⟩, false,
        s!"theorem {declaration}", none⟩
      let requests := artifact.bindings.foldl (fun requests binding =>
        requests.push ⟨⟨"script", .inl binding.contract.ruleId⟩, false,
          s!"theorem {declaration}", none⟩) requests
      let env ← match registerProofArtifact (← getEnv) artifact with
        | .ok env => pure env
        | .error message => throwError message
      let env ← match registerProofDocument env artifact document with
        | .ok env => pure env
        | .error message => throwError message
      match addComponent env component requests with
      | .ok updated => setEnv updated
      | .error message => throwErrorAt name message
      for reference in stagedReferences do stageTheoremRef reference
      for dependency in dependencies do stageTheoremRef dependency
    modify fun state => { state with messages := saved.messages ++ state.messages }
  catch error =>
    set saved
    if error.isRuntime then throw error
    -- The native proof reports one error at the user's declaration, without leaking helper diagnostics.

elab "script_theorem_impl " name:ident helper:ident binders:bracketedBinder*
    ":" type:term ":=" proof:term : command =>
  allowHashCommandLint <| elabDeclaration .«theorem» name helper binders type proof

elab "script_lemma_impl " name:ident helper:ident binders:bracketedBinder*
    ":" type:term ":=" proof:term : command =>
  allowHashCommandLint <| elabDeclaration .«lemma» name helper binders type proof

elab "scriptProof% " helper:ident " := " _proof:term : term <= expectedType => do
  let helperName := resolveHelperName helper (← getCurrNamespace)
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


/- Expose the native theorem through macro expansion so Lean's language server
   retains its declaration snapshots and goals-accomplished marker. -/
macro doc?:(docComment)? "#page" "theorem"
    name:ident binders:bracketedBinder* ":" type:term ":=" proof:term : command => do
  let helper := mkIdent <| ← Macro.addMacroScope (name.getId.appendBefore "scriptcheck_")
  let implementation ← `(command| script_theorem_impl $name $helper $[$binders]* : $type := $proof)
  let declaration ← `(command| $[$doc?:docComment]? theorem $name $[$binders]* : $type := scriptProof% $helper := $proof)
  let info := SourceInfo.fromRef (← getRef) (canonical := true)
  let implementation := implementation.raw.setInfo info
  let declaration := declaration.raw.setInfo info |>.modifyArg 1 (·.setInfo info)
  return ⟨mkNullNode #[implementation, declaration]⟩

macro doc?:(docComment)? "#page" "lemma"
    name:ident binders:bracketedBinder* ":" type:term ":=" proof:term : command => do
  let helper := mkIdent <| ← Macro.addMacroScope (name.getId.appendBefore "scriptcheck_")
  let implementation ← `(command| script_lemma_impl $name $helper $[$binders]* : $type := $proof)
  let declaration ← `(command| $[$doc?:docComment]? theorem $name $[$binders]* : $type := scriptProof% $helper := $proof)
  let info := SourceInfo.fromRef (← getRef) (canonical := true)
  let implementation := implementation.raw.setInfo info
  let declaration := declaration.raw.setInfo info |>.modifyArg 1 (·.setInfo info)
  return ⟨mkNullNode #[implementation, declaration]⟩

end ProofScript
