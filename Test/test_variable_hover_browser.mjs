// Run with Node 22+ and Chrome (CHROME may override the executable).
// Requires access to the same KaTeX CDN used by the page template.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const assets = new URL('../tools/ps4html/PS4HTML/assets/', import.meta.url);
const profile = mkdtempSync(join(tmpdir(), 'ps4html-hover-'));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const server = createServer((request, response) => {
  if (request.url === '/lean2tex.css' || request.url === '/lean2tex.js') {
    const css = request.url.endsWith('.css');
    response.setHeader('Content-Type', css ? 'text/css' : 'text/javascript');
    response.end(readFileSync(new URL(`${css ? 'css' : 'js'}${request.url}`, assets)));
  } else {
    response.setHeader('Content-Type', 'text/html');
    response.end(`<!doctype html><meta charset="utf-8">
      <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
      <link rel="stylesheet" href="/lean2tex.css">
      <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
      <script defer src="/lean2tex.js"></script>
      <style>body { padding: 40px; font-size: 30px; } .theorem-proof { margin: 30px; }</style>
      <div id="proof" class="theorem-proof"></div>
      <div id="other" class="theorem-proof"></div>`);
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = spawn(process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ['--headless', '--no-sandbox', '--disable-gpu', '--remote-debugging-port=0',
    `--user-data-dir=${profile}`, 'about:blank'], { stdio: 'ignore' });
let socket;
try {
  let debuggerUrl;
  for (let i = 0; i < 100; i++) {
    try {
      const port = readFileSync(join(profile, 'DevToolsActivePort'), 'utf8').split('\n')[0];
      const tabs = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
      debuggerUrl = tabs.find(tab => tab.type === 'page').webSocketDebuggerUrl;
      break;
    } catch { await sleep(100); }
  }
  assert.ok(debuggerUrl, 'Chrome debugger did not start');
  socket = new WebSocket(debuggerUrl);
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  let serial = 0;
  const pending = new Map();
  socket.onmessage = ({ data }) => {
    const message = JSON.parse(data);
    const callback = pending.get(message.id);
    if (callback) { pending.delete(message.id); callback(message); }
  };
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++serial;
    pending.set(id, message => message.error ? reject(new Error(message.error.message)) : resolve(message.result));
    socket.send(JSON.stringify({ id, method, params }));
  });
  const evaluate = async expression => {
    const result = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
    assert.ok(!result.exceptionDetails, JSON.stringify(result.exceptionDetails));
    return result.result.value;
  };
  await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: `http://127.0.0.1:${server.address().port}/` });
  for (let i = 0; i < 200; i++) {
    if (await evaluate('document.readyState === "complete" && typeof katex !== "undefined"')) break;
    await sleep(100);
  }
  const variable = (name, ref = 'x') => `\\htmlData{l2t-ref=${ref}}{${name}}`;
  const x = variable('x');
  const formulas = [x, `\\frac{${x}}{${x}}`, `a_{${x}}`, `a_{${x}}^{${x}}`,
    variable('x_0'), `\\frac{1}{\\frac{${x}}{${x}}}`, variable('y', 'y')];
  await evaluate(`(() => {
    for (const formula of ${JSON.stringify(formulas)}) {
      const span = document.createElement('span');
      span.style.marginRight = '20px';
      document.querySelector('#proof').append(span);
      katex.render(formula, span, {trust: true});
    }
    katex.render(${JSON.stringify(x)}, document.querySelector('#other'), {trust: true});
  })()`);
  await evaluate('document.fonts.ready.then(() => true)');
  // Target actual glyphs, including the digit in x_0, rather than wrapper boxes.
  const points = await evaluate(`Array.from(document.querySelectorAll('#proof .katex-html [data-l2t-ref]'))
    .flatMap(ref => Array.from(ref.querySelectorAll('span')).filter(n => !n.children.length && n.textContent.trim() && n.textContent !== '\u200b')
      .map(n => { const r = n.getBoundingClientRect(); return {x: r.x + r.width / 2, y: r.y + r.height / 2, ref: ref.dataset.l2tRef, text: n.textContent}; }))`);
  assert.ok(points.length >= 10, 'Expected fractions, nested fractions and scripts');
  for (const point of points) {
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 5, y: 5 });
    assert.equal(await evaluate('document.querySelectorAll("[data-l2t-active]").length'), 0);
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: point.x, y: point.y });
    const state = await evaluate(`(() => {
      const refs = Array.from(document.querySelectorAll('#proof [data-l2t-ref]'));
      return {correct: refs.every(n => n.hasAttribute('data-l2t-active') === (n.dataset.l2tRef === ${JSON.stringify(point.ref)})),
        other: document.querySelectorAll('#other [data-l2t-active]').length};
    })()`);
    assert.deepEqual(state, { correct: true, other: 0 }, `Hover failed: ${JSON.stringify(point)}`);
  }
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 5, y: 5 });
  assert.equal(await evaluate('document.querySelectorAll("[data-l2t-active]").length'), 0);
  console.log(`Variable hover passed: ${points.length} glyph positions, linked activation, scope isolation and pointer exit.`);
} finally {
  socket?.close();
  const exited = new Promise(resolve => browser.once('exit', resolve));
  if (browser.exitCode === null) { browser.kill(); await exited; }
  await new Promise(resolve => server.close(resolve));
  rmSync(profile, { recursive: true, force: true });
}
