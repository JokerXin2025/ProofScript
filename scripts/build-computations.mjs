#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = process.cwd();
const proofScriptRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outputRoot = resolve(process.env.PROOF_SCRIPT_OUTPUT_ROOT || join(root, ".ProofScript"));
const pendingRoot = join(outputRoot, "computations", "pending");
const bundlesRoot = join(outputRoot, "computations", "bundles");
const leanWasmPrefix = process.env.PROOF_SCRIPT_LEAN_WASM_PREFIX;

if (!leanWasmPrefix) {
  throw new Error("PROOF_SCRIPT_LEAN_WASM_PREFIX is required");
}
const archiveLibraries = ["libLean.a", "libStd.a", "libInit.a", "libleanrt.a"]
  .map(library => join(leanWasmPrefix, "lib", "lean", library));
for (const library of archiveLibraries) {
  if (!existsSync(library)) throw new Error(`missing Wasm Lean library: ${library}`);
}
// Archive objects may be pulled in by reachable functions as well as initializers.
// Never emit a competing stub for an initializer supplied by the runtime.
const archiveInitializers = new Set(execFileSync("emnm",
  ["--defined-only", "--just-symbol-name", ...archiveLibraries],
  {encoding: "utf8", maxBuffer: 64 * 1024 * 1024}).split(/\r?\n/)
  .filter(symbol => /^(?:runtime_|meta_)?initialize_[A-Za-z0-9_x]+$/.test(symbol)));

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

function manglePart(text) {
  let result = "";
  for (const char of text) {
    if (/^[A-Za-z0-9]$/.test(char)) result += char;
    else if (char === "_") result += "__";
    else {
      const value = char.codePointAt(0);
      const prefix = value < 0x100 ? "_x" : value < 0x10000 ? "_u" : "_U";
      const width = value < 0x100 ? 2 : value < 0x10000 ? 4 : 8;
      result += `${prefix}${value.toString(16).padStart(width, "0")}`;
    }
  }
  return result;
}

function needsDisambiguation(previous, next) {
  if (previous.endsWith("_")) return true;
  return /^_*(?:x[0-9a-f]{2}|u[0-9a-f]{4}|U[0-9a-f]{8}|[0-9])/.test(next);
}

function mangleName(name, prefix = "l_") {
  const parts = name.split(".");
  let result = "";
  let previous = "";
  for (const part of parts) {
    const encoded = manglePart(part);
    if (!result) result = /^_*(?:x[0-9a-f]{2}|u[0-9a-f]{4}|U[0-9a-f]{8}|[0-9])/.test(encoded)
      ? `00${encoded}` : encoded;
    else result += `${needsDisambiguation(previous, encoded) ? "_00" : "_"}${encoded}`;
    previous = part;
  }
  return `${prefix}${result}`;
}

function modulePaths(moduleName) {
  const path = moduleName.replaceAll(".", "/");
  return {
    c: join(root, ".lake", "build", "ir", `${path}.c`),
    setup: join(root, ".lake", "build", "ir", `${path}.setup.json`),
  };
}

function importCFile(setup, moduleName) {
  const artifacts = setup.importArts?.[moduleName] ?? [];
  const olean = artifacts.find(path => path.endsWith(".olean"));
  if (!olean) {
    const support = join(proofScriptRoot, ".lake", "build", "ir", `${moduleName.replaceAll(".", "/")}.c`);
    if (existsSync(support)) return support;
    throw new Error(`missing imported module artifact: ${moduleName}`);
  }
  const marker = `${join("lib", "lean")}/`;
  const normalized = olean.replaceAll("\\", "/");
  const index = normalized.lastIndexOf(marker);
  if (index < 0) throw new Error(`cannot locate package root for ${moduleName}`);
  const packageRoot = normalized.slice(0, index);
  const candidate = join(packageRoot, "ir", `${moduleName.replaceAll(".", "/")}.c`);
  if (!existsSync(candidate)) throw new Error(`missing C IR for imported module ${moduleName}`);
  return candidate;
}

function importedCFiles(setup) {
  const files = [];
  for (const artifacts of Object.values(setup.importArts ?? {})) {
    const olean = artifacts.find(path => path.endsWith(".olean"));
    if (!olean) continue;
    const normalized = olean.replaceAll("\\", "/");
    const marker = "/lib/lean/";
    const index = normalized.lastIndexOf(marker);
    if (index < 0) continue;
    const packageRoot = normalized.slice(0, index);
    const modulePath = normalized.slice(index + marker.length, -".olean".length);
    const candidate = join(packageRoot, "ir", `${modulePath}.c`);
    if (existsSync(candidate)) files.push(candidate);
  }
  return [...new Set(files)];
}

