'use strict';
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const {randomUUID,createHash} = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const {bounded,cleanupOwnedChrome,closeLoopbackServer} = require('../../WebPageProgram/native-chrome-cleanup.cjs');
const {mountAttachmentEntryCase} = require('../../WebPageProgram/attachment-entry-application.cjs');
const {FixtureDriver} = require('../renderer/driver.cjs');
const binaries={chrome:['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','com.google.Chrome'],
  edge:['/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge','com.microsoft.edgemac']};
const modes=['portalABA','focusABA','closedShadowFocus','menu','unlinkedFocusMenu'];
const asExpected=(row)=>{
  assert.equal(row.repeat,'COMMIT_REFUSED');
  assert.ok(row.priorCardPreserved);
  if(row.mode==='portalABA') {
    assert.ok(row.validBefore && row.returnedToSameLineage);
    assert.deepEqual(row.counts,{setter:1,input:1,change:0,send:0});
    assert.equal(row.state,'unknown');
  } else if(row.mode==='focusABA' || row.mode==='closedShadowFocus') {
    if(row.mode==='closedShadowFocus')assert.ok(row.capturedShadowFocus && row.capturedShadowBlur && row.shadowRetargeted);
    assert.equal(row.focusRoundTrip,true);
    assert.deepEqual(row.counts,{setter:0,input:0,change:0,send:0});
    assert.equal(row.validBefore,false);
    assert.equal(row.retirement,'targetInvalidBeforeInput');
  } else {
    if(row.mode==='unlinkedFocusMenu')assert.equal(row.actualPortalFocus,true);
    assert.equal(row.validBefore,true); assert.equal(row.draftPreserved,true);
    assert.deepEqual(row.counts,{setter:1,input:1,change:1,send:0});
    assert.equal(row.state,'inputTriggered');
    assert.deepEqual(row.menu,{opened:1,selected:1,invoked:1,defaultChooserAllowed:0});
  }
};
async function run(family,sourceFile) {
  assert.ok(Object.hasOwn(binaries,family) && path.isAbsolute(sourceFile),'supply chrome|edge and absolute JS file');
  const [binary,bundle]=binaries[family], prefix='/'+randomUUID()+'/';
  const source=fs.readFileSync(sourceFile), script=mountAttachmentEntryCase.toString()+'\n'+fs.readFileSync(path.join(__dirname,'case.js'),'utf8');
  const html='<!doctype html><meta charset=utf-8><form data-composer-layout><div id="prompt-textarea" contenteditable="true" role="textbox">Original draft with selection</div><div role="button" data-file-name="prior.png"><img alt="prior.png"></div><button type="submit">Send</button></form><script src="case.js"></script>';
  const server=http.createServer((req,res)=>{
    const route=req.url.slice(prefix.length);
    if(req.method!=='GET'||req.headers.host!=='127.0.0.1:'+server.address().port || !req.url.startsWith(prefix)) {
      res.writeHead(404);res.end();return;
    }
    const file=modes.includes(route)?['text/html',html]:route==='case.js'?['text/javascript',script]:route==='program'?['text/plain',source]:null;
    if(!file){res.writeHead(404);res.end();return;}
    res.writeHead(200,{'Content-Type':file[0],'Content-Security-Policy':"default-src 'none'; script-src 'self' 'unsafe-eval'; connect-src 'self'; img-src data:; form-action 'none'; base-uri 'none'; frame-ancestors 'none'"});res.end(file[1]);
  });
  server.on('connect',(_req,s)=>s.destroy());server.on('upgrade',(_req,s)=>s.destroy());
  const sockets=new Set();
  server.on('connection',s=>{sockets.add(s);s.once('close',()=>sockets.delete(s));});
  const profile=fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-owned-product-'));
  let child,exited,cleaned=false;
  try {
    await bounded(new Promise((ok,fail)=>{server.once('error',fail);server.listen(0,'127.0.0.1',ok);}),3000,'loopback listen timeout');
    const origin='127.0.0.1:'+server.address().port;
    child=spawn(binary,['--headless=new','--remote-debugging-pipe','--user-data-dir='+profile,
      '--no-first-run','--no-default-browser-check','--disable-sync','--disable-extensions','--disable-background-networking',
      '--disable-component-update','--disable-quic','--proxy-server=http://'+origin,'--proxy-bypass-list='+origin,
      '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','--force-webrtc-ip-handling-policy=disable_non_proxied_udp','about:blank'],
      {detached:true,stdio:['ignore','ignore','ignore','pipe','pipe']});
    exited=new Promise(ok=>child.once('exit',ok));
    const driver=new FixtureDriver(child),version=(await driver.call('Browser.getVersion')).product,cases=[];
    for(const mode of modes){
      const url='http://'+origin+prefix+mode;
      const {targetId}=await driver.call('Target.createTarget',{url,background:false});
      const {sessionId}=await driver.call('Target.attachToTarget',{targetId,flatten:true});
      try {
        await driver.call('Target.activateTarget',{targetId});
        const evaluate=async(expression)=>{
          const res=await driver.call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true},sessionId);
          if(res.exceptionDetails)throw Error(res.exceptionDetails.exception?.description || res.exceptionDetails.text);
          return res.result.value;
        };
        const deadline=Date.now()+5000;
        while(!await evaluate("document.readyState==='complete' && typeof runOperationCase==='function' && document.hasFocus() && document.visibilityState==='visible'")){
          if(Date.now()>=deadline)throw Error('original fixture not ready');
          await new Promise(ok=>setTimeout(ok,20));
        }
        const result=await evaluate('fetch("./program").then(r=>r.text()).then(s=>runOperationCase('+JSON.stringify(mode)+','+JSON.stringify(bundle)+',s))');
        try {asExpected(result);result.status='PASS';}
        catch(error){result.status='FAIL';result.reason=error.message;}
        cases.push(result);
      } finally {await driver.call('Target.closeTarget',{targetId});}
    }
    return {family,version,resourceSHA256:createHash('sha256').update(source).digest('hex'),utc:new Date().toISOString(),
      scope:'Complete page resource and native browser DOM in a disposable headless process. Controlled route/native arguments.',cases};
  } finally {
    try{await cleanupOwnedChrome(child,exited);cleaned=true;}
    finally{await closeLoopbackServer(server,sockets);if(cleaned)fs.rmSync(profile,{recursive:true});}
  }
}
run(process.argv[2],process.argv[3]).then(row=>{console.log(JSON.stringify(row,null,2));if(row.cases.some(c=>c.status!=='PASS'))process.exitCode=1;})
  .catch(error=>{console.error(error.message);process.exitCode=1;});
