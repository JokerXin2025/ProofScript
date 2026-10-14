from string import Template
from pathlib import Path
from textwrap import indent
import os
import html
from contextvars import ContextVar
from Lean2TeX import Expr2TeX
from Lean2TeX.configuration import EffectiveConfiguration
from PS4HTML.i18n import normalize_language, tr

_CURRENT_LANGUAGE = ContextVar("ps4html_language", default="zh")

PASS = 0
SORRY = 1
ERROR = 2

CURRENT_DIR = Path(__file__).absolute().parent
TEMPLATE_STEP = Template((CURRENT_DIR / "Templates/step.html").read_text())
TEMPLATE_CAL_STEP = Template((CURRENT_DIR / "Templates/cal_step.html").read_text())
TEMPLATE_DETAILS = Template((CURRENT_DIR / "Templates/details.html").read_text())
TEMPLATE_STRATEGY = Template((CURRENT_DIR / "Templates/strategy.html").read_text())
TEMPLATE_PROOF = Template((CURRENT_DIR / "Templates/proof.html").read_text())
TEMPLATE_PAGE = Template((CURRENT_DIR / "Templates/page.html").read_text())
TEMPLATE_ANNOTATION = Template((CURRENT_DIR / "Templates/annotation.html").read_text())


def render_step(tag, content, sort = "", style = ""):
    return TEMPLATE_STEP.substitute(
        tag = tag,
        content = content,
        sort = sort,
        style = style,
    )

def render_cal_step(tag, lhs, rel, rhs):
    return TEMPLATE_CAL_STEP.substitute(
        tag = tag,
        lhs = lhs,
        rel = rel,
        rhs = rhs,
    )

def render_details(open, tag, title, content):
    return TEMPLATE_DETAILS.substitute(
        open = "open" if open else "close",
        tag = tag,
        title = title,
        content = indent(content, "    ")
    )

def render_strategy(sort, tag, content, style = ""):
    return TEMPLATE_STRATEGY.substitute(
        sort = sort,
        tag = tag,
        content = indent(content, "    "),
        style = style,
    )

def render_annotation(sort, icon, content):
    return TEMPLATE_ANNOTATION.substitute(
        sort = sort,
        icon = icon,
        content = content
    )

def render_proof(proof_state, title, content, file_name, lines_count, code, anchor = "", language="zh", default_language="zh"):
    return TEMPLATE_PROOF.substitute(
        proof_state = proof_state,
        title = html.escape(title),
        content = indent(content, "        "),
        file_name = html.escape(str(file_name)),
        lines_count = lines_count,
        code = code,
        anchor = html.escape(anchor, quote = True),
        language = language,
        hidden = "" if language == default_language else "hidden",
        indent_title = tr("proof.indent_title", language),
        indent_label = tr("proof.indent_label", language),
        source_title = tr("proof.source_title", language),
        lines_label = tr("proof.lines", language),
    )

def render_page(title, contents, index_href, navigation = "", default_language="zh"):
    language = normalize_language(default_language)
    index_path = Path(index_href)
    project_base_url = (index_path.parent.as_posix().rstrip("/") + "/") if index_path.parent.as_posix() != "." else "./"
    return TEMPLATE_PAGE.substitute(
        asset_root = html.escape(project_base_url + "assets/", quote=True),
        title = html.escape(title),
        index_href = html.escape(index_href, quote = True),
        navigation = indent(navigation, "        "),
        contents = indent(contents, "    "),
        default_language = default_language,
        html_language = "zh-CN" if language == "zh" else "en",
        project_base_url = html.escape(project_base_url, quote=True),
        mobile_title = tr("page.mobile_title", language),
        mobile_desc = tr("page.mobile_desc", language),
    )


def render_index(pages, default_language="zh", module_contents="", theorem_navigation="", project_info=None):
    roots = sorted({page.module.split(".")[0] for page in pages})
    root_module = roots[0] if len(roots) == 1 else None
    items = _render_project_index_tree(pages, root_module)
    project_info = project_info or {}
    title = project_info.get("title") or "Lean Modules"
    authors = " · ".join(project_info.get("authors", []))
    description = project_info.get("description", "")
    metadata = " · ".join(value for value in (authors, project_info.get("year", "")) if value)
    project = f'''<header class="project-header">
  <h1>{html.escape(title)}</h1>
  {f'<p class="project-metadata">{html.escape(metadata)}</p>' if metadata else ''}
  {f'<p class="project-abstract">{html.escape(description)}</p>' if description else ''}
</header>'''
    contents = f'{project}{module_contents}<ul class="module-index-tree">{items}</ul>'
    navigation = render_module_navigation(
        pages, Path("index.html"), root_module, "index.html", default_language, theorem_navigation, project_info
    )
    return render_page(title, contents, "index.html", navigation, default_language)


def _render_project_index_tree(pages, root_module):
    tree = {}
    root_parts = root_module.split(".") if root_module else []
    for page in pages:
        parts = page.module.split(".")
        if page.module == root_module:
            continue
        relative = parts[len(root_parts):] if root_module and parts[:len(root_parts)] == root_parts else parts
        nodes = tree
        for part in relative:
            node = nodes.setdefault(part, {"page": None, "children": {}})
            nodes = node["children"]
        node["page"] = page

    return _render_project_index_nodes(tree, Path("."), root_parts)


