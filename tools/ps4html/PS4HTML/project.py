from pathlib import Path


class PS4HTMLError(Exception):
    pass


def validate_project_registry(session, package: str, library: str, owners: set[str]) -> None:
    """Check Lake's project inventory and the selected library's exported owners."""
    selected = {"package": package, "library": library}
    if session.get("selectedProject") != selected:
        raise PS4HTMLError("PS4HTML session selected project does not match the Lake target")
    projects = session.get("projects")
    if (not isinstance(projects, list) or
            any(not isinstance(item, dict) or set(item) != {"package", "library"} or
                item["package"] != package or not isinstance(item["library"], str) or
                not item["library"] for item in projects)):
        raise PS4HTMLError("Invalid PS4HTML package project inventory")
    keys = [(item["package"], item["library"]) for item in projects]
    if len(set(keys)) != len(keys) or (package, library) not in keys:
        raise PS4HTMLError("Duplicate or missing PS4HTML library in project inventory")
    roots = session.get("projectRoots")
    if (not isinstance(roots, list) or
            any(not isinstance(root, str) or not root for root in roots) or
            len(set(roots)) != len(roots)):
        raise PS4HTMLError("Invalid PS4HTML library roots")
    library_modules = session.get("libraryModules")
    if (not isinstance(library_modules, list) or
            any(not isinstance(module, str) or not module for module in library_modules) or
            len(set(library_modules)) != len(library_modules) or not owners <= set(library_modules)):
        raise PS4HTMLError("Invalid PS4HTML library module inventory")
    assignments = session.get("moduleProjects")
    if (not isinstance(assignments, list) or
            any(not isinstance(item, dict) or set(item) != {"module", "package", "library"} or
                not isinstance(item["module"], str) or not item["module"] or
                item["package"] != package or item["library"] != library for item in assignments)):
        raise PS4HTMLError("Invalid PS4HTML module project assignments")
    names = [item["module"] for item in assignments]
    if len(set(names)) != len(names) or set(names) != owners:
        raise PS4HTMLError("PS4HTML project assignments do not match exported modules")
    closure = session.get("closureProjects")
    if (not isinstance(closure, list) or
            any(not isinstance(item, dict) or set(item) != {"module", "package", "library"} or
                not all(isinstance(item[key], str) and item[key] for key in item) for item in closure)):
        raise PS4HTMLError("Invalid PS4HTML import-closure project assignments")
    by_module = {item["module"]: (item["package"], item["library"]) for item in closure}
    if len(by_module) != len(closure) or any(by_module.get(owner) != (package, library) for owner in owners):
        raise PS4HTMLError("PS4HTML import closure disagrees with the selected library")
    if any(root in by_module and by_module[root] != (package, library) for root in roots):
        raise PS4HTMLError("PS4HTML library root belongs to another project")


def find_project_root(start: Path) -> Path:
    current = start.resolve()
    if current.is_file():
        current = current.parent
    for directory in (current, *current.parents):
        if (directory / "lakefile.toml").is_file() or (directory / "lakefile.lean").is_file():
            return directory
    raise PS4HTMLError(f"No Lean project found from {start}")
