'use strict';
// Real browser-window destruction and process death against a disposable local origin.
// Every browser command travels on pipes inherited by our own newly spawned process.
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const {createHash, randomUUID} = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const {FixtureDriver} = require('./driver.cjs');
const {bounded, cleanupOwnedChrome, closeLoopbackServer} = require('../WebPageProgram/native-chrome-cleanup.cjs');

const defaultHash = '50b0d16d10f38c688ce33189df55ad3da6588b4c7006b710777f30340dc55ed7';
const pathInCheckout = 'Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js';
const explicitPath = process.env.RIFTLET_SAFETY_ASSET_PATH;
const root = process.env.RIFTLET_SAFETY_SOURCE_ROOT;
assert.ok(!explicitPath || !root,'choose a single page asset source');
assert.ok(!explicitPath || path.isAbsolute(explicitPath),'asset path must be absolute');
const program = fs.readFileSync(explicitPath || path.resolve(root || path.join(__dirname,'../..'),pathInCheckout));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const expected = explicitPath || root ? process.env.RIFTLET_SAFETY_EXPECT_SHA256 : defaultHash;
assert.match(expected || '',/^[a-f0-9]{64}$/);
assert.equal(digest(program),expected,'page program digest mismatch');
const html = '<!doctype html><meta charset=utf-8><body><form data-composer-layout>' +
  '<div id="prompt-textarea" contenteditable="true" role="textbox">Original QA draft text</div>' +
  '<input type="file" hidden accept="image/*"><div role="button" data-file-name="existing.png"><img alt="existing.png"></div>' +
  '<button type="submit">Send</button></form><script src="../page.js"></script>';
const zero = {setter:0,input:0,change:0,send:0};
// Counters must exist even before any file event. A nonce proves the second
// window/process read the same storage, instead of defaulting absent counters to zero.
const stateWitness = `
  (() => {
    const key = 'counts:' + location.pathname.split('/')[2];
    const stamp = key + ':stamp';
    window.qa.startHostLedger = () => {
      if(localStorage.getItem(stamp) !== null) throw Error('host ledger already exists');
      const id = crypto.randomUUID();
      localStorage.setItem(key,JSON.stringify({setter:0,input:0,change:0,send:0}));
      localStorage.setItem(stamp,id);
      return id;
    };
    window.qa.hostLedger = () => ({stamp:localStorage.getItem(stamp), totals:JSON.parse(localStorage.getItem(key))});
  })();`;
