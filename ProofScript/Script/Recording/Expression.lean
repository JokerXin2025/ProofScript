import ProofScript.Script.Recording.Data
import ProofScript.Utils.Tactic

open Lean Elab Tactic


namespace ProofScript

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

/-- Pretty-printed details are supplementary; an unavailable type must not
    prevent recording an otherwise valid expression. Query in the current
    local context, without modifying the expression that will be exported. -/
private def withOccurrenceDetails (data : MData) (expr : Expr)
    (boundVars : Array Expr) : TacticM MData := do
  let instantiated := expr.instantiateRev boundVars
  let mut data := data
  try
    let type ← Meta.inferType instantiated
    let typeText := toString (← Meta.ppExpr type)
    if typeText.length ≤ 4096 then
      data := data.setString `ProofScript.exprType typeText
  catch _ => pure ()
  try
    let valueText := toString (← Meta.ppExpr instantiated)
    return if valueText.length ≤ 4096 then
      data.setString `ProofScript.exprText valueText else data
  catch _ => return data

private def constantKind : ConstantInfo → String
  | .axiomInfo _ => "axiom"
  | .defnInfo _ => "definition"
  | .thmInfo _ => "theorem"
  | .opaqueInfo _ => "opaque"
  | .quotInfo _ => "quotient"
  | .inductInfo _ => "inductive"
  | .ctorInfo _ => "constructor"
  | .recInfo _ => "recursor"

private def withConstantDetails (data : MData) (name : Name) : TacticM MData := do
  let some info := (← getEnv).find? name | return data
  let mut data := data.setString `ProofScript.declarationKind (constantKind info)
  data := data.setString `ProofScript.levelParams
    (Json.compress <| toJson (info.levelParams.map toString))
  data := data.setBool `ProofScript.declarationUnsafe info.isUnsafe
  data := data.setBool `ProofScript.declarationPartial info.isPartial
  try
    let typeText := toString (← Meta.ppExpr info.type)
    if typeText.length ≤ 4096 then
      data := data.setString `ProofScript.declarationType typeText
  catch _ => pure ()
  return data

/-- Add variable naming and occurrence details along the original expression.
    `boundVars` contains temporary locals in outermost-first order, used only to
    interpret binder types and let values during queries. Recorded bodies retain
    their original bound variables. Existing outer metadata takes precedence. -/
private partial def annotateExpression (expr : Expr)
    (boundVars : Array Expr := #[])
    : TacticM Expr := do
  if let .mdata data body := expr then
    return .mdata data (← annotateExpression body boundVars)
  let mut data : MData := {}
  if let .fvar id := expr then
    let declaration ← id.getDecl
    data := (data.setName `ProofScript.userName declaration.userName)
      |>.setString `ProofScript.type (← namingType declaration.type)
    data := data.setString `ProofScript.variableKind
      (match declaration with | .cdecl .. => "parameter" | .ldecl .. => "let")
    try
      let typeText := toString (← Meta.ppExpr declaration.type)
      if typeText.length ≤ 4096 then
        data := data.setString `ProofScript.variableType typeText
      if let .ldecl _ _ _ value _ _ _ := declaration then
        let valueText := toString (← Meta.ppExpr value)
        if valueText.length ≤ 4096 then
          data := data.setString `ProofScript.variableValue valueText
    catch _ => pure ()
  if let .const name _ := expr then
    data ← withConstantDetails data name
  -- Bound variables need the surrounding local declarations instantiated
  -- before querying their types; uninstantiated bvars cannot be inferred.
  data ← withOccurrenceDetails data expr boundVars
  let expr ← match expr with
    | .app fn arg =>
      pure <| expr.updateApp! (← annotateExpression fn boundVars)
        (← annotateExpression arg boundVars)
    | .lam name type body info
    | .forallE name type body info =>
      let localType := type.instantiateRev boundVars
      data := data.setString `ProofScript.type (← namingType localType)
      try
        let typeText := toString (← Meta.ppExpr localType)
        if typeText.length ≤ 4096 then
          data := data.setString `ProofScript.variableType typeText
      catch _ => pure ()
      let type ← annotateExpression type boundVars
      let body ← Meta.withLocalDecl name info localType fun boundVar =>
        annotateExpression body (boundVars.push boundVar)
      pure <| if expr.isLambda then expr.updateLambdaE! type body
        else expr.updateForallE! type body
    | .letE name type value body nondep =>
      let localType := type.instantiateRev boundVars
      let localValue := value.instantiateRev boundVars
      data := data.setString `ProofScript.type (← namingType localType)
      try
        let typeText := toString (← Meta.ppExpr localType)
        let valueText := toString (← Meta.ppExpr localValue)
        if typeText.length ≤ 4096 then
          data := data.setString `ProofScript.variableType typeText
        if valueText.length ≤ 4096 then
          data := data.setString `ProofScript.variableValue valueText
      catch _ => pure ()
      let type ← annotateExpression type boundVars
      let value ← annotateExpression value boundVars
      let body ← Meta.withLetDecl name localType localValue (nondep := nondep) fun boundVar =>
        annotateExpression body (boundVars.push boundVar)
      pure <| expr.updateLetE! type value body
    | .proj _ _ body =>
      pure <| expr.updateProj! (← annotateExpression body boundVars)
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
- `ProofScript.variableType`, `ProofScript.variableValue`: pretty-printed
  variable/binder type and optional local definition, when available.
- `ProofScript.variableKind`: `parameter` or `let` for free variables.
- `ProofScript.declarationKind`, `ProofScript.declarationType`,
  `ProofScript.levelParams`, `ProofScript.declarationUnsafe`,
  `ProofScript.declarationPartial`: declaration-level information on constant nodes.
  `levelParams` is a JSON-encoded string array within scalar metadata.
- `ProofScript.exprType`, `ProofScript.exprText`: the type and text of this
  particular occurrence in its local context, when inference succeeds.

These annotations are always collected when available and use native `MData`.
Export always includes scalar metadata, including annotations supplied by a recorder.
Temporary Lean state is restored on both success and failure. Recorders that
supply their own expression use `RecordedValue.expression` directly, without
invoking this reader.
-/
def recordExpression (expr : Expr) : TacticM RecordedValue := do
  withoutModifyingState' <| Term.withoutErrToSorry <| withoutRecover do
      let expr ← instantiateMVars expr
      return .expression (← annotateExpression expr)

namespace ValueRecorder

scoped instance : RecordValue Expr where
  record expr _ := recordExpression expr

end ValueRecorder

end ProofScript
