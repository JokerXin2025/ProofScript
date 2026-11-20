"""Render a Lake target from completed, independently published module exports."""

import fcntl
import hashlib
import html
import json
import shutil
import os
import re
import tempfile
from contextlib import contextmanager
from pathlib import Path
from urllib.parse import quote as quote_url_path

from Lean2TeX.configuration import interpret
from PS4HTML.config import load_config
from PS4HTML.info import RefInfo, TheoremRecord, name_key, name_text, project_id
from PS4HTML.large_json import loads as load_json
from PS4HTML.project import PS4HTMLError, find_project_root
from PS4HTML.recording import BRANCHES_FIELD, RULE_ID_FIELD, proof_steps
from PS4HTML.render_rules import validate_record, validate_rules
from PS4HTML.schema import validate_document

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


_LIBRARY_SLOTS = re.compile(
    r'(<!-- ps4html-libraries-before:([^\n]*?) -->)(.*?)(<!-- ps4html-libraries-after:\2 -->)', re.S)


def _publish_library_navigation(build, libraries):
    """Fill static sidebar slots for every published library under the build lock."""
    for library in libraries:
        for page in (build / library).rglob("*.html"):
            if page.is_symlink():
                continue
            source = page.read_text(encoding="utf-8")
            def replace(match):
                current = html.unescape(match[2])
                if current != library:
                    return match[0]
                path = page.parent
                def node(name):
                    href = quote_url_path(os.path.relpath(build / name / "index.html", path))
                    return (f'<li><a class="module-tree-node" data-ps-library-link '
                            f'href="{html.escape(href, quote=True)}">'
                            f'<span class="module-tree-node-mark" aria-hidden="true"></span>'
                            f'{html.escape(name)}</a></li>')
                before = "".join(node(name) for name in libraries if name < current)
                after = "".join(node(name) for name in libraries if name > current)
                # Strip previously published siblings before rebuilding from the
                # authoritative directory list; the current branch remains intact.
                branch = re.sub(r'<li><a class="module-tree-node" data-ps-library-link .*?</li>', '', match[3], flags=re.S)
                return match[1] + before + branch + after + match[4]
            updated = _LIBRARY_SLOTS.sub(replace, source)
            if updated != source:
                page.write_text(updated, encoding="utf-8")


def _encoded_name(parts):
    return "/".join(f"%N{part}" if type(part) is int else "".join(
        chr(byte) if byte < 128 and (chr(byte).isalnum() or chr(byte) == "_")
        else f"%{byte:02X}" for byte in part.encode("utf-8")) for part in name_key(parts))


def render_cached_targets():
    """Re-render the latest completed library targets."""
    root = find_project_root(Path.cwd()).resolve()
    targets = sorted((root / ".ProofScript" / "manifests" / "targets").glob("*/*/library/*.json"))
    if not targets:
        raise PS4HTMLError("No completed library export; run lake build <Library>:proofscriptExport")
    config = load_config(root)
    for target in targets:
        render_target(target, config=config)


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
            if (completion.get("complete") is not True or
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
        if target["kind"] == "library":
            info = target.get("info")
            if not isinstance(info, dict) or info.get("path") != f"info/{library}.json":
                raise PS4HTMLError("Invalid library Info snapshot path")
            source = _relative(root, info["path"])
            _digest(source, info["sha256"])
            output = _relative(destination, info["path"])
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, output)
            _digest(output, info["sha256"])
        return target, modules


