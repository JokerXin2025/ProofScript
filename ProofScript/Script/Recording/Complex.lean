import ProofScript.Script.Recording.Codec
import Lean.Elab.Tactic.Location
import Lean.Elab.ConfigEval

namespace ProofScript.Recording

open Lean Elab Tactic Meta
open Lean.Parser.Tactic

def locationSchema : ParamSchema := .object [
  ("kind", .literal "location"), ("wildcard", .boolean), ("goal", .boolean),
  ("hypotheses", .array .expression)]

def captureLocation (value : TSyntax `location) : TacticM RecordedValue := do
  let data : Bool × Bool × Array RecordedValue ← match expandLocation value.raw with
    | .wildcard => withMainContext do
      let declarations := (← getLCtx).getFVarIds
      let hypotheses ← declarations.filterM fun id => return !(← id.getDecl).isImplementationDetail
      let values ← hypotheses.mapM fun id => snapshotExpression (mkFVar id)
      pure (true, true, values)
    | .targets hypotheses target => do
      pure (false, target, ← hypotheses.mapM expression)
  let (wildcard, target, hypotheses) := data
  return .object [("kind", .scalar (json% "location")), ("wildcard", .scalar (toJson wildcard)),
    ("goal", .scalar (toJson target)), ("hypotheses", .array hypotheses)]

def rewriteRulesSchema : ParamSchema := .array (.object [
  ("reverse", .boolean), ("expression", .expression)])

def captureRewriteRules (value : TSyntax `rwRuleSeq) : TacticM RecordedValue := do
  let `(rwRuleSeq| [$rules,*]) := value | throwErrorAt value "invalid rewrite rules"
  let rules ← rules.getElems.mapM fun rule => do
    unless rule.getKind == ``Parser.Tactic.rwRule do throwErrorAt rule "invalid rewrite rule"
    return RecordedValue.object [("reverse", .scalar (toJson (!rule[0].isNone))),
      ("expression", ← expression rule[1])]
  return .array rules

def simpArgumentsSchema : ParamSchema := .array (.union [
  .object [("kind", .literal "lemma"), ("phase", .union [.literal "pre", .literal "post"]), ("reverse", .boolean),
    ("expression", .expression)],
  .object [("kind", .literal "erase"), ("name", .name), ("expression", .optional .expression)],
  .object [("kind", .literal "star")]])

def captureSimpArguments (value : TSyntax `simpArgs) : TacticM RecordedValue := do
  let `(simpArgs| [$args,*]) := value | throwErrorAt value "invalid simp arguments"
  let values ← args.getElems.mapM fun arg => do
    let arg := arg.raw
    if arg.getKind == ``Parser.Tactic.simpStar then
      return RecordedValue.object [("kind", .scalar (json% "star"))]
    if arg.getKind == ``Parser.Tactic.simpErase then
      let raw := arg[1]
      let captured ← tryCapture (expression raw)
      let value := match captured with
        | .ok value => some value
        | .error _ => none -- Builtin simprocs have names but are not term expressions.
      let label := if raw.isIdent then raw.getId.eraseMacroScopes.toString
        else raw.reprint.getD (reprStr raw)
      return .object [("kind", .scalar (json% "erase")), ("name", .scalar (toJson label)),
        ("expression", .optional value)]
    if arg.getKind == ``Parser.Tactic.simpLemma then
      let phase := if !arg[0].isNone && arg[0][0].getKind == ``Parser.Tactic.simpPre then "pre" else "post"
      return .object [("kind", .scalar (json% "lemma")), ("phase", .scalar (toJson phase)),
        ("reverse", .scalar (toJson (!arg[1].isNone))), ("expression", ← expression arg[2])]
    throwErrorAt arg "unsupported simp argument"
  return .array values

def configSchema : ParamSchema := .array (.object [
  ("name", .name), ("value", .union [.boolean, .number, .string,
    .object [("kind", .literal "syntax"), ("text", .syntax)]])])

/-- A shared category has no tactic-specific expected type. Record explicit settings,
    preserving scalar meaning and retaining typed/config expressions as syntax. Defaults
    remain owned by the tactic's configuration elaborator. -/
def captureConfig (value : TSyntax `optConfig) : TacticM RecordedValue := do
  let entries ← Elab.ConfigEval.foldConfigM (#[] : Array RecordedValue) value.raw
    (fun entries item => do
      let value : RecordedValue ← if let some flag := item.bool? then pure (.scalar (toJson flag)) else
        match (⟨item.value⟩ : TSyntax `term) with
        | `(term| true) => pure (.scalar (json% true))
        | `(term| false) => pure (.scalar (json% false))
        | `(term| $n:num) => pure (.scalar (toJson n.getNat))
        | `(term| $s:str) => pure (.scalar (toJson s.getString))
        | _ => do
          let text ← syntaxText item.value
          pure (.object [("kind", .scalar (json% "syntax")), ("text", text)])
      return entries.push (.object [("name", .scalar (toJson item.origOptionName.toString)),
        ("value", value)]))
    (fun _ raw => throwErrorAt raw "invalid explicit tactic configuration")
  return .array entries

instance : RecordParam (.category `location) where
  schema := locationSchema
  capture := captureLocation

instance : RecordParam (.category `rwRuleSeq) where
  schema := rewriteRulesSchema
  capture := captureRewriteRules

instance : RecordParam (.category `simpArgs) where
  schema := simpArgumentsSchema
  capture := captureSimpArguments

instance : RecordParam (.category `optConfig) where
  schema := configSchema
  capture := captureConfig

instance : RecordParam (.category ``Parser.Tactic.location) where
  schema := locationSchema
  capture value := captureLocation ⟨value.raw⟩

instance : RecordParam (.category ``Parser.Tactic.rwRuleSeq) where
  schema := rewriteRulesSchema
  capture value := captureRewriteRules ⟨value.raw⟩

instance : RecordParam (.category ``Parser.Tactic.simpArgs) where
  schema := simpArgumentsSchema
  capture value := captureSimpArguments ⟨value.raw⟩

instance : RecordParam (.category ``Parser.Term.optConfig) where
  schema := configSchema
  capture value := captureConfig ⟨value.raw⟩

end ProofScript.Recording
