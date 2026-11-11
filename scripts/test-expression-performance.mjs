// Requires Playwright and Chrome, plus a built Test.PageScriptBoard page.
// PLAYWRIGHT_MODULE may point to an external Playwright index.mjs.
// KATEX_DIST optionally supplies KaTeX 0.16.9 locally for offline runs.
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const browser = await chromium.launch({channel: 'chrome', headless: true});
try {
    const page = await browser.newPage({viewport: {width: 1440, height: 1000}});
    if (process.env.KATEX_DIST) await page.route('https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/**', route =>
        route.fulfill({path: `${process.env.KATEX_DIST}/${route.request().url().split('/dist/')[1]}`}));
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => {
        window.perfCounts = {reads: 0, layouts: 0, indexes: 0};
        for (const prototype of [Element.prototype, Range.prototype]) {
            for (const key of ['getBoundingClientRect', 'getClientRects']) {
                const original = prototype[key];
                prototype[key] = function (...args) { window.perfCounts.reads++; return original.apply(this, args); };
            }
        }
        const query = document.querySelectorAll;
        document.querySelectorAll = function (selector) {
            if (selector === '[data-ps-expr-fragment]') window.perfCounts.indexes++;
            return query.call(this, selector);
        };
        document.addEventListener('ps4html:layoutchange', () => window.perfCounts.layouts++);
    });
    await page.goto(pathToFileURL(process.argv[2] || `${process.cwd()}/.PS4HTML/build/Test/Test/PageScriptBoard.html`).href);
    await page.waitForFunction(() => document.querySelector('.katex-html'));
    await page.waitForTimeout(1000);
    const reset = () => page.evaluate(() => { window.perfCounts = {reads: 0, layouts: 0, indexes: 0}; });
    await reset();
    await page.mouse.move(30, 400);
    await page.waitForTimeout(100);
    const blank = await page.evaluate(() => window.perfCounts);
    assert.equal(blank.reads, 0, 'sidebar pointer must not measure page expressions');
    assert.equal(blank.indexes, 0);
    const point = await page.evaluate(() => {
        for (const node of document.querySelectorAll('[data-ps-expr-fragment]')) {
            const rect = node.getBoundingClientRect();
            if (rect.width && rect.top > 200 && rect.bottom < 800 && !node.closest('.proof-dashboard-reveal'))
                return {x: (rect.left + rect.right) / 2, y: (rect.top + rect.bottom) / 2};
        }
    });
    assert.ok(point, 'fixture has a visible formula');
    await reset();
    await page.mouse.move(point.x, point.y);
    await page.waitForTimeout(600); // Includes hover transitionend, not just pointer dispatch.
    const hover = await page.evaluate(() => ({...window.perfCounts,
        anchor: window.PS4HTMLExpressionInteractions.getState().anchor,
        boxes: document.querySelectorAll('.ps-expression-highlight').length}));
    assert.ok(hover.anchor);
    assert.ok(hover.boxes);
    assert.equal(hover.layouts, 0, 'hover transitions must not dispatch layout events');
    assert.equal(hover.indexes, 0, 'hover must not rebuild the semantic index');
    await page.mouse.click(point.x, point.y);
    assert.ok(await page.evaluate(() => window.PS4HTMLExpressionInteractions.getState().pinned));
    await page.mouse.click(30, 400);
    const header = page.locator('.proof-step-header:visible').first();
    await header.focus();
    await page.keyboard.press('Enter');
    await page.waitForTimeout(400);
    assert.equal(await header.getAttribute('aria-expanded'), 'true');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(400);
    assert.equal(await header.getAttribute('aria-expanded'), 'false');
    assert.deepEqual(errors, []);
    console.log({blank, hover});
    console.log('Real-browser hover performance and dashboard interactions OK');
} finally {
    await browser.close();
}