class ModuleBundle:
    """The renderer-facing view of frozen module Info and proof facts."""

    def __init__(self, root, target, modules):
        self.root = root
        self.project_id = project_id(target["package"], target["library"])
        self.infos = {}
        self.pages = {}
        self.theorems = {}
        self._proof_rules = {}
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
            if (info.get("module") != list(module) or page.get("module") != list(module) or
                    info.get("library") != {"package": target["package"], "library": target["library"]} or
                    page.get("info") != ".ProofScript/" + info_paths[0] or
                    not isinstance(page.get("components"), list) or not page["components"]):
                raise PS4HTMLError(f"Module page/Info identity mismatch: {module}")
            records = {}
            for record in info["records"]:
                identity = record["identity"]
                if (identity.get("kind") not in ("decl", "script") or
                        not isinstance(identity.get("target"), list) or not identity["target"]):
                    raise PS4HTMLError("Unsupported frozen Info identity; rebuild the module export")
                key = (identity["kind"], name_key(identity["target"]))
                if key in records:
                    raise PS4HTMLError(f"Duplicate frozen Info: {key}")
                if identity["kind"] == "decl":
                    from Lean2TeX.names import validate_names
                    try:
                        validate_names(record["value"], name_text(identity["target"]))
                    except ValueError as error:
                        raise PS4HTMLError(str(error)) from error
                records[key] = record["value"]
            contracts = {item["id"]: item["value"] for item in info["contracts"]}
            self.infos[module] = records
            self.pages[module] = page_paths[0]
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
                        if ("name" in value or type(value.get("sorryAx")) is not bool or
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
                            module, ".ProofScript/" + relative)
            for relative in paths:
                if relative not in selected_proofs:
                    continue
                document = _read(root, relative)
                if document.get("module") != name_text(list(module)):
                    raise PS4HTMLError(f"Proof owner mismatch: {relative}")
                resolver = validate_document(document, module_protocol=True)
                semantic = document["semanticCode"]["$resource"]
                semantic_path = semantic["path"].removeprefix(".ProofScript/")
                if semantic_path not in paths or not semantic_path.startswith("resources/"):
                    raise PS4HTMLError(f"Verso resource missing from module inventory: {relative}")
                semantic_file = _relative(root, semantic_path)
                semantic_text = semantic_file.read_text(encoding="utf-8")
                semantic_hash = hashlib.sha256(json.dumps(semantic_text, ensure_ascii=False,
                    separators=(",", ":")).encode("utf-8")).hexdigest()
                if semantic_hash != semantic["hash"]:
                    raise PS4HTMLError(f"Verso resource digest mismatch: {relative}")
                envelope = load_json(semantic_text)
                source_hash = hashlib.sha256(json.dumps(document["code"], ensure_ascii=False,
                    separators=(",", ":")).encode("utf-8")).hexdigest()
                if (not isinstance(envelope, dict) or
                        set(envelope) != {"format", "sourceHash", "declaration", "producer", "highlighted"} or
                        envelope["format"] != "proofscript.verso.highlighted.v1" or
                        envelope["producer"] != "verso-v4.32.0/subverso-0076a9e8" or
                        envelope["sourceHash"] != source_hash or
                        not isinstance(envelope["highlighted"], str)):
                    raise PS4HTMLError(f"Verso semantic envelope invalid: {relative}")
                owner = next((record for record in self.theorems.values()
                              if self.relative(record.path) == relative), None)
                if owner is None or envelope["declaration"] != name_text(list(owner.declaration)):
                    raise PS4HTMLError(f"Verso declaration identity mismatch: {relative}")
                self._proof_rules[relative] = self._rules(module, document, contracts, records, resolver)
        if selected_proofs != set(self._proof_rules):
            raise PS4HTMLError(f"Theorem proof missing from target: {selected_proofs - set(self._proof_rules)}")

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
            for template in info["templates"]:
                value = {key: val for key, val in template["value"].items() if val is not None}
                if "cases" in value:
                    value["cases"] = [{key: val for key, val in case.items() if val is not None}
                                       for case in value["cases"]]
                if "case" in value:
                    value["case"] = {key: val for key, val in value["case"].items() if val is not None}
                templates.append(value)
            if templates:
                fields["template"] = templates
            rule = {"ruleId": name_text(list(identity)), "kind": contract["kind"],
                    "fields": fields, "extra": info["extra"]}
            validate_rules({"module": name_text(list(module)),
                            "imports": [], "rules": [rule]}, name_text(list(module)))
            if path in rules:
                raise PS4HTMLError(f"Duplicate proof binding: {path}")
            rules[path] = rule
        seen = set()

        def visit(steps, parent):
            for index, step in enumerate(proof_steps(steps)):
                path = parent + (index,)
                rule = rules.get(path)
                if rule is None or rule["ruleId"] != step[RULE_ID_FIELD]:
                    raise PS4HTMLError(f"Missing frozen proof binding: {path}")
                validate_record(rule, step, resolver=resolver, path=path)
                seen.add(path)
                if rule["kind"] == "strategy":
                    for branch_index, branch in enumerate(step.get(BRANCHES_FIELD, [])):
                        visit(branch["proof"], path + (BRANCHES_FIELD, branch_index, "proof"))

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

    def theorem(self, reference):
        relative = self.relative(reference["$resource"]["path"])
        for record in self.theorems.values():
            if self.relative(record.path) == relative:
                return record
        raise PS4HTMLError(f"Unknown theorem proof: {reference}")

    def configuration(self, module):
        records = self.infos[module]
        values = {}
        for (kind, target), value in records.items():
            if kind != "decl":
                continue
            fields = {key: field for key, field in value.items() if key != "extra"}
            fields["name_last_component"] = name_text([target[-1]])
            if fields["alias_target"] is not None and not isinstance(fields["alias_target"], str):
                fields["alias_target"] = name_text(fields["alias_target"])
            values[(kind, name_text(list(target)))] = fields
        return interpret(values)

    def proof_rules(self, relative):
        return self._proof_rules[relative]


