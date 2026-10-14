import ProofScript.Page.Path
import ProofScript.Page.State
import ProofScript.Page.Component.Theorem
import ProofScript.Render.Registry
import ProofScript.Lean2TeX.Registry

open Lean


namespace ProofScript


open Lean.Elab.Command in
elab "page_end" : command => do
  let env ← getEnv
  if let .error message := effectiveIncomingRenderFields env then
    throwError message
  liftIO <| exportRenderEvents env
  liftIO <| exportLean2TeXEvents env
  match ← liftIO <| exportEffectiveRenderRules env with
  | .ok () => pure ()
  | .error message => throwError "{message}"
  let state := getPageState env
  let moduleName ← getMainModule
  let fileName ← getFileName
  let page : Page := {
    module := moduleName
    source := fileName
    components := resolveTheoremComponents env state.components
  }
  let path ← liftIO <| activeOutputPath (pageOutputPath moduleName)
  liftIO do
    ensureParentDir path
    IO.FS.writeFile path (toJson page).pretty
  let env ← match closePage env with
            | .ok env => pure env
            | .error message => throwError message
  setEnv env


end ProofScript
