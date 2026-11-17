import argparse
from pathlib import Path

from PS4HTML.clean import clean
from PS4HTML.config import load_config
from PS4HTML.project import PS4HTMLError
from PS4HTML.serve import serve


def render_target(manifest: Path):
    from PS4HTML.module_protocol import render_target as render
    return render(manifest)


def render_cached():
    from PS4HTML.module_protocol import render_cached_targets
    return render_cached_targets()


def check_config():
    config = load_config()
    print("PS4HTML configuration valid" if config.present
          else "PS4HTML configuration absent; using defaults")


def main():
    parser = argparse.ArgumentParser(prog="ps4html", description="ProofScript HTML site generator")
    commands = parser.add_subparsers(dest="command", required=True)
    cache = commands.add_parser("make", help="Render completed exports using the compiled read-only Verso renderer")
    cache.add_argument("-c", "--cache", action="store_true", required=True)
    cache.set_defaults(func=lambda args: render_cached())
    rendered = commands.add_parser("_render-target", help="Render a completed ProofScript target")
    rendered.add_argument("manifest", type=Path)
    rendered.set_defaults(func=lambda args: render_target(args.manifest))
    config = commands.add_parser("config", help="Inspect PS4HTML configuration")
    config_commands = config.add_subparsers(dest="config_command", required=True)
    config_commands.add_parser("check", help="Validate ps4html-config.toml").set_defaults(
        func=lambda args: check_config())
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
    except (PS4HTMLError, OSError, KeyError, TypeError, ValueError) as error:
        parser.exit(1, f"ps4html: error: {error}\n")