def render_target(manifest, config=None):
    from PS4HTML.assets import publish_assets
    from PS4HTML.engine import render_index, render_package_index
    from PS4HTML.page import Page, PageRenderer, build_label_index, directory_modules
    from PS4HTML.theorem_graph import TheoremGraph, TheoremDestination
    from PS4HTML.verso import VersoFragments

    root = find_project_root(Path.cwd()).resolve()
    config = config if config is not None else load_config(root)
    staging = root / ".PS4HTML" / "staging"
    staging.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=staging) as temporary:
        stage = Path(temporary)
        exported = stage / ".ProofScript"
        target, modules = snapshot_target(manifest, exported)
        bundle = ModuleBundle(exported, target, modules)
        project_info = config.library_metadata(target["package"], target["library"])
        pages = []
        destinations = {}
        for module, relative in bundle.pages.items():
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
                    key = record.key
                    if key in destinations:
                        raise PS4HTMLError(f"Duplicate theorem destination: {key}")
                    destinations[key] = TheoremDestination(page.output_path,
                        f"theorem-{name_text(list(record.declaration))}",
                        bundle.configuration(record.owner).declaration_info[name_text(list(record.declaration))]["names"],
                        name_text([record.declaration[-1]]), index)
            pages.append(page)
        output_paths = [page.output_path for page in pages]
        if len(set(output_paths)) != len(output_paths) or any(
            path.is_absolute() or ".." in path.parts for path in output_paths):
            raise PS4HTMLError("Duplicate or unsafe module HTML output path")
        pages.sort(key=lambda page: page.module)
        graph = TheoremGraph(bundle.theorems.values(), destinations=destinations, modules=modules)
        site = stage / "site"
        executable = os.environ.get("PROOF_SCRIPT_VERSO_RENDERER") or root / ".lake/build/bin/proofscriptVersoRender"
        verso = VersoFragments(root, stage, pages, bundle, destinations, executable)
        verso.publish(site)
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
                                 export_root=exported, project_info=project_info, bundle=bundle,
                                 verso=verso,
                                default_language=config.default_language,
                                reference_metadata=lambda identity: config.reference_metadata(target["package"], identity))
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
        contents = "\n\n".join(renderer.render_components(home, Path("index.html"))) if home else ""
        navigation = renderer._theorem_navigation(home, Path("index.html")) if home else ""
        (site / "index.html").write_text(render_index(pages, module_contents=contents,
            theorem_navigation=navigation, project_info=project_info,
            default_language=config.default_language,
            project_id=bundle.project_id, asset_root="../assets/", package_home_href="../index.html",
            verso_data=verso.data(home.module) if home else {}), encoding="utf-8")
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
            libraries.sort()
            _publish_library_navigation(build, libraries)
            index = build / "index.html"
            next_index = index.with_name("index.html.next")
            next_index.write_text(render_package_index(target["package"], libraries,
                default_language=config.default_language, project_info=config.metadata(target["package"])), encoding="utf-8")
            next_index.replace(index)
        print(f"[PS4HTML] Rendered {target['package']}/{target['library']} from {len(modules)} modules: {output}")
        return output
