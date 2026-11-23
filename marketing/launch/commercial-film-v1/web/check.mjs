/** Run with Playwright installed locally or NODE_PATH pointing at its directory. */
import {createRequire} from 'node:module'
import {fileURLToPath, pathToFileURL} from 'node:url'
import {dirname, join} from 'node:path'
import {mkdir} from 'node:fs/promises'
import assert from 'node:assert/strict'

const require = createRequire(import.meta.url)
const {chromium} = require('playwright')
const root = dirname(fileURLToPath(import.meta.url))
const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.CHROMIUM_BIN || undefined
})
const reports = []
const previews = join(root, 'previews')
await mkdir(previews, {recursive:true})
try {
  for (const [lang, file, sentence] of [
    ['zh-CN','index.html','和上周比呢？'],
    ['en','en.html','How did it compare with last week?']
  ]) {
    for (const [device, width, height] of [['desktop',1440,900],['mobile',390,844]]) {
      const page = await browser.newPage({viewport:{width, height}, deviceScaleFactor:device === 'mobile' ? 2 : 1})
      const errors = []
      page.on('pageerror', err => errors.push(err.message))
      await page.goto(pathToFileURL(join(root,file)).href)
      await page.evaluate(() => document.fonts.ready)
      const pageLang = await page.locator('html').getAttribute('lang')
      assert.equal(pageLang,lang)
      const oldSrc = await page.locator('.old img').getAttribute('src')
      const original = await page.locator('textarea').inputValue()
      const startMessage = await page.locator('#state').innerText()
      const edge = page.locator('.edge')
      assert.ok(await edge.isVisible())
      assert.ok(await page.locator('.new').isHidden())
      assert.equal(await page.locator('.watch').getAttribute('href'),'../film/'+lang+'/master.mp4')
      assert.match(await page.locator('.get').getAttribute('href'),/v1\.0\.5\/Riftlet-1\.0\.5\.dmg$/)
      assert.equal(await page.locator('meta[property="og:image"]').getAttribute('content'),'../social/share/'+lang+'.jpg')
      const bounds = await page.evaluate(() => ({
        scrollWidth: Math.max(document.documentElement.scrollWidth,document.body.scrollWidth),
        innerWidth, text:document.querySelector('h1').getBoundingClientRect().toJSON(),
        illustration:document.querySelector('.desk').getBoundingClientRect().toJSON(),
        missingImages:[...document.images].filter(img => !img.complete || !img.naturalWidth).length
      }))
      assert.ok(bounds.scrollWidth <= width,'Horizontal overflow')
      assert.ok(bounds.illustration.top < height && bounds.text.bottom < height,'Hero below fold')
      assert.equal(bounds.missingImages,0)
      await page.screenshot({path:join(previews,lang+'-'+device+'.jpg'),type:'jpeg',quality:91})
      const text = page.locator('textarea')
      await text.fill(original+' '+sentence)
      await text.evaluate(el => el.setSelectionRange(2,4))
      await edge.click()
      assert.ok(await page.locator('.new').isVisible())
      assert.equal(await page.locator('.old img').getAttribute('src'),oldSrc)
      assert.equal(await text.inputValue(),original+' '+sentence)
      assert.deepEqual(await text.evaluate(el => [el.selectionStart, el.selectionEnd]),[2,4])
      assert.ok(await text.evaluate(el => el === document.activeElement))
      assert.ok(await edge.isDisabled())
      assert.equal(await page.locator('form').count(),0)
      assert.notEqual(await page.locator('#state').innerText(),startMessage)
      await page.locator('.reset').click()
      assert.ok(await page.locator('.new').isHidden())
      assert.equal(await text.inputValue(),original)
      assert.ok(await edge.isEnabled())
      assert.equal(await page.locator('#state').innerText(),startMessage)
      await edge.press('Enter')
      assert.ok(await page.locator('.new').isVisible())
      await page.locator('.switch').click()
      assert.equal(await page.locator('html').getAttribute('lang'),lang === 'en' ? 'zh-CN':'en')
      assert.deepEqual(errors,[])
      reports.push({lang,device,viewport:[width,height],h1Bottom:Math.round(bounds.text.bottom),demoTop:Math.round(bounds.illustration.top),demoBottom:Math.round(bounds.illustration.bottom)})
      await page.close()
    }
  }
} finally {
  await browser.close()
}
console.log(JSON.stringify(reports,null,2))
