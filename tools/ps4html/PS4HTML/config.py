"""Project-root PS4HTML configuration; independent of ProofScript exports."""

from __future__ import annotations

import math
import json
import tomllib
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote, urlsplit, urlunsplit

from PS4HTML.project import PS4HTMLError, find_project_root


def _fail(path: Path, field: str, message: str):
    raise PS4HTMLError(f"{path}: {field}: {message}")


def _table(path, name, value, allowed=None):
    if not isinstance(value, dict):
        _fail(path, name, "expected a table")
    if allowed is not None:
        for key in value:
            if key not in allowed:
                _fail(path, f"{name}.{key}" if name else key, "unknown field")
    return value


def _extra(path, name, value):
    if isinstance(value, dict):
        for key, item in value.items():
            _extra(path, f"{name}.{key}", item)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            _extra(path, f"{name}[{index}]", item)
    elif type(value) is float:
        if not math.isfinite(value):
            _fail(path, name, "expected a finite number")
    elif type(value) not in (str, int, bool):
        _fail(path, name, "expected a JSON-compatible value")


def _base_url(path, value):
    if not value:
        return ""
    try:
        url = urlsplit(value)
        _ = url.port  # Reject invalid port numbers even when the URL is not used yet.
    except ValueError as error:
        _fail(path, "site.base_url", str(error))
    if (url.scheme not in ("http", "https") or not url.hostname or
            url.username is not None or url.password is not None or url.query or url.fragment or
            "?" in value or "#" in value or any(char.isspace() for char in value) or
            "\\" in value or "%2f" in url.path.lower() or "%5c" in url.path.lower() or
            any(part in (".", "..") for part in url.path.split("/"))):
        _fail(path, "site.base_url", "expected an absolute HTTP(S) root URL without credentials, query or fragment")
    return urlunsplit((url.scheme, url.netloc, url.path.rstrip("/") + "/", "", ""))


@dataclass(frozen=True)
class PS4HTMLConfig:
    site: dict
    default_language: str
    present: bool

    def metadata(self, package: str) -> dict:
        return {**self.site, "title": self.site["title"] or package}

    def library_metadata(self, package: str, library: str) -> dict:
        metadata = self.metadata(package)
        metadata["url"] = (self.site["base_url"] + quote(library, safe="") + "/"
                           if self.site["base_url"] else "")
        return metadata

    def reference_metadata(self, package: str, project_id: str | None) -> dict:
        """Only this package's libraries share the site's presentation metadata."""
        if not isinstance(project_id, str):
            return {}
        try:
            identity = json.loads(project_id)
        except ValueError:
            return {}
        if (not isinstance(identity, dict) or identity.get("package") != package or
                not isinstance(identity.get("library"), str) or not identity["library"]):
            return {}
        library = identity["library"]
        metadata = self.library_metadata(package, library)
        metadata["base_url"] = metadata["url"]
        return metadata


def load_config(root: Path | None = None) -> PS4HTMLConfig:
    root = find_project_root(root or Path.cwd())
    path = root / "ps4html-config.toml"
    try:
        data = tomllib.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        if path.exists() or path.is_symlink():
            raise PS4HTMLError(f"{path}: cannot read configuration") from None
        data = {}
        present = False
    except (OSError, UnicodeError, tomllib.TOMLDecodeError) as error:
        raise PS4HTMLError(f"{path}: {error}") from error
    else:
        present = True
    _table(path, "", data, {"site", "render"})
    site = _table(path, "site", data.get("site", {}),
                  {"title", "authors", "keywords", "description", "year", "license", "base_url", "extra"})
    render = _table(path, "render", data.get("render", {}), {"default_language"})
    values = {}
    for name in ("title", "description", "year", "license", "base_url"):
        value = site.get(name, "")
        if type(value) is not str:
            _fail(path, f"site.{name}", "expected a string")
        values[name] = value
    for name in ("authors", "keywords"):
        value = site.get(name, [])
        if not isinstance(value, list) or any(type(item) is not str for item in value):
            _fail(path, f"site.{name}", "expected an array of strings")
        values[name] = value
    values["base_url"] = _base_url(path, values["base_url"])
    values["extra"] = _table(path, "site.extra", site.get("extra", {}))
    _extra(path, "site.extra", values["extra"])
    language = render.get("default_language", "en")
    if type(language) is not str or language not in ("en", "zh"):
        _fail(path, "render.default_language", 'expected "en" or "zh"')
    return PS4HTMLConfig(values, language, present)
