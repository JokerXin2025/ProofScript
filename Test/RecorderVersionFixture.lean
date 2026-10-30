import ProofScript.Script.Script

open Lean ProofScript

script_macro importedVersionRule
  "imported_version" h:ident => `(tactic| exact $h:ident)

script_recorder importedVersionRule => do
  record_value "first" true
  execute

script_recorder importedVersionRule => do
  execute
  record_value "second" true
