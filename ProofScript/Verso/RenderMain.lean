import ProofScript.Verso.Capture
import Verso.Code.Highlighted.WebAssets

open Lean System SubVerso.Highlighting
open Verso.Code

namespace ProofScript.Verso

private def fail (message : String) : IO α := throw <| IO.userError s!"Verso renderer: {message}"

private def field (value : Json) (key : String) : IO Json :=
  match value.getObjVal? key with
  | .ok result => pure result
  | .error error => fail s!"{key}: {error}"

private def string (value : Json) (key : String) : IO String := do
  match (← field value key).getStr? with
  | .ok result => pure result
  | .error error => fail s!"{key}: {error}"

private def array (value : Json) (key : String) : IO (Array Json) := do
  match (← field value key).getArr? with
  | .ok result => pure result
  | .error error => fail s!"{key}: {error}"

private def parse (text : String) : IO Json :=
  match Json.parse text with
  | .ok value => pure value
  | .error error => fail s!"invalid JSON: {error}"

private def exactKeys (value : Json) (keys : List String) : IO Unit := do
  let .ok obj := value.getObj? | fail "expected a JSON object"
  unless (obj.toList.map Prod.fst).mergeSort == keys.mergeSort do
    fail s!"unexpected JSON fields (expected {keys})"

private def nameOf (value : Json) : IO Name := do
  if let .ok text := value.getStr? then
    unless !text.isEmpty do fail "empty declaration identity"
    return text.toName
  let components ← match fromJson? value with
    | .ok (parts : Array Json) => pure parts
    | .error error => fail s!"invalid declaration identity: {error}"
  if components.isEmpty then fail "empty declaration identity"
  components.foldlM (init := Name.anonymous) fun name part =>
    match part with
    | .str s => if s.isEmpty then fail "empty declaration component" else pure (name.str s)
    | .num _ => match part.getNat? with
      | .ok value => pure (name.num value)
      | .error _ => fail "invalid numeric declaration component"
    | _ => fail "invalid declaration component"

private def linksOf (value : Json) : IO (NameMap (Array CodeLink)) := do
  let mut result := {}
  for entry in ← array value "links" do
    exactKeys entry ["name", "targets"]
    let name ← nameOf (← field entry "name")
    unless (result.find? name).isNone do fail s!"duplicate link target for {name}"
    let mut links := #[]
    for target in ← array entry "targets" do
      exactKeys target ["short", "long", "href"]
      let short ← string target "short"
      let description ← string target "long"
      let href ← string target "href"
      unless !short.isEmpty && !href.isEmpty &&
          !(href.toLower.startsWith "javascript:" || href.toLower.startsWith "data:") do
        fail "invalid link target"
      links := links.push {shortDescription := short, description, href}
    unless !links.isEmpty do fail s!"no links for {name}"
    result := result.insert name links
  return result

private partial def safeName (name : Name) : Bool :=
  name.components.all fun part => match part with
  | .str _ s => !(s.startsWith "scriptcheck_" || s.startsWith "scriptProof%" ||
      s.startsWith "_record_theorem_statement")
  | _ => true

private partial def safeHighlight : Highlighted → Bool
  | .token tok =>
    let kindSafe := match tok.kind with
      | .const name .. | .anonCtor name .. => safeName name
      | _ => true
    kindSafe && !(tok.content.splitOn "scriptcheck_").length > 1
  | .seq pieces => pieces.all safeHighlight
  | .span info inner => safeHighlight inner && info.all (safeMessage ·.2)
  | .tactics goals _ _ inner => safeHighlight inner && goals.all safeGoal
  | .point _ info => safeMessage info
  | .text text | .unparsed text => !(text.splitOn "scriptcheck_").length > 1
where
  safeGoal (goal : Highlighted.Goal Highlighted) : Bool :=
    safeHighlight goal.conclusion && goal.hypotheses.all fun h =>
      safeHighlight h.typeAndVal && h.names.all fun token => match token.kind with
        | .const name .. => safeName name
        | _ => true
  safeMessage : Highlighted.MessageContents Highlighted → Bool
    | .text text => !(text.splitOn "scriptcheck_").length > 1
    | .goal goal => safeGoal goal
    | .term term => safeHighlight term
    | .append parts => parts.all safeMessage
    | .trace _ msg children _ => safeMessage msg && children.all safeMessage

private def loadHighlight (resource code : String) (declaration : Name) : IO Highlighted := do
  let envelope ← parse resource
  exactKeys envelope ["format", "sourceHash", "declaration", "producer", "highlighted"]
  unless (← string envelope "format") == formatId &&
      (← string envelope "producer") == "verso-v4.32.0/subverso-0076a9e8" &&
      (← string envelope "sourceHash") == contentHash code &&
      (← nameOf (← field envelope "declaration")) == declaration do
    fail "incompatible semantic resource or source identity"
  let payload := ← string envelope "highlighted"
  let exported ← parse payload
  let decoded ← match SubVerso.Highlighting.ExportCode.fromJson? exported with
    | .ok data => pure data
    | .error error => fail s!"invalid SubVerso export: {error}"
  let hl ← match decoded.toHighlighted with
    | .ok result => pure result
    | .error error => fail s!"invalid SubVerso highlighted tree: {error}"
  unless hl.toString == code do fail "highlighted text does not equal original source"
  unless safeHighlight hl do fail "private implementation name in semantic resource"
  return hl

