'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawn} = require('node:child_process');
const {setTimeout: delay} = require('node:timers/promises');
const {FixtureDriver} = require('../../../OriginalDocumentDelivery/renderer/driver.cjs');
const {cleanupOwnedChrome, closeLoopbackServer} = require('../../../WebPageProgram/native-chrome-cleanup.cjs');
const {localSite, sha} = require('./server.cjs');

async function waitFor(read, label, limit = 25000) {
  const end = performance.now() + limit;
  do {
    const value = await read();if (value) return value; await delay(40);
  } while (performance.now() < end);
  throw Error('Timeout observing ' + label);
}
async function readPage(driver, tab, expression) {
  const r = await driver.call('Runtime.evaluate', {expression, returnByValue:true}, tab.sessionId);
  assert.ok(!r.exceptionDetails, 'local page read failed'); return r.result.value;
}
function verify(row, route, original) {
  assert.equal(row.refused,undefined);const complete = route.mode === 'complete';
  assert.equal(row.requestID,route.requestID);assert.equal(row.urlSHA256,route.urlSHA256);
  assert.equal(row.fileSHA256,sha(original));assert.equal(row.fileBytes,original.length);
  assert.equal(row.createStatus,201);assert.equal(row.sendReturned,true);assert.equal(row.pendingXHR,0);
  assert.equal(row.listenersRemaining,0);assert.ok(row.listenersRemoved>0);
  assert.deepEqual(row.counts,{input:1,change:1,create:1,sends:1,abortCalls:complete?0:1,formSubmit:0,sendButton:0});
  assert.deepEqual(row.inputEvents,[{type:'input',trusted:true},{type:'change',trusted:true}]);
  assert.equal(route.creates,1);assert.equal(route.puts,1);assert.equal(route.pending,0);
  const server = route.evidence;assert.ok(server.bytesRead>0 && server.prefixMatches && server.bytesSHA256===server.originalPrefixSHA256);
  assert.equal(server.requestID,row.requestID);assert.equal(server.urlSHA256,row.urlSHA256);
  assert.ok(row.events.every(e=>e.trusted && e.sameTarget));
  for (const phase of ['request','upload']) {
    const events=row.events.filter(e=>e.phase===phase);
    for (const [name,count] of Object.entries({loadstart:1,loadend:1,load:complete?1:0,abort:complete?0:1,error:0,timeout:0})) {
      assert.equal(events.filter(e=>e.type===name).length,count,phase+' '+name);
    }
    assert.equal(events.at(-1).type,'loadend');
  }
  if (complete) {
    assert.equal(row.trigger,null);assert.equal(server.httpStatus,201);assert.equal(server.httpBodyComplete,true);
    assert.equal(server.bytesRead,original.length);assert.equal(server.bytesSHA256,row.fileSHA256);
    assert.equal(row.events.find(e=>e.phase==='request'&&e.type==='load').status,201);
  } else {
    const t=row.trigger;
    assert.ok(t && t.fraction>=.10 && t.fraction<=.50 && t.loaded>0 && t.loaded<t.total && t.total===original.length &&
      t.trusted && t.sameTarget && t.originalFile && t.originalInstance && t.sendReturned && t.readyState===1 && t.status===0);
    assert.equal(row.abortReturned,true);assert.ok(server.bytesRead<original.length && !server.httpBodyComplete && server.httpStatus===null);
    assert.equal(row.events.filter(e=>e.phase==='request' && (e.status!==0 || e.readyState===2 || e.readyState===3)).length,0);
  }
}
function verifyWithdrawal(browser, route, original) {
  const {disposition, nativeTerminal, counts} = browser;
  assert.equal(disposition.reason, route.mode === 'request-released' ? 'request-changed' : route.mode);
  if (route.mode === 'pagehide') assert.equal(disposition.pagehideTrusted, false, 'fixture-dispatched lifecycle control');
  assert.equal(disposition.pendingXHRAtWithdrawal, 1, 'An already-running PUT must remain pending at withdrawal');
  assert.equal(disposition.pendingCreatesAtWithdrawal, 0);
  assert.ok(disposition.listenersRemoved > 0 && disposition.mutationObserverDisconnected);
  assert.equal(disposition.observerListenersRemaining, 0);
  assert.equal(browser.listenersRemaining, 0);
  assert.equal(browser.pendingXHR, 0);
  assert.equal(browser.abortReturned, false);
  assert.equal(browser.trigger, null);
  assert.deepEqual(counts, {input:1,change:1,create:1,sends:1,abortCalls:0,formSubmit:0,sendButton:0});
  if (route.mode === 'expired') assert.ok(disposition.atMS >= disposition.deadlineMS, 'Independent monotonic deadline');
  assert.deepEqual(nativeTerminal, {type:'loadend',trusted:true,originalInstance:true,status:201});
  assert.ok(!browser.events.some(event => event.type === 'loadend'), 'Observation stopped before the native terminal');
  assert.equal(route.evidence.httpBodyComplete, true);
  assert.equal(route.evidence.httpStatus, 201);
  assert.equal(route.evidence.bytesRead, original.length);
  assert.equal(route.evidence.bytesSHA256, sha(original));
  assert.equal(browser.requestID, route.requestID);
  assert.equal(browser.urlSHA256, route.urlSHA256);
  assert.equal(route.creates, 1);
  assert.equal(route.puts, 1);
  assert.equal(route.pending, 0);
}
async function run() {
  const args = process.argv.slice(2);
  const controls = args[0] === '--lifetime-controls';
  if (controls) args.shift();
  assert.ok(args.length >= 1 && args.length <= 2, 'Expected one PNG and an optional capture receipt');
  const [png,provenance]=args;assert.ok(png,'Pass a local 5–15 MiB QA PNG and optional capture receipt');
  process.umask(0o077);
  const original=fs.readFileSync(png);
  assert.ok(original.length>=5*1024**2 && original.length<=15*1024**2);
  assert.equal(original.subarray(0,8).toString('hex'),'89504e470d0a1a0a');assert.equal(original.subarray(12,16).toString(),'IHDR');
  const dimensions=[original.readUInt32BE(16),original.readUInt32BE(20)];
  let source={scope:'local-development-PNG',sha256:sha(original),bytes:original.length,dimensions};
  if (provenance) {
    const data=fs.readFileSync(provenance),p=JSON.parse(data),c=p.capture;
    assert.equal(fs.realpathSync(p.originalPath),fs.realpathSync(png));assert.equal(p.exit,0);assert.equal(p.privatePNGCount,1);
    assert.equal(p.independentSHA256,source.sha256);assert.equal(p.independentBytes,original.length);assert.deepEqual(p.independentDimensions.map((v,i)=>{
      const m=new RegExp('^\\s*'+['pixelWidth','pixelHeight'][i]+':\\s*(\\d+)\\s*$').exec(v);assert.ok(m);return Number(m[1]);
    }),dimensions);
    assert.deepEqual(c.measuredFixture.dimensions,dimensions);
    assert.equal(c.sha256,source.sha256);assert.equal(c.byteCount,original.length);assert.equal(p.executedBrowserFileInputs,0);
    assert.equal(p.attemptedBrowserInteraction,false);assert.ok(c.ownerVerified && c.foregroundPIDUnchanged && c.windowOnlyCapture &&
      c.systemScreenshotMarker && c.nonactivatingPanel && c.measuredFixture);
    source={...source,scope:'macOS system screenshot of QA-owned nonactivating pattern window',captureReceiptSHA256:sha(data)};
  }
  const modes = controls ? ['partial', 'expired', 'source-changed', 'request-released', 'pagehide'] : ['complete', 'partial'];
  const site=localSite(original,fs.readFileSync(path.join(__dirname,'page.js')),modes);
  await new Promise((resolve,reject)=>{site.server.once('error',reject);site.server.listen(0,'127.0.0.1',resolve);});
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-owned-transfer-')), pngLocal=path.join(root,'control.png');
  const rows=[];let child,exited,version;
  try {
    fs.writeFileSync(pngLocal,original);
    child=spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',['--headless=new','--remote-debugging-pipe',
      '--user-data-dir='+path.join(root,'profile'),'--no-first-run','--no-default-browser-check','--disable-extensions','--disable-sync',
      '--disable-background-networking','--disable-component-update','--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','about:blank'],
      {detached:true,stdio:['ignore','ignore','ignore','pipe','pipe']});
    exited=new Promise(resolve=>{child.once('exit',resolve);child.once('error',resolve);});
    const driver=new FixtureDriver(child);version=(await driver.call('Browser.getVersion')).product;
    for (const [mode,route] of site.routes) {
      const url='http://127.0.0.1:'+site.server.address().port+'/case/'+mode;
      const tab=await driver.open(url);
      try {
        await waitFor(()=>readPage(driver,tab,'window.ready === true'),'owned page');
        assert.equal(await readPage(driver,tab,'location.href'),url);
        const {root:doc}=await driver.call('DOM.getDocument',{},tab.sessionId);
        const {nodeIds}=await driver.call('DOM.querySelectorAll',{nodeId:doc.nodeId,selector:'form input[type=file]'},tab.sessionId);
        assert.equal(nodeIds.length,1);
        await driver.call('DOM.setFileInputFiles',{nodeId:nodeIds[0],files:[pngLocal]},tab.sessionId);
        const browser=await waitFor(()=>readPage(driver,tab,'window.result'),'browser terminal');
        assert.ok(!browser.refused,browser.refused);
        await waitFor(()=>route.evidence,'server terminal');
        // Catch any late retry from this still-open original after the native terminal.
        await delay(300);
        const admitted={mode,browser,server:{...route.evidence,creates:route.creates,puts:route.puts,pending:route.pending}};
        rows.push(admitted);
        if (['complete', 'partial'].includes(mode)) verify(browser,route,original);
        else verifyWithdrawal(browser,route,original);
        assert.equal(browser.normalCompletionHandlerRemoved,true);
        assert.equal(browser.pendingCreates,0);
      } finally {await driver.call('Target.closeTarget',{targetId:tab.targetId});}
    }
    assert.deepEqual(site.unexpected,[]);
  } catch (error) {
    if (rows.length) console.error(JSON.stringify({scope:'incomplete-local-fixture',reason:error.message,rows}));
    throw error;
  } finally {
    try {if(child)await cleanupOwnedChrome(child,exited);fs.rmSync(root,{recursive:true,force:true});}
    finally {await closeLoopbackServer(site.server,site.sockets);}
  }
  assert.equal(site.server.listening,false);assert.equal(fs.existsSync(root),false);
  return {scope:'QA-owned IPv4 loopback only',schemaVersion:2,caseSet:controls?'lifetime-controls':'complete-and-partial',status:'PASS',browser:version,source,rows,
    cleanup:{ownedHeadlessProcessGroupExited:true,disposableProfileRemoved:true,listenerClosed:true,pendingPUTs:[...site.routes.values()].reduce((n,r)=>n+r.pending,0)},
    limitations:'Native browser file selection and local HTTP. This does not exercise Riftlet AppKit, SQLite, a ChatGPT upload, or a ChatGPT failure card.'};
}
run().then(row=>console.log(JSON.stringify(row,null,2)),error=>{console.error(error.message);process.exitCode=1;});
