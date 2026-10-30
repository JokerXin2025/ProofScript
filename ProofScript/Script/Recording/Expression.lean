import ProofScript.Script.Recording.Data
import ProofScript.Foundation.Source
import ProofScript.Utils.Tactic

open Lean Elab Tactic


namespace ProofScript

/-- Only original tokens retain their parser input. Comparing input objects is
    deliberately conservative: equal text from a replayed foreign file does not
    establish that its offsets belong to the current file. A failed identity
    check merely loses optional source information. -/
private def sameInput (first second : String) : Bool :=
  unsafe ptrEq first second

/-- Recover a range only when original tokens establish that the syntax belongs
    to the current parser input. Synthetic positions alone do not identify a file.
    This also rejects imported/replayed syntax, including equal-text inputs. -/
def trustedSyntaxSource? (raw : Syntax) : TacticM (Option SourceLocation) := do
  let file ← getFileName
  let input := (← getFileMap).source
  let some range := raw.getRange? | return none
  if file.isEmpty || range.start.byteIdx > range.stop.byteIdx ||
      range.stop.byteIdx > input.utf8ByteSize then
    return none
  let mut pending := [raw]
  let mut original := false
  while !pending.isEmpty do
    let current := pending.head!
    pending := pending.tail!
    if let .original leading start trailing stop := current.getHeadInfo then
      unless sameInput leading.str input && sameInput trailing.str input &&
          range.start.byteIdx ≤ start.byteIdx && stop.byteIdx ≤ range.stop.byteIdx do
        return none
      original := true
    pending := current.getArgs.toList ++ pending
  if !original then return none
  return some { file, start := range.start.byteIdx, stop := range.stop.byteIdx }

private def metadataSource? (data : MData) : TacticM (Option SourceLocation) := do
  for (_, value) in data.entries do
    if let .ofSyntax raw := value then
      if let some source ← trustedSyntaxSource? raw then
        return some source
  return none

/-- Describe a variable's type for naming. Proofs are classified before structural
    function types; declaration heads are retained without unfolding definitions. -/
private def namingType (type : Expr) : TacticM String := do
  let type ← instantiateMVars type
  if ← Meta.isProp type then return "proof"
  return match type.getAppFn' with
    | .const name _ => s!"decl:{name}"
    | .sort level => if level == .zero then "sort:Prop" else "sort:Type"
    | .forallE .. => "function"
    | _ => "unknown"

/-- Add variable naming and source annotations along the original expression.
    `boundVars` contains temporary locals in outermost-first order, used only to
    interpret binder types and let values during queries. Recorded bodies retain
    their original bound variables. Existing outer metadata takes precedence;
    source information belongs only to the annotated occurrence. -/
private partial def annotateExpression (expr : Expr) (source : Option SourceLocation)
    (boundVars : Array Expr := #[])
    : TacticM Expr := do
  if let .mdata data body := expr then
    let source ← match source with
      | some _ => pure source
      | none => metadataSource? data
    return .mdata data (← annotateExpression body source boundVars)
  let mut data : MData := {}
  if let .fvar id := expr then
    let declaration ← id.getDecl
    data := (data.setName `ProofScript.userName declaration.userName)
      |>.setString `ProofScript.type (← namingType declaration.type)
  if let some source := source then
    data := ((data.setString `ProofScript.sourceFile source.file)
      |>.setNat `ProofScript.sourceStart source.start)
      |>.setNat `ProofScript.sourceStop source.stop
  let expr ← match expr with
    | .app fn arg =>
      pure <| expr.updateApp! (← annotateExpression fn none boundVars)
        (← annotateExpression arg none boundVars)
    | .lam name type body info
    | .forallE name type body info =>
      let localType := type.instantiateRev boundVars
      data := data.setString `ProofScript.type (← namingType localType)
      let type ← annotateExpression type none boundVars
      let body ← Meta.withLocalDecl name info localType fun boundVar =>
        annotateExpression body none (boundVars.push boundVar)
      pure <| if expr.isLambda then expr.updateLambdaE! type body
        else expr.updateForallE! type body
    | .letE name type value body nondep =>
      let localType := type.instantiateRev boundVars
      let localValue := value.instantiateRev boundVars
      data := data.setString `ProofScript.type (← namingType localType)
      let type ← annotateExpression type none boundVars
      let value ← annotateExpression value none boundVars
      let body ← Meta.withLetDecl name localType localValue (nondep := nondep) fun boundVar =>
        annotateExpression body none (boundVars.push boundVar)
      pure <| expr.updateLetE! type value body
    | .proj _ _ body =>
      pure <| expr.updateProj! (← annotateExpression body none boundVars)
    | _ => pure expr
  return if data.isEmpty then expr else .mdata data expr

/--
Read a native expression using the default expression reader. Assigned expression
and universe metavariables are instantiated before annotations are collected.

- `ProofScript.userName`: A free variable's user-facing name.
- `ProofScript.type`: A naming type descriptor on free variables and on lambda,
  forall and let binders. Values are `proof`, `decl:<name>`, `sort:Prop`,
  `sort:Type`, `function` or `unknown`; binder annotations describe the bound
  variable's type, not the type of the whole binding expression.
- `ProofScript.sourceFile`, `ProofScript.sourceStart`, `ProofScript.sourceStop`:
  A reliable file and UTF-8 byte range for this occurrence, when available.

These annotations are always collected when available and use native `MData`.
Export always includes scalar metadata, including annotations supplied by a recorder.
Temporary Lean state is restored on both success and failure. Recorders that
supply their own expression use `RecordedValue.expression` directly, without
invoking this reader.
-/
def recordExpression (expr : Expr) (source : Option SourceLocation := none)
    : TacticM RecordedValue := do
  withoutModifyingState' <| Term.withoutErrToSorry <| withoutRecover do
      let expr ← instantiateMVars expr
      return .expression (← annotateExpression expr source)

namespace ValueRecorder

scoped instance : RecordValue Expr where
  record expr _ := recordExpression expr

end ValueRecorder

end ProofScript
