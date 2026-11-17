import ProofScript.Info.Freeze
import ProofScript.Output.TheoremDependencies
import ProofScript.Page.State
import ProofScript.Output.Path
import ProofScript.Page.Component.Computation

namespace ProofScript

open Lean System
open scoped InfoJson

private def checked (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error

private def relativePath (path : FilePath) : IO String := do
  let name := path.toString
  unless name.startsWith ".ProofScript/" do
    throw <| IO.userError s!"invalid output path: {name}"
  let relative := (name.drop ".ProofScript/".length).toString
  unless !relative.isEmpty && (relative.splitOn "/").all (fun part =>
      !part.isEmpty && part != "." && part != ".." && !part.contains '\\') do
    throw <| IO.userError s!"unsafe output path: {name}"
  return relative

def moduleFile (kind : String) (owner : Name) : String :=
  s!"{kind}/{modulePath owner}.json"

private def document (owner : Name) (source : String)
    (components : Array Component) : Json := json% {
  module: $owner,
  source: $source,
  components: $(components.map toJson) }

private def resourcePath (owner : Name) (kind file : String) : FilePath :=
  outputRoot / "resources" / modulePath owner / kind / file

private def renameResource (owner : Name) (original : FilePath) : FilePath :=
  resourcePath owner "generated" (original.fileName.getD "resource")

private partial def replaceResourcePaths (paths : Array (String × String)) (value : Json) : Json :=
  match value with
  | .arr values => .arr (values.map (replaceResourcePaths paths))
  | .obj entries => Json.mkObj <| entries.toList.map fun (key, child) =>
    if key == "$resource" then
      let child := match child.getObjValAs? String "path" with
        | .ok path => match paths.find? (·.1 == path) with
          | some (_, replacement) => child.setObjVal! "path" (.str replacement)
          | none => child
        | .error _ => child
      (key, child)
    else (key, replaceResourcePaths paths child)
  | _ => value

private partial def referencedResourcePaths (value : Json) : Array String :=
  match value with
  | .obj entries =>
    let current := match entries.get? "$resource" with
      | some resource =>
        match resource.getObjValAs? String "path" with
        | .ok path => #[path]
        | .error _ => #[]
      | none => #[]
    current ++ (entries.toList.toArray.flatMap fun (_, child) => referencedResourcePaths child)
  | .arr values => values.flatMap referencedResourcePaths
  | _ => #[]

structure PreparedModule where
  files : Array (String × Json) := #[]
  texts : Array (String × String) := #[]
  figures : Array (String × FilePath) := #[]
  pending : Array (String × Json) := #[]
  hasComponents : Bool := false

/-- Freeze the owner's final view; no page file is needed for configuration-only modules. -/
def prepareModule (env : Environment) (registry : ProjectRegistry) (owner : Name)
    (source : String) : IO PreparedModule := do
  let components := modulePageComponents env owner
  let mut prepared : PreparedModule := { hasComponents := !components.isEmpty }
  if components.isEmpty then return prepared
  let frozen ← checked <| freezeRequestedInfo env owner
    (moduleInfoRequests env owner)
  let contracts := (moduleArtifacts env owner).flatMap fun artifact =>
    artifact.bindings.map (·.contract)
  let contracts := contracts.foldl (fun seen contract =>
    if seen.any (·.id == contract.id) then seen else seen.push contract) (#[] : Array RecordingContract)
  for contract in contracts do
    let some (_, value) := frozen.scripts.find? (·.1 == contract.ruleId)
      | throw <| IO.userError s!"missing requested script Info for {contract.ruleId}"
    let _ ← checked <| validateScriptContract contract.kind value
  let records := frozen.toRecords
  let info := json% {
    module: $owner,
    library: $(registry.selected),
    records: $records,
    contracts: $(contracts.map fun contract => json% { id: $(contract.id), value: $contract }) }
  prepared := { prepared with files := prepared.files.push (moduleFile "info" owner, info) }
  let infoPath := (outputRoot / moduleFile "info" owner).toString
  let mut paths : Array (String × String) := #[]
  let mut figures : Array (String × String) := #[]
  let mut proofResources : Array (String × Json) := #[]
  for item in moduleTextResources env owner do
    let used := components.any fun component =>
      (referencedResourcePaths component.value).contains item.path.toString ||
        (moduleProofDocuments env owner).any (fun proof =>
          (referencedResourcePaths proof.value).contains item.path.toString)
    unless used do continue
    let _ ← relativePath item.path
    let target := renameResource owner item.path
    let next ← relativePath target
    paths := paths.push (item.path.toString, target.toString)
    unless prepared.texts.any (fun (path, content) => path == next && content == item.content) do
      prepared := { prepared with texts := prepared.texts.push (next, item.content) }
  for component in components do
    if component.kind == "figure" then
      let path ← match component.value.getObjValAs? String "path" with
        | .ok path => pure path
        | .error error => throw <| IO.userError error
      let original := FilePath.mk path
      if original.isAbsolute || (path.splitOn "/").any (fun part => part == ".." || part.isEmpty) ||
          path.contains '\\' then
        throw <| IO.userError s!"unsafe figure source: {path}"
      let extension := original.extension.getD ""
      unless !extension.isEmpty && extension.toList.all (fun char => char.isAlphanum) do
        throw <| IO.userError s!"invalid figure extension: {path}"
      let destination := resourcePath owner "images" <|
        s!"{Json.sha256 (toJson path)}.{extension}"
      let relative ← relativePath destination
      unless prepared.figures.any (fun (existing, _) => existing == relative) do
        prepared := { prepared with figures := prepared.figures.push (relative, original) }
      figures := figures.push (path, destination.toString)
  for artifact in moduleArtifacts env owner do
    let some proof := (moduleProofDocuments env owner).find? (·.key == artifact.key)
      | throw <| IO.userError s!"missing persisted proof: {artifact.key.name}"
    unless proof.value.sha256 == artifact.contentDigest do
      throw <| IO.userError s!"proof digest disagrees with .olean: {artifact.key.name}"
    let relative ← relativePath (proofOutputPath owner artifact.key.name)
    let destination := (outputRoot / relative).toString
    paths := paths.push (artifact.path, destination)
    let proof := proof.value.setObjVal! "bindings" (toJson artifact.bindings)
    let proof := replaceResourcePaths paths proof
    proofResources := proofResources.push (artifact.path, json% {
      "$resource": {
        path: $destination,
        hash: $(contentHash proof.pretty),
        mediaType: "application/vnd.proofscript.proof+json", encoding: "utf-8" } })
    prepared := { prepared with files := prepared.files.push (relative, proof) }
  for entry in Computation.modulePendingEntries env owner do
    let relative := s!"computations/pending/{modulePath owner}/{Json.sha256 (toJson entry.entry)}.json"
    paths := paths.push ((Computation.pendingEntryPath entry.module entry.entry).toString,
      (outputRoot / relative).toString)
    prepared := { prepared with pending := prepared.pending.push (relative, toJson entry) }
  let mut finalized := #[]
  for component in components do
    let mut value := component.value
    if let some declaration := component.declaration then
      let facts ← checked <| freezeTheoremFacts env registry owner declaration
      let some _ := frozen.decls.find? (·.1 == declaration)
        | throw <| IO.userError s!"missing requested declaration Info for {declaration}"
      let proof ← match value.getObjVal? "proof" with
        | .ok proof => pure proof
        | .error error => throw <| IO.userError error
      let sorryAx ← match value.getObjVal? "sorryAx" with
        | .ok sorryAx => pure sorryAx
        | .error error => throw <| IO.userError error
      let proof := match proof.getObjVal? "$resource" with
        | .ok resource =>
          match resource.getObjValAs? String "path" with
          | .ok oldPath =>
            (proofResources.find? (fun (entry : String × Json) => entry.1 == oldPath))
              |>.map (fun (entry : String × Json) => entry.2) |>.getD proof
          | .error _ => proof
        | .error _ => proof
      value := json% {
        declaration: $(facts.declaration), projectId: $(facts.projectId),
        proofRefs: $(facts.proofRefs),
        proofDependencies: $(facts.proofDependencies),
        proof: $proof, sorryAx: $sorryAx }
    if component.kind == "references" then
      let mut references := #[]
      for reference in component.references do
        let some (_, declarationValue) := frozen.decls.find? (·.1 == reference.name)
          | throw <| IO.userError s!"missing requested declaration Info for {reference.name}"
        let projectId := (registry.declarationProject? env reference.name).map ProjectKey.projectId
        references := references.push <| json% {
          name: $(reference.name), isDependency: $(reference.isDependency),
          info: $declarationValue, projectId: $projectId }
      value := .arr references
    if component.kind == "figure" then
      if let .ok path := value.getObjValAs? String "path" then
        if let some (_, destination) := figures.find? (·.1 == path) then
          value := value.setObjVal! "path" (.str destination)
    finalized := finalized.push { component with value }
  let page := document owner source finalized
    |>.setObjVal! "info" (toJson infoPath)
  prepared := { prepared with files := prepared.files.push (moduleFile "pages" owner,
    replaceResourcePaths paths page) }
  return prepared

/-- Serialize an owner's staged inputs without writing any public output. -/
def moduleDescriptor (env : Environment) (registry : ProjectRegistry) (owner : Name)
    (source : String) : IO Json := do
  -- Configuration-only modules publish no Info document.
  let prepared ← prepareModule env registry owner source
  let files := prepared.files.map fun (path, value) => json% { path: $path, json: $value }
  let files := files ++ prepared.texts.map fun (path, value) => json% { path: $path, text: $value }
  let files := files ++ prepared.pending.map fun (path, value) => json% { path: $path, json: $value }
  let figures := prepared.figures.map fun (path, source) => json% {
    path: $path, source: $(source.toString) }
  let manifest := moduleFile "manifests/modules" owner
  return json% {
    module: $owner,
    package: $(registry.selected.package),
    library: $(registry.selected.library),
    resourceModule: $(modulePath owner |>.toString),
    manifest: $manifest,
    hasComponents: $(prepared.hasComponents),
    files: $files, figures: $figures }

end ProofScript
