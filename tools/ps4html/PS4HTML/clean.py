import shutil
import fcntl
from pathlib import Path
from PS4HTML.project import find_project_root


def clean(print_info: bool, start: Path | None = None):
    root = find_project_root(start or Path.cwd())
    generated = root / ".PS4HTML"
    generated.mkdir(exist_ok=True)
    with (generated / "build.lock").open("a+b") as stream:
        fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
        shutil.rmtree(root / ".ProofScript", ignore_errors=True)
        for child in generated.iterdir():
            if child.name != "build.lock":
                if child.is_dir():
                    shutil.rmtree(child)
                else:
                    child.unlink()
        fcntl.flock(stream.fileno(), fcntl.LOCK_UN)
    (generated / "build.lock").unlink(missing_ok=True)

    if print_info:
        print("PS4HTML generated files have been cleaned up.")


if __name__ == "__main__":
    clean(True)
