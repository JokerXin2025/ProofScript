import ProofScript.Script.Recording.Parameter

open Lean


namespace ProofScript

/-- Preserve the configuration code without interpreting individual options. -/
def captureConfig (value : TSyntax `Lean.Parser.Tactic.optConfig) : String :=
  (value.raw.reprint.getD "").trimAscii.toString
