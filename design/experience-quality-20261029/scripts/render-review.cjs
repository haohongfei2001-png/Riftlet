/* Offline visual export. This renders a design prototype, never the native App. */
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const executablePath = process.env.RIFTLET_REVIEW_CHROMIUM || '/tmp/riftlet-chrome-131/chrome-headless-shell-linux64/chrome-headless-shell';
const fontPath = process.env.RIFTLET_REVIEW_FONT || '/tmp/riftlet-review-cjk-subset.otf';
const cases = [
 ['01-first-use-local','start','local',false],
 ['02-first-use-access','start','source',false],
 ['03-first-use-candidate','start','candidate',false],
 ['04-capture-countdown','capture','switched',false],
 ['05-capture-revoked','capture','revoked',true],
 ['06-attach-rejected','attach','rejected',false],
 ['07-attach-prepared','attach','prepared',true],
 ['08-recovery-permission','settings','permission',false],
 ['09-display-fallback','settings','display',true],
 ['10-relaunch-state','settings','relaunch',false],
 ['11-history-unknown','history','unknown',false],
 ['12-history-preview','history','preview',true],
 ['13-feedback-offline','feedback','offline',false],
 ['14-feedback-ime','feedback','ime',true],
 ['15-feedback-delete','feedback','remote',false],
 ['16-feedback-save-failure','feedback','savefail',false]
];
(async () => {
 const browser = await chromium.launch({executablePath,headless:true,args:['--no-sandbox']});
 const page = await browser.newPage({viewport:{width:1440,height:1050},deviceScaleFactor:1});
 await page.route('**/*',r=>r.abort());
 const errors=[]; page.on('pageerror',e=>errors.push(e.message));
 await page.setContent(fs.readFileSync(path.join(root,'Riftlet-Experience-Prototype.html'),'utf8'),{waitUntil:'load'});
 if(fs.existsSync(fontPath)){
  const data=fs.readFileSync(fontPath).toString('base64');
  await page.addStyleTag({content:`@font-face{font-family:ReviewCJK;src:url(data:font/otf;base64,${data}) format('opentype');font-display:block}body{--font:-apple-system,BlinkMacSystemFont,'PingFang SC',ReviewCJK,sans-serif}`});
 }
 await page.evaluate(()=>document.fonts.ready);
 const exports=[];
 for(const [name,scene,scenario,dark] of cases){
  console.log('Rendering '+name);
  await page.evaluate(({scene,scenario,dark})=>{riftletReview.selectScene(scene,scenario);riftletReview.setTheme(dark)}, {scene,scenario,dark});
  if(name==='15-feedback-delete')await page.locator('[data-action="deleteFeedback:1"]').click();
  await page.evaluate(()=>document.fonts.ready);
  const data=await page.evaluate(()=>({width:document.documentElement.scrollWidth,height:document.documentElement.scrollHeight,
   windowBounds:[...document.querySelectorAll('.mock-window')].map(e=>({label:e.getAttribute('aria-label'),w:e.offsetWidth,h:e.offsetHeight})),
   text:document.querySelector('#product').innerText,state:riftletReview.getState()}));
  await page.screenshot({path:path.join(root,'boards',`${name}.png`),fullPage:true,animations:'disabled',timeout:20000});
  exports.push({name,scene,scenario,appearance:dark?'dark':'light',...data});
 }
 fs.writeFileSync(path.join(root,'evidence','prototype-renders.json'),JSON.stringify({scope:'DESIGN_PROTOTYPE_ONLY',sourceSHA256:require('crypto').createHash('sha256').update(fs.readFileSync(path.join(root,'Riftlet-Experience-Prototype.html'))).digest('hex'),network:'blocked',errors,exports},null,2));
 await browser.close();
 if(errors.length)throw new Error(errors.join('\n'));
 console.log(JSON.stringify({boards:exports.length,errors,dimensions:exports.map(x=>[x.name,x.width,x.height])}));
})().catch(e=>{console.error(e);process.exit(1)});
