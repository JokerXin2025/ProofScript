import base64
import html
import json
import mimetypes
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from string import Template

from PS4HTML.project import PS4HTMLError
from PS4HTML.schema import ResourceLoader
from PS4HTML.highlight import highlight_code


ET.register_namespace("", "http://www.w3.org/2000/svg")
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")

TEMPLATE_DIR = Path(__file__).absolute().parent.parent / "Templates"
TEMPLATE_MEDIA = Template((TEMPLATE_DIR / "media.html").read_text())
TEMPLATE_LATEX = Template((TEMPLATE_DIR / "latex.html").read_text())
TEMPLATE_INLINE_LATEX = Template((TEMPLATE_DIR / "inline_latex.html").read_text())
TEMPLATE_MEDIA_ERROR = Template((TEMPLATE_DIR / "media_error.html").read_text())


def render_latex(value, project_root: Path | None = None,
                 resource_loader: ResourceLoader | None = None, *,
                 inline: bool = False) -> tuple[str, list[dict]]:
    if not isinstance(value, dict):
        return _error("LaTeX", "Invalid LaTeX component")
    metadata, svg, source = value.get("metadata"), value.get("svg"), value.get("source")
    if not isinstance(metadata, dict) or not isinstance(source, str):
        return _error("LaTeX", "LaTeX component is missing required fields")
    if isinstance(svg, dict):
        if project_root is None:
            return _error(_title(metadata, "LaTeX"), "LaTeX resource requires a project root")
        try:
            loader = resource_loader or ResourceLoader(project_root)
            svg = loader.read_text(svg, "image/svg+xml")
        except PS4HTMLError as error:
            return _error(_title(metadata, "LaTeX"), str(error))
    if not isinstance(svg, str):
        return _error("LaTeX", "LaTeX component is missing required fields")
    try:
        svg = _sanitize_svg(svg)
    except ValueError as error:
        return _error(_title(metadata, "LaTeX"), str(error))
    label = metadata.get("label")
    anchor = f"figure-{label}" if isinstance(label, str) else ""
    parameters = dict(
        anchor = html.escape(anchor, quote = True),
        title = html.escape(_title(metadata, "LaTeX")),
        extra = html.escape(json.dumps(metadata.get("extra", []), ensure_ascii = False), quote = True),
    )
    if inline:
        return TEMPLATE_INLINE_LATEX.substitute(**parameters, svg_code=svg), []
    highlighted_source = highlight_code(source, "latex", theme="light")[0]
    encoded = base64.b64encode(svg.encode("utf-8")).decode("ascii")
    return TEMPLATE_LATEX.substitute(
        **parameters,
        uri=html.escape(f"data:image/svg+xml;base64,{encoded}", quote=True),
        alt="LaTeX SVG",
        source=highlighted_source,
    ), []


def render_figure(value, project_root: Path) -> tuple[str, list[dict]]:
    if not isinstance(value, dict):
        return _error("Figure", "Invalid figure component")
    metadata, resource, extension = value.get("metadata"), value.get("path"), value.get("extension")
    if not isinstance(metadata, dict) or not isinstance(resource, str) or not isinstance(extension, str):
        return _error("Figure", "Figure component is missing required fields")
    relative = Path(resource)
    if relative.is_absolute():
        return _error(_title(metadata, "Figure"), "Figure resource path must be relative")
    path = (project_root / relative).resolve()
    try:
        path.relative_to(project_root.resolve())
    except ValueError:
        return _error(_title(metadata, "Figure"), "Figure resource escapes the Lean project")
    try:
        content = path.read_bytes()
    except OSError as error:
        return _error(_title(metadata, "Figure"), f"Unable to read figure resource: {error}")
    mime = mimetypes.guess_type(path.name)[0]
    if mime is None:
        mime = "image/svg+xml" if extension.lower() == "svg" else f"image/{extension.lower()}"
    encoded = base64.b64encode(content).decode("ascii")
    return _render("figure", metadata, f"data:{mime};base64,{encoded}", path.name, resource), []


def _render(kind, metadata, uri, alt, source):
    label = metadata.get("label")
    anchor = f"figure-{label}" if isinstance(label, str) else ""
    return TEMPLATE_MEDIA.substitute(
        kind = kind,
        anchor = html.escape(anchor, quote = True),
        title = html.escape(_title(metadata, kind.title())),
        uri = html.escape(uri, quote = True),
        alt = html.escape(alt, quote = True),
        source = html.escape(source, quote = True),
        extra = html.escape(json.dumps(metadata.get("extra", []), ensure_ascii = False), quote = True),
    )


def _error(title, message):
    return TEMPLATE_MEDIA_ERROR.substitute(
        title = html.escape(str(title)), message = html.escape(message)
    ), [{"kind": "media-error", "message": message}]


def _title(metadata, fallback):
    title = metadata.get("title") if isinstance(metadata, dict) else None
    return title if isinstance(title, str) and title else fallback


def _sanitize_svg(source: str) -> str:
    try:
        root = ET.fromstring(source)
    except ET.ParseError as error:
        raise ValueError(f"Invalid SVG resource: {error}") from error
    if root.tag.split("}")[-1].lower() != "svg":
        raise ValueError("LaTeX resource root must be an SVG element")

    unsafe_tags = {"script", "foreignobject", "iframe", "object", "embed"}
    external_url = re.compile(r"(?:https?:|//|data:|javascript:)", re.IGNORECASE)
    for parent in root.iter():
        for child in list(parent):
            if child.tag.split("}")[-1].lower() in unsafe_tags:
                parent.remove(child)
        for attribute, value in list(parent.attrib.items()):
            name = attribute.split("}")[-1].lower()
            if name.startswith("on"):
                del parent.attrib[attribute]
            elif name in {"href", "src"} and external_url.match(value.strip()):
                del parent.attrib[attribute]
            elif name == "style" and re.search(r"url\s*\(\s*['\"]?(?:https?:|//|data:|javascript:)", value, re.IGNORECASE):
                del parent.attrib[attribute]
    return ET.tostring(root, encoding="unicode")
