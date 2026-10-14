"""Validate real exporter output against the public schemas (requires jsonschema)."""

import argparse
import json
from pathlib import Path

from jsonschema import Draft202012Validator


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    args = parser.parse_args()
    schemas = Path(__file__).resolve().parents[1] / "docs/schema"
    project = args.project.resolve()
    snapshots = sorted((project / ".PS4HTML" / "inputs").glob("*/*/.ProofScript"))
    outputs = snapshots or [project / ".ProofScript"]
    groups = (
        ("pages/**/*.json", "page"),
        ("proofs/**/*.json", "proof"),
        ("rendering/effective/**/*.json", "render-effective"),
        ("lean2tex/events/**/*.json", "lean2tex-events"),
        ("computations/pending/**/*.json", "computation-pending"),
        ("computations/bundles/**/bundle.json", "computation-bundle"),
        ("resources/computation/**/bundle.json", "computation-published-bundle"),
        ("computations/index.json", "computation-index"),
    )
    total = 0
    errors = []
    for pattern, name in groups:
        schema = json.loads((schemas / f"{name}.schema.json").read_text())
        Draft202012Validator.check_schema(schema)
        validator = Draft202012Validator(schema)
        for output in outputs:
            for path in output.glob(pattern):
                total += 1
                document = json.loads(path.read_text())
                for error in validator.iter_errors(document):
                    errors.append(f"{path.relative_to(project)}:{list(error.absolute_path)}: {error.message}")
    if not total:
        raise SystemExit(f"No exported documents found in {project}")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Validated {total} exported documents against the current schemas")


if __name__ == "__main__":
    main()
