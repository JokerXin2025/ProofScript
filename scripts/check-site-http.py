"""Smoke-test a built site through PS4HTML's HTTP handler, including all local assets."""

import argparse
from functools import partial
from html.parser import HTMLParser
from http.server import ThreadingHTTPServer
from pathlib import Path
from threading import Thread
from urllib.parse import urljoin, urlsplit
from urllib.request import urlopen

from PS4HTML.serve import PS4HTMLRequestHandler


class Assets(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urls = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "script" and attrs.get("src"):
            self.urls.append(attrs["src"])
        if tag == "link" and attrs.get("href"):
            self.urls.append(attrs["href"])


class QuietHandler(PS4HTMLRequestHandler):
    def log_message(self, *_args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    args = parser.parse_args()
    build = args.project.resolve() / ".PS4HTML/build"
    assert (build / "index.html").is_file(), "Build the site first"
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(QuietHandler, directory=str(build)))
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = f"http://127.0.0.1:{server.server_port}/"
    checked = set()
    try:
        for page in build.rglob("*.html"):
            url = urljoin(base, page.relative_to(build).as_posix())
            with urlopen(url) as response:
                assert response.headers["Cross-Origin-Opener-Policy"] == "same-origin"
                assert response.headers["Cross-Origin-Embedder-Policy"] == "require-corp"
                assets = Assets()
                assets.feed(response.read().decode())
            for asset in assets.urls:
                target = urljoin(url, asset)
                if urlsplit(target).netloc == urlsplit(base).netloc and target not in checked:
                    with urlopen(target) as response:
                        assert response.status == 200
                        response.read()
                    checked.add(target)
        for wasm in build.rglob("*.wasm"):
            with urlopen(urljoin(base, wasm.relative_to(build).as_posix())) as response:
                assert response.headers.get_content_type() == "application/wasm"
                response.read()
        print(f"HTTP site smoke test passed; {len(checked)} local assets")
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


if __name__ == "__main__":
    main()
