import argparse
from pathlib import Path

from PS4HTML.clean import clean
from PS4HTML.make import make, build_library
from PS4HTML.project import PS4HTMLError
from PS4HTML.serve import serve


def main():
    parser = argparse.ArgumentParser(prog="ps4html", description="ProofScript HTML site generator")
    commands = parser.add_subparsers(dest="command", required=True)
    cache = commands.add_parser("make", help="Render existing ProofScript exports only")
    cache.add_argument("-c", "--cache", action="store_true", required=True)
    cache.set_defaults(func=lambda args: make())
    library = commands.add_parser("_build-library", help="Internal Lake facet entry point")
    library.add_argument("package")
    library.add_argument("library")
    library.add_argument("--source-root", type=Path)
    library.add_argument("modules_and_sources", nargs="+")
    library.set_defaults(func=lambda args: build_library(args.package, args.library, args.modules_and_sources,
                                                       source_root=args.source_root))
    commands.add_parser("clean").set_defaults(func=lambda args: clean(True))
    preview = commands.add_parser("serve", help="Serve .PS4HTML/build with Wasm headers")
    preview.add_argument("target", nargs="?", default=".")
    preview.add_argument("--host", default="127.0.0.1")
    preview.add_argument("--port", type=int, default=8000)
    preview.add_argument("--lan", action="store_true")
    preview.add_argument("--cert", type=Path)
    preview.add_argument("--key", type=Path)
    preview.set_defaults(func=lambda args: serve(Path(args.target), "0.0.0.0" if args.lan else args.host,
                                                  args.port, args.cert, args.key))
    args = parser.parse_args()
    try:
        args.func(args)
    except (PS4HTMLError, OSError) as error:
        parser.exit(1, f"ps4html: error: {error}\n")
