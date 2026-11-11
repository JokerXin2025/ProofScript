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
            remove(...names) { for (const name of names) {
                const index = classes.indexOf(name);
                if (index >= 0) classes.splice(index, 1);
            } },
            add(name) { if (!classes.includes(name)) classes.push(name); },
            toggle(name, active) {
                const index = classes.indexOf(name);
                if (active && index < 0) classes.push(name);
                if (!active && index >= 0) classes.splice(index, 1);
            } };
    }
    getClientRects() { return this.rects; }
    getBoundingClientRect() { return this.rects[0] || rect(0, 0, 0, 0); }
    matches() { return false; }
    querySelector() { return null; }
    closest(selector) {
        if (selector === '.proof-dashboard-reveal') return this.hiddenPanel || this.parent?.hiddenPanel || null;
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
const closedFragment = new Element([rect(100, 85, 240, 115)]);
closedFragment.dataset.psExprFragment = 'p1';
closedFragment.hiddenPanel = { classList: { contains: () => false } };
const unrelated = new Element([rect(500, 500, 550, 550)]);
unrelated.querySelectorAll = () => { throw new Error('unrelated expression was traversed'); };
arrow.children.push(path);
target.children.push(arrow, detached);
const nodeFilter = { SHOW_ELEMENT: 1, SHOW_TEXT: 4, FILTER_ACCEPT: 1, FILTER_REJECT: 2 };
const handlers = new Map();
const frames = new Map();
let frameId = 0;
let hitTests = 0;
const document = {
    body: { append() {} },
    getElementById: () => ({ textContent: JSON.stringify({ occurrences: {
        o1: { fragmentIds: ['p1'], kind: 'const', entityKey: '["constant", "Filter.Tendsto"]' },
            o2: { fragmentIds: ['p2'], kind: 'const', entityKey: '["constant", "Filter.Tendsto"]' },
            o3: { fragmentIds: ['p3'], kind: 'const', entityKey: '["constant", "Other"]' },
            o4: { fragmentIds: ['p4', 'p5'], kind: 'binder', entityKey: '["bvar", "cauchy", "z"]' },
            o5: { fragmentIds: ['p6', 'p7'], kind: 'concept', entityKey: '["constant", "Repeated"]' },
    } }) }),
    createElement: () => ({ setAttribute() {}, replaceChildren(...children) { this.children = children; },
        classList: { add(name) { this.names ??= []; this.names.push(name); } }, style: {} }),
    createRange: () => ({}),
    createTreeWalker(root) {
        const nodes = [...root.children, ...root.children.flatMap(child => child.children)];
        let index = 0;
        return { nextNode: () => nodes[index++] || null };
    },
    elementFromPoint: (x, y) => { hitTests++; return x === 0 ? null : x === 1 ? closedFragment : x === 2 ? unrelated : arrow; },
    addEventListener(name, handler) { handlers.set(name, handler); },
};
const context = { document, window: { addEventListener() {} }, Element, SVGElement: Element,
    Node: { ELEMENT_NODE: 1, TEXT_NODE: 3 }, NodeFilter: nodeFilter,
    requestAnimationFrame(callback) { const id = ++frameId; frames.set(id, callback); return id; },
    cancelAnimationFrame(id) { frames.delete(id); } };
const source = readFileSync(new URL('../tools/ps4html/PS4HTML/assets/js/lean2tex.js', import.meta.url), 'utf8');
vm.runInNewContext(source.replace(/\}\)\(\);\s*$/, 'window.__geometryTest = { visibleRects, fragmentAt, paintHighlights, setEntityActive, updateClasses, activeOccurrences, occurrenceNodes, highlights, state }; })();'), context);
const { visibleRects, fragmentAt, paintHighlights, activeOccurrences,
    occurrenceNodes, highlights, state, setEntityActive, updateClasses } = context.window.__geometryTest;
math.children.push(target);
const boxes = visibleRects(target);
assert.equal(boxes.length, 1);
assert.deepEqual({ ...boxes[0] }, { left: 100, right: 240, top: 65, bottom: 135 });
assert.equal(fragmentAt(150, 70), target, 'hover reaches the top of the tall arrow');
assert.equal(fragmentAt(0, 20), null, 'the detached zero-origin box does not become a hit target');
assert.equal(visibleRects(closedFragment).length, 0, 'closed dashboard nodes have no highlight geometry');
assert.equal(fragmentAt(1, 90), null, 'closed dashboard expressions cannot intercept pointer hits');
occurrenceNodes.set('o1', [hoveredLeft, hoveredRight]);
occurrenceNodes.set('o2', [linkedLeft, linkedRight]);
occurrenceNodes.get('o2').push(closedFragment);
occurrenceNodes.set('o3', [unrelated]);
activeOccurrences.add('o1');
setEntityActive('o1', true);
assert.ok(activeOccurrences.has('o2'), 'linked constant occurrence is tracked for painting');
state.pinned = {id: 'o1'};
paintHighlights();
assert.equal(highlights.children.length, 4, 'linked occurrences highlight each rendered fragment');
assert.deepEqual(highlights.children.map(box => [box.style.left, box.style.width]),
    [['100px', '30px'], ['137px', '63px'], ['300px', '25px'], ['332px', '68px']]);
assert.deepEqual(highlights.children.map(box => box.classList.names?.includes('is-selected') || false),
    [true, true, false, false], 'only the hovered occurrence is selected');
activeOccurrences.clear();
occurrenceNodes.set('o4', [new Element([rect(100, 85, 110, 110)]),
    new Element([rect(300, 85, 310, 110)])]);
activeOccurrences.add('o4');
state.pinned = {id: 'o4'};
paintHighlights();
assert.deepEqual(highlights.children.map(box => [box.style.left, box.style.width]),
    [['100px', '10px'], ['300px', '10px']],
    'the two Cauchy integral binder z anchors each receive their own box');
activeOccurrences.clear();
occurrenceNodes.set('o5', [new Element([rect(100, 85, 110, 110)]),
    new Element([rect(300, 85, 310, 110)])]);
activeOccurrences.add('o5');
state.pinned = {id: 'o5'};
paintHighlights();
assert.deepEqual(highlights.children.map(box => [box.style.left, box.style.width]),
    [['100px', '10px'], ['300px', '10px']],
    'non-binder occurrences also keep separate fragment boundaries');
occurrenceNodes.set('o5', [new Element([rect(100, 85, 110, 110), rect(100, 135, 140, 160)])]);
paintHighlights();
assert.deepEqual(highlights.children.map(box => [box.style.top, box.style.width]),
    [['85px', '10px'], ['135px', '40px']],
    'one fragment wrapped across lines keeps its distinct layout rectangles');
updateClasses();
assert.equal(closedFragment.classList.contains('ps-expression-active'), false,
    'hidden linked expressions are not styled');
unrelated.getBoundingClientRect = () => { throw new Error('blank-space hover measured unrelated content'); };
assert.equal(fragmentAt(2, 90), null, 'blank space does not scan expressions');
state.pinned = null;
frames.clear();
hitTests = 0;
for (let i = 0; i < 100; i++) handlers.get('pointermove')({isPrimary: true, pointerType: 'mouse', clientX: 2, clientY: 90});
assert.equal(hitTests, 0, 'pointer handlers defer geometry to the frame');
assert.equal(frames.size, 1, 'pointer bursts coalesce into one hit test');
for (const callback of frames.values()) callback();
assert.equal(hitTests, 1);
// A semantic rebuild would call document.querySelectorAll, absent in this mock.
handlers.get('ps4html:layoutchange')();
console.log('Expression highlight geometry and pointer hit testing OK');
