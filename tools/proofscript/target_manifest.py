"""Publish a completed Lake target inventory after all module exports succeed."""

import fcntl
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path


VERSION = "14.0.0"


def publish(root: Path, package: str, library: str, kind: str, target: str,
            modules: list[str]) -> Path:
    if kind not in ("library", "module") or not modules or len(modules) != len(set(modules)):
        raise ValueError("invalid ProofScript target inventory")
    root.mkdir(parents=True, exist_ok=True)
    lock = root / "publish.lock"
    with lock.open("a+b") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            transaction = root / "staging" / "transactions"
            if transaction.is_dir() and any(transaction.iterdir()):
                raise ValueError("module publication needs recovery before publishing target")
            entries = []
            for item in modules:
                module, separator, encoded = item.partition("=")
                if not separator or not encoded or any(part in ("", ".", "..") for part in encoded.split("/")):
                    raise ValueError(f"invalid module identity: {item}")
                relative = "manifests/modules/" + encoded + ".json"
                path = root / relative
                data = path.read_bytes()
                value = json.loads(data)
                if (value.get("schemaVersion") != VERSION or value.get("complete") is not True
                        or value.get("package") != package or value.get("library") != library
                        or relative != value.get("manifest", relative) or
                        not isinstance(value.get("module"), list)):
                    raise ValueError(f"invalid module completion: {relative}")
                expected_parts = [f"%N{part}" if type(part) is int else "".join(
                    chr(byte) if byte < 128 and (chr(byte).isalnum() or chr(byte) == "_")
                    else f"%{byte:02X}" for byte in part.encode("utf-8"))
                    for part in value["module"]]
                if encoded != "/".join(expected_parts):
                    raise ValueError(f"module identity does not match encoded path: {relative}")
                for file in value.get("files", []):
                    content = root / file["path"]
                    if hashlib.sha256(content.read_bytes()).hexdigest() != file["sha256"]:
                        raise ValueError(f"incomplete module output: {file['path']}")
                entries.append({"module": value["module"], "path": relative,
                                "sha256": hashlib.sha256(data).hexdigest()})
            destination = root / "manifests" / "targets" / package / library / kind / (target + ".json")
            destination.parent.mkdir(parents=True, exist_ok=True)
            document = {"schemaVersion": VERSION, "package": package, "library": library,
                        "kind": kind, "target": target, "modules": entries}
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=destination.parent,
                                             delete=False) as stream:
                json.dump(document, stream, ensure_ascii=False, indent=2)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
                temporary = Path(stream.name)
            temporary.replace(destination)
            for entry in entries:
                module_name = ".".join(str(part) for part in entry["module"])
                other = (root / "manifests" / "targets" / package / library /
                         ("module" if kind == "library" else "library") /
                         (module_name + ".json" if kind == "library" else library + ".json"))
                if not other.is_file():
                    continue
                previous = json.loads(other.read_text(encoding="utf-8"))
                if (previous.get("schemaVersion") != VERSION or previous.get("kind") == kind or
                        previous.get("package") != package or previous.get("library") != library or
                        not isinstance(previous.get("modules"), list)):
                    continue
                updated_entries = [entry if item.get("module") == entry["module"] else item
                                   for item in previous["modules"]]
                if updated_entries == previous["modules"]:
                    continue
                updated = {**previous, "modules": updated_entries}
                with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=other.parent,
                                                 delete=False) as stream:
                    json.dump(updated, stream, ensure_ascii=False, indent=2)
                    stream.write("\n")
                    stream.flush()
                    os.fsync(stream.fileno())
                    next_target = Path(stream.name)
                next_target.replace(other)
            return destination
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


if __name__ == "__main__":
    print(publish(Path(sys.argv[1]), *sys.argv[2:6], sys.argv[6:]))
