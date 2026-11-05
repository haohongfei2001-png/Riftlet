'use strict';
// Additional raw views of changed, contextual controls. No production access.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const assert=require('node:assert/strict');
const {pathToFileURL}=require('node:url');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'..'),html=path.join(root,'Riftlet-Settings-Prototype.html');
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const runID=process.env.RUN_ID||new Date().toISOString().replace(/[:.]/g,'-');
assert(/^[a-zA-Z0-9_-]+$/.test(runID));
const out=path.join(root,'evidence',runID);assert(!fs.existsSync(out),'Do not overwrite evidence');
fs.mkdirSync(path.join(out,'screenshots'),{recursive:true});
const result={scope:'Raw Chromium visual evidence, synthetic local prototype only',runID,prototypeSHA256:hash(html),scriptSHA256:hash(__filename),startedAt:new Date().toISOString(),screenshots:[],errors:[]};
assert.equal(result.prototypeSHA256,JSON.parse(fs.readFileSync(path.join(root,'prototype/build-manifest.json'),'utf8')).output.sha256);
let browser,page;
async function click(name){await page.locator(`[data-action="${name}"]`).click();}
async function nav(name){await page.locator(`[data-page="${name}"]`).first().click();}
async function details(id){const d=page.locator('#'+id);if(!await d.evaluate(e=>e.open))await d.locator('summary').first().click();}
async function screenshot(id){
  const file='screenshots/'+id+'.png';await page.screenshot({path:path.join(out,file),fullPage:true});
  const metrics=await page.evaluate(()=>({
    viewport:{width:innerWidth,height:innerHeight},horizontalOverflow:document.documentElement.scrollWidth>innerWidth,
    controls:[...document.querySelectorAll('.placement-grid button,.native-switch,.button,.setting-description p')].filter(e=>e.getClientRects().length).slice(0,40).map(e=>{const r=e.getBoundingClientRect(),s=getComputedStyle(e);return{selector:e.className,text:e.textContent.trim().slice(0,48),width:r.width,height:r.height,font:s.fontSize,lineHeight:s.lineHeight,color:s.color,background:s.backgroundColor};})
  }));
  result.screenshots.push({id,file,sha256:hash(path.join(out,file)),state:await page.evaluate(()=>RiftletDesign.getState()),metrics});
}
(async()=>{
  try{
    browser=await chromium.launch({headless:true,...(process.env.BROWSER_EXECUTABLE?{executablePath:process.env.BROWSER_EXECUTABLE}:{})});
    result.browser=browser.version();
    const ctx=await browser.newContext({viewport:{width:1440,height:1100},deviceScaleFactor:1,locale:'zh-CN',timezoneId:'Asia/Shanghai'});
    await ctx.route(/^https?:/,async r=>{result.errors.push('Unexpected network: '+r.request().url());await r.abort();});
    page=await ctx.newPage();page.setDefaultTimeout(4000);page.on('pageerror',e=>result.errors.push(String(e)));
    await page.goto(pathToFileURL(html).href);
    for(const theme of ['light','dark']){
      await page.evaluate(t=>RiftletDesign.reset({theme:t}),theme);
      await details('custom-display');await details('fine-display');
      await page.locator('.settings-content').evaluate(e=>e.scrollTop=0);await screenshot(theme+'-display-custom');
      await page.locator('.settings-content').evaluate(e=>e.scrollTop=e.scrollHeight);await screenshot(theme+'-display-fine');
      await nav('motion');await details('fine-motion');await page.locator('.settings-content').evaluate(e=>e.scrollTop=e.scrollHeight);await screenshot(theme+'-motion-fine');
      await nav('general');await page.locator('#save-failure').check();await page.locator('[data-setting="paused"]').check();await page.locator('[data-setting="hidden"]').check();
      await nav('capture');await page.locator('[data-setting="entryEnabled"]').uncheck();
      await page.locator('[data-view="control"]').click();await screenshot(theme+'-three-stop-errors');
      await page.evaluate(t=>RiftletDesign.reset({theme:t}),theme);await nav('history');
      await page.locator('[data-setting="archivePreset"]').selectOption('custom');
      await page.locator('[data-setting="archiveHours"]').fill('2.5');await screenshot(theme+'-archive-editing');
      await click('save-archive');assert.equal((await page.evaluate(()=>RiftletDesign.getState())).archiveHours,2.5);
      await screenshot(theme+'-archive-first-click-saved');
      await page.locator('[data-setting="archiveHours"]').fill('8');await click('close-window');
      assert.equal((await page.evaluate(()=>RiftletDesign.getState())).modal,'unsaved');await screenshot(theme+'-close-confirmation');
      await click('cancel-modal');await nav('display');await details('custom-display');
      await page.locator('[data-config="fitWidth"]').fill('96');await page.locator('#save-failure').check();await click('apply-config');
      await screenshot(theme+'-layout-save-error');
      console.log('Captured changed views: '+theme);
    }
    // A compact Mac-sized viewport is separate from the main 1440px record.
    await page.setViewportSize({width:1100,height:820});await page.evaluate(()=>RiftletDesign.reset());
    await screenshot('compact-display');await nav('general');await screenshot('compact-general');
    assert.equal(result.errors.length,0);result.status='PASS';
  }catch(e){result.status='FAIL';result.errors.push(e.stack);console.error(e.message);}
  finally{if(browser)await browser.close();result.finishedAt=new Date().toISOString();fs.copyFileSync(__filename,path.join(out,'runner-snapshot.cjs'));fs.writeFileSync(path.join(out,'visual-results.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify({status:result.status,screenshots:result.screenshots.length,errors:result.errors}));process.exitCode=result.status==='PASS'?0:1;}
})();
