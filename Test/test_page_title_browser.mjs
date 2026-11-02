// Build the gallery with `lake build +Test.PageTitle:ps4html` before running.
// PLAYWRIGHT_MODULE and PLAYWRIGHT_CHANNEL may select an existing installation.
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const browser = await chromium.launch({
  headless: true,
  ...(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {}),
});

try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
  await page.route('https://**/*', route => route.abort());
  const gallery = resolve(process.argv[2] ||
    '.PS4HTML/build/ProofScript/.modules/Test.PageTitle/Test/PageTitle.html');
  await page.goto(pathToFileURL(gallery).href, { waitUntil: 'load' });
  const titles = await page.locator('.page-title').evaluateAll(nodes => nodes.map(node => ({
    level: Number(node.dataset.titleLevel),
    size: Number.parseFloat(getComputedStyle(node).fontSize),
    arrows: node.querySelector('.page-title-depth')?.textContent || '',
  })));
  assert.deepEqual(titles.map(title => title.level), [1, 2, 3, 4, 5, 6, 7, 8, 2, 64, 2]);
  for (const title of titles) {
    assert.equal(title.size, [34, 27, 21, 17, 15][Math.min(5, title.level) - 1]);
    assert.equal(title.arrows, '→'.repeat(Math.max(0, title.level - 5)));
  }
  assert.equal(await page.locator('.proof-text-card :is(h1,h2,h3,h4,h5,h6)').count(), 0);
  assert.equal(await page.locator('.unresolved-reference').count(), 0);
  assert.equal(await page.evaluate(() =>
    document.documentElement.scrollWidth <= window.innerWidth), true);
  if (process.env.TITLE_TEST_SCREENSHOT) {
    await page.screenshot({ path: process.env.TITLE_TEST_SCREENSHOT, fullPage: true });
  }
  await page.locator('a[href$="#heading-title-six"]').first().click();
  assert.equal(await page.evaluate(() => location.hash), '#heading-title-six');
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(await page.locator('[data-title-level="1"]').evaluate(node =>
    getComputedStyle(node).fontSize), '28px');
  assert.equal(await page.locator('[data-title-level="8"]').evaluate(node =>
    getComputedStyle(node).fontSize), '15px');
  console.log('PASS title font sizes, depth arrows, layout and reference navigation in Chromium');
} finally {
  await browser.close();
}
