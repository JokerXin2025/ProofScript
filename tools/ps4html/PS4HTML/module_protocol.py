"""Render a Lake target from completed, independently published module exports."""

import fcntl
import hashlib
import json
import shutil
import tempfile
from contextlib import contextmanager
from pathlib import Path

from Lean2TeX.configuration import interpret
from PS4HTML.info import RefInfo, TheoremRecord, name_key, name_text, project_id
from PS4HTML.large_json import loads as load_json
from PS4HTML.project import PS4HTMLError, find_project_root
from PS4HTML.recording import BRANCHES_FIELD, PROOF_SCHEMA_VERSION, RULE_ID_FIELD, proof_steps
from PS4HTML.render_rules import validate_record, validate_rules
from PS4HTML.schema import validate_document

VERSION = "14.0.0"


def _diagnostic_summary(diagnostics):
    by_code, missing = {}, {}
    for diagnostic in diagnostics:
        code = diagnostic.get("code", "unknown")
        by_code[code] = by_code.get(code, 0) + 1
        if code == "L2T001" and diagnostic.get("constant"):
            constant = diagnostic["constant"]
            missing[constant] = missing.get(constant, 0) + 1
    return {"total": len(diagnostics), "byCode": dict(sorted(by_code.items())),
            "missingConstants": dict(sorted(missing.items(), key=lambda item: (-item[1], item[0])))}


def _replace_tree(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        raise PS4HTMLError(f"Expected a directory, found a release link: {destination}")
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


def _encoded_name(parts):
    return "/".join(f"%N{part}" if type(part) is int else "".join(
        chr(byte) if byte < 128 and (chr(byte).isalnum() or chr(byte) == "_")
        else f"%{byte:02X}" for byte in part.encode("utf-8")) for part in name_key(parts))


def render_cached_targets():
    """Re-render the latest completed library targets using the current protocol."""
    root = find_project_root(Path.cwd()).resolve()
    targets = sorted((root / ".ProofScript" / "manifests" / "targets").glob("*/*/library/*.json"))
    if not targets:
        raise PS4HTMLError("No completed library export; run lake build <Library>:proofscriptExport")
    for target in targets:
        render_target(target)


def _relative(root, value):
    if not isinstance(value, str) or not value or any(
        part in ("", ".", "..") for part in value.split("/")) or "\\" in value or "\0" in value:
        raise PS4HTMLError(f"Unsafe ProofScript output path: {value!r}")
    path = root / value
    if path.resolve().is_relative_to(root.resolve()) and not any(
        parent.is_symlink() for parent in (path, *path.parents) if parent == root or root in parent.parents
    ):
        return path
    raise PS4HTMLError(f"ProofScript output escapes its root: {value}")


def _read(root, relative):
    return load_json(_relative(root, relative).read_text(encoding="utf-8"))


def _digest(path, expected):
    if not isinstance(expected, str) or len(expected) != 64 or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise PS4HTMLError(f"ProofScript completion digest mismatch: {path}")


@contextmanager
def _lock(path, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as stream:
        fcntl.flock(stream, mode)
        try:
            yield
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)


def snapshot_target(manifest, destination):
    """Copy precisely the target's verified files while holding the publisher lock."""
    root = find_project_root(Path.cwd()).resolve() / ".ProofScript"
    manifest = Path(manifest).resolve()
    if not manifest.is_relative_to(root / "manifests" / "targets"):
        raise PS4HTMLError("Target manifest is outside the ProofScript export root")
    with _lock(root / "publish.lock", fcntl.LOCK_SH):
        if (root / "staging" / "transactions").is_dir() and any((root / "staging" / "transactions").iterdir()):
            raise PS4HTMLError("ProofScript module publication requires recovery")
        target = _read(root, manifest.relative_to(root).as_posix())
        if target.get("schemaVersion") != VERSION:
            raise PS4HTMLError("Unsupported ProofScript target protocol; rebuild with lake build <Library>:proofscriptExport")
        package, library = target.get("package"), target.get("library")
        if not all(isinstance(value, str) and value and value not in (".", "..") and
                   "/" not in value and "\\" not in value for value in (package, library)):
            raise PS4HTMLError("Invalid target project identity")
        entries = target.get("modules")
        if target.get("kind") not in ("module", "library") or not isinstance(entries, list) or not entries:
            raise PS4HTMLError("Invalid target module inventory")
        target_name = target.get("target")
        expected = root / "manifests" / "targets" / package / library / target["kind"]
        if not isinstance(target_name, str) or not target_name or "/" in target_name or "\\" in target_name or "\0" in target_name or manifest != expected / (target_name + ".json"):
            raise PS4HTMLError("Target manifest identity does not match its path")
        if target["kind"] == "module" and (len(entries) != 1 or
                name_text(entries[0].get("module")) != target.get("target")):
            raise PS4HTMLError("Module target contains another module")
        modules, files = {}, set()
        for entry in entries:
            module = name_key(entry["module"])
            name = name_text(list(module))
            if module in modules:
                raise PS4HTMLError(f"Duplicate target module: {name}")
            relative = entry["path"]
            if relative != f"manifests/modules/{_encoded_name(entry['module'])}.json":
                raise PS4HTMLError("Invalid module completion path")
            path = _relative(root, relative)
            _digest(path, entry["sha256"])
            completion = _read(root, relative)
            if (completion.get("schemaVersion") != VERSION or completion.get("complete") is not True or
                    completion.get("module") != list(module) or completion.get("package") != package or
                    completion.get("library") != library or not isinstance(completion.get("files"), list)):
                raise PS4HTMLError(f"Invalid module completion: {relative}")
            expected_files = {"info/" + relative.removeprefix("manifests/modules/"),
                              "pages/" + relative.removeprefix("manifests/modules/")}
            if completion["hasComponents"] is not True and completion["hasComponents"] is not False:
                raise PS4HTMLError(f"Invalid module component flag: {relative}")
            if completion["hasComponents"] and not expected_files <= {item["path"] for item in completion["files"]}:
                raise PS4HTMLError(f"Module completion omits page or Info: {relative}")
            modules[module] = completion
            for file in completion["files"]:
                relative = file["path"]
                if relative in files:
                    raise PS4HTMLError(f"Shared module output: {relative}")
                files.add(relative)
                source = _relative(root, relative)
                _digest(source, file["sha256"])
                output = _relative(destination, relative)
                output.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, output)
                _digest(output, file["sha256"])
        return target, modules


