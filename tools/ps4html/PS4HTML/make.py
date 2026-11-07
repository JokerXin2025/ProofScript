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
from PS4HTML.page import Page, PageRenderer, build_label_index, directory_modules, discover_pages
from PS4HTML.theorem_graph import TheoremGraph
from PS4HTML.project import PS4HTMLError, find_project_root, validate_project_registry
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
        if snapshot_root.exists():
            from PS4HTML.info import INFO_VERSION
            def current(index_file):
                try:
                    return json.loads(index_file.read_text(encoding="utf-8")).get("schemaVersion") == INFO_VERSION
                except (OSError, ValueError):
                    return False
            libraries = sorted(snapshot_root.glob("*/*/.ProofScript/info/index.json"))
            modules = sorted(snapshot_root.glob("*/.modules/*/.ProofScript/info/index.json"))
            rebuilt = set()
            for index_file in libraries:
                if not current(index_file):
                    continue
                bundle_root = index_file.parent.parent
                target = bundle_root.parent.relative_to(snapshot_root)
                _publish_render(root, root / ".PS4HTML" / "build" / target,
                                export_root=bundle_root)
                rebuilt.add(tuple(target.parts))
            for index_file in modules:
                if not current(index_file):
                    continue
                bundle_root = index_file.parent.parent
                target = bundle_root.parent.relative_to(snapshot_root)
                module_bundle = _validate_render_inputs(bundle_root)
                project = module_bundle.project
                if (project["package"], project["library"]) in rebuilt:
                    continue
                staging = root / ".PS4HTML" / "staging"
                staging.mkdir(parents=True, exist_ok=True)
                with tempfile.TemporaryDirectory(dir=staging) as temporary:
                    stage = Path(temporary)
                    cached = stage / ".ProofScript"
                    shutil.copytree(bundle_root, cached)
                    render_site(root, stage / "site", export_root=cached)
                    _publish_module_site(root, target.parts[0], project["library"], stage)
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
    output = root / ".PS4HTML" / "build" / package / name
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
            selected_project = session.get("selectedProject")
            selected_library = name if kind == "library" else (
                selected_project.get("library") if isinstance(selected_project, dict) else None)
            if not isinstance(selected_library, str) or not selected_library:
                raise PS4HTMLError("Page build session lacks a selected library")
            validate_project_registry(session, package, selected_library, modules)
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
            if kind == "module":
                output = _publish_module_site(root, package, selected_library, stage)
            else:
                _clear_module_snapshots(root, package, selected_library)
            _write_project_index(root, session["projects"])
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


def _clear_module_snapshots(root, package, library):
    """A full library build supersedes older module inputs in cached re-renders."""
    module_inputs = root / ".PS4HTML" / "inputs" / package / ".modules"
    if not module_inputs.is_dir():
        return
    for entry in module_inputs.iterdir():
        link = entry / ".ProofScript"
        if not link.is_symlink():
            continue
        try:
            from PS4HTML.info import InfoBundle
            selected = InfoBundle(link).project
        except (PS4HTMLError, OSError, ValueError):
            continue
        if selected["package"] == package and selected["library"] == library:
            release_link = root / ".PS4HTML" / "releases" / package / ".modules" / entry.name / "current"
            link.unlink()
            release_link.unlink(missing_ok=True)


