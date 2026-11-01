// Executed in CI against the built local site; no production site is contacted.
const { chromium } = require(process.env.DOCS_PLAYWRIGHT || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
(async () => {
  const browser = await chromium.launch({headless: true});
  const context = await browser.newContext({viewport: {width: 1440, height: 1000}, deviceScaleFactor: 2, reducedMotion: 'reduce', permissions: ['clipboard-read', 'clipboard-write']});
  const page = await context.newPage();
  const failures = [];
  page.on('pageerror', error => failures.push(error.message));
  const origin = 'http://127.0.0.1:8000';
  const output = process.env.DOCS_SCREENSHOTS || '/tmp/like-docs-screenshots';
  fs.mkdirSync(output, {recursive: true});
  await page.goto(origin + '/like/');
  await page.getByRole('heading', {name: 'One networking layer. Your state management.'}).waitFor();
  await page.screenshot({path: output + '/desktop.png', fullPage: true});
  await page.getByRole('button', {name: 'Search documentation', exact: true}).click();
  await page.getByRole('searchbox').fill('slow internet');
  const result = page.locator('#search-results').getByRole('link').filter({hasText: 'Connectivity & toast hooks'});
  await result.waitFor();
  await result.click();
  await page.getByRole('heading', {name: 'Connectivity & toast hooks', exact: true}).waitFor();
  await page.getByRole('button', {name: 'Copy code example'}).first().click();
  assert.match(await page.evaluate(() => navigator.clipboard.readText()), /LikeToastConfig/);
  await page.getByRole('button', {name: 'Copy page', exact: true}).click();
  await page.waitForFunction(async () => (await navigator.clipboard.readText()).startsWith('# Connectivity'));
  const markdownResponse = await page.request.get(origin + '/like/markdown/connectivity.md');
  assert.equal(markdownResponse.status(), 200);
  assert.match(await markdownResponse.text(), /slowInternet/);
  await page.getByRole('button', {name: 'Switch color theme'}).click();
  const theme = await page.locator('html').getAttribute('data-theme');
  await page.reload();
  assert.equal(await page.locator('html').getAttribute('data-theme'), theme);
  await page.screenshot({path: output + '/guide.png', fullPage: true});
  await page.keyboard.press('Control+k');
  await page.getByRole('searchbox').fill('zzzz-no-such-guide');
  await page.getByRole('status').filter({hasText: 'No matching guides'}).waitFor();
  await page.keyboard.press('Escape');
  await page.setViewportSize({width: 390, height: 844});
  await page.goto(origin + '/like/');
  await page.getByRole('button', {name: 'Menu', exact: true}).click();
  assert.equal(await page.locator('#menu').getAttribute('aria-expanded'), 'true');
  await page.getByRole('navigation', {name: 'Documentation', exact: true}).getByRole('link', {name: 'Quick start', exact: true}).click();
  await page.getByRole('heading', {name: 'Quick start', exact: true}).waitFor();
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);
  await page.screenshot({path: output + '/mobile.png', fullPage: true});
  // Every guide must reflow without whole-page horizontal scrolling.
  const manifest = await (await page.request.get(origin + '/like/manifest.json')).json();
  for (const width of [320, 360, 390, 768, 980, 1024, 1280, 1440, 1920]) {
    await page.setViewportSize({width, height: 900});
    for (const guide of manifest.pages) {
      await page.goto(origin + guide.url);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), true, guide.slug + ' overflows at ' + width);
    }
  }
  await page.setViewportSize({width: 1440, height: 1000});
  await page.goto(origin + '/like/quickstart/');
  const sizes = await page.evaluate(() => Object.fromEntries(['body', 'pre code', 'table', '#sidebar a'].map(selector => {
    const el = document.querySelector(selector);
    return [selector, el ? parseFloat(getComputedStyle(el).fontSize) : null];
  })));
  assert.ok(sizes.body >= 17);
  assert.ok(sizes['pre code'] >= 14);
  assert.ok(sizes['#sidebar a'] >= 15);
  await page.goto(origin + '/like/');
  assert.ok(await page.locator('table').evaluate(el => parseFloat(getComputedStyle(el).fontSize)) >= 15);
  await page.screenshot({path: output + '/desktop-readable.png', fullPage: true});
  // Text resizing must preserve usable layout and access to navigation.
  await page.addStyleTag({content: 'html { font-size: 200%; }'});
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), true);
  await page.setViewportSize({width: 390, height: 844});
  await page.goto(origin + '/like/quickstart/');
  await page.getByRole('button', {name: 'Menu', exact: true}).click();
  await page.getByRole('button', {name: 'Close menu', exact: true}).waitFor();
  assert.equal(await page.locator('main').evaluate(el => el.inert), true);
  await page.keyboard.press('Escape');
  assert.equal(await page.locator('main').evaluate(el => el.inert), false);
  assert.equal(await page.locator('#menu').getAttribute('aria-expanded'), 'false');
  for (const name of ['Menu', 'Switch color theme', 'Copy page']) {
    const size = await page.getByRole('button', {name, exact: true}).boundingBox();
    assert.ok(size.height >= 44, name + ' touch target too small');
  }
  await page.screenshot({path: output + '/mobile-readable.png', fullPage: true});
  assert.deepEqual(failures, []);
  await browser.close();
  console.log('Desktop/mobile navigation, search, empty state, theme, clipboard and Markdown checks passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
