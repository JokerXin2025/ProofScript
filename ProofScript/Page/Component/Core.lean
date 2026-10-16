import ProofScript.Page.State

open Lean Elab Command


namespace ProofScript

structure ComponentMetadata where
  title : String
  label : Option String := none
  extra : List (String × String) := []
  deriving Inhabited, Repr, ToJson, FromJson

syntax componentMetaEntry := ident " := " str
syntax componentMeta := "(" sepBy1(componentMetaEntry, ", ") ")"

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

def componentMetadataJson (metadata : ComponentMetadata) := toJson metadata

def sourceLocation (stx : Syntax) : CoreM Foundation.SourceLocation := do
  return Foundation.SourceLocation.ofSyntax (← getFileName) stx

/-- Adds component data to the current page. Custom component modules can use this
    after implementing their own syntax, validation, and JSON representation. -/
def addPageComponent (stx : Syntax) (kind : String) (value : Json)
    (labels : Array (ReferenceKind × String) := #[]) : CommandElabM Unit := do
  let location ← liftCoreM <| sourceLocation stx
  let mut env ← getEnv
  for (kind, label) in labels do
    env ← match registerLabel env kind label location with
      | .ok nextEnv => pure nextEnv
      | .error message => throwErrorAt stx message
  let data : ComponentData := { kind, value }
  let (nextEnv, added) ← match addComponent env { source := location, data } with
    | .ok result => pure result
    | .error message => throwErrorAt stx message
  unless added do
    logWarningAt stx "page component appears after page_end and was ignored"
  setEnv nextEnv

end ProofScript
