import ProofScript.Page.Component.Core
import ProofScript.Extensions.ProofText.Inline

open Lean Elab Command
open ProofScript


private syntax titleSub := &"sub"
private syntax titleLabel := "(" &"label" " := " str ")"

private structure TitleComponent where
  source : String
  level : Nat
  label : Option String := none
  content : Array ProofText.Inline
deriving Inhabited, Repr, ToJson, FromJson

private def addTitleComponent (level : Nat) (source : TSyntax `str)
    (labelStx : Option (TSyntax ``titleLabel)) : CommandElabM Unit := do
  let label ← labelStx.mapM fun (labelStx : TSyntax ``titleLabel) => do
    let `(titleLabel| (label := $label:str)) := labelStx
      | throwErrorAt labelStx "invalid title label"
    let label := label.getString
    unless validComponentLabel label do
      throwErrorAt labelStx "title label must match [A-Za-z][A-Za-z0-9_-]*"
    return label
  let content ← match ProofText.parseInline source.getString.trimAscii.toString with
    | .ok content => pure content
    | .error message => throwErrorAt source message
  let value : TitleComponent := { source := source.getString, level, label, content }
  let labels := match label with
    | some label => #[("heading", label)]
    | none => #[]
  addPageComponent (← getRef) "title" (toJson value) labels

/-- A page title with optional reference label and ProofText inline formatting. -/
page_component "title" label:(titleLabel)? source:str => do
  when_page_build
    addTitleComponent 1 source label

/-- Each `sub` before `title` increases the title level by one, without a depth limit. -/
page_component "sub" subs:titleSub* &"title" label:(titleLabel)? source:str => do
  when_page_build
    addTitleComponent (subs.size + 2) source label
