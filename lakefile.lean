import Lake

open Lake DSL System Lean


package ProofScript where
  version := v!"0.1.0"

require mathlib from git
  "https://github.com/leanprover-community/mathlib4" @ "v4.32.0"

@[default_target]
lean_lib ProofScript

lean_lib Test where
  roots := #[
    `Test.ClassicalFormula,
    `Test.PageScriptBoard,
    `Test.RecorderAuto,
    `Test.RecorderStage3,
    `Test.RecorderVersionBase,
    `Test.RecorderVersionExtension
  ]

lean_exe proofscriptModuleExport where
  root := `ProofScript.Output.ModuleMain
  supportInterpreter := true

namespace ProofScriptPageBuild

private def encodePart (text : String) : String := Id.run do
  let mut result := ""
  let digits := "0123456789ABCDEF".toList.toArray
  for byte in text.toUTF8.data do
    let char := Char.ofNat byte.toNat
    if byte.toNat < 128 && (char.isAlphanum || char == '_') then
      result := result.push char
    else
      result := result ++ "%" ++ String.singleton digits[byte.toNat / 16]! ++
        String.singleton digits[byte.toNat % 16]!
  return result

private def encodedName (name : Name) : String :=
  String.intercalate "/" (name.components.map fun part => match part with
    | .num _ index => "%N" ++ toString index
    | .str _ text => encodePart text
    | .anonymous => "")

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
      enableArtifactCache? := some false }
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

def pageOptions (ws : Workspace) (sources : NameSet)
    (original : NameMap LeanOptions) : NameMap LeanOptions :=
  ws.packages.foldl (init := original) fun options pkg =>
    if sources.contains pkg.keyName then
      options.insert pkg.baseName ((options.find? pkg.baseName |>.getD {}) ++
        -- Foundations may be compiled before the module that registers this option.
        -- Lean's weak option name still participates in Lake's setup-options trace.
        LeanOptions.ofArray #[⟨`weak.pageBuild, .ofBool true⟩])
    else options

def exportBuildRoot (ws : Workspace) (lib : LeanLib) : FilePath :=
  ws.root.dir / ".lake" / "proofscript" / lib.pkg.baseName.toString / lib.name.toString

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

def PageTarget.lib : PageTarget → LeanLib
  | .library lib => lib
  | .module mod => mod.lib

def mappedLibrary (ws : Workspace) (original : LeanLib) : FetchM LeanLib := do
  let some pkg := ws.findPackageByKey? original.pkg.keyName | error "page build package not found"
  let some lib := pkg.findLeanLib? original.name | error "page build library not found"
  return lib

def mappedModule (ws : Workspace) (original : Lake.Module) : FetchM Lake.Module := do
  let lib ← mappedLibrary ws original.lib
  let some mod := lib.findModule? original.name | error "page build module not found"
  return mod

def moduleClosure (mods : Array Lake.Module) : FetchM (Array Lake.Module) := do
  let mut seen : ModuleSet := ∅
  let mut result := #[]
  for mod in mods do
    for dep in (← (← mod.transImports.fetch).await).push mod do
      unless seen.contains dep do
        seen := seen.insert dep
        result := result.push dep
  return result

end ProofScriptPageBuild

namespace ProofScriptPageBuild

