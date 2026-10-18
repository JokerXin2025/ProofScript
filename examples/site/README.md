# PS4HTML Demo

This project demonstrates every ProofScript component currently rendered by PS4HTML:

- project metadata and the generated project index;
- all current ProofText inline and block forms;
- build-time code highlighting through Pygments, with plain-text fallback for unknown languages;
- theorem components and proof-tree rendering;
- cross-module theorem references and the references component.
- proof-derived dependency navigation with theorem and lemma bodies sharing mouse interaction with their navigation;
- a single explicit project ID, `"PS4HTMLDemo"`, shared by the theorem library, gallery and dependency examples;
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
It first removes this project's Lake build directory, then compiles the library once with JSON
exports written into staging. Dependency build directories and caches are retained. Info export,
Wasm finalization, and HTML rendering use those outputs without compiling the Lean sources again.

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

The theorem library includes an ordinary Lean theorem with explicit `theorem_info.project`,
a recorded lemma using it, and a theorem on the Dependencies page using that lemma. The
ordinary theorem remains an unlinked dependency node; the exported lemma has a reverse link
to the other page. Dependencies are direct references in the final proof, filtered by the
frozen `ProjectId`. Reference collection is independent of this graph.

Move the mouse over a theorem to show its navigation. Moving to that navigation preserves
the source selection so its links can be clicked. Moving outside both areas hides it after
150 ms; another theorem switches immediately. Scroll and layout changes recheck the saved
mouse position. Hash navigation alone does not select a theorem.

From the repository root, check the interaction controller and the generated site with Node 22+
and Chrome (`CHROME` may specify a different browser executable):

```bash
node Test/test_theorem_navigation_browser.mjs
node Test/test_theorem_site_browser.mjs
```

The generated-site check uses the published HTML, CSS, JS and matching exported proof facts,
including cross-page reverse edges, lemma language switching and navigation clicks. It loads
the page's normal KaTeX CDN assets, so network access is required. Internal Python test scripts
were removed after acceptance; they are not part of the build.

Each proof and page component uses local metadata available when it is created, plus the complete
configuration of imported modules. Recorded declarations set their own title with inline
`(info := { name := "..." })`; later `theorem_info` commands only affect subsequent content.
`page_end` controls page output rather than configuration scope.

Ordinary `lake build` and IDE checking only verify native theorems. The `:ps4html` target
automatically enables recording and page export, using `.lake/ps4html/PS4HTMLDemo/PS4HTMLDemo/`
for user-source Lean artifacts. It preserves the ordinary verification cache; the computation
bundler uses the isolated workspace's C and setup paths supplied by Lake.

Info bundles use protocol `5.0.0`, theorem manifest `5`, and snapshot payload `4`. To migrate
older exports, rebuild with `lake build PS4HTMLDemo:ps4html`; `--cache` never upgrades exports
or invokes Lean. If an old installation used real directories at the build/input release-link
paths, archive that project's `.PS4HTML` directory before rebuilding. Do not edit protocol
versions or add empty dependency arrays to old JSON. See the [migration notes](../../docs/Theorem-Navigation-Refactor-Plan-zh.md).
