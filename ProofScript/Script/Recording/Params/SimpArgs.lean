import ProofScript.Script.Recording.Parameter
import ProofScript.Utils.Tactic

open Lean Parser Elab Tactic


namespace ProofScript

private def recordSimpArguments (value : TSyntax `simpArgs) : TacticM RecordedValue := do
  let `(simpArgs| [$args,*]) := value
  | throwErrorAt value "invalid simp arguments"
  let values ← args.getElems.mapM fun arg => do
    let arg := arg.raw
    if arg.getKind == ``Parser.Tactic.simpStar then
      return .object [("kind", .plain (toJson "star"))]
    if arg.getKind == ``Parser.Tactic.simpErase then
      let raw := arg[1]
      -- Simprocs have names but need not elaborate as terms. Restore even a
      -- successful optional attempt before continuing with the next argument.
      let value ← try
          withoutModifyingState' <| Term.withoutErrToSorry <| withoutRecover <| expression raw
        catch _ =>
          pure (.plain .null)
      let label := if raw.isIdent then raw.getId.eraseMacroScopes.toString
        else raw.reprint.getD (reprStr raw)
      return .object [("kind", .plain (json% "erase")), ("name", .plain (toJson label)),
        ("expression", value)]
    if arg.getKind == ``Parser.Tactic.simpLemma then
      let phase := if !arg[0].isNone && arg[0][0].getKind == ``Parser.Tactic.simpPre then "pre" else "post"
      return .object [("kind", .plain (json% "lemma")), ("phase", .plain (toJson phase)),
        ("reverse", .plain (toJson (!arg[1].isNone))), ("expression", ← expression arg[2])]
    throwErrorAt arg "unsupported simp argument"
  return .array values

namespace ParamRecorder

scoped instance recordParamSimpArgs : RecordValue (TSyntax `simpArgs) where
  record value _ := recordSimpArguments value

scoped instance recordParamParserTacticSimpArgs : RecordValue (TSyntax ``Parser.Tactic.simpArgs) where
  record value _ := recordSimpArguments ⟨value.raw⟩

end ParamRecorder
