/* Owned, ephemeral headless-browser regression of the delivered offline HTML.
 * No connection to an existing browser, user profile, native App or chat.
 * PLAYWRIGHT_MODULE selects a separately installed playwright/playwright-core.
 * HEADLESS_BROWSER must identify its isolated chrome-headless-shell executable.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {pathToFileURL} = require('node:url');
const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const option = (name, fallback) => args.includes(name) ? args[args.indexOf(name) + 1] : fallback;
const html = path.resolve(option('--html', path.join(root, 'exports/Riftlet-Experience-Prototype.html')));
const out = path.resolve(option('--out', path.join(root, 'evidence/export-repair-20261107/headless')));
if (fs.existsSync(path.join(out, 'results.json'))) throw new Error('Choose a fresh --out directory; previous results are immutable.');
fs.mkdirSync(out, {recursive: true});
const executable = process.env.HEADLESS_BROWSER;
if (!executable || !/^chrome-headless-shell(?:\.exe)?$/.test(path.basename(executable))) {
  throw new Error('HEADLESS_BROWSER must point to an owned test chrome-headless-shell, never a user browser.');
}
const moduleName = process.env.PLAYWRIGHT_MODULE || 'playwright';
const {chromium} = require(moduleName);
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const relative = file => path.relative(root, file).split(path.sep).join('/');
const report = {schemaVersion: 1, target: relative(html), targetSHA256: sha(fs.readFileSync(html)),
  script: relative(__filename), scriptSHA256: sha(fs.readFileSync(__filename)),
  scope: 'Offline synthetic web prototype only; no native App or real attachment verification.',
  runtime: {headless: true, ownedEphemeralProfile: true, userProfile: false, externalBrowserConnection: false},
  cases: [], screenshots: [], pageErrors: [], externalRequests: []};
let browser, page;
async function shot(name) {
  const file = path.join(out, name + '.png');
  await page.screenshot({path: file, fullPage: true, animations: 'disabled'});
  const size = await page.evaluate(() => ({width: document.documentElement.scrollWidth, height: document.documentElement.scrollHeight, deviceScaleFactor: devicePixelRatio}));
  report.screenshots.push({file: path.basename(file), sha256: sha(fs.readFileSync(file)), ...size});
}
async function check(name, work) {
  const before = report.pageErrors.length;
  try {
    await work();
    assert.equal(report.pageErrors.length, before, 'No JavaScript error during this interaction');
    report.cases.push({name, result: 'PASS'});
  } catch (error) {
    report.cases.push({name, result: 'FAIL', message: String(error.message).slice(0, 1600)});
    await shot('failure-' + report.cases.length).catch(() => {});
  }
}
const value = selector => page.locator(selector).inputValue();
const state = () => page.evaluate(() => window.RiftPrototype.exportState());
const historyUI = () => page.evaluate(() => ({
  selected: window.RiftPrototype.state.selectedHistory,
  query: document.querySelector('#history-query')?.value,
  filter: document.querySelector('#history-filter')?.value,
  ids: [...document.querySelectorAll('.history-grid-area [data-history-id]')].map(e => e.dataset.historyId)
}));
const scene = name => page.locator(`[data-scene="${name}"]`).click();
const sameRecords = (before, after) => {
  assert.deepEqual(after.queue, before.queue, 'Style and navigation preserve queue IDs');
  assert.deepEqual(after.history, before.history, 'Style and navigation preserve record IDs/status');
  assert.deepEqual(after.attached, before.attached, 'No attachments are added by history actions');
  assert.equal(after.draft, before.draft, 'History actions preserve the synthetic draft');
};
(async () => {
  try {
    browser = await chromium.launch({headless: true, executablePath: executable, args: ['--disable-background-networking']});
    report.runtime.browser = await browser.version();
    report.runtime.playwright = require(path.join(path.dirname(require.resolve(moduleName)), 'package.json')).version;
    const context = await browser.newContext({viewport: {width: 1200, height: 1000}, deviceScaleFactor: 1, colorScheme: 'light'});
    page = await context.newPage();
    page.setDefaultTimeout(5000);
    page.on('pageerror', error => report.pageErrors.push({name: error.name, message: error.message}));
    await context.route('**/*', route => {
      const url = route.request().url();
      if (/^(file:|data:|blob:)/.test(url)) return route.continue();
      report.externalRequests.push({origin: new URL(url).origin, resourceType: route.request().resourceType()});
      return route.abort();
    });
    await page.goto(pathToFileURL(html).href);
    await check('standalone initializes without JavaScript errors', async () => {
      assert.deepEqual(report.pageErrors, [], 'No parse/runtime error on load');
      await page.waitForFunction(() => typeof window.RiftPrototype?.exportState === 'function');
      assert.equal(await page.locator('[data-scene]').count(), 8);
    });
    if (report.cases[0].result !== 'PASS') return;
    const initial = await state();
    await check('history default and both style options', async () => {
      await scene('history');
      assert.equal(await value('#history-style'), 'current');
      assert.deepEqual(await page.locator('#history-style option').evaluateAll(es => es.map(e => e.value)), ['current', 'imageGrid']);
      assert.ok(await page.locator('.history-grid-area [data-history-id]').count() > 1);
    });
    await check('selection and record identity survive round-trip style switches', async () => {
      await page.locator('.history-grid-area [data-history-id]').nth(1).click();
      const before = await historyUI();
      for (const style of ['imageGrid', 'current']) {
        await page.locator('#history-style').selectOption(style);
        assert.equal(await page.locator('.history-grid-area').getAttribute('data-history-style'), style);
        assert.deepEqual(await historyUI(), before);
      }
      sameRecords(initial, await state());
    });
    await check('status filter and real search input survive style switches', async () => {
      await page.locator('#history-filter').selectOption('archived');
      const name = await page.locator('.history-grid-area .history-item-caption strong').first().innerText();
      await page.locator('#history-query').fill(name);
      const before = await historyUI();
      assert.ok(before.ids.length > 0);
      await page.locator('#history-style').selectOption('imageGrid');
      assert.deepEqual(await historyUI(), before);
      await page.locator('#history-style').selectOption('current');
      assert.deepEqual(await historyUI(), before);
    });
    await check('empty search remains empty in both styles', async () => {
      await page.locator('#history-query').fill('synthetic-no-match-20261107');
      for (const style of ['current', 'imageGrid']) {
        await page.locator('#history-style').selectOption(style);
        assert.equal(await page.locator('.history-grid-area .history-empty').count(), 1);
        assert.equal(await page.locator('.history-grid-area [data-history-id]').count(), 0);
      }
      await page.locator('#history-query').fill('');
      await page.locator('#history-filter').selectOption('all');
    });
    await check('all six settings pages remain reachable by their controls', async () => {
      await scene('settings');
      for (const name of ['general', 'display', 'capture', 'motion', 'history', 'help']) {
        await page.locator(`[data-setting-page="${name}"]`).click();
        assert.equal(await page.locator('[data-st-page]').getAttribute('data-st-page'), name);
        assert.ok((await page.locator('.st-page-heading h2').innerText()).length > 0);
      }
    });
    await check('settings and history selectors share the same preference both ways', async () => {
      await page.locator('[data-setting-page="history"]').click();
      await page.locator('[data-st-key="historyDisplayStyle"]').selectOption('current');
      await scene('history');
      assert.equal(await value('#history-style'), 'current');
      await page.locator('#history-style').selectOption('imageGrid');
      await page.locator('[data-action="history-settings"]').first().click();
      assert.equal(await value('[data-st-key="historyDisplayStyle"]'), 'imageGrid');
      await page.locator('[data-st-key="historyDisplayStyle"]').selectOption('current');
      await scene('history');
      assert.equal(await value('#history-style'), 'current');
      sameRecords(initial, await state());
    });
    await check('original-image modal zoom and Escape preserve selection', async () => {
      const selected = (await historyUI()).selected;
      await page.locator('[data-action="original"]').click();
      assert.equal(await page.locator('[role="dialog"]').count(), 1);
      await page.locator('#original-zoom').selectOption('100');
      assert.equal(await value('#original-zoom'), '100');
      await page.keyboard.press('Escape');
      assert.equal(await page.locator('[role="dialog"]').count(), 0);
      assert.equal((await historyUI()).selected, selected);
    });
    await check('feedback modal traps focus and closes with Escape', async () => {
      await scene('control');
      await page.locator('[data-action="feedback"]').click();
      await page.waitForFunction(() => document.activeElement?.id === 'feedback-input');
      await page.locator('#feedback-input').fill('Synthetic offline feedback; never transmitted.');
      for (let i = 0; i < 5; i++) {
        await page.keyboard.press('Tab');
        assert.equal(await page.evaluate(() => !!document.activeElement?.closest('[role="dialog"]')), true);
      }
      await page.keyboard.press('Escape');
      assert.equal(await page.locator('[role="dialog"]').count(), 0);
      assert.equal(await page.evaluate(() => document.activeElement?.dataset.action), 'feedback');
      sameRecords(initial, await state());
    });
    await check('all historical comparison images load and fit through the double-dollar helper', async () => {
      await scene('compare');
      const options = await page.locator('#compare-selector option').evaluateAll(es => es.map(e => e.value));
      assert.equal(options.length, 4);
      for (const key of options) {
        await page.locator('#compare-selector').selectOption(key);
        await page.waitForFunction(() => [...document.querySelectorAll('[data-compare-size]')].every(e => e.complete && e.naturalWidth > 0 && parseFloat(e.style.width) > 0));
        assert.equal(await page.locator('[data-compare-size]').count(), 2);
      }
    });
    await check('side-by-side variants share selected record', async () => {
      await scene('historyVariants');
      const id = await page.locator('.history-variant-tile').nth(1).getAttribute('data-history-id');
      await page.locator(`.history-variant-row[data-history-id="${id}"]`).click();
      assert.equal(await page.locator('.history-variant-row.selected').getAttribute('data-history-id'), id);
      assert.equal(await page.locator('.history-variant-tile.selected').getAttribute('data-history-id'), id);
      assert.equal(await page.locator('.history-variant-detail').count(), 2);
      sameRecords(initial, await state());
    });
    await check('light/dark history styles and settings render with original brand', async () => {
      for (const theme of ['light', 'dark']) {
        if (await page.locator('#riftlet-design').getAttribute('data-theme') !== theme) await page.locator('[data-action="theme"]').click();
        await scene('history');
        for (const style of ['current', 'imageGrid']) {
          await page.locator('#history-style').selectOption(style);
          assert.equal(await page.locator('#riftlet-design').getAttribute('data-theme'), theme);
          await shot(`history-${style}-${theme}`);
        }
        await scene('historyVariants');
        await shot(`history-variants-${theme}`);
        await scene('settings');
        await page.locator('[data-setting-page="history"]').click();
        await shot(`settings-history-${theme}`);
      }
      const expected = 'data:image/svg+xml;base64,' + fs.readFileSync(path.join(root, 'prototype/assets/riftlet.svg')).toString('base64');
      assert.equal(await page.locator('.viewer-brand .brand-mark img').getAttribute('src'), expected);
      sameRecords(initial, await state());
    });
    await check('offline delivery makes no external requests or JavaScript errors', async () => {
      assert.deepEqual(report.pageErrors, []);
      assert.deepEqual(report.externalRequests, []);
    });
  } catch (error) {
    report.fatal = String(error.message).slice(0, 1600);
  } finally {
    report.passed = report.cases.filter(c => c.result === 'PASS').length;
    report.failed = report.cases.filter(c => c.result === 'FAIL').length;
    report.result = !report.fatal && !report.failed && report.cases.length === 13 && !report.pageErrors.length && !report.externalRequests.length ? 'PASS' : 'FAIL';
    fs.writeFileSync(path.join(out, 'results.json'), JSON.stringify(report, null, 2) + '\n');
    if (browser) await browser.close();
    console.log(JSON.stringify({result: report.result, passed: report.passed, failed: report.failed, errors: report.pageErrors, fatal: report.fatal, output: relative(out)}));
    if (report.result !== 'PASS') process.exitCode = 1;
  }
})();
