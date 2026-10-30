import Lake

open Lake DSL System Lean


package ProofScript where
  version := v!"0.1.0"

require mathlib from git
  "https://github.com/leanprover-community/mathlib4" @ "v4.32.0"

@[default_target]
lean_lib ProofScript

lean_lib Test where
  roots := #[`Test.RecorderVersions, `Test.RecorderVersionFixture,
    `Test.RecorderVersionExtension, `Test.RecorderVersionImport,
    `Test.PageTheoremMathlib]

lean_exe proofscriptExport where
  root := `ProofScript.Output.Main
  supportInterpreter := true

namespace ProofScriptPageBuild

private partial def dependsOn (pkg : Package) (key : Name) : Bool :=
  pkg.keyName == key || pkg.depPkgs.any (dependsOn · key)

def sourcePackages (ws : Workspace) (selected : Package) : NameSet := Id.run do
  let mut result := ({} : NameSet).insert selected.keyName
  let some framework := ws.packages.find? (·.baseName == `ProofScript) | return result
  for pkg in ws.packages do
    -- Framework defaults use the same page-only Info commands as user modules.
    -- Its dependents must also be isolated from their ordinary import artifacts.
    if dependsOn selected pkg.keyName && dependsOn pkg framework.keyName then
      result := result.insert pkg.keyName
  return result

private def pageConfig (sources : NameSet) (buildRoot : FilePath) (pkg : Package) : PackageConfig pkg.keyName pkg.origName :=
  if sources.contains pkg.keyName then
    { pkg.config with
      buildDir := buildRoot / s!"{pkg.wsIdx}-{pkg.baseName}"
      enableArtifactCache? := some false
      restoreAllArtifacts? := some true }
  else pkg.config

private partial def remapDeps (sources : NameSet) (buildRoot : FilePath) (pkg : Package) : Array Package :=
  pkg.depPkgs.map fun dep =>
    { dep with
      config := pageConfig sources buildRoot dep
      depPkgs := remapDeps sources buildRoot dep }

private def remapPackage (sources : NameSet) (buildRoot : FilePath) (pkg : Package) : Package :=
  { pkg with
    config := pageConfig sources buildRoot pkg
    depPkgs := remapDeps sources buildRoot pkg }

def remapWorkspace (ws : Workspace) (sources : NameSet) (buildRoot : FilePath) : Workspace :=
  let packages := ws.packages.map (remapPackage sources buildRoot)
  { ws with
    packages := packages
    packageMap := packages.foldl (fun map pkg => map.insert pkg.keyName ⟨pkg, rfl⟩) {}
    size_packages_pos := by simpa [packages] using ws.size_packages_pos
    packages_wsIdx := by
      intro i hi
      simpa [packages, remapPackage] using ws.packages_wsIdx (by simpa [packages] using hi)
    depIdxs_packages := by
      intro pkg hp i hi
      obtain ⟨old, hold, rfl⟩ := Array.mem_map.mp hp
      simpa [packages] using ws.depIdxs_packages old hold i hi }

def pageOptions (ws : Workspace) (sources : NameSet) (original : NameMap LeanOptions) : NameMap LeanOptions :=
  ws.packages.foldl (init := original) fun options pkg =>
    if sources.contains pkg.keyName then
      options.insert pkg.baseName ((options.find? pkg.baseName |>.getD {}) ++
        -- Foundations may be compiled before the module that registers this option.
        -- Lean's weak option name still participates in Lake's setup-options trace.
        LeanOptions.ofArray #[⟨`weak.proofScript.pageBuild, .ofBool true⟩])
    else options

def buildRoot (ws : Workspace) (lib : LeanLib) : FilePath :=
  ws.root.dir / ".lake" / "ps4html" / lib.pkg.baseName.toString / lib.name.toString

def moduleBuildRoot (ws : Workspace) (mod : Lake.Module) : FilePath :=
  ws.root.dir / ".lake" / "ps4html" / mod.pkg.baseName.toString / ".modules" / mod.name.toString

inductive PageTarget where
  | library (lib : LeanLib)
  | module (mod : Lake.Module)

def PageTarget.pkg : PageTarget → Package
  | .library lib => lib.pkg
  | .module mod => mod.pkg

def PageTarget.name : PageTarget → Name
  | .library lib => lib.name
  | .module mod => mod.name

def PageTarget.kind : PageTarget → String
  | .library _ => "library"
  | .module _ => "module"

def PageTarget.buildRoot (ws : Workspace) : PageTarget → FilePath
  | .library lib => ProofScriptPageBuild.buildRoot ws lib
  | .module mod => moduleBuildRoot ws mod

