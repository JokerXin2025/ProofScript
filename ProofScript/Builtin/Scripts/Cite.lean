import ProofScript.Script.Command
import ProofScript.Info.Commands
import ProofScript.Core.References

open Lean Meta Elab
open ProofScript


/-- Manually cite a theorem. -/
script_elab «cite» (kind := metadata, clear := [thm])
"cite " thm:ident => do
  let name ← realizeGlobalConstNoOverloadWithInfo thm
  unless ← isProp (← getConstInfo name).type do
    throwErrorAt thm "`{thm}` should be a theorem"
  stageTheoremRef ⟨name, false⟩

script_info «cite» {
  display := false
}
