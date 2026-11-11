import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const handlers = new Map();
const classes = new Set(['proof-step', 'has-dashboard']);
const peerClasses = new Set(['proof-step', 'has-dashboard']);
function classList(initial = []) {
    const names = new Set(initial);
    return { contains: name => names.has(name), toggle(name, value) { if (value) names.add(name); else names.delete(name); } };
}
const panel = { attributes: {}, inert: true, classList: classList(), setAttribute(key, value) { this.attributes[key] = value; } };
const step = {
    classList: {
        toggle(name, value) { if (value) classes.add(name); else classes.delete(name); },
    },
    querySelector(selector) {
        if (selector === ':scope > .proof-step-header') return header;
        assert.equal(selector, ':scope > .proof-dashboard-reveal'); return panel;
    },
    closest(selector) { return selector.includes('.proof-step.has-dashboard') ? this : null; },
};
const header = {
    parentElement: step, attributes: {},
    setAttribute(key, value) { this.attributes[key] = value; },
    getAttribute(key) { return this.attributes[key]; },
    contains(node) { return node === this || node === child || node === link; },
    closest(selector) { return selector.includes('.proof-step.has-dashboard') || selector.includes("[role='button']") ? this : theorem; },
};
const peerPanel = { attributes: {}, inert: true, classList: classList(), setAttribute(key, value) { this.attributes[key] = value; } };
const peerStep = {
    classList: { toggle(name, value) { if (value) peerClasses.add(name); else peerClasses.delete(name); } },
    querySelector(selector) { return selector.includes('reveal') ? peerPanel : peerHeader; },
};
const peerHeader = { parentElement: peerStep, attributes: {}, setAttribute(key, value) { this.attributes[key] = value; } };
const theorem = { dataset: { theoremId: 'same-proof' }, querySelectorAll: () => [step] };
const peerTheorem = { dataset: { theoremId: 'same-proof' }, querySelectorAll: () => [peerStep] };
const child = { closest(selector) { return selector.includes('.proof-step.has-dashboard') ? step : null; } };
const link = { closest(selector) { return selector.includes('.proof-step.has-dashboard') ? step : selector.includes('a, button') ? this : null; } };
const dashboardBody = { closest: () => null };
let dashboardChanges = 0;
const document = { addEventListener(name, handler) { handlers.set(name, handler); },
    querySelectorAll: () => [theorem, peerTheorem],
    dispatchEvent(event) { if (event.type === 'ps4html:dashboardchange') dashboardChanges++; } };
const window = { getSelection: () => ({ toString: () => 'previous selection' }) };
const source = readFileSync(new URL('../tools/ps4html/PS4HTML/assets/js/proof-dashboard.js', import.meta.url), 'utf8');
vm.runInNewContext(source, { document, window, Element: Object, Event: class { constructor(type) { this.type = type; } } });
function click(target) { handlers.get('click')({ target }); }
function key(target, value) {
    let prevented = false;
    handlers.get('keydown')({ target, key: value, preventDefault() { prevented = true; } });
    return prevented;
}

click(child);
assert.equal(header.attributes['aria-expanded'], 'true');
assert.equal(panel.attributes['aria-hidden'], 'false');
assert.equal(panel.inert, false);
assert.equal(panel.classList.contains('is-dashboard-visible'), true);
assert.equal(peerPanel.inert, false, 'language peer is expanded too');
assert.equal(dashboardChanges, 1, 'one interaction invalidates geometry once for all language panels');
click(child);
assert.equal(header.attributes['aria-expanded'], 'false', 'clicking at the same position closes the panel');
assert.equal(panel.classList.contains('is-dashboard-visible'), false);
assert.equal(dashboardChanges, 2);
click(step);
assert.equal(header.attributes['aria-expanded'], 'true', 'header padding remains a usable toggle target');
click(link);
click(dashboardBody);
assert.equal(header.attributes['aria-expanded'], 'true', 'links and panel body do not toggle');
assert.equal(key(child, 'Enter'), false, 'nested controls do not trigger keyboard toggle');
assert.equal(key(header, ' '), true);
assert.equal(header.attributes['aria-expanded'], 'false');
assert.equal(panel.inert, true);
assert.equal(peerPanel.inert, true, 'language peer is collapsed too');
assert.equal(key(header, 'Enter'), true);
assert.equal(header.attributes['aria-expanded'], 'true');
console.log('Dashboard step interactions OK');
