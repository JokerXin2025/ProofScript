#!/usr/bin/env python3
"""Check the language server's native theorem-completion markers.

Run after `lake build ProofScript`: python3 scripts/test-theorem-ide.py.
"""

import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time


ROOT = Path(__file__).resolve().parents[1]
SOURCE = """import ProofScript.Page.Component.Declaration
import ProofScript.Builtin.Scripts.Trivial
set_option pageBuild MODE
namespace IdeProof
theorem control : True := by trivial
#page theorem goodNative : True := by trivial
#page lemma goodScript : True := script trivial
#page theorem openSorry : True := by sorry
#page lemma openError : False := by exact True.intro
#page end
#page theorem afterNative : True := by trivial
#page lemma afterScript : True := script trivial
#page theorem closedSorry : True := by sorry
#page lemma closedError : False := by exact True.intro
end IdeProof
"""


def read_messages(stream, messages):
    try:
        while True:
            headers = {}
            while line := stream.readline():
                if line == b"\r\n":
                    break
                name, value = line.decode().split(":", 1)
                headers[name.lower()] = value.strip()
            if not headers:
                return
            messages.put(json.loads(stream.read(int(headers["content-length"]))))
    except Exception as error:
        messages.put(error)
    finally:
        messages.put(None)


def main():
    with tempfile.TemporaryDirectory(prefix="proofscript-theorem-ide-") as directory:
        work = Path(directory).resolve()
        with (work / "server.log").open("wb") as log:
            process = subprocess.Popen(
                ["lake", "env", "lean", "--server"], cwd=ROOT,
                env=dict(os.environ, PROOF_SCRIPT_OUTPUT_ROOT=str(work / "output")),
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log,
            )
            messages = queue.Queue()
            threading.Thread(target=read_messages, args=(process.stdout, messages), daemon=True).start()

            def write(message):
                body = json.dumps(message).encode()
                process.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
                process.stdin.flush()

            def send(method, params, request_id=None):
                message = {"jsonrpc": "2.0", "method": method, "params": params}
                if request_id is not None:
                    message["id"] = request_id
                write(message)

            def response(request_id, uri=None):
                diagnostics = []
                deadline = time.monotonic() + 120
                while True:
                    try:
                        message = messages.get(timeout=max(0, deadline - time.monotonic()))
                    except queue.Empty:
                        raise AssertionError("Lean language server timed out") from None
                    if message is None:
                        raise AssertionError("Lean language server exited:\n" + (work / "server.log").read_text())
                    if isinstance(message, Exception):
                        raise message
                    if "method" in message and "id" in message:
                        write({"jsonrpc": "2.0", "id": message["id"], "result": None})
                    if message.get("method") == "textDocument/publishDiagnostics":
                        params = message["params"]
                        if params["uri"] == uri:
                            if not params.get("isIncremental", False):
                                diagnostics = []
                            diagnostics.extend(params["diagnostics"])
                    if "method" not in message and message.get("id") == request_id:
                        assert "error" not in message, message
                        return diagnostics

            try:
                send("initialize", {
                    "processId": os.getpid(), "rootUri": ROOT.as_uri(),
                    "capabilities": {"lean": {"silentDiagnosticSupport": True}},
                }, 1)
                response(1)
                send("initialized", {})
                for request_id, mode in enumerate((False, True), start=2):
                    source = SOURCE.replace("MODE", str(mode).lower())
                    path = work / f"IdeProof{request_id}.lean"
                    path.write_text(source)
                    uri = path.as_uri()
                    send("textDocument/didOpen", {"textDocument": {
                        "uri": uri, "languageId": "lean4", "version": 1, "text": source,
                    }})
                    # This Lean request waits for all snapshots and diagnostic reporting.
                    send("textDocument/waitForDiagnostics", {"uri": uri, "version": 1}, request_id)
                    diagnostics = response(request_id, uri)
                    lines = source.splitlines()

                    def line_of(name):
                        return next(i for i, line in enumerate(lines) if f" {name} " in line)

                    markers = {item["range"]["start"]["line"] for item in diagnostics
                               if 2 in item.get("leanTags", [])}
                    expected = {line_of(name) for name in
                                ("control", "goodNative", "goodScript", "afterNative", "afterScript")}
                    assert markers == expected, (mode, markers, expected, diagnostics)
                    errors = [item for item in diagnostics if item.get("severity") == 1]
                    assert len(errors) == 2, (mode, errors)
                    assert {item["range"]["start"]["line"] for item in errors} == {
                        line_of("openError"), line_of("closedError")}, (mode, errors)
                    warnings = {item["range"]["start"]["line"] for item in diagnostics
                                if item.get("severity") == 2}
                    assert warnings == {line_of("openSorry"), line_of("closedSorry")}, (mode, diagnostics)
                    print(f"PASS native IDE completion markers pageBuild={mode}", flush=True)
                    send("textDocument/didClose", {"textDocument": {"uri": uri}})
                send("shutdown", None, 4)
                response(4)
                send("exit", None)
                assert process.wait(timeout=10) == 0
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


if __name__ == "__main__":
    main()
