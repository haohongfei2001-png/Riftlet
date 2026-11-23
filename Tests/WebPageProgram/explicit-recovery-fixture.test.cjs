'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createHash, randomUUID} = require('node:crypto');
const {spawn} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {setTimeout:delay} = require('node:timers/promises');
const {pathToFileURL} = require('node:url');
const {build} = require('../ProductRecoveryAcceptance/Fixture/bridge.cjs');
const {FixtureDriver} = require('../OriginalDocumentDelivery/renderer/driver.cjs');
const {cleanupOwnedChrome} = require('./native-chrome-cleanup.cjs');

const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+cSe0AAAAASUVORK5CYII=', 'base64');
const sha256 = createHash('sha256').update(png).digest('hex');
const binaries = {chrome:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  edge:'/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'};

async function exercise(family, driver, file, mode) {
  const tab=await driver.open(file);
  const browser = family==='edge'?'com.microsoft.edgemac':'com.google.Chrome';
  const native={applicationID:browser,sessionID:'owned-fixture',windowID:'1',tabID:'1'};
  async function invoke(method,...args) {
    assert.ok(['command','snapshot','setNext','transition','navigate'].includes(method));
    const expr='window.recoveryFixture['+JSON.stringify(method)+'](...'+JSON.stringify(args)+')';
    const r=await driver.call('Runtime.evaluate',{expression:expr,awaitPromise:true,returnByValue:true},tab.sessionId);
    if(r.exceptionDetails)throw Error(r.exceptionDetails.exception?.description||r.exceptionDetails.text);
    return r.result.value;
  }
  async function fixtureClock(expression) {
    const r = await driver.call('Runtime.evaluate',{expression,returnByValue:true},tab.sessionId);
    if (r.exceptionDetails) throw Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text);
    return r.result.value;
  }
  const installClock = () => fixtureClock(`(() => {
    const real = window.setTimeout, callbacks = [];
    window.setTimeout = function(fn, ms, ...args) {
      const id = real(fn, ms, ...args);
      if (ms === 600000) callbacks.push(() => {clearTimeout(id);fn(...args);});
      return id;
    };
    window.expireOwnedOriginal = () => {
      window.setTimeout = real;
      const now = Date.now;
      Date.now = () => now() + 60 * 60 * 1000;
      try {callbacks.forEach(run => run());} finally {Date.now = now;}
      return callbacks.length;
    };
  })()`);
  const call=command=>invoke('command',command,native);
  const snap=()=>invoke('snapshot');
  async function pin() {
    const id=randomUUID();
    assert.equal(await call({action:'pinTarget',clickWitnessID:id,address:'https://chatgpt.com/'}),'bound');
    return call({action:'captureTarget',clickWitnessID:id});
  }
  const assetID=randomUUID();
  function make(target,attempt) {
    const identity={operationID:randomUUID(),assetID,assetSHA256:sha256,attempt,target};
    const invocationID=randomUUID();
    return {identity,invocationID,target};
  }
  async function stage(op,source) {
    await call({...op,action:'begin',uploadName:'riftlet-'+op.identity.operationID+'.png',byteCount:png.length,
      mediaType:'image/png',...(source?{recoverySource:source}:{})});
    await call({...op,action:'chunk',chunkIndex:0,chunkBase64:png.toString('base64')});
  }
  const commit=op=>call({...op,action:'commit',chunkIndex:1});
  async function observed(op,check) {
    const end=performance.now()+3000;let value;
    do {value=(await call({...op,action:'observe'})).observation;
      if(check(value))return value;await delay(20);
    } while(performance.now()<end);
    throw Error('expected product observation, actual '+JSON.stringify(value));
  }
  try {
    let before;
    for(let i=0;i<100 && !before;i++) {try{before=await snap();}catch{await delay(15);}}
    assert.equal(before?.selection,'preserve this original draft');
    const expired = mode === 'one-hour' || mode === 'one-hour-aba';
    if (expired) await installClock();
    const original=make(await pin(),1);
    await invoke('setNext',mode==='pre-input'?'pre-input-failure':mode==='delayed'?'pending':mode==='unobserved'?'silent':'preview');
    await stage(original);
    const first=(await commit(original)).observation;
    if(mode==='pre-input') {
      assert.equal(first.preInputRetirement.inputCount,0);
      assert.equal((await snap()).inputs,0);
      await invoke('setNext','preview');
      const replacement=make(await pin(),2);
      await stage(replacement);await commit(replacement);
      await observed(replacement,v=>v.uploadStart?.signal==='attachmentAccepted');
      const s=await snap();assert.equal(s.inputs,1);assert.equal(s.files[0].sha256,sha256);
      return;
    }
    if(mode==='delayed') {
      assert.equal(first.uploadStart,undefined);
      await invoke('transition',original.identity.operationID,'preview');
    }
    const firstStart=mode==='unobserved' ? null : await observed(original,v=>v.uploadStart?.signal==='attachmentAccepted');
    const source={identity:original.identity,invocationID:original.invocationID,
      ...(firstStart ? {startEvidenceID:firstStart.uploadStart.evidenceID} : {})};
    const inspect=(s=source)=>call({action:'validate',target:original.target,recoverySource:s,recoveryInspection:true});
    assert.equal((await inspect()).attachmentPresence,mode==='unobserved'?'unknown':'present');
    if(mode==='ambiguous') {
      await invoke('transition',original.identity.operationID,'ambiguous');
      const weak=await observed(original,v=>v.state==='failed');
      assert.equal(weak.hasError,true);
      assert.equal(weak.attachmentID,firstStart.attachmentID);
      assert.equal(weak.originalCardFailureInvocationID,undefined);
      assert.equal(weak.uploadStart,undefined);
      assert.equal((await inspect()).attachmentPresence,'present');
    } else if(mode==='failed') {
      await invoke('transition',original.identity.operationID,'failed');
      const failure=await observed(original,v=>v.state==='originalCardFailed' && v.hasError);
      assert.equal(failure.originalCardFailureInvocationID,original.invocationID);
      assert.equal(failure.attachmentID,firstStart.attachmentID);
      assert.equal(failure.uploadStart,undefined);
      source.failureAttachmentID=failure.attachmentID;
      assert.equal((await inspect()).attachmentPresence,'failed');
    } else if(mode==='disappeared'||mode==='delayed'){
      await invoke('transition',original.identity.operationID,'unknown');
      assert.equal((await inspect()).attachmentPresence,'absent');
    }
    if (expired) {
      assert.ok(await fixtureClock('expireOwnedOriginal()') >= 2,'expire the write ticket and operation');
      assert.equal((await call({action:'validate',target:original.target})).valid,false);
      assert.equal((await call({action:'validate',target:original.target,requireLiveOriginal:true})).valid,true);
      const forged = {...original.target,clickBindingID:randomUUID()};
      assert.equal((await call({action:'validate',target:forged,requireLiveOriginal:true})).valid,false);
      assert.equal((await inspect()).attachmentPresence,'present');
      assert.equal((await call({...original,action:'observe'})).observation.state,'invalidated');
      await assert.rejects(()=>stage(original),/TARGET_INVALID/);
      if (mode === 'one-hour-aba') {
        await fixtureClock(`(() => {
          const form = document.querySelector('form'), before = form.dataset.draftId;
          form.dataset.draftId = 'another-fixture-draft';
          form.dataset.draftId = before;
        })()`);
        assert.equal((await inspect()).valid,false,'old and current attributes match after a real ABA');
        assert.equal((await call({action:'validate',target:original.target,requireLiveOriginal:true})).valid,false);
        const nextTarget=await pin();
        assert.notEqual(nextTarget.draftGeneration, original.target.draftGeneration);
        assert.equal((await call({action:'validate',target:nextTarget,
          recoverySource:{...source,userConfirmedDuplicateRisk:true}})).valid,false);
        assert.equal((await snap()).setterEntries,1);
        return;
      }
    }
    assert.equal((await inspect({...source,invocationID:randomUUID()})).valid,false);
    const confirmed={...source,userConfirmedDuplicateRisk:true};
    const destination=await pin(), replacement=make(destination,2);
    assert.notEqual(destination.clickBindingID,original.target.clickBindingID);
    for(const key of ['documentID','composerID','draftGeneration'])assert.equal(destination[key],original.target[key]);
    if(mode==='present'||mode==='unobserved')assert.equal((await call({action:'validate',target:destination,recoverySource:source})).valid,false);
    assert.equal((await call({action:'validate',target:destination,recoverySource:confirmed})).valid,true);
    assert.equal((await call({action:'validate',target:original.target,recoverySource:confirmed})).valid,false);
    for (const bad of [{...confirmed,startEvidenceID:randomUUID()},
                       {...confirmed,identity:{...original.identity,assetSHA256:'0'.repeat(64)}},
                       {...confirmed,identity:{...original.identity,target:{...original.target,documentID:randomUUID()}}}])
      assert.equal((await call({action:'validate',target:destination,recoverySource:bad})).valid,false);
    assert.equal((await snap()).inputs,1,'inspection and cancellation alone do not write');
    if (mode === 'stale-new-ticket') {
      await fixtureClock("window.dispatchEvent(new Event('blur'))");
      assert.equal((await inspect()).valid,true,'the earlier enrolled original remains readable');
      assert.equal((await call({action:'validate',target:destination,recoverySource:confirmed})).valid,false);
      await assert.rejects(()=>stage(replacement,confirmed),/TARGET_INVALID/);
      assert.equal((await snap()).setterEntries,1);
      return;
    }
    await stage(replacement,confirmed);
    assert.equal((await call({action:'validate',target:destination,recoverySource:confirmed})).valid,false,
      'an enrolled write ticket cannot begin another recovery');
    if(mode==='changed') {
      await invoke('navigate');
      assert.equal((await inspect()).valid,false);
      assert.equal((await commit(replacement)).observation.preInputRetirement.inputCount,0);
      assert.equal((await snap()).inputs,1);
      return;
    }
    await commit(replacement);
    await observed(replacement,v=>v.uploadStart?.signal==='attachmentAccepted');
    await assert.rejects(()=>commit(replacement),/COMMIT_REFUSED/);
    const after=await snap();
    assert.equal(after.setterEntries,2);assert.equal(after.setterReturns,2);assert.equal(after.foreignSetters,0);
    assert.equal(after.inputs,2);assert.equal(after.changes,2);assert.equal(after.duplicates,0);
    assert.deepEqual(after.files.map(f=>f.sha256),[sha256,sha256]);
    assert.equal(after.text,before.text);assert.equal(after.selection,before.selection);
    assert.equal(after.documentID,before.documentID);assert.equal(after.previousAttachmentPreserved,true);
    assert.equal(after.sends,0);assert.equal(after.submits,0);
    const late=(await call({...original,action:'observe',preferStartReceipt:true})).observation;
    assert.equal(late.identity.operationID,original.identity.operationID);
    if(expired)assert.equal(late.state,'invalidated');
    else if(firstStart)assert.equal(late.uploadStart.evidenceID,firstStart.uploadStart.evidenceID);
    else assert.equal(late.uploadStart,undefined);
    assert.equal((await snap()).inputs,2,'late observation cannot enter another setter');
  } finally {await driver.call('Target.closeTarget',{targetId:tab.targetId});}
}

