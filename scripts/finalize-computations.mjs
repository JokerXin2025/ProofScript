#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, relative, resolve } from "node:path";

const root = process.cwd();
const outputRoot = resolve(process.env.PROOF_SCRIPT_OUTPUT_ROOT || join(root, ".ProofScript"));
const pendingRoot = join(outputRoot, "computations", "pending");
const bundlesRoot = join(outputRoot, "computations", "bundles");
const pagesRoot = join(outputRoot, "pages");
const resourcesRoot = join(outputRoot, "resources", "computation");
const indexPath = join(outputRoot, "computations", "index.json");

function filesBelow(path, suffix) {
  if (!existsSync(path)) return [];
  const result = [];
  for (const entry of readdirSync(path, { withFileTypes: true })) {
    const child = join(path, entry.name);
    if (entry.isDirectory()) result.push(...filesBelow(child, suffix));
    else if (entry.name.endsWith(suffix)) result.push(child);
  }
  return result;
}

function sha256(content) {
  return createHash("sha256").update(content).digest("hex");
}

function resource(path, hash, mediaType, encoding, byteSize) {
  return {
    $resource: {
      path: join(".ProofScript", relative(outputRoot, path)),
      hash,
      mediaType,
      encoding,
      byteSize,
    },
  };
}

function writeJsonAtomic(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  const temporary = `${path}.tmp-${process.pid}`;
  writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`);
  renameSync(temporary, path);
}

const pending = filesBelow(pendingRoot, ".json").map(path => JSON.parse(readFileSync(path, "utf8")));
if (pending.length === 0) throw new Error("no pending computation manifests to finalize");
const pendingKeys = new Set(pending.map(entry => `${entry.bundleId}\0${entry.entry}`));

const buildManifests = filesBelow(bundlesRoot, "bundle.json").map(path => ({
  path,
  value: JSON.parse(readFileSync(path, "utf8")),
}));
if (buildManifests.length === 0) throw new Error("no computation bundles; run build-computations.mjs first");

const bundles = new Map();
for (const { path, value } of buildManifests) {
  if (bundles.has(value.bundleId)) throw new Error(`duplicate bundle: ${value.bundleId}`);
  const actualEntries = new Set(value.entries.map(entry => `${value.bundleId}\0${entry.id}`));
  for (const key of actualEntries) {
    if (!pendingKeys.has(key)) throw new Error(`stale bundle entry: ${key.replace("\0", ":")}`);
  }
  const expected = pending.filter(entry => entry.bundleId === value.bundleId);
  for (const entry of expected) {
    if (!actualEntries.has(`${entry.bundleId}\0${entry.entry}`)) {
      throw new Error(`bundle ${value.bundleId} is missing entry ${entry.entry}`);
    }
  }

  const sourceDir = dirname(path);
  const moduleSource = join(sourceDir, basename(value.artifacts.module));
  const wasmSource = join(sourceDir, basename(value.artifacts.wasm));
  const moduleBytes = readFileSync(moduleSource);
  const wasmBytes = readFileSync(wasmSource);
  const moduleHash = sha256(moduleBytes);
  const wasmHash = sha256(wasmBytes);
  if (wasmHash !== value.artifacts.wasmSha256) {
    throw new Error(`Wasm hash mismatch for ${value.bundleId}`);
  }
  const bundleHash = createHash("sha256")
    .update(moduleBytes)
    .update("\0")
    .update(wasmBytes)
    .digest("hex");
  const destination = join(resourcesRoot, bundleHash);
  if (!existsSync(destination)) {
    const temporary = `${destination}.tmp-${process.pid}`;
    rmSync(temporary, { recursive: true, force: true });
    mkdirSync(temporary, { recursive: true });
    copyFileSync(moduleSource, join(temporary, "bundle.mjs"));
    copyFileSync(wasmSource, join(temporary, "bundle.wasm"));
    renameSync(temporary, destination);
  } else {
    if (sha256(readFileSync(join(destination, "bundle.mjs"))) !== moduleHash ||
        sha256(readFileSync(join(destination, "bundle.wasm"))) !== wasmHash) {
      throw new Error(`content-addressed resource collision: ${bundleHash}`);
    }
  }

  const published = {
    schemaVersion: "0.0.0",
    abi: value.abi,
    bundleId: value.bundleId,
    bundleHash,
    entries: value.entries,
    module: resource(join(destination, "bundle.mjs"), moduleHash, "text/javascript", "utf-8", moduleBytes.length),
    wasm: resource(join(destination, "bundle.wasm"), wasmHash, "application/wasm", "binary", wasmBytes.length),
  };
  const publishedText = `${JSON.stringify(published, null, 2)}\n`;
  const publishedPath = join(destination, "bundle.json");
  writeFileSync(publishedPath, publishedText);
  published.manifest = resource(
    publishedPath,
    sha256(Buffer.from(publishedText)),
    "application/vnd.proofscript.computation-bundle+json",
    "utf-8",
    Buffer.byteLength(publishedText),
  );
  bundles.set(value.bundleId, published);
}

for (const entry of pending) {
  if (!bundles.has(entry.bundleId)) throw new Error(`missing bundle for pending entry ${entry.entry}`);
}

const pageUpdates = [];
const finalizedEntries = new Set();
for (const pagePath of filesBelow(pagesRoot, ".json")) {
  const page = JSON.parse(readFileSync(pagePath, "utf8"));
  let changed = false;
  for (const component of page.components ?? []) {
    const value = component.data?.computation?.value;
    const execution = value?.execution;
    if (!execution || execution.backend !== "wasm") continue;
    const bundle = bundles.get(execution.bundleId);
    if (!bundle) continue;
    if (!bundle.entries.some(entry => entry.id === execution.entry)) {
      throw new Error(`page ${relative(root, pagePath)} references missing entry ${execution.entry}`);
    }
    value.schemaVersion = "0.0.0";
    value.execution = {
      backend: "wasm",
      status: "ready",
      abi: bundle.abi,
      bundleId: execution.bundleId,
      entry: execution.entry,
      wrapper: execution.wrapper,
      manifest: bundle.manifest,
      module: bundle.module,
      wasm: bundle.wasm,
    };
    finalizedEntries.add(`${execution.bundleId}\0${execution.entry}`);
    changed = true;
  }
  if (changed) pageUpdates.push({ pagePath, page });
}

for (const key of pendingKeys) {
  if (!finalizedEntries.has(key)) {
    throw new Error(`pending entry has no page component: ${key.replace("\0", ":")}`);
  }
}

for (const { pagePath, page } of pageUpdates) writeJsonAtomic(pagePath, page);

const index = {
  schemaVersion: "0.0.0",
  abi: "proofscript-json-v1",
  bundles: [...bundles.values()].map(bundle => ({
    bundleId: bundle.bundleId,
    bundleHash: bundle.bundleHash,
    entries: bundle.entries.map(entry => entry.id),
    manifest: bundle.manifest,
    module: bundle.module,
    wasm: bundle.wasm,
  })).sort((left, right) => left.bundleId.localeCompare(right.bundleId)),
  pagesUpdated: pageUpdates.map(update => relative(root, update.pagePath)).sort(),
};
writeJsonAtomic(indexPath, index);
console.log(`finalized ${bundles.size} bundles and ${finalizedEntries.size} entries in ${pageUpdates.length} pages`);
