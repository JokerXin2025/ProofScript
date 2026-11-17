import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const window = {};
vm.runInNewContext(readFileSync(new URL('../tools/ps4html/PS4HTML/assets/js/beta-reduce.js', import.meta.url), 'utf8'), {window});
vm.runInNewContext(readFileSync(new URL('../tools/ps4html/PS4HTML/assets/js/render-tree.js', import.meta.url), 'utf8'), {window});
const {reduce} = window.PS4HTMLBetaReduce;
const {render} = window.PS4HTMLRenderTree;
const node = (kind, occurrence, name, children = [], metadata = {}) => ({kind, occurrence, name, children, metadata});
const variable = (id, occurrence) => node('bvar', occurrence, id, [], {bindRef: id});
const binder = (id, occurrence) => node('binder', occurrence, id, [], {bindId: id});
const constant = (name, occurrence) => node('const', occurrence, name);
const lambda = (id, occurrence, body) => node('lambda', occurrence, 'lambda', [binder(id, `${occurrence}-binder`),
    constant('Type', `${occurrence}-type`), body]);
const application = (occurrence, ...children) => node('application', occurrence, 'application', children);

const nested = lambda('outer', 'outer-lambda', lambda('inner', 'inner-lambda', variable('outer', 'outer-use')));
const original = application('app', nested, variable('inner', 'free-inner'));
const reduced = reduce(original);
assert.equal(reduced.kind, 'lambda');
assert.equal(reduced.children[2].metadata.bindRef, 'inner');
assert.equal(reduced.children[2].occurrence, 'free-inner');
assert.equal(original.kind, 'application', 'the original tree remains available when the option is turned off');
assert.equal(render(reduced, {}, {}, 'en', 'formula'), 'inner \\mapsto inner');

const chained = application('chain', lambda('x', 'x-lambda', lambda('y', 'y-lambda', variable('x', 'x-use'))),
    constant('A', 'a'), constant('B', 'b'));
assert.equal(render(reduce(chained), {}, {}, 'en', 'formula'), '\\operatorname{A}');
const untouched = application('ordinary', constant('F', 'f'), constant('A', 'a'));
assert.equal(reduce(untouched), untouched);
console.log('PS4HTML beta reduction: capture, multi-argument applications and immutable trees OK');
