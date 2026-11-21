'use strict';

// Optional development probe. Run against a fresh, headless browser exclusively.
// Supply an installed puppeteer-core module and an installed Chromium executable.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const puppeteer = require(process.env.RIFTLET_PUPPETEER || 'puppeteer-core');
const sites = require('./public-entries.json').map(({id,entry})=>[id,entry]);

// Keep only counts, boolean capability signals, and fixed labels. A discovered
// input is an inventory observation, never a candidate for file assignment.
function inventory() {
  const shown = e => e.checkVisibility({opacityProperty:true,visibilityProperty:true}) &&
    e.getClientRects().length > 0 && !e.closest('[hidden],[inert],[aria-hidden="true"]');
  const word = [
    ['attach', /attach(?:ment|ments| files?)?|附件|添加文件|附加文件/i],
    ['upload', /upload(?: files?| images?)?|上传(?:图片|文件)?/i],
    ['add', /^(?:add|添加|新建)$/i],
    ['signIn', /log ?in|sign ?in|登录|登入/i],
    ['search', /search|搜索/i],
    ['research', /research|深度研究/i],
    ['image', /image|picture|图片|图像/i]
  ];
  const controls = [...document.querySelectorAll('button,[role=button],a[href],input[type=button],label')].filter(shown);
  const labels = Object.fromEntries(word.map(([key, re]) => [key,controls.filter(el=>
    [el.getAttribute('aria-label'),el.getAttribute('title'),el.innerText].some(s=>s && s.trim().length<=64 && re.test(s.trim()))).length]));
  const editors = [...document.querySelectorAll('textarea,[contenteditable="true"],[contenteditable="plaintext-only"],input[type=text]')].filter(shown);
  const inputs = [...document.querySelectorAll('input[type=file]')];
  function structure(el) {
    const result=[];
    for(let node=el;node && result.length<8;node=node.parentElement) {
      const classes=['ql-editor','ProseMirror','tiptap'].filter(key=>node.classList.contains(key));
      result.push({tag:node.localName,classes,role:['textbox','searchbox','button','form','dialog','main','group'].includes(node.getAttribute('role'))?node.getAttribute('role'):null});
    }
    return result;
  }
  const namedActions = controls.filter(el=>['attach','upload'].some(key=>
    word.find(([label])=>label===key)[1].test([el.getAttribute('aria-label'),el.getAttribute('title'),el.innerText?.slice(0,64)].filter(Boolean).join(' '))));
  const actionOwnership=namedActions.slice(0,8).map(el=>{
    let common=el;
    while(common && !editors.some(editor=>common.contains(editor))) common=common.parentElement;
    return {actionStructure:structure(el),sharedAncestor:common?.localName||null,
      editorsInSharedAncestor:editors.filter(editor=>common?.contains(editor)).length,
      fileInputsInSharedAncestor:inputs.filter(input=>common?.contains(input)).length,
      disabled:el.matches(':disabled,[aria-disabled="true"]')};
  });
  const text = document.body?.innerText || '';
  const challenge = /verify (?:that )?you are human|checking your browser|正在验证您是人类|security verification|performing security verification/i.test(text)
    || !!document.querySelector('iframe[src*="challenges.cloudflare.com"]');
  const hasLocation = /not (?:yet )?available in your (?:country|region)|not supported in your (?:country|region)|不支持.{0,6}地区/i.test(text);
  const route = location.pathname;
  return {finalOrigin: location.origin, routeFamily: route==='/'?'root':/^\/(?:new|app|chat)(?:\/|$)/.test(route)?route.split('/')[1]:
    /login|sign[-_]?in|account|oauth/i.test(route)?'account':'other',
    editorStructures:editors.slice(0,6).map(structure),actionOwnership,visibleEditableKinds:editors.map(e=>e.tagName.toLowerCase()).slice(0,10),visibleControlLabels:labels,
    fileInputs:inputs.map(e=>({multiple:e.multiple,disabled:e.disabled,visible:shown(e),
      acceptsImageHint:/image\/|\.(?:png|jpe?g|webp)\b/i.test(e.accept),
      soleEditorInSameActualForm:!!e.form && editors.filter(a=>e.form.contains(a)).length===1})).slice(0,12),
    challenge,regionNotice:hasLocation,visibleTextPresent:text.trim().length>0};
}

async function main() {
  const requested = process.argv.slice(2);
  if (requested.some(id=>!sites.some(([name])=>name===id))) throw Error('unknown provider');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-provider-public-'));
  let browser;
  try {
    browser = await puppeteer.launch({headless:true,pipe:true,userDataDir:dir,executablePath:process.env.RIFTLET_CHROME_BIN ||
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',defaultViewport:{width:1280,height:860}});
    const version = await browser.version();
    for(const [id,url] of sites.filter(([name])=>!requested.length || requested.includes(name))) {
      const context=await browser.createBrowserContext();
      try {
        const page=await context.newPage();
        let response,error;
        try {response=await page.goto(url,{waitUntil:'domcontentloaded',timeout:16000});}
        catch(e){error=e.name==='TimeoutError'?'navigation_timeout':(String(e.message).match(/net::ERR_[A-Z_]+/)||['navigation_error'])[0];}
        let view=null;
        for(let frame=0;frame<3;frame++) {
          try {view=await page.evaluate(inventory);} catch {view=null;}
          if(view?.challenge || view?.regionNotice || (frame>=1 && view?.visibleTextPresent)) break;
          await new Promise(done=>setTimeout(done,1350));
        }
        let observedProviderState=null;
        if(id==='gemini' && view?.finalOrigin==='https://gemini.google.com' && view.routeFamily==='app') {
          const source=fs.readFileSync(path.join(__dirname,'gemini-surface.mjs'),'utf8').replaceAll('export function ','function ');
          observedProviderState=await page.evaluate(source+'\ninspectGeminiSurface(document).state').catch(()=>null);
        }
        const origin=view?.finalOrigin;
        if(origin && !/^(?:https?:\/\/[a-z0-9.-]+|null|chrome-error:\/\/chromewebdata)$/i.test(origin)) view.finalOrigin='other';
        const status=response?.status() ?? null;
        const result=view?.challenge?'challenge_observed':view?.regionNotice?'region_notice_observed':
          !view?.visibleTextPresent || !origin?.startsWith('https://') || (status!==null && status>=400)?'page_unavailable':
          'public_page_observed';
        console.log(JSON.stringify({provider:id,requestedURL:url,recordedAt:new Date().toISOString(),browser:version,anon:true,
          result,httpStatus:status,navigationError:error??null,view,observedProviderState,authenticatedDraftAcceptance:'NOT_RUN'}));
      } finally {await context.close();}
    }
  } finally {try {if(browser) await browser.close();} finally {fs.rmSync(dir,{recursive:true,force:true});}}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
