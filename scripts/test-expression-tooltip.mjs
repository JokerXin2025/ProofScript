import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

class Element {
    constructor(tag) {
        this.tag = tag;
        this.children = [];
        this.className = '';
        this.textContent = '';
    }
    setAttribute(key, value) { this[key] = value; }
    append(...children) { this.children.push(...children); }
}

const document = {
    documentElement: { dataset: { language: 'zh' } },
    createElement: tag => new Element(tag),
};
const window = {};
vm.runInNewContext(readFileSync(new URL('../tools/ps4html/PS4HTML/assets/js/expression-tooltip.js', import.meta.url), 'utf8'),
    { document, window });

const ui = {
    zh: {
        'title.exists': '存在量词', 'title.operator': '运算符', 'title.application': '应用',
        'title.universe': '类型宇宙', 'title.boundVariable': '绑定变量',
        'field.expression': '表达式', 'field.type': '类型', 'field.leanName': 'Lean 中的声明名',
        'field.level': '宇宙层级', 'field.index': 'de Bruijn 索引', 'field.rawData': '原始数据',
    },
    en: {
        'title.exists': 'Existential quantifier', 'title.boundVariable': 'Bound variable',
        'field.index': 'de Bruijn index', 'field.rawData': 'Raw data',
    },
};
const view = (category, occurrence, technical = false) => window.PS4HTMLExpressionTooltip.render({
    category, occurrence, entity: null,
    traits: [], layer: '1 / 2',
}, ui, technical);
const text = element => [element.textContent, ...element.children.map(text)].join(' ');

assert.equal(view('operator', { headConst: 'Exists', originalExprKind: 'app',
    expressionText: '∃ x, P x' }).children[0].textContent, '存在量词');
assert.equal(view('operator', { headConst: 'HAdd.hAdd' }).children[0].textContent, '运算符');
assert.equal(view('application', { headConst: 'Exists' }).children[0].textContent, '应用');
assert.match(text(view('sort', { display: 'Type', level: { kind: 'level.succ',
    level: { kind: 'level.max', u: { kind: 'level.param', name: 'u' },
        v: { kind: 'level.zero' } } } })), /max\(u, 0\) \+ 1/);
const bound = view('bvar', { display: 'x', index: 0, fvarId: 'internal' });
assert.match(text(bound), /de Bruijn 索引.*0/);
assert.doesNotMatch(text(bound), /internal|1 \/ 2/);
for (const [kind, detail, expected] of [
    ['fvar', {}, 'freeVariable'], ['binder', {}, 'binder'],
    ['metavariable', {}, 'unknownVariable'], ['let', {}, 'localDefinition'],
    ['const', { leanName: 'Exists' }, 'constant'],
    ['const', { headConst: 'Exists', originalExprKind: 'app' }, 'exists'],
    ['lambda', {}, 'lambda'], ['forall', { isArrow: true }, 'implication'],
    ['forall', { isArrow: false }, 'forall'],
    ['literal', { literalKind: 'literal.nat', value: '0' }, 'number'],
    ['literal', { literalKind: 'literal.str', value: '' }, 'string'],
    ['projection', {}, 'projection'], ['relation', {}, 'relation'],
    ['wrapper', { headConst: 'Exists' }, 'wrapper'], ['unexpected', {}, 'expression'],
]) {
    assert.equal(view(kind, detail).children[0].textContent, ui.zh[`title.${expected}`] || `title.${expected}`);
}
document.documentElement.dataset.language = 'en';
assert.match(text(view('bvar', { display: 'x', index: 0 })), /Bound variable.*de Bruijn index/);
const detailed = view('bvar', { display: 'x', index: 0 }, true);
assert.match(text(detailed), /Raw data/);
assert.match(text(detailed), /"index": 0/);
console.log('Expression tooltip classification, localization and technical details OK');