class ModuleBundle:
    """The renderer-facing view of frozen module Info and proof facts."""

    def __init__(self, root, target, modules):
        self.root = root
        self.project_id = project_id(target["package"], target["library"])
        self.modules = modules
        self.infos = {}
        self.theorems = {}
        self.proofs = {}
        self.artifacts = {}
        self.project = {"metadata": {"title": target["library"]}}
        self.project_by_module = {}
        selected_proofs = set()
        for module, completion in modules.items():
            paths = {item["path"] for item in completion["files"]}
            if not completion["hasComponents"]:
                if paths:
                    raise PS4HTMLError(f"Configuration-only module has outputs: {module}")
                continue
            info_paths = [path for path in paths if path.startswith("info/")]
            page_paths = [path for path in paths if path.startswith("pages/")]
            if len(info_paths) != 1 or len(page_paths) != 1:
                raise PS4HTMLError(f"Missing page or Info for {module}")
            info = _read(root, info_paths[0])
            page = _read(root, page_paths[0])
            if (info.get("schemaVersion") != VERSION or page.get("schemaVersion") != VERSION or
                    info.get("module") != list(module) or page.get("module") != list(module) or
                    info.get("library") != {"package": target["package"], "library": target["library"]} or
                    page.get("info") != ".ProofScript/" + info_paths[0] or
                    not isinstance(page.get("components"), list) or not page["components"]):
                raise PS4HTMLError(f"Module page/Info identity mismatch: {module}")
            records = {}
            for record in info["records"]:
                identity = record["identity"]
                key = (identity["kind"], tuple(identity["target"]) if isinstance(identity["target"], list)
                       else identity["target"])
                if key in records:
                    raise PS4HTMLError(f"Duplicate frozen Info: {key}")
                records[key] = record["value"]
            project = records.get(("project", self.project_id))
            if not isinstance(project, dict):
                raise PS4HTMLError(f"Missing frozen project Info: {module}")
            self.project_by_module[module] = project
            contracts = {item["id"]: item["value"] for item in info["contracts"]}
            self.infos[module] = (records, contracts, info_paths[0], page_paths[0])
            for component in page["components"]:
                data = component.get("data", {}) if isinstance(component, dict) else {}
                for tag in ("theorem", "lemma"):
                    if tag in data:
                        value = data[tag]["value"]
                        reference = value["proof"]
                        if not isinstance(reference, dict) or not isinstance(reference.get("$resource"), dict):
                            raise PS4HTMLError(f"Invalid theorem proof reference: {page_paths[0]}")
                        relative = self.relative(reference["$resource"]["path"])
                        if relative in selected_proofs or relative not in paths or not relative.startswith("proofs/"):
                            raise PS4HTMLError(f"Duplicate or missing theorem proof: {relative}")
                        selected_proofs.add(relative)
                        if value.get("projectId") != self.project_id:
                            raise PS4HTMLError(f"Invalid theorem project: {relative}")
                        try:
                            declaration = name_key(value["declaration"])
                            references = tuple(RefInfo(name_key(item["name"]), item["isDependency"])
                                               for item in value["proofRefs"])
                            dependencies = tuple(name_key(item) for item in value["proofDependencies"])
                        except (KeyError, TypeError, ValueError) as error:
                            raise PS4HTMLError(f"Invalid theorem facts: {relative}") from error
                        if (not isinstance(value.get("name"), str) or not value["name"] or
                                type(value.get("sorryAx")) is not bool or
                                any(type(item.is_dependency) is not bool for item in references) or
                                len({item.name for item in references}) != len(references) or
                                len(set(dependencies)) != len(dependencies) or
                                declaration in dependencies or any(item.name == declaration for item in references) or
                                not set(dependencies) <= {item.name for item in references if item.is_dependency}):
                            raise PS4HTMLError(f"Invalid theorem facts: {relative}")
                        key = (self.project_id, declaration)
                        if key in self.theorems:
                            raise PS4HTMLError(f"Duplicate theorem: {declaration}")
                        self.theorems[key] = TheoremRecord(
                            declaration, tag, self.project_id, references, dependencies,
                            relative, relative, module, ".ProofScript/" + relative)
            for relative in paths:
                if relative not in selected_proofs:
                    continue
                document = _read(root, relative)
                if document.get("module") != name_text(list(module)):
                    raise PS4HTMLError(f"Proof owner mismatch: {relative}")
                resolver = validate_document(document, module_protocol=True)
                bindings = self._rules(module, document, contracts, records, resolver)
                self.artifacts[relative] = {"module": name_text(list(module)), "bindings": bindings}
                self.proofs[relative] = document
        if selected_proofs != set(self.proofs):
            raise PS4HTMLError(f"Theorem proof missing from target: {selected_proofs - set(self.proofs)}")

    def _rules(self, module, document, contracts, records, resolver):
        rules = {}
        for binding in document.get("bindings", []):
            path = tuple(binding["path"])
            contract = contracts[binding["contractId"]]
            identity = name_key(contract["ruleId"])
            info = records[("script", identity)]
            color = info["color"]
            fields = {"renderer": info["renderer"], "display": info["display"],
                      "color": [color[key] for key in ("tag", "border", "background")],
                      "board": info.get("board", [])}
            templates = []
            for template in info["template"]:
                value = {key: val for key, val in template["value"].items() if val is not None}
                if "cases" in value:
                    value["cases"] = [{key: val for key, val in case.items() if val is not None}
                                      for case in value["cases"]]
                templates.append(value)
            if templates:
                fields["template"] = templates
            rule = {"ruleId": name_text(list(identity)), "kind": contract["kind"],
                    "fields": fields, "extra": info["extra"]}
            validate_rules({"schemaVersion": PROOF_SCHEMA_VERSION, "module": name_text(list(module)),
                            "imports": [], "rules": [rule]}, name_text(list(module)))
            if path in rules:
                raise PS4HTMLError(f"Duplicate proof binding: {path}")
            rules[path] = rule
        seen = set()

        def visit(steps, parent):
            for index, step in enumerate(proof_steps(steps)):
                path = parent + (index,)
                if step[RULE_ID_FIELD] == "ProofScript.unrecorded" and path not in rules:
                    continue
                rule = rules.get(path)
                if rule is None or rule["ruleId"] != step[RULE_ID_FIELD]:
                    raise PS4HTMLError(f"Missing frozen proof binding: {path}")
                validate_record(rule, step, resolver=resolver, path=path)
                seen.add(path)
                if rule["kind"] == "strategy":
                    for branch_index, branch in enumerate(step.get(BRANCHES_FIELD, [])):
                        visit(branch["proof"], path + (BRANCHES_FIELD, branch_index, "proof"))
                if rule["fields"]["renderer"] == "embed" and isinstance(step.get("proof"), list):
                    visit(step["proof"], path + ("proof",))

        if "proof" in document:
            visit(document["proof"], ("proof",))
        if seen != set(rules):
            raise PS4HTMLError("Orphan frozen proof bindings")
        return rules

    @staticmethod
    def relative(path):
        return str(path).removeprefix(".ProofScript/")

    def file_path(self, relative):
        return _relative(self.root, relative)

    def read(self, relative):
        return _read(self.root, relative)

    def artifact(self, path):
        relative = Path(path).resolve().relative_to(self.root.resolve()).as_posix() if Path(path).is_absolute() else self.relative(path)
        return self.artifacts[relative]

    def theorem(self, reference):
        if isinstance(reference, dict):
            reference = reference["$resource"]["path"]
        relative = self.relative(reference)
        for record in self.theorems.values():
            if self.relative(record.path) == relative:
                return record
        raise PS4HTMLError(f"Unknown theorem proof: {reference}")

    def configuration(self, module=None, snapshot_id=None):
        if module is None:
            module = self.artifacts[self.relative(snapshot_id)]["module"]
        records = self.infos[next(key for key in self.infos if name_text(list(key)) == module)][0]
        values = {}
        for (kind, target), value in records.items():
            if kind not in ("definition", "theorem"):
                continue
            fields = {key: field for key, field in value.items() if key != "extra"}
            if kind == "definition" and fields["alias_info"]["target"] is not None:
                fields["alias_info"] = {"target": name_text(fields["alias_info"]["target"])}
            values[(kind, name_text(list(target)))] = fields
        return interpret(values)

    def proof_rules(self, artifact):
        return artifact["bindings"]


