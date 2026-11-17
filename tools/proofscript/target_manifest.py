"""Publish a completed Lake target inventory after all module exports succeed."""

import fcntl
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path


def _encoded_name(parts):
    return "/".join(f"%N{part}" if type(part) is int else "".join(
        chr(byte) if byte < 128 and (chr(byte).isalnum() or chr(byte) == "_")
        else f"%{byte:02X}" for byte in part.encode("utf-8")) for part in parts)


def publish(root: Path, package: str, library: str, kind: str, target: str,
            modules: list[str], info: Path | None = None) -> Path:
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
                if (value.get("complete") is not True
                        or value.get("package") != package or value.get("library") != library
                        or relative != value.get("manifest", relative) or
                        not isinstance(value.get("module"), list)):
                    raise ValueError(f"invalid module completion: {relative}")
                if encoded != _encoded_name(value["module"]):
                    raise ValueError(f"module identity does not match encoded path: {relative}")
                for file in value.get("files", []):
                    content = root / file["path"]
                    if hashlib.sha256(content.read_bytes()).hexdigest() != file["sha256"]:
                        raise ValueError(f"incomplete module output: {file['path']}")
                entries.append({"module": value["module"], "path": relative,
                                "sha256": hashlib.sha256(data).hexdigest()})
            snapshot = None
            if kind == "library":
                if info is None:
                    raise ValueError("library target requires frozen Info snapshot")
                snapshot = {"path": f"info/{library}.json"}
                if (not library or library in (".", "..") or "/" in library or "\\" in library
                        or "\0" in library):
                    raise ValueError("unsafe library Info path")
                if _encoded_name([library]) != library:
                    raise ValueError("library Info path needs an encoded library name")
                source = json.loads(info.read_text(encoding="utf-8"))
                records = source.get("records")
                if not isinstance(records, list) or not all(isinstance(item, dict) for item in records):
                    raise ValueError("invalid library Info records")
                identities = [json.dumps(item.get("identity"), sort_keys=True) for item in records]
                if len(identities) != len(set(identities)) or any(
                    not isinstance(item.get("identity"), dict)
                    or item["identity"].get("kind") not in ("decl", "script")
                    or not isinstance(item["identity"].get("target"), list)
                    or not item["identity"]["target"] for item in records
                ):
                    raise ValueError("invalid library Info identities")
                destination_info = root / snapshot["path"]
                if destination_info.is_symlink() or destination_info.parent.is_symlink():
                    raise ValueError("library Info path is a symlink")
                manifests = root / "manifests" / "modules"
                for other in manifests.rglob("*.json"):
                    if other.is_symlink():
                        raise ValueError("module completion path is a symlink")
                    if snapshot["path"].casefold() in {item["path"].casefold() for item in
                            json.loads(other.read_text(encoding="utf-8")).get("files", [])}:
                        raise ValueError("library Info path overlaps a module output")
                if destination_info.is_file():
                    existing = json.loads(destination_info.read_text(encoding="utf-8"))
                    if existing.get("library") != {"package": package, "library": library}:
                        raise ValueError("library Info path is owned by another project")
            elif info is not None:
                raise ValueError("module target cannot publish library Info")
            destination = root / "manifests" / "targets" / package / library / kind / (target + ".json")
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.is_symlink():
                raise ValueError("target manifest path is a symlink")
            document = {"package": package, "library": library,
                         "kind": kind, "target": target, "modules": entries}
            if snapshot is not None:
                document["info"] = snapshot
            temporary_info = None
            temporary = None
            try:
                if snapshot is not None:
                    destination_info.parent.mkdir(parents=True, exist_ok=True)
                    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=destination_info.parent,
                                                     delete=False) as stream:
                        json.dump({"library": {"package": package, "library": library}, "records": records},
                                  stream, ensure_ascii=False, indent=2)
                        stream.write("\n")
                        stream.flush()
                        os.fsync(stream.fileno())
                        temporary_info = Path(stream.name)
                    snapshot["sha256"] = hashlib.sha256(temporary_info.read_bytes()).hexdigest()
                with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=destination.parent,
                                                 delete=False) as stream:
                    json.dump(document, stream, ensure_ascii=False, indent=2)
                    stream.write("\n")
                    stream.flush()
                    os.fsync(stream.fileno())
                    temporary = Path(stream.name)
                if temporary_info is not None:
                    temporary_info.replace(destination_info)
                temporary.replace(destination)
            finally:
                if temporary_info is not None:
                    temporary_info.unlink(missing_ok=True)
                if temporary is not None:
                    temporary.unlink(missing_ok=True)
            for entry in entries:
                module_name = ".".join(str(part) for part in entry["module"])
                other = (root / "manifests" / "targets" / package / library /
                         ("module" if kind == "library" else "library") /
                         (module_name + ".json" if kind == "library" else library + ".json"))
                if not other.is_file():
                    continue
                previous = json.loads(other.read_text(encoding="utf-8"))
                if (previous.get("kind") == kind or
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
    arguments = sys.argv[6:]
    info = None
    if "--info" in arguments:
        index = arguments.index("--info")
        if index != len(arguments) - 2:
            raise ValueError("--info must follow module inventory")
        info = Path(arguments[-1])
        arguments = arguments[:-2]
    print(publish(Path(sys.argv[1]), *sys.argv[2:6], arguments, info))
