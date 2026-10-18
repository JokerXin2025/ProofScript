#!/usr/bin/env node

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const root = process.cwd();
const pagePath = process.argv[2];
if (!pagePath) throw new Error("usage: test-finalized-computation.mjs <page.json>");
const resolvedPage = resolve(root, pagePath);
const snapshot = resolvedPage.includes("/.PS4HTML/inputs/")
  ? resolvedPage.slice(0, resolvedPage.indexOf("/.ProofScript/pages/")) : root;
const page = JSON.parse(await readFile(resolve(root, pagePath), "utf8"));
const bundle = JSON.parse(await readFile(resolve(snapshot, ".ProofScript/info/index.json"), "utf8"));
assert.equal(bundle.schemaVersion, "5.0.0");
assert.equal(bundle.complete, true);
const computations = page.components
  .map(component => component.data?.computation?.value)
  .filter(Boolean);
assert.ok(computations.length > 0);
assert.ok(computations.every(value => value.execution.status === "ready"));
assert.ok(computations.every(value => value.schemaVersion === "0.0.0"));

async function verifiedResource(reference) {
  const descriptor = reference.$resource;
  const path = resolve(snapshot, descriptor.path);
  const bytes = await readFile(path);
  assert.equal(createHash("sha256").update(bytes).digest("hex"), descriptor.hash);
  assert.equal(bytes.length, descriptor.byteSize);
  return { path, bytes };
}

const execution = computations[0].execution;
for (const value of computations) {
  const manifest = JSON.parse((await verifiedResource(value.execution.manifest)).bytes.toString("utf8"));
  assert.equal(manifest.schemaVersion, "0.0.0");
  assert.ok(manifest.entries.some(entry => entry.id === value.execution.entry));
  await verifiedResource(value.execution.module);
  await verifiedResource(value.execution.wasm);
}
await verifiedResource(execution.wasm);
const moduleResource = await verifiedResource(execution.module);
const instance = await (await import(pathToFileURL(moduleResource.path))).default();
instance._proof_script_init();
const encoder = new TextEncoder();
const decoder = new TextDecoder();

function invoke(entry, input) {
  const entryBytes = encoder.encode(entry);
  const inputBytes = encoder.encode(JSON.stringify(input));
  const entryPtr = instance._proof_script_alloc(entryBytes.length);
  const inputPtr = instance._proof_script_alloc(inputBytes.length);
  instance.HEAPU8.set(entryBytes, entryPtr);
  instance.HEAPU8.set(inputBytes, inputPtr);
  let capacity = 256;
  let outputPtr = instance._proof_script_alloc(capacity);
  let length = instance._proof_script_invoke(
    entryPtr, entryBytes.length, inputPtr, inputBytes.length, outputPtr, capacity,
  );
  if (length > capacity) {
    instance._proof_script_free(outputPtr);
    capacity = length;
    outputPtr = instance._proof_script_alloc(capacity);
    length = instance._proof_script_invoke(
      entryPtr, entryBytes.length, inputPtr, inputBytes.length, outputPtr, capacity,
    );
  }
  const result = JSON.parse(decoder.decode(instance.HEAPU8.slice(outputPtr, outputPtr + length)));
  instance._proof_script_free(entryPtr);
  instance._proof_script_free(inputPtr);
  instance._proof_script_free(outputPtr);
  return result;
}

assert.equal(invoke("__missing_entry__", {}).error.code, "unknown-entry");
const entries = new Set(computations.filter(value => value.execution.bundleId === execution.bundleId).map(value => value.execution.entry));
if (entries.has("chooseOffset")) assert.deepEqual(invoke("chooseOffset", true), { ok: true, value: 128 });
if (entries.has("doubleValue")) assert.deepEqual(invoke("doubleValue", { value: 21 }), { ok: true, value: { doubled: 42 } });
if (entries.has("computeFibonacci")) {
  assert.equal(invoke("computeFibonacci", { n: 10 }).value.value, 55);
  assert.equal(invoke("computeFibonacci", { n: 41 }).error.code, "computation-error");
}
console.log(JSON.stringify({ resources: 3, entries: computations.length, status: "ok" }));
