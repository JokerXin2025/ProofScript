# Lean Wasm Spike

> Historical prototype. Its `build.sh` refers to the removed standalone
> `ProofScript/Computation/Json.lean` layout and is not the supported current build entry.
> Use `lake build MyLibrary:ps4html` and the [current computation quickstart](../../../docs/Embedded-Computation-Quickstart-zh.md).
> The notes below record the original experiment; `build_lean_runtime.sh` remains the runtime preparation helper.

This directory contains the Phase 1 runtime probe and Phase 2 typed JSON ABI
probe. It deliberately does not use the page computation component and does not
attempt to interpret Lean expression JSON.

## Pipeline

```text
ProofScript/Computation/Json.lean + Spike.lean --(Lean C backend)--> build/*.c
generated C + proof_script_shim.c --(Emscripten)--> proof_script_spike.mjs/.wasm
Node smoke test --> typed JSON success/errors and 1000 repeated calls
```

The exported Lean entry point remains `String -> String` at the FFI boundary, but
`ProofScript.Computation.invokeJson` parses JSON, derives typed `FromJson`/`ToJson`
codecs, executes `α -> Except String β`, and returns a stable envelope. The C shim
exposes a small fixed byte-buffer ABI and keeps Lean's `lean_object*` representation
behind the boundary.

Success response:

```json
{"ok":true,"value":{}}
```

Error response:

```json
{"ok":false,"error":{"code":"invalid-input","message":"..."}}
```

Error codes are `invalid-json`, `invalid-input`, and `computation-error`.

## Run

```sh
source "$HOME/Developer/emsdk/emsdk_env.sh"
./runtime/wasm/spike/build_lean_runtime.sh
PROOF_SCRIPT_LEAN_WASM_PREFIX="$HOME/Developer/lean4-wasm-4.32.0/build/proofscript-emscripten" \
  ./runtime/wasm/spike/build.sh
node runtime/wasm/spike/node_smoke_test.mjs
```

If libuv cannot be downloaded during the runtime build, an existing v1.48.0
checkout can be supplied without changing global Git proxy settings:

```sh
PROOF_SCRIPT_LIBUV_SOURCE=/path/to/libuv-v1.48.0 \
  ./runtime/wasm/spike/build_lean_runtime.sh
```

If a compatible runtime prefix already exists, only the last two commands are
needed:

```sh
./runtime/wasm/spike/build.sh
node runtime/wasm/spike/node_smoke_test.mjs
```

The build always produces `build/Spike.c` and `build/build-report.json`. If `emcc`
is unavailable it exits successfully after reporting `status: pending`; the Wasm
link and Node smoke test are then intentionally unavailable rather than silently
using a native library.

The expected pinned inputs are Lean 4.32.0 and the Lean commit reported by
`lean --githash`. The Emscripten link also requires a target-platform Lean
prefix, not the host macOS libraries:

```sh
PROOF_SCRIPT_LEAN_WASM_PREFIX=/path/to/emscripten/lean-prefix \
  ./runtime/wasm/spike/build.sh
```

That prefix must contain `lib/lean/libleanrt.a`, `libInit.a`, `libStd.a`, and `libLean.a`
produced by the same Lean source commit. The build script intentionally refuses
to link the host's `libleanrt.a`. Once the toolchain is available, the project
should pin the Emscripten version in CI and include it in `build-report.json`.

Lean 4.32.0 contains several Emscripten fallback definitions whose C signatures do
not match their headers. `build_lean_runtime.sh` applies the narrow compatibility
patch in `lean-4.32.0-emscripten.patch`; it rejects an unrelated or mismatched
Lean checkout instead of applying the patch fuzzily.

The target platform is selected by `emcmake` (`CMAKE_SYSTEM_NAME=Emscripten`);
the CMake build type remains `Release`. The historical documentation's
`CMAKE_BUILD_TYPE=Emscripten` omits the current release optimization flags.

Lean's current Emscripten settings build the runtime with pthread support. A
browser deployment therefore needs cross-origin isolation for SharedArrayBuffer
(`Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp`). Removing that requirement by
building a single-thread runtime is a follow-up optimization, not part of this
pipeline feasibility spike.

Application C objects and the runtime must use the same release flags. In
particular, `build.sh` compiles generated C with `-DNDEBUG`; mixing assert-enabled
application C with release bootstrap libraries triggers internal reference-count
assertions in JSON decoding paths.