for(const [family,executable] of Object.entries(binaries)) {
  test('original-draft informed recovery and authored page responses: '+family,{skip:!fs.existsSync(executable)},async t=>{
    const root=fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-product-recovery-'));
    let child,exited;
    try {
      build(root);
      child=spawn(executable,['--headless=new','--remote-debugging-pipe','--user-data-dir='+path.join(root,'profile'),
        '--no-first-run','--no-default-browser-check','--disable-gpu','--disable-extensions','--disable-sync',
        '--disable-background-networking','--disable-component-update','--host-resolver-rules=MAP * ~NOTFOUND','about:blank'],
        {detached:true,stdio:['ignore','ignore','ignore','pipe','pipe']});
      exited=new Promise(resolve=>{child.once('exit',resolve);child.once('error',resolve);});
      const driver=new FixtureDriver(child), file=pathToFileURL(path.join(root,'index.html')).href;
      for(const mode of ['pre-input','present','disappeared','failed','delayed','changed','unobserved','one-hour','one-hour-aba','stale-new-ticket','ambiguous'])
        await t.test(mode,()=>exercise(family,driver,file,mode));
    } finally {
      if(child?.pid)await cleanupOwnedChrome(child,exited);
      fs.rmSync(root,{recursive:true,force:true});
    }
  });
}