private def checkedJson [FromJson α] (value : Json) (field : String) : IO α :=
  match value.getObjValAs? α field with
  | .ok result => pure result
  | .error message => throw <| IO.userError s!"invalid PS4HTML session field {field}: {message}"

structure Session where
  file : FilePath
  value : Json
  buildRoot : FilePath
  exportRoot : FilePath

/-- The Python coordinator owns the project lock and cleans this session's Lean directory. -/
def readSession (ws : Workspace) (selection : PageTarget) : IO Session := do
  let some session ← IO.getEnv "PS4HTML_BUILD_SESSION"
    | throw <| IO.userError "ps4htmlInputs requires a PS4HTML build session; use the ps4html facet"
  let file := FilePath.mk session |>.normalize
  let value ← match Json.parse (← IO.FS.readFile file) with
    | .ok value => pure value
    | .error message => throw <| IO.userError s!"invalid PS4HTML session JSON: {message}"
  unless (← checkedJson (α := Nat) value "schemaVersion") == 1 do
    throw <| IO.userError "unsupported PS4HTML build session version"
  let targetKind ← match value.getObjVal? "targetKind" with
    | .error _ => pure "library"
    | .ok _ => checkedJson (α := String) value "targetKind"
  unless targetKind == selection.kind &&
      (← checkedJson (α := String) value "package") == selection.pkg.baseName.toString &&
      (← checkedJson (α := String) value selection.kind) == selection.name.toString do
    throw <| IO.userError s!"PS4HTML build session does not match the requested {selection.kind}"
  let sessionBuild := FilePath.mk (← checkedJson value "buildRoot") |>.normalize
  let exportRoot := FilePath.mk (← checkedJson value "exportRoot") |>.normalize
  unless sessionBuild.isAbsolute && sessionBuild == (selection.buildRoot ws).normalize do
    throw <| IO.userError s!"PS4HTML session must use the {selection.kind}'s dedicated page build directory"
  let staging := (ws.root.dir / ".PS4HTML" / "staging").normalize.toString ++ "/"
  unless file.isAbsolute && file.toString.startsWith staging &&
      exportRoot == file.parent.getD ws.root.dir / "release" / ".ProofScript" do
    throw <| IO.userError "PS4HTML exports must use the build session's unpublished release directory"
  unless (← IO.getEnv "PROOF_SCRIPT_OUTPUT_ROOT") == some exportRoot.toString do
    throw <| IO.userError "PROOF_SCRIPT_OUTPUT_ROOT disagrees with the PS4HTML session"
  IO.FS.createDirAll sessionBuild
  unless (← sessionBuild.readDir).isEmpty do
    throw <| IO.userError "PS4HTML page build directory was not cleaned before starting Lake"
  let supportNames : Array String ← match value.getObjVal? "supportPackages" with
    | .error _ => pure #[]
    | .ok _ => checkedJson value "supportPackages"
  let required := sourcePackages ws selection.pkg
  for name in supportNames do
    let some pkg := ws.packages.find? (·.baseName.toString == name)
      | throw <| IO.userError s!"unknown PS4HTML support package: {name}"
    if required.contains pkg.keyName then
      throw <| IO.userError s!"PS4HTML package {name} requires page compilation; supportPackages cannot exclude the selected package, ProofScript, or its dependent packages"
  return { file, value, buildRoot := sessionBuild, exportRoot }

def mappedLibrary (ws : Workspace) (original : LeanLib) : FetchM LeanLib := do
  let some pkg := ws.findPackageByKey? original.pkg.keyName | error "page build package not found"
  let some lib := pkg.findLeanLib? original.name | error "page build library not found"
  return lib

def mappedModule (ws : Workspace) (original : Lake.Module) : FetchM Lake.Module := do
  let lib ← mappedLibrary ws original.lib
  let some mod := lib.findModule? original.name | error "page build module not found"
  return mod

