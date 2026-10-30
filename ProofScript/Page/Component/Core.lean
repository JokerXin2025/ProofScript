import ProofScript.Page.State
import ProofScript.Core.BuildMode

open Lean Elab Command


namespace ProofScript

structure ComponentMetadata where
  title : String
  label : Option String := none
  extra : List (String × String) := []
  deriving Inhabited, Repr, ToJson, FromJson

syntax componentMetaEntry := ident " := " str
syntax componentMeta := "(" sepBy1(componentMetaEntry, ", ") ")"

/-- Annotate component field names without validating or consuming page metadata. -/
def addComponentMetadataInfo {m : Type → Type} [Monad m] [MonadEnv m] [MonadError m]
    [MonadInfoTree m] (stx : Syntax) : m Unit := do
  for entry in stx[1].getSepArgs do
    match entry with
    | `(componentMetaEntry| $key:ident := $_value:str) =>
        Elab.addCompletionInfo (.fieldId key.raw (some key.getId) {} ``ComponentMetadata)
        match key.getId.eraseMacroScopes with
        | `title => Elab.addConstInfo key.raw ``ComponentMetadata.title
        | `label => Elab.addConstInfo key.raw ``ComponentMetadata.label
        | _ => pure ()
    | _ => pure ()

def validComponentLabel (label : String) : Bool :=
  match label.toList with
  | [] => false
  | first :: rest =>
      first.isAlpha && rest.all fun c => c.isAlphanum || c == '-' || c == '_'

def parseComponentMetadata (stx : Syntax) : Except String ComponentMetadata := do
  let mut title : Option String := none
  let mut label : Option String := none
  let mut extra := []
  let entries := stx.getArgs[1]!.getSepArgs
  for entry in entries do
    match entry with
    | `(componentMetaEntry| $key:ident := $value:str) =>
        let key := key.getId.toString
        let value := value.getString
        match key with
        | "title" =>
            if title.isSome then throw "duplicate component metadata field 'title'"
            title := some value
        | "label" =>
            if label.isSome then throw "duplicate component metadata field 'label'"
            unless validComponentLabel value do
              throw "component label must match [A-Za-z][A-Za-z0-9_-]*"
            label := some value
        | other => extra := extra ++ [(other, value)]
    | _ => throw "invalid component metadata"
  let some titleValue := title
  | throw "component metadata requires 'title'"
  return { title := titleValue, label, extra }

def sourceLocation (stx : Syntax) : CoreM SourceLocation := do
  return SourceLocation.ofSyntax (← getFileName) stx

/-- Record the module build mode and reject a component after `#page end`
before running any component elaboration code. -/
def beginPageComponent : CommandElabM Unit := do
  discard <| recordModuleBuildMode
  ofExcept <| ensurePageOpen (← getEnv)

/-- Adds component data during page builds. `page_component` checks the page
    boundary before the command body; `when_page_build` should guard validation,
    JSON construction and resource IO within that body. -/
def addPageComponent (stx : Syntax) (kind : String) (value : Json)
    (labels : Array (ReferenceKind × String) := #[]) : CommandElabM Unit := whenPageBuild do
  let location ← liftCoreM <| sourceLocation stx
  let mut env ← getEnv
  for (kind, label) in labels do
    env ← match registerLabel env kind label location with
      | .ok nextEnv => pure nextEnv
      | .error message => throwErrorAt stx message
  let (nextEnv, added) ← match addComponent env { source := location, kind, value } with
    | .ok result => pure result
    | .error message => throwErrorAt stx message
  unless added do
    logWarningAt stx "page component appears after #page end and was ignored"
  setEnv nextEnv

end ProofScript