const js = fs.readFileSync(path.join(__dirname,'page.js'),'utf8') + stateWitness;
const members = {
  chrome: {bundle:'com.google.Chrome',bin:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'},
  edge: {bundle:'com.microsoft.edgemac',bin:'/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'}
};

function fixtureServer(nonce) {
  const server = http.createServer((req,res)=>{
    const headers = {'Content-Security-Policy':"default-src 'none'; script-src 'self' 'unsafe-eval'; connect-src 'self'; img-src data:; form-action 'none'; base-uri 'none'; frame-ancestors 'none'",'Referrer-Policy':'no-referrer'};
    const name = req.url.slice(nonce.length);
    if(req.method!=='GET' || req.headers.host!=='127.0.0.1:'+server.address().port || !req.url.startsWith(nonce)) {
      res.writeHead(404); res.end(); return;
    }
    const resources = {'program':['text/plain',program],'page.js':['text/javascript',js],
      'close/draft':['text/html',html],'close/witness':['text/html',html],'restart/draft':['text/html',html]};
    if(!Object.hasOwn(resources,name)) {res.writeHead(404); res.end(); return;}
    const [type,body]=resources[name];
    res.writeHead(200,{...headers,'Content-Type':type});res.end(body);
  });
  const sockets=new Set();
  server.on('connection',s=>{sockets.add(s);s.once('close',()=>sockets.delete(s));});
  server.on('connect',(_req,s)=>s.destroy());
  server.on('upgrade',(_req,s)=>s.destroy());
  return {server,sockets};
}
async function waitFor(check,reason) {
  const deadline=Date.now()+5000;
  let last;
  do {
    try {const result=await check();if(result)return result;} catch(error){last=error;}
    await new Promise(ok=>setTimeout(ok,25));
  } while(Date.now()<deadline);
  throw Error(reason + (last ? '; '+last.message : ''));
}
function launch(member,origin,profile) {
  const args=['--headless=new','--remote-debugging-pipe','--user-data-dir='+profile,'--disable-extensions',
    '--disable-sync','--disable-background-networking','--disable-component-update','--no-first-run',
    '--no-default-browser-check','--disable-quic','--disable-crash-reporter','--proxy-server=http://'+origin,
    '--proxy-bypass-list='+origin,'--force-webrtc-ip-handling-policy=disable_non_proxied_udp',
    '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','about:blank'];
  const child=spawn(member.bin,args,{detached:true,stdio:['ignore','ignore','ignore','pipe','pipe']});
  const exited=new Promise((ok,fail)=>{child.once('exit',ok);child.once('error',fail);});
  exited.catch(()=>{});
  return {child,exited,driver:new FixtureDriver(child)};
}
async function newWindow(driver,url) {
  const {targetId}=await driver.call('Target.createTarget',{url,newWindow:true,background:false});
  const {sessionId}=await driver.call('Target.attachToTarget',{targetId,flatten:true});
  const tab={targetId,sessionId};
  await driver.call('Target.activateTarget',{targetId});
  const doc=await waitFor(async()=>{
    const s=await driver.fixture(tab,'ready');
    return s.active && s.visible==='visible' && s.href===url && s;
  },'new browser window did not become active at the owned URL');
  const {windowId}=await driver.call('Browser.getWindowForTarget',{targetId});
  assert.ok(Number.isSafeInteger(windowId),'missing browser window identity');
  return {...tab,windowId,instance:doc.instance};
}
async function stage(driver,tab,bundle,pid) {
  // Pass one frozen native identity tuple to the ordinary page-program API.
  // In the restart case the exact same tuple is deliberately supplied again.
  const native={applicationID:bundle,sessionID:'qa-owned-pid:'+pid,windowID:String(tab.windowId),tabID:tab.targetId};
  const stamp=await driver.fixture(tab,'startHostLedger');
  const op=await driver.fixture(tab,'stage',native);
  const read=await driver.fixture(tab,'read',op,native);
  assert.equal(read.write,true,'precondition: original witness live');
  assert.deepEqual(await driver.fixture(tab,'hostLedger'),{stamp,totals:zero});
  return {native,op,stamp};
}
async function closeWindow(browser,bundle,base) {
  const {driver,child}=browser;
  const observer=await newWindow(driver,base+'close/witness');
  const original=await newWindow(driver,base+'close/draft');
  assert.notEqual(original.windowId,observer.windowId,'two independent browser windows required');
  // Prove the tested window has precisely one page before closing its only tab.
  const ids=[];
  const {targetInfos}=await driver.call('Target.getTargets');
  for(const t of targetInfos.filter(t=>t.type==='page')) {
    const {windowId}=await driver.call('Browser.getWindowForTarget',{targetId:t.targetId});
    if(windowId===original.windowId)ids.push(t.targetId);
  }
  assert.deepEqual(ids,[original.targetId]);
  const {op,native,stamp}=await stage(driver,original,bundle,child.pid);
  assert.deepEqual(await driver.fixture(observer,'hostLedger'),{stamp,totals:zero});
  await driver.call('Target.closeTarget',{targetId:original.targetId});
  const gone=await waitFor(async()=>{
    try {await driver.call('Browser.getWindowBounds',{windowId:original.windowId});return false;}
    catch(err){if(!/window.*not found|no window/i.test(err.message))throw err;return err.message;}
  },'original browser window still exists');
  await assert.rejects(driver.fixture(original,'commit',op,native),/session.*not found|no session with given id/i);
  assert.ok((await driver.call('Browser.getWindowBounds',{windowId:observer.windowId})).bounds);
  assert.deepEqual(await driver.fixture(observer,'hostLedger'),{stamp,totals:zero});
  return {status:'PASS',distinctBrowserWindowIDs:true,originalWindowHadSinglePage:true,
    originalWindowGone:gone,oldSessionDelivery:'REJECTED',observerWindowStillExists:true,
    originalLedgerStillPresent:true,totals:zero};
}
async function scenario(family) {
  assert.ok(Object.hasOwn(members,family));
  const member=members[family], nonce='/'+randomUUID()+'/';
  const {server,sockets}=fixtureServer(nonce);
  const profile=fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-host-life-'));
  let browser;
  let profileSafe=true;
  async function stopBrowser() {
    if(!browser)return;
    profileSafe=false;
    await cleanupOwnedChrome(browser.child,browser.exited);
    browser=null;
    profileSafe=true;
  }
  try {
    await bounded(new Promise((ok,fail)=>{server.once('error',fail);server.listen(0,'127.0.0.1',ok);}),3000,'cannot start loopback origin');
    const origin='127.0.0.1:'+server.address().port, base='http://'+origin+nonce;
    browser=launch(member,origin,profile);
    const version=(await browser.driver.call('Browser.getVersion')).product;
    const close=await closeWindow(browser,member.bundle,base);
    const targetURL=base+'restart/draft';
    const original=await newWindow(browser.driver,targetURL);
    const {op,native,stamp}=await stage(browser.driver,original,member.bundle,browser.child.pid);
    const persisted=JSON.stringify({op,native}), frozenDigest=digest(persisted);
    const oldPID=browser.child.pid;
    // The browser's orderly exit flushes its owned localStorage before relaunch.
    await browser.driver.call('Browser.close');
    await bounded(browser.exited,8000,'first browser did not exit normally');
    assert.equal(browser.child.exitCode,0,'browser exited abnormally');
    await stopBrowser();
    browser=launch(member,origin,profile);
    const newPID=browser.child.pid;
    assert.notEqual(newPID,oldPID,'test requires two independently observed process identities');
    const fresh=await newWindow(browser.driver,targetURL);
    assert.notEqual(fresh.instance,original.instance,'full restart must produce a different document');
    const restored=JSON.parse(persisted);
    assert.equal(digest(JSON.stringify(restored)),frozenDigest);
    assert.deepEqual(await browser.driver.fixture(fresh,'hostLedger'),{stamp,totals:zero});
    const read=await browser.driver.fixture(fresh,'read',restored.op,restored.native);
    assert.equal(read.open,false); assert.equal(read.write,false);assert.equal(read.observation,'invalidated');
    const commit=await browser.driver.fixture(fresh,'commit',restored.op,restored.native);
    assert.equal(commit,'ORIGINAL_OPERATION_REQUIRED');
    const ledger=await browser.driver.fixture(fresh,'hostLedger');
    assert.deepEqual(ledger,{stamp,totals:zero});
    return {family,version,programSHA256:expected,completedUTC:new Date().toISOString(),
      scope:'Isolated headless browser windows and process restart with a persisted loopback fixture ledger',
      closeWindow:close,restart:{status:'PASS',originalProcessExitedNormally:true,actualPIDsDistinct:true,
        originAndURLPreserved:true,originalLedgerStillPresent:true,documentInstanceChanged:true,
        stagedIdentityAndInjectedNativeTuplePreserved:true,read,commit,totals:ledger.totals}};
  } finally {
    try {await stopBrowser();}
    finally {await closeLoopbackServer(server,sockets);if(profileSafe)fs.rmSync(profile,{recursive:true});}
  }
}
(async()=>{
  const reports=[];
  for(const family of process.argv.slice(2).length?process.argv.slice(2):Object.keys(members)) {
    try {reports.push(await scenario(family));}
    catch(err){reports.push({family,programSHA256:expected,status:'INCOMPLETE',reason:err.message});process.exitCode=1;}
  }
  console.log(JSON.stringify(reports,null,2));
})();
