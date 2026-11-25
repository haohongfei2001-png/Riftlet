'use strict';
const assert = require('node:assert/strict');
const {createHash,randomUUID} = require('node:crypto');
const {readFileSync} = require('node:fs');
const path = require('node:path');
const {setTimeout:wait} = require('node:timers/promises');
const {chromium} = require('playwright-core');
const {fixture,installFixture} = require('./fixture.cjs');

const resource = path.resolve(__dirname,'../../Sources/RiftletAdapters/Resources/conversation-providers.js');
const source = readFileSync(resource,'utf8');
const pinSource = source.split('\n  // RIFTLET_CLICK_PIN_END\n')[0] + "\n  return 'refused';\n}";
assert.ok(pinSource.length < 20480 && pinSource.length < source.length);
const ids = 'claude gemini copilot perplexity grok poe deepseek kimi qianwen qwen doubao yuanbao qingyan spark meta mistral wenxin zai'.split(' ');
const browsers = {
  chrome:['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','com.google.Chrome'],
  edge:['/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge','com.microsoft.edgemac']
};
const browserName = process.argv[2] || 'chrome';
const [defaultExecutable,applicationID] = browsers[browserName];
const origin = 'https://riftlet-provider-fixture.invalid', address = origin + '/draft?chat=1#original';
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
async function run() {
  const browser = await chromium.launch({headless:true,executablePath:process.env.RIFTLET_FIXTURE_BROWSER || defaultExecutable,
    args:['--disable-background-networking','--disable-component-update','--host-resolver-rules=MAP * ~NOTFOUND']});
  const results = [];
  async function test(id,mode) {
    const context = await browser.newContext({serviceWorkers:'block'});
    try {
      await context.route('**/*',route => route.request().isNavigationRequest() && route.request().url().startsWith(origin + '/draft')
        ? route.fulfill({contentType:'text/html',body:fixture(id,mode)}) : route.abort());
      const page = await context.newPage(); await page.goto(address);
      await page.evaluate(installFixture,mode);
      const session = await context.newCDPSession(page);
      const frame = (await session.send('Page.getFrameTree')).frameTree.frame.id;
      const world = await session.send('Page.createIsolatedWorld',{frameId:frame,worldName:'isolated QA click witness'});
      const profile = {id,adapterID:id + '-web',origins:[origin],routes:['/draft']};
      const native = {applicationID,sessionID:'test-session',windowID:'1',tabID:'2'};
      function command(body) {
        return page.evaluate(({source,body,native,profile}) => (0,eval)('(' + source + ')')(body,native,profile),
          {source,body,native,profile});
      }
      async function pin() {
        const clickWitnessID = randomUUID();
        const reply = await session.send('Runtime.evaluate',{contextId:world.executionContextId,
          expression:'(' + pinSource + ')(' + JSON.stringify({action:'pinTarget',clickWitnessID,address}) + ',{},' + JSON.stringify(profile) + ')',returnByValue:true});
        assert.equal(reply.exceptionDetails,undefined);
        return {state:reply.result.value,clickWitnessID};
      }
      async function capture() {
        const {state,clickWitnessID} = await pin(); assert.equal(state,'bound');
        return command({action:'captureTarget',clickWitnessID});
      }
      async function prepare(target,color) {
        const image = await page.evaluate(c => fixture.png(c),color);
        const chunkBase64 = image.split(',')[1], bytes = Buffer.from(chunkBase64,'base64');
        const identity = {target,operationID:randomUUID(),assetID:randomUUID(),attempt:1,assetSHA256:sha256(bytes)};
        const body = {target,identity,invocationID:randomUUID()};
        const uploadName = 'riftlet-' + identity.operationID + '.png';
        assert.equal((await command({...body,action:'begin',uploadName,mediaType:'image/png',byteCount:bytes.length})).nextChunk,0);
        assert.equal((await command({...body,action:'chunk',chunkBase64,chunkIndex:0})).nextChunk,1);
        return {body,commit:() => command({...body,action:'commit',chunkIndex:1}),observe:(extra = {}) => command({...body,action:'observe',...extra})};
      }
      async function settle(prepared,wanted) {
        let receipt = await prepared.commit();
        for (let i=0; i<25 && receipt.observation.state !== wanted; i++) {
          await wait(20); receipt = await prepared.observe();
        }
        return receipt;
      }
      if (mode === 'genericNonChat' || mode === 'gatedEditor' || mode === 'unlabelledField') {
        if (mode === 'unlabelledField') await page.evaluate(() => fixture.field.removeAttribute('aria-label'));
        if (mode === 'gatedEditor') await page.evaluate(() => fixture.root.setAttribute('aria-hidden','true'));
        assert.equal((await pin()).state,'refused'); return;
      }
      if (mode === 'foreign' || mode === 'ambiguous') {
        await page.evaluate(m => {
          const field = fixture.field;
          if (m === 'foreign') { field.remove(); }
          else { const next = field.cloneNode(); next.id='another'; field.after(next); }
        },mode);
        assert.equal((await pin()).state,'refused'); return;
      }
      if (mode === 'pinABA') {
        const witness = await pin(); assert.equal(witness.state,'bound');
        await page.evaluate(() => { const field=fixture.field,parent=field.parentNode; field.remove(); parent.append(field); });
        await assert.rejects(command({action:'captureTarget',clickWitnessID:witness.clickWitnessID}),/CLICK_PIN_REFUSED/); return;
      }
      const target = await capture();
      assert.equal(target.adapterID,id + '-web');
      assert.ok((await command({action:'validate',target})).valid);
      assert.equal((await command({action:'validate',target:{...target,tabID:'99'}})).valid,false);
      const first = await prepare(target,'red');
      if (mode === 'unrelatedMount' || mode === 'unrelatedMenu') {
        const receipt = await first.commit();
        assert.equal(receipt.observation.preInputRetirement.inputSideEffectEntered,false);
        assert.deepEqual(await page.evaluate(() => fixture.snapshot().counts),{setter:0,input:0,change:0,send:0,submit:0,avatar:0});
        return;
      }
      if (mode === 'routeRoundTrip' || mode === 'fieldABA' || mode === 'editorABA') {
        await page.evaluate(m => {
          if (m === 'routeRoundTrip') {
            history.pushState(null,'','?chat=another'); history.replaceState(null,'','?chat=1#original');
          } else {
            const node = m === 'fieldABA' ? fixture.field : fixture.editor;
            const parent=node.parentNode; node.remove(); parent.append(node);
          }
        },mode);
        const retired = await first.commit();
        assert.equal(retired.observation.preInputRetirement.inputSideEffectEntered,false);
        assert.equal(retired.observation.preInputRetirement.reason,'targetInvalidBeforeInput');
        assert.equal(await page.evaluate(() => fixture.counts.setter),0); return;
      }
      const absent = ['noCard','oldCardABA','differentPixels','progress'].includes(mode);
      const wanted = absent ? 'inputTriggered' : mode === 'failure' ? 'originalCardFailed' : 'uploadStarted';
      const result = await settle(first,wanted);
      assert.equal(result.provenance.evidenceID,'conversation-provider-20261125-v1');
      if (absent) {
        await wait(60); assert.equal((await first.observe()).observation.state,'inputTriggered');
      } else {
        assert.equal(result.observation.state,wanted,JSON.stringify(result.observation));
        assert.equal(result.observation.exactImageIdentity,true); assert.ok(result.observation.attachmentID);
        if (wanted === 'uploadStarted') assert.equal(result.observation.uploadStart.inputCount,1);
      }
      await assert.rejects(first.commit(),/COMMIT_REFUSED/);
      if (mode === 'memberABA') {
        await page.evaluate(() => fixture.originalCardABA());
        assert.equal((await first.observe()).observation.state,'uploadStarted');
        assert.equal((await first.observe({requireLiveOriginal:true})).observation.state,'invalidated');
      }
      const pair = mode === 'pair';
      if (pair) {
        const secondTarget = await capture();
        assert.deepEqual(secondTarget.logicalDraftIdentity,target.logicalDraftIdentity);
        assert.notEqual(secondTarget.clickBindingID,target.clickBindingID);
        const second = await prepare(secondTarget,'blue');
        const next = await settle(second,'uploadStarted');
        assert.equal(next.observation.state,'uploadStarted');
        assert.notEqual(next.observation.attachmentID,result.observation.attachmentID);
        assert.notEqual(next.observation.uploadStart.evidenceID,result.observation.uploadStart.evidenceID);
      }
      const after = await page.evaluate(() => fixture.snapshot());
      const before = await page.evaluate(() => fixture.before);
      const n = pair ? 2 : 1;
      assert.deepEqual(after.counts,{setter:n,input:n,change:n,send:0,submit:0,avatar:0});
      assert.equal(after.old,'prior.png'); assert.equal(after.text,before.text); assert.deepEqual(after.selection,before.selection);
    } finally { await context.close(); }
  }
  try {
    for (const id of ids) {
      await test(id,'pair'); results.push([id,'pair']); console.log('PASS',id,'pair');
    }
    await test('zai','unlabelledField'); results.push(['zai','unlabelledField']); console.log('PASS zai unlabelledField');
    for (const mode of ['menu','detached','focusTheft','foreign','ambiguous','linkedMount','unrelatedMount','unrelatedMenu','genericNonChat','gatedEditor','pinABA','fieldABA','editorABA','routeRoundTrip',
      'oldCardABA','memberABA','differentPixels','noCard','failure','progress']) {
      await test('claude',mode); results.push(['semantic',mode]); console.log('PASS',mode);
    }
    console.log(JSON.stringify({scope:'isolated synthetic receiver',browser:browserName,version:browser.version(),cases:results.length,programSHA256:sha256(source)}));
  } finally { await browser.close(); }
}
run().catch(error => { console.error(error); process.exitCode = 1; });
