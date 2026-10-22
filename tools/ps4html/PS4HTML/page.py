import html
import json
import os
from dataclasses import dataclass, field, replace
from pathlib import Path
from urllib.parse import quote as quote_url_path

from PS4HTML.engine import ERROR, SORRY, ProofEngine, render_module_navigation, render_page
from PS4HTML.highlight import highlight_code
from PS4HTML.project import PS4HTMLError
from PS4HTML.Rules.proof_text import ProofTextRenderer
from PS4HTML.Rules.media import render_figure, render_latex
from PS4HTML.Rules.references import render_references
from PS4HTML.schema import ResourceLoader, SCHEMA_VERSION, PROOF_SCHEMA_VERSION, validate_document
from PS4HTML.Rules.computation import render_computation
from PS4HTML.info import InfoBundle, name_text
from PS4HTML.theorem_graph import TheoremGraph, theorem_id


SUPPORTED_COMPUTATION_SCHEMA_VERSION = SCHEMA_VERSION


@dataclass(frozen = True)
class Page:
    path: Path
    module: str
    source: Path
    components: list
    declarations: dict = field(default_factory=dict)
    exported_path: Path | None = None

    @property
    def output_path(self) -> Path:
        if self.exported_path is not None:
            relative = self.exported_path.with_suffix(".html")
            return Path("index.html") if len(relative.parts) == 1 else relative
        if "pages" in self.path.parts:
            position = len(self.path.parts) - 1 - list(reversed(self.path.parts)).index("pages")
            relative = Path(*self.path.parts[position + 1:]).with_suffix(".html")
            return Path("index.html") if len(relative.parts) == 1 else relative
        parts = self.module.split(".")
        if len(parts) == 1:
            return Path("index.html")
        return Path(*parts[:-1]) / f"{parts[-1]}.html"


@dataclass(frozen = True)
class LabelTarget:
    output_path: Path
    anchor: str
    source: Path
    line: int


