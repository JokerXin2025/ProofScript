import subprocess
import json
import os
import shutil
import fcntl
import tempfile
from contextlib import contextmanager
from pathlib import Path
from PS4HTML.engine import render_index
from PS4HTML.page import PageRenderer, build_label_index, build_theorem_dependency_index, directory_modules, discover_pages
from PS4HTML.schema import SCHEMA_VERSION
from PS4HTML.project import PS4HTMLError, find_project_root
from PS4HTML.assets import publish_assets
from PS4HTML.i18n import DEFAULT_LANGUAGE


def make():
    root = find_project_root(Path.cwd())
    print("Using cached ProofScript output; skipping Lean compilation.", flush=True)
    with _project_lock(root):
        snapshot_root = root / ".PS4HTML" / "inputs"
        snapshots = sorted(snapshot_root.glob("*/*/.ProofScript/pages")) if snapshot_root.exists() else []
        if snapshots:
            for pages in snapshots:
                package, library = pages.parents[2].name, pages.parents[1].name
                _publish_render(root, root / ".PS4HTML" / "build" / package / library,
                                export_root=pages.parent)
        else:
            _publish_render(root, root / ".PS4HTML" / "build" / "cached-project")
        _write_project_index(root)
    return root / ".PS4HTML" / "build"


def build_library(package: str, library: str, modules_and_sources: list[str]):
    """Called by the Lake facet after Lake has built this library's Lean artifacts."""
    root = find_project_root(Path.cwd())
    if len(modules_and_sources) % 2:
        raise PS4HTMLError("Expected module/source pairs from Lake")
    sources = dict(zip(modules_and_sources[::2], modules_and_sources[1::2]))
    modules = set(sources)
    if any(not _safe_module_name(name) for name in modules):
        raise PS4HTMLError("Invalid module list from Lake")
    output = root / ".PS4HTML" / "build" / package / library
    with _project_lock(root):
        stage_root = root / ".PS4HTML" / "staging"
        stage_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=stage_root) as temporary:
            stage = Path(temporary)
            export_root = stage / ".ProofScript"
            environment = os.environ.copy()
            environment["PROOF_SCRIPT_OUTPUT_ROOT"] = str(export_root)
            for name, source_name in sources.items():
                source = Path(source_name)
                if not source.is_file():
                    raise PS4HTMLError(f"Missing Lean source for {name}: {source}")
                _compile_source(root, source, environment)
            _build_computations(root, export_root)
            rendered = stage / "site"
            render_site(root, rendered, modules, export_root)
            snapshot = root / ".PS4HTML" / "inputs" / package / library / ".ProofScript"
            _replace_tree(export_root, snapshot)
            _replace_tree(rendered, output)
            _write_project_index(root)
    return output


def _safe_module_name(name: str) -> bool:
    """Lake owns Lean name parsing; only reject names unsafe for output paths."""
    return (isinstance(name, str) and all(part and part != ".." for part in name.split("."))
            and not any(char in name for char in "/\\\0")
            and not any(ord(char) < 32 or ord(char) == 127 for char in name))


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
        rendered = Path(temporary) / "site"
        render_site(root, rendered, export_root=export_root)
        _replace_tree(rendered, output)


def _write_project_index(root):
    index = root / ".PS4HTML" / "build" / "index.html"
    index.parent.mkdir(parents=True, exist_ok=True)
    sites = sorted(index.parent.glob("*/*/index.html")) + sorted(index.parent.glob("cached-project/index.html"))
    links = "".join(f'<li><a href="{path.relative_to(index.parent)}">{path.parent.name}</a></li>' for path in sites)
    next_index = index.with_name("index.html.next")
    next_index.write_text(f'<!doctype html><meta charset="utf-8"><title>PS4HTML</title><ul>{links}</ul>', encoding="utf-8")
    next_index.replace(index)


