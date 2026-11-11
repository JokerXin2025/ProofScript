import fcntl
import shutil
from contextlib import contextmanager
from pathlib import Path
from PS4HTML.project import find_project_root


@contextmanager
def _lock(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)


def clean(print_info: bool, start: Path | None = None):
    root = find_project_root(start or Path.cwd())
    generated = root / ".PS4HTML"
    with _lock(root / ".ProofScript" / "publish.lock"), _lock(generated / "build.lock"):
        for child in generated.iterdir():
            if child.name != "build.lock":
                if child.is_dir():
                    shutil.rmtree(child)
                else:
                    child.unlink()
    shutil.rmtree(root / ".ProofScript", ignore_errors=True)
    (generated / "build.lock").unlink(missing_ok=True)
    generated.rmdir()

    if print_info:
        print("PS4HTML generated files have been cleaned up.")


if __name__ == "__main__":
    clean(True)
