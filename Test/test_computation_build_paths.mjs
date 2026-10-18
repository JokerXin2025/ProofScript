import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { computationBuildPaths } from "../scripts/computation-build-paths.mjs";

test("computations use isolated owner/import paths and cached support paths", t => {
  const root = mkdtempSync(join(tmpdir(), "proofscript-build-paths-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const page = join(root, ".lake", "ps4html", "Demo", "Demo");
  const own = join(page, "Demo", "ir", "Demo", "Page.c");
  const upstream = join(page, "Upstream", "ir", "Upstream.c");
  const supportRoot = join(root, ".lake", "packages", "ProofScript", ".lake", "build");
  const support = join(supportRoot, "ir", "ProofScript", "Page", "Component", "Computation.c");
  for (const path of [own, upstream, support]) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, "/* C IR */");
  }
  const session = join(root, "session.json");
  writeFileSync(session, JSON.stringify({ schemaVersion: 1, modules: [
    { name: "Demo.Page", c: own, setup: own.replace(/\.c$/, ".setup.json") },
    { name: "Upstream", c: upstream, setup: upstream.replace(/\.c$/, ".setup.json") },
  ] }));
  const paths = computationBuildPaths(root, root, session);
  const setup = { importArts: {
    Upstream: [join(page, "Upstream", "lib", "lean", "Upstream.olean")],
    "ProofScript.Page.Component.Computation": [join(supportRoot, "lib", "lean", "ProofScript", "Page", "Component", "Computation.olean")],
  } };
  assert.equal(paths.modulePaths("Demo.Page").c, own);
  assert.equal(paths.importCFile(setup, "Upstream"), upstream);
  assert.equal(paths.importCFile(setup, "ProofScript.Page.Component.Computation"), support);
  assert.deepEqual(paths.importedCFiles(setup), [upstream, support]);
  assert.throws(() => paths.modulePaths("Missing"), /missing computation module/);
});

test("explicit standalone builds retain their ordinary Lake paths", () => {
  const root = join(tmpdir(), "standalone-proofscript");
  const paths = computationBuildPaths(root, root);
  assert.equal(paths.modulePaths("Demo.Page").c, join(root, ".lake", "build", "ir", "Demo", "Page.c"));
});
