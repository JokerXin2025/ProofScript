import os, html, json
from pathlib import Path
from urllib.parse import quote as quote_url_path
from string import Template
from textwrap import indent
from PS4HTML.i18n import normalize_language, tr


CURRENT_DIR = Path(__file__).absolute().parent
TEMPLATE_DIR = CURRENT_DIR.parent / "Templates"
TEMPLATE_REFERENCES = Template((TEMPLATE_DIR / "references.html").read_text())
TEMPLATE_REFERENCE = Template((TEMPLATE_DIR / "reference.html").read_text())
TEMPLATE_REFERENCE_ROW = Template((TEMPLATE_DIR / "reference_row.html").read_text())
TEMPLATE_REFERENCE_THEOREM = Template((TEMPLATE_DIR / "reference_theorem.html").read_text())
TEMPLATE_REFERENCE_THEOREM_UNRESOLVED = Template(
    (TEMPLATE_DIR / "reference_theorem_unresolved.html").read_text()
)

PROJECT_FIELDS = (
    ("title", "title"),
    ("authors", "authors"),
    ("description", "description"),
    ("keywords", "keywords"),
    ("year", "year"),
    ("base_url", "base_url"),
    ("license", "license"),
)

FIELD_LABELS = {
    "zh": {"title": "标题", "authors": "作者", "description": "简介", "keywords": "关键词", "year": "年份", "base_url": "项目网址", "license": "许可"},
    "en": {"title": "Title", "authors": "Authors", "description": "Description", "keywords": "Keywords", "year": "Year", "base_url": "Project URL", "license": "License"},
}


def render_references(references, labels, build_root, current_output, language="zh"):
    language = normalize_language(language)
    if not isinstance(references, list):
        return TEMPLATE_REFERENCES.substitute(items = "", title = tr("page.references", language))

    groups = []
    group_indexes = {}
    for position, reference in enumerate(references, 1):
        if not isinstance(reference, dict):
            continue
        info = reference.get("info", {})
        project_id = info.get("project") if isinstance(info, dict) else None
        project = reference.get("project", {})
        key = project_id
        index = group_indexes.get(key)
        if index is None:
            index = len(groups)
            group_indexes[key] = index
            groups.append({"project": project, "theorems": []})
        groups[index]["theorems"].append((position, reference))

    items = "\n".join(
        _render_project(index, group, labels, build_root, current_output, language)
        for index, group in enumerate(groups, 1)
    )
    return TEMPLATE_REFERENCES.substitute(items = indent(items, "    "), title = tr("page.references", language))


def _render_project(index, group, labels, build_root, current_output, language):
    project = group["project"] if isinstance(group["project"], dict) else {}
    title = project.get("title") or (f"Project {index}" if language == "en" else f"项目 {index}")
    authors = _list_value(project.get("authors"))
    subtitle = " · ".join(
        value for value in (authors, project.get("year", "")) if value
    )
    rows = _project_rows(project, language)
    theorems = "\n".join(
        _render_theorem(position, reference, labels, build_root, current_output, language)
        for position, reference in group["theorems"]
    )
    return TEMPLATE_REFERENCE.substitute(
        index = index,
        title = html.escape(str(title)),
        subtitle = html.escape(subtitle),
        rows = indent(rows, "      "),
        theorems = indent(theorems, "    "),
        info_title = tr("page.reference_info", language)
    )


def _project_rows(project, language="zh"):
    rows = []
    for key, label_key in PROJECT_FIELDS:
        value = project.get(key)
        if isinstance(value, list):
            value = _list_value(value)
        if value:
            rows.append(_row(FIELD_LABELS.get(language, FIELD_LABELS["zh"]).get(label_key, label_key), value, key == "base_url"))
    for key, value in project.get("extra", {}).items():
        if value is not None:
            rendered = json.dumps(value, ensure_ascii=False) if isinstance(value, (list, dict)) else str(value)
            rows.append(_row(key, rendered))
    return "\n".join(rows)


def _row(key, value, link = False):
    escaped = html.escape(str(value))
    if link:
        escaped = f'<a href="{html.escape(str(value), quote = True)}">{escaped}</a>'
    return TEMPLATE_REFERENCE_ROW.substitute(
        key = html.escape(str(key)),
        value = escaped
    )


def _render_theorem(position, reference, labels, build_root, current_output, language):
    info = reference.get("info", {})
    lean_name = str(reference.get("name", ""))
    display_name = info.get("name") or (f"Theorem {position}" if language == "en" else f"定理{position}")
    target = labels.get(("theorem", lean_name))
    location = lean_name
    if target is not None:
        source_name = target.source.name
        location = f"{source_name}:{target.line}" if target.line else source_name
        target_file = build_root / target.output_path
        current_dir = (build_root / current_output).parent
        href = f'{quote_url_path(os.path.relpath(target_file, current_dir))}#{quote_url_path(target.anchor)}'
        return TEMPLATE_REFERENCE_THEOREM.substitute(
            href = html.escape(href, quote = True),
            name = html.escape(str(display_name)),
            location = html.escape(location)
        )
    return TEMPLATE_REFERENCE_THEOREM_UNRESOLVED.substitute(
        name = html.escape(str(display_name)),
        location = html.escape(location)
    )


def _list_value(value):
    return ", ".join(str(item) for item in value) if isinstance(value, list) else ""