def _merge_project_bundles(root, previous, current, destination, retained):
    """Build one verifiable library input from the retained module snapshots."""
    from PS4HTML.info import InfoBundle

    sources = []
    if previous.is_dir() and (previous / "info/index.json").is_file():
        try:
            sources.append((previous, InfoBundle(previous)))
        except PS4HTMLError as error:
            raise PS4HTMLError("Previously published pages use an incompatible Info model; "
                               "rebuild the complete library before updating one module") from error
    current_bundle = InfoBundle(current)
    package, library = current_bundle.project["package"], current_bundle.project["library"]
    available = {module for _, bundle in sources for module in bundle.modules}
    available.update(current_bundle.modules)
    for module in retained:
        if module in available:
            continue
        module_root = root / ".PS4HTML" / "inputs" / package / ".modules" / module / ".ProofScript"
        library_root = root / ".PS4HTML" / "inputs" / package / library / ".ProofScript"
        for candidate in (module_root, library_root):
            if not candidate.is_dir():
                continue
            try:
                bundle = InfoBundle(candidate)
            except PS4HTMLError:
                continue
            if bundle.project_id == current_bundle.project_id and module in bundle.modules:
                sources.append((candidate, bundle))
                available.update(bundle.modules)
                break
        if module not in available:
            raise PS4HTMLError(f"Cannot retain {module}: its validated project input is unavailable")
    sources.append((current, current_bundle))
    modules, artifacts, snapshots, files = {}, {}, {}, {}
    retained_without_new_page = {
        module for module in retained if module in current_bundle.modules and
        not any(artifact["kind"] == "page" and artifact["module"] == module
                for artifact in current_bundle.artifacts.values())
    }
    for source, bundle in sources:
        if bundle.project_id != current_bundle.project_id:
            raise PS4HTMLError("Cannot merge inputs from different Lake libraries")
        index = bundle.index
        for entry in index["files"]:
            path = entry["path"]
            target = destination / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source / path, target)
            files[path] = entry
        modules.update((entry["module"], entry) for entry in index["modules"]
                       if bundle is not current_bundle or entry["module"] not in retained_without_new_page)
        for module in bundle.modules:
            if bundle is current_bundle and module in retained_without_new_page:
                continue
            artifacts = {key: entry for key, entry in artifacts.items() if entry["module"] != module}
        artifacts.update((entry["path"], entry) for entry in index["artifacts"]
                         if bundle is not current_bundle or entry["module"] not in retained_without_new_page)
        snapshots.update((entry["id"], entry) for entry in index["snapshots"])
    merged = dict(current_bundle.index)
    merged.update(modules=list(modules.values()), artifacts=list(artifacts.values()),
                  snapshots=list(snapshots.values()), files=list(files.values()))
    (destination / "info" / "index.json").write_text(json.dumps(merged, ensure_ascii=False, indent=2))
    validated = InfoBundle(destination)
    if any(module not in validated.modules or
           not any(artifact["kind"] == "page" and artifact["module"] == module
                   for artifact in validated.artifacts.values()) for module in retained):
        raise PS4HTMLError("Merged project input does not contain every retained page")