def load_page(path: Path, project_root: Path) -> Page:
    try:
        data = json.loads(path.read_text(encoding = "utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PS4HTMLError(f"Failed to read page JSON {path}: {error}") from error

    if not isinstance(data, dict):
        raise PS4HTMLError(f"Page JSON must be an object: {path}")
    module = data.get("module")
    source = data.get("source")
    components = data.get("components")
    if not isinstance(module, str) or not module:
        raise PS4HTMLError(f"Page module must be a non-empty string: {path}")
    if not isinstance(source, str) or not source:
        raise PS4HTMLError(f"Page source must be a non-empty string: {path}")
    if not isinstance(components, list):
        raise PS4HTMLError(f"Page components must be an array: {path}")

    source_path = Path(source)
    if not source_path.is_absolute():
        source_path = project_root / source_path
    return Page(path, module, source_path, components)


def discover_pages(project_root: Path, export_root: Path | None = None, *, bundle=None) -> list[Page]:
    output_root = (export_root or project_root / ".ProofScript") / "pages"
    if not output_root.is_dir():
        raise PS4HTMLError(f"ProofScript output directory not found: {output_root}")
    bundle = bundle or InfoBundle(export_root or project_root / ".ProofScript")
    pages = []
    for artifact in bundle.artifacts.values():
        if artifact["kind"] == "page":
            relative = Path(bundle.relative(artifact["path"]))
            page = load_page(bundle.root / relative, project_root)
            pages.append(replace(page, exported_path=relative.relative_to("pages")))
    for page in pages:
        page.declarations.update({artifact["path"]: name_text(artifact["declaration"])
                                  for artifact in bundle.artifacts.values()
                                  if artifact["module"] == page.module and artifact["declaration"] is not None})
    pages.sort(key = lambda page: page.module)
    if not pages:
        raise PS4HTMLError(f"No ProofScript page JSON found in {output_root}")
    return pages


def build_label_index(pages: list[Page]) -> dict[tuple[str, str], LabelTarget]:
    labels = {}
    for page in pages:
        for component in page.components:
            data = component.get("data", {}) if isinstance(component, dict) else {}
            if "text" in data:
                value = data.get("text", {}).get("value", {})
                _collect_heading_labels(value.get("blocks", []), page, labels)
            elif "theorem" in data or "lemma" in data:
                declaration_kind = "theorem" if "theorem" in data else "lemma"
                value = data.get(declaration_kind, {}).get("value", {})
                proof = value.get("proof")
                declaration = _declaration_name(page.module, proof, page.declarations)
                if declaration is not None:
                    _add_label(labels, "theorem", declaration, page, _theorem_anchor(declaration))
            elif "figure" in data or "latex" in data:
                tag = "figure" if "figure" in data else "latex"
                value = data.get(tag, {}).get("value", {})
                label = value.get("metadata", {}).get("label")
                if isinstance(label, str):
                    _add_label(labels, "figure", label, page, f"figure-{label}")
    return labels


def _collect_heading_labels(blocks, page, labels):
    for block in blocks if isinstance(blocks, list) else []:
        if not isinstance(block, dict):
            continue
        if "heading" in block:
            label = block["heading"].get("label")
            if isinstance(label, str):
                _add_label(labels, "heading", label, page, f"heading-{label}")
        elif "quote" in block:
            _collect_heading_labels(block["quote"].get("content", []), page, labels)
        elif "orderedList" in block or "unorderedList" in block:
            key = "orderedList" if "orderedList" in block else "unorderedList"
            for item in block[key].get("items", []):
                _collect_heading_labels(item.get("content", []), page, labels)


def _add_label(labels, kind, label, page, anchor):
    key = (kind, label)
    if key in labels:
        raise PS4HTMLError(f"Duplicate {kind} label: {label}")
    location = _component_location(page, kind, label)
    labels[key] = LabelTarget(page.output_path, anchor, page.source, location)


def _component_location(page, kind, label):
    for component in page.components:
        data = component.get("data", {}) if isinstance(component, dict) else {}
        if kind == "theorem" and ("theorem" in data or "lemma" in data):
            tag = "theorem" if "theorem" in data else "lemma"
            value = data[tag].get("value", {})
            if _declaration_name(page.module, value.get("proof"), page.declarations) != label:
                continue
        elif kind == "heading" and "text" in data:
            continue
        else:
            continue
        start = component.get("source", {}).get("start", 0)
        try:
            return page.source.read_bytes()[:start].count(b"\n") + 1
        except OSError:
            return 0
    return 0


class PageRenderer:
    def __init__(self, project_root: Path, build_root: Path, labels, pages = None, default_language="zh", theorem_graph=None, export_root=None, project_info=None, bundle=None):
        self.project_root = project_root
        self.export_root = export_root or project_root / ".ProofScript"
        self.build_root = build_root
        self.labels = labels
        self.pages = list(pages or [])
        self.project_info = project_info or {}
        self.default_language = default_language if default_language in ("zh", "en") else "zh"
        self.diagnostics = []
        self.resources = ResourceLoader(project_root, export_root)
        self.bundle = bundle or InfoBundle(self.export_root)
        self.theorem_graph = theorem_graph if theorem_graph is not None else TheoremGraph.from_bundle(
            self.bundle, discover_pages(project_root, self.export_root, bundle=self.bundle))
        self.rendered_outputs = frozenset(page.output_path for page in self.pages)

    def render(self, page: Page) -> str:
        current_output = page.output_path
        contents = self.render_components(page, current_output)
        contents.extend(self._descendant_index(page.module, current_output))
        index_href = os.path.relpath(self.build_root / "index.html", (self.build_root / current_output).parent)
        pages = self.pages or [page]
        theorem_navigation = self._theorem_navigation(page, current_output)
        navigation = render_module_navigation(pages, current_output, page.module, index_href, self.default_language, theorem_navigation, self.project_info)
        return render_page(page.module, "\n\n".join(contents), index_href, navigation, self.default_language)

    def _theorem_navigation(self, page, current_output):
        templates = []
        current_dir = current_output.parent
        for component in page.components:
            data = component.get("data", {}) if isinstance(component, dict) else {}
            tag = "theorem" if "theorem" in data else "lemma" if "lemma" in data else None
            if tag is None:
                continue
            record = self.bundle.theorem(data[tag]["value"]["proof"])
            key = record.key
            graph = self.theorem_graph
            identity = theorem_id(key)
            levels = []
            for css_class, title_zh, title_en, keys in (
                ("incoming", "当前定理依赖的定理", "Theorems used by the current theorem", graph.uses[key]),
                ("outgoing", "依赖当前定理的定理", "Theorems using the current theorem", graph.used_by[key]),
            ):
                links = []
                for other_key in graph.ordered(keys):
                    destination = graph.destinations.get(other_key)
                    declaration = html.escape(name_text(list(other_key[1])), quote=True)
                    label = html.escape(graph.title(other_key))
                    mark = '<span class="theorem-dependency-mark" aria-hidden="true"></span>'
                    if destination and (destination.output_path in self.rendered_outputs or destination.output_path == current_output):
                        href = quote_url_path(os.path.relpath(destination.output_path, current_dir)) + f"#{quote_url_path(destination.anchor)}"
                        node = f'<a class="theorem-dependency-node" href="{html.escape(href, quote=True)}" title="{declaration}">{mark}{label}</a>'
                    else:
                        node = f'<span class="theorem-dependency-node is-unlinked" title="{declaration}">{mark}{label}</span>'
                    links.append(
                        f'<li data-theorem-node="{theorem_id(other_key)}">{node}</li>'
                    )
                if links:
                    levels.append(
                        f'<ul class="theorem-dependency-level {css_class}" aria-label="{html.escape(title_zh, quote=True)}" data-label-en="{html.escape(title_en, quote=True)}">{"".join(links)}</ul>'
                    )
                else:
                    levels.append("")
            incoming, outgoing = levels
            templates.append(
                f'<template class="theorem-dependency-template" data-theorem-id="{identity}"><div class="theorem-dependency-graph">{incoming}<div class="theorem-dependency-current" data-theorem-node="{identity}"><span class="theorem-dependency-mark" aria-hidden="true"></span><strong>{html.escape(graph.title(key))}</strong></div>{outgoing}</div></template>'
            )
        if not templates:
            return ""
        return (
            '<section class="theorem-dependency-navigation" hidden>'
            '<h3><span data-language-panel="zh">定理依赖</span><span data-language-panel="en" hidden>Theorem dependencies</span></h3>'
            '<div class="theorem-dependency-panel" data-theorem-navigation-content></div>'
            + "".join(templates) + '</section>'
        )

    def render_components(self, page: Page, current_output: Path) -> list[str]:
        return [self._component(component, page, current_output) for component in page.components]

    def render_directory(self, module: str) -> str:
        current_output = _module_output_path(module)
        contents = self._descendant_index(module, current_output)
        index_href = os.path.relpath(self.build_root / "index.html", (self.build_root / current_output).parent)
        navigation = render_module_navigation(
            self.pages, current_output, module, index_href, self.default_language,
            project_info=self.project_info
        )
        return render_page(module, "\n\n".join(contents), index_href, navigation, self.default_language)

    def _descendant_index(self, module, current_output):
        descendants = [
            page for page in self.pages
            if page.module.startswith(f"{module}.")
        ]
        if not descendants:
            return []
        current_dir = current_output.parent
        tree = {}
        for page in descendants:
            relative = page.module.split(".")[len(module.split(".")):]
            nodes = tree
            for part in relative:
                node = nodes.setdefault(part, {"page": None, "children": {}})
                nodes = node["children"]
            node["page"] = page
        return [
            f'<ul class="module-index-tree">{_render_index_tree(tree, current_dir, module.split("."))}</ul>'
        ]

    def _component(self, component, page, current_output):
        if not isinstance(component, dict) or not isinstance(component.get("data"), dict):
            raise PS4HTMLError(f"Invalid component in {page.path}")
        data = component["data"]
        if len(data) != 1:
            raise PS4HTMLError(f"Component must contain exactly one tag in {page.path}")
        tag = next(iter(data))
        envelope = data[tag]
        value = envelope.get("value") if isinstance(envelope, dict) else None
        if tag == "text":
            return ProofTextRenderer(self.labels, self.build_root, current_output).render(value)
        if tag in {"theorem", "lemma"}:
            return self._theorem(value, component.get("source", {}), page, tag)
        if tag == "latex":
            rendered, diagnostics = render_latex(value, self.project_root, self.resources)
            self.diagnostics.extend(diagnostics)
            return rendered
        if tag == "figure":
            rendered, diagnostics = render_figure(value, self.project_root)
            self.diagnostics.extend(diagnostics)
            return rendered
        if tag == "computation":
            if not isinstance(value, dict) or value.get("schemaVersion") != SUPPORTED_COMPUTATION_SCHEMA_VERSION:
                self.diagnostics.append({
                    "kind": "computation-error",
                    "message": f"Unsupported computation schema version: {value.get('schemaVersion') if isinstance(value, dict) else None}",
                })
            return render_computation(value)
        if tag == "references":
            panels = []
            for language in ("zh", "en"):
                panel = render_references(value, self.labels, self.build_root, current_output, language)
                hidden = "" if language == self.default_language else " hidden"
                panels.append(f'<div data-language-panel="{language}"{hidden}>{panel}</div>')
            return "\n".join(panels)
        return self._placeholder(tag, value)

    def _theorem(self, value, location, page, declaration_kind="theorem"):
        state = None
        expression_resolver = None
        proof_data = []
        code = ""
        name = value.get("name") if isinstance(value, dict) else None
        proof = value.get("proof") if isinstance(value, dict) else None
        sorry_ax = value.get("sorryAx") if isinstance(value, dict) else None
        record = self.bundle.theorem(proof)
        declaration = name_text(list(record.declaration))
        identity = theorem_id(record.key)
        if not isinstance(name, str) or not name:
            name = "Invalid theorem"
            state = ERROR
        if not isinstance(proof, str) or not proof or not isinstance(sorry_ax, bool):
            state = ERROR
        elif sorry_ax:
            state = SORRY

        proof_relative = self.bundle.relative(record.path)
        proof_path = self.bundle.file_path(proof_relative)
        proof_document = self.bundle.read(proof_relative)
        expression_resolver = validate_document(proof_document)
        if isinstance(proof_document, dict):
            if proof_document.get("schemaVersion") != PROOF_SCHEMA_VERSION:
                state = ERROR
            if isinstance(proof_document.get("code"), str):
                code = proof_document["code"]
            else:
                state = ERROR
            if isinstance(proof_document.get("proof"), list):
                proof_data = proof_document["proof"]
            elif isinstance(proof_document.get("code"), str) and state != ERROR:
                code = proof_document["code"]
                highlighted_code, _applied = highlight_code(code, "lean4", theme="light")
                return _render_code_only_declaration(
                    declaration_kind, name,
                    _theorem_anchor(declaration),
                    highlighted_code,
                    code.count("\n") + (1 if code else 0), identity
                )
            else:
                state = ERROR
        else:
            state = ERROR

        source_file = Path(location.get("file", page.source)) if isinstance(location, dict) else page.source
        if not source_file.is_absolute():
            source_file = self.project_root / source_file
        anchor = _theorem_anchor(declaration)
        highlighted_code, _applied = highlight_code(code, "lean4", theme = "light")
        lines = code.count("\n") + (1 if code else 0)
        rendered = []
        rules = None
        step_rules = None
        lean2tex_config = None
        if proof_data:
            if proof_document.get("module") != page.module:
                raise PS4HTMLError(f"Proof module does not match page: {proof_path}")
            artifact = self.bundle.artifact(proof_path)
            step_rules = self.bundle.proof_rules(artifact)
            try:
                lean2tex_config = self.bundle.configuration(snapshot_id=artifact["snapshotId"])
            except (OSError, ValueError, json.JSONDecodeError) as error:
                raise PS4HTMLError(f"Invalid Lean2TeX configuration for {page.module}: {error}") from error
        for language in ("zh", "en"):
            engine = ProofEngine(
                proof_data,
                language=language,
                project_root=self.project_root,
                expression_resolver=expression_resolver,
                resource_loader=self.resources,
                resource_stack=(proof_path.resolve(),),
                rules=rules,
                lean2tex_config=lean2tex_config,
                step_rules=step_rules,
            )
            rendered.append(engine.make(
                name,
                source_file,
                lines,
                highlighted_code,
                anchor if language == "zh" else f"{anchor}-en",
                state = state,
                language = language,
                default_language = self.default_language,
                theorem_id = identity,
            ))
            self.diagnostics.extend({
                "theorem": name,
                "proof": record.path,
                "language": language,
                **diagnostic,
            } for diagnostic in engine.diagnostics)
        return "\n\n".join(rendered)

    @staticmethod
    def _placeholder(tag, value):
        title = tag
        if isinstance(value, dict):
            title = value.get("metadata", {}).get("title") or tag
        preserved = html.escape(json.dumps(value, ensure_ascii=False), quote=True)
        return f'<section class="unsupported-component" data-component="{html.escape(tag, quote = True)}" data-component-value="{preserved}"><strong>{html.escape(str(title))}</strong><span>Component rendering is not supported yet.</span></section>'


def _render_code_only_declaration(kind, name, anchor, code, lines, theorem_id):
    return f'''<section class="theorem-proof theorem-code-only" id="{html.escape(anchor, quote=True)}" data-theorem-id="{html.escape(theorem_id, quote=True)}">
  <h2><span>{html.escape(name)}</span></h2>
  <div class="proof-source-card">
    <div class="code-header"><span>{html.escape(kind.title())}</span><span>{lines} 行</span></div>
    <pre class="page-code code-highlighted"><code>{code}</code></pre>
  </div>
</section>'''


def _theorem_anchor(declaration) -> str:
    return f"theorem-{declaration}" if isinstance(declaration, str) and declaration else "theorem-proof"


def directory_modules(pages: list[Page]) -> list[str]:
    modules = set()
    for page in pages:
        parts = page.module.split(".")
        modules.update(".".join(parts[:end]) for end in range(1, len(parts)))
    return sorted(modules)


def _module_output_path(module: str) -> Path:
    parts = module.split(".")
    if len(parts) == 1:
        return Path("index.html")
    return Path(*parts[:-1]) / f"{parts[-1]}.html"


def _declaration_name(module, proof, declarations=None) -> str | None:
    if declarations and isinstance(proof, str):
        normalized = Path(proof).as_posix()
        if normalized in declarations:
            return declarations[normalized]
    if not isinstance(proof, str) or not proof:
        return None
    path = Path(proof)
    try:
        parts = list(path.parts[path.parts.index("proofs") + 1:])
    except ValueError:
        return None
    module_parts = module.split(".")
    if parts[:len(module_parts)] == module_parts:
        parts = parts[len(module_parts):]
    if not parts:
        return None
    parts[-1] = Path(parts[-1]).stem
    declaration = ".".join(parts)
    return declaration if declaration.startswith(f"{module}.") else f"{module}.{declaration}"


def _render_index_tree(nodes, current_dir, prefix):
    items = []
    for name, node in sorted(nodes.items()):
        path = (*prefix, name)
        page = node["page"]
        if page is None:
            output_path = _module_output_path(".".join(path))
        else:
            output_path = page.output_path
        href = quote_url_path(os.path.relpath(output_path, current_dir))
        label = (
            f'<a href="{html.escape(href, quote=True)}">'
            f'<span class="module-index-tree-mark" aria-hidden="true"></span>{html.escape(name)}</a>'
        )
        children = _render_index_tree(node["children"], current_dir, path)
        child_list = f'<ul>{children}</ul>' if children else ""
        items.append(f'<li>{label}{child_list}</li>')
    return "".join(items)
