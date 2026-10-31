/* Browser-only synthetic reference checks. Not macOS or ChatGPT acceptance. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { chromium } = require(process.env.PLAYWRIGHT_PATH || 'playwright');

const output = process.env.RIFTLET_QA_ARTIFACTS;
const report = { scope: 'SYNTHETIC_BROWSER_REFERENCE_ONLY', cases: [], errors: [], network: [] };
report.inputs = Object.fromEntries(['source.html', 'Riftlet-Capture-Entry.html'].map(name => [name,
  createHash('sha256').update(fs.readFileSync(path.join(__dirname, name))).digest('hex')
]));
if (output) fs.mkdirSync(output, { recursive: true });
let browser;

async function load(options) {
  const page = await browser.newPage(options);
  page.on('pageerror', error => report.errors.push(error.message));
  await page.route(/^https?:/, route => { report.network.push(route.request().url()); return route.abort(); });
  await page.goto('file://' + path.join(__dirname, 'Riftlet-Capture-Entry.html'), { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  const root = page.locator('#riftlet-capture-reference-design');
  const desktop = root.locator('.rf-desktop');
  await desktop.waitFor();
  return { page, root, desktop };
}

async function shot(desktop, name) {
  if (output) await desktop.screenshot({ path: path.join(output, name + '.png') });
}

async function slots(root) {
  return root.locator('.rf-toolbar button[data-slot]').evaluateAll(elements => elements.map(element => {
    const rect = element.getBoundingClientRect();
    return { slot: element.dataset.slot, mode: element.dataset.mode, x: rect.x, y: rect.y, w: rect.width, h: rect.height };
  }));
}

async function point(page, locator) {
  const rect = await locator.boundingBox();
  assert(rect);
  return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
}

(async () => {
  browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_EXECUTABLE || undefined,
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
    env: { ...process.env }
  });
  const { page, root, desktop } = await load({ viewport: { width: 1060, height: 960 }, deviceScaleFactor: 2, colorScheme: 'light' });
  const phase = () => desktop.getAttribute('data-phase');
  const mode = () => desktop.getAttribute('data-mode');
  const total = async () => Number(await desktop.getAttribute('data-total'));
  const entry = root.locator('.rf-entry');
  const entryPoint = await point(page, entry);
  const entryRect = await entry.boundingBox();
  const local = async (x, y) => { const r = await desktop.boundingBox(); return { x: r.x + x, y: r.y + y }; };
  const click = p => page.mouse.click(p.x, p.y);
  const open = async () => { await click(entryPoint); assert.equal(await phase(), 'select'); };
  assert.equal(await desktop.getAttribute('data-simulation'), 'synthetic-only');
  await page.mouse.move(entryPoint.x, entryPoint.y); await page.waitForTimeout(700);
  await shot(desktop, 'closed-approved-material');
  await open(); assert.equal(await mode(), 'window'); assert.equal(await total(), 0);
  const originalSlots = await slots(root);
  assert.deepEqual(originalSlots.map(s => [s.slot, s.mode]), [['base', 'window'], ['near', 'region'], ['far', 'full']]);
  await page.waitForTimeout(220); await shot(desktop, 'fixed-slots-window');
  for (const [slot, expected] of [['near', 'region'], ['far', 'full'], ['base', 'window']]) {
    await root.locator('[data-slot="' + slot + '"]').click();
    assert.equal(await mode(), expected); assert.equal(await phase(), 'select');
    assert.equal(await desktop.getAttribute('data-active-slot'), slot);
    assert.deepEqual(await slots(root), originalSlots, 'Mode selection reassigned or moved a fixed slot');
    assert.equal(await total(), 0, 'Mode selection also triggered capture');
    await page.waitForTimeout(120);
    const cover = await root.locator('.rf-active-cover').boundingBox();
    const target = await root.locator('[data-slot="' + slot + '"]').boundingBox();
    assert(Math.abs(cover.x + cover.width / 2 - target.x - target.width / 2) < .1);
    assert(Math.abs(cover.y + cover.height / 2 - target.y - target.height / 2) < .1);
  }
  const note = root.locator('[data-window="notes"]');
  const noteRect = await note.boundingBox();
  const notePoint = { x: noteRect.x + noteRect.width / 2, y: noteRect.y + 80 };
  for (let n = 1; n <= 2; n++) {
    await click(notePoint);
    assert.equal(await total(), n, 'A window capture required another start or confirmation click');
    assert.equal(await phase(), 'select', 'Successful capture closed the session');
    assert.equal(await mode(), 'window');
    assert.deepEqual(await slots(root), originalSlots);
  }
  await root.locator('[data-slot="near"]').click();
  const a = await local(170, 190), b = await local(390, 315);
  await page.mouse.move(a.x, a.y); await page.mouse.down(); await page.mouse.move(b.x, b.y, { steps: 5 }); await page.mouse.up();
  assert.equal(await total(), 3, 'Region release did not capture immediately');
  assert.equal(await phase(), 'select');
  await page.waitForTimeout(130); await shot(desktop, 'continuous-queue-region');
  await root.locator('[data-slot="far"]').click();
  await click(await local(15, 410)); assert.equal(await total(), 4); assert.equal(await phase(), 'select');
  const thumb = root.locator('.rf-thumb').first();
  await thumb.hover(); assert.equal(await root.locator('.rf-camera').isVisible(), false);
  await thumb.click(); await page.waitForTimeout(120);
  assert.equal(await total(), 3, 'Thumbnail click fell through into capture or failed to consume');
  assert.equal(await phase(), 'select'); assert.equal(await mode(), 'full');
  assert.match(await root.locator('[data-status]').textContent(), /SIMULATED/);
  assert.deepEqual(await slots(root), originalSlots);
  await shot(desktop, 'continuous-queue-full');
  await root.locator('[data-slot="far"]').click();
  assert.equal(await phase(), 'rest', 'The active X did not cancel');
  await page.waitForTimeout(220);
  assert.deepEqual(await entry.boundingBox(), entryRect, 'Cancel moved the fixed default entry');
  await open(); assert.equal(await mode(), 'window');
  await root.locator('[data-more]').click(); await root.locator('[data-settings]').click();
  await root.locator('[data-default-mode="region"]').click();
  assert.deepEqual(await slots(root), originalSlots, 'Settings mutated positions during an active session');
  await page.keyboard.press('Escape'); await page.keyboard.press('Escape'); assert.equal(await phase(), 'rest');
  await open(); assert.equal(await mode(), 'region');
  assert.deepEqual((await slots(root)).map(s => [s.slot, s.mode]), [['base', 'region'], ['near', 'window'], ['far', 'full']]);
  const count = await total();
  await page.mouse.move(a.x, a.y); await page.mouse.down(); await page.mouse.move(b.x, b.y);
  await page.keyboard.press('Escape'); await page.mouse.up();
  assert.equal(await phase(), 'rest'); assert.equal(await total(), count, 'Cancelled selection created another image');
  report.cases.push('fixed mode positions', 'moving active X', 'two consecutive window captures', 'direct region release', 'direct full screen click', 'clickable queue during capture', 'cancel returns to fixed entry', 'settings apply next session', 'cancelled drag has no capture');
  await page.close();
  for (const touch of [false, true]) {
    const n = await load({ viewport: { width: 320, height: 960 }, deviceScaleFactor: 2, colorScheme: 'dark', hasTouch: touch, isMobile: touch });
    const e = n.root.locator('.rf-entry');
    if (touch) await e.tap(); else { const p = await point(n.page, e); await n.page.mouse.move(p.x, p.y); await n.page.mouse.click(p.x, p.y); }
    if (touch) await n.root.locator('[data-slot="near"]').tap(); else await n.root.locator('[data-slot="near"]').click();
    await n.page.waitForTimeout(220);
    const cover = await n.root.locator('.rf-active-cover').boundingBox(), near = await n.root.locator('[data-slot="near"]').boundingBox();
    assert(Math.abs(cover.y + cover.height / 2 - near.y - near.height / 2) < .1);
    if (touch) { await n.root.locator('[data-more]').tap(); await n.root.locator('[data-settings]').tap(); }
    else { await n.root.locator('[data-more]').click(); await n.root.locator('[data-settings]').click(); }
    const bounds = await n.desktop.boundingBox(), panel = await n.root.locator('.rf-options').boundingBox();
    assert(panel.x >= bounds.x && panel.x + panel.width <= bounds.x + bounds.width);
    assert(panel.y >= bounds.y && panel.y + panel.height <= bounds.y + bounds.height);
    await shot(n.desktop, 'narrow-' + (touch ? 'coarse' : 'fine'));
    report.cases.push('320px ' + (touch ? 'coarse' : 'fine') + ' active cover and settings');
    await n.page.close();
  }
  assert.deepEqual(report.network, [], 'The offline reference attempted an external request');
  assert.deepEqual(report.errors, [], 'Browser runtime errors');
  report.passed = true;
  if (output) fs.writeFileSync(path.join(output, 'verification.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
  await browser.close();
})().catch(async error => {
  report.passed = false; report.failure = String(error.stack || error);
  if (output) fs.writeFileSync(path.join(output, 'verification.json'), JSON.stringify(report, null, 2));
  console.error(error); if (browser) await browser.close(); process.exitCode = 1;
});
