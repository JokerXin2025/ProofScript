import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const rect = (left, top, right, bottom) => ({ left, top, right, bottom,
    width: right - left, height: bottom - top });
class Element {
    constructor(rects = [], parent = null, classes = []) {
        this.rects = rects;
        this.parent = parent;
        this.children = [];
        this.dataset = {};
        this.classList = { contains: name => classes.includes(name),
            toggle(name, active) {
                const index = classes.indexOf(name);
                if (active && index < 0) classes.push(name);
                if (!active && index >= 0) classes.splice(index, 1);
            } };
    }
    getClientRects() { return this.rects; }
    getBoundingClientRect() { return this.rects[0] || rect(0, 0, 0, 0); }
    closest(selector) {
        if (selector === 'svg' && this.isSvg) return this;
        if (selector === 'svg' && this.parent?.isSvg) return this.parent;
        if (selector === '.katex' && this.classList.contains('katex')) return this;
        return this.parent?.closest(selector) || null;
    }
    querySelectorAll() { return this.children; }
    hasAttribute(name) { return name === 'data-ps-expr-fragment' && !!this.dataset.psExprFragment; }
}
const math = new Element([rect(95, 60, 260, 140)], null, ['katex']);
const target = new Element([rect(100, 85, 240, 115)], math);
target.dataset.psExprFragment = 'p1';
const linkedLeft = new Element([rect(300, 85, 325, 115)]);
const linkedRight = new Element([rect(332, 85, 400, 115)]);
const hoveredLeft = new Element([rect(100, 155, 130, 180)]);
const hoveredRight = new Element([rect(137, 155, 200, 180)]);
const arrow = new Element([rect(120, 65, 200, 135)], target);
arrow.isSvg = true;
const path = new Element([rect(-6292, 65, 200, 135)], arrow);
path.isSvg = true;
const detached = new Element([rect(0, 0, 40, 50)], target);
arrow.children.push(path);
target.children.push(arrow, detached);
const nodeFilter = { SHOW_ELEMENT: 1, SHOW_TEXT: 4, FILTER_ACCEPT: 1, FILTER_REJECT: 2 };
const document = {
    body: { append() {} },
    getElementById: () => ({ textContent: JSON.stringify({ occurrences: {
        o1: { fragmentIds: ['p1'], kind: 'const', entityKey: '["constant", "Filter.Tendsto"]' },
        o2: { fragmentIds: ['p2'], kind: 'const', entityKey: '["constant", "Filter.Tendsto"]' },
    } }) }),
    createElement: () => ({ setAttribute() {}, replaceChildren(...children) { this.children = children; },
        classList: { add(name) { this.names ??= []; this.names.push(name); } }, style: {} }),
    createRange: () => ({}),
    createTreeWalker(root) {
        const nodes = [...root.children, ...root.children.flatMap(child => child.children)];
        let index = 0;
        return { nextNode: () => nodes[index++] || null };
    },
    elementFromPoint: (x, y) => x === 0 ? null : arrow,
    addEventListener() {},
};
const context = { document, window: { addEventListener() {} }, Element, SVGElement: Element,
    Node: { ELEMENT_NODE: 1, TEXT_NODE: 3 }, NodeFilter: nodeFilter,
    requestAnimationFrame() {}, cancelAnimationFrame() {} };
const source = readFileSync(new URL('../tools/ps4html/PS4HTML/assets/js/lean2tex.js', import.meta.url), 'utf8');
vm.runInNewContext(source.replace(/\}\)\(\);\s*$/, 'window.__geometryTest = { visibleRects, fragmentAt, mergeHighlightRects, paintHighlights, setEntityActive, activeOccurrences, occurrenceNodes, highlights, state }; })();'), context);
const { visibleRects, fragmentAt, mergeHighlightRects, paintHighlights, activeOccurrences,
    occurrenceNodes, highlights, state, setEntityActive } = context.window.__geometryTest;
math.children.push(target);
const boxes = visibleRects(target);
assert.equal(boxes.length, 1);
assert.deepEqual({ ...boxes[0] }, { left: 100, right: 240, top: 65, bottom: 135 });
assert.equal(fragmentAt(150, 70), target, 'hover reaches the top of the tall arrow');
assert.equal(fragmentAt(0, 20), null, 'the detached zero-origin box does not become a hit target');
const merged = mergeHighlightRects([rect(100, 85, 120, 110), rect(128, 86, 180, 110), rect(190, 85, 240, 110)]);
assert.deepEqual([...merged].map(box => [box.left, box.right]), [[100, 240]],
    'one expression made of adjacent text and math fragments has one outline');
assert.equal(mergeHighlightRects([rect(100, 85, 120, 110), rect(100, 130, 160, 150)]).length, 2,
    'different visual lines retain separate outlines');
occurrenceNodes.set('o1', [hoveredLeft, hoveredRight]);
occurrenceNodes.set('o2', [linkedLeft, linkedRight]);
activeOccurrences.add('o1');
setEntityActive('o1', true);
assert.ok(activeOccurrences.has('o2'), 'linked constant occurrence is tracked for painting');
state.pinned = {id: 'o1'};
paintHighlights();
assert.equal(highlights.children.length, 2, 'each occurrence produces one outline, including linked constants');
assert.equal(highlights.children[0].style.width, '100px');
assert.equal(highlights.children[1].style.width, '100px');
assert.deepEqual(highlights.children.map(box => box.classList.names?.includes('is-selected') || false),
    [true, false], 'only the hovered occurrence is selected');
console.log('Expression highlight geometry and pointer hit testing OK');
