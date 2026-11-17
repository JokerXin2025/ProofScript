"""Plan and verify one read-only Verso batch for a completed target."""

import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path
from urllib.parse import quote

from Lean2TeX.names import select_name
from PS4HTML.info import name_text
from PS4HTML.project import PS4HTMLError


PROTOCOL = "proofscript.verso.render.v1"
ASSETS = {"highlighting.css", "highlighting.js", "popper.js", "tippy.js",
          "tippy-border.css", "marked.js"}


def _hash(text):
    return hashlib.sha256(json.dumps(text, ensure_ascii=False,
        separators=(",", ":")).encode("utf-8")).hexdigest()


def _id(*parts):
    return "psv-" + hashlib.sha256(json.dumps(parts, ensure_ascii=False,
        separators=(",", ":")).encode("utf-8")).hexdigest()[:28]


class VersoFragments:
    def __init__(self, project_root, stage, pages, bundle, destinations, executable):
        self.fragments = {}
        self.hover = {}
        self.executable = Path(executable).resolve()
        if not self.executable.is_file() or not os.access(self.executable, os.X_OK):
            raise PS4HTMLError(f"Verso renderer executable missing: {self.executable}; run lake build proofscriptVersoRender")
        requests = []
        expected = {}
        for page in pages:
            instances = []
            page_id = _id("page", page.module)
            links = []
            for (project, declaration), destination in sorted(destinations.items(),
                    key=lambda entry: (entry[0][0], str(entry[0][1]))):
                if project != bundle.project_id:
                    continue
                href = quote(os.path.relpath(destination.output_path, page.output_path.parent), safe="/")
                href += "#" + quote(destination.anchor, safe="")
                links.append({"name": list(declaration), "targets": [{
                    "short": "theorem", "long": select_name(destination.title, "en",
                        name_text(list(declaration)), theorem=True,
                        lean_last_component=destination.last_component), "href": href}]})
            for index, component in enumerate(page.components):
                data = component.get("data", {})
                tag = "theorem" if "theorem" in data else "lemma" if "lemma" in data else None
                if tag is None:
                    continue
                record = bundle.theorem(data[tag]["value"]["proof"])
                proof = bundle.read(bundle.relative(record.path))
                semantic = proof["semanticCode"]
                resource = bundle.root / semantic["$resource"]["path"].removeprefix(".ProofScript/")
                text = resource.read_text(encoding="utf-8")
                if _hash(text) != semantic["$resource"]["hash"]:
                    raise PS4HTMLError(f"Verso resource hash mismatch: {resource}")
                for language in ("zh", "en"):
                    key = (page.module, index, language)
                    ident = _id("code", page.module, list(record.declaration), index, language)
                    expected[ident] = key
                    instances.append({"id": ident, "context": ident,
                        "declaration": list(record.declaration), "code": proof["code"],
                        "resource": text, "visibleStates": []})
            requests.append({"id": page_id, "links": links, "instances": instances})
        request = {"protocol": PROTOCOL, "pages": requests}
        work = stage / "verso"
        work.mkdir()
        source = work / "request.json"
        result = work / "result.json"
        source.write_text(json.dumps(request, ensure_ascii=False), encoding="utf-8")
        process = subprocess.run([str(self.executable), str(source), str(result), str(work / "assets")],
                                 cwd=project_root, capture_output=True, text=True)
        if process.returncode != 0:
            raise PS4HTMLError(f"Verso renderer failed: {process.stderr or process.stdout}")
        try:
            value = json.loads(result.read_text(encoding="utf-8"))
            if value["protocol"] != PROTOCOL or len(value["pages"]) != len(requests):
                raise ValueError("Verso page count or protocol mismatch")
            seen = set()
            for planned, rendered in zip(requests, value["pages"]):
                if rendered["id"] != planned["id"] or len(rendered["instances"]) != len(planned["instances"]):
                    raise ValueError("Verso instance plan mismatch")
                hover = rendered["hover"]
                if not isinstance(hover, dict) or not all(re.fullmatch(r"\d+", key) and isinstance(item, str)
                                                          for key, item in hover.items()):
                    raise ValueError("Invalid Verso hover table")
                self.hover[planned["id"]] = hover
                for asked, item in zip(planned["instances"], rendered["instances"]):
                    ident, fragment = item["id"], item["html"]
                    if ident != asked["id"] or ident in seen or ident not in expected or not isinstance(fragment, str):
                        raise ValueError("Verso instance identity mismatch")
                    if not fragment.startswith('<code class="hl lean block"') or \
                            f'id="{ident}"' not in fragment or "scriptcheck_" in fragment:
                        raise ValueError("Invalid Verso code fragment")
                    if not set(re.findall(r'data-verso-hover="(\d+)"', fragment)) <= set(hover):
                        raise ValueError("Verso hover reference missing")
                    self.fragments[expected[ident]] = fragment
                    seen.add(ident)
                if rendered["instances"] and not hover:
                    raise ValueError("Verso source instances have no semantic hover data")
            if len(seen) != len(expected):
                raise ValueError("Verso output omitted an instance")
            assets = value["assets"]
            if assets["version"] != "verso-v4.32.0" or \
                    {entry["path"] for entry in assets["files"]} != ASSETS or len(assets["files"]) != len(ASSETS):
                raise ValueError("Verso frontend asset inventory mismatch")
            self.assets = {}
            self.asset_hashes = {}
            for entry in assets["files"]:
                path = work / "assets" / entry["path"]
                text = path.read_text(encoding="utf-8")
                if _hash(text) != entry["hash"]:
                    raise ValueError(f"Verso frontend asset hash mismatch: {path}")
                self.assets[entry["path"]] = path
                self.asset_hashes[entry["path"]] = hashlib.sha256(path.read_bytes()).hexdigest()
            self.cache_key = hashlib.sha256((value["cacheKey"] + hashlib.sha256(
                self.executable.read_bytes()).hexdigest()).encode()).hexdigest()
        except (OSError, KeyError, TypeError, ValueError) as error:
            raise PS4HTMLError(f"Invalid Verso renderer output: {error}") from error

    @staticmethod
    def page_id(module):
        return _id("page", module)

    def fragment(self, module, index, language):
        try:
            return self.fragments[(module, index, language)]
        except KeyError as error:
            raise PS4HTMLError(f"Missing Verso source instance: {module}/{index}/{language}") from error

    def data(self, module):
        return self.hover.get(self.page_id(module), {})

    def publish(self, site):
        destination = site / "verso"
        destination.mkdir(parents=True, exist_ok=True)
        for name, path in self.assets.items():
            shutil.copyfile(path, destination / name)
        (destination / "manifest.json").write_text(json.dumps({"version": "verso-v4.32.0",
            "cacheKey": self.cache_key, "files": [
                {"path": f"verso/{name}", "sha256": self.asset_hashes[name]}
                for name in sorted(self.assets)]}, indent=2), encoding="utf-8")
