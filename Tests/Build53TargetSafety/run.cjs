'use strict';
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const {bounded,cleanupOwnedChrome,closeLoopbackServer} = require('../WebPageProgram/native-chrome-cleanup.cjs');
const {FixtureDriver} = require('./driver.cjs');
const baselineHash = '50b0d16d10f38c688ce33189df55ad3da6588b4c7006b710777f30340dc55ed7';
const asset = 'Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js';
const root = process.env.RIFTLET_SAFETY_SOURCE_ROOT;
const packaged = process.env.RIFTLET_SAFETY_ASSET_PATH;
assert.ok(!(root && packaged), 'select one product source');
if (packaged) assert.ok(path.isAbsolute(packaged), 'require absolute package resource path');
const expected = root || packaged ? process.env.RIFTLET_SAFETY_EXPECT_SHA256 : baselineHash;
const program = fs.readFileSync(packaged || path.resolve(root || path.join(__dirname,'../..'),asset));
assert.match(expected || '', /^[a-f0-9]{64}$/);
assert.equal(crypto.createHash('sha256').update(program).digest('hex'),expected);
const pageJS = fs.readFileSync(path.join(__dirname,'page.js'));
const documentHTML = '<!doctype html><meta charset=utf-8><body><form data-composer-layout>' +
  '<div id="prompt-textarea" contenteditable="true" role="textbox">Original QA draft text</div>' +
  '<input type="file" hidden accept="image/*"><div role="button" data-file-name="existing.png"><img alt="existing.png"></div>' +
  '<button type="submit">Send</button></form><script src="../page.js"></script>';
const variants = ['control','tabInactive','tabABA','sameURLDocument','reload','historyABA','pagehide','bfcache',
  'editorReplacement','closedTarget','menuABA','rebuildDuringInput','portalMoveDuringInput'];
