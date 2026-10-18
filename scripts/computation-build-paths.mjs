import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

/** Resolve computation artifacts from the Lake workspace that compiled the page. */
export function computationBuildPaths(root, proofScriptRoot, manifestPath) {
  let modules;
  if (manifestPath) {
    const session = JSON.parse(readFileSync(manifestPath, "utf8"));
    if (session.schemaVersion !== 1 || !Array.isArray(session.modules)) {
      throw new Error(`invalid page build manifest: ${manifestPath}`);
    }
    modules = new Map(session.modules.map(entry => [entry.name, entry]));
  }

  function modulePaths(moduleName) {
    if (modules) {
      const entry = modules.get(moduleName);
      if (!entry?.c || !entry?.setup) {
        throw new Error(`missing computation module in page build manifest: ${moduleName}`);
      }
      return { c: resolve(root, entry.c), setup: resolve(root, entry.setup) };
    }
    const path = moduleName.replaceAll(".", "/");
    return {
      c: join(root, ".lake", "build", "ir", `${path}.c`),
      setup: join(root, ".lake", "build", "ir", `${path}.setup.json`),
    };
  }

  // setup.importArts already identifies the actual package build directory,
  // including isolated source packages and cached support packages.
  function importedCPath(artifacts) {
    const olean = artifacts.find(path => path.endsWith(".olean"));
    if (!olean) return undefined;
    const normalized = olean.replaceAll("\\", "/");
    const marker = "/lib/lean/";
    const absolute = resolve(root, normalized).replaceAll("\\", "/");
    const index = absolute.lastIndexOf(marker);
    if (index < 0) return undefined;
    return join(absolute.slice(0, index), "ir", `${absolute.slice(index + marker.length, -6)}.c`);
  }

  function importCFile(setup, moduleName) {
    const entry = modules?.get(moduleName);
    const candidate = entry?.c ? resolve(root, entry.c)
      : importedCPath(setup.importArts?.[moduleName] ?? []);
    if (candidate) {
      if (!existsSync(candidate)) throw new Error(`missing C IR for imported module ${moduleName}`);
      return candidate;
    }
    if (!modules) {
      const support = join(proofScriptRoot, ".lake", "build", "ir", `${moduleName.replaceAll(".", "/")}.c`);
      if (existsSync(support)) return support;
    }
    throw new Error(`missing imported module artifact: ${moduleName}`);
  }

  function importedCFiles(setup) {
    const files = [];
    for (const [name, artifacts] of Object.entries(setup.importArts ?? {})) {
      const entry = modules?.get(name);
      const candidate = entry?.c ? resolve(root, entry.c) : importedCPath(artifacts);
      if (candidate && existsSync(candidate)) files.push(candidate);
    }
    return [...new Set(files)];
  }

  return { modulePaths, importCFile, importedCFiles };
}
