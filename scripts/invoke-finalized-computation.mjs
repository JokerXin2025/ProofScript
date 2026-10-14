#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [pageArgument, entryArgument, inputArgument] = process.argv.slice(2);
if (!pageArgument || !entryArgument || inputArgument === undefined) {
  throw new Error("usage: invoke-finalized-computation.mjs <page.json> <entry> <input-json>");
}
const root = process.cwd();
const resolvedPage = resolve(root, pageArgument);
const snapshot = resolvedPage.includes("/.PS4HTML/inputs/")
  ? resolvedPage.slice(0, resolvedPage.indexOf("/.ProofScript/pages/")) : root;
const page = JSON.parse(await readFile(resolve(root, pageArgument), "utf8"));
const value = page.components
  .map(component => component.data?.computation?.value)
  .find(component => component?.execution?.entry === entryArgument);
if (!value) throw new Error(`page does not contain computation entry ${entryArgument}`);
if (value.execution.status !== "ready") throw new Error(`computation is ${value.execution.status}`);

async function verifiedPath(reference) {
  const descriptor = reference.$resource;
  const path = resolve(snapshot, descriptor.path);
  const bytes = await readFile(path);
  if (descriptor.byteSize !== undefined && descriptor.byteSize !== bytes.length) {
    throw new Error(`byte size mismatch: ${descriptor.path}`);
  }
  if (createHash("sha256").update(bytes).digest("hex") !== descriptor.hash) {
    throw new Error(`SHA-256 mismatch: ${descriptor.path}`);
  }
  return path;
}

await verifiedPath(value.execution.manifest);
await verifiedPath(value.execution.wasm);
const modulePath = await verifiedPath(value.execution.module);
const instance = await (await import(pathToFileURL(modulePath))).default();
instance._proof_script_init();
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
const entryBytes = encoder.encode(entryArgument);
const inputBytes = encoder.encode(inputArgument);
const entryPointer = instance._proof_script_alloc(entryBytes.length);
const inputPointer = instance._proof_script_alloc(inputBytes.length);
instance.HEAPU8.set(entryBytes, entryPointer);
instance.HEAPU8.set(inputBytes, inputPointer);
let capacity = 64 * 1024;
let outputPointer = instance._proof_script_alloc(capacity);
try {
  let length = instance._proof_script_invoke(
    entryPointer, entryBytes.length, inputPointer, inputBytes.length, outputPointer, capacity,
  );
  if (length > capacity) {
    instance._proof_script_free(outputPointer);
    capacity = length;
    outputPointer = instance._proof_script_alloc(capacity);
    length = instance._proof_script_invoke(
      entryPointer, entryBytes.length, inputPointer, inputBytes.length, outputPointer, capacity,
    );
  }
  const result = JSON.parse(decoder.decode(instance.HEAPU8.slice(outputPointer, outputPointer + length)));
  console.log(JSON.stringify(result, null, 2));
} finally {
  instance._proof_script_free(entryPointer);
  instance._proof_script_free(inputPointer);
  instance._proof_script_free(outputPointer);
}