def _publish_module_site(root, package, library, stage):
    """Overlay only this module onto a library release, retaining sibling pages."""
    library_target = Path(library)
    published = root / ".PS4HTML" / "build" / package / library
    releases = root / ".PS4HTML" / "releases" / package / library_target
    base = releases / "current" / "site"
    with tempfile.TemporaryDirectory(dir=root / ".PS4HTML" / "staging") as temporary:
        prepared = Path(temporary) / "release"
        site = prepared / "site"
        previous = releases / "current" / ".ProofScript"
        previous_pages = []
        if base.is_dir() and previous.is_dir() and (previous / "info/index.json").is_file():
            previous_pages = discover_pages(root, previous)
        if base.is_dir() and ((releases / "current" / "pages.json").is_file() or previous_pages):
            shutil.copytree(base, site)
        else:
            site.mkdir(parents=True)
        source = stage / "site"
        bundle = _validate_render_inputs(stage / ".ProofScript")
        pages = discover_pages(root, stage / ".ProofScript", bundle=bundle)
        for page in pages:
            path = page.output_path
            if path != Path("index.html"):
                destination = site / path
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source / path, destination)
        for directory in directory_modules(pages):
            path = Path(*directory.split(".")[:-1]) / f"{directory.split('.')[-1]}.html"
            if not (site / path).exists() and (source / path).is_file():
                (site / path).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source / path, site / path)
        for relative in ("assets", ".ProofScript/resources/computation"):
            path = source / relative
            if path.is_dir():
                shutil.copytree(path, site / relative, dirs_exist_ok=True)
        records = {}
        record_path = releases / "current" / "pages.json"
        if record_path.is_file():
            saved = json.loads(record_path.read_text(encoding="utf-8"))
            records = dict(saved.get("pages", saved))
        else:
            for page in previous_pages:
                records[page.module] = {"path": str(page.output_path), "data": json.loads(page.path.read_text())}
        for page in pages:
            records[page.module] = {"path": str(page.output_path), "data": json.loads(page.path.read_text())}
        if not pages and previous.is_dir():
            current_modules = set(bundle.modules)
            for module in current_modules & records.keys():
                # A module-only build without a page retains its published page until a full build.
                if module not in {page.module for page in previous_pages}:
                    raise PS4HTMLError(f"Cannot retain {module}: its previous page input is unavailable")
        index_pages = []
        for name, record in sorted(records.items()):
            data = record["data"]
            path = Path(record["path"])
            if path != Path("index.html") and not (site / path).is_file():
                continue
            source_path = Path(data["source"])
            if not source_path.is_absolute():
                source_path = root / source_path
            index_pages.append(Page(source_path, name, source_path,
                                    data["components"], exported_path=path.with_suffix(".json")))
        root_page = next((page for page in pages if page.output_path == Path("index.html")), None)
        root_contents = ""
        root_navigation = ""
        if root_page is not None and root_page.components:
            renderer = PageRenderer(root, site, build_label_index(pages), pages,
                                    export_root=stage / ".ProofScript", project_info=bundle.project["metadata"],
                                    bundle=bundle)
            root_contents = "\n\n".join(renderer.render_components(root_page, Path("index.html")))
            root_navigation = renderer._theorem_navigation(root_page, Path("index.html"))
        elif root_page is None:
            prior_root = next((page for page in previous_pages if page.output_path == Path("index.html")), None)
            if prior_root is not None and prior_root.components:
                previous_bundle = _validate_render_inputs(previous)
                renderer = PageRenderer(root, site, build_label_index(previous_pages), previous_pages,
                                        export_root=previous, project_info=bundle.project["metadata"],
                                        bundle=previous_bundle)
                root_contents = "\n\n".join(renderer.render_components(prior_root, Path("index.html")))
                root_navigation = renderer._theorem_navigation(prior_root, Path("index.html"))
            elif record_path.is_file():
                retained = saved
                root_contents = retained.get("rootContents", "")
                root_navigation = retained.get("rootNavigation", "")
        (site / "index.html").write_text(
            render_index(index_pages, DEFAULT_LANGUAGE, root_contents, root_navigation,
                         bundle.project["metadata"], project_id=bundle.project_id), encoding="utf-8")
        report = source / "lean2tex-report.json"
        if report.is_file():
            shutil.copy2(report, site / report.name)
        (prepared / "pages.json").write_text(json.dumps({"pages": records, "rootContents": root_contents,
                                                         "rootNavigation": root_navigation}, ensure_ascii=False), encoding="utf-8")
        _merge_project_bundles(root, previous, stage / ".ProofScript",
                               prepared / ".ProofScript", records)
        _publish_release(root, package, library_target, prepared)
    return published


def _safe_module_name(name: str) -> bool:
    """Lake owns Lean name parsing; only reject names unsafe for output paths."""
    return (isinstance(name, str) and all(part and part != ".." for part in name.split("."))
            and not any(char in name for char in "/\\\0")
            and not any(ord(char) < 32 or ord(char) == 127 for char in name))


def _seal_resources(export_root, *, original_pages=None):
    """Seal finalized computation pages and binary resources after Lean has checked source digests."""
    import hashlib
    from PS4HTML.info import digest
    from PS4HTML.large_json import loads as load_large_json
    index_path = export_root / "info" / "index.json"
    index = json.loads(index_path.read_text())
    entries = {entry["path"]: entry for entry in index["files"]}
    for artifact in index["artifacts"]:
        path = artifact["path"].removeprefix(".ProofScript/")
        document = load_large_json((export_root / path).read_text(), parse_float=Decimal)
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
            if relative.parts[1] == ".modules":
                project = _validate_render_inputs(cached).project
                _publish_module_site(root, relative.parts[0], project["library"], stage)
            _write_project_index(root)
            _report_output(output)
        else:
            render_site(root, rendered, export_root=export_root)
            _replace_tree(rendered, output)
            _report_output(output)


def _report_output(output):
    """Report the stable public path, rather than the temporary staging tree."""
    print(f"\n\033[32m\033[1m✓ Output has been saved to \033[4m{output}\033[0m\n")


def _archive_legacy_project_directories(root, directory):
    """Move pre-registry project trees out of the flat, package-wide inventory."""
    old = [entry for entry in directory.iterdir() if entry.is_dir() or entry.is_symlink()]
    if not old:
        return
    archive_root = root / ".PS4HTML" / "archives" / "legacy-projects"
    archive_root.mkdir(parents=True, exist_ok=True)
    for entry in old:
        archive = Path(tempfile.mkdtemp(prefix="projects-", dir=archive_root)) / entry.name
        entry.rename(archive)


