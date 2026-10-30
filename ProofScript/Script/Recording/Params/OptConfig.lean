import ProofScript.Script.Recording.Parameter

open Lean Elab Tactic


namespace ProofScript

/-- A shared category has no tactic-specific expected type. Record explicit settings,
    preserving scalar meaning and retaining typed/config expressions as syntax. Defaults
    remain owned by the tactic's configuration elaborator. -/
private def recordConfig (value : TSyntax `optConfig) : TacticM RecordedValue := do
  let entries ← Elab.ConfigEval.foldConfigM (#[] : Array RecordedValue) value.raw
    (fun entries item => do
      let value ← if let some flag := item.bool? then pure (.plain (toJson flag)) else
        match (⟨item.value⟩ : TSyntax `term) with
        | `(term| true) => pure (.plain (json% true))
        | `(term| false) => pure (.plain (json% false))
        | `(term| $n:num) => pure (.plain (toJson n.getNat))
        | `(term| $s:str) => pure (.plain (toJson s.getString))
        | _ => do
          let text ← syntaxText item.value
          pure (.object [("kind", .plain (json% "syntax")), ("text", text)])
      return entries.push (.object [("name", .plain (toJson item.origOptionName.toString)),
        ("value", value)]))
    (fun _ raw => throwErrorAt raw "invalid explicit tactic configuration")
  return .array entries

namespace ParamRecorder

scoped instance recordParamOptConfig : RecordValue (TSyntax `optConfig) where
  record value _ := recordConfig value

scoped instance recordParamParserTermOptConfig : RecordValue (TSyntax ``Parser.Term.optConfig) where
  record value _ := recordConfig ⟨value.raw⟩

scoped instance recordParamParserTacticOptConfig : RecordValue (TSyntax ``Parser.Tactic.optConfig) where
  record value _ := recordConfig ⟨value.raw⟩

end ParamRecorder
