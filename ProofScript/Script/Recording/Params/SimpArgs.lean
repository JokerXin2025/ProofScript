import ProofScript.Script.Recording.Parameter
import ProofScript.Utils.Tactic

open Lean Parser Elab Tactic


namespace ProofScript

/-- Capture one aligned row for each simp argument, including inapplicable slots. -/
def captureSimpArguments (value : TSyntax `simpArgs) : TacticM
    (Array String × Array String × Array String × Array String × Array RecordedValue) :=
  withoutModifyingState' <| Term.withoutErrToSorry <| withoutRecover do
    let `(simpArgs| [$args,*]) := value
      | throwErrorAt value "invalid simp arguments"
    let mut kinds := #[]
    let mut names := #[]
    let mut phases := #[]
    let mut directions := #[]
    let mut expressions := #[]
    for arg in args.getElems do
      let arg := arg.raw
      if arg.getKind == ``Parser.Tactic.simpStar then
        kinds := kinds.push "star"
        names := names.push "not applicable"
        phases := phases.push "not applicable"
        directions := directions.push "not applicable"
        expressions := expressions.push (.plain (toJson "not applicable"))
      else if arg.getKind == ``Parser.Tactic.simpErase then
        let raw := arg[1]
        -- Simprocs have names but need not elaborate as terms. Restore even a
        -- successful optional attempt before continuing with the next argument.
        let value ← try
            withoutModifyingState' <| Term.withoutErrToSorry <| withoutRecover <| expression raw
          catch _ =>
            pure (.plain (toJson "not applicable"))
        let label := if raw.isIdent then raw.getId.eraseMacroScopes.toString
          else raw.reprint.getD (reprStr raw)
        kinds := kinds.push "erase"
        names := names.push label
        phases := phases.push "not applicable"
        directions := directions.push "not applicable"
        expressions := expressions.push value
      else if arg.getKind == ``Parser.Tactic.simpLemma then
        let phase := if !arg[0].isNone && arg[0][0].getKind == ``Parser.Tactic.simpPre then "pre" else "post"
        kinds := kinds.push "lemma"
        names := names.push "not applicable"
        phases := phases.push phase
        directions := directions.push (if arg[1].isNone then "forward" else "backward")
        expressions := expressions.push (← expression arg[2])
      else throwErrorAt arg "unsupported simp argument"
    return (kinds, names, phases, directions, expressions)
