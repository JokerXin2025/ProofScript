from pathlib import Path


class PS4HTMLError(Exception):
    pass


def find_project_root(start: Path) -> Path:
    current = start.resolve()
    if current.is_file():
        current = current.parent
    for directory in (current, *current.parents):
        if (directory / "lakefile.toml").is_file() or (directory / "lakefile.lean").is_file():
            return directory
    raise PS4HTMLError(f"No Lean project found from {start}")
