import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const handlers = new Map();
const windowHandlers = new Map();
let href = 'file:///site/index.html?ps4html-language=en&ps-display-wrappers=1&ps4html-sidebar-width=300&other=keep#proof';
const links = [
    { href: 'chapter.html#theorem', dataset: {} },
    { href: '#heading', dataset: {} },
    { href: 'https://example.org/other.html', dataset: {} },
    { href: 'other-project.html', dataset: { psProjectId: 'different' } },
].map(link => ({ ...link, getAttribute(name) { return this[name]; }, setAttribute(name, value) { this[name] = value; } }));
const document = {
    documentElement: { dataset: { projectBaseUrl: './', projectId: 'example' } },
    querySelectorAll: selector => selector === 'a[href]' ? links : [],
    addEventListener: (type, handler) => handlers.set(type, handler),
};
const window = {
    location: { get href() { return href; } },
    history: { state: null, replaceState: (_state, _title, url) => { href = url.href; } },
    addEventListener: (type, handler) => windowHandlers.set(type, handler),
};
const source = readFileSync(new URL('../tools/ps4html/PS4HTML/assets/js/navigation-state.js', import.meta.url), 'utf8');
vm.runInNewContext(source, { document, window, URL });

handlers.get('DOMContentLoaded')();
const destination = new URL(links[0].href);
assert.equal(destination.protocol, 'file:');
assert.equal(destination.pathname, '/site/chapter.html');
assert.equal(destination.hash, '#theorem');
for (const key of ['ps4html-language', 'ps-display-wrappers', 'ps4html-sidebar-width']) {
    assert.equal(destination.searchParams.get(key), new URL(href).searchParams.get(key));
}
assert.equal(links[1].href, '#heading');
assert.equal(links[2].href, 'https://example.org/other.html');
assert.equal(links[3].href, 'other-project.html');

const choices = { '["builtin", "lambda"]': 'fun' };
assert.equal(window.PS4HTMLNavigationState.save(choices), true);
assert.equal(new URL(href).searchParams.get('other'), 'keep');
assert.equal(Object.keys(window.PS4HTMLNavigationState.read()).length, 1);
assert.equal(new URL(links[0].href).searchParams.get('ps4html-templates'), new URL(href).searchParams.get('ps4html-templates'));

const share = new URL('https://example.org/site/chapter.html?stale=1');
window.PS4HTMLNavigationState.carryToUrl(share);
assert.equal(share.searchParams.get('other'), null);
assert.equal(share.searchParams.get('stale'), '1');
assert.equal(share.searchParams.get('ps4html-language'), 'en');
assert.equal(share.searchParams.get('ps4html-templates'), new URL(href).searchParams.get('ps4html-templates'));

href = 'file:///site/index.html';
windowHandlers.get('popstate')();
assert.equal(new URL(links[0].href).searchParams.has('ps4html-templates'), false);
assert.equal(new URL(links[0].href).searchParams.has('ps4html-language'), false);
console.log('PS4HTML URL preferences, internal navigation, and sharing OK');
