import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../tools/ps4html/PS4HTML/assets/js/package-navigation.js', import.meta.url), 'utf8');

function run({ page, library, entries, parent = false }) {
    let href = `file:///site/${library}/${page}?ps4html-language=en&ps-display-wrappers=1&ps4html-sidebar-width=320`;
    const events = new Map();
    const makeLink = (name, path) => ({
        className: 'module-tree-node', textContent: name, dataset: {},
        href: `file:///site/${library}/${path}`, append() {}, setAttribute() {},
    });
    const items = entries.map(name => ({
        link: makeLink(name, name === library ? 'index.html' : `${name}.html`),
        querySelector() { return this.link; },
    }));
    if (parent) items[0].link.className = 'module-tree-parent';
    const tree = {
        children: items,
        querySelector: selector => selector === '.module-tree-root' && parent ? items[0] : null,
        replaceChildren(...children) { this.children = children; },
    };
    const home = { href: `file:///site/index.html`, dataset: {} };
    const document = {
        documentElement: { dataset: { projectBaseUrl: '../', packageBaseUrl: '../../' } },
        querySelector: selector => selector === '.module-context-tree' ? tree : null,
        querySelectorAll: () => [home, ...tree.children.map(item => item.link || item.children?.[0])
            .filter(link => link && 'psLibraryLink' in link.dataset)],
        createElement: tag => ({ tag, className: '', dataset: {}, append(...children) {
            this.children = children;
        }, setAttribute() {}, get textContent() { return this.children?.map(child => typeof child === 'string' ? child : child.textContent || '').join('') || ''; } }),
        createTextNode: text => text,
        addEventListener: (name, handler) => events.set(name, handler),
    };
    const window = {
        PS4HTMLLibraries: ['Test', 'ProofScript'],
        location: { get href() { return href; } },
        addEventListener: (name, handler) => events.set(name, handler),
    };
    vm.runInNewContext(source, { window, document, URL, encodeURIComponent, decodeURIComponent });
    return {tree, home, events, setHref(value) { href = value; }};
}

const shallow = run({ page: 'ProofScript/Builtin.html', library: 'ProofScript', entries: ['ProofScript', 'Zeta'] });
assert.deepEqual(shallow.tree.children.map(item => item.link?.textContent || item.children?.[0]?.textContent),
    ['ProofScript', 'Test', 'Zeta'], 'other library links sort alongside the visible root-level nodes');
assert.equal(new URL(shallow.tree.children[1].children[0].href).pathname, '/site/Test/index.html');
assert.equal(new URL(shallow.tree.children[1].children[0].href).searchParams.get('ps4html-language'), 'en');
assert.equal(new URL(shallow.home.href).searchParams.get('ps4html-sidebar-width'), '320');
shallow.setHref('file:///site/ProofScript/ProofScript/Builtin.html?ps4html-language=zh');
shallow.events.get('popstate')();
assert.equal(new URL(shallow.home.href).searchParams.get('ps4html-language'), 'zh');
assert.equal(new URL(shallow.tree.children[1].children[0].href).searchParams.has('ps-display-wrappers'), false);

const child = run({ page: 'ProofScript/Builtin.html', library: 'ProofScript', entries: ['ProofScript'], parent: true });
assert.equal(child.tree.children.length, 2, 'a visible library parent retains its other-library sibling');

const deep = run({ page: 'ProofScript/Builtin/Scripts.html', library: 'ProofScript', entries: ['Builtin'], parent: true });
assert.equal(deep.tree.children.length, 1, 'no library entries when the current library root is collapsed');
assert.equal(new URL(deep.home.href).pathname, '/site/index.html');
assert.equal(new URL(deep.home.href).searchParams.get('ps4html-language'), 'en');
console.log('Package navigation sorting, collapsed roots, and home link URL settings OK');
