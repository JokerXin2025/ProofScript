import subprocess
import json
import os
import shutil
import fcntl
import tempfile
import html
import sys
from contextlib import contextmanager
from decimal import Decimal
from pathlib import Path
from urllib.parse import quote as quote_url_path
from PS4HTML.engine import render_index
from PS4HTML.page import PageRenderer, build_label_index, directory_modules, discover_pages
from PS4HTML.theorem_graph import TheoremGraph
from PS4HTML.project import PS4HTMLError, find_project_root
from PS4HTML.assets import publish_assets
from PS4HTML.i18n import DEFAULT_LANGUAGE


def _progress_stream():
    """Return the controlling terminal when Lake captures this process's stdout.

    A Lake ``proc`` captures stdout/stderr until the job finishes.  Progress
    written to the controlling terminal therefore remains visible while the
    facet is running, while normal stdout is still retained for diagnostics.
    """
    try:
        return open("/dev/tty", "w", buffering=1, encoding="utf-8")
    except (OSError, UnicodeError):
        return sys.stdout


def _progress(message):
    stream = _progress_stream()
    try:
        print(message, file=stream, flush=True)
    finally:
        if stream is not sys.stdout:
            stream.close()


def make():
    root = find_project_root(Path.cwd())
    print("Using cached ProofScript output; skipping Lean compilation.", flush=True)
    with _project_lock(root):
        snapshot_root = root / ".PS4HTML" / "inputs"
        snapshots = (sorted(snapshot_root.glob("*/*/.ProofScript/pages")) +
                     sorted(snapshot_root.glob("*/.modules/*/.ProofScript/pages"))) if snapshot_root.exists() else []
        if snapshots:
            for pages in snapshots:
                target = pages.parent.parent.relative_to(snapshot_root)
                _publish_render(root, root / ".PS4HTML" / "build" / target,
                                export_root=pages.parent)
        else:
            _publish_render(root, root / ".PS4HTML" / "build" / "cached-project")
        _write_project_index(root)
    return root / ".PS4HTML" / "build"


def build_library(package: str, library: str, modules_and_sources: list[str], *, build_dir: Path):
    return _build_target(package, library, modules_and_sources, build_dir=build_dir)


def build_module(package: str, module: str, source: str, *, build_dir: Path):
    return _build_target(package, module, [module, source], build_dir=build_dir, kind="module")


