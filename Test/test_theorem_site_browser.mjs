// Build examples/site first. This checks the exported facts against the real generated DOM.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync, readFileSync, realpathSync, rmSync} from 'node:fs';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {dirname, extname, join, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const project = resolve(process.argv[2] || fileURLToPath(new URL('../examples/site', import.meta.url)));
const site = realpathSync(join(project, '.PS4HTML/build/PS4HTMLDemo/PS4HTMLDemo'));
const exported = realpathSync(join(project, '.PS4HTML/inputs/PS4HTMLDemo/PS4HTMLDemo/.ProofScript'));
assert.equal(dirname(site), dirname(exported), 'HTML and facts must belong to the same atomic release');
const json = path => JSON.parse(readFileSync(path, 'utf8'));
const canonical = value => JSON.stringify(value, (_key, child) => child && !Array.isArray(child) && typeof child === 'object'
  ? Object.fromEntries(Object.keys(child).sort().map(key => [key, child[key]])) : child);
const hash = value => createHash('sha256').update(canonical(value)).digest('hex');
const identity = (projectId, declaration) => `theorem-${hash({projectId, declaration})}`;
const index = json(join(exported, 'info/index.json'));
assert.equal(index.schemaVersion, '5.0.0');
assert.equal(index.complete, true);
const artifactPath = path => join(exported, path.replace(/^\.ProofScript\//, ''));
for (const entry of index.files) {
  const path = join(exported, entry.path);
  assert.equal(entry.sha256 ? createHash('sha256').update(readFileSync(path)).digest('hex') : hash(json(path)),
    entry.sha256 || entry.digest, `Bundle digest: ${entry.path}`);
}
const proofs = index.artifacts.filter(artifact => artifact.kind === 'proof' && Array.isArray(artifact.declaration));
const proofsByPath = new Map(proofs.map(proof => [proof.path, proof]));
const snapshotsById = new Map(index.snapshots.map(snapshot => [snapshot.id, json(join(exported, snapshot.path)).payload]));
const graph = new Map();
for (const proof of proofs) {
  assert.equal(proof.projectId, 'PS4HTMLDemo');
  assert.ok(Array.isArray(proof.proofDependencies));
  const id = identity(proof.projectId, proof.declaration);
  assert.ok(!graph.has(id));
  graph.set(id, {incoming: proof.proofDependencies.map(name => identity(proof.projectId, name)), outgoing: []});
}
for (const [source, edges] of [...graph]) for (const target of edges.incoming) {
  if (!graph.has(target)) graph.set(target, {incoming: [], outgoing: []});
  graph.get(target).outgoing.push(source);
}
const facts = name => proofs.find(proof => proof.declaration.join('.') === name);
assert.deepEqual(facts('PS4HTMLDemo.Library.identityLemma').proofDependencies, [['PS4HTMLDemo', 'Library', 'ordinaryIdentity']]);
assert.deepEqual(facts('PS4HTMLDemo.Dependencies.importedIdentity').proofDependencies, [['PS4HTMLDemo', 'Library', 'identityLemma']]);
assert.deepEqual(facts('PS4HTMLDemo.Dependencies.limitUniqueness').proofDependencies, [['PS4HTMLDemo', 'Dependencies', 'importedIdentity']]);
const pages = index.artifacts.filter(artifact => artifact.kind === 'page').map(artifact => {
  const page = json(artifactPath(artifact.path));
  return {url: `${artifact.module.replaceAll('.', '/')}.html`,
    ids: page.components.flatMap(component => {
      const snapshot = snapshotsById.get(component.snapshotId);
      assert.ok(snapshot, 'Every page component must name its own snapshot');
      assert.deepEqual(snapshot.query.module, artifact.owner);
      const value = (component.data.theorem || component.data.lemma)?.value;
      if (!value) return [];
      const proof = proofsByPath.get(value.proof);
      assert.ok(proof, `Missing theorem facts for ${value.proof}`);
      assert.equal(component.snapshotId, proof.snapshotId, 'Theorem component uses its proof snapshot');
      return [identity(proof.projectId, proof.declaration)];
    })};
});
const profile = mkdtempSync(join(tmpdir(), 'ps4html-theorem-site-'));
const failures = [];
const types = {'.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.wasm': 'application/wasm', '.json': 'application/json'};
const server = createServer((request, response) => {
  try {
    const path = resolve(site, `.${decodeURIComponent(new URL(request.url, 'http://localhost').pathname)}`);
    assert.ok(path.startsWith(site + sep), 'Resource outside site');
    response.setHeader('Content-Type', types[extname(path)] || 'application/octet-stream');
    response.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    response.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    response.end(readFileSync(path));
  } catch {
    if (request.url !== '/favicon.ico') failures.push(request.url);
    response.writeHead(404).end();
  }
});
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
let browser, socket;
try {
  await new Promise((yes, no) => {server.once('error', no); server.listen(0, '127.0.0.1', yes);});
  browser = spawn(process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    ['--headless', '--no-sandbox', '--disable-gpu', '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank'], {stdio: ['ignore', 'ignore', 'pipe']});
  let startupLog = '';
  browser.stderr.on('data', chunk => {startupLog = (startupLog + chunk).slice(-4000);});
  browser.on('error', error => {startupLog += String(error);});
  let debuggerUrl;
  for (let i = 0; i < 300; i++) {
    if (browser.exitCode !== null) break;
    try {
      const port = readFileSync(join(profile, 'DevToolsActivePort'), 'utf8').split('\n')[0];
      debuggerUrl = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(tab => tab.type === 'page').webSocketDebuggerUrl;
      break;
    } catch {await sleep(100);}
  }
  assert.ok(debuggerUrl, `Chrome debugger did not start: ${startupLog}`);
  socket = new WebSocket(debuggerUrl);
  await new Promise((yes, no) => {socket.onopen = yes; socket.onerror = no;});
  let serial = 0;
  const pending = new Map(), exceptions = [];
  socket.onmessage = ({data}) => {
    const message = JSON.parse(data);
    if (message.method === 'Runtime.exceptionThrown') exceptions.push(message.params.exceptionDetails);
    pending.get(message.id)?.(message);
    pending.delete(message.id);
  };
  const send = (method, params = {}) => new Promise((yes, no) => {
    const id = ++serial;
    pending.set(id, message => message.error ? no(new Error(message.error.message)) : yes(message.result));
    socket.send(JSON.stringify({id, method, params}));
  });
  const evaluate = async expression => {
    const result = await send('Runtime.evaluate', {expression, returnByValue: true, awaitPromise: true});
    assert.ok(!result.exceptionDetails, JSON.stringify(result.exceptionDetails));
    return result.result.value;
  };
  const settle = () => evaluate('new Promise(done => requestAnimationFrame(() => requestAnimationFrame(() => done(true))))');
  let lastPoint;
  const move = async point => {lastPoint = point; await send('Input.dispatchMouseEvent', {type: 'mouseMoved', ...point}); await settle();};
  const body = id => `.theorem-proof[data-theorem-id="${id}"]:not([hidden])`;
  const enter = async id => {
    await evaluate(`document.querySelector(${JSON.stringify(body(id))}).scrollIntoView({block: 'start', behavior: 'instant'})`);
    await settle();
    await move(await evaluate(`(() => {const r = document.querySelector(${JSON.stringify(body(id))}).getBoundingClientRect(); return {x: r.left + 80, y: Math.max(0, r.top) + 20};})()`));
  };
  const current = () => evaluate('document.querySelector(".theorem-dependency-navigation")?.dataset.theoremId || null');
  const check = async id => {
    assert.equal(await current(), id, await evaluate(`(() => {
      const section = document.querySelector(${JSON.stringify(body(id))});
      const r = section.getBoundingClientRect(), {x, y} = ${JSON.stringify(lastPoint)};
      const hit = document.elementFromPoint(x, y);
      return JSON.stringify({page: location.pathname, expected: section.id, rect: r.toJSON(),
        pointer: {x, y},
        hit: hit?.outerHTML.slice(0, 300), hitTheorem: hit?.closest('[data-theorem-id]')?.dataset.theoremId});
    })()`));
    assert.equal(await evaluate('document.querySelectorAll(".theorem-dependency-current").length'), 1);
    const actual = await evaluate(`(() => {const slot = document.querySelector('[data-theorem-navigation-content]');
      const nodes = level => [...slot.querySelectorAll('.' + level + ' li')].map(node => node.dataset.theoremNode).sort();
      return {incoming: nodes('incoming'), outgoing: nodes('outgoing')};})()`);
    const expected = graph.get(id);
    assert.deepEqual(actual, {incoming: [...expected.incoming].sort(), outgoing: [...expected.outgoing].sort()});
  };
  await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride', {width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false});
  const base = `http://127.0.0.1:${server.address().port}/`;
  let hovered = 0;
  for (const page of pages) {
    await move({x: -10, y: 0});
    await send('Page.navigate', {url: base + page.url});
    for (let i = 0; i < 400; i++) {
      if (await evaluate('document.readyState === "complete"')) break;
      await sleep(50);
    }
    assert.equal(await evaluate('document.readyState'), 'complete', page.url);
    await settle();
    assert.equal(await current(), null, 'A new page never selects a theorem by its scroll/hash');
    assert.equal(await evaluate('document.querySelectorAll(".theorem-dependency-current").length'), 0);
    assert.equal(await evaluate('document.querySelectorAll("template[data-theorem-id]").length'), page.ids.length);
    for (const id of page.ids) {await enter(id); await check(id); hovered++;}
  }
  // Check the ordinary theorem's unlinked node, and the reverse edge from another page.
  const lemma = identity('PS4HTMLDemo', ['PS4HTMLDemo', 'Library', 'identityLemma']);
  await send('Page.navigate', {url: base + 'PS4HTMLDemo/Library.html'});
  for (let i = 0; i < 200; i++) {if (await evaluate('document.readyState === "complete"')) break; await sleep(50);}
  await enter(lemma);
  await check(lemma);
  assert.equal(await evaluate('document.querySelector(".incoming .is-unlinked").title'), 'PS4HTMLDemo.Library.ordinaryIdentity');
  assert.equal(await evaluate('document.querySelector(".outgoing a").getAttribute("href")'), 'Dependencies.html#theorem-PS4HTMLDemo.Dependencies.importedIdentity');
  await evaluate('window.retained = document.querySelector(".theorem-dependency-current"); document.querySelector("[data-language=en]").click()');
  await settle();
  await check(lemma);
  assert.equal(await evaluate('window.retained === document.querySelector(".theorem-dependency-current")'), true);
  const target = await evaluate(`(() => {const r = document.querySelector('.outgoing a').getBoundingClientRect(); return {x: r.left + 30, y: r.top + 12};})()`);
  await move(target);
  await sleep(200);
  await check(lemma);
  await send('Input.dispatchMouseEvent', {type: 'mousePressed', ...target, button: 'left', clickCount: 1});
  await send('Input.dispatchMouseEvent', {type: 'mouseReleased', ...target, button: 'left', clickCount: 1});
  for (let i = 0; i < 200; i++) {
    if (await evaluate('location.pathname.endsWith("/Dependencies.html") && document.readyState === "complete"')) break;
    await sleep(50);
  }
  assert.equal(await evaluate('decodeURIComponent(location.hash)'), '#theorem-PS4HTMLDemo.Dependencies.importedIdentity');
  assert.equal(await current(), null);
  assert.equal(await evaluate('document.documentElement.dataset.language'), 'en');
  await enter(identity('PS4HTMLDemo', ['PS4HTMLDemo', 'Dependencies', 'importedIdentity']));
  await check(identity('PS4HTMLDemo', ['PS4HTMLDemo', 'Dependencies', 'importedIdentity']));
  await move({x: 1400, y: 100});
  await sleep(200);
  await settle();
  assert.equal(await current(), null);
  assert.deepEqual(exceptions, [], 'Generated pages must not throw JavaScript errors');
  assert.deepEqual(failures, [], 'All local assets must load');
  console.log(`Generated theorem site passed: ${proofs.length} proofs, ${pages.length} pages, ${hovered} theorem regions; exact direct/reverse edges, cross-page links, lemma translations and one active graph.`);
} finally {
  socket?.close();
  if (browser && browser.exitCode === null) {const exited = new Promise(done => browser.once('exit', done)); browser.kill(); await exited;}
  if (server.listening) await new Promise(done => server.close(done));
  rmSync(profile, {recursive: true, force: true});
}
