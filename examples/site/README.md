# PS4HTML Demo

This project demonstrates every ProofScript component currently rendered by PS4HTML:

- project metadata and the generated project index;
- all current ProofText inline and block forms;
- build-time code highlighting through Pygments, with plain-text fallback for unknown languages;
- theorem components and proof-tree rendering;
- cross-module theorem references and the references component.
- a real Lean/Wasm Fibonacci computation with a range control, chart, timing, loading, and error states.

Build it from this directory:

```bash
python3 -m pip install -e ../../tools/ps4html
lake update
lake build PS4HTMLDemo:ps4html
```

The Fibonacci page requires the matching Lean/Wasm runtime:

```bash
source "$HOME/Developer/emsdk/emsdk_env.sh"
export PROOF_SCRIPT_LEAN_WASM_PREFIX="$HOME/Developer/lean4-wasm-4.32.0/build/proof-script-emscripten"
lake build PS4HTMLDemo:ps4html
```

The library facet builds the complete gallery, including the Fibonacci page and its C IR, finalizes
the Wasm bundle, and renders `.PS4HTML/build/PS4HTMLDemo/PS4HTMLDemo/PS4HTMLDemo/Fibonacci.html`.

Then serve the generated site:

```bash
ps4html serve
```

Open `http://127.0.0.1:8000/`. Do not double-click the generated HTML: browsers reject Wasm
resource fetches from a `file://` page. `ps4html serve` supplies the required Wasm MIME, COOP, COEP,
and CSP headers.

To expose the demo on the local network:

```bash
ps4html serve --lan
```

This prints the machine's LAN URL. Because the computation bundle uses pthreads and
`SharedArrayBuffer`, computation from another device requires trusted HTTPS:

```bash
ps4html serve --lan --cert ./localhost+2.pem --key ./localhost+2-key.pem
```

To render the existing ProofScript JSON without compiling Lean again:

```bash
ps4html make --cache
```