def _write_project_index(root, inventory=None):
    import hashlib
    from PS4HTML.info import INFO_VERSION, project_id
    index = root / ".PS4HTML" / "build" / "index.html"
    index.parent.mkdir(parents=True, exist_ok=True)
    inventory_path = root / ".PS4HTML" / "projects.json"
    if inventory is not None:
        inventory = sorted(inventory, key=lambda item: (item["package"], item["library"]))
        next_inventory = inventory_path.with_name("projects.json.next")
        next_inventory.write_text(json.dumps(inventory, ensure_ascii=False), encoding="utf-8")
        next_inventory.replace(inventory_path)
    elif inventory_path.is_file():
        inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
    else:
        inventory = []
    links = []
    packages = {item["package"] for item in inventory}
    if len(packages) > 1:
        raise PS4HTMLError("Published project inventory must belong to one package")
    projects_dir = index.parent / "projects"
    projects_dir.mkdir(exist_ok=True)
    exported_projects_dir = root / ".ProofScript" / "projects"
    exported_projects_dir.mkdir(parents=True, exist_ok=True)
    _archive_legacy_project_directories(root, exported_projects_dir)
    expected_records = set()
    for item in inventory:
        package, library = item["package"], item["library"]
        if not _safe_module_name(package) or not _safe_module_name(library):
            raise PS4HTMLError("Invalid project identity in published inventory")
        path = index.parent / package / library / "index.html"
        metadata = {"title": library}
        if path.is_file():
            bundle_path = root / ".PS4HTML" / "inputs" / package / library / ".ProofScript"
            if bundle_path.is_dir():
                try:
                    metadata = load_project_info(bundle_path)
                except PS4HTMLError:
                    pass
        record = {"schemaVersion": INFO_VERSION, "package": package, "library": library, "metadata": metadata}
        destination = projects_dir / f"{hashlib.sha256(project_id(package, library).encode('utf-8')).hexdigest()}.json"
        expected_records.add(destination.name)
        next_record = destination.with_name(destination.name + ".next")
        next_record.write_text(json.dumps(record, ensure_ascii=False), encoding="utf-8")
        next_record.replace(destination)
        exported_record = exported_projects_dir / destination.name
        next_exported = exported_record.with_name(exported_record.name + ".next")
        next_exported.write_text(json.dumps(record, ensure_ascii=False), encoding="utf-8")
        next_exported.replace(exported_record)
        label = metadata.get("title") or library
        if not path.is_file():
            from PS4HTML.engine import render_index
            staging = root / ".PS4HTML" / "staging"
            staging.mkdir(parents=True, exist_ok=True)
            with tempfile.TemporaryDirectory(dir=staging) as temporary:
                stage = Path(temporary)
                (stage / "site").mkdir()
                _publish_runtime_assets(stage / "site")
                (stage / "site" / "index.html").write_text(
                    render_index([], project_info=metadata,
                                 project_id=project_id(package, library)), encoding="utf-8")
                _publish_release(root, package, Path(library), stage)
        href = quote_url_path(path.relative_to(index.parent).as_posix())
        links.append(f'<li><a href="{href}">{html.escape(label)}</a></li>')
    for stale in projects_dir.glob("*.json"):
        if stale.name not in expected_records:
            stale.unlink()
    for stale in exported_projects_dir.glob("*.json"):
        if stale.name not in expected_records:
            stale.unlink()
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
    project_info = load_project_info(export_root or root / ".ProofScript", bundle=bundle)
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
        render_index(pages, language, root_contents, root_theorem_navigation, project_info,
                     project_id=bundle.project_id), encoding = "utf-8"
    )
    (build_root / "lean2tex-report.json").write_text(
        json.dumps({
            "summary": _diagnostic_summary(renderer.diagnostics),
            "diagnostics": renderer.diagnostics,
        }, ensure_ascii = False, indent = 2),
        encoding = "utf-8",
    )
    return build_root


def load_project_info(export_root, *, bundle=None):
    from PS4HTML.info import InfoBundle
    bundle = bundle or InfoBundle(export_root)
    return bundle.project["metadata"]


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