function cSymbols(source) {
  const symbols = new Set();
  const callPattern = /\b(lp_[A-Za-z0-9_x]+|l_[A-Za-z0-9_x]+|(?:runtime_|meta_)?initialize_[A-Za-z0-9_x]+)\s*\(/g;
  const pointerPattern = /\(void\*\)\s*(lp_[A-Za-z0-9_x]+|l_[A-Za-z0-9_x]+)/g;
  const objectPointerPattern = /\(\(lean_object\*\)\s*\(?(lp_[A-Za-z0-9_x]+|l_[A-Za-z0-9_x]+)/g;
  const objectReferencePattern = /\b(lp_[A-Za-z0-9_x]+___closed__[A-Za-z0-9_x]+)\b/g;
  for (const line of source.split("\n")) {
    for (const match of line.matchAll(pointerPattern)) symbols.add(match[1]);
    for (const match of line.matchAll(objectPointerPattern)) symbols.add(match[1]);
    for (const match of line.matchAll(objectReferencePattern)) symbols.add(match[1]);
    if (/^\s*(?:LEAN_EXPORT|static|extern\b)/.test(line)) continue;
    if (/^\s*(?:(?:LEAN_EXPORT|static)\s+)?(?:lean_object\s*\*|lean_obj_res|uint8_t|uint32_t|uint64_t|int8_t|int32_t|int64_t|double|void|bool|size_t|float)\s+(?:lp_|l_|(?:runtime_|meta_)?initialize_)/.test(line)) continue;
    for (const match of line.matchAll(callPattern)) symbols.add(match[1]);
  }
  return symbols;
}

function cDefinitions(source) {
  const definitions = new Set();
  const pattern = /\b(?:LEAN_EXPORT|static)\s+(?:const\s+)?(?:lean_object\s*\*|lean_obj_res|uint8_t|uint32_t|uint64_t|int8_t|int32_t|int64_t|double|void|bool|size_t|float)\s+([A-Za-z0-9_x]+)\s*\(/g;
  for (const match of source.matchAll(pattern)) definitions.add(match[1]);
  return definitions;
}

function cInitializerDefinitions(source) {
  const definitions = new Set();
  const pattern = /\b((?:runtime_|meta_)?initialize_[A-Za-z0-9_x]+)\s*\([^)]*\)\s*\{/g;
  for (const match of source.matchAll(pattern)) definitions.add(match[1]);
  return definitions;
}

function isInitializer(symbol) {
  return /^(?:runtime_|meta_)?initialize_/.test(symbol);
}

function cDefinitionBodies(source) {
  const bodies = new Map();
  const pattern = /\b(?:LEAN_EXPORT|static)\s+(?:const\s+)?(?:lean_object\*|lean_obj_res|uint8_t|uint32_t|uint64_t|int8_t|int32_t|int64_t|double|void|bool|size_t|float)\s+([A-Za-z0-9_x]+)\s*\([^;{}]*\)\s*\{/g;
  for (const match of source.matchAll(pattern)) {
    const bodyStart = match.index + match[0].length - 1;
    let depth = 0;
    let quote = false;
    let escaped = false;
    let lineComment = false;
    let blockComment = false;
    let end = bodyStart;
    for (let index = bodyStart; index < source.length; index += 1) {
      const char = source[index];
      const next = source[index + 1];
      if (lineComment) {
        if (char === "\n") lineComment = false;
        continue;
      }
      if (blockComment) {
        if (char === "*" && next === "/") {
          blockComment = false;
          index += 1;
        }
        continue;
      }
      if (quote) {
        if (escaped) escaped = false;
        else if (char === "\\") escaped = true;
        else if (char === '"') quote = false;
        continue;
      }
      if (char === '"') {
        quote = true;
      } else if (char === "/" && next === "/") {
        lineComment = true;
        index += 1;
      } else if (char === "/" && next === "*") {
        blockComment = true;
        index += 1;
      } else if (char === "{") {
        depth += 1;
      } else if (char === "}" && --depth === 0) {
        end = index + 1;
        break;
      }
    }
    if (end > bodyStart) bodies.set(match[1], source.slice(bodyStart, end));
  }
  // Lean stores function closures in static const objects. Their `.m_fun`
  // pointer is part of the dependency graph even though the object is not a
  // C function declaration.
  const closurePattern = /\bstatic\s+const\s+[^;{}]+\s+(lp_[A-Za-z0-9_x]+)_value\s*=\s*\{/g;
  for (const match of source.matchAll(closurePattern)) {
    const bodyStart = match.index + match[0].length - 1;
    let depth = 0;
    let end = bodyStart;
    for (let index = bodyStart; index < source.length; index += 1) {
      if (source[index] === "{") depth += 1;
      else if (source[index] === "}" && --depth === 0) {
        end = index + 1;
        break;
      }
    }
    if (end > bodyStart) bodies.set(match[1], source.slice(bodyStart, end));
  }
  return bodies;
}

function dependencyClosure(rootFiles, candidates, rootSymbols = []) {
  const sourceByFile = new Map();
  const fileBySymbol = new Map();
  const fileByInitializer = new Map();
  const bodiesByFile = new Map();
  const closureTargetByObject = new Map();
  for (const file of candidates) {
    const source = readFileSync(file, "utf8");
    sourceByFile.set(file, source);
    bodiesByFile.set(file, cDefinitionBodies(source));
    for (const match of source.matchAll(/static\s+const\s+lean_(?:closure|object)_object\s+([A-Za-z0-9_x]+)_value[\s\S]*?\.m_fun\s*=\s*\(void\*\)([A-Za-z0-9_x]+)/g)) {
      closureTargetByObject.set(match[1], { file, symbol: match[2] });
    }
    for (const symbol of cDefinitions(source)) {
      if (isInitializer(symbol)) {
        if (!fileByInitializer.has(symbol)) fileByInitializer.set(symbol, file);
      } else if (!fileBySymbol.has(symbol)) {
        fileBySymbol.set(symbol, file);
      }
    }
  }
  const included = new Set(rootFiles);
  const queued = new Set();
  const queue = [];
  const enqueue = (source, symbol, followInitializers = true) => {
    const key = `${source}\0${symbol}`;
    if (symbol && !queued.has(key)) {
      queued.add(key);
      queue.push({ source, symbol, followInitializers });
    }
  };
  for (const { source, symbol } of rootSymbols) {
    // Keep the target module initializer itself, but do not recursively pull
    // every imported module initializer into a computation bundle. Imported
    // module initializers are optional for the generated computation function;
    // unresolved ones are supplied as no-op stubs below.
    enqueue(source, symbol, false);
  }
  while (queue.length > 0) {
    const { source: file, symbol: rootSymbol, followInitializers } = queue.shift();
    const source = bodiesByFile.get(file)?.get(rootSymbol) ?? sourceByFile.get(file) ?? readFileSync(file, "utf8");
    for (const symbol of cSymbols(source)) {
      const closureTarget = closureTargetByObject.get(symbol);
      if (closureTarget) {
        if (!included.has(closureTarget.file)) included.add(closureTarget.file);
        enqueue(closureTarget.file, closureTarget.symbol, false);
        continue;
      }
      const dependency = isInitializer(symbol)
        ? fileByInitializer.get(symbol)
        : fileBySymbol.get(symbol);
      // The imported C files are candidates, not dependencies yet. Follow every
      // reference from an included file so an indirect module dependency is not
      // lost (for example, root -> A -> B). Symbols supplied by the Lean archives
      // simply have no candidate and are left for the final link step.
      if (dependency && bodiesByFile.get(dependency)?.has(symbol) &&
          (!isInitializer(symbol) || followInitializers)) {
        if (!included.has(dependency)) included.add(dependency);
        // Initialization is a module-level dependency and must be followed
        // transitively. Ordinary function calls remain limited to their own
        // reachable function bodies.
        enqueue(dependency, symbol, isInitializer(symbol));
      }
    }
  }
  return [...included];
}

function packagePrefix(setup) {
  return setup.package ? `${manglePart(setup.package)}_` : "";
}

function moduleInitSymbol(moduleName, setup) {
  return `initialize_${packagePrefix(setup)}${mangleName(moduleName, "")}`;
}

function wrapperSymbol(wrapper, setup) {
  return `lp_${packagePrefix(setup)}${mangleName(wrapper, "")}`;
}

function run(command, args, cwd = root) {
  execFileSync(command, args, { cwd, stdio: "inherit" });
}

async function smokeTest(modulePath) {
  const factory = (await import(`${pathToFileURL(modulePath).href}?t=${Date.now()}`)).default;
  const instance = await factory();
  instance._proof_script_init();
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const entry = encoder.encode("__proof_script_missing_entry__");
  const input = encoder.encode("{}");
  const entryPtr = instance._proof_script_alloc(entry.length);
  const inputPtr = instance._proof_script_alloc(input.length);
  const outputPtr = instance._proof_script_alloc(256);
  instance.HEAPU8.set(entry, entryPtr);
  instance.HEAPU8.set(input, inputPtr);
  const length = instance._proof_script_invoke(
    entryPtr, entry.length, inputPtr, input.length, outputPtr, 256,
  );
  const result = JSON.parse(decoder.decode(instance.HEAPU8.slice(outputPtr, outputPtr + length)));
  instance._proof_script_free(entryPtr);
  instance._proof_script_free(inputPtr);
  instance._proof_script_free(outputPtr);
  if (result?.error?.code !== "unknown-entry") {
    throw new Error(`bundle smoke test failed for ${modulePath}`);
  }
}

const pending = filesBelow(pendingRoot, ".json").map(path => ({
  path,
  value: JSON.parse(readFileSync(path, "utf8")),
}));
if (pending.length === 0) {
  throw new Error(`no pending computation manifests under ${relative(root, pendingRoot)}`);
}

const groups = Map.groupBy(pending, item => item.value.bundleId);
mkdirSync(bundlesRoot, { recursive: true });

for (const [bundleId, items] of groups) {
  const moduleName = items[0].value.module;
  if (items.some(item => item.value.module !== moduleName)) {
    throw new Error(`bundle ${bundleId} spans multiple modules; project bundles are not implemented yet`);
  }
  const paths = modulePaths(moduleName);
  if (!existsSync(paths.c) || !existsSync(paths.setup)) {
    throw new Error(`missing C IR for ${moduleName}; run lake build first`);
  }
  const setup = JSON.parse(readFileSync(paths.setup, "utf8"));
  const safeBundle = bundleId.replaceAll(/[^A-Za-z0-9._-]/g, "_");
  const out = join(bundlesRoot, safeBundle);
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });

  const entryRows = items.map(({ value }) => ({
    id: value.entry,
    wrapper: value.wrapper,
    symbol: wrapperSymbol(value.wrapper, setup),
  })).sort((left, right) => left.id.localeCompare(right.id));
  const moduleSource = readFileSync(paths.c, "utf8");
  for (const entry of entryRows) {
    if (!moduleSource.includes(entry.symbol)) {
      throw new Error(`C IR for ${moduleName} does not contain wrapper ${entry.wrapper}; run lake build ${moduleName}`);
    }
  }
  const dispatcher = `
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <lean/lean.h>

#ifdef __cplusplus
extern "C" {
#endif
extern void lean_initialize_runtime_module(void);
extern lean_obj_res initialize_Lean_Data_Json(uint8_t builtin);
extern lean_obj_res ${moduleInitSymbol(moduleName, setup)}(uint8_t builtin);
${entryRows.map(entry => `extern lean_obj_res ${entry.symbol}(lean_obj_arg input);`).join("\n")}

void proof_script_init(void) {
  lean_initialize_runtime_module();
  lean_object *result = initialize_Lean_Data_Json(0);
  lean_dec(result);
  result = ${moduleInitSymbol(moduleName, setup)}(0);
  lean_dec(result);
}
uint32_t proof_script_alloc(uint32_t size) { return (uint32_t)(uintptr_t)malloc(size); }
void proof_script_free(uint32_t ptr) { free((void *)(uintptr_t)ptr); }

static lean_obj_res dispatch(char const *entry, lean_obj_arg input) {
${entryRows.map(entry => `  if (strcmp(entry, ${JSON.stringify(entry.id)}) == 0) return ${entry.symbol}(input);`).join("\n")}
  lean_dec(input);
  return lean_mk_string("{\\"ok\\":false,\\"error\\":{\\"code\\":\\"unknown-entry\\",\\"message\\":\\"unknown computation entry\\"}}");
}

uint32_t proof_script_invoke(uint32_t entry_ptr, uint32_t entry_len,
    uint32_t input_ptr, uint32_t input_len, uint32_t output_ptr, uint32_t output_capacity) {
  char *entry = (char *)malloc(entry_len + 1);
  memcpy(entry, (void *)(uintptr_t)entry_ptr, entry_len);
  entry[entry_len] = 0;
  lean_object *input = lean_mk_string_from_bytes((char const *)(uintptr_t)input_ptr, input_len);
  lean_object *result = dispatch(entry, input);
  free(entry);
  char const *text = lean_string_cstr(result);
  uint32_t length = (uint32_t)strlen(text);
  if (length <= output_capacity) memcpy((void *)(uintptr_t)output_ptr, text, length);
  lean_dec(result);
  return length;
}
#ifdef __cplusplus
}
#endif
`;
  const dispatcherPath = join(out, "dispatcher.c");

  const supportC = importCFile(setup, "ProofScript.Page.Component.Computation");
  const imported = importedCFiles(setup);
  const candidates = [...new Set([supportC, paths.c, ...imported])];
  const rootSymbols = [
    ...entryRows.map(entry => ({ source: paths.c, symbol: entry.symbol })),
    ...[...cDefinitions(readFileSync(supportC, "utf8"))]
      .filter(symbol => symbol.endsWith("ProofScript_Computation_invokeJson"))
      .map(symbol => ({ source: supportC, symbol })),
    { source: paths.c, symbol: moduleInitSymbol(moduleName, setup) },
    ...[...cSymbols(readFileSync(supportC, "utf8"))]
      .filter(symbol => isInitializer(symbol))
      .map(symbol => ({ source: supportC, symbol })),
  ];
  const cFiles = dependencyClosure(
    [supportC, paths.c],
    candidates,
    rootSymbols,
  );
  // Selected C-IR files and runtime archives provide real initializers. Other
  // referenced module initializers get stubs because their registration is not
  // needed by the computation entry itself.
  const includedInitializers = new Set(cFiles.flatMap(file => {
    const source = readFileSync(file, "utf8");
    return [...cInitializerDefinitions(source), ...[...cDefinitions(source)]
      .filter(symbol => isInitializer(symbol))];
  }));
  const stubbedInitializers = new Set();
  for (const file of cFiles) {
    const source = readFileSync(file, "utf8");
    for (const symbol of cSymbols(source)) {
      if (isInitializer(symbol) && !includedInitializers.has(symbol) &&
          !archiveInitializers.has(symbol)) {
        stubbedInitializers.add(symbol);
      }
    }
  }
  const initializerStubs = [...stubbedInitializers].map(symbol =>
    `LEAN_EXPORT lean_object* ${symbol}(uint8_t builtin) { return lean_io_result_mk_ok(lean_box(0)); }`)
    .join("\n");
  writeFileSync(dispatcherPath,
    `#include <stdint.h>\n#include <lean/lean.h>\n#ifdef __cplusplus\nextern "C" {\n#endif\n${initializerStubs}\n#ifdef __cplusplus\n}\n#endif\n${dispatcher}`);
  // Lean's Emscripten archives require LTO to resolve generated runtime helpers.
  // The function-level closure above keeps this bounded for imported libraries.
  const commonFlags = ["-O3", "-DNDEBUG", "-pthread", "-fwasm-exceptions", "-flto",
    "-ffunction-sections", "-fdata-sections",
    `-I${join(leanWasmPrefix, "include")}`, `-I${join(leanWasmPrefix, "src")}`];
  const objects = [];
  for (const [index, cFile] of cFiles.entries()) {
    const object = join(out, `module-${index}.o`);
    run("emcc", ["-c", cFile, ...commonFlags, "-o", object]);
    objects.push(object);
  }
  const modulePath = join(out, "bundle.mjs");
  run("em++", [
    ...objects,
    dispatcherPath,
    ...commonFlags,
    "-Wno-pthreads-mem-growth",
    "-Wl,--gc-sections",
    `-Wl,--undefined=${moduleInitSymbol(moduleName, setup)}`,
    ...entryRows.map(entry => `-Wl,--undefined=${entry.symbol}`),
    "-s", "WASM=1",
    "-s", "MODULARIZE=1",
    "-s", "EXPORT_ES6=1",
    "-s", "ALLOW_MEMORY_GROWTH=1",
    "-s", 'EXPORTED_FUNCTIONS=["_proof_script_init","_proof_script_alloc","_proof_script_free","_proof_script_invoke","_malloc"]',
    "-s", 'EXPORTED_RUNTIME_METHODS=["HEAPU8"]',
    "-Wl,--start-group",
    ...archiveLibraries,
    "-Wl,--end-group",
    "-o", modulePath,
  ]);

  const wasmPath = join(out, "bundle.wasm");
  await smokeTest(modulePath);
  const wasm = readFileSync(wasmPath);
  const manifest = {
    schemaVersion: "0.0.0",
    abi: "proofscript-json-v1",
    bundleId,
    module: moduleName,
    entries: entryRows.map(({ id, wrapper }) => ({ id, wrapper })),
    linking: {
      mode: "module-local",
      cModules: cFiles.map(path => relative(root, path)),
    },
    smokeTest: { status: "passed", case: "unknown-entry" },
    artifacts: {
      module: relative(root, modulePath),
      wasm: relative(root, wasmPath),
      wasmBytes: wasm.length,
      wasmSha256: createHash("sha256").update(wasm).digest("hex"),
    },
  };
  writeFileSync(join(out, "bundle.json"), `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`built ${bundleId}: ${entryRows.length} entries, ${wasm.length} bytes`);
}
