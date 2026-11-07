import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const handlers = new Map();
const content = {style: {}, scrollWidth: 900, scrollHeight: 120};
const viewport = {
    clientWidth: 450, style: {},
    querySelector: selector => selector === ':scope > .ps-fit-content' ? content : null,
};
const document = {
    querySelectorAll: selector => selector === '.ps-fit-viewport' ? [viewport] : [],
    addEventListener: (name, handler) => handlers.set(name, handler),
    dispatchEvent() {},
};
const window = {addEventListener: (name, handler) => handlers.set(name, handler)};
let frame;
const requestAnimationFrame = callback => { frame = callback; };
const source = readFileSync(new URL('../tools/ps4html/PS4HTML/assets/js/equation_size.js', import.meta.url), 'utf8');
vm.runInNewContext(source, {document, window, Event, requestAnimationFrame});

handlers.get('resize')();
frame();
assert.equal(content.style.transform, 'scale(0.5)', 'oversized content fits the available width');
assert.equal(viewport.style.height, '60px', 'the box reserves the scaled content height');

viewport.clientWidth = 1000;
handlers.get('resize')();
frame();
assert.equal(content.style.transform, '', 'content returns to natural size when space is available');
assert.equal(viewport.style.height, '', 'unscaled content determines its own height');

content.scrollWidth = 100;
content.scrollHeight = 300;
handlers.get('resize')();
frame();
assert.equal(content.style.transform, '', 'tall content does not shrink when it fits horizontally');
console.log('Unified content width fitting and height behavior OK');
