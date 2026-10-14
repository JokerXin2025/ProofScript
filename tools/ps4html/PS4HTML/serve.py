from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
from pathlib import Path
import socket
import ssl

from PS4HTML.project import PS4HTMLError, find_project_root


LAN_NETWORKS = tuple(ipaddress.ip_network(value) for value in (
    "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
))


class PS4HTMLRequestHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".mjs": "text/javascript",
        ".wasm": "application/wasm",
    }

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self' https://cdn.jsdelivr.net; "
            "script-src 'self' https://cdn.jsdelivr.net 'wasm-unsafe-eval'; "
            "style-src 'self' https://cdn.jsdelivr.net 'unsafe-inline'; "
            "worker-src 'self' blob:; connect-src 'self'; img-src 'self' data:",
        )
        super().end_headers()


def local_ipv4_addresses():
    addresses = set()
    try:
        records = socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET)
    except OSError:
        records = []
    for record in records:
        address = record[4][0]
        parsed = ipaddress.ip_address(address)
        if any(parsed in network for network in LAN_NETWORKS):
            addresses.add(address)
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("8.8.8.8", 80))
            address = probe.getsockname()[0]
            if any(ipaddress.ip_address(address) in network for network in LAN_NETWORKS):
                addresses.add(address)
    except OSError:
        pass
    return sorted(addresses)


def serve(start: Path | None = None, host="127.0.0.1", port=8000,
          certfile: Path | None = None, keyfile: Path | None = None):
    root = find_project_root(start or Path.cwd())
    build_root = root / ".PS4HTML" / "build"
    if not (build_root / "index.html").is_file():
        raise PS4HTMLError(f"PS4HTML build output not found: {build_root}; run lake build MyLibrary:ps4html first")
    handler = partial(PS4HTMLRequestHandler, directory=str(build_root))
    try:
        server = ThreadingHTTPServer((host, port), handler)
    except OSError as error:
        raise PS4HTMLError(f"Unable to start server at http://{host}:{port}: {error}") from error
    if (certfile is None) != (keyfile is None):
        server.server_close()
        raise PS4HTMLError("Both --cert and --key are required for HTTPS")
    scheme = "http"
    if certfile is not None and keyfile is not None:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        try:
            context.load_cert_chain(certfile, keyfile)
        except (OSError, ssl.SSLError) as error:
            server.server_close()
            raise PS4HTMLError(f"Unable to load HTTPS certificate: {error}") from error
        server.socket = context.wrap_socket(server.socket, server_side=True)
        scheme = "https"

    print(f"Serving {build_root}", flush=True)
    if host in {"0.0.0.0", "::"}:
        print(f"  Local:   {scheme}://127.0.0.1:{port}/", flush=True)
        for address in local_ipv4_addresses():
            print(f"  Network: {scheme}://{address}:{port}/", flush=True)
        if scheme == "http":
            print("  Note: pthread computations require trusted HTTPS on non-localhost devices.", flush=True)
    else:
        print(f"  URL: {scheme}://{host}:{port}/", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