def render_site(root, build_root, modules=None, export_root=None):
    """Render already exported JSON without invoking Lean or computation tools."""
    _validate_render_inputs(export_root or root / ".ProofScript")
    print("Discovering cached pages...", flush = True)
    all_pages = discover_pages(root, export_root)
    pages = [page for page in all_pages if modules is None or page.module in modules]
    if not pages:
        raise PS4HTMLError("No ProofScript pages found for this library")
    project_info = load_project_info(export_root or root / ".ProofScript", modules)
    language = DEFAULT_LANGUAGE
    _publish_runtime_assets(build_root)
    _publish_computation_resources(root, build_root, export_root)
    labels = build_label_index(pages)
    theorem_dependencies = build_theorem_dependency_index(pages, root, export_root)
    renderer = PageRenderer(
        root, build_root, labels, pages,
        default_language=language, theorem_dependencies=theorem_dependencies, export_root=export_root,
        project_info=project_info,
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
    print(f"\n\033[32m\033[1m✓ Output has been saved to \033[4m{build_root}\033[0m\n")
    return build_root


def load_project_info(export_root, modules=None):
    export_root = Path(export_root)
    records = []
    for path in sorted(export_root.glob("projects/**/*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or not isinstance(data.get("module"), str) or not isinstance(data.get("ProjectInfo"), dict):
            raise PS4HTMLError(f"Invalid project_info record: {path}")
        if modules is None or data["module"] in modules:
            records.append((path, data["ProjectInfo"]))
    if len(records) > 1:
        raise PS4HTMLError("project_info may only be configured once: " + ", ".join(str(path) for path, _ in records))
    project_info = records[0][1] if records else {}
    project_file = export_root / "project.json"
    project_file.write_text(
        json.dumps({"schemaVersion": SCHEMA_VERSION, "ProjectInfo": project_info}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    document = json.loads(project_file.read_text(encoding="utf-8"))
    if document.get("schemaVersion") != SCHEMA_VERSION or not isinstance(document.get("ProjectInfo"), dict):
        raise PS4HTMLError(f"Invalid project metadata: {project_file}")
    return document["ProjectInfo"]


def _validate_render_inputs(export_root):
    """Require each proof module's resolved rendering rules before publishing."""
    from PS4HTML.render_rules import (load_effective_rules, validate_record, validate_rules,
                                     validate_template, template_language)
    from Lean2TeX.configuration import ConfigurationIndex
    from PS4HTML.recording import SUPPORTED_RECORDING_VERSIONS, validate_contract
    root = Path(export_root)
    modules = {}
    for path in root.glob("rendering/modules/**/*.json"):
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("schemaVersion") not in SUPPORTED_RECORDING_VERSIONS:
            raise PS4HTMLError(f"Unsupported render module manifest: {path}")
        modules[data["module"]] = data
    if not modules:
        raise PS4HTMLError("Missing rendering module manifests")
    try:
        snapshots = load_effective_rules(root)
        lean2tex_configs = ConfigurationIndex(root)
    except (OSError, ValueError) as error:
        raise PS4HTMLError(f"Invalid rendering inputs: {error}") from error
    events_by_module = {}
    event_files = {}
    for event_path in (*root.glob("tactics/**/*.json"), *root.glob("strategys/**/*.json")):
        data = json.loads(event_path.read_text(encoding="utf-8"))
        if data.get("schemaVersion") not in SUPPORTED_RECORDING_VERSIONS or not isinstance(data.get("events"), list):
            raise PS4HTMLError(f"Unsupported script_info event file: {event_path}")
        if data["module"] not in modules:
            raise PS4HTMLError(f"Missing module manifest for {event_path}")
        sequences = [event["sequence"] for event in data["events"]]
        if sequences != sorted(set(sequences)):
            raise PS4HTMLError(f"Out-of-order script_info events in {event_path}")
        key = (data["module"], event_path.relative_to(root).parts[0])
        if key in event_files:
            raise PS4HTMLError(f"Duplicate script_info event file for {key}: {event_path}")
        event_files[key] = event_path
        events_by_module.setdefault(data["module"], []).extend(data["events"])
    for owner, manifest in modules.items():
        for entry in manifest.get("registrations", []):
            if manifest["schemaVersion"] == "0.1.0" and "recordedFields" not in entry:
                raise PS4HTMLError(f"Missing recordedFields contract in {owner}")
            try:
                validate_contract(entry.get("recordedFields"))
            except ValueError as error:
                raise PS4HTMLError(f"Invalid recording contract in {owner}: {error}") from error
            if entry.get("owner") != owner:
                raise PS4HTMLError(f"Invalid registration owner in {owner}")
            directory = "strategys" if entry.get("strategy") else "tactics"
            if any(event.get("ruleId") == entry.get("ruleId") for event in events_by_module.get(owner, ())):
                if (owner, directory) not in event_files:
                    raise PS4HTMLError(f"Missing {directory} event file for {owner}")
    def incoming_rules(module):
        seen, visiting, ordered = set(), set(), []

        def visit(name):
            if name in visiting:
                raise PS4HTMLError(f"Cyclic rendering imports in {module}: {name}")
            if name in seen:
                return
            if name not in modules:
                raise PS4HTMLError(f"Missing rendering module manifest for {name}")
            visiting.add(name)
            for parent in modules[name].get("imports", []):
                visit(parent)
            visiting.remove(name)
            seen.add(name)
            ordered.append(name)

        for imported in modules[module].get("imports", []):
            visit(imported)

        def imports(owner, ancestor):
            pending, visited = [owner], set()
            while pending:
                current = pending.pop()
                if current == ancestor:
                    return True
                if current in visited:
                    continue
                visited.add(current)
                pending.extend(modules[current].get("imports", []))
            return False

        merged, writers = {}, {}
        for owner in ordered:
            for event in sorted(events_by_module.get(owner, ()), key=lambda entry: entry["sequence"]):
                rule_id, fields = event.get("ruleId"), event.get("fields")
                if not isinstance(rule_id, str) or not isinstance(fields, dict):
                    raise PS4HTMLError(f"Invalid script_info event in {owner}")
                values = merged.setdefault(rule_id, {})
                for key, value in fields.items():
                    if key == "template":
                        try:
                            languages = [template_language(item) for item in value]
                        except (TypeError, ValueError):
                            languages = []
                        if not languages or any(not lang for lang in languages) or len(set(languages)) != len(languages):
                            raise PS4HTMLError(f"Invalid script_info template in {owner}")
                        registration = next((r for module in modules.values()
                                             for r in module.get("registrations", []) if r["ruleId"] == rule_id), None)
                        if registration is None:
                            raise PS4HTMLError(f"Unknown script_info registration {rule_id} in {owner}")
                        try:
                            validate_template(value, registration["strategy"])
                        except ValueError as error:
                            raise PS4HTMLError(f"Invalid script_info template in {owner}: {error}") from error
                        keys = [f"template.{lang}" for lang in languages]
                    else:
                        keys = [key]
                    for field in keys:
                        previous = writers.get((rule_id, field), set())
                        conflicts = [old for old in previous if old != owner and
                                     not imports(owner, old) and not imports(old, owner)]
                        if conflicts:
                            raise PS4HTMLError(f"Conflicting script_info {rule_id}.{field} in {owner} and {conflicts[0]}")
                        writers[(rule_id, field)] = {old for old in previous if not imports(owner, old)} | {owner}
                    if key == "template":
                        existing = values.setdefault("template", [])
                        positions = {template_language(item): index for index, item in enumerate(existing)}
                        for item in value:
                            language = template_language(item)
                            if language in positions:
                                existing[positions[language]] = item
                            else:
                                existing.append(item)
                    else:
                        values[key] = value
        return merged

    for proof_path in root.glob("proofs/**/*.json"):
        document = json.loads(proof_path.read_text(encoding="utf-8"))
        if "proof" not in document:
            continue
        if document.get("schemaVersion") not in SUPPORTED_RECORDING_VERSIONS:
            raise PS4HTMLError(f"Unsupported proof version in {proof_path}")
        proof_module = document.get("module")
        if not isinstance(proof_module, str) or proof_module not in modules:
            raise PS4HTMLError(f"Invalid proof module in {proof_path}")
        try:
            lean2tex_configs.effective(proof_module)
        except (OSError, ValueError, json.JSONDecodeError) as error:
            raise PS4HTMLError(f"Invalid Lean2TeX configuration for {proof_module}: {error}") from error
        rules_path, snapshot = snapshots.get(proof_module, (None, None))
        if snapshot is None:
            raise PS4HTMLError(f"Missing effective rules for {proof_module}")
        try:
            configured = validate_rules(snapshot, proof_module,
                                        modules[proof_module].get("imports"))
        except (OSError, ValueError) as error:
            raise PS4HTMLError(f"Invalid effective rules {rules_path}: {error}") from error
        merged = incoming_rules(proof_module)
        if any(key not in configured or configured[key]["fields"] != value
               for key, value in merged.items()):
            raise PS4HTMLError(f"Effective rule fields disagree with imported script_info in {proof_module}")
        visible = set()
        pending = [proof_module]
        while pending:
            owner = pending.pop()
            if owner in visible:
                continue
            visible.add(owner)
            pending.extend(modules[owner].get("imports", []))
        registrations = {
            entry["ruleId"]: entry for owner in visible
            for entry in modules[owner].get("registrations", [])
        }
        if set(configured) != set(registrations):
            raise PS4HTMLError(f"Effective rules do not cover visible registrations in {proof_module}")
        for rule_id, entry in configured.items():
            registration = registrations[rule_id]
            if entry["strategy"] != registration["strategy"]:
                raise PS4HTMLError(f"Strategy classification differs for {rule_id}")
            if entry.get("recordedFields") != registration.get("recordedFields"):
                raise PS4HTMLError(f"Recording contract differs for {rule_id}")
            default_fields = ({"renderer": "strategy"} if registration["strategy"] else
                              {"template": [{"lang": "zh", "tag": registration["name"], "content": ""}]})
            if rule_id not in merged and entry["fields"] != default_fields:
                raise PS4HTMLError(f"Invalid default rendering rule for {rule_id}")

        def check_records(records, path=()):
            for index, record in enumerate(records):
                if not isinstance(record, dict) or index % 2 == 0:
                    continue
                rule_id = record.get("_ruleId")
                if not isinstance(rule_id, str):
                    raise PS4HTMLError(f"Missing recorded rule ID in {proof_path}, {path} step {index}")
                if rule_id not in configured:
                    raise PS4HTMLError(f"Missing rendering rule for {rule_id} in {proof_module}")
                try:
                    validate_record(configured[rule_id], record, records[index - 1], document["schemaVersion"])
                except ValueError as error:
                    raise PS4HTMLError(f"Invalid recorded step {proof_path}, {path} index {index}: {error}") from error
                if configured[rule_id]["fields"].get("display") is False:
                    continue
                for branch in record.get("branches", []):
                    if isinstance(branch, dict) and isinstance(branch.get("proof"), list):
                        check_records(branch["proof"], path + (f"{index}:{branch['name']}",))
        check_records(document["proof"])


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
    """Run a build tool without starting another Lake build."""
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
            print(line, end = "", flush = True)
    except KeyboardInterrupt:
        process.terminate()
        process.wait()
        raise
    finally:
        process.stdout.close()
    returncode = process.wait()
    if returncode:
        raise PS4HTMLError(f"Lean build failed:\n{''.join(output)}")


def _compile_source(project_root, source, environment=None):
    print(f"\n[PS4HTML] Exporting {source}", flush=True)
    _run_lake(
        [os.environ.get("LEAN", "lean"), str(source)],
        project_root, environment,
    )


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


def _build_computations(project_root, export_root=None):
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