def _build_target(package: str, name: str, modules_and_sources: list[str], *, build_dir: Path,
                  kind: str = "library"):
    """Build and export in one isolated Lake workspace, then publish atomically."""
    root = find_project_root(Path.cwd()).resolve()
    if not all(_safe_module_name(value) for value in (package, name)):
        raise PS4HTMLError("Invalid package or target name from Lake")
    if len(modules_and_sources) % 2:
        raise PS4HTMLError("Expected module/source pairs from Lake")
    sources = dict(zip(modules_and_sources[::2], modules_and_sources[1::2]))
    modules = set(sources)
    if any(not _safe_module_name(name) for name in modules):
        raise PS4HTMLError("Invalid module list from Lake")
    for module_name, source_name in sources.items():
        if not Path(source_name).is_file():
            raise PS4HTMLError(f"Missing Lean source for {module_name}: {source_name}")
    build_dir = (root / build_dir).absolute()
    target = Path(".modules") / name if kind == "module" else Path(name)
    expected_build = root / ".lake" / "ps4html" / package / target
    page_parents = (root / ".lake", root / ".lake" / "ps4html",
                    root / ".lake" / "ps4html" / package, expected_build.parent, expected_build)
    if (build_dir != expected_build or any(path.is_symlink() for path in page_parents)
            or any(Path(source).resolve().is_relative_to(build_dir.resolve()) for source in sources.values())):
        raise PS4HTMLError(f"Expected a dedicated page build directory: {expected_build}; got {build_dir}")
    lake = _lake_command()
    output = root / ".PS4HTML" / "build" / package / target
    with _project_lock(root):
        stage_root = root / ".PS4HTML" / "staging"
        stage_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=stage_root) as temporary:
            session_path = Path(temporary) / "session.json"
            stage = Path(temporary) / "release"
            stage.mkdir()
            export_root = stage / ".ProofScript"
            session_value = {
                "schemaVersion": 1,
                "package": package,
                "buildRoot": str(build_dir),
                "exportRoot": str(export_root),
            }
            session_value[kind] = name
            if kind == "module":
                session_value["targetKind"] = kind
            session_path.write_text(json.dumps(session_value), encoding="utf-8")
            environment = os.environ.copy()
            environment["PROOF_SCRIPT_OUTPUT_ROOT"] = str(export_root)
            environment["PS4HTML_BUILD_SESSION"] = str(session_path)
            environment["PROOF_SCRIPT_BUILD_MANIFEST"] = str(session_path)
            # The Wasm bundler also needs C IR and setup files from cached support packages.
            environment["LAKE_RESTORE_ARTIFACTS"] = "true"
            _progress(f"[PS4HTML] Cleaning page build output: {build_dir}")
            if build_dir.exists():
                shutil.rmtree(build_dir)
            build_dir.mkdir(parents=True)
            _progress(f"[PS4HTML] Building and exporting {package}/{name} with Lake...")
            # The facet records source packages and runs the exporter before
            # leaving its isolated workspace and import paths.
            lake_target = f"+{name}" if kind == "module" else name
            _run_lake([*lake, "--no-cache", "build", f"@{package}/{lake_target}:ps4htmlInputs"], root, environment)
            session = json.loads(session_path.read_text(encoding="utf-8"))
            if set(session.get("owners", [])) != modules:
                raise PS4HTMLError("Page build session does not match the requested modules")
            index = json.loads((export_root / "info/index.json").read_text())
            original_pages = {artifact["path"]: json.loads(
                (export_root / artifact["path"].removeprefix(".ProofScript/")).read_text(), parse_float=Decimal)
                for artifact in index["artifacts"] if artifact["kind"] == "page"}
            if kind == "module":
                _select_computations(export_root, original_pages.values())
            _build_computations(root, export_root, build_manifest=session_path)
            _seal_resources(export_root, original_pages=original_pages)
            rendered = stage / "site"
            render_site(root, rendered, modules, export_root)
            _publish_release(root, package, target, stage)
            _write_project_index(root)
            _report_output(output)
    return output


def _select_computations(export_root, pages):
    """Imports may emit pending computations; only build entries used by the selected page."""
    pending = export_root / "computations" / "pending"
    selected = set()
    for page in pages:
        for component in page.get("components", []):
            execution = component.get("data", {}).get("computation", {}).get("value", {}).get("execution", {})
            if execution.get("backend") != "wasm" or execution.get("status") != "pending":
                continue
            manifest = execution.get("manifest")
            if not isinstance(manifest, str) or not manifest.startswith(".ProofScript/computations/pending/"):
                raise PS4HTMLError("Invalid pending computation manifest in selected page")
            path = export_root / manifest.removeprefix(".ProofScript/")
            if not path.resolve().is_relative_to(pending.resolve()) or not path.is_file():
                raise PS4HTMLError(f"Missing or invalid pending computation manifest: {manifest}")
            selected.add(path.resolve())
    for path in pending.rglob("*.json"):
        if path.resolve() not in selected:
            path.unlink()


def _lake_command():
    """Keep the outer facet's package configuration in its page build subprocess."""
    command = [os.environ.get("LAKE", "lake")]
    if config := os.environ.get("PS4HTML_LAKE_CONFIG"):
        command.extend(("--file", config))
    arguments = iter(json.loads(os.environ.get("PS4HTML_LAKE_ARGS", "[]")))
    original_cwd = Path(os.environ.get("PS4HTML_LAKE_CWD", os.getcwd()))
    for argument in arguments:
        if argument == "-K":
            command.extend((argument, next(arguments)))
        elif argument.startswith("-K"):
            command.append(argument)
        elif argument == "--packages":
            command.extend((argument, str(original_cwd / next(arguments))))
        elif argument.startswith("--packages="):
            command.extend(("--packages", str(original_cwd / argument.removeprefix("--packages="))))
    return command


