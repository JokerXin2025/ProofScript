#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
spike="$root/runtime/wasm/spike"
out="$spike/build"
lean_version=$(lean --version | head -n 1)
lean_hash=$(lean --githash)

mkdir -p "$out"
mkdir -p "$out/ProofScript/Computation"
lean "$root/ProofScript/Computation/Json.lean" -R "$root" \
  -o "$out/ProofScript/Computation/Json.olean" \
  -i "$out/ProofScript/Computation/Json.ilean" \
  -c "$out/ComputationJson.c"
LEAN_PATH="$out${LEAN_PATH:+:$LEAN_PATH}" lean "$spike/Spike.lean" -R "$root" \
  -o "$out/Spike.olean" \
  -i "$out/Spike.ilean" \
  -c "$out/Spike.c"

if command -v emcc >/dev/null 2>&1; then
  emcc_version=$(emcc --version | head -n 1)
  lean_wasm_prefix=${PROOF_SCRIPT_LEAN_WASM_PREFIX:-}
  if [ -z "$lean_wasm_prefix" ] || [ ! -f "$lean_wasm_prefix/lib/lean/libleanrt.a" ] || [ ! -f "$lean_wasm_prefix/lib/lean/libInit.a" ] || [ ! -f "$lean_wasm_prefix/lib/lean/libStd.a" ] || [ ! -f "$lean_wasm_prefix/lib/lean/libLean.a" ]; then
    echo "PROOF_SCRIPT_LEAN_WASM_PREFIX must point to an Emscripten-built Lean prefix" >&2
    echo "required: libleanrt.a, libInit.a, libStd.a, and libLean.a" >&2
    exit 2
  fi
  common_flags="-O3 -DNDEBUG -pthread -fwasm-exceptions -flto"
  emcc -c "$out/Spike.c" \
    -I"$lean_wasm_prefix/include" \
    -I"$lean_wasm_prefix/src" \
    $common_flags -o "$out/Spike.wasm.o"
  emcc -c "$out/ComputationJson.c" \
    -I"$lean_wasm_prefix/include" \
    -I"$lean_wasm_prefix/src" \
    $common_flags -o "$out/ComputationJson.wasm.o"
  emcc -c "$spike/proof_script_shim.c" \
    -I"$lean_wasm_prefix/include" \
    -I"$lean_wasm_prefix/src" \
    $common_flags -o "$out/proof_script_shim.wasm.o"
  em++ "$out/ComputationJson.wasm.o" "$out/Spike.wasm.o" "$out/proof_script_shim.wasm.o" \
    $common_flags -Wno-pthreads-mem-growth \
    -s WASM=1 -s MODULARIZE=1 -s EXPORT_ES6=1 -s ALLOW_MEMORY_GROWTH=1 \
    -s EXPORTED_FUNCTIONS='["_proof_script_init","_proof_script_alloc","_proof_script_free","_proof_script_invoke","_malloc"]' \
    -s EXPORTED_RUNTIME_METHODS='["HEAPU8"]' \
    "$lean_wasm_prefix/lib/lean/libLean.a" \
    "$lean_wasm_prefix/lib/lean/libStd.a" \
    "$lean_wasm_prefix/lib/lean/libInit.a" \
    "$lean_wasm_prefix/lib/lean/libleanrt.a" \
    -o "$out/proof_script_spike.mjs"
  wasm_bytes=$(wc -c < "$out/proof_script_spike.wasm" | tr -d ' ')
  module_bytes=$(wc -c < "$out/proof_script_spike.mjs" | tr -d ' ')
  gzip_bytes=$(gzip -c "$out/proof_script_spike.wasm" | wc -c | tr -d ' ')
else
  emcc_version="unavailable"
  wasm_bytes=0
  module_bytes=0
  gzip_bytes=0
  echo "emcc is not installed; generated Lean C but skipped Wasm link" >&2
fi

cat > "$out/build-report.json" <<EOF
{
  "leanVersion": "$(printf '%s' "$lean_version" | sed 's/"/\\"/g')",
  "leanCommit": "$lean_hash",
  "emscripten": "$emcc_version",
  "sources": ["ProofScript/Computation/Json.lean", "runtime/wasm/spike/Spike.lean"],
  "entry": "proof_script_spike",
  "abi": "proofscript-json-v1",
  "artifacts": {
    "wasmBytes": $wasm_bytes,
    "moduleBytes": $module_bytes,
    "wasmGzipBytes": $gzip_bytes
  },
  "status": "$(if [ "$emcc_version" = unavailable ]; then printf pending; else printf wasm-linked; fi)"
}
EOF

wc -c "$out/Spike.c" "$out/build-report.json"
