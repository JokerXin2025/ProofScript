import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const handlers = new Map();
const windowHandlers = new Map();
const styles = new Map();
const attributes = new Map();
const stored = new Map();
let frame;
let width = 1200;
const splitter = {
    offsetWidth: 12,
    addEventListener: (type, handler) => handlers.set(type, handler),
    setAttribute: (name, value) => attributes.set(name, value),
    getBoundingClientRect: () => ({ left: Number(styles.get('--sidebar-width')?.replace('px', '') || 300) }),
    setPointerCapture(id) { this.captured = id; },
};
const layout = {
    get clientWidth() { return width; },
    getBoundingClientRect: () => ({ left: 0 }),
    querySelector: () => splitter,
    style: { setProperty: (name, value) => styles.set(name, value) },
    classList: { add() {}, remove() {} },
};
const document = { querySelector: () => layout };
const window = {
    addEventListener: (type, handler) => windowHandlers.set(type, handler),
    dispatchEvent: event => windowHandlers.get(event.type)?.(event),
};
const localStorage = {
    getItem: key => stored.get(key) ?? null,
    setItem: (key, value) => stored.set(key, value),
};
const source = readFileSync(new URL('../tools/ps4html/PS4HTML/assets/js/page-splitter.js', import.meta.url), 'utf8');
vm.runInNewContext(source, { document, window, localStorage, Event, requestAnimationFrame: callback => { frame = callback; return 1; } });

const pointer = (type, x) => handlers.get(type)({ type, pointerId: 1, isPrimary: true, button: 0,
    clientX: x, preventDefault() {} });
pointer('pointerdown', 300);
pointer('pointermove', 500);
pointer('pointerup', 500);
assert.equal(styles.get('--sidebar-width'), '494px');
assert.equal(attributes.get('aria-valuenow'), '494');
assert.equal(stored.get('ps4html:sidebar-width'), '494');
frame();

pointer('pointerdown', 500);
pointer('pointerup', 1100);
assert.equal(styles.get('--sidebar-width'), '708px', 'main content retains its minimum width');
pointer('pointerdown', 700);
pointer('pointerup', 0);
assert.equal(styles.get('--sidebar-width'), '240px', 'sidebar retains its minimum width');

handlers.get('keydown')({ key: 'ArrowRight', preventDefault() {} });
assert.equal(styles.get('--sidebar-width'), '264px');
width = 800;
windowHandlers.get('resize')();
handlers.get('keydown')({ key: 'End', preventDefault() {} });
assert.equal(styles.get('--sidebar-width'), '308px');
assert.equal(attributes.get('aria-valuemax'), '308');
console.log('Page splitter drag, keyboard controls, and size limits OK');