def _publish_release(root, package, target, stage):
    """One atomic pointer selects matching input and HTML trees; failed staging is never visible."""
    import hashlib
    releases = root / ".PS4HTML" / "releases" / package / target
    releases.mkdir(parents=True, exist_ok=True)
    identity = hashlib.sha256()
    for path in sorted(stage.rglob("*")):
        if path.is_file():
            identity.update(path.relative_to(stage).as_posix().encode())
            identity.update(path.read_bytes())
    release = releases / identity.hexdigest()
    if not release.exists():
        with tempfile.TemporaryDirectory(dir=releases) as temporary:
            prepared = Path(temporary) / "release"
            shutil.copytree(stage, prepared)
            prepared.rename(release)
    current = releases / "current"
    next_pointer = releases / "current.next"
    next_pointer.unlink(missing_ok=True)
    next_pointer.symlink_to(release.name, target_is_directory=True)
    # Public aliases remain stable across releases and resolve through the one current pointer.
    for alias, target in (
        (root / ".PS4HTML" / "inputs" / package / target / ".ProofScript", current / ".ProofScript"),
        (root / ".PS4HTML" / "build" / package / target, current / "site"),
    ):
        alias.parent.mkdir(parents=True, exist_ok=True)
        if alias.is_symlink():
            continue
        if alias.exists():
            raise PS4HTMLError(f"Expected a release link at {alias}; remove the directory before rebuilding")
        alias.symlink_to(os.path.relpath(target, alias.parent), target_is_directory=True)
    next_pointer.replace(current)


def _safe_module_name(name: str) -> bool:
    """Lake owns Lean name parsing; only reject names unsafe for output paths."""
    return (isinstance(name, str) and all(part and part != ".." for part in name.split("."))
            and not any(char in name for char in "/\\\0")
            and not any(ord(char) < 32 or ord(char) == 127 for char in name))


