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
const argument = index => ({kind: 'argument', index, mode: 'formula', max_precedence: false});
const binder = (index, depth) => ({kind: 'binder', index, depth, mode: 'formula', max_precedence: false});
const body = (index, depth) => ({kind: 'body', index, depth, mode: 'formula', max_precedence: false});
const literal = content => ({kind: 'literal', content});
const template = (label, instructions, options = {}) => ({
    label, lang: null, mode: 'formula', content: 'inspection only',
    autoArity: true, argumentIndices: [0, 1],
    precedence: 60, instructions, ...options,
});
const catalog = {[key]: {kind: 'concept', arity: 2, default: 'formula', templates: [
    template('formula', [literal('\\exists\\ '), binder(1, 1), literal('\\in '), argument(0), literal(',\\ '), body(1, 1)]),
    template('function', [literal('Exists('), argument(0), literal(','), argument(1), literal(')')], {lang: 'en'}),
]}};
exists.metadata.headConst = 'Exists';
const owned = [];
const tex = render(exists, catalog, {}, 'zh', 'formula', id => {
    owned.push(id);
    return `p${owned.length}`;
});
assert.match(tex, /\\exists\\/);
assert.doesNotMatch(tex, /\\mapsto|\\operatorname\{fun\}/);
assert.ok(!owned.includes('lambda'), 'the lambda itself is not rendered when the template uses binder selectors');
assert.ok(owned.includes('binder') && owned.includes('body') && owned.includes('exists'));

const unifiedCatalog = {
    '["constant", "Add"]': {kind: 'operator', arity: 2, default: '$infixl', templates: [
        template('$infixl', [argument(0), literal('+'), argument(1)], {precedence: 65})]},
    '["constant", "Eq"]': {kind: 'relation', arity: 2, default: '$relation', templates: [
        template('$relation', [argument(0), literal('='), argument(1)], {precedence: 50})]},
    '["constant", "Neg"]': {kind: 'operator', arity: 1, default: '$prefix', templates: [
        template('$prefix', [literal('-'), argument(0)], {precedence: 75, argumentIndices: [0]})]},
};
const sum = {occurrence: 'sum', name: 'Add', kind: 'operator', metadata: {leanName: 'Add', headConst: 'Add'},
    children: [leaf('a', 'a', 'fvar'), leaf('b', 'b', 'fvar')]};
const equality = {occurrence: 'eq', name: 'Eq', kind: 'relation', metadata: {leanName: 'Eq', headConst: 'Eq'},
    children: [sum, leaf('c', 'c', 'fvar')]};
const negative = {occurrence: 'neg', name: 'Neg', kind: 'operator', metadata: {leanName: 'Neg', headConst: 'Neg'}, children: [sum]};
assert.equal(render(equality, unifiedCatalog, {}, 'zh', 'formula'), 'a+b=c');
assert.equal(render(negative, unifiedCatalog, {}, 'zh', 'formula'), '-\\left(a+b\\right)');

function nested(label, left) {
    const inner = {occurrence: 'inner', name: 'Assoc', kind: 'operator',
        metadata: {leanName: 'Assoc', headConst: 'Assoc'}, children: [leaf('a', 'a', 'fvar'), leaf('b', 'b', 'fvar')]};
    const outer = {occurrence: 'outer', name: 'Assoc', kind: 'operator',
        metadata: {leanName: 'Assoc', headConst: 'Assoc'},
        children: left ? [inner, leaf('c', 'c', 'fvar')] : [leaf('c', 'c', 'fvar'), inner]};
    const templates = {'["constant", "Assoc"]': {kind: 'operator', arity: 2, default: label,
        templates: [template(label, [argument(0), literal('+'), argument(1)], {precedence: 65})]}};
    return render(outer, templates, {}, 'zh', 'formula');
}
assert.equal(nested('$infixl', true), 'a+b+c');
assert.equal(nested('$infixl', false), 'c+\\left(a+b\\right)');
assert.equal(nested('$infixr', true), '\\left(a+b\\right)+c');
assert.equal(nested('$infixr', false), 'c+a+b');
assert.equal(nested('$infix', true), '\\left(a+b\\right)+c');
assert.equal(nested('$infix', false), 'c+\\left(a+b\\right)');

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
