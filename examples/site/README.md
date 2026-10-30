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

For custom recorders, the separate [recording example](../recording/README.md) shows parameter
recording, typed value writes, and goal snapshots. Neither parameter recording nor value writes
collect literature references.

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
to the other page. Navigation uses automatic references in the final proof, filtered by the
frozen `ProjectId`. The complete `proofRefs` also retains manual citations and references to
other projects; `proofDependencies` is the navigation projection.

The final section of `Dependencies.lean` disables automatic collection and explicitly cites
the imported lemma. Its references panel displays that citation with `isDependency = false`,
and the theorem has no navigation dependencies. The preceding references panel consumes the
earlier automatic references without changing any theorem's persisted facts.

To build this page independently:

```bash
lake build +PS4HTMLDemo.Dependencies:ps4html
```

Its module preview is under `.PS4HTML/build/PS4HTMLDemo/.modules/PS4HTMLDemo.Dependencies/`.

Move the mouse over a theorem to show its navigation. Moving to that navigation preserves
the source selection so its links can be clicked. Moving outside both areas hides it after
150 ms; another theorem switches immediately. Scroll and layout changes recheck the saved
mouse position. Hash navigation alone does not select a theorem.

Each proof and page component uses the final metadata of its owner module and all transitive
imports, including local Info commands after the proof or `#page end`. The standalone
`theorem_info` command configures theorem titles, tags and project ownership after the
declaration exists. Native doc comments remain available to Lean and the editor.
`#page end` closes page content collection. Downstream overrides affect
downstream content while reused upstream proofs retain their upstream snapshots.
Pages with multiple candidate projects have no default page `projectId`; each named proof must
select its own project explicitly. The last `project_info` does not choose a page-wide default.

Ordinary `lake build` and IDE checking synchronously check each proof in an internal `def`
and publish a native theorem that references it, without recording or exporting pages. The `:ps4html` target
automatically enables recording and page export, using `.lake/ps4html/PS4HTMLDemo/PS4HTMLDemo/`
for user-source Lean artifacts. It preserves the ordinary verification cache; the computation
bundler uses the isolated workspace's C and setup paths supplied by Lake.

Info bundles use protocol `9.0.0`, theorem manifest `9`, and snapshot payload `7`. Proof steps
use the recording protocol `0.3.0` with `$ruleId`, `$goal_before`, `$goal_after`, and
`$branches` as framework fields. To migrate older exports, rebuild with
`lake build PS4HTMLDemo:ps4html`; `--cache` never upgrades exports or invokes Lean. If an old
installation used real directories at the build/input release-link paths, archive that
project's `.PS4HTML` directory before rebuilding. Do not edit protocol versions or add empty
dependency arrays to old JSON. See the [current export protocol](../../docs/Info-Commands-zh.md)
and the [phase-six recording migration](../../docs/Script-Binding-Phase6-zh.md).
