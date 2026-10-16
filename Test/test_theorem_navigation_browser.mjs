// Node 22+ and Chrome; real pointer hit testing, without CDN or a Lean build.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const assets = new URL('../tools/ps4html/PS4HTML/assets/', import.meta.url);
const profile = mkdtempSync(join(tmpdir(), 'ps4html-theorem-navigation-'));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const scripts = {
  '/navigation.js': 'theorem-dependencies.js',
  '/language.js': 'language-switcher.js',
  '/flip.js': 'code-flip.js',
  '/indent.js': 'proof-indent.js',
  '/math.js': 'equation_size.js',
};
const server = createServer((request, response) => {
  if (scripts[request.url]) {
    response.setHeader('Content-Type', 'text/javascript');
    response.end(readFileSync(new URL(`js/${scripts[request.url]}`, assets)));
  } else {
    response.setHeader('Content-Type', 'text/html');
    response.end(`<!doctype html><meta charset="utf-8"><html data-default-language="zh">
      <script defer src="/language.js"></script><script defer src="/flip.js"></script>
      <script defer src="/indent.js"></script><script defer src="/math.js"></script>
      <script defer src="/navigation.js"></script>
      <style>
        body {margin: 0} [hidden] {display: none !important} h2, h3, pre {margin: 0}
        main {margin-left: 300px; width: 600px} #intro {height: 200px}
        @media (max-width: 1000px) {#intro {height: 360px}}
        .theorem-proof {position: relative; background: #ddd}
        .theorem-code-only {height: 220px} .theorem-proof h2 {height: 40px}
        .interlude {height: 80px} #tail {height: 1000px}
        .language-menu {position: fixed; right: 0; top: 0; z-index: 20}
        .other-sidebar {position: fixed; left: 20px; top: 20px}
        .theorem-dependency-navigation {position: fixed; left: 20px; top: 200px; width: 200px; z-index: 10; background: #eef}
        .theorem-dependency-navigation h3 {height: 40px}
        .theorem-dependency-navigation a {display: block; height: 30px}
        .theorem-dependency-current {height: 30px; color: blue}
        .theorem-dependency-panel {display: block}
        .proof-flip-inner {position: relative; transform-style: preserve-3d; transition: height .08s, transform .08s}
        .proof-flip-inner.flipped {transform: rotateY(180deg)}
        .proof-flip-front {height: 100px; backface-visibility: hidden}
        [data-language-panel=en] .proof-flip-front {height: 40px}
        .proof-flip-back {position: absolute; inset: 0; backface-visibility: hidden; transform: rotateY(180deg)}
        summary {height: 30px} .branch-content {height: 180px}
        .scroll-host {height: 160px; overflow: auto} .nested-space {height: 80px} .nested-tail {height: 300px}
      </style>
      <div class="language-menu"><button data-language="zh">中文</button><button data-language="en">EN</button></div>
      <aside class="other-sidebar">Other sidebar</aside>
      <main id="main-content">
        <div id="intro">General text</div>
        <section id="theorem-first-en" class="theorem-proof theorem-code-only" data-theorem-id="logical-first">
          <h2>Code-only theorem whose name ends in -en</h2><pre><code>Proof source</code></pre>
        </section>
        <div class="interlude">Explanation between theorems</div>
        ${['zh', 'en'].map(language => `
          <section id="theorem-lemma${language === 'en' ? '-en' : ''}" class="theorem-proof" data-theorem-id="logical-lemma" data-language-panel="${language}" ${language === 'en' ? 'hidden' : ''}>
            <h2>${language} lemma <button class="flip-btn">Source</button>
              <label class="proof-indent-control"><span class="proof-indent-value"></span><input class="proof-indent-slider" type="range" value="20"></label>
            </h2>
            <div class="proof-flip"><div class="proof-flip-inner">
              <div class="proof-flip-front">Proof body</div><div class="proof-flip-back"><pre>Lean source</pre></div>
            </div></div>
            <details class="proof-branch"><summary>Branch</summary><div class="branch-content">Expanded proof</div></details>
          </section>`).join('')}
        <div class="scroll-host"><div class="nested-space"></div>
          <section class="theorem-proof theorem-code-only" data-theorem-id="logical-first">Nested scroll theorem</section>
          <div class="nested-tail"></div>
        </div>
        <div id="tail"></div>
      </main>
      <section class="theorem-dependency-navigation" hidden>
        <h3>Dependencies</h3><div class="theorem-dependency-panel" data-theorem-navigation-content></div>
        <template class="theorem-dependency-template" data-theorem-id="logical-first">
          <div class="theorem-dependency-current">First</div><a href="#theorem-lemma">Lemma</a>
        </template>
        <template class="theorem-dependency-template" data-theorem-id="logical-lemma">
          <div class="theorem-dependency-current">Lemma</div><a href="#theorem-first-en">First</a>
        </template>
      </section></html>`);
  }
});
let socket, browser;
try {
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  browser = spawn(process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    ['--headless', '--no-sandbox', '--disable-gpu', '--remote-debugging-port=0',
      `--user-data-dir=${profile}`, 'about:blank'], { stdio: ['ignore', 'ignore', 'pipe'] });
  let startupLog = '';
  browser.stderr.on('data', chunk => {startupLog = (startupLog + chunk).slice(-4000);});
  browser.on('error', error => {startupLog += String(error);});
  let debuggerUrl, pageTargetId;
  for (let i = 0; i < 300; i++) {
    if (browser.exitCode !== null) break;
    try {
      const port = readFileSync(join(profile, 'DevToolsActivePort'), 'utf8').split('\n')[0];
      const tabs = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
      const tab = tabs.find(tab => tab.type === 'page');
      debuggerUrl = tab.webSocketDebuggerUrl;
      pageTargetId = tab.id;
      break;
    } catch { await sleep(100); }
  }
  assert.ok(debuggerUrl, `Chrome debugger did not start: ${startupLog}`);
  socket = new WebSocket(debuggerUrl);
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  let serial = 0;
  const pending = new Map();
  const exceptions = [];
  socket.onmessage = ({ data }) => {
    const message = JSON.parse(data);
    if (message.method === 'Runtime.exceptionThrown') exceptions.push(message.params.exceptionDetails);
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
  const settle = () => evaluate('new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve(true))))');
  const move = async (x, y) => {
    await send('Input.dispatchMouseEvent', {type: 'mouseMoved', x, y});
    await settle();
  };
  const click = async (x, y) => {
    await move(x, y);
    await send('Input.dispatchMouseEvent', {type: 'mousePressed', x, y, button: 'left', clickCount: 1});
    await send('Input.dispatchMouseEvent', {type: 'mouseReleased', x, y, button: 'left', clickCount: 1});
    await settle();
  };
  const waitClose = async () => { await sleep(200); await settle(); };
  const state = () => evaluate(`(() => {
    const nav = document.querySelector('.theorem-dependency-navigation');
    return {hidden: nav.hidden, active: nav.dataset.theoremId || null,
      current: document.querySelectorAll('.theorem-dependency-current').length,
      text: nav.querySelector('[data-theorem-navigation-content]').textContent.trim()};
  })()`);
  const active = async expected => {
    const actual = await state();
    assert.equal(actual.active, expected, JSON.stringify(actual));
    assert.equal(actual.hidden, expected === null);
    assert.equal(actual.current, expected === null ? 0 : 1);
  };
  const retain = () => evaluate('window.retainedCenter = document.querySelector(".theorem-dependency-current"); true');
  const retained = async () => assert.equal(await evaluate('window.retainedCenter === document.querySelector(".theorem-dependency-current")'), true);
  const scrollTop = async () => { await evaluate('window.scrollTo(0, 0)'); await settle(); };
  await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 1200, height: 800, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: `http://127.0.0.1:${server.address().port}/` });
  for (let i = 0; i < 100; i++) {
    if (await evaluate('document.readyState === "complete"')) break;
    await sleep(50);
  }
  await settle();
  assert.deepEqual(await state(), {hidden: true, active: null, current: 0, text: ''});
  assert.equal(await evaluate('document.querySelectorAll("template").length'), 2);
  // Scroll, hash, resize and language alone never establish a mouse selection.
  await evaluate('document.querySelector("#theorem-first-en").scrollIntoView()');
  await settle();
  await active(null);
  await evaluate('location.hash = "theorem-lemma"; window.dispatchEvent(new Event("resize")); document.querySelector("[data-language=en]").click()');
  await settle();
  await active(null);
  await evaluate('document.querySelector("[data-language=zh]").click(); history.replaceState(null, "", location.pathname)');
  await scrollTop();
  await move(400, 100);
  await active(null);
  await move(400, 210); // Code-only title.
  await active('logical-first');
  await retain();
  await move(400, 250); // Source child.
  await retained();
  await move(260, 250); // Gap; graph remains during the crossing deadline.
  await active('logical-first');
  await move(100, 280); // Dependency link.
  await waitClose();
  await active('logical-first');
  await retained();
  await click(100, 280); // Follow the link without changing the source selection.
  assert.equal(await evaluate('location.hash'), '#theorem-lemma');
  await active('logical-first');
  await move(1000, 400);
  await active('logical-first');
  await evaluate('window.layoutNoise = setInterval(() => document.dispatchEvent(new Event("ps4html:layoutchange")), 30)');
  await waitClose();
  await evaluate('clearInterval(window.layoutNoise)');
  await active(null);

  await scrollTop();
  await move(400, 250);
  await retain();
  await move(260, 250);
  await move(400, 250); // Cancel a pending close on reentry.
  await waitClose();
  await retained();
  await move(260, 250);
  await move(400, 550); // Another theorem switches immediately, even while pending.
  await active('logical-lemma');
  await retain();
  await evaluate('document.querySelector("[data-language=en]").click()');
  await settle();
  await active('logical-lemma');
  await retained();
  assert.equal(await evaluate('document.querySelector("#theorem-lemma-en").hidden'), false);
  await evaluate('document.querySelector("[data-language=zh]").click()');
  await settle();
  await move(400, 650); // In zh body, below the shorter English body.
  await active('logical-lemma');
  await evaluate('document.querySelector("[data-language=en]").click()');
  await waitClose();
  await active(null);
  await evaluate('document.querySelector("[data-language=zh]").click()');
  await settle();
  await active('logical-lemma');

  // Branch and source flip alter what is beneath a stationary pointer.
  await move(400, 730);
  await waitClose();
  await active(null);
  await evaluate('document.querySelector("#theorem-lemma details").open = true');
  await settle();
  await active('logical-lemma');
  await move(410, 740); // Expanded branch descendant is still part of the theorem.
  await active('logical-lemma');
  await evaluate('document.querySelector("#theorem-lemma details").open = false');
  await waitClose();
  await active(null);
  await evaluate('document.querySelector("#theorem-lemma .flip-btn").click()');
  await sleep(130);
  await settle();
  await active('logical-lemma');
  assert.equal(await evaluate('document.elementFromPoint(410, 740).closest(".proof-flip-back") !== null'), true);
  await evaluate('document.querySelector("#theorem-lemma .flip-btn").click()');
  await sleep(650);
  await settle();
  await active(null);

  await move(400, 300);
  await active('logical-first');
  await evaluate('window.scrollTo(0, 300)');
  await settle();
  await active('logical-lemma');
  await scrollTop();
  await active('logical-first');
  await evaluate('document.querySelector(".scroll-host").scrollIntoView()');
  await settle();
  await move(400, 120);
  await active('logical-first');
  const outerScroll = await evaluate('window.scrollY');
  await evaluate('document.querySelector(".scroll-host").scrollTop = 300');
  await waitClose();
  await active(null);
  assert.equal(await evaluate('window.scrollY'), outerScroll);
  await evaluate('document.querySelector(".scroll-host").scrollTop = 0');
  await settle();
  await active('logical-first');

  await scrollTop();
  await move(400, 300);
  // Compensate the tail to keep main's height unchanged: observe individual content too.
  await evaluate('document.querySelector("#intro").style.height = "360px"; document.querySelector("#tail").style.height = "840px"');
  await waitClose();
  await active(null);
  await evaluate('document.querySelector("#intro").style.height = ""; document.querySelector("#tail").style.height = ""');
  await settle();
  await active('logical-first');
  await send('Emulation.setDeviceMetricsOverride', {width: 900, height: 800, deviceScaleFactor: 1, mobile: false});
  await waitClose();
  await active(null);
  await send('Emulation.setDeviceMetricsOverride', {width: 1200, height: 800, deviceScaleFactor: 1, mobile: false});
  await settle();
  await active('logical-first');

  // Formula component explicitly reports a geometry change invisible to ResizeObserver.
  await evaluate('document.querySelector("#theorem-first-en").style.transform = "translateX(650px)"; alignAndScaleMath()');
  await waitClose();
  await active(null);
  await evaluate('document.querySelector("#theorem-first-en").style.transform = ""; alignAndScaleMath()');
  await settle();
  await active('logical-first');
  await retain();
  await evaluate('window.dispatchEvent(new Event("resize")); document.querySelector("#theorem-lemma .proof-indent-slider").dispatchEvent(new Event("input"))');
  await settle();
  await retained();
  await move(100, 30); // Another sidebar is outside the interaction area.
  await waitClose();
  await active(null);

  await move(400, 300);
  await move(-10, 300); // Actual browser viewport exit clears immediately.
  await active(null);
  await evaluate('window.dispatchEvent(new Event("resize")); window.dispatchEvent(new Event("hashchange"))');
  await settle();
  await active(null);
  await move(400, 300);
  await move(260, 250); // Clear also cancels a pending close/frame.
  await evaluate('window.dispatchEvent(new Event("blur"))');
  await active(null);
  await waitClose();
  await evaluate('document.dispatchEvent(new Event("ps4html:layoutchange"))');
  await settle();
  await active(null);

  await move(400, 300);
  const background = await send('Target.createTarget', {url: 'about:blank'});
  await send('Target.activateTarget', {targetId: background.targetId});
  await sleep(100);
  assert.equal(await evaluate('document.hidden'), true);
  await active(null);
  await send('Target.activateTarget', {targetId: pageTargetId});
  await send('Target.closeTarget', {targetId: background.targetId});
  await settle();
  await active(null); // Returning to the tab does not revive stale coordinates.
  await send('Input.dispatchTouchEvent', {type: 'touchStart', touchPoints: [{x: 400, y: 300}]});
  await send('Input.dispatchTouchEvent', {type: 'touchMove', touchPoints: [{x: 410, y: 300}]});
  await send('Input.dispatchTouchEvent', {type: 'touchEnd', touchPoints: []});
  await settle();
  await active(null);
  await move(420, 300);
  await active('logical-first');
  await evaluate('window.dispatchEvent(new Event("pagehide"))');
  await active(null);
  assert.equal(await evaluate('document.querySelectorAll("template").length'), 2);
  assert.deepEqual(exceptions, [], 'No uncaught browser exceptions');
  console.log('Theorem navigation passed: mouse hit testing, one live graph, gap/link interaction, stable identity, stationary scroll/layout/language/branch/flip, exit/blur/background and touch isolation.');
} finally {
  socket?.close();
  if (browser && browser.exitCode === null) {
    const exited = new Promise(resolve => browser.once('exit', resolve));
    browser.kill();
    await exited;
  }
  if (server.listening) await new Promise(resolve => server.close(resolve));
  rmSync(profile, { recursive: true, force: true });
}
