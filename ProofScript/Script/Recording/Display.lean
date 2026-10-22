import ProofScript.Script.Recording.Codec
import ProofScript.Script.Recording.DisplaySchema

namespace ProofScript.Recording

open Lean Elab Tactic Meta
open scoped ExprJson

private def query? (action : TacticM α) : TacticM (Option α) := do
  let saved ← Tactic.saveState
  try
    return some (← withCurrHeartbeats <| withOptions (fun options =>
      (options.set `maxRecDepth (64 : Nat)).set `maxHeartbeats (2000 : Nat)) action)
  catch _ =>
    return none
  finally
    saved.restore

private def sourceRange (range : Syntax.Range) : TacticM Json := do
  if range.start.byteIdx > range.stop.byteIdx then return Json.null
  return json% {
    file: $(← getFileName), start: $(range.start.byteIdx), stop: $(range.stop.byteIdx) }

private def metadataRange (data : MData) : Option Syntax.Range :=
  data.entries.findSome? fun (_, value) => match value with
    | .ofSyntax stx => stx.getRange?
    | _ => none

/-- A failed or dependent-open parameter query keeps the corresponding unknown
    slot. We never ask Meta to reduce an expression with loose bound variables. -/
private def applicationBinders (expr : Expr) : TacticM (Array (Option BinderInfo)) := do
  let mut type? ← query? (inferType expr.getAppFn)
  let mut result := #[]
  for argument in expr.getAppArgs do
    match type? with
    | some type =>
      let reduced ← if type.hasLooseBVars then pure none else query? (whnf type)
      match reduced with
      | some (.forallE _ _ body info) =>
        result := result.push (some info)
        type? := some (body.instantiate1 argument)
      | _ =>
        result := result.push none
        type? := none
    | none => result := result.push none
  return result

private abbrev DisplayBuildM := StateT (Array RecordedData) CaptureM

private def inDeclarationContext (goal : Option MVarId)
    (action : DisplayBuildM α) : DisplayBuildM α :=
  fun views => match goal with
    | some goal => CaptureM.withGoalContext goal (StateT.run action views)
    | none => StateT.run action views

private def setView (index : Nat) (root : RecordedData)
    (hints : Array RecordedData) : DisplayBuildM Unit :=
  modify (·.set! index (.object [("root", root), ("hints", .array hints)]))

/-- Auxiliary capture failure must discard both its provisional views and nodes.
    The nested capture also restores all temporary elaboration state. -/
private def optionalAuxiliary (action : DisplayBuildM Nat) : DisplayBuildM (Option Nat) :=
  fun previous => do
    let result ← tryCapture do
      let (index, views) ← StateT.run action previous
      return .object [("index", .plain (toJson index)), ("views", .array views)]
    match result with
    | .ok (.object [("index", .plain value), ("views", .array views)]) =>
      return (value.getNat?.toOption, views)
    | _ => return (none, previous)

mutual

private partial def auxiliaryView (expr : Expr) (fuel : Nat)
    (active : List (Bool × Name)) (withSource : Bool) : DisplayBuildM Nat := do
  let frozen ← instantiateMVars expr
  let expression ← snapshotExpression frozen
  addView (.object [("kind", .plain (.str "auxiliary")), ("expression", expression)])
    frozen fuel active withSource

private partial def addView (root : RecordedData) (expr : Expr) (fuel : Nat)
    (active : List (Bool × Name)) (withSource : Bool) : DisplayBuildM Nat := do
  let index := (← get).size
  modify (·.push (.plain Json.null))
  let hints ← expressionHints expr #[] fuel active withSource none
  setView index root hints
  return index

private partial def declarationHint (expr : Expr) (fuel : Nat)
    (active : List (Bool × Name)) (withSource : Bool) : DisplayBuildM Json := do
  let declaration : Option ((Bool × Name) × Name × Expr × Option Expr × Option MVarId) ←
    match expr with
    | .fvar id => do
      let declaration ← query? id.getDecl
      pure (declaration.map fun declaration =>
        ((false, id.name), declaration.userName, declaration.type, declaration.value?, none))
    | .mvar id => do
      let declaration ← query? id.getDecl
      pure (declaration.map fun declaration =>
        ((true, id.name), declaration.userName, declaration.type, none, some id))
    | _ => pure none
  let some (key, name, type, value, context) := declaration | return Json.null
  let mut typeView : Option Nat := none
  let mut valueView : Option Nat := none
  if fuel > 0 && (← get).size < 256 && !active.contains key then
    typeView ← optionalAuxiliary <| inDeclarationContext context
      (auxiliaryView type (fuel - 1) (key :: active) withSource)
    if (← get).size < 256 then
      if let some value := value then
        valueView ← optionalAuxiliary <| inDeclarationContext context
          (auxiliaryView value (fuel - 1) (key :: active) withSource)
  return json% { name: $(name.toString), typeView: $typeView, valueView: $valueView }

private partial def expressionHints (expr : Expr) (path : Array String) (fuel : Nat)
    (active : List (Bool × Name)) (withSource : Bool)
    (range : Option Syntax.Range) : DisplayBuildM (Array RecordedData) := do
  if let .mdata data body := expr then
    return ← expressionHints body path fuel active withSource
      (range <|> (if withSource then metadataRange data else none))
  let proposition ← if expr.hasLooseBVars then pure none else query? (isProp expr)
  let declaration ← declarationHint expr fuel active withSource
  let binders ← if expr.isApp && !expr.hasLooseBVars then
      query? (applicationBinders expr)
    else pure none
  let source ← match range with
    | some range => sourceRange range
    | none => pure Json.null
  let hint := RecordedData.plain (json% {
    path: $path, isProp: $proposition, declaration: $declaration,
    appBinders: $binders, sourceRange: $source })
  let mut result := #[hint]
  let children : Array (String × Expr) := match expr with
    | .app fn arg => #[("fn", fn), ("arg", arg)]
    | .lam _ type body _ | .forallE _ type body _ => #[("type", type), ("body", body)]
    | .letE _ type value body _ => #[("type", type), ("value", value), ("body", body)]
    | .proj _ _ body => #[("expr", body)]
    | _ => #[]
  for (edge, child) in children do
    result := result ++ (← expressionHints child (path.push edge) fuel active withSource none)
  return result

end

private def captureLeafDisplay (expr : Expr) (withSource : Bool) : CaptureM RecordedData := do
  let (_, views) ← StateT.run
    (addView (.plain Json.null) expr 32 [] withSource) #[]
  return .array views

private partial def expressionOccurrences (data : RecordedData) (path : Array Json := #[]) :
    Array (Nat × Array Json) :=
  match data with
  | .plain _ => #[]
  | .expression root => #[(root, path)]
  | .array values => (values.mapIdx fun index value =>
      expressionOccurrences value (path.push (toJson index))).flatten
  | .object fields => (fields.toArray.map fun (key, value) =>
      expressionOccurrences value (path.push (.str key))).flatten

private def mapJsonObject (json : Json) (transform : String → Json → Json) : Json :=
  match json with
  | .obj fields => .mkObj (fields.toList.map fun (key, value) => (key, transform key value))
  | other => other

/-- Only the two declared display-view indices move when independent leaf
    displays are composed. These are never expression-node offsets. -/
private def relocateHint (hint : RecordedData) (offset : Nat)
    (rootSource : Option Json) : RecordedData :=
  match hint with
  | .plain json => .plain <| mapJsonObject json fun key value =>
      if key == "declaration" then mapJsonObject value fun key value =>
        if key == "typeView" || key == "valueView" then
          match value.getNat? with
          | .ok index => toJson (offset + index)
          | .error _ => value
        else value
      else if key == "sourceRange"
          && (json.getObjVal? "path").toOption == some (.arr #[]) then
        rootSource.getD value
      else value
  | other => other

private def relocateView (view : RecordedData) (offset : Nat)
    (root : Option RecordedData) (rootSource : Option Json) : RecordedData :=
  match view with
  | .object fields => .object <| fields.map fun (key, value) =>
      if key == "root" then (key, root.getD value)
      else if key == "hints" then
        match value with
        | .array hints => (key, .array (hints.map (relocateHint · offset rootSource)))
        | _ => (key, value)
      else (key, value)
  | other => other

/-- Explicitly freeze the subject and its occurrence-scoped display information
    at one capture point. Ordinary codecs and conversions remain structural.
    The caller atomically writes this envelope's `value` and `display` siblings. -/
def captureWithDisplay (field : String) (action : CaptureM RecordedData)
    (source : Option Syntax := none) : CaptureM RecordedData := do
  let initial ← get
  let observerIndex := initial.expressionObservers.size
  let observationStart := initial.observations.size
  let observer := fun expr (_ : Nat) =>
    CaptureM.run (captureLeafDisplay expr source.isSome)
  set { initial with expressionObservers := initial.expressionObservers.push observer }
  let subject ← action
  let captured ← get
  let observations := (captured.observations.extract observationStart captured.observations.size).filter
    (·.observer == observerIndex)
  let remaining := captured.observations.extract 0 observationStart ++
    (captured.observations.extract observationStart captured.observations.size).filter
      (·.observer != observerIndex)
  set { captured with
    expressionObservers := initial.expressionObservers
    observations := remaining }
  if subject == .plain Json.null then
    return .object [("value", subject), ("display", .plain Json.null)]
  let rootSource ← match source.bind Syntax.getRange? with
    | some range => pure (some (← sourceRange range))
    | none => pure none
  let mut views := #[]
  for (rootId, path) in expressionOccurrences subject do
    let root := RecordedData.plain (json% { kind: "field", path: $path })
    let offset := views.size
    match observations.find? (·.root == rootId) with
    | some observation =>
      let imported ← CaptureM.importValue observation.value
      if let .array localViews := imported then
        for index in [:localViews.size] do
          views := views.push (relocateView localViews[index]! offset
            (if index == 0 then some root else none)
            (if index == 0 && path.isEmpty then rootSource else none))
      else
        throwError "invalid internal display observation"
    | none =>
      let hints := match (if path.isEmpty then rootSource else none) with
        | some source => #[RecordedData.plain (.mkObj [
            ("path", .arr #[]), ("isProp", .null), ("declaration", .null),
            ("appBinders", .null), ("sourceRange", source)])]
        | none => #[]
      views := views.push (.object [("root", root), ("hints", .array hints)])
  let display := RecordedData.object [
    ("kind", .plain (.str "expression-display-v1")), ("field", .plain (.str field)),
    ("views", .array views)]
  return .object [("value", subject), ("display", display)]

/-- Add explicitly declared companions for fields whose semantic schema contains
    expressions. The field literal follows the final emitted timing suffix. -/
def withDisplayFields (fields : Array OutputField) : Array OutputField :=
  fields.foldl (fun result field =>
    let result := result.push field
    if field.schema.hasExpressions then
      result.push (OutputField.mk (field.name ++ "_display")
        (.optional (displaySchema field.name)) false)
    else result) #[]

end ProofScript.Recording
