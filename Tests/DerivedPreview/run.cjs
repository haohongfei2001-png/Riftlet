'use strict';
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const {createHash} = require('node:crypto');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const {pathToFileURL} = require('node:url');
const {FixtureDriver} = require('../OriginalDocumentDelivery/renderer/driver.cjs');
const {cleanupOwnedChrome} = require('../WebPageProgram/native-chrome-cleanup.cjs');

const families = {
  chrome:['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','com.google.Chrome'],
  edge:['/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge','com.microsoft.edgemac'],
};
const negatives = ['otherFileSameBytes','similarName','onePixel','oneAlpha','wrongMIME','oldCard','oldImage','oldSurface','oldRemove',
  'foreignDraft','competing','competingThenRemoved','sameAliasFailure','competingRemove','mismatchedRemove','errorCard','editorReplaced','cardReplaced','cardReplacedDuringDecode','cardRevoked'];

async function run(family, resource, baseline) {
  assert.ok(Object.hasOwn(families, family) && path.isAbsolute(resource));
  assert.ok(!baseline || baseline === '--baseline58');
  const [binary, bundle] = families[family], source = fs.readFileSync(resource, 'utf8');
  const resourceSHA256 = createHash('sha256').update(source).digest('hex');
  if (baseline) assert.equal(resourceSHA256,'43e43df544d4edb6081dfe592b1b18166039f98983ab8f0fac0f31efdf60d166');
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'riftlet-derived-preview-'));
  const child = spawn(binary,['--headless=new','--remote-debugging-pipe','--user-data-dir='+profile,
    '--no-first-run','--no-default-browser-check','--disable-extensions','--disable-sync','--disable-background-networking',
    '--disable-component-update','--host-resolver-rules=MAP * ~NOTFOUND','--proxy-server=http://127.0.0.1:1','about:blank'],
    {detached:true,stdio:['ignore','ignore','ignore','pipe','pipe']});
  const exited = new Promise(resolve=>child.once('exit',resolve)), driver = new FixtureDriver(child);
  const results = [];
  try {
    const version = (await driver.call('Browser.getVersion')).product;
    for (const mode of (baseline ? ['validPair'] : ['validPair','otherAliasFailure', ...negatives])) {
      const row = {mode}, tab = await driver.open(pathToFileURL(path.join(__dirname,'fixture.html')).href);
      const qa = (method,...args)=>driver.fixture(tab,method,...args);
      try {
        await driver.call('Target.activateTarget',{targetId:tab.targetId});
        const end = performance.now()+3000;
        for (;;) {
          const {result} = await driver.call('Runtime.evaluate',{expression:'typeof qa==="object" && document.hasFocus() && document.visibilityState==="visible"'},tab.sessionId);
          if (result.value) break;
          if (performance.now()>end) throw Error('private fixture did not become active');
          await new Promise(resolve=>setTimeout(resolve,15));
        }
        assert.equal(await qa('init',mode,source,bundle),true);
        const total = mode==='validPair' ? 2 : 1;
        for (let i=0;i<total;i++) assert.equal(await qa('prepare'),i);
        row.commits=[]; row.published=[]; row.observed=[];
        for (let i=0;i<total;i++) {
          const result=await qa('commit',i);
          row.commits.push(result);
          assert.equal(result.commit,'inputTriggered');
          assert.equal(result.pending.start,false,'a named PNG placeholder cannot prove preview acceptance');
          assert.equal(result.repeat,'COMMIT_REFUSED');
        }
        for (let i=0;i<total;i++) { row.published.push(await qa('publish',i)); }
        for (let i=0;i<total;i++) {
          const result=await qa('settle',i,(mode==='validPair' || mode==='otherAliasFailure') && !baseline ? 1800:400);
          row.observed.push(result);
        }
        Object.assign(row,await qa('summary'));
        assert.deepEqual(row.counts,{setter:total,input:total,change:total,send:0});
        assert.equal(row.originalText,true);
        assert.equal(row.originalEditor, mode!=='editorReplaced');
        assert.equal(row.priorAttachment,true);
        assert.deepEqual(row.selection,[2,8]);
        for(const published of row.published) {
          assert.deepEqual(published.decoded,[36,24]);
          assert.notEqual(published.originalSHA,published.previewSHA,'distinct legal PNG encoding is required');
          assert.equal(published.pixelProof.pixels,864);
          assert.equal(published.pixelProof.partialAlpha,288);
          assert.equal(published.pixelProof.differentPixels,mode==='onePixel' || mode==='oneAlpha'?1:0);
          assert.equal(published.pixelProof.differentAlpha,mode==='oneAlpha'?1:0);
          assert.equal(published.replacedDuringDecode,mode==='cardReplacedDuringDecode');
          if(mode==='otherFileSameBytes') assert.equal(published.otherFileSHA,published.originalSHA);
        }
        if (total===2) {
          for (const key of ['opID','inv','sha']) assert.notEqual(row.commits[0][key],row.commits[1][key]);
          assert.equal(row.commits[0].target,row.commits[1].target);
          assert.ok(row.inputIntervalMS>=0 && row.inputIntervalMS<2000);
        }
        if (!baseline && (mode==='validPair' || mode==='otherAliasFailure')) {
          for(const observed of row.observed) {
            assert.equal(observed.state,'uploadStarted');
            assert.equal(observed.original,true); assert.equal(observed.inputCount,1);assert.equal(observed.exact,true);
            assert.ok(observed.startSequence>observed.inputSequence && observed.inputSequence>0);
            assert.ok(observed.attachmentID && observed.evidenceID);
          }
          if(total===2){
            assert.notEqual(row.observed[0].attachmentID,row.observed[1].attachmentID);
            assert.notEqual(row.observed[0].evidenceID,row.observed[1].evidenceID);
          }
        } else {
          for(const published of row.published) assert.equal(published.atPublish.start,false);
          for(const observed of row.observed) {
            assert.ok(['inputTriggered','invalidated','unknown'].includes(observed.state),observed.state);
            assert.equal(observed.start,false);assert.equal(observed.attachmentID,null);
          }
        }
        row.status = baseline ? 'BASELINE_MISSING_START_REPRODUCED' : 'PASS';
      } catch(error) { row.status='FAIL';row.reason=error.message; }
      finally { results.push(row);await driver.call('Target.closeTarget',{targetId:tab.targetId}); }
    }
    return {family,version,resourceSHA256,scope:'Real isolated headless engine. Controlled fixture route and native IDs. No provider website or signed App input.',results};
  } finally { await cleanupOwnedChrome(child,exited);fs.rmSync(profile,{recursive:true}); }
}
run(...process.argv.slice(2)).then(report=>{
  console.log(JSON.stringify(report,null,2));
  if(report.results.some(row=>row.status==='FAIL'))process.exitCode=1;
}).catch(error=>{console.error(error.message);process.exitCode=1;});
