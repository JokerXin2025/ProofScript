import Lean.Elab.ElabRules
import Lean.Parser.Term
import ProofScript.Page.State
import ProofScript.Core.BuildMode
import ProofScript.Utils.Linter

open Lean Elab Command
open Lean.Parser.Command (docComment macroArg)
open Lean.Parser.Term (doSeq)


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

/- `page_component` supplies this lexical instance while elaborating its body.
    Helpers constructed elsewhere cannot accidentally acquire that scope. -/
private class PageComponentScope where

private def withPageComponentScope
    (action : PageComponentScope → Lean.Elab.Command.CommandElabM Unit)
    : Lean.Elab.Command.CommandElabM Unit :=
  action {}

private def runPageBuild [PageComponentScope]
    (action : Unit → Lean.Elab.Command.CommandElabM Unit)
    : Lean.Elab.Command.CommandElabM Unit :=
  -- CommandElabM is a reader: delay constructing the action until the gate
  -- actually runs it, including any initial pure expressions in the block.
  whenPageBuild (fun context => action () context)

/-/ Gate an indented `CommandElabM` sequence behind the page-build mode.

    This is intentionally a `doElem`, so callers can keep editor-only work before
    the gated sequence:

    ```lean
    page_component "figure" metadata:componentMeta path:str => do
      addComponentMetadataInfo metadata.raw
      when_page_build
        addFigureComponent metadata.raw path
    ``` -/
macro "when_page_build" body:doSeq : doElem =>
  `(doElem| runPageBuild (fun () => do $body:doSeq))

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

/-/ Define a page command whose invocation syntax is `#page <keyword> ...`.

    The first string is the component keyword after `#page`. Arguments use
    the same syntax as native `elab`; the RHS has type
    `Lean.Elab.Command.CommandElabM Unit`.

    The generated elaborator first calls `beginPageComponent`, so a command after
    `#page end` fails before any RHS code runs. Page-only work inside the RHS uses
    `when_page_build`; editor annotations can remain outside it. -/
macro doc?:(docComment)? "page_component" keyword:str
    args:(macroArg)* " => " rhs:term : command => do
  let component := keyword.getString.trimAscii.toString
  if component.isEmpty then
    Macro.throwErrorAt keyword "page_component requires a non-empty component name"
  if component == "end" then
    Macro.throwErrorAt keyword "`end` is reserved for `#page end` and cannot be a page component name"
  let page ← `(macroArg| "#page")
  let first ← `(macroArg| &$keyword:str)
  -- Keep the category unscoped, as Lean's elab_rules dispatches on its name.
  let category := mkIdent `command
  `(command| $[$doc?:docComment]? elab $page:macroArg $first:macroArg
      $args:macroArg* : $category:ident => do
    Lean.Elab.Command.allowHashCommandLint do
      ProofScript.beginPageComponent
      withPageComponentScope fun scope =>
        letI : PageComponentScope := scope
        let action : Lean.Elab.Command.CommandElabM Unit := $rhs
        action)

end ProofScript
