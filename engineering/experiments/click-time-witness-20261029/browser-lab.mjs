// Offline architecture comparison, not an extension/native input implementation.
import assert from 'node:assert/strict';
import {createHash, randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';

const require = createRequire(new URL('../../../Tests/ColdClickBrowser/package.json', import.meta.url));
const {chromium} = require('playwright');
const driverVersion = require('playwright/package.json').version;
assert.equal(driverVersion, '1.62.1', 'reuse the existing exact locked Playwright version');
const pageSource = readFileSync(new URL('../../../Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js', import.meta.url), 'utf8');
const witnessSource = readFileSync(new URL('./witness.js', import.meta.url), 'utf8');
const sha256 = value => createHash('sha256').update(value).digest('hex');
const sourceSHA256 = sha256(pageSource), witnessSHA256 = sha256(witnessSource);
const url = 'https://chatgpt.com/c/11111111-1111-4111-8111-111111111111';
const businessA = '11111111-1111-4111-8111-111111111111';
const businessB = '22222222-2222-4222-8222-222222222222';
const native = {applicationID: 'com.google.Chrome', sessionID: '4242:1', windowID: '17', tabID: '19'};
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==', 'base64');
const html = `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>Offline witness experiment</title>
<style>body{font:16px sans-serif;margin:20px}button{margin:8px;padding:12px}form{padding:10px}#editor{min-height:50px;border:1px solid gray}img{width:24px;height:24px}iframe{width:240px;height:70px;display:block}</style>
<button id="body-control" type="button">Reading body</button><button id="entry" type="button">Synthetic page-owned thumbnail</button>
<iframe srcdoc="<button>Local child focus</button>" title="Local focus boundary"></iframe>
<form data-chatgpt-composer data-composer-placement="thread" data-thread-find-composer="true">
<div id="editor" contenteditable="true" role="textbox" aria-label="询问 ChatGPT">Synthetic original draft with noncollapsed selection.</div>
<input type="file" aria-label="附加文件" style="display:none">
<div id="old-card" role="button" aria-label="old.png"><img alt="old.png" src="data:image/png;base64,${png.toString('base64')}"></div>
<button type="submit">Never send</button></form><dialog id="modal">Blocking modal</dialog></html>`;
const results = [], unexpectedRequests = [];
let browser, context, checks = 0, totalSyntheticInputs = 0;
function check(condition, message) { checks++; assert.ok(condition, message); }
function equal(actual, expected, message) { checks++; assert.deepEqual(actual, expected, message); }

async function fresh({publish = true, defer = false} = {}) {
  const page = await context.newPage();
  page.setDefaultTimeout(4_000);
  await page.goto(url);
  await page.evaluate(({businessA, businessB, native, asset, pngBase64}) => {
    const form = document.querySelector('form'), editor = document.querySelector('#editor');
    const input = form.querySelector('input'), entry = document.querySelector('#entry');
    const rootObject = {}, oldCard = document.querySelector('#old-card'), oldImage = oldCard.querySelector('img');
    const fixture = window.fixture = {form, editor, input, entry, oldCard, oldImage, rootObject,
      native, asset, host: {connectionEpoch: 1, permissionEpoch: 1, allowed: true},
      pngBytes: [...Uint8Array.from(atob(pngBase64), char => char.charCodeAt(0))],
      commands: [], fileEvents: [], sends: 0, requests: [], held: [], defer: false,
      beforePointer: null, deferSink: false, sinkResolve: null, frozenTargetIdentityKept: true,
      focusEvents: [], businessA, businessB};
    fixture.setBusiness = id => {
      const leaf = {stateNode: form, memoizedProps: {}, return: null};
      const mode = {memoizedProps: {conversationId: id, isHome: false, isWork: false, readOnly: false}, child: leaf};
      const draft = {memoizedProps: {conversationId: id, draftKey: id, isWorkConversation: false,
        isTemporaryChat: false, readOnly: false, surfacePlacement: {kind: 'thread'}}, child: mode};
      const root = {tag: 3, stateNode: rootObject, child: draft, return: null};
      leaf.return = mode; mode.return = draft; draft.return = root;
      form.__reactFiber$clickWitnessFixture = leaf;
      rootObject.current = root;
    };
    fixture.setBusiness(businessA);
    form.addEventListener('submit', event => { event.preventDefault(); fixture.sends++; });
    input.addEventListener('change', event => fixture.fileEvents.push({trusted: event.isTrusted,
      at: performance.now(), fileCount: input.files.length}));
    for (const type of ['blur', 'focus']) window.addEventListener(type, event => {
      if (event.target === window) fixture.focusEvents.push({type, trusted: event.isTrusted});
    });
    // Adversarial earlier capture listener. These actions intentionally happen
    // AFTER event creation but BEFORE the protocol's entry handler.
    document.addEventListener('pointerdown', event => {
      if (event.target !== entry || !fixture.beforePointer) return;
      const action = fixture.beforePointer; fixture.beforePointer = null;
      const until = performance.now() + 15;
      while (performance.now() < until) { /* bounded renderer long task */ }
      if (action === 'late-publish') fixture.lab.publishWitness();
      if (action === 'business-ABA') {
        fixture.setBusiness(businessB); fixture.setBusiness(businessA);
      }
    }, true);
    fixture.command = value => {
      fixture.commands.push({action: value.action, at: performance.now()});
      return window.riftletWebAcceptance(value, native);
    };
    fixture.baseline = () => {
      const selection = getSelection();
      return {text: editor.textContent, html: editor.innerHTML, anchor: selection.anchorOffset,
        focus: selection.focusOffset, anchorIsOriginal: selection.anchorNode === editor.firstChild,
        focusIsOriginal: selection.focusNode === editor.firstChild, collapsed: selection.isCollapsed,
        active: document.activeElement?.id, editorFocused: document.activeElement === editor,
        oldCardSame: document.querySelector('#old-card') === oldCard,
        oldImageSame: oldCard.querySelector('img') === oldImage, oldSource: oldImage.currentSrc,
        oldCount: form.querySelectorAll('[role=button][aria-label]').length, sends: fixture.sends};
    };
    fixture.selectRange = () => {
      const range = document.createRange(); range.setStart(editor.firstChild, 3); range.setEnd(editor.firstChild, 20);
      getSelection().removeAllRanges(); getSelection().addRange(range);
      document.querySelector('#body-control').focus({preventScroll: true});
    };
    fixture.reply = (mutation = null) => {
      const item = fixture.held.shift();
      if (!item) throw Error('NO_HELD_REQUEST');
      const response = {request: JSON.parse(JSON.stringify(item.request)), bytes: [...fixture.pngBytes]};
      if (mutation === 'request') response.request.requestID = crypto.randomUUID();
      if (mutation === 'attempt') response.request.asset.attempt++;
      if (mutation === 'hash') response.request.asset.sha256 = '0'.repeat(64);
      if (mutation === 'bytes') response.bytes[response.bytes.length - 1] ^= 1;
      item.resolve(response);
    };
  }, {businessA, businessB, native, asset: {assetID: randomUUID(), sha256: sha256(png), byteCount: png.length,
    attempt: 1, visibilityRevision: 1}, pngBase64: png.toString('base64')});
  await page.waitForFunction(() => fixture.oldImage.complete && fixture.oldImage.naturalWidth === 1);
  await page.evaluate(pageSource);
  await page.evaluate(witnessSource);
  await page.locator('#body-control').click();
  await page.evaluate(({publish, defer}) => {
    fixture.defer = defer;
    fixture.selectRange();
    fixture.lab = createClickTimeWitnessExperiment({entry: fixture.entry, form: fixture.form,
      editor: fixture.editor, fileInput: fixture.input,
      captureTarget: () => fixture.command({action: 'captureTarget'}),
      validateTarget: target => fixture.command({action: 'validate', target}).valid,
      readAsset: () => fixture.asset, readHost: () => fixture.host,
      requestAsset: request => {
        fixture.requests.push(request);
        if (fixture.defer) return new Promise(resolve => fixture.held.push({request, resolve}));
        return Promise.resolve({request, bytes: [...fixture.pngBytes]});
      },
      syntheticInput: ({request, bytes, originalTarget}) => {
        if (request.target !== originalTarget || !Object.isFrozen(originalTarget)) {
          fixture.frozenTargetIdentityKept = false; throw Error('FROZEN_TARGET_REPLACED');
        }
        // Adversarial observation-only sink. It invokes no File/input protocol,
        // allowing the post-consumption uncertainty boundary to be tested.
        if (fixture.deferSink) return new Promise(resolve => { fixture.sinkResolve = resolve; });
        const identity = {operationID: request.operationID, assetID: request.asset.assetID,
          attempt: request.asset.attempt, assetSHA256: request.asset.sha256, target: originalTarget};
        fixture.originalIdentity = identity;
        fixture.command({action: 'begin', target: originalTarget, identity,
          uploadName: 'riftlet-' + identity.operationID + '.png', mediaType: 'image/png', byteCount: bytes.length});
        fixture.command({action: 'chunk', target: originalTarget, identity, chunkIndex: 0,
          chunkBase64: btoa(String.fromCharCode(...bytes))});
        fixture.command({action: 'commit', target: originalTarget, identity, chunkIndex: 1});
      }});
    if (publish) fixture.lab.publishWitness();
  }, {publish, defer});
  return page;
}

async function snapshot(page) {
  return page.evaluate(() => ({...fixture.lab.snapshot(), fileEvents: fixture.fileEvents,
    commands: fixture.commands.map(value => value.action), requestCount: fixture.requests.length,
    sends: fixture.sends, preservedTargetObject: fixture.frozenTargetIdentityKept}));
}
async function waitSettled(page) {
  await page.waitForFunction(() => fixture.lab.snapshot().pending === null);
}
async function refused(page, reason) {
  await waitSettled(page);
  const value = await snapshot(page);
  check(value.receipts.some(receipt => receipt.status === 'REFUSED' && receipt.reason === reason), reason);
  equal(value.fileEvents.length, 0, 'refusal has zero fixture File change');
  equal(value.commands.filter(action => ['begin', 'chunk', 'commit'].includes(action)), [], 'refusal enters no input protocol');
  equal(value.sends, 0, 'refusal sends nothing');
  return value;
}
async function heldPage() {
  const page = await fresh({defer: true});
  await page.locator('#entry').click();
  await page.waitForFunction(() => fixture.held.length === 1);
  equal((await snapshot(page)).fileEvents.length, 0, 'asset wait has no input');
  return page;
}

async function run() {
  browser = await chromium.launch({headless: true,
    ...(process.env.RIFTLET_TEST_CHROMIUM ? {executablePath: process.env.RIFTLET_TEST_CHROMIUM} : {}),
    args: ['--disable-background-networking', '--disable-component-update']});
  const browserVersion = browser.version();
  context = await browser.newContext({offline: true, serviceWorkers: 'block', viewport: {width: 900, height: 700}});
  await context.route('**/*', route => {
    const request = route.request();
    if (request.url() === url && request.method() === 'GET' && request.resourceType() === 'document')
      return route.fulfill({status: 200, contentType: 'text/html; charset=utf-8', body: html});
    unexpectedRequests.push({method: request.method(), resourceType: request.resourceType()});
    return route.abort('blockedbyclient');
  });

  // A vs B. Host target ACK is absent in BOTH. Only B has the browser's actual
  // event route in the same document as the completed, pre-event page witness.
  let page = await fresh();
  const baseline = await page.evaluate(() => fixture.baseline());
  check(!baseline.editorFocused && !baseline.collapsed && baseline.oldCount === 1, 'unfocused draft baseline');
  equal(await page.evaluate(() => fixture.lab.nativeClickWithoutHostACK()), false, 'native comparison refuses');
  equal((await snapshot(page)).fileEvents.length, 0, 'page witness alone does not authorize an external native click');
  await page.locator('#entry').click();
  await waitSettled(page);
  await page.waitForFunction(() => window.__riftletWebAcceptance20261027v13.tail.operations
    .get(fixture.originalIdentity.operationID)?.fileHashVerified === true);
  let outcome = await snapshot(page);
  equal(outcome.commands.filter(action => ['begin', 'chunk', 'commit'].includes(action)), ['begin', 'chunk', 'commit'], 'unique fixture protocol input');
  equal(outcome.fileEvents.length, 1, 'exactly one actual browser File change');
  check(!outcome.fileEvents[0].trusted, 'File change is programmatic, not physical');
  equal(outcome.captureCount, 1, 'pointer handlers never capture/rebind');
  check(outcome.preservedTargetObject, 'sink receives exact frozen target object');
  const frozen = outcome.receipts.find(receipt => receipt.status === 'FROZEN');
  check(frozen.witnessCompletedAt < frozen.eventAt && frozen.eventAt <= frozen.handlerAt, 'strict same-renderer causal order');
  equal(await page.evaluate(() => fixture.baseline()), baseline, 'text, noncollapsed selection and original attachment preserved');
  const observed = await page.evaluate(() => fixture.command({action: 'observe',
    target: fixture.originalIdentity.target, identity: fixture.originalIdentity}));
  equal(observed.observation.state, 'inputTriggered', 'no invented upload start or completion');
  check(!observed.observation.uploadStart, 'start remains unproved');
  await page.locator('#entry').dblclick();
  outcome = await snapshot(page);
  equal(outcome.fileEvents.length, 1, 'double/repeated click cannot consume original asset twice');
  equal(outcome.sinkInvocationCount, 1, 'consumed ledger does not replay');
  equal(outcome.captureCount, 1, 'repeat click does not capture a replacement');
  await page.evaluate(() => {
    fixture.asset.attempt++; fixture.asset.visibilityRevision++;
    fixture.lab.publishWitness();
  });
  await page.locator('#entry').click();
  outcome = await snapshot(page);
  equal(outcome.fileEvents.length, 1, 'new attempt/visibility revision cannot reauthorize a consumed asset');
  equal(outcome.sinkInvocationCount, 1, 'no second sink invocation after metadata changes');
  check(outcome.receipts.some(receipt => receipt.reason === 'ASSET_ALREADY_CONSUMED'), 'per-asset once ledger');
  results.push({case: 'pre_event_page_witness_browser_owned_entry', status: 'PASS', hostTargetACK: 'ABSENT_BY_CONSTRUCTION',
    nativeEntryComparison: 'REFUSED_MODEL_ONLY', pointerSource: frozen.source, syntheticFixtureInputCount: 1,
    witnessCompletedBeforeEventMS: Number((frozen.eventAt - frozen.witnessCompletedAt).toFixed(3)),
    eventToHandlerMS: Number((frozen.handlerAt - frozen.eventAt).toFixed(3)),
    state: observed.observation.state, textSelectionOldAttachmentPreserved: true});
  totalSyntheticInputs++;
  await page.close();

  page = await fresh();
  await page.evaluate(() => { fixture.deferSink = true; });
  await page.locator('#entry').click();
  await page.waitForFunction(() => fixture.sinkResolve !== null);
  await page.frameLocator('iframe').locator('button').click();
  await page.locator('#body-control').click();
  await page.evaluate(() => fixture.sinkResolve());
  await waitSettled(page);
  outcome = await snapshot(page);
  check(outcome.receipts.some(receipt => receipt.status === 'UNKNOWN'
    && receipt.reason === 'CONSUMED_BOUNDARY_INVALIDATED'), 'post-consumption boundary remains unknown');
  equal(outcome.receipts.filter(receipt => receipt.status === 'CONSUMED').length, 0,
    'late sink resolve cannot turn invalidated observation into completion');
  equal(outcome.receipts.filter(receipt => receipt.status === 'REFUSED').length, 0,
    'already invoked sink cannot be reported as pre-input refusal');
  equal(outcome.fileEvents.length, 0, 'observation-only sink emitted no File');
  equal(outcome.commands.filter(action => ['begin', 'chunk', 'commit'].includes(action)), [],
    'observation-only sink never called production input');
  await page.evaluate(() => fixture.lab.publishWitness());
  await page.locator('#entry').click();
  equal((await snapshot(page)).sinkInvocationCount, 1, 'unknown sink result cannot be re-invoked');
  results.push({case: 'consumed_sink_boundary_and_late_reply', status: 'PASS', input: 0,
    sinkInvocations: 1, result: 'UNKNOWN_RETAINED'});
  await page.close();

  page = await fresh({publish: false});
  await page.locator('#entry').click();
  await refused(page, 'NO_PRE_EVENT_WITNESS');
  await page.evaluate(() => fixture.lab.publishWitness());
  equal((await snapshot(page)).fileEvents.length, 0, 'later witness never replays rejected event');
  results.push({case: 'true_zero_page_witness_and_later_publication', status: 'PASS', input: 0});
  await page.close();

  page = await fresh({publish: false});
  await page.evaluate(() => { fixture.beforePointer = 'late-publish'; });
  await page.locator('#entry').click();
  outcome = await refused(page, 'WITNESS_NOT_PRE_EVENT');
  const late = outcome.receipts.find(receipt => receipt.reason === 'WITNESS_NOT_PRE_EVENT');
  check(late.witnessCompletedAt >= late.eventAt, 'real event existed before deliberately late witness');
  results.push({case: 'late_witness_in_earlier_capture_listener', status: 'PASS', input: 0,
    witnessAfterEventMS: Number((late.witnessCompletedAt - late.eventAt).toFixed(3)),
    eventToHandlerMS: Number((late.handlerAt - late.eventAt).toFixed(3))});
  await page.close();

  page = await fresh();
  await page.evaluate(() => { fixture.beforePointer = 'business-ABA'; });
  await page.locator('#entry').click();
  await refused(page, 'ORIGINAL_WITNESS_INVALID');
  results.push({case: 'delayed_handler_business_ABA', status: 'PASS', input: 0});
  await page.close();

  page = await fresh();
  await page.evaluate(() => fixture.entry.dispatchEvent(new PointerEvent('pointerdown', {
    bubbles: true, composed: true, pointerId: 1, pointerType: 'mouse', isPrimary: true, button: 0})));
  await refused(page, 'NOT_ORIGINAL_TRUSTED_PRIMARY_POINTER');
  results.push({case: 'untrusted_dispatchEvent', status: 'PASS', input: 0});
  await page.close();

  page = await fresh();
  const box = await page.locator('#entry').boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.locator('#body-control').hover();
  await page.mouse.up();
  await refused(page, 'POINTER_UP_DOES_NOT_MATCH');
  results.push({case: 'release_outside_original_control', status: 'PASS', input: 0});
  await page.close();

  // Async replies are fixture-controlled. None may select another target.
  for (const mutation of ['business-ABA', 'host-epoch-ABA', 'permission-ABA', 'asset-revision', 'detach', 'modal']) {
    page = await heldPage();
    await page.evaluate(mutation => {
      if (mutation === 'business-ABA') { fixture.setBusiness(fixture.businessB); fixture.setBusiness(fixture.businessA); }
      if (mutation === 'host-epoch-ABA') fixture.host.connectionEpoch += 2;
      if (mutation === 'permission-ABA') { fixture.host.allowed = false; fixture.host.permissionEpoch++; fixture.host.allowed = true; fixture.host.permissionEpoch++; }
      if (mutation === 'asset-revision') fixture.asset.visibilityRevision++;
      if (mutation === 'detach') fixture.editor.replaceWith(fixture.editor.cloneNode(true));
      if (mutation === 'modal') document.querySelector('#modal').showModal();
      fixture.reply();
    }, mutation);
    outcome = await refused(page, 'ORIGINAL_WITNESS_CHANGED_BEFORE_INPUT');
    equal(outcome.captureCount, 1, 'async invalidation never reacquires current target');
    results.push({case: 'asset_wait_' + mutation, status: 'PASS', input: 0});
    await page.close();
  }

  page = await heldPage();
  await page.frameLocator('iframe').locator('button').click();
  await page.locator('#body-control').click();
  await page.evaluate(() => fixture.reply());
  await refused(page, 'DOCUMENT_BOUNDARY_CHANGED');
  const focusEvents = await page.evaluate(() => fixture.focusEvents);
  equal(focusEvents.map(event => event.type), ['blur', 'focus'], 'real Chromium Window focus roundtrip');
  check(focusEvents.every(event => event.trusted), 'focus boundary events are UA dispatched');
  results.push({case: 'asset_wait_actual_frame_focus_roundtrip', status: 'PASS', input: 0,
    scope: 'HEADLESS_FRAME_BOUNDARY_NOT_MACOS_APPLICATION_SWITCH'});
  await page.close();

  for (const mutation of ['request', 'attempt', 'hash', 'bytes']) {
    page = await heldPage();
    await page.evaluate(mutation => fixture.reply(mutation), mutation);
    await refused(page, mutation === 'bytes' ? 'ASSET_BYTES_MISMATCH' : 'ASSET_REPLY_IDENTITY_MISMATCH');
    results.push({case: 'wrong_async_reply_' + mutation, status: 'PASS', input: 0});
    await page.close();
  }
  equal(unexpectedRequests, [], 'no external request or upload endpoint');
  await context.close();
  return {status: 'PASS', scope: 'OFFLINE_BROWSER_OWNED_ENTRY_ARCHITECTURE_EXPERIMENT',
    sourceSHA256, witnessSHA256, driverVersion, browserVersion, nodeVersion: process.version, checks,
    productionInputAuthority: false, liveInputAuthority: false, productionAdmission: false,
    syntheticFixtureInputCount: totalSyntheticInputs, results,
    environment: {headless: true, freshTemporaryProfile: true, nonPersistentContext: true,
      offline: true, serviceWorkers: 'blocked', externalRequests: 0, userProfileUsed: false, extensionInstalled: false},
    limits: ['Alternate page-owned entry; not a fix for the original native NSPanel click',
      'Native target ACK absent and host metadata simulated; no Native Messaging transport tested',
      'Trusted UA/CDP pointer is software automation, not a human physical mouse',
      'Synthetic React ancestry; no live ChatGPT or real screenshot/uploadStarted/attached',
      'Only same-renderer timestamps; no host/renderer clock comparison or backfilled ACK',
      'No pre-event page witness still refuses; browser startup and uninstalled monitor remain uncovered']};
}

let timer;
try {
  const bound = new Promise((_, reject) => { timer = setTimeout(() => reject(Error('bounded architecture lab deadline')), 60_000); });
  console.log(JSON.stringify(await Promise.race([run(), bound]), null, 2));
} catch (error) {
  console.error(JSON.stringify({status: 'FAIL', sourceSHA256, witnessSHA256, driverVersion, checks,
    syntheticFixtureInputCount: totalSyntheticInputs, completedCases: results,
    reason: String(error.message), unexpectedRequestCount: unexpectedRequests.length}, null, 2));
  process.exitCode = 1;
} finally {
  clearTimeout(timer);
  await browser?.close();
}
