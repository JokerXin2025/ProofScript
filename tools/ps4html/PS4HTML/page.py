import html
import json
import os
from Lean2TeX.interactions import ExpressionInteractions
from Lean2TeX.names import select_name
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote as quote_url_path

from PS4HTML.engine import SORRY, ProofEngine, render_module_navigation, render_page
from PS4HTML.i18n import tr
from PS4HTML.project import PS4HTMLError
from PS4HTML.Rules.proof_text import ProofTextRenderer
from PS4HTML.Rules.title import TitleRenderer
from PS4HTML.Rules.media import render_figure, render_latex
from PS4HTML.Rules.references import render_references
from PS4HTML.schema import ResourceLoader, validate_document
from PS4HTML.Rules.computation import render_computation
from PS4HTML.info import name_text
from PS4HTML.theorem_graph import theorem_id




@dataclass(frozen = True)
class Page:
    path: Path
    module: str
    source: Path
    components: list
    exported_path: Path

    @property
    def output_path(self) -> Path:
        return self.exported_path.with_suffix(".html")


@dataclass(frozen = True)
class LabelTarget:
    output_path: Path
    anchor: str
    source: Path


def build_label_index(pages: list[Page]) -> dict[tuple[str, str], LabelTarget]:
    labels = {}
    for page in pages:
        for component in page.components:
            data = component.get("data", {}) if isinstance(component, dict) else {}
            if "title" in data:
                value = data.get("title", {}).get("value", {})
                label = value.get("label") if isinstance(value, dict) else None
                if isinstance(label, str):
                    _add_label(labels, "heading", label, page, f"heading-{label}")
            elif "theorem" in data or "lemma" in data:
                declaration_kind = "theorem" if "theorem" in data else "lemma"
                value = data.get(declaration_kind, {}).get("value", {})
                declaration = name_text(value["declaration"])
                _add_label(labels, "theorem", declaration, page, _theorem_anchor(declaration))
            elif "figure" in data or "latex" in data:
                tag = "figure" if "figure" in data else "latex"
                value = data.get(tag, {}).get("value", {})
                label = value.get("metadata", {}).get("label")
                if isinstance(label, str):
                    _add_label(labels, "figure", label, page, f"figure-{label}")
    return labels


def _add_label(labels, kind, label, page, anchor):
    key = (kind, label)
    if key in labels:
        raise PS4HTMLError(f"Duplicate {kind} label: {label}")
    labels[key] = LabelTarget(page.output_path, anchor, page.source)