def _seal_resources(export_root, *, original_pages=None):
    """Seal finalized computation pages and binary resources after Lean has checked source digests."""
    import hashlib
    from PS4HTML.info import digest
    index_path = export_root / "info" / "index.json"
    index = json.loads(index_path.read_text())
    entries = {entry["path"]: entry for entry in index["files"]}
    for artifact in index["artifacts"]:
        path = artifact["path"].removeprefix(".ProofScript/")
        document = json.loads((export_root / path).read_text(), parse_float=Decimal)
        published = digest(document)
        if published != artifact["contentDigest"]:
            if artifact["kind"] != "page":
                raise PS4HTMLError(f"Proof changed after Lean export: {path}")
            original = (original_pages or {}).get(artifact["path"])
            if original is None or not _only_computations_finalized(original, document):
                raise PS4HTMLError(f"Unexpected page change after Lean export: {path}")
            artifact["publishedDigest"] = published
            artifact["transform"] = "finalize-computations"
            entries[path]["digest"] = published
    for path in sorted((export_root / "resources").rglob("*")):
        if path.is_file():
            relative = path.relative_to(export_root).as_posix()
            entries[relative] = {"path": relative, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    index["files"] = list(entries.values())
    index_path.write_text(json.dumps(index, ensure_ascii=False, indent=2))


def _only_computations_finalized(original, published):
    """The computation finalizer may replace execution resources, preserving all page metadata."""
    import copy
    normalized = copy.deepcopy(published)
    before = original.get("components", [])
    after = normalized.get("components", [])
    if len(before) != len(after):
        return False
    for source, target in zip(before, after):
        source_value = source.get("data", {}).get("computation", {}).get("value")
        target_value = target.get("data", {}).get("computation", {}).get("value")
        if not isinstance(source_value, dict) or not isinstance(target_value, dict):
            continue
        old, new = source_value.get("execution", {}), target_value.get("execution", {})
        if old == new:
            continue
        if old.get("backend") != "wasm" or old.get("status") != "pending" or new.get("status") != "ready":
            return False
        if any(old.get(key) != new.get(key) for key in ("backend", "bundleId", "entry", "wrapper")):
            return False
        if not all(isinstance(new.get(key), dict) and "$resource" in new[key] for key in ("manifest", "module", "wasm")):
            return False
        target_value["execution"] = old
    return normalized == original


@contextmanager
def _project_lock(root):
    lock = root / ".PS4HTML" / "build.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open("a+b") as stream:
        fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


def _replace_tree(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    backup = destination.with_name(destination.name + ".previous")
    if backup.exists():
        shutil.rmtree(backup)
    if destination.exists():
        destination.rename(backup)
    try:
        source.rename(destination)
    except Exception:
        if backup.exists():
            backup.rename(destination)
        raise
    if backup.exists():
        shutil.rmtree(backup)


def _publish_render(root, output, export_root=None):
    staging = root / ".PS4HTML" / "staging"
    staging.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=staging) as temporary:
        stage = Path(temporary)
        rendered = stage / "site"
        relative = output.relative_to(root / ".PS4HTML" / "build")
        release_target = (len(relative.parts) == 2 or
                          len(relative.parts) == 3 and relative.parts[1] == ".modules")
        if export_root is not None and release_target:
            cached = stage / ".ProofScript"
            shutil.copytree(export_root, cached)
            render_site(root, rendered, export_root=cached)
            _publish_release(root, relative.parts[0], Path(*relative.parts[1:]), stage)
            _write_project_index(root)
            _report_output(output)
        else:
            render_site(root, rendered, export_root=export_root)
            _replace_tree(rendered, output)
            _report_output(output)


def _report_output(output):
    """Report the stable public path, rather than the temporary staging tree."""
    print(f"\n\033[32m\033[1m✓ Output has been saved to \033[4m{output}\033[0m\n")


def _write_project_index(root):
    index = root / ".PS4HTML" / "build" / "index.html"
    index.parent.mkdir(parents=True, exist_ok=True)
    sites = (sorted(index.parent.glob("*/*/index.html")) +
             sorted(index.parent.glob("*/.modules/*/index.html")) +
             sorted(index.parent.glob("cached-project/index.html")))
    links = []
    for path in sites:
        relative = path.relative_to(index.parent)
        label = (f"{relative.parts[0]}/+{path.parent.name}" if len(relative.parts) == 4
                 else "/".join(relative.parts[:-1]))
        links.append(f'<li><a href="{quote_url_path(relative.as_posix())}">{html.escape(label)}</a></li>')
    next_index = index.with_name("index.html.next")
    next_index.write_text(f'<!doctype html><meta charset="utf-8"><title>PS4HTML</title><ul>{"".join(links)}</ul>', encoding="utf-8")
    next_index.replace(index)


def render_site(root, build_root, modules=None, export_root=None):
    """Render already exported JSON without invoking Lean or computation tools."""
    bundle = _validate_render_inputs(export_root or root / ".ProofScript")
    print("Discovering cached pages...", flush = True)
    all_pages = discover_pages(root, export_root, bundle=bundle)
    theorem_graph = TheoremGraph.from_bundle(bundle, all_pages)
    pages = [page for page in all_pages if modules is None or page.module in modules]
    if not pages:
        raise PS4HTMLError("No ProofScript pages found for the selected modules; close a page with #page end and rebuild")
    project_info = load_project_info(export_root or root / ".ProofScript", modules, bundle=bundle)
    language = DEFAULT_LANGUAGE
    _publish_runtime_assets(build_root)
    _publish_computation_resources(root, build_root, export_root)
    labels = build_label_index(pages)
    renderer = PageRenderer(
        root, build_root, labels, pages,
        default_language=language, theorem_graph=theorem_graph, export_root=export_root,
        project_info=project_info,
        bundle=bundle,
    )
    pages_by_module = {page.module: page for page in pages}
    render_pages = {page.module: page for page in pages if "." in page.module}
    directories = directory_modules(pages)
    virtual_directories = [
        module for module in directories
        if "." in module and module not in pages_by_module
    ]
    for position, module in enumerate(virtual_directories, 1):
        print(f"[PS4HTML] Rendering directory {position}/{len(virtual_directories)}: {module}", flush = True)
        output = build_root / Path(*module.split(".")[:-1]) / f"{module.split('.')[-1]}.html"
        output.parent.mkdir(parents = True, exist_ok = True)
        output.write_text(renderer.render_directory(module), encoding = "utf-8")

    for module in directories:
        if "." in module and module in pages_by_module:
            render_pages[module] = pages_by_module[module]

    pages_to_render = list(render_pages.values())
    for position, page in enumerate(pages_to_render, 1):
        print(f"[PS4HTML] Rendering module {position}/{len(pages_to_render)}: {page.module}", flush = True)
        output = build_root / page.output_path
        output.parent.mkdir(parents = True, exist_ok = True)
        output.write_text(renderer.render(page), encoding = "utf-8")

    build_root.mkdir(parents = True, exist_ok = True)
    print("[PS4HTML] Rendering project index and diagnostics...", flush = True)
    roots = sorted({page.module.split(".")[0] for page in pages})
    root_page = pages_by_module.get(roots[0]) if len(roots) == 1 else None
    root_contents = ""
    root_theorem_navigation = ""
    if root_page is not None:
        root_contents = "\n\n".join(renderer.render_components(root_page, Path("index.html")))
        root_theorem_navigation = renderer._theorem_navigation(root_page, Path("index.html"))
    (build_root / "index.html").write_text(
        render_index(pages, language, root_contents, root_theorem_navigation, project_info), encoding = "utf-8"
    )
    (build_root / "lean2tex-report.json").write_text(
        json.dumps({
            "summary": _diagnostic_summary(renderer.diagnostics),
            "diagnostics": renderer.diagnostics,
        }, ensure_ascii = False, indent = 2),
        encoding = "utf-8",
    )
    return build_root


def load_project_info(export_root, modules=None, *, bundle=None):
    from PS4HTML.info import InfoBundle
    bundle = bundle or InfoBundle(export_root)
    pages = [artifact for artifact in bundle.artifacts.values()
             if artifact["kind"] == "page" and (modules is None or artifact["module"] in modules)]
    if not pages:
        return {}
    roots = {page["module"].split(".")[0] for page in pages}
    root_page = next((page for page in pages if page["module"] in roots), None)
    selected = root_page if root_page is not None else (pages[0] if len(pages) == 1 else None)
    if selected is None or selected.get("projectId") is None:
        return {}
    return bundle.projects(selected["snapshotId"]).get(selected["projectId"], {})


def _validate_render_inputs(export_root):
    """Validate the completed bundle and every step, including hidden and embedded proofs."""
    from PS4HTML.info import InfoBundle
    return InfoBundle(export_root)


def _diagnostic_summary(diagnostics):
    by_code = {}
    missing_constants = {}
    for diagnostic in diagnostics:
        code = diagnostic.get("code", "unknown")
        by_code[code] = by_code.get(code, 0) + 1
        if code == "L2T001" and diagnostic.get("constant"):
            constant = diagnostic["constant"]
            missing_constants[constant] = missing_constants.get(constant, 0) + 1
    return {
        "total": len(diagnostics),
        "byCode": dict(sorted(by_code.items())),
        "missingConstants": dict(sorted(missing_constants.items(), key = lambda item: (-item[1], item[0]))),
    }


def _run_lake(command, project_root, environment=None):
    """Run a build tool and stream its output."""
    process = subprocess.Popen(
        command,
        cwd = project_root,
        env = environment,
        text = True,
        stdout = subprocess.PIPE,
        stderr = subprocess.STDOUT,
        bufsize = 1,
    )
    output = []
    assert process.stdout is not None
    try:
        for line in process.stdout:
            output.append(line)
            _progress(line.rstrip("\n"))
    except KeyboardInterrupt:
        process.terminate()
        process.wait()
        raise
    finally:
        process.stdout.close()
    returncode = process.wait()
    if returncode:
        raise PS4HTMLError(f"Lean build failed:\n{''.join(output)}")


def _proof_script_root(project_root=None):
    configured = os.environ.get("PROOF_SCRIPT_ROOT")
    if configured:
        root = Path(configured).expanduser().resolve()
        if not (root / "scripts" / "build-computations.mjs").is_file():
            raise PS4HTMLError(f"Invalid PROOF_SCRIPT_ROOT: {root}")
        return root
    candidates = []
    if project_root is not None:
        project_root = Path(project_root).resolve()
        candidates.append(project_root)
        manifest = project_root / "lake-manifest.json"
        if manifest.is_file():
            try:
                data = json.loads(manifest.read_text(encoding="utf-8"))
                for package in data.get("packages", []):
                    if package.get("name") == "ProofScript":
                        if package.get("type") == "path":
                            candidates.append(project_root / package["dir"])
                        else:
                            candidates.append(project_root / data.get("packagesDir", ".lake/packages") / "ProofScript")
            except (OSError, ValueError, KeyError) as error:
                raise PS4HTMLError(f"Cannot resolve ProofScript from {manifest}: {error}") from error
        candidates.append(project_root / ".lake" / "packages" / "ProofScript")
    # Development checkout fallback, after the user's resolved Lake dependency.
    candidates.extend(Path(__file__).resolve().parents)
    for candidate in candidates:
        if (candidate / "ProofScript.lean").is_file() and (candidate / "scripts" / "build-computations.mjs").is_file():
            return candidate.resolve()
    raise PS4HTMLError("ProofScript computation scripts not found; set PROOF_SCRIPT_ROOT")


def _build_computations(project_root, export_root=None, *, build_manifest=None):
    export_root = export_root or project_root / ".ProofScript"
    pending = export_root / "computations" / "pending"
    if not pending.is_dir() or not any(pending.rglob("*.json")):
        return
    pending_values = []
    for manifest in pending.rglob("*.json"):
        try:
            value = json.loads(manifest.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise PS4HTMLError(f"Failed to read pending computation manifest {manifest}: {error}") from error
        if isinstance(value, dict):
            pending_values.append(value)
    pending_bundles = {value.get("bundleId") for value in pending_values}
    bundles = export_root / "computations" / "bundles"
    if bundles.is_dir():
        for bundle in bundles.iterdir():
            if bundle.is_dir() and bundle.name not in pending_bundles:
                shutil.rmtree(bundle)
    proof_script = _proof_script_root(project_root)
    # ProofScript's bundler needs the Lean Wasm runtime. Prefer an explicit
    # environment setting, but make the standard PS4HTML command work with the
    # conventional local installation as well.
    if not os.environ.get("PROOF_SCRIPT_LEAN_WASM_PREFIX"):
        candidates = [
            Path.home() / "Developer" / "lean4-wasm-4.32.0" / "build" / "proof-script-emscripten",
            Path.home() / "Developer" / "lean4-wasm" / "build" / "proof-script-emscripten",
        ]
        for candidate in candidates:
            if (candidate / "lib" / "lean" / "libleanrt.a").is_file():
                os.environ["PROOF_SCRIPT_LEAN_WASM_PREFIX"] = str(candidate)
                print(f"[PS4HTML] Using Lean Wasm runtime: {candidate}", flush=True)
                break
    _load_emscripten_environment()
    environment = os.environ.copy()
    environment["PROOF_SCRIPT_OUTPUT_ROOT"] = str(export_root)
    if build_manifest is not None:
        environment["PROOF_SCRIPT_BUILD_MANIFEST"] = str(build_manifest)
    for script in ("build-computations.mjs", "finalize-computations.mjs"):
        print(f"[PS4HTML] Running ProofScript {script}", flush=True)
        _run_lake(["node", str(proof_script / "scripts" / script)], project_root, environment)


def _load_emscripten_environment():
    """Load emsdk variables when a local installation is available."""
    if shutil.which("emcc"):
        return
    candidates = [
        Path.home() / "Developer" / "emsdk" / "emsdk_env.sh",
        Path.home() / "emsdk" / "emsdk_env.sh",
    ]
    script = next((candidate for candidate in candidates if candidate.is_file()), None)
    if script is None:
        return
    command = ["/bin/bash", "-c", f"source {str(script)!r} >/dev/null 2>&1 && env -0"]
    try:
        result = subprocess.run(command, capture_output=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        return
    for item in result.stdout.decode().split("\0"):
        if "=" in item:
            key, value = item.split("=", 1)
            os.environ[key] = value
    if not shutil.which("emcc"):
        return
    print(f"[PS4HTML] Loaded Emscripten environment: {script}", flush=True)


def _publish_computation_resources(project_root, build_root, export_root=None):
    source = (export_root or project_root / ".ProofScript") / "resources" / "computation"
    destination = build_root / ".ProofScript" / "resources" / "computation"
    if source.is_dir():
        shutil.copytree(source, destination, dirs_exist_ok=True)


def _publish_runtime_assets(build_root):
    publish_assets(build_root / "assets")
