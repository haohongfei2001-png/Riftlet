// Exercise the actual homepage in a fresh, offline browser context.
// NODE_PATH may point at an existing Playwright installation.
const assert = require('node:assert/strict');
const {resolve, sep} = require('node:path');
const {pathToFileURL} = require('node:url');
const {chromium} = require('playwright');

(async () => {
  const browser = await chromium.launch({headless: true,
    ...(process.env.CHROMIUM_EXECUTABLE && {executablePath: process.env.CHROMIUM_EXECUTABLE})});
  try {
    for (const locale of ['en-US', 'zh-CN']) {
      const context = await browser.newContext({locale, reducedMotion: 'reduce'});
      const page = await context.newPage();
      const root = pathToFileURL(resolve(__dirname, '..') + sep).href;
      await page.route('**/*', route => route.request().url().startsWith(root) ? route.continue() : route.abort());
      await page.goto(new URL('index.html', root).href);
      const alts = () => page.locator('img').evaluateAll(images => images.map(i => i.getAttribute('alt')));
      const first = await alts();
      for (const pass of [0, 1, 2]) {
        const english = (locale === 'en-US') === (pass % 2 === 0);
        assert.equal(await page.locator('html').getAttribute('lang'), english ? 'en' : 'zh-CN');
        const descriptions = await alts();
        assert.ok(descriptions.every(a => a !== null));
        assert.ok(descriptions.some(a => a.includes(english ? 'Taylor' : '泰勒')));
        assert.ok(descriptions.includes(english ? 'Portrait screenshot' : '纵向截图'));
        if (english) assert.ok(descriptions.every(a => !/\p{Script=Han}/u.test(a)));
        assert.ok(descriptions.includes(''), 'decorative images remain silent');
        if (pass === 2) assert.deepEqual(descriptions, first);
        else await page.locator('#language-toggle').click();
      }
      await context.close();
      console.log('PASS', locale, 'default, switch and switch back');
    }
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