/-- Run a module export after its page-mode .olean and the independent exporter exist. -/
def exportTarget (selection : PageTarget) : FetchM (Job FilePath) := do
  let ws ← getWorkspace
  let sources := sourcePackages ws selection.pkg
  let workspace := remapWorkspace ws sources (exportBuildRoot ws selection.lib)
   let options := pageOptions ws sources (← getLeanOptOverrides)
  let originalModules ← match selection with
    | .library lib => (← lib.modules.fetch).await
    | .module mod => pure #[mod]
  withTheReader BuildContext (fun context => { context with
      opaqueWs := workspace, leanOptOverrides := options }) do
    let owners ← originalModules.mapM (mappedModule workspace)
    let library ← mappedLibrary workspace selection.lib
    let inventory ← (← library.modules.fetch).await
    let mut exports : Job Unit := Job.pure ()
    let some exporter ← findLeanExe? `proofscriptModuleExport
      | error "ProofScript module exporter not found"
    let executable ← exporter.fetch
    let framework := ws.packages.findSome? fun pkg =>
      if pkg.baseName == `ProofScript then some pkg.dir else none
    let some framework := framework | error "ProofScript package not found"
    let output := ws.root.dir / ".ProofScript"
    let build := exportBuildRoot ws selection.lib
    for owner in owners do
      let compiled ← owner.leanArts.fetch
      let closure ← moduleClosure #[owner]
      let manifest := json% {
         schemaVersion: 1,
         sourcePackages: $(ws.packages.filterMap fun pkg =>
           if sources.contains pkg.keyName then some pkg.baseName.toString else none),
        selectedProject: { "package": $(selection.pkg.baseName.toString),
          library: $(selection.lib.name.toString) },
        projects: $((#[selection.lib]).map fun lib => json% {
          "package": $(lib.pkg.baseName.toString), library: $(lib.name.toString) }),
        projectRoots: $(selection.lib.roots.map (·.toString)),
        libraryModules: $(inventory.map (·.name.toString)),
        moduleProjects: $((#[owner]).map fun mod => json% {
          module: $(mod.name.toString), "package": $(selection.pkg.baseName.toString),
          library: $(selection.lib.name.toString) }),
         closureProjects: $(closure.map fun mod => json% {
           module: $(mod.name.toString), "package": $(mod.lib.pkg.baseName.toString),
           library: $(mod.lib.name.toString) }),
         modules: $(closure.map fun mod => json% {
           name: $(mod.name.toString), "package": $(mod.pkg.baseName.toString),
           source: $(mod.leanFile.toString), olean: $(mod.oleanFile.toString),
           c: $(mod.cFile.toString), setup: $(mod.setupFile.toString) }),
         moduleManifest: $(s!"manifests/modules/{encodedName owner.name}.json") }
      let job ← (compiled.mix executable).mapM fun _ => do
        let metadata := build / "exports" / selection.kind / encodedName owner.name / "build.json"
        let descriptor := build / "exports" / selection.kind / encodedName owner.name / "descriptor.json"
        IO.FS.createDirAll metadata.parent.get!
        IO.FS.writeFile metadata manifest.pretty
        let python := (← IO.getEnv "PROOF_SCRIPT_PYTHON").getD "python3"
        let publisher := framework / "tools" / "proofscript" / "module_export.py"
        let scripts := #[framework / "scripts" / "build-computations.mjs",
           framework / "scripts" / "finalize-computations.mjs",
           framework / "scripts" / "computation-build-paths.mjs",
           framework / "tools" / "proofscript" / "export_cache.py",
           framework / "tools" / "proofscript" / "target_manifest.py"]
        let cache ← IO.Process.output {
          cmd := python,
          args := #[ (framework / "tools" / "proofscript" / "export_cache.py").toString,
            metadata.toString, output.toString,
             (output / "manifests" / "modules" /
               s!"{encodedName owner.name}.json").toString,
            exporter.file.toString, publisher.toString] ++ scripts.map (·.toString),
          cwd := ws.root.dir }
        if cache.exitCode == 0 then return
        unless cache.exitCode == 1 do
          error s!"ProofScript export cache check failed: {cache.stderr}"
        proc {
          cmd := exporter.file.toString,
          args := #[descriptor.toString, output.toString,
            publisher.toString,
            framework.toString, owner.name.toString],
          cwd := ws.root.dir,
          env := (← getAugmentedEnv).push
            ("PROOF_SCRIPT_BUILD_MANIFEST", some metadata.toString)
            |>.push ("PROOF_SCRIPT_EXPORT_FINGERPRINT", some cache.stdout.trimAscii.toString)
        }
      exports := (exports.mix job).map (fun _ => ())
    exports.mapM fun _ => do
      let python := (← IO.getEnv "PROOF_SCRIPT_PYTHON").getD "python3"
      let targetName := selection.name.toString
      proc {
        cmd := python,
         args := #[(framework / "tools" / "proofscript" / "target_manifest.py").toString,
           output.toString, selection.pkg.baseName.toString, selection.lib.name.toString,
           selection.kind, targetName] ++ owners.map fun mod => s!"{mod.name.toString}={encodedName mod.name}",
        cwd := ws.root.dir,
        env := ← getAugmentedEnv
      }
      return output / "manifests" / "targets" / selection.pkg.baseName.toString /
        selection.lib.name.toString / selection.kind / s!"{targetName}.json"

/-- Rendering begins only after Lake has compiled and published every owner. -/
def renderTarget (selection : PageTarget) : FetchM (Job FilePath) := do
  let exports ← exportTarget selection
  let ws ← getWorkspace
  let framework := ws.packages.findSome? fun pkg =>
    if pkg.baseName == `ProofScript then some pkg.dir else none
  let some framework := framework | error "ProofScript package not found"
  exports.mapM fun targetFile => do
    let python := (← IO.getEnv "PS4HTML_PYTHON").getD "python3"
    let result := ws.root.dir / ".PS4HTML" / "build" /
      selection.pkg.baseName.toString / selection.lib.name.toString / "index.html"
    proc {
      cmd := python,
      args := #["-m", "PS4HTML", "_render-target", targetFile.toString],
      cwd := ws.root.dir,
      env := (← getAugmentedEnv).push ("PYTHONPATH", some
        (framework / "tools" / "ps4html").toString)
    }
    return result

end ProofScriptPageBuild

/-- Build the complete HTML site for the requested Lean library. -/
library_facet ps4html (lib) : FilePath := do
  ProofScriptPageBuild.renderTarget (.library lib)

/-- Build an isolated HTML preview; use `+Module:ps4html` to select a module explicitly. -/
module_facet ps4html (mod) : FilePath := do
  ProofScriptPageBuild.renderTarget (.module mod)

/-- Export a complete library to the project's .ProofScript directory without rendering HTML. -/
library_facet proofscriptExport (lib) : FilePath := do
  ProofScriptPageBuild.exportTarget (.library lib)

/-- Export one module and update its library's complete input bundle. -/
module_facet proofscriptExport (mod) : FilePath := do
  ProofScriptPageBuild.exportTarget (.module mod)