def PageTarget.inputs (ws : Workspace) : PageTarget → FetchM (Array Lake.Module × Job Unit)
  | .library original => do
    let lib ← mappedLibrary ws original
    let job ← lib.leanArts.fetch
    let owners ← (← lib.modules.fetch).await
    return (owners, job)
  | .module original => do
    let mod ← mappedModule ws original
    let job ← mod.leanArts.fetch
    return (#[mod], job.mix (Job.pure ()))

def moduleClosure (mods : Array Lake.Module) : FetchM (Array Lake.Module) := do
  let mut seen : ModuleSet := ∅
  let mut result := #[]
  for mod in mods do
    for dep in (← (← mod.transImports.fetch).await).push mod do
      unless seen.contains dep do
        seen := seen.insert dep
        result := result.push dep
  return result

def sessionManifest (session : Session) (ws : Workspace) (sources : NameSet)
    (owners modules : Array Lake.Module) : Json :=
  session.value
    |>.setObjVal! "buildMode" (.str "page")
    |>.setObjVal! "pageBuildVersion" (toJson (1 : Nat))
    |>.setObjVal! "owners" (toJson (owners.map (·.name.toString)))
    |>.setObjVal! "sourcePackages" (toJson (ws.packages.filterMap fun pkg =>
      if sources.contains pkg.keyName then some pkg.baseName.toString else none))
    |>.setObjVal! "modules" (.arr (modules.map fun mod => json% {
      name: $(mod.name.toString), "package": $(mod.pkg.baseName.toString),
      source: $(mod.leanFile.toString), olean: $(mod.oleanFile.toString),
      c: $(mod.cFile.toString), setup: $(mod.setupFile.toString) }))

/-- Both scopes compile in the same isolated page environment, exporting only their owners. -/
def buildInputs (selection : PageTarget) : FetchM (Job Unit) := do
  let ws ← getWorkspace
  let session ← readSession ws selection
  let sources := sourcePackages ws selection.pkg
  let workspace := remapWorkspace ws sources session.buildRoot
  let options := pageOptions ws sources (← getLeanOptOverrides)
  withTheReader BuildContext (fun context => { context with
      opaqueWs := workspace, leanOptOverrides := options }) do
    let (owners, inputJob) ← selection.inputs workspace
    let some exporter ← findLeanExe? `proofscriptExport | error "ProofScript Info exporter not found"
    let exporterJob ← exporter.fetch
    let modules ← moduleClosure owners
    (inputJob.mix exporterJob).mapM fun _ => do
      proc {
        cmd := exporter.file.toString
        args := #[session.exportRoot.toString] ++ owners.map (·.name.toString)
        cwd := workspace.root.dir
        env := (← getAugmentedEnv).push ("PROOF_SCRIPT_OUTPUT_ROOT", some session.exportRoot.toString)
      }
      IO.FS.writeFile session.file (sessionManifest session workspace sources owners modules).pretty

/-- Hand off publication to Python without first building the ordinary Lean artifacts. -/
def buildSite (selection : PageTarget) : FetchM (Job FilePath) := do
  let mods ← match selection with
    | .library lib => (← lib.modules.fetch).await
    | .module mod => pure #[mod]
  let root ← getRootPackage
  Job.async do
    let relative := match selection with
      | .library _ => FilePath.mk selection.name.toString
      | .module _ => FilePath.mk ".modules" / selection.name.toString
    let output := root.dir / ".PS4HTML" / "build" / selection.pkg.baseName.toString / relative / "index.html"
    let python := (← IO.getEnv "PS4HTML_PYTHON").getD "python3"
    let backend := (← getWorkspace).packages.findSome? fun p =>
      if p.baseName == `ProofScript then some (p.dir / "tools" / "ps4html") else none
    let some backend := backend | error "ProofScript package not found in Lake workspace"
    let sourceArgs := match selection with
      | .library _ => mods.flatMap fun mod => #[mod.name.toString, mod.leanFile.toString]
      | .module mod => #[mod.leanFile.toString]
    proc {
      cmd := python
      args := #["-m", "PS4HTML", s!"_build-{selection.kind}", selection.pkg.baseName.toString, selection.name.toString,
        "--build-dir", (selection.buildRoot (← getWorkspace)).toString] ++ sourceArgs
      cwd := root.dir
      env := (← getAugmentedEnv).push ("PYTHONPATH", some backend.toString)
        |>.push ("LAKE", some (← getLake).toString)
        |>.push ("PS4HTML_LAKE_CONFIG", some root.configFile.toString)
        |>.push ("PS4HTML_LAKE_ARGS", some (Lean.toJson ((← getWorkspace).lakeArgs?.getD #[])).compress)
        |>.push ("PS4HTML_LAKE_CWD", some (← IO.currentDir).toString)
    }
    return output

end ProofScriptPageBuild

/-- Compile and export a fresh page session without touching ordinary verification products. -/
library_facet ps4htmlInputs (original) : Unit := do
  ProofScriptPageBuild.buildInputs (.library original)

/-- Compile one module and its imports; the export bundle owns only the requested module. -/
module_facet ps4htmlInputs (original) : Unit := do
  ProofScriptPageBuild.buildInputs (.module original)

/-- Build the complete HTML site for the requested Lean library. -/
library_facet ps4html (lib) : FilePath := do
  ProofScriptPageBuild.buildSite (.library lib)

/-- Build an isolated HTML preview; use `+Module:ps4html` to select a module explicitly. -/
module_facet ps4html (mod) : FilePath := do
  ProofScriptPageBuild.buildSite (.module mod)
