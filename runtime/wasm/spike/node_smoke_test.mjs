import assert from "node:assert/strict";
import { writeFile } from "node:fs/promises";

const started = process.hrtime.bigint();
const module = await import("./build/proof_script_spike.mjs");
const instance = await module.default();
instance._proof_script_init();
const initialized = process.hrtime.bigint();
const encoder = new TextEncoder();
const decoder = new TextDecoder();

function invokeJson(input) {
  const encoded = encoder.encode(typeof input === "string" ? input : JSON.stringify(input));
  const inputPtr = instance._proof_script_alloc(encoded.byteLength);
  let outputCapacity = 256;
  let outputPtr = instance._proof_script_alloc(outputCapacity);
  instance.HEAPU8.set(encoded, inputPtr);

  let written = instance._proof_script_invoke(
    inputPtr,
    encoded.byteLength,
    outputPtr,
    outputCapacity,
  );
  if (written > outputCapacity) {
    instance._proof_script_free(outputPtr);
    outputCapacity = written;
    outputPtr = instance._proof_script_alloc(outputCapacity);
    written = instance._proof_script_invoke(
      inputPtr,
      encoded.byteLength,
      outputPtr,
      outputCapacity,
    );
  }

  const text = decoder.decode(instance.HEAPU8.slice(outputPtr, outputPtr + written));
  instance._proof_script_free(inputPtr);
  instance._proof_script_free(outputPtr);
  return JSON.parse(text);
}

assert.deepEqual(invokeJson({ message: "ab", count: 3 }), {
  ok: true,
  value: { text: "ababab", length: 6 },
});
assert.deepEqual(invokeJson({ message: "球", count: 2 }), {
  ok: true,
  value: { text: "球球", length: 6 },
});
const resized = invokeJson({ message: "lean", count: 300 });
assert.equal(resized.ok, true);
assert.equal(resized.value.text.length, 1200);

const invalidJson = invokeJson("{");
assert.equal(invalidJson.ok, false);
assert.equal(invalidJson.error.code, "invalid-json");

const invalidInput = invokeJson({ message: 1, count: 2 });
assert.equal(invalidInput.ok, false);
assert.equal(invalidInput.error.code, "invalid-input");

assert.deepEqual(invokeJson({ message: "x", count: 1001 }), {
  ok: false,
  error: { code: "computation-error", message: "count must not exceed 1000" },
});

const durations = [];
for (let i = 0; i < 1000; i += 1) {
  const before = process.hrtime.bigint();
  const response = invokeJson({ message: "e8", count: 4 });
  durations.push(Number(process.hrtime.bigint() - before) / 1e6);
  assert.equal(response.value.text, "e8e8e8e8");
}

durations.sort((a, b) => a - b);
const callsTotalMs = durations.reduce((sum, value) => sum + value, 0);
const report = {
  calls: 1006,
  protocol: "proofscript-json-v1",
  initializationMs: Number(initialized - started) / 1e6,
  callsTotalMs,
  callMeanMs: callsTotalMs / durations.length,
  callP95Ms: durations[Math.floor(durations.length * 0.95)],
  cases: ["success", "utf8", "output-resize", "invalid-json", "invalid-input", "computation-error"],
};
await writeFile("runtime/wasm/spike/build/benchmark-report.json", `${JSON.stringify(report, null, 2)}\n`);
console.log(JSON.stringify(report));
