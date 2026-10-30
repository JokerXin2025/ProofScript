import ProofScript.Script.Recording.Parameter

open Lean Parser Elab Tactic


namespace ProofScript

private def recordRewriteRules (value : TSyntax `rwRuleSeq) : TacticM RecordedValue := do
  let `(rwRuleSeq| [$rules,*]) := value
  | throwErrorAt value "invalid rewrite rules"
  let rules ← rules.getElems.mapM fun rule => do
    unless rule.getKind == ``Parser.Tactic.rwRule do throwErrorAt rule "invalid rewrite rule"
    return .object [("reverse", .plain (toJson !rule[0].isNone)),
      ("expression", ← expression rule[1])]
  return .array rules

namespace ParamRecorder

scoped instance recordParamRwRuleSeq : RecordValue (TSyntax `rwRuleSeq) where
  record value _ := recordRewriteRules value

scoped instance recordParamParserTacticRwRuleSeq : RecordValue (TSyntax ``Parser.Tactic.rwRuleSeq) where
  record value _ := recordRewriteRules ⟨value.raw⟩

end ParamRecorder