const binaries = {chrome:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  edge:'/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'};
const sleep = ms => new Promise(resolve => setTimeout(resolve,ms));
async function waitUntil(test,label) {
  const deadline = Date.now()+5000;
  let last;
  do {
    try { const value=await test(); if(value) return value; } catch(err) {last=err;}
    await sleep(25);
  } while(Date.now()<deadline);
  throw Error(label + (last ? ' ('+last.message+')' : ''));
}
async function runCase(driver,base,family,mode) {
  const address = base + mode + '/draft';
  const tab = await driver.open(address);
  const qa = (method,...args) => driver.fixture(tab,method,...args);
  const activate = t => driver.call('Target.activateTarget',{targetId:t.targetId});
  const close = t => driver.call('Target.closeTarget',{targetId:t.targetId});
  let sibling,closed=false;
  const row = {mode};
  try {
    await activate(tab);
    const first = await waitUntil(async()=>{
      const s=await qa('ready');return s.active && s.visible==='visible' && s;
    },'original tab did not acquire focus');
    const normal = {applicationID:family==='edge'?'com.microsoft.edgemac':'com.google.Chrome',
      sessionID:'isolated-build53-fixture',windowID:'test-window',tabID:tab.targetId};
    if (mode==='menuABA') await qa('setupMenu');
    const op=await qa('stage',normal);
    const original=await qa('state');
    assert.deepEqual(original.totals,{setter:0,input:0,change:0,send:0});
    const observe=()=>qa('read',op,normal);
    const commit=()=>qa('commit',op,normal);
    const readyNewDocument=()=>waitUntil(async()=>{
      const s=await qa('ready');return s.instance!==first.instance && s;
    },'same tab did not produce a new document');
    const navigate = url => driver.call('Page.navigate',{url},tab.sessionId);
    if (['tabInactive','tabABA','menuABA'].includes(mode)) {
      if(mode==='menuABA') { await qa('startMenu',op,normal); await waitUntil(()=>qa('menuOpened'),'menu did not open'); }
      sibling=await driver.open(base+mode+'/sibling');
      await activate(sibling);
      const hidden=await waitUntil(async()=>{
        const a=await qa('state'), b=await driver.fixture(sibling,'ready');
        return a.visible==='hidden' && !a.active && b.visible==='visible' && b.active && a;
      },'browser did not deliver A hidden and B active');
      row.hiddenAndBlurred=hidden.events.some(e=>e.type==='blur') && hidden.events.some(e=>e.type==='visibilitychange' && e.value==='hidden');
      assert.equal(row.hiddenAndBlurred,true);
      if(mode!=='tabInactive') {
        await activate(tab);
        await waitUntil(async()=>{const a=await qa('state');return a.active && a.visible==='visible';},'A did not return');
      }
      if(mode==='menuABA') await qa('mountChoice');
    } else if (mode==='sameURLDocument' || mode==='reload') {
      if(mode==='reload') await driver.call('Page.reload',{},tab.sessionId);
      else await navigate(address);
      const newDoc=await readyNewDocument();
      row.sameURLNewDocument=newDoc.href===first.href;
      assert.equal(row.sameURLNewDocument,true);
    } else if(mode==='historyABA') {
      await qa('pushSameDocument');
      assert.notEqual((await qa('state')).href,first.href);
      await qa('returnBack');
      const back=await waitUntil(async()=>{const s=await qa('state');return s.href===first.href && s;},'history back not observed');
      row.sameDocument=first.instance===back.instance;
      row.entryChanges=back.events.filter(e=>e.type==='currententrychange').length;
      assert.ok(row.sameDocument && row.entryChanges>=2);
    } else if(mode==='pagehide' || mode==='bfcache') {
      if(mode==='pagehide') await qa('observeOnPagehide',op,normal);
      await navigate(base+mode+'/away');
      await readyNewDocument();
      if(mode==='pagehide') {
        row.duringTrustedPagehide=await qa('pagehideReceipt');
        assert.equal(row.duringTrustedPagehide,'targetInvalidBeforeInput');
      } else {
        await qa('returnBack');
        const back=await waitUntil(async()=>{const s=await qa('ready');return s.href===first.href && s;},'back did not settle');
        const es=(await qa('state')).events;
        row.bfcacheRestored=back.instance===first.instance && es.some(e=>e.type==='pageshow' && e.persisted) &&
          es.some(e=>e.type==='pagehide' && e.persisted);
        if(!row.bfcacheRestored) {row.status='NOT_RUN';row.reason='browser returned a new document';return row;}
      }
    } else if(mode==='portalMoveDuringInput') {
      await qa('movePortalOnInput');
    } else if(mode==='rebuildDuringInput') {
      await qa('rebuildOnInput');
    } else if(mode==='editorReplacement') {
      await qa('replaceEditor');
    } else if(mode==='closedTarget') {
      sibling=await driver.open(base+mode+'/witness');
      await waitUntil(()=>driver.fixture(sibling,'ready'),'witness did not open');
      await close(tab); closed=true;
      await waitUntil(async()=>!(await driver.call('Target.getTargets')).targetInfos.some(t=>t.targetId===tab.targetId),'owned target still exists');
      try { await commit(); throw Error('stale Target accepted call'); }
      catch(err){if(!/session|closed|target.*not found/i.test(err.message))throw err;row.closedSessionRejected=true;}
      row.totals=(await driver.fixture(sibling,'state')).totals;
      assert.deepEqual(row.totals,{setter:0,input:0,change:0,send:0});
      row.status='PASS'; return row;
    }
    row.beforeCommit=await observe();
    row.commit=mode==='menuABA'?await qa('finishMenu'):await commit();
    const result=await qa('state');
    row.totals=result.totals;
    if(mode==='menuABA') row.menu=await qa('menuState');
    if(['rebuildDuringInput','portalMoveDuringInput'].includes(mode)) {
      row.afterCommit=await observe();
      row.secondCommit=await commit();
      assert.equal(row.beforeCommit.write,true);
      assert.equal(row.afterCommit.write,mode==='portalMoveDuringInput');
      assert.equal(row.secondCommit,'COMMIT_REFUSED');
      assert.deepEqual((await qa('state')).totals,row.totals);
      assert.deepEqual(row.totals,{setter:1,input:1,change:0,send:0});
      assert.equal(row.commit,'unknown');
    } else if(mode==='control') {
      row.draftPreserved=result.textPreserved && result.selectionPreserved && result.priorPreserved;
      assert.equal(row.draftPreserved,true);
      assert.deepEqual(row.totals,{setter:1,input:1,change:1,send:0});
      assert.equal(row.commit,'inputTriggered');
      await observe();
      assert.equal(await commit(),'COMMIT_REFUSED');
      assert.deepEqual((await qa('state')).totals,row.totals);
    } else {
      assert.equal(row.beforeCommit.write,false);
      if(['tabInactive','tabABA'].includes(mode)) assert.equal(row.beforeCommit.open,true,'read-only original should survive tab switch');
      const freshDocument=['sameURLDocument','reload','pagehide'].includes(mode);
      if(mode==='menuABA') assert.ok(['targetInvalidBeforeInput','attachmentInputNotCreated'].includes(row.commit),row.commit);
      else assert.equal(row.commit,freshDocument?'ORIGINAL_OPERATION_REQUIRED':'targetInvalidBeforeInput');
      await observe();
      row.secondCommit=await commit();
      assert.equal(row.secondCommit,freshDocument?'ORIGINAL_OPERATION_REQUIRED':'COMMIT_REFUSED');
      assert.deepEqual((await qa('state')).totals,row.totals);
      assert.deepEqual(row.totals,{setter:0,input:0,change:0,send:0});
      if(mode==='menuABA') assert.deepEqual(row.menu,{opener:1,choice:0,escape:0,selectionRestoration:0});
    }
    row.status='PASS';
  } catch(err) {row.status='FAIL';row.reason=err.message;}
  finally { if(sibling) await close(sibling); if(!closed) await close(tab); }
  return row;
}
async function suite(family) {
  assert.ok(Object.hasOwn(binaries,family),'unknown browser');
  const nonce='/'+crypto.randomBytes(24).toString('hex')+'/';
  const server=http.createServer((req,res)=>{
    const serve=(code,type,value)=>{res.writeHead(code,{'Content-Type':type,'Content-Security-Policy':"default-src 'none'; script-src 'self' 'unsafe-eval'; connect-src 'self'; img-src data:; form-action 'none'; base-uri 'none'; frame-ancestors 'none'",'Referrer-Policy':'no-referrer'});res.end(value);};
    if(req.method!=='GET' || req.headers.host!=='127.0.0.1:'+server.address().port || !req.url.startsWith(nonce))return serve(404,'text/plain','');
    const name=req.url.slice(nonce.length).split('?')[0];
    if(name==='program')return serve(200,'text/plain',program);
    if(name==='page.js')return serve(200,'text/javascript',pageJS);
    if(variants.includes(name.split('/')[0]) && ['draft','away','witness','sibling'].includes(name.split('/')[1]))return serve(200,'text/html',documentHTML);
    serve(404,'text/plain','');
  });
  server.on('connect',(_req,s)=>s.destroy()); server.on('upgrade',(_req,s)=>s.destroy());
  const sockets=new Set(); server.on('connection',s=>{sockets.add(s);s.once('close',()=>sockets.delete(s));});
  const profile=fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-owned-target-'));
  let child,exited,cleaned=false;
  try {
    await bounded(new Promise((ok,fail)=>{server.once('error',fail);server.listen(0,'127.0.0.1',ok);}),3000,'loopback listen timeout');
    const origin='127.0.0.1:'+server.address().port;
    const args=['--headless=new','--remote-debugging-pipe','--user-data-dir='+profile,
      '--disable-extensions','--disable-sync','--disable-background-networking','--disable-component-update',
      '--no-first-run','--no-default-browser-check','--disable-quic','--disable-crash-reporter',
      '--proxy-server=http://'+origin,'--proxy-bypass-list='+origin,'--force-webrtc-ip-handling-policy=disable_non_proxied_udp',
      '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','about:blank'];
    child=spawn(binaries[family],args,{detached:true,stdio:['ignore','ignore','ignore','pipe','pipe']});
    exited=new Promise(resolve=>child.once('exit',resolve));
    const driver=new FixtureDriver(child);
    const version=(await driver.call('Browser.getVersion')).product, cases=[];
    for(const mode of variants) {
      const result=await runCase(driver,'http://'+origin+nonce,family,mode);
      cases.push(result); console.error(family,mode,result.status,result.reason || '');
    }
    return {family,version,completedUTC:new Date().toISOString(),scope:'Disposable real browser loopback fixture; controlled route and native identity arguments',programSHA256:expected,cases};
  } finally {
    try {await cleanupOwnedChrome(child,exited);cleaned=true;}
    finally {await closeLoopbackServer(server,sockets);if(cleaned)fs.rmSync(profile,{recursive:true});}
  }
}
(async()=>{
  const results=[];
  for(const family of process.argv.slice(2).length?process.argv.slice(2):Object.keys(binaries)) results.push(await suite(family));
  console.log(JSON.stringify(results,null,2));
  if(results.some(r=>r.cases.some(c=>c.status!=='PASS')))process.exitCode=1;
})().catch(err=>{console.error(err.message);process.exitCode=1;});