private def instanceId (text : String) : IO String := do
  unless !text.isEmpty && text.toList.all (fun c => c.isAlphanum || c == '-' || c == '_') do
    fail s!"invalid HTML instance ID: {text}"
  return text

private def renderBatch (input : Json) : IO Json := do
  exactKeys input ["protocol", "pages"]
  unless (← string input "protocol") == "proofscript.verso.render.v1" do
    fail "unsupported render protocol"
  let mut ids : Std.HashSet String := {}
  let mut pages := #[]
  let mut idSupply : Hover.IdSupply := {}
  for page in ← array input "pages" do
    exactKeys page ["id", "links", "instances"]
    let pageId ← instanceId (← string page "id")
    unless !ids.contains pageId do fail s!"duplicate page ID: {pageId}"
    ids := ids.insert pageId
    let linkMap ← linksOf page
    let mut pageIds : Std.HashSet String := {}
    let linkTargets : LinkTargets Unit := {
      const := fun n _ => (linkMap.find? n).getD #[],
      definition := fun n _ => (linkMap.find? n).getD #[] }
    let context : HighlightHtmlM.Context _root_.Verso.Doc.Genre.none := {
      linkTargets, traverseContext := (), definitionIds := {}, options := {} }
    let mut state : Hover.State _root_.Verso.Output.Html := {dedup := {}, idSupply}
    let mut instances := #[]
    for item in ← array page "instances" do
      exactKeys item ["id", "context", "declaration", "code", "resource", "visibleStates"]
      let id ← instanceId (← string item "id")
      unless (ids.insert id).size > ids.size do fail s!"duplicate instance ID: {id}"
      ids := ids.insert id
      pageIds := pageIds.insert id
      let contextName ← instanceId (← string item "context")
      let declaration ← nameOf (← field item "declaration")
      unless safeName declaration do fail "private declaration identity"
      let code ← string item "code"
      let highlighted ← loadHighlight (← string item "resource") code declaration
      let ranges ← (← array item "visibleStates").mapM fun range => do
        let .ok #[.num start, .num stop] := range.getArr? | fail "invalid visible state range"
        let .ok start := (Json.num start).getNat? | fail "invalid start position"
        let .ok stop := (Json.num stop).getNat? | fail "invalid end position"
        unless start ≤ stop do fail "inverted visible state range"
        pure (start, stop)
      let context := {context with options := {context.options with
        visibleProofStates := .states ranges} }
      let (html, nextState) :=
        (highlighted.blockHtml contextName (trim := false) (htmlId := some id)).run context |>.run state
      state := nextState
      instances := instances.push <| json% { id: $id, html: $(html.asString) }
    if pageIds.size != instances.size then fail "duplicate instance plan"
    idSupply := state.idSupply
    pages := pages.push <| json% {
      id: $pageId, instances: $instances, hover: $(state.dedup.docJson) }
  return json% { protocol: "proofscript.verso.render.v1", pages: $pages }

private def writeAsset (root : FilePath) (name content : String) : IO Json := do
  let path := root / name
  IO.FS.writeFile path content
  return json% {path: $name, hash: $(contentHash content)}

private def writeAssets (root : FilePath) : IO Json := do
  IO.FS.createDirAll root
  let upstream := highlightingJs "Promise.resolve(window.ProofScriptVersoHoverData)"
  let scopedJs := (upstream.replace "window.onload = async () => {"
    "window.ProofScriptVersoInit = async () => {").replace ".hl.lean" ".verso-source .hl.lean"
      |>.replace "document.querySelectorAll(\"code.docstring, pre.docstring\")"
        "document.querySelectorAll(\".verso-source code.docstring, .verso-source pre.docstring\")"
  unless scopedJs != upstream && !scopedJs.contains "window.onload = async () => {" &&
      !scopedJs.contains "document.querySelectorAll(\"code.docstring, pre.docstring\")" do
    fail "Verso frontend initialization contract changed"
  let files ← #[
    ("highlighting.css", highlightingStyle),
    ("highlighting.js", scopedJs),
    ("popper.js", Highlighted.WebAssets.popper),
    ("tippy.js", Highlighted.WebAssets.tippy),
    ("tippy-border.css", Highlighted.WebAssets.tippy.border.css),
    ("marked.js", Highlighted.WebAssets.marked)
  ].mapM fun (name, content) => writeAsset root name content
  return json% { version: "verso-v4.32.0", files: $files }

/-- Only parses persisted data. No module import or elaboration occurs here. -/
def run (args : List String) : IO Unit := do
  let [input, output, assets] := args | fail "usage: proofscriptVersoRender INPUT OUTPUT ASSET_DIR"
  let result ← renderBatch (← parse (← IO.FS.readFile input))
  let assetManifest ← writeAssets assets
  let result := result.setObjVal! "assets" assetManifest
    |>.setObjVal! "cacheKey" (toJson (Json.sha256 <| json% {
      input: $(← parse (← IO.FS.readFile input)), assets: $assetManifest }))
  let path : FilePath := output
  path.ensureParentDir
  IO.FS.writeFile path result.pretty

end ProofScript.Verso

def main (args : List String) : IO UInt32 := do
  ProofScript.Verso.run args
  return 0
