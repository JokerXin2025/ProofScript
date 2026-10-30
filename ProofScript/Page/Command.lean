import ProofScript.Info.Commands
import ProofScript.Page.Component.Declaration
import ProofScript.Page.Component.Command
import ProofScript.Page.Component.References

namespace ProofScript

open Lean Elab Command

elab "#page" "end" : command => do
  let pageBuild ← recordModuleBuildMode
  let env ← getEnv
  if pageBuild then
    match closePage env (← getFileName) with
    | .ok env => setEnv env
    | .error message => throwError message
  else
    match markPageClosed env with
    | .ok env => setEnv env
    | .error message => throwError message

end ProofScript
