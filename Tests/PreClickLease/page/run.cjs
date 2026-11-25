'use strict';
const assert=require('node:assert/strict');
const {spawn}=require('node:child_process');
const {createHash}=require('node:crypto');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {pathToFileURL}=require('node:url');
const {FixtureDriver}=require('../../OriginalDocumentDelivery/renderer/driver.cjs');
const {cleanupOwnedChrome}=require('../../WebPageProgram/native-chrome-cleanup.cjs');
const families={chrome:['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','com.google.Chrome'],
  edge:['/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge','com.microsoft.edgemac']};
const cases=['fastPair','queuedPairNoEviction','absentBeforeACK','ambiguousBeforeACK','invalidReclaim','expiredPending','renewSameLease','renewRetired','replaceField','ancestorRoundTrip','modeRoundTrip','sameEditorNewDraft','stagedAncestorRoundTrip',
  'replaceOpener','lateFieldAndOriginalMenu','enableOriginalField','moveThenOpenMenu','competingFields','tabRoundTrip','releaseAndBound','hostRestart','idlePreparedOver60s'];
async function until(test) {
  const deadline=performance.now()+5000;
  while (!await test()) {
    if(performance.now()>deadline)throw Error('fixture did not reach its expected browser state');
    await new Promise(resolve=>setTimeout(resolve,20));
  }
}
async function run(name,resource) {
  assert.ok(Object.hasOwn(families,name) && path.isAbsolute(resource));
  const [binary,bundle]=families[name],source=fs.readFileSync(resource,'utf8');
  const profile=fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-preclick-page-'));
  const child=spawn(binary,['--headless=new','--remote-debugging-pipe','--user-data-dir='+profile,'--no-first-run',
    '--no-default-browser-check','--disable-extensions','--disable-sync','--disable-background-networking','--disable-component-update',
    '--host-resolver-rules=MAP * ~NOTFOUND','--proxy-server=http://127.0.0.1:1','about:blank'],
    {detached:true,stdio:['ignore','ignore','ignore','pipe','pipe']});
  const exited=new Promise(resolve=>child.once('exit',resolve)),driver=new FixtureDriver(child);
  const rows=[];
  try {
    const version=(await driver.call('Browser.getVersion')).product;
    const fixtureURL=pathToFileURL(path.join(__dirname,'fixture.html')).href;
    for(const mode of cases) {
      const tab=await driver.open(fixtureURL),row={mode};
      const qa=(method,...args)=>driver.fixture(tab,method,...args);
      const ready=async(active)=>{
        const {result}=await driver.call('Runtime.evaluate',{expression:'typeof qa==="object" && document.hasFocus()==='+active+
          ' && document.visibilityState==='+JSON.stringify(active?'visible':'hidden')},tab.sessionId);
        return result.value===true;
      };
      try {
        await driver.call('Target.activateTarget',{targetId:tab.targetId}); await until(()=>ready(true));
        const {x,y,assetSHA256}=await qa('init',mode,source,bundle); row.assetSHA256=assetSHA256;
        const pair=mode==='fastPair' || mode==='queuedPairNoEviction';
        const noACK=mode==='absentBeforeACK' || mode==='ambiguousBeforeACK';
        const management=noACK || ['releaseAndBound','hostRestart','invalidReclaim','expiredPending','renewRetired'].includes(mode);
        let first;
        if(!noACK) {
          first=await qa('prepare');
          assert.deepEqual(await qa('validation',0),{write:true,read:true});
        }
        if(noACK) {
          row.prepare=await qa('tryPrepare');assert.equal(row.prepare,'ATTACHMENT_INPUT_UNAVAILABLE');
        } else if(mode==='releaseAndBound') {
          await qa('prepare');await qa('prepare');
          row.capacity=await qa('tryPrepare');assert.equal(row.capacity,'CLICK_PIN_LIMIT');
          for(let i=0;i<3;i++)assert.deepEqual(await qa('validation',i),{write:true,read:true});
          assert.equal(await qa('release',1),true);assert.equal(await qa('release',1),false);assert.equal(await qa('renew',1),false);
          await qa('prepare');
          row.releases=[];
          for(let i=0;i<4;i++)row.releases.push(await qa('release',i));
          assert.deepEqual(row.releases,[true,false,true,true]);
        } else if(mode==='hostRestart') {
          const prior={scope:'a'.repeat(64),generation:'0000000000000001'};
          const successor={...prior,generation:'0000000000000002'};
          const foreign={scope:'b'.repeat(64),generation:successor.generation};
          assert.equal(await qa('tryBegin',0),'accepted');
          row.enrolledBefore=await qa('observeBegun',0);
          assert.equal(row.enrolledBefore.original,true);
          await qa('prepare',prior);await qa('prepare',prior);await qa('prepare',foreign);
          row.foreignPressure=await qa('tryPrepare',foreign);
          assert.equal(row.foreignPressure,'CLICK_PIN_LIMIT');
          row.successor=[await qa('tryPrepare',successor),await qa('tryPrepare',successor)];
          assert.deepEqual(row.successor,['accepted','accepted']);
          for(const index of [1,2])assert.equal((await qa('validation',index)).write,false);
          for(const index of [3,4,5])assert.equal((await qa('validation',index)).write,true);
          row.delayedPrior=await qa('tryPrepare',prior);
          assert.equal(row.delayedPrior,'CLICK_PIN_REFUSED');
          row.enrolledAfter=await qa('observeBegun',0);
          assert.deepEqual(row.enrolledAfter,row.enrolledBefore);
          assert.equal(await qa('release',0),false);
          for(const index of [3,4,5])assert.equal(await qa('release',index),true);
          row.lateAfterDrain=await qa('tryPrepare',prior);
          assert.equal(row.lateAfterDrain,'CLICK_PIN_REFUSED');
        } else if(mode==='invalidReclaim') {
          await qa('prepare');await qa('prepare');await qa('mutate');await qa('prepare');
          row.releases=[];for(let i=0;i<4;i++)row.releases.push(await qa('release',i));
          assert.deepEqual(row.releases,[false,false,false,true]);
        } else if(mode==='renewRetired') {
          await qa('mutate');row.renewOnMoved=await qa('renew',0);assert.equal(row.renewOnMoved,false);
          assert.deepEqual(await qa('validation',0),{write:false,read:false});assert.equal(await qa('tryBegin',0),'TARGET_INVALID');
        } else if(mode==='expiredPending') {
          await qa('prepare');await qa('prepare');
          row.clock='injected monotonic, wall clock and timer scheduler in the product function scope';
          row.before=await qa('advanceClock',599999,599999);assert.deepEqual(await qa('validation',0),{write:true,read:true});
          row.deadline=await qa('advanceClock',1,1);assert.equal(row.deadline.fired,0);
          row.beginAtDeadline=await qa('tryBegin',0);assert.equal(row.beginAtDeadline,'TARGET_INVALID');
          row.renewAtDeadline=await qa('renew',2);assert.equal(row.renewAtDeadline,false);
          row.reaped=await qa('advanceClock',0,0,true);assert.equal(row.reaped.fired,1);assert.equal(row.reaped.remainingTimers,0);
          assert.equal(await qa('release',1),false);assert.equal(await qa('renew',0),false);
          await qa('prepare');row.wallDeadline=await qa('advanceClock',0,600000);
          row.beginAfterSleep=await qa('tryBegin',3);assert.equal(row.beginAfterSleep,'TARGET_INVALID');
        } else {
          if(mode==='renewSameLease') {
            row.clock='injected; full target is cloned across fresh instances of the same product function';
            await qa('advanceClock',240000,240000,true); row.firstRenew=await qa('renew',0);assert.equal(row.firstRenew,true);
            await qa('advanceClock',240000,240000,true); row.secondRenew=await qa('renew',0);assert.equal(row.secondRenew,true);
            row.pastOriginalExpiry=await qa('advanceClock',120001,120001,true);
            assert.equal(row.pastOriginalExpiry.monotonic,600001);assert.equal(row.pastOriginalExpiry.remainingTimers,1);
          }
          if(mode==='idlePreparedOver60s') {
            const since=performance.now();await new Promise(resolve=>setTimeout(resolve,61000));row.idleMS=performance.now()-since;
            assert.ok(row.idleMS>=60000);
          }
          if(pair) assert.equal(await qa('prepare'),first);
          if(mode==='tabRoundTrip') {
            const away=await driver.open('about:blank');
            try {
              await driver.call('Target.activateTarget',{targetId:away.targetId});await until(()=>ready(false));
              await driver.call('Target.activateTarget',{targetId:tab.targetId});await until(()=>ready(true));
            } finally {await driver.call('Target.closeTarget',{targetId:away.targetId});}
          } else if(mode!=='stagedAncestorRoundTrip')await qa('mutate');
          row.atPress=await qa('validation',0);
          row.outcomes=[];
          for(let i=0;i<(pair?2:1);i++) {
            for(const type of ['mousePressed','mouseReleased'])await driver.call('Input.dispatchMouseEvent',
              {type,x,y,button:'left',buttons:type==='mousePressed'?1:0,clickCount:1},tab.sessionId);
            if(mode!=='queuedPairNoEviction')row.outcomes.push(await qa('last'));
          }
          if(mode==='queuedPairNoEviction') {
            const queued=await qa('summary');row.queueBeforeBegin={presses:queued.presses.length,counts:queued.counts};
            assert.equal(queued.presses.length,2);assert.equal(queued.counts.setter,0);
            await qa('prepare');row.capacity=await qa('tryPrepare');assert.equal(row.capacity,'CLICK_PIN_LIMIT');
            for(let i=0;i<3;i++)assert.deepEqual(await qa('validation',i),{write:true,read:true});
            row.outcomes=await qa('drain');
            assert.equal(await qa('release',2),true);
          }
          if(['modeRoundTrip','sameEditorNewDraft','tabRoundTrip'].includes(mode)) {
            row.freshGeneration=(await qa('prepare'))!==first; assert.equal(row.freshGeneration,true);
            assert.equal(row.atPress.read,mode==='tabRoundTrip');
          }
        }
        Object.assign(row,await qa('summary'));
        const expected=pair?2:['lateFieldAndOriginalMenu','idlePreparedOver60s','renewSameLease','enableOriginalField','moveThenOpenMenu'].includes(mode)?1:0;
        assert.deepEqual(row.counts,{setter:expected,input:expected,change:expected,send:0,otherSetter:0,
          opened:['lateFieldAndOriginalMenu','moveThenOpenMenu','competingFields'].includes(mode)?1:0});
        assert.equal(row.stableDraft,true);
        assert.deepEqual(row.deliveredHashes,expected?row.outcomes.map(o=>o.assetSHA256):[]);
        if(!management) {
          assert.ok(row.presses.length===row.outcomes.length && row.presses.every(e=>e.trusted));
          const retiredAtCommit=mode==='stagedAncestorRoundTrip' || mode==='competingFields';
          assert.equal(row.atPress.write,expected>0 || retiredAtCommit);
          for(const result of row.outcomes) {
            if(expected || retiredAtCommit) {
              assert.equal(result.state,expected?'inputTriggered':'invalidated');
              if(!expected)assert.equal(result.reason,mode==='competingFields'?'attachmentInputNotCreated':'targetInvalidBeforeInput');
              assert.equal(result.repeated,'COMMIT_REFUSED'); assert.equal(result.releaseAfterBegin,false); assert.equal(result.renewAfterBegin,false);
            } else assert.equal(result.state,'preClickRejected');
          }
          if(pair) {
            assert.notEqual(row.outcomes[0].assetSHA256,row.outcomes[1].assetSHA256);
            assert.notEqual(row.outcomes[0].operationID,row.outcomes[1].operationID);
            assert.notEqual(row.outcomes[0].invocationID,row.outcomes[1].invocationID);
            row.intervalMS=row.presses[1].time-row.presses[0].time; assert.ok(row.intervalMS<2000);
          }
        }
        row.status='PASS';
      } catch(error) {row.status='FAIL';row.reason=error.message;}
      finally {await driver.call('Target.closeTarget',{targetId:tab.targetId});rows.push(row);}
    }
    return {family:name,version,utc:new Date().toISOString(),resourceSHA256:createHash('sha256').update(source).digest('hex'),
      scope:'Headless private test process; real DOM and trusted Chromium mouse events on fixture button. Controlled route/native IDs. No macOS click or provider website.',cases:rows};
  } finally {await cleanupOwnedChrome(child,exited);fs.rmSync(profile,{recursive:true});}
}
run(process.argv[2],process.argv[3]).then(result=>{console.log(JSON.stringify(result,null,2));if(result.cases.some(c=>c.status==='FAIL'))process.exitCode=1;})
  .catch(error=>{console.error(error.message);process.exitCode=1;});
