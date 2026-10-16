import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const profile = mkdtempSync(join(tmpdir(), 'ps4html-diagram-'));
const root = resolve('.PS4HTML/build');
const server = createServer(async (request, response) => {
  const { readFile } = await import('node:fs/promises');
  const path = resolve(root, '.' + new URL(request.url, 'http://localhost').pathname);
  if (!path.startsWith(root + '/')) { response.writeHead(404).end(); return; }
  try {
    const type = path.endsWith('.css') ? 'text/css' : path.endsWith('.js') ? 'text/javascript' : 'text/html';
    response.setHeader('Content-Type', type);
    response.setHeader('Content-Security-Policy', "default-src 'self' https://cdn.jsdelivr.net; script-src 'self' https://cdn.jsdelivr.net 'wasm-unsafe-eval'; style-src 'self' https://cdn.jsdelivr.net 'unsafe-inline'; img-src 'self' data:");
    response.end(await readFile(path));
  } catch { response.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = spawn(chrome, ['--headless', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage',
  '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank'], { stdio: 'ignore' });

async function waitForDebugger() {
  const { readFileSync } = await import('node:fs');
  for (let i = 0; i < 100; i++) {
    try {
      const [port] = readFileSync(join(profile, 'DevToolsActivePort'), 'utf8').split('\n');
      const tabs = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
      return tabs.find(tab => tab.type === 'page').webSocketDebuggerUrl;
    } catch { await new Promise(r => setTimeout(r, 100)); }
  }
  throw new Error('Chrome debugger did not start');
}

try {
  const socket = new WebSocket(await waitForDebugger());
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  let serial = 0;
  const pending = new Map();
  socket.onmessage = ({ data }) => {
    const message = JSON.parse(data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) reject(new Error(message.error.message));
      else resolve(message.result);
    }
  };
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++serial;
    pending.set(id, { resolve, reject });
    socket.send(JSON.stringify({ id, method, params }));
  });
  const evaluate = async expression => {
    const response = await send('Runtime.evaluate', { expression, returnByValue: true });
    if (response.exceptionDetails) throw new Error(response.exceptionDetails.text);
    return response.result.value;
  };
  const page = `http://127.0.0.1:${server.address().port}/ProofScript/Test/Test/LatexComponentsTest.html`;
  await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', {width: 1440, height: 900, deviceScaleFactor: 1, mobile: false});
  await send('Page.navigate', { url: page });
  let result;
  for (let i = 0; i < 100; i++) {
    result = await evaluate(`(() => {
      const input = document.querySelector('.theorem-proof:not([hidden]) .diagram-zoom');
      if (!input) return null;
      input.scrollIntoView({block: 'center'});
      const box = input.getBoundingClientRect();
      const x = box.left + box.width / 2, y = box.top + box.height / 2;
      const hit = document.elementFromPoint(x, y);
      return {x, y, hit: hit?.outerHTML.slice(0, 250), value: input.value,
        rect: [box.left, box.top, box.width, box.height],
        blockHeight: input.closest('.proof-strategy.diagram').getBoundingClientRect().height,
        svgHeight: input.closest('.diagram-figure').querySelector('svg')?.getBoundingClientRect().height};
    })()`);
    if (result?.hit && await evaluate(`document.readyState === 'complete'`)) break;
    await new Promise(r => setTimeout(r, 100));
  }
  assert(result, 'input missing');
  assert.match(result.hit, /class="diagram-zoom"/);
  await send('Input.dispatchMouseEvent', {type:'mousePressed', x: result.x + 35, y: result.y, button:'left', clickCount:1});
  await send('Input.dispatchMouseEvent', {type:'mouseReleased', x: result.x + 35, y: result.y, button:'left', clickCount:1});
  await new Promise(resolve => setTimeout(resolve, 300));
  const after = await evaluate(`(() => {const input = document.querySelector('.theorem-proof:not([hidden]) .diagram-zoom'); const svg = input.closest('.diagram-figure').querySelector('svg'); return {value: input.value, text: input.nextElementSibling.textContent, svgHeight: svg.getBoundingClientRect().height, blockHeight: input.closest('.proof-strategy.diagram').getBoundingClientRect().height}})()`);
  assert.notEqual(after.value, '100');
  assert.equal(after.text, `${after.value}%`);
  assert(after.svgHeight > result.svgHeight, 'SVG should grow vertically');
  assert(after.blockHeight > result.blockHeight, 'blue diagram block should grow with SVG');
  const tagColors = await evaluate(`(() => {const block = document.querySelector('.theorem-proof:not([hidden]) .proof-step:not(.introducer)'); return {actual: getComputedStyle(block.querySelector('.proof-step-label')).color, expected: getComputedStyle(document.body).color}})()`);
  assert.equal(tagColors.actual, tagColors.expected, 'ordinary script tags should use the default text color');
  socket.close();
} finally {
  browser.kill();
  await new Promise(resolve => browser.once('exit', resolve));
  rmSync(profile, {recursive: true, force: true, maxRetries: 5, retryDelay: 100});
  await new Promise(resolve => server.close(resolve));
}