class PageRenderer:
    def __init__(self, project_root: Path, build_root: Path, labels, pages = None, default_language="en", theorem_graph=None, export_root=None, project_info=None, bundle=None, reference_metadata=None, verso=None):
        self.project_root = project_root
        self.export_root = export_root or project_root / ".ProofScript"
        self.build_root = build_root
        self.labels = labels
        self.pages = list(pages or [])
        self.project_info = project_info or {}
        self.reference_metadata = reference_metadata
        self.default_language = default_language if default_language in ("zh", "en") else "en"
        self.diagnostics = []
        self.resources = ResourceLoader(project_root, export_root)
        if bundle is None or theorem_graph is None:
            raise PS4HTMLError("A completed ProofScript target is required for rendering")
        self.bundle = bundle
        if verso is None:
            raise PS4HTMLError("Verso source renderer is required")
        self.verso = verso
        self.theorem_graph = theorem_graph
        self.rendered_outputs = frozenset(page.output_path for page in self.pages)

    def render(self, page: Page) -> str:
        self._expression_interactions = ExpressionInteractions()
        self._expression_interactions.enable_render_roots = True
        current_output = page.output_path
        contents = self.render_components(page, current_output)
        contents.extend(self._descendant_index(page.module, current_output))
        index_href = os.path.relpath(self.build_root / "index.html", (self.build_root / current_output).parent)
        package_href = os.path.relpath(self.build_root.parent / "index.html", (self.build_root / current_output).parent)
        pages = self.pages or [page]
        theorem_navigation = self._theorem_navigation(page, current_output)
        navigation = render_module_navigation(pages, current_output, page.module, package_href,
                                               self.default_language, theorem_navigation, self.project_info, package_home=True)
        return render_page(page.module, "\n\n".join(contents), index_href, navigation,
                           self.default_language, self._expression_interactions,
                            project_id=self.bundle.project_id, project_url=self.project_info.get("url", ""),
                            asset_root=os.path.relpath(self.build_root.parent / "assets", (self.build_root / current_output).parent) + "/",
                            verso_data=self.verso.data(page.module))

    def _theorem_navigation(self, page, current_output):
        panels = []
        for language in ("zh", "en"):
            panels.append(self._theorem_navigation_panel(page, current_output, language))
        return "".join(panels)

    def _theorem_navigation_panel(self, page, current_output, language):
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
                    other_record = graph.nodes[other_key].record
                    if css_class == "outgoing" and other_record is not None and other_record.declaration_kind == "lemma":
                        continue
                    destination = graph.destinations.get(other_key)
                    declaration = html.escape(name_text(list(other_key[1])), quote=True)
                    label = html.escape(graph.title(other_key, language))
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
                f'<template class="theorem-dependency-template" data-theorem-id="{identity}"><div class="theorem-dependency-graph">{incoming}<div class="theorem-dependency-current" data-theorem-node="{identity}"><span class="theorem-dependency-mark" aria-hidden="true"></span><strong>{html.escape(graph.title(key, language))}</strong></div>{outgoing}</div></template>'
            )
        if not templates:
            return ""
        return (
            f'<section class="theorem-dependency-navigation" data-language-panel="{language}" hidden>'
            f'<h3>{"依赖" if language == "zh" else "Dependencies"}</h3>'
            '<div class="theorem-dependency-panel" data-theorem-navigation-content></div>'
            + "".join(templates) + '</section>'
        )

    def render_components(self, page: Page, current_output: Path) -> list[str]:
        return [self._component(component, page, current_output, index) for index, component in enumerate(page.components)]

    def render_directory(self, module: str) -> str:
        current_output = _module_output_path(module)
        contents = self._descendant_index(module, current_output)
        index_href = os.path.relpath(self.build_root / "index.html", (self.build_root / current_output).parent)
        package_href = os.path.relpath(self.build_root.parent / "index.html", (self.build_root / current_output).parent)
        navigation = render_module_navigation(
            self.pages, current_output, module, package_href, self.default_language,
            project_info=self.project_info, package_home=True
        )
        return render_page(module, "\n\n".join(contents), index_href, navigation, self.default_language,
                           project_id=self.bundle.project_id, project_url=self.project_info.get("url", ""),
                           asset_root=os.path.relpath(self.build_root.parent / "assets", (self.build_root / current_output).parent) + "/")

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

    def _component(self, component, page, current_output, index):
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
        if tag == "title":
            return TitleRenderer(self.labels, self.build_root, current_output).render(value)
        if tag in {"theorem", "lemma"}:
            return self._theorem(value, page, index)
        if tag == "latex":
            rendered, diagnostics = render_latex(value, self.project_root, self.resources)
            self.diagnostics.extend(diagnostics)
            return rendered
        if tag == "figure":
            rendered, diagnostics = render_figure(value, self.export_root)
            self.diagnostics.extend(diagnostics)
            return rendered
        if tag == "computation":
            return render_computation(value)
        if tag == "references":
            panels = []
            for language in ("zh", "en"):
                panel = render_references(value, self.labels, self.build_root, current_output, language,
                                          project_metadata=self.reference_metadata)
                hidden = "" if language == self.default_language else " hidden"
                panels.append(f'<div data-language-panel="{language}"{hidden}>{panel}</div>')
            return "\n".join(panels)
        return self._placeholder(tag, value)

    def _theorem(self, value, page, index):
        proof = value["proof"]
        state = SORRY if value["sorryAx"] else None
        record = self.bundle.theorem(proof)
        declaration = name_text(list(record.declaration))
        identity = theorem_id(record.key)
        proof_relative = self.bundle.relative(record.path)
        proof_path = self.bundle.file_path(proof_relative)
        proof_document = self.bundle.read(proof_relative)
        self.resources.read_text(proof, "application/vnd.proofscript.proof+json")
        expression_resolver = validate_document(proof_document, module_protocol=True)
        if proof_document["module"] != page.module:
            raise PS4HTMLError(f"Proof module does not match page: {proof_path}")
        try:
            lean2tex_config = self.bundle.configuration(record.owner)
        except (OSError, ValueError) as error:
            raise PS4HTMLError(f"Invalid Lean2TeX configuration for {page.module}: {error}") from error
        fields = lean2tex_config.declaration_info[declaration]
        names = fields["names"]
        code = proof_document["code"]
        anchor = _theorem_anchor(declaration)
        lines = code.count("\n") + (1 if code else 0)
        if "proof" not in proof_document:
            from PS4HTML.statement import render_statement
            panels = []
            for language in ("zh", "en"):
                name = select_name(names, language, declaration, theorem=True,
                                   lean_last_component=fields["name_last_component"])
                engine = ProofEngine([], language=language, expression_resolver=expression_resolver,
                                     lean2tex_config=lean2tex_config)
                engine.renderer.interactions = self._expression_interactions
                engine.renderer.theorem_id = identity
                statement = render_statement(proof_document["statement"], engine, omit_proof_divider=True)
                panels.append(_render_code_only_declaration(
                    name, anchor + ("-en" if language == "en" else ""),
                    self.verso.fragment(page.module, index, language), lines, identity, statement, language, self.default_language,
                    code))
                self.diagnostics.extend({"theorem": name, "proof": record.path, "language": language,
                                         **diagnostic} for diagnostic in engine.diagnostics)
            return "\n".join(panels)
        proof_data = proof_document["proof"]
        step_rules = self.bundle.proof_rules(proof_relative)
        rendered = []
        for language in ("zh", "en"):
            name = select_name(names, language, declaration, theorem=True,
                               lean_last_component=fields["name_last_component"])
            engine = ProofEngine(
                proof_data,
                language=language,
                project_root=self.project_root,
                expression_resolver=expression_resolver,
                resource_loader=self.resources,
                resource_stack=(proof_path.resolve(),),
                lean2tex_config=lean2tex_config,
                step_rules=step_rules,
            )
            engine.renderer.interactions = self._expression_interactions
            engine.renderer.theorem_id = identity
            rendered.append(engine.make(
                name,
                lines,
                self.verso.fragment(page.module, index, language),
                anchor if language == "zh" else f"{anchor}-en",
                state = state,
                language = language,
                default_language = self.default_language,
                theorem_id = identity,
                statement = proof_document["statement"],
                source = code,
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


def _render_code_only_declaration(name, anchor, code, lines, theorem_id, statement, language="en", default_language="en", source=""):
    hidden = "" if language == default_language else " hidden"
    copy_label = html.escape(tr("proof.copy_source", language), quote=True)
    source_title = html.escape(tr("proof.source_title", language), quote=True)
    back_title = html.escape(tr("proof.back_title", language), quote=True)
    return f'''<section class="theorem-proof theorem-code-only" id="{html.escape(anchor, quote=True)}" data-theorem-id="{html.escape(theorem_id, quote=True)}" data-language-panel="{language}"{hidden}>
  <h2><span>{html.escape(name)}</span>
    <button class="flip-btn" type="button" title="{source_title}" data-front-title="{source_title}" data-back-title="{back_title}"><i class="codicon codicon-file-code"></i></button>
  </h2>
  <div class="proof-flip">
    <div class="proof-flip-inner">
      <div class="proof-flip-front">{statement}</div>
      <div class="proof-flip-back proof-source-card">
        <div class="verso-container">
          <pre class="verso-source">{code}</pre>
          <button class="verso-copy" type="button" data-verso-source="{html.escape(source, quote=True)}" aria-label="{copy_label}" title="{copy_label}"><i class="codicon codicon-copy" aria-hidden="true"></i></button>
        </div>
      </div>
    </div>
  </div>
</section>'''


def _theorem_anchor(declaration) -> str:
    return f"theorem-{declaration}"


def directory_modules(pages: list[Page]) -> list[str]:
    modules = set()
    for page in pages:
        parts = page.module.split(".")
        modules.update(".".join(parts[:end]) for end in range(1, len(parts)))
    return sorted(modules)


def _module_output_path(module: str) -> Path:
    parts = module.split(".")
    return Path(*parts[:-1]) / f"{parts[-1]}.html"


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
