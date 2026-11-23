'use strict';
// No file is selected. A true local navigation verifies the browser's trusted lifecycle event separately.
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {setTimeout: delay} = require('node:timers/promises');
const {FixtureDriver} = require('../../../OriginalDocumentDelivery/renderer/driver.cjs');
const {cleanupOwnedChrome, closeLoopbackServer} = require('../../../WebPageProgram/native-chrome-cleanup.cjs');
const {localSite} = require('./server.cjs');

async function evaluate(driver, tab, expression) {
  const {result,exceptionDetails} = await driver.call('Runtime.evaluate',{expression,returnByValue:true},tab.sessionId);
  assert.ok(!exceptionDetails);
  return result.value;
}
async function awaitPage(driver, tab, url) {
  const end = performance.now()+4000;
  do {
    const valid = await evaluate(driver,tab,'location.href==='+JSON.stringify(url)+' && window.ready === true');
    if (valid) return;
    await delay(20);
  } while (performance.now()<end);
  throw Error('Local document unavailable');
}
async function main() {
  const site=localSite(Buffer.alloc(0),fs.readFileSync(path.join(__dirname,'page.js')));
  await new Promise((resolve,reject)=>{site.server.once('error',reject);site.server.listen(0,'127.0.0.1',resolve);});
  const origin='http://127.0.0.1:'+site.server.address().port;
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-owned-pagehide-'));
  let child,exited,witness,browser;
  try {
    child=spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',['--headless=new','--remote-debugging-pipe',
      '--user-data-dir='+path.join(root,'profile'),'--no-first-run','--no-default-browser-check','--disable-extensions','--disable-sync',
      '--disable-background-networking','--disable-component-update','--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','about:blank'],
      {detached:true,stdio:['ignore','ignore','ignore','pipe','pipe']});
    exited=new Promise(resolve=>{child.once('exit',resolve);child.once('error',resolve);});
    const driver=new FixtureDriver(child);
    browser=(await driver.call('Browser.getVersion')).product;
    const first=origin+'/case/partial',next=origin+'/case/complete';
    const tab=await driver.open(first);
    try {
      await awaitPage(driver,tab,first);
      // This fixture-only witness runs after the page's own pagehide listener. Only its
      // bounded disposition is carried through the native navigation of this private tab.
      await evaluate(driver,tab,`if (location.href !== ${JSON.stringify(first)}) throw Error('wrong local case');
        window.addEventListener('pagehide', e => {
          sessionStorage.setItem('owned-pagehide-control',JSON.stringify({isTrusted:e.isTrusted,after:window.result}));
        },{once:true});true`);
      await driver.call('Page.navigate',{url:next},tab.sessionId);
      await awaitPage(driver,tab,next);
      witness=JSON.parse(await evaluate(driver,tab,"sessionStorage.getItem('owned-pagehide-control')"));
      assert.equal(witness.isTrusted,true);
      assert.equal(witness.after.disposition.reason,'pagehide');
      assert.equal(witness.after.disposition.pagehideTrusted,true);
      assert.equal(witness.after.disposition.observerListenersRemaining,0);
      assert.ok(witness.after.disposition.listenersRemoved>0 && witness.after.disposition.mutationObserverDisconnected);
      assert.equal(witness.after.pendingXHR,0);
      assert.equal(witness.after.pendingCreates,0);
      assert.ok([...site.routes.values()].every(r=>r.creates===0 && r.puts===0 && r.pending===0));
      assert.deepEqual(site.unexpected,[]);
    } finally {await driver.call('Target.closeTarget',{targetId:tab.targetId});}
  } finally {
    try {if(child)await cleanupOwnedChrome(child,exited);fs.rmSync(root,{recursive:true,force:true});}
    finally {await closeLoopbackServer(site.server,site.sockets);}
  }
  assert.equal(site.server.listening,false);
  return {scope:'trusted same-origin headless navigation before any selected File',browser,witness,
    creates:0,puts:0,cleanup:{processGroupExited:true,listenerClosed:true,pendingPUTs:0}};
}
main().then(row=>console.log(JSON.stringify(row,null,2)),e=>{console.error(e.message);process.exitCode=1;});
