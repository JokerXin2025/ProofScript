import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const handlers = new Map();
const timers = new Map();
let clock = 0;
let nextTimer = 0;
const anchor = { classList: { contains: name => name === 'ps-expression-switchable' }, closest: () => null };
const otherAnchor = { classList: { contains: () => true }, closest: () => null };
const target = { anchor, id: 'same', occurrence: {} };
const other = { anchor: otherAnchor, id: 'other', occurrence: {} };
const window = { opened: [], addEventListener() {}, PS4HTMLExpressionInteractions: {
    resolveTarget: (_element, x) => window.menu && window.menu.style.pointerEvents !== 'none' && window.menu.overPointer ? null
        : x < 100 ? target : x < 200 ? other : null,
} };
const document = {
    documentElement: { dataset: {} },
    getElementById: () => ({ textContent: '{"occurrences":{},"renderRoots":{}}' }),
    addEventListener(name, handler) {
        if (!handlers.has(name)) handlers.set(name, []);
        handlers.get(name).push(handler);
    },
    contains: value => value === anchor || value === otherAnchor,
};
const setTimeout = (callback, delay) => {
    const id = ++nextTimer;
    timers.set(id, { callback, at: clock + delay });
    return id;
};
const clearTimeout = id => timers.delete(id);
function advance(ms) {
    clock += ms;
    for (const [id, timer] of [...timers]) {
        if (timer.at <= clock) { timers.delete(id); timer.callback(); }
    }
}
function fire(name, properties = {}) {
    const event = { pointerId: 1, isPrimary: true, button: 0, clientX: 20, clientY: 20,
        target: anchor, ...properties };
    for (const handler of handlers.get(name) || []) {
        handler(event);
        if (event.stopped) break;
    }
    return event;
}
const source = readFileSync(new URL('../tools/ps4html/PS4HTML/assets/js/template-switcher.js', import.meta.url), 'utf8');
vm.runInNewContext(source.replace('function open(target, x, y) {',
    'function open(target, x, y) { window.opened.push({target, x, y}); menu = window.menu = {style: {}, remove() { window.menu = null; }}; return true; }\n' +
    'function originalOpen(target, x, y) {'), { document, window, setTimeout, clearTimeout });

fire('pointerdown');
fire('pointermove', { clientX: 40 });
advance(1000);
assert.equal(window.opened.length, 1, 'menu opens as soon as the long-press timer completes');
assert.equal(window.opened[0].x, 52, 'menu opens beside the current pointer position');
window.menu.overPointer = true;
fire('pointerup', { clientX: 40 });
assert.equal(window.opened.length, 1, 'release does not reopen an already visible menu');
let consumed = false;
fire('click', { preventDefault() { consumed = true; }, stopImmediatePropagation() { this.stopped = true; } });
assert.equal(consumed, true, 'release click cannot immediately close the menu');
window.menu.overPointer = false;

fire('pointerdown');
advance(1000);
assert.equal(window.opened.length, 2, 'press opens before release');
fire('pointerup', { clientX: 150, target: otherAnchor });
assert.equal(window.opened.length, 2, 'releasing on another object does not reopen');

fire('pointerdown');
fire('pointermove', { clientX: 250 });
advance(1000);
assert.equal(window.opened.length, 2, 'leaving the object before timeout does not open');
fire('pointerup', { clientX: 20 });
assert.equal(window.opened.length, 3, 'returning to the original object on release still opens');

fire('pointerdown');
advance(999);
fire('pointerup');
assert.equal(window.opened.length, 3, 'short press does not open');

fire('pointerdown');
fire('pointercancel');
advance(1000);
fire('pointerup');
assert.equal(window.opened.length, 3, 'cancelled press does not open');
console.log('Template long-press immediate opening and release targeting OK');
