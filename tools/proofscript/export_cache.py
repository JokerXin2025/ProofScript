"""Validate a module's completed export against its actual page-mode inputs."""

import hashlib
import json
import sys
from pathlib import Path


def fingerprint(build: Path, exporter: Path, publisher: Path,
                scripts: list[Path]) -> str:
    inventory = json.loads(build.read_text(encoding="utf-8"))
    digest = hashlib.sha256()
    digest.update(json.dumps({key: inventory[key] for key in (
        "selectedProject", "projectRoots", "libraryModules", "closureProjects",
        "moduleProjects")}, sort_keys=True, ensure_ascii=False).encode())
    selected = inventory.get("selectedProject", {})
    if selected.get("package") is None or selected.get("library") is None:
        raise ValueError("missing selected ProofScript library")
    owner = inventory["moduleProjects"][0]["module"]
    paths = [exporter, publisher, *scripts]
    sources = set(inventory["sourcePackages"])
    owners = [entry for entry in inventory["modules"] if entry["name"] == owner]
    if len(owners) != 1 or owners[0]["package"] not in sources:
        raise ValueError(f"missing page-mode olean for {owner}")
    # A dependent module's .olean need not change when an imported module's
    # persistent Info events change. Hash every page-mode import in its closure.
    paths.extend(Path(entry["olean"]) for entry in inventory["modules"]
                 if entry["package"] in sources)
    # Computation bundles also depend on generated C and setup artifacts.
    for entry in inventory["modules"]:
        if entry["package"] in sources:
            paths.extend(Path(entry[key]) for key in ("c", "setup")
                         if entry.get(key) and Path(entry[key]).is_file())
    paths = [path.resolve() for path in paths]
    paths = sorted(set(paths), key=lambda path: str(path))
    # Source files and images do not invalidate a completed export independently:
    # Lake invalidates the oleans, while images are copied on the next export.
    for path in paths:
        digest.update(str(path).encode())
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def completed(root: Path, manifest: Path, value: str) -> bool:
    try:
        record = json.loads(manifest.read_text(encoding="utf-8"))
        if record.get("complete") is not True or \
                record.get("exportFingerprint") != value:
            return False
        for entry in record["files"]:
            relative = entry["path"]
            if not isinstance(relative, str) or any(part in ("", ".", "..")
                                                    for part in relative.split("/")):
                return False
            if hashlib.sha256((root / relative).read_bytes()).hexdigest() != entry["sha256"]:
                return False
        return True
    except (OSError, ValueError, KeyError, TypeError):
        return False


if __name__ == "__main__":
    build, root, manifest, exporter, publisher, *scripts = map(Path, sys.argv[1:])
    value = fingerprint(build, exporter, publisher, scripts)
    # Lake captures stdout; a cache hit returns zero and a miss returns one.
    if completed(root, manifest, value):
        sys.exit(0)
    print(value)
    sys.exit(1)
