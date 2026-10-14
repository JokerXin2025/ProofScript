#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
spike="$root/runtime/wasm/spike"
lean_source=${PROOF_SCRIPT_LEAN_SOURCE:-$HOME/Developer/lean4-wasm-4.32.0}
out=${PROOF_SCRIPT_LEAN_WASM_BUILD:-$lean_source/build/proofscript-emscripten}
libuv_source=${PROOF_SCRIPT_LIBUV_SOURCE:-}
expected_hash=$(lean --githash)

if ! command -v emcmake >/dev/null 2>&1; then
  echo "emcmake is unavailable; source emsdk_env.sh first" >&2
  exit 2
fi
if [ ! -d "$lean_source/.git" ]; then
  echo "PROOF_SCRIPT_LEAN_SOURCE must be a Lean git checkout" >&2
  exit 2
fi
actual_hash=$(git -C "$lean_source" rev-parse HEAD)
if [ "$actual_hash" != "$expected_hash" ]; then
  echo "Lean source commit $actual_hash does not match toolchain $expected_hash" >&2
  exit 2
fi

if patch -d "$lean_source/stage0" -p1 --dry-run < "$spike/lean-4.32.0-emscripten.patch" >/dev/null 2>&1; then
  patch -d "$lean_source/stage0" -p1 < "$spike/lean-4.32.0-emscripten.patch"
elif ! patch -d "$lean_source/stage0" -R -p1 --dry-run < "$spike/lean-4.32.0-emscripten.patch" >/dev/null 2>&1; then
  echo "Lean Emscripten compatibility patch cannot be applied cleanly" >&2
  exit 2
fi

rm -rf "$out"
emcmake cmake -S "$lean_source/stage0/src" -B "$out" -G "Unix Makefiles" \
  -DSTAGE=0 -DCMAKE_BUILD_TYPE=Release \
  -DUSE_LAKE=OFF -DUSE_MIMALLOC=OFF -DUSE_GMP=OFF -DWFAIL=OFF

if [ -n "$libuv_source" ]; then
  if [ ! -d "$libuv_source/.git" ]; then
    echo "PROOF_SCRIPT_LIBUV_SOURCE must be a libuv git checkout" >&2
    exit 2
  fi
  libuv_target="$out/libuv/src/libuv"
  rm -rf "$libuv_target"
  mkdir -p "$out/libuv/src"
  cp -R "$libuv_source" "$libuv_target"
  git -C "$libuv_target" clean -fdx
  touch "$out/libuv/src/libuv-stamp/libuv-download"
fi

cmake --build "$out" --target leanrt -j2
make -C "$lean_source/stage0/src" -f "$out/stdlib.make" Lean

test -f "$out/lib/lean/libleanrt.a"
test -f "$out/lib/lean/libInit.a"
test -f "$out/lib/lean/libStd.a"
test -f "$out/lib/lean/libLean.a"
printf '%s\n' "$out"
