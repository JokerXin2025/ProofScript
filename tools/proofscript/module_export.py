"""Finalize and publish one independently built ProofScript module."""

import contextlib
import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path


VERSION = "14.0.0"
PREVIOUS_VERSION = "13.0.0"


def _safe(root: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not relative or any(
        part in ("", ".", "..") for part in relative.split("/")
    ) or "\\" in relative or "\0" in relative:
        raise ValueError(f"unsafe module export path: {relative!r}")
    path = root / relative
    if path.is_symlink() or any(parent.is_symlink() for parent in path.parents
                                if parent == root or root in parent.parents):
        raise ValueError(f"module export path traverses a symlink: {relative!r}")
    return path


def _hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _write(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _write_journal(path: Path, value):
    temporary = path.with_name("journal.next")
    _write(temporary, value)
    with temporary.open("rb") as stream:
        os.fsync(stream.fileno())
    temporary.replace(path)
    _fsync_directory(path.parent)


def _fsync_directory(path: Path):
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _files(root: Path):
    for path in root.rglob("*"):
        if path.is_file():
            yield path.relative_to(root).as_posix()


def _check_casefold_paths(paths):
    seen = set()
    for relative in paths:
        key = relative.casefold()
        if key in seen:
            raise ValueError(f"module output paths collide on case-insensitive filesystems: {relative}")
        seen.add(key)


def _copy_figure(stage: Path, source_root: Path, entry: dict):
    relative = Path(entry["source"])
    if relative.is_absolute() or any(part in ("", ".", "..") for part in relative.parts):
        raise ValueError(f"unsafe figure source: {relative}")
    source = (source_root / entry["source"]).resolve(strict=True)
    if not source.is_relative_to(source_root.resolve()):
        raise ValueError(f"figure leaves source root: {source}")
    target = _safe(stage, entry["path"])
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)


def _build_computations(stage: Path, source_root: Path, proofscript_root: Path,
                        build_manifest: Path, resource_module: str):
    pending = stage / "computations" / "pending"
    if not pending.is_dir() or not any(pending.rglob("*.json")):
        return
    environment = os.environ.copy()
    if not environment.get("PROOF_SCRIPT_LEAN_WASM_PREFIX"):
        for prefix in (
            Path.home() / "Developer" / "lean4-wasm-4.32.0" / "build" / "proof-script-emscripten",
            Path.home() / "Developer" / "lean4-wasm" / "build" / "proof-script-emscripten",
        ):
            if (prefix / "lib" / "lean" / "libleanrt.a").is_file():
                environment["PROOF_SCRIPT_LEAN_WASM_PREFIX"] = str(prefix)
                break
    if not shutil.which("emcc", path=environment.get("PATH")):
        for script in (Path.home() / "Developer" / "emsdk" / "emsdk_env.sh",
                       Path.home() / "emsdk" / "emsdk_env.sh"):
            if not script.is_file():
                continue
            result = subprocess.run(["/bin/bash", "-c", f"source {str(script)!r} >/dev/null 2>&1 && env -0"],
                                    check=True, capture_output=True)
            for item in result.stdout.decode().split("\0"):
                if "=" in item:
                    key, value = item.split("=", 1)
                    environment[key] = value
            if shutil.which("emcc", path=environment.get("PATH")):
                break
    environment["PROOF_SCRIPT_OUTPUT_ROOT"] = str(stage)
    environment["PROOF_SCRIPT_BUILD_MANIFEST"] = str(build_manifest)
    environment["PROOF_SCRIPT_RESOURCE_MODULE"] = resource_module
    # The Node coordinator is part of ProofScript, not the HTML renderer.
    for script in ("build-computations.mjs", "finalize-computations.mjs"):
        subprocess.run(["node", str(proofscript_root / "scripts" / script)],
                       cwd=source_root, env=environment, check=True)


def _verify_computations(stage: Path):
    for page in (stage / "pages").rglob("*.json"):
        document = _json(page)
        for component in document.get("components", []):
            value = component.get("data", {}).get("computation", {}).get("value")
            if value is None:
                continue
            execution = value.get("execution", {})
            if execution.get("status") != "ready":
                raise ValueError(f"unbuilt computation in {page}")
            for key in ("manifest", "module", "wasm"):
                path = execution[key]["$resource"]["path"]
                if not path.startswith(".ProofScript/") or not _safe(
                    stage, path.removeprefix(".ProofScript/")
                ).is_file():
                    raise ValueError(f"missing computation {key}: {path}")


def _validate_resource_references(stage: Path):
    def visit(value):
        if isinstance(value, dict):
            if "$resource" in value:
                resource = value["$resource"]
                path = resource.get("path") if isinstance(resource, dict) else None
                if not isinstance(path, str) or not path.startswith(".ProofScript/"):
                    raise ValueError(f"invalid resource reference: {resource}")
                relative = path.removeprefix(".ProofScript/")
                target = _safe(stage, relative)
                if not target.is_file():
                    raise ValueError(f"missing exported resource: {path}")
                expected_hash = resource.get("hash")
                if not isinstance(expected_hash, str) or len(expected_hash) != 64:
                    raise ValueError(f"invalid resource hash: {path}")
                content = target.read_bytes()
                if resource.get("encoding") == "binary":
                    actual = hashlib.sha256(content).hexdigest()
                elif relative.startswith("resources/") and "/computation/" in relative:
                    actual = hashlib.sha256(content).hexdigest()
                elif resource.get("encoding") == "utf-8":
                    text = content.decode("utf-8")
                    actual = hashlib.sha256(json.dumps(text, ensure_ascii=False,
                        separators=(",", ":")).encode("utf-8")).hexdigest()
                else:
                    raise ValueError(f"unsupported resource encoding: {path}")
                if actual != expected_hash:
                    raise ValueError(f"resource content hash mismatch: {path}")
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    for page in (stage / "pages").rglob("*.json"):
        visit(_json(page))
    for proof in (stage / "proofs").rglob("*.json"):
        visit(_json(proof))


def _seal_figures(stage: Path):
    for page in (stage / "pages").rglob("*.json"):
        document = _json(page)
        changed = False
        for component in document.get("components", []):
            value = component.get("data", {}).get("figure", {}).get("value")
            if not isinstance(value, dict) or not isinstance(value.get("path"), str):
                continue
            path = value["path"]
            if not path.startswith(".ProofScript/"):
                raise ValueError(f"figure has no exported resource: {path}")
            target = _safe(stage, path.removeprefix(".ProofScript/"))
            content = target.read_bytes()
            value["resource"] = {"$resource": {
                "path": path, "hash": hashlib.sha256(content).hexdigest(),
                "mediaType": "application/octet-stream", "encoding": "binary",
                "byteSize": len(content),
            }}
            changed = True
        if changed:
            _write(page, document)


def _validate_figures(stage: Path):
    for page in (stage / "pages").rglob("*.json"):
        for component in _json(page).get("components", []):
            value = component.get("data", {}).get("figure", {}).get("value")
            if not isinstance(value, dict):
                continue
            descriptor = value.get("resource", {}).get("$resource", {})
            if value.get("path") != descriptor.get("path") or descriptor.get("encoding") != "binary":
                raise ValueError(f"figure has no sealed export resource: {page}")


def _seal_proof_references(stage: Path):
    for page in (stage / "pages").rglob("*.json"):
        document = _json(page)
        changed = False
        for component in document.get("components", []):
            for declaration in ("theorem", "lemma"):
                value = component.get("data", {}).get(declaration, {}).get("value")
                if not isinstance(value, dict):
                    continue
                reference = value.get("proof", {}).get("$resource")
                if not isinstance(reference, dict) or not isinstance(reference.get("path"), str):
                    continue
                path = reference["path"]
                if not path.startswith(".ProofScript/proofs/"):
                    raise ValueError(f"invalid proof reference: {path}")
                text = _safe(stage, path.removeprefix(".ProofScript/")).read_text(encoding="utf-8")
                reference["hash"] = hashlib.sha256(json.dumps(text, ensure_ascii=False,
                    separators=(",", ":")).encode("utf-8")).hexdigest()
                changed = True
        if changed:
            _write(page, document)


def _seal_text_references(stage: Path):
    for kind in ("pages", "proofs"):
        for path in (stage / kind).rglob("*.json"):
            document = _json(path)
            changed = False

            def visit(value):
                nonlocal changed
                if isinstance(value, dict):
                    resource = value.get("$resource")
                    if isinstance(resource, dict) and resource.get("encoding") == "utf-8":
                        name = resource.get("path")
                        if isinstance(name, str) and name.startswith(".ProofScript/resources/"):
                            text = _safe(stage, name.removeprefix(".ProofScript/")).read_text(encoding="utf-8")
                            resource["hash"] = hashlib.sha256(json.dumps(text, ensure_ascii=False,
                                separators=(",", ":")).encode("utf-8")).hexdigest()
                            changed = True
                    for child in value.values():
                        visit(child)
                elif isinstance(value, list):
                    for child in value:
                        visit(child)

            visit(document)
            if changed:
                _write(path, document)


def _validate_module_files(stage: Path, module: list, has_components: bool):
    files = set(_files(stage))
    if not has_components:
        if any(path.startswith(("info/", "pages/")) for path in files):
            raise ValueError("configuration-only module exported a page or Info document")
        return
    for kind in ("info", "pages"):
        documents = sorted(path for path in files if path.startswith(f"{kind}/"))
        if len(documents) != 1:
            raise ValueError(f"module export needs exactly one {kind} document: {module}")
        document = _json(stage / documents[0])
        if document.get("schemaVersion") != VERSION or document.get("module") != module:
            raise ValueError(f"invalid {kind} identity: {documents[0]}")
    page = _json(stage / next(path for path in files if path.startswith("pages/")))
    if not isinstance(page.get("components"), list) or not page["components"]:
        raise ValueError("page export has no components")
    if not isinstance(page.get("info"), str) or not page["info"].startswith(".ProofScript/info/"):
        raise ValueError("page does not reference its module Info document")
    if page["info"].removeprefix(".ProofScript/") not in files:
        raise ValueError("page references an Info document outside its module")
    info = _json(stage / next(path for path in files if path.startswith("info/")))
    records = info.get("records")
    if not isinstance(records, list) or not all(isinstance(item, dict) for item in records):
        raise ValueError("invalid module Info records")
    identities = [json.dumps(item.get("identity"), sort_keys=True) for item in records]
    if len(identities) != len(set(identities)):
        raise ValueError("duplicate frozen Info identity")
    for proof in (stage / "proofs").rglob("*.json"):
        document = _json(proof)
        if document.get("module") != ".".join(str(part) for part in module):
            raise ValueError(f"proof belongs to another module: {proof}")


def _validate_owned_paths(value: dict, files: set[str]):
    prefix = value["resourceModule"] + "/"
    name = value["resourceModule"] + ".json"
    module_prefixes = {
        "info/": f"info/{name}",
        "pages/": f"pages/{name}",
        "proofs/": f"proofs/{prefix}",
        "resources/": f"resources/{prefix}",
        "computations/pending/": f"computations/pending/{prefix}",
        "computations/bundles/": f"computations/bundles/{prefix}",
        "computations/indices/": f"computations/indices/{name}",
    }
    for relative in files:
        for category, expected in module_prefixes.items():
            if relative.startswith(category):
                if relative != expected and not (
                    category in ("proofs/", "resources/", "computations/pending/",
                                 "computations/bundles/")
                    and relative.startswith(expected)
                ):
                    raise ValueError(f"module output path escapes ownership: {relative}")
                break
        else:
            raise ValueError(f"unsupported module output path: {relative}")


@contextlib.contextmanager
def _lock(root: Path):
    path = root / "publish.lock"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def _recover(root: Path):
    """Restore interrupted transactions before another module is published."""
    transactions = root / "staging" / "transactions"
    if not transactions.exists():
        return
    for transaction in sorted(transactions.iterdir()):
        if not transaction.is_dir() or transaction.is_symlink():
            raise ValueError(f"invalid publication journal: {transaction}")
        journal = transaction / "journal.json"
        if not journal.is_file():
            # No public path is touched until the prepared journal exists.
            shutil.rmtree(transaction)
            continue
        record = _json(journal)
        if record.get("schemaVersion") != VERSION or record.get("state") not in \
                ("prepared", "committed") or not isinstance(record.get("touched"), list) or \
                not isinstance(record.get("existing"), list) or \
                not set(record["existing"]) <= set(record["touched"]):
            raise ValueError(f"invalid publication journal: {transaction}")
        if record.get("state") != "committed":
            # Check all backups before restoring any path; recovery can be retried.
            for relative in record["existing"]:
                if not _safe(transaction / "backup", relative).is_file():
                    raise ValueError(f"missing publication backup: {relative}")
            for relative in record["touched"]:
                target = _safe(root, relative)
                saved = _safe(transaction / "backup", relative)
                if relative in record["existing"]:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(saved, target)
                else:
                    target.unlink(missing_ok=True)
        shutil.rmtree(transaction)


def _commit(root: Path, stage: Path, files: list[str], old_files: set[str],
            manifest: str, completion: dict):
    transactions = root / "staging" / "transactions"
    transactions.mkdir(parents=True, exist_ok=True)
    transaction = transactions / uuid.uuid4().hex
    transaction.mkdir()
    _fsync_directory(transactions)
    touched = sorted(old_files | set(files) | {manifest})
    existing = []
    try:
        # Pre-stage every new byte before entering the prepared transaction.
        for relative in files:
            staged = _safe(transaction / "new", relative)
            staged.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(stage / relative, staged)
            with staged.open("rb") as stream:
                os.fsync(stream.fileno())
        for relative in touched:
            target = _safe(root, relative)
            if target.is_file():
                backup = _safe(transaction / "backup", relative)
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(target, backup)
                with backup.open("rb") as stream:
                    os.fsync(stream.fileno())
                existing.append(relative)
        record = {"schemaVersion": VERSION, "state": "prepared",
                  "touched": touched, "existing": existing}
        _write_journal(transaction / "journal.json", record)
        _fsync_directory(transaction)
        _fsync_directory(transactions)
        for relative in touched:
            _safe(root, relative).unlink(missing_ok=True)
        for relative in files:
            target = _safe(root, relative)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(_safe(transaction / "new", relative), target)
            with target.open("rb") as stream:
                os.fsync(stream.fileno())
        _write(_safe(root, manifest), completion)
        with _safe(root, manifest).open("rb") as stream:
            os.fsync(stream.fileno())
        record["state"] = "committed"
        _write_journal(transaction / "journal.json", record)
        _fsync_directory(transaction)
    except Exception:
        if (transaction / "journal.json").is_file():
            state = _json(transaction / "journal.json").get("state")
            if state == "prepared":
                _recover(root)
        else:
            shutil.rmtree(transaction)
        raise
    shutil.rmtree(transaction)


def _publish(root: Path, stage: Path, module: list, package: str, library: str,
              manifest: str, has_components: bool):
    root.mkdir(parents=True, exist_ok=True)
    files = sorted(_files(stage))
    if len(files) != len(set(files)):
        raise ValueError("duplicate module output paths")
    _check_casefold_paths(files + [manifest])
    completion = {
        "schemaVersion": VERSION, "module": module,
        "package": package, "library": library,
        "complete": True, "hasComponents": has_components,
        "files": [{"path": path, "sha256": _hash(stage / path)} for path in files],
    }
    if fingerprint := os.environ.get("PROOF_SCRIPT_EXPORT_FINGERPRINT"):
        completion["exportFingerprint"] = fingerprint
    with _lock(root):
        _recover(root)
        destination = _safe(root, manifest)
        old_manifests = root / "manifests" / "modules"
        if old_manifests.is_symlink():
            raise ValueError("module manifest directory is a symlink")
        for other in old_manifests.rglob("*.json"):
            _safe(root, other.relative_to(root).as_posix())
            if other == destination:
                continue
            owner = _json(other)
            if owner.get("schemaVersion") not in (PREVIOUS_VERSION, VERSION) or owner.get("complete") is not True:
                raise ValueError(f"invalid previously published module manifest: {other}")
            owned = {item["path"] for item in owner.get("files", [])}
            other_paths = owned | {other.relative_to(root).as_posix()}
            if {path.casefold() for path in other_paths}.intersection(
                path.casefold() for path in files + [manifest]
            ):
                raise ValueError(f"module output path owned by {other}")
        previous = _json(destination) if destination.is_file() else None
        if previous is not None and (previous.get("module") != module or
                                     previous.get("package") != package or
                                     previous.get("library") != library):
            raise ValueError(f"module export ownership conflict: {manifest}")
        if previous is not None and previous.get("schemaVersion") not in (PREVIOUS_VERSION, VERSION):
            raise ValueError(f"incompatible previous module export: {manifest}")
        old_files = {entry["path"] for entry in previous["files"]} if previous else set()
        for current in root.rglob("*"):
            if not current.is_file() or "staging" in current.relative_to(root).parts:
                continue
            relative = current.relative_to(root).as_posix()
            if relative.casefold() in {path.casefold() for path in files + [manifest]} and \
                    relative not in old_files | {manifest} and relative not in files:
                raise ValueError(f"case-insensitive module output path collision: {relative}")
        if manifest in files or manifest in old_files:
            raise ValueError("module completion manifest overlaps a content file")
        for entry in completion["files"]:
            target = _safe(root, entry["path"])
            if target.is_dir():
                raise ValueError(f"export file collides with directory: {target}")
        for path in old_files:
            _safe(root, path)
        _commit(root, stage, files, old_files, manifest, completion)


def publish(descriptor: Path, root: Path, source_root: Path,
            proofscript_root: Path, build_manifest: Path):
    value = _json(descriptor)
    if value.get("schemaVersion") != VERSION:
        raise ValueError("unsupported ProofScript module export descriptor")
    module = value["module"]
    if not isinstance(module, list) or not module or any(
        not isinstance(part, (str, int)) or isinstance(part, bool) or part == "" or
        (isinstance(part, int) and part < 0) for part in module
    ):
        raise ValueError("invalid module identity")
    manifest = value["manifest"]
    if not manifest.startswith("manifests/modules/"):
        raise ValueError("invalid module completion manifest path")
    resource_module = value["resourceModule"]
    if not isinstance(resource_module, str) or not resource_module or any(
        part in ("", ".", "..") for part in resource_module.split("/")
    ) or "\\" in resource_module:
        raise ValueError("invalid module resource path")
    if not manifest.endswith(f"/{resource_module}.json"):
        raise ValueError("module completion path does not match its identity")
    if not isinstance(value.get("package"), str) or not value["package"] or not isinstance(
        value.get("library"), str
    ) or not value["library"]:
        raise ValueError("invalid module library identity")
    if not isinstance(value.get("hasComponents"), bool):
        raise ValueError("invalid module component flag")
    if not isinstance(value.get("files"), list) or not isinstance(value.get("figures"), list):
        raise ValueError("invalid module output inventory")
    _check_casefold_paths([entry["path"] for entry in value["files"] + value["figures"]])
    root.mkdir(parents=True, exist_ok=True)
    staging = root / "staging"
    staging.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=staging) as temporary:
        stage = Path(temporary)
        expected = set()
        for entry in value["files"]:
            if entry["path"] in expected:
                raise ValueError(f"duplicate module output path: {entry['path']}")
            expected.add(entry["path"])
            target = _safe(stage, entry["path"])
            target.parent.mkdir(parents=True, exist_ok=True)
            if "json" in entry:
                _write(target, entry["json"])
            else:
                target.write_text(entry["text"], encoding="utf-8")
        for figure in value["figures"]:
            if figure["path"] in expected:
                raise ValueError(f"duplicate module output path: {figure['path']}")
            expected.add(figure["path"])
            _copy_figure(stage, source_root, figure)
        _seal_figures(stage)
        _validate_figures(stage)
        _seal_proof_references(stage)
        _seal_text_references(stage)
        _validate_module_files(stage, module, value["hasComponents"])
        _build_computations(stage, source_root, proofscript_root, build_manifest,
                            value["resourceModule"])
        _verify_computations(stage)
        _validate_resource_references(stage)
        _validate_owned_paths(value, set(_files(stage)))
        _publish(root, stage, module, value["package"], value["library"],
                 manifest, value["hasComponents"])


if __name__ == "__main__":
    publish(*(Path(argument).resolve() for argument in sys.argv[1:]))
