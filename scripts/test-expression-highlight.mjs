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
    contains(node) {
        for (let current = node; current; current = current.parent) if (current === this) return true;
        return false;
    }
    querySelector() { return null; }
    closest(selector) {
        if (selector === '[data-ps-render-root]' && this.dataset.psRenderRoot) return this;
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
// A multiplication can have a narrow inline piece across a much taller sum /
// fraction. The ancestor's smaller area must not hide the nested expression.
const sum = new Element([rect(100, 60, 240, 140)], target);
sum.dataset.psExprFragment = 'p2';
const fraction = new Element([rect(150, 70, 230, 130)], sum);
fraction.dataset.psExprFragment = 'p3';
const originalTargetRects = target.rects;
target.rects = [rect(100, 80, 240, 100)];
target.children = [];
// Use a fresh root to avoid relying on any internal cache invalidation API.
const nestedMath = new Element([rect(95, 50, 260, 150)], null, ['katex']);
target.parent = nestedMath;
nestedMath.children.push(target, sum, fraction);
assert.equal(fragmentAt(120, 90), sum, 'sum wins over a smaller enclosing multiplication fragment');
assert.equal(fragmentAt(180, 90), fraction, 'fraction wins over both enclosing sum and multiplication');
const reverseMath = new Element([rect(95, 50, 260, 150)], null, ['katex']);
target.parent = reverseMath;
reverseMath.children.push(fraction, sum, target);
assert.equal(fragmentAt(180, 90), fraction, 'a later ancestor cannot replace its descendant');
target.parent = math;
target.rects = originalTargetRects;
target.children = [arrow, detached];
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
    [['85px', '40px']],
    'one fragment wrapped across lines receives one enclosing rectangle');
assert.equal(highlights.children[0].style.height, '75px');
const island = new Element();
island.dataset.psRenderRoot = 'r1';
const inlinePieces = new Element([rect(100, 200, 120, 221), rect(120, 200, 140, 221)], island);
assert.equal(visibleRects(inlinePieces).length, 2, 'hit testing retains original fragment areas');
occurrenceNodes.set('o5', [inlinePieces]);
paintHighlights();
assert.deepEqual(highlights.children.map(box => [box.style.left, box.style.width]),
    [['100px', '40px']], 'multiple client rects on one inline line form one outline');
const textPiece = new Element([rect(140, 200.5, 180, 221)], island);
const mathPiece = new Element([rect(180, 200, 210, 221)], island);
// Occurrence fragment IDs are allocated in render order, not visual order.
occurrenceNodes.set('o5', [mathPiece, inlinePieces, textPiece]);
paintHighlights();
assert.deepEqual(highlights.children.map(box => [box.style.left, box.style.width, box.style.height]),
    [['100px', '110px', '21px']], 'adjacent text and formula anchors have no internal borders');
const gap = new Element([rect(220, 200, 240, 221)], island);
occurrenceNodes.set('o5', [inlinePieces, gap]);
paintHighlights();
assert.deepEqual(highlights.children.map(box => [box.style.left, box.style.width]),
    [['100px', '140px']], 'one template gets its minimal enclosing rectangle across component gaps');
const otherIsland = new Element();
otherIsland.dataset.psRenderRoot = 'r2';
occurrenceNodes.set('o5', [inlinePieces, new Element([rect(140, 200, 180, 221)], otherIsland)]);
paintHighlights();
assert.equal(highlights.children.length, 2, 'touching render islands stay independent');
activeOccurrences.add('o4');
occurrenceNodes.set('o4', [textPiece]);
occurrenceNodes.set('o5', [inlinePieces]);
paintHighlights();
assert.equal(highlights.children.length, 2, 'linked semantic occurrences never compose their boxes');
activeOccurrences.delete('o4');
const tallMath = new Element([rect(95, 180, 260, 280)], island, ['katex']);
const tall = new Element([rect(100, 200, 140, 221)], tallMath);
const tallLeaf = new Element([rect(110, 185, 135, 260)], tall);
tall.children.push(tallLeaf);
occurrenceNodes.set('o5', [tall, new Element([rect(140, 240, 180, 261)], island)]);
paintHighlights();
assert.equal(highlights.children.length, 1, 'one template includes every line and overflowing math ink');
assert.deepEqual(highlights.children.map(box => [box.style.top, box.style.height]), [['185px', '76px']]);
const wrapped = new Element([rect(100, 300, 160, 321), rect(100, 330, 130, 351)], island);
occurrenceNodes.set('o5', [wrapped, new Element([rect(130, 330.5, 190, 351)], island)]);
paintHighlights();
assert.deepEqual(highlights.children.map(box => [box.style.top, box.style.width, box.style.height]),
    [['300px', '90px', '51px']], 'a wrapped mixed template has exactly one minimal enclosing box');
// The middle HTML atom can be taller than both math runs (strong/code styles).
const literalParent = new Element([rect(140, 190, 180, 230)], island);
occurrenceNodes.set('o5', [inlinePieces, literalParent, mathPiece]);
paintHighlights();
assert.deepEqual(highlights.children.map(box => [box.style.left, box.style.top, box.style.width, box.style.height]),
    [['100px', '190px', '110px', '40px']], 'HTML atom height participates in the parent template bounds');
assert.equal(literalParent.classList.contains('ps-expression-active'), false,
    'enclosing a child does not activate that child as a separate selected expression');
activeOccurrences.clear();
activeOccurrences.add('o4');
occurrenceNodes.set('o4', [inlinePieces, mathPiece]);
paintHighlights();
assert.equal(highlights.children.length, 2, 'repeated binder selectors in one render root stay separate symbols');
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
