import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const window = {};
vm.runInNewContext(readFileSync(new URL('../tools/ps4html/PS4HTML/assets/js/render-tree.js', import.meta.url), 'utf8'), {window});
const {render} = window.PS4HTMLRenderTree;
const leaf = (occurrence, name, kind = 'const') => ({occurrence, name, kind, metadata: {}, children: []});
const exists = {occurrence: 'exists', name: 'Exists', kind: 'concept', metadata: {leanName: 'Exists'}, children: [
    leaf('type', 'T'), {occurrence: 'lambda', name: 'lambda', kind: 'lambda', metadata: {}, children: [
        leaf('binder', 'x', 'binder'), leaf('binderType', 'T'), leaf('body', 'P'),
    ]},
]};
const key = '["constant", "Exists"]';
const catalog = {[key]: {kind: 'concept', default: 'formula', templates: [
    {label: 'formula', lang: null, mode: 'formula', content: '\\exists\\ @1\\in #0,\\ @@1',
        binders: {'1': 1}, isolatedArguments: [], fixity: 'binder', precedence: 20, associativity: 'none'},
    {label: 'function', lang: 'en', mode: 'formula', content: 'Exists(#0,#1)',
        binders: {}, isolatedArguments: [], fixity: 'binder', precedence: 20, associativity: 'none'},
]}};
const owned = [];
const tex = render(exists, catalog, {}, 'zh', 'formula', id => {
    owned.push(id);
    return `p${owned.length}`;
});
assert.match(tex, /\\exists\\/);
assert.doesNotMatch(tex, /\\mapsto|\\operatorname\{fun\}/);
assert.ok(!owned.includes('lambda'), 'the lambda itself is not rendered when the template uses binder selectors');
assert.ok(owned.includes('binder') && owned.includes('body') && owned.includes('exists'));

const symbolicCatalog = {
    '["constant", "Add"]': {kind: 'operator', symbol: '+', fixity: 'infix', precedence: 65,
        associativity: 'left', templates: [], default: 'formula'},
    '["constant", "Eq"]': {kind: 'relation', symbol: '=', fixity: 'infix', precedence: 50,
        associativity: 'none', templates: [], default: 'formula'},
    '["constant", "Neg"]': {kind: 'operator', symbol: '-', fixity: 'prefix', precedence: 75,
        associativity: 'none', templates: [], default: 'formula'},
};
const sum = {occurrence: 'sum', name: 'Add', kind: 'operator', metadata: {leanName: 'Add'},
    children: [leaf('a', 'a', 'fvar'), leaf('b', 'b', 'fvar')]};
const equality = {occurrence: 'eq', name: 'Eq', kind: 'relation', metadata: {leanName: 'Eq'},
    children: [sum, leaf('c', 'c', 'fvar')]};
const negative = {occurrence: 'neg', name: 'Neg', kind: 'operator', metadata: {leanName: 'Neg'}, children: [sum]};
assert.equal(render(equality, symbolicCatalog, {}, 'zh', 'formula'), 'a+b=c');
assert.equal(render(negative, symbolicCatalog, {}, 'zh', 'formula'), '-\\left(a+b\\right)');

const letKey = '["builtin", "let"]';
const letCatalog = {[letKey]: {default: 'where', templates: [
    {label: 'where', available: true},
]}};
const inner = {occurrence: 'inner', name: 'let', kind: 'let', metadata: {}, children: [
    leaf('innerBinder', 'b', 'binder'), leaf('innerValue', 'B'), leaf('result', 'R'),
]};
const outer = {occurrence: 'outer', name: 'let', kind: 'let', metadata: {}, children: [
    leaf('outerBinder', 'a', 'binder'), leaf('outerValue', 'A'), inner,
]};
const where = render(outer, letCatalog, {}, 'zh', 'formula', id => `p${id}`);
assert.ok(where.indexOf('{b}') < where.indexOf('{a}'),
    `inner definitions precede outer definitions in the where clause: ${where}`);
console.log('Browser renderer binder ownership and let clause order OK');
