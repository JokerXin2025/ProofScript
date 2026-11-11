import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

let ready, transition, notifications = 0;
const inner = { style: {height: '400px'}, dataset: {frontHeight: '400'},
    classList: {contains: () => false},
    addEventListener(name, callback) { if (name === 'transitionend') transition = callback; } };
const button = {addEventListener() {}};
const card = {querySelector: selector => selector === '.proof-flip-inner' ? inner : button};
const document = {addEventListener(name, callback) { ready = callback; },
    querySelectorAll: () => [card], dispatchEvent() { notifications++; }};
vm.runInNewContext(readFileSync(new URL('../tools/ps4html/PS4HTML/assets/js/code-flip.js', import.meta.url), 'utf8'),
    {document, Event: class {}});
ready();
for (const propertyName of ['color', 'background-color', 'box-shadow', 'height', 'transform', 'grid-template-rows']) {
    transition({target: {}, propertyName});
}
transition({target: inner, propertyName: 'color'});
assert.equal(notifications, 0, 'descendant hover/dashboard transitions cannot trigger global layout work');
assert.equal(inner.style.height, '400px', 'descendant height transitions cannot reset the flip height');
transition({target: inner, propertyName: 'transform'});
transition({target: inner, propertyName: 'height'});
assert.equal(notifications, 2, 'actual flip transitions still notify');
assert.equal(inner.style.height, '');
console.log('Code flip transition event isolation OK');