def render_target(manifest):
    from PS4HTML.assets import publish_assets
    from PS4HTML.engine import render_index, render_package_index
    from PS4HTML.page import Page, PageRenderer, build_label_index, directory_modules
    from PS4HTML.theorem_graph import TheoremGraph, TheoremDestination

    root = find_project_root(Path.cwd()).resolve()
    staging = root / ".PS4HTML" / "staging"
    staging.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=staging) as temporary:
        stage = Path(temporary)
        exported = stage / ".ProofScript"
        target, modules = snapshot_target(manifest, exported)
        bundle = ModuleBundle(exported, target, modules)
        pages = []
        destinations = {}
        for module, (records, _contracts, _info, relative) in bundle.infos.items():
            document = bundle.read(relative)
            page = Page(exported / relative, name_text(list(module)), Path(document["source"]),
                        document["components"], exported_path=Path(relative).relative_to("pages"))
            if not isinstance(document["source"], str) or not document["source"]:
                raise PS4HTMLError(f"Invalid page source: {relative}")
            for index, component in enumerate(page.components):
                data = component["data"]
                tag = "theorem" if "theorem" in data else "lemma" if "lemma" in data else None
                if tag:
                    record = bundle.theorem(data[tag]["value"]["proof"])
                    if record.owner != module or record.declaration_kind != tag:
                        raise PS4HTMLError(f"Theorem page/proof mismatch: {relative}")
                    page.declarations[record.path] = name_text(list(record.declaration))
                    key = record.key
                    if key in destinations:
                        raise PS4HTMLError(f"Duplicate theorem destination: {key}")
                    destinations[key] = TheoremDestination(page.output_path,
                        f"theorem-{name_text(list(record.declaration))}", data[tag]["value"]["name"], index)
            pages.append(page)
        output_paths = [page.output_path for page in pages]
        if len(set(output_paths)) != len(output_paths) or any(
            path.is_absolute() or ".." in path.parts for path in output_paths):
            raise PS4HTMLError("Duplicate or unsafe module HTML output path")
        pages.sort(key=lambda page: page.module)
        graph = TheoremGraph(bundle.theorems.values(), destinations=destinations, modules=modules)
        site = stage / "site"
        for completion in modules.values():
            for file in completion["files"]:
                relative = file["path"]
                if "/computation/" not in relative or not relative.startswith("resources/"):
                    continue
                destination = site / ".ProofScript" / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(exported / relative, destination)
        labels = build_label_index(pages)
        renderer = PageRenderer(root, site, labels, pages, theorem_graph=graph,
                                export_root=exported, project_info=bundle.project["metadata"], bundle=bundle)
        renderer.project_by_module = {name_text(list(key)): value
            for key, value in bundle.project_by_module.items()}
        by_module = {page.module: page for page in pages}
        for module in directory_modules(pages):
            if "." not in module or module in by_module:
                continue
            output = site / Path(*module.split(".")[:-1]) / (module.split(".")[-1] + ".html")
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(renderer.render_directory(module), encoding="utf-8")
        for page in pages:
            if "." not in page.module:
                continue
            output = site / page.output_path
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(renderer.render(page), encoding="utf-8")
        roots = {page.module.split(".")[0] for page in pages}
        home = by_module.get(next(iter(roots))) if len(roots) == 1 else None
        home_info = next((value for key, value in bundle.project_by_module.items()
            if name_text(list(key)) == home.module), None) if home else None
        contents = "\n\n".join(renderer.render_components(home, Path("index.html"))) if home else ""
        navigation = renderer._theorem_navigation(home, Path("index.html")) if home else ""
        (site / "index.html").write_text(render_index(pages, module_contents=contents,
            theorem_navigation=navigation, project_info=home_info or bundle.project["metadata"],
            project_id=bundle.project_id, asset_root="../assets/", package_home_href="../index.html"), encoding="utf-8")
        (site / "lean2tex-report.json").write_text(json.dumps({
            "summary": _diagnostic_summary(renderer.diagnostics), "diagnostics": renderer.diagnostics,
        }, ensure_ascii=False, indent=2), encoding="utf-8")
        output = root / ".PS4HTML" / "build" / target["library"]
        with _lock(root / ".PS4HTML" / "build.lock", fcntl.LOCK_EX):
            build = root / ".PS4HTML" / "build"
            build.mkdir(parents=True, exist_ok=True)
            publish_assets(build / "assets")
            _replace_tree(site, output)
            libraries = [directory.name for directory in build.iterdir()
                         if directory.is_dir() and (directory / "index.html").is_file()]
            (build / "assets" / "js" / "libraries.js").write_text(
                "window.PS4HTMLLibraries = " + json.dumps(sorted(libraries), ensure_ascii=False).replace("<", "\\u003c") + ";\n", encoding="utf-8")
            index = build / "index.html"
            next_index = index.with_name("index.html.next")
            next_index.write_text(render_package_index(target["package"], libraries), encoding="utf-8")
            next_index.replace(index)
        print(f"[PS4HTML] Rendered {target['package']}/{target['library']} from {len(modules)} modules: {output}")
        return output