def _render_project_index_nodes(nodes, current_dir, prefix):
    items = []
    for name, node in sorted(nodes.items()):
        path = (*prefix, name)
        page = node["page"]
        output_path = page.output_path if page is not None else _module_output_path(path)
        href = os.path.relpath(output_path, current_dir)
        label = (
            f'<a href="{html.escape(href, quote=True)}">'
            f'<span class="module-index-tree-mark" aria-hidden="true"></span>{html.escape(name)}</a>'
        )
        children = _render_project_index_nodes(node["children"], current_dir, path)
        child_list = f'<ul>{children}</ul>' if children else ""
        items.append(f'<li>{label}{child_list}</li>')
    return "".join(items)


def render_module_navigation(pages, current_output: Path, current_module: str | None, index_href: str, language="zh", theorem_navigation="", project_info=None):
    tree = {}
    for page in pages:
        children = tree
        for part in page.module.split("."):
            node = children.setdefault(part, {"page": None, "children": {}})
            children = node["children"]
        node["page"] = page

    current_parts = tuple(current_module.split(".")) if current_module else ()
    current_dir = current_output.parent
    if not current_parts:
        tree_html = _render_module_level(tree, current_dir, None, ())
    else:
        parent_path = current_parts[:-1]
        parent_children = tree
        parent_node = None
        for part in parent_path:
            parent_node = parent_children[part]
            parent_children = parent_node["children"]

        if not parent_path:
            tree_html = _render_context_siblings(tree, current_dir, current_parts, ())
        else:
            parent_name = parent_path[-1]
            parent_href = os.path.relpath(_module_output_path(parent_path), current_dir)
            parent_label = (
                f'<a class="module-tree-parent" href="{html.escape(parent_href, quote = True)}">'
                f'<span class="module-tree-node-mark" aria-hidden="true"></span>{html.escape(parent_name)}</a>'
            )
            siblings = _render_context_siblings(parent_children, current_dir, current_parts, parent_path)
            tree_html = f'<li class="module-tree-root">{parent_label}<ul>{siblings}</ul></li>'

    project_info = project_info or {}
    project_title = str(project_info.get("title") or "PS4HTML")
    path_prefix = "/".join(current_parts[:-2])
    if path_prefix:
        path_prefix += "/"
    path_html = f'''<div class="module-path-row">
      <div class="module-path-prefix" aria-hidden="true">{html.escape(path_prefix)}</div>
      <a class="module-home-button" href="{html.escape(index_href, quote=True)}" aria-label="{html.escape(tr("page.project_home", language), quote=True)}" title="{html.escape(tr("page.project_home", language), quote=True)}">
        <i class="codicon codicon-home" aria-hidden="true"></i>
      </a>
    </div>'''
    return f'''<aside class="module-sidebar" aria-label="{html.escape(tr("page.module_directory", language), quote=True)}">
  <div class="module-sidebar-inner">
    <div class="module-sidebar-heading">
      <span>{html.escape(project_title)}</span>
    </div>
    <div class="language-switcher">
      <button class="language-button" type="button" aria-haspopup="true" aria-expanded="false" title="{html.escape(tr("language.switch", language), quote=True)}">
        <i class="codicon codicon-globe" aria-hidden="true"></i>
      </button>
      <div class="language-menu" role="menu">
        <button type="button" role="menuitemradio" data-language="zh"><span class="language-node-mark" aria-hidden="true"></span>{html.escape(tr("language.zh", language))}</button>
        <button type="button" role="menuitemradio" data-language="en"><span class="language-node-mark" aria-hidden="true"></span>{html.escape(tr("language.en", language))}</button>
      </div>
    </div>
    {path_html}
    <nav class="module-directory-scroll" aria-label="{html.escape(tr("page.nearby_modules", language), quote=True)}">
      <ul class="module-context-tree">{tree_html}</ul>
    </nav>
    {theorem_navigation}
  </div>
</aside>'''


def _render_context_siblings(nodes, current_dir: Path, current_parts, parent_path):
    items = []
    for name, node in sorted(nodes.items()):
        path = parent_path + (name,)
        page = node["page"]
        children = node["children"]
        is_current = tuple(current_parts) == path
        label = _module_tree_label(name, page, current_dir, is_current, path)
        descendants = _render_module_level(children, current_dir, None, path) if is_current else ""
        child_list = f'<ul>{descendants}</ul>' if descendants else ""
        current_class = " class=\"is-current-branch\"" if is_current else ""
        items.append(f'<li{current_class}>{label}{child_list}</li>')
    return "".join(items)


def _render_module_level(nodes, current_dir: Path, current_module, prefix):
    items = []
    for name, node in sorted(nodes.items()):
        path = prefix + (name,)
        is_current = current_module == ".".join(path)
        label = _module_tree_label(name, node["page"], current_dir, is_current, path)
        items.append(f'<li>{label}</li>')
    return "".join(items)


