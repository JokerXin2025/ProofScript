import ProofScript.Script.Recording.Parameter

open Lean Parser Elab Tactic


namespace ProofScript

/-- Capture rewrite rule expressions in one elaboration snapshot. -/
def captureRewriteRules (value : TSyntax `rwRuleSeq) : TacticM (Array RecordedValue) :=
  withoutModifyingState' <| Term.withoutErrToSorry <| withoutRecover do
    let `(rwRuleSeq| [$rules,*]) := value
      | throwErrorAt value "invalid rewrite rules"
    let mut expressions := #[]
    for rule in rules.getElems do
      let rule := rule.raw
      unless rule.getKind == ``Parser.Tactic.rwRule do throwErrorAt rule "invalid rewrite rule"
      expressions := expressions.push (← expression rule[1])
    return expressions
