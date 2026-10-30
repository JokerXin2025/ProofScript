import Lean.Elab.ElabRules
import Lean.Parser.Term
import ProofScript.Page.Component.Core

open Lean
open Lean.Parser.Command (docComment macroArg)
open Lean.Parser.Term (doSeq)

namespace ProofScript

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

/-- Gate an indented `CommandElabM` sequence behind the page-build mode.

This is intentionally a `doElem`, so callers can keep editor-only work before
the gated sequence:

```lean
page_component "figure" metadata:componentMeta path:str => do
  addComponentMetadataInfo metadata.raw
  when_page_build
    addFigureComponent metadata.raw path
```
-/
macro "when_page_build" body:doSeq : doElem =>
  `(doElem| runPageBuild (fun () => do $body:doSeq))

/-- Define a page command whose invocation syntax is `#page <keyword> ...`.

The first string is the component keyword after `#page`. Arguments use the
same syntax as native `elab`; the RHS has type
`Lean.Elab.Command.CommandElabM Unit`. For example:

```lean
page_component "widget" source:str => do
  when_page_build
    addPageComponent source.raw "widget" (toJson source.getString)

#page widget "Hello"
```

The generated elaborator first calls `beginPageComponent`, so a command after
`#page end` fails before any RHS code runs. Page-only work inside the RHS uses
`when_page_build`; editor annotations can remain outside it.
-/
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
    ProofScript.beginPageComponent
    withPageComponentScope fun scope =>
      letI : PageComponentScope := scope
      let action : Lean.Elab.Command.CommandElabM Unit := $rhs
      action)

end ProofScript