def _module_tree_label(name, page, current_dir: Path, is_current: bool, path):
    classes = "module-tree-node is-current" if is_current else "module-tree-node"
    current_attr = ' aria-current="page"' if is_current else ""
    mark = '<span class="module-tree-node-mark" aria-hidden="true"></span>'
    href = os.path.relpath(page.output_path if page is not None else _module_output_path(path), current_dir)
    return f'<a class="{classes}" href="{html.escape(href, quote = True)}"{current_attr}>{mark}{html.escape(name)}</a>'


def _module_output_path(parts) -> Path:
    if len(parts) == 1:
        return Path("index.html")
    return Path(*parts[:-1]) / f"{parts[-1]}.html"


class ProofEngine:

    def __init__(self, data, language="zh", project_root: Path | None = None,
                 expression_resolver=None, resource_loader=None, resource_stack=(), rules=None,
                 lean2tex_config: EffectiveConfiguration | None = None, proof_version="0.1.0"):
        self.data = data
        self.proof_version = proof_version
        self.language = normalize_language(language)
        self.project_root = project_root
        self.expression_resolver = expression_resolver
        self.resource_loader = resource_loader
        self.resource_stack = tuple(resource_stack)
        self.rules = rules or {}
        self.materialized = rules is not None
        # The page supplies a proof-module snapshot; direct callers may pass an
        # empty configuration when no Lean export tree is involved.
        self.renderer = Expr2TeX.from_config(lean2tex_config) if lean2tex_config is not None else Expr2TeX()
        self.diagnostics = []

    def tex(self, node):
        """把单个 JSON 表达式 AST 渲染为 TeX 字符串；非 AST 值原样转字符串。"""
        if isinstance(node, dict):
            if "kind" in node:
                result = self.renderer.render(node, language=self.language)
                self.diagnostics.extend(self.renderer.diagnostics_dict())
                return result
            return ""
        if node is None:
            return ""
        return str(node)

    def render_relation(self, relation):
        """Render a calc relation without exposing Lean2TeX internals to rules."""
        return self.renderer.render_relation(relation)

    def tex_param(self, value):
        """渲染一个录制参数值或 `ident+` 的数组。"""
        if isinstance(value, dict):
            if "kind" in value:
                return self.tex(value)
            return ""
        if isinstance(value, list):
            return "，".join(self.tex_param(v) for v in value)
        if value is None:
            return ""
        return str(value)

    def text(self, key, **values):
        return tr(key, self.language, **values)

    def render(self, steps, path=()):
        self.validate(steps)
        token = _CURRENT_LANGUAGE.set(self.language)
        html_blocks = []
        try:
            for i in range(1, len(steps) // 2 + 1):
                is_last_step = (i == len(steps) // 2)
                previous = self.resolve(steps[2 * i - 2])
                step = self.resolve(steps[2 * i - 1])
                subsequent = self.resolve(steps[2 * i]) if not is_last_step else {}

                rule_id = step.get("_ruleId")
                rule = self.rules.get(rule_id)
                if rule is not None:
                    from PS4HTML.render_rules import render_rule
                    rendered = render_rule(rule, steps[2 * i - 1], steps[2 * i - 2],
                                           steps[2 * i] if not is_last_step else {},
                                           self, path, 2 * i - 1)
                    if rendered:
                        html_blocks.append(rendered)
                    continue

                raise ValueError(f"No rendering rule for recorded ID {rule_id!r}")
        finally:
            _CURRENT_LANGUAGE.reset(token)

        return "\n".join(html_blocks)

    def resolve(self, value):
        if self.expression_resolver is None:
            return value
        return self.expression_resolver.resolve(value)

    @staticmethod
    def validate(steps):
        if not isinstance(steps, list) or len(steps) < 2:
            raise ValueError("proof must contain at least one goal and one step")
        for index, record in enumerate(steps):
            if not isinstance(record, dict):
                raise ValueError(f"proof record {index} must be an object")
            if index % 2 == 0:
                if "_goal_" not in record:
                    raise ValueError(f"proof record {index} must be a goal")
            else:
                if not isinstance(record.get("_ruleId"), str) or not record["_ruleId"]:
                    raise ValueError(f"proof record {index} must contain a rule ID")

    def make(self, title, file_name, lines_count, code, anchor = "", state = None, language=None, default_language="zh"):
        previous_language = self.language
        if language is not None:
            self.language = normalize_language(language)
        try:
            content = self.render(self.data)
        finally:
            self.language = previous_language

        state = PASS if state is None else state
        if state == PASS:
            proof_state = '<sup class="proof-mark pass"><i class="codicon codicon-check-all"></i></sup>'
        elif state == SORRY:
            proof_state = '<sup class="proof-mark sorry"><i class="codicon codicon-warning"></i></sup>'
        elif state == ERROR:
            proof_state = '<sup class="proof-mark error"><i class="codicon codicon-error"></i></sup>'

        return render_proof(
            proof_state = proof_state,
            title = title,
            content = content,
            file_name = file_name,
            lines_count = lines_count,
            code = code,
            anchor = anchor,
            language = normalize_language(language or previous_language),
            default_language = normalize_language(default_language),
        )
