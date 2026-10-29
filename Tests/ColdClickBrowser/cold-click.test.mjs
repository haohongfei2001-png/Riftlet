// Real browser DOM regression, entirely offline and synthetic. This does not
// exercise Apple Events, AppKit clicks, ChatGPT React, or upload admission.
import assert from 'node:assert/strict';
import {createHash, randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);
const {chromium} = require('playwright');
const driverVersion = require('playwright/package.json').version;
const source = readFileSync(new URL('../../Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js', import.meta.url), 'utf8');
const sourceSHA256 = createHash('sha256').update(source).digest('hex');
const fixtureURL = 'https://chatgpt.com/c/11111111-1111-4111-8111-111111111111';
const native = {applicationID: 'com.google.Chrome', sessionID: '4242:1', windowID: '17', tabID: '19'};
const businessA = '11111111-1111-4111-8111-111111111111';
const businessB = '22222222-2222-4222-8222-222222222222';
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==', 'base64');
const hash = data => createHash('sha256').update(data).digest('hex');
const html = `<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<title>Riftlet offline synthetic browser regression</title>
<style>body{font:16px sans-serif;margin:20px}button{margin:10px}iframe{display:block;width:240px;height:80px}form{margin-top:20px;padding:10px}#editor{min-height:60px;border:1px solid gray}img{width:24px;height:24px}</style>
<button type="button" id="body-control">阅读正文</button><button type="button" id="sidebar-control">侧栏</button>
<iframe title="Local focus boundary" srcdoc="<button type='button'>Local child focus</button>"></iframe>
<form data-chatgpt-composer data-composer-placement="thread" data-thread-find-composer="true">
<div id="editor" contenteditable="true" role="textbox" aria-label="询问 ChatGPT">Synthetic nonempty draft with a selected range.</div>
<input type="file" aria-label="附加文件" style="display:none">
<div id="old-card" role="button" aria-label="old-fixture.png"><img alt="old-fixture.png" src="data:image/png;base64,${png.toString('base64')}"></div>
<button type="submit">Send fixture only</button></form>
<dialog id="modal">A real native dialog outside the composer</dialog></html>`;

const results = [];
const unexpectedRequests = [];
let browser;
let checks = 0;
function check(condition, message) { checks++; assert.ok(condition, message); }
function equal(actual, expected, message) { checks++; assert.deepEqual(actual, expected, message); }
function identity(target) {
  return {operationID: randomUUID(), assetID: randomUUID(), attempt: 1, assetSHA256: hash(png), target};
}
function beginCommand(original) {
  return {action: 'begin', target: original.target, identity: original,
    uploadName: 'riftlet-' + original.operationID + '.png', mediaType: 'image/png', byteCount: png.length};
}
async function command(page, value) {
  return page.evaluate(({value, native}) => window.riftletWebAcceptance(value, native), {value, native});
}
async function capture(page) { return command(page, {action: 'captureTarget'}); }
async function valid(page, target) { return (await command(page, {action: 'validate', target})).valid; }
async function rejects(page, value, expected) {
  const result = await page.evaluate(({value, native}) => {
    try { window.riftletWebAcceptance(value, native); return null; }
    catch (error) { return String(error.message); }
  }, {value, native});
  equal(result, expected, 'exact rejection; no fixture fallback or new target');
}

async function freshPage(context) {
  const page = await context.newPage();
  page.setDefaultTimeout(5_000);
  await page.goto(fixtureURL);
  await page.evaluate(({businessA}) => {
    const form = document.querySelector('form'), editor = document.querySelector('#editor');
    const input = form.querySelector('input'), oldCard = document.querySelector('#old-card');
    const oldImage = oldCard.querySelector('img'), rootObject = {};
    const fixture = window.fixture = {form, editor, input, oldCard, oldImage, rootObject,
      events: [], fileEvents: [], submissions: 0, priorTargets: []};
    // Only business ancestry is a stand-in. DOM nodes, visibility, selection,
    // File/DataTransfer, crypto, MutationObserver and focus events are Chromium's.
    fixture.setBusiness = id => {
      const leaf = {stateNode: form, memoizedProps: {}, return: null};
      const mode = {memoizedProps: {conversationId: id, isHome: false, isWork: false, readOnly: false}, child: leaf};
      const draft = {memoizedProps: {conversationId: id, draftKey: id, isWorkConversation: false,
        isTemporaryChat: false, readOnly: false, surfacePlacement: {kind: 'thread'}}, child: mode};
      const root = {tag: 3, stateNode: rootObject, child: draft, return: null};
      leaf.return = mode; mode.return = draft; draft.return = root;
      form.__reactFiber$offlineFixture = leaf;
      rootObject.current = root;
    };
    fixture.setBusiness(businessA);
    for (const type of ['blur', 'focus']) window.addEventListener(type, event => {
      if (event.target === window) fixture.events.push({type, trusted: event.isTrusted,
        focused: document.hasFocus(), visibility: document.visibilityState});
    });
    form.addEventListener('submit', event => { event.preventDefault(); fixture.submissions++; });
    input.addEventListener('change', event => {
      for (const file of input.files) fixture.fileEvents.push({name: file.name, size: file.size, type: file.type,
        trusted: event.isTrusted, timestamp: performance.now()});
    });
    fixture.baseline = () => {
      const selection = getSelection();
      return {text: editor.textContent, html: editor.innerHTML,
        anchorIsText: selection.anchorNode === editor.firstChild, anchorOffset: selection.anchorOffset,
        focusIsText: selection.focusNode === editor.firstChild, focusOffset: selection.focusOffset,
        collapsed: selection.isCollapsed, active: document.activeElement?.id,
        editorFocused: document.activeElement === editor, pageFocused: document.hasFocus(),
        oldCardSame: document.querySelector('#old-card') === oldCard,
        oldImageSame: oldCard.querySelector('img') === oldImage, oldSource: oldImage.currentSrc,
        cards: form.querySelectorAll('[role=button][aria-label]').length,
        sends: fixture.submissions};
    };
    fixture.selectRange = () => {
      const range = document.createRange(); range.setStart(editor.firstChild, 3); range.setEnd(editor.firstChild, 18);
      const selection = getSelection(); selection.removeAllRanges(); selection.addRange(range);
      // Selection may focus the editable element on some Chromium versions.
      // Move keyboard focus outside it while retaining the exact DOM Range.
      document.querySelector('#body-control').focus({preventScroll: true});
    };
  }, {businessA});
  await page.waitForFunction(() => fixture.oldImage.complete && fixture.oldImage.naturalWidth === 1);
  await page.evaluate(source);
  await page.locator('#body-control').click();
  return page;
}

async function focusRoundTrip(page) {
  const before = await page.evaluate(() => fixture.events.length);
  // A real Chromium window focus boundary, using native frame focus. Headless
  // tab bringToFront does not model OS application switching and is not used.
  await page.frameLocator('iframe').locator('button').click();
  await page.locator('#body-control').click();
  const events = await page.evaluate(before => fixture.events.slice(before), before);
  equal(events.map(event => event.type), ['blur', 'focus'], 'real Window blur then focus');
  check(events.every(event => event.trusted), 'browser-produced focus events, never dispatchEvent');
  check(await page.evaluate(() => document.hasFocus() && document.activeElement !== fixture.editor),
    'top-level document focused with editor unfocused');
}

async function run() {
  // Optional local path may refer to an already installed testing binary. Never
  // infer, attach to, launch with, or load the user's existing Chrome profile.
  browser = await chromium.launch({headless: true,
    ...(process.env.RIFTLET_TEST_CHROMIUM ? {executablePath: process.env.RIFTLET_TEST_CHROMIUM} : {}),
    args: ['--disable-background-networking', '--disable-component-update']});
  const browserVersion = browser.version();
  const context = await browser.newContext({offline: true, serviceWorkers: 'block', viewport: {width: 900, height: 700}});
  await context.route('**/*', route => {
    const request = route.request();
    if (request.url() === fixtureURL && request.method() === 'GET' && request.resourceType() === 'document') {
      return route.fulfill({status: 200, contentType: 'text/html; charset=utf-8', body: html});
    }
    unexpectedRequests.push({method: request.method(), resourceType: request.resourceType()});
    return route.abort('blockedbyclient');
  });

  const page = await freshPage(context);
  let target = await capture(page);
  await page.evaluate(() => {
    const registry = window.__riftletWebAcceptance20261027v13;
    fixture.firstState = registry.tail;
    fixture.firstTarget = registry.tail.target;
    fixture.firstTargetJSON = JSON.stringify(registry.tail.target);
  });
  check(await valid(page, target), 'first fixture target is valid');
  const firstTarget = target;
  for (let cycle = 0; cycle < 40; cycle++) {
    const old = target;
    await focusRoundTrip(page);
    check(!(await valid(page, old)), 'old lease stays revoked before renewed capture');
    target = await capture(page);
    check(target.documentID !== old.documentID && target.draftGeneration !== old.draftGeneration,
      'each renewed target has distinct immutable authority');
    check(await valid(page, target), 'new capture valid without another pointer action or editor focus');
    check(!(await valid(page, old)), 'new capture never reauthorizes old target');
  }
  await rejects(page, beginCommand(identity(firstTarget)), 'TARGET_INVALID');
  equal(await page.evaluate(() => {
    const registry = window.__riftletWebAcceptance20261027v13;
    return {count: registry.count, sameState: registry.tail === fixture.firstState,
      oldObjectUnchanged: JSON.stringify(fixture.firstTarget) === fixture.firstTargetJSON,
      operations: registry.tail.operations.size, fileEvents: fixture.fileEvents.length, sends: fixture.submissions};
  }), {count: 1, sameState: true, oldObjectUnchanged: true, operations: 0, fileEvents: 0, sends: 0},
  'forty no-input focus changes use one retained state without deleting operations');
  results.push({name: 'empty_focus_rearm', status: 'PASS', cycles: 40,
    browserTrustedWindowFocusEvents: 80, retainedStates: 1, realUploads: 0});

  const beforeModal = target;
  await page.evaluate(() => document.querySelector('#modal').showModal());
  await rejects(page, {action: 'captureTarget'}, 'COMPOSER_UNAVAILABLE');
  check(!(await valid(page, beforeModal)), 'actual modal blocks the previous lease');
  await page.evaluate(() => document.querySelector('#modal').close());
  await page.locator('#body-control').click();
  target = await capture(page);
  check(target.documentID !== beforeModal.documentID, 'post-modal capture is a fresh target');
  await rejects(page, beginCommand(identity(beforeModal)), 'TARGET_INVALID');
  equal(await page.evaluate(() => fixture.fileEvents.length), 0, 'modal refusal has zero file input');
  results.push({name: 'modal_and_revoked_target', status: 'PASS', fileInputs: 0});

  for (const button of ['#body-control', '#sidebar-control']) {
    await page.locator(button).click();
    check(await valid(page, target), 'body/sidebar interaction alone does not revoke a continuous composer');
  }
  await page.evaluate(() => fixture.selectRange());
  const beforeInput = await page.evaluate(() => fixture.baseline());
  check(beforeInput.pageFocused && !beforeInput.editorFocused && !beforeInput.collapsed
    && beforeInput.anchorIsText && beforeInput.focusIsText && beforeInput.text.length > 0,
  'nonempty draft and noncollapsed selection; editor not focused');
  check(beforeInput.oldCardSame && beforeInput.oldImageSame && beforeInput.cards === 1,
    'one stable original attachment exists before input');
  check(await valid(page, target), 'pre-input original fixture target remains valid');
  const original = identity(target);
  await command(page, beginCommand(original));
  await command(page, {action: 'chunk', target, identity: original, chunkIndex: 0, chunkBase64: png.toString('base64')});
  await command(page, {action: 'commit', target, identity: original, chunkIndex: 1});
  await page.waitForFunction(operationID => {
    const op = window.__riftletWebAcceptance20261027v13.tail.operations.get(operationID);
    return op?.inputCount === 1 && op.fileHashVerified;
  }, original.operationID);
  const afterInput = await page.evaluate(() => fixture.baseline());
  equal(afterInput, beforeInput, 'actual browser DOM text, selection, focus and original card preserved');
  const file = await page.evaluate(async () => {
    const value = fixture.input.files[0], bytes = await value.arrayBuffer();
    const sha256 = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))]
      .map(value => value.toString(16).padStart(2, '0')).join('');
    return {name: value.name, size: value.size, type: value.type, sha256,
      count: fixture.input.files.length, events: fixture.fileEvents, sends: fixture.submissions};
  });
  equal({name: file.name, size: file.size, type: file.type, sha256: file.sha256, count: file.count, sends: file.sends},
    {name: 'riftlet-' + original.operationID + '.png', size: png.length, type: 'image/png', sha256: hash(png), count: 1, sends: 0},
  'one real File/DataTransfer carries the exact synthetic bytes');
  equal(file.events.length, 1, 'one actual DOM change only');
  check(!file.events[0].trusted, 'programmatic attachment change is explicitly not physical input');
  await rejects(page, {action: 'commit', target, identity: original, chunkIndex: 1}, 'COMMIT_REFUSED');
  const observed = await command(page, {action: 'observe', target, identity: original});
  equal(observed.observation.state, 'inputTriggered', 'file input is not fabricated uploadStarted or attached');
  check(!observed.observation.uploadStart, 'no fake upload start');
  await page.evaluate(operationID => {
    fixture.operationState = window.__riftletWebAcceptance20261027v13.tail;
    fixture.originalOperation = fixture.operationState.operations.get(operationID);
    fixture.originalOperationIdentity = JSON.stringify(fixture.originalOperation.identity);
  }, original.operationID);
  results.push({name: 'unfocused_exact_synthetic_input', status: 'PASS', begin: 1, chunk: 1,
    acceptedCommit: 1, fileChange: 1, sends: 0, state: 'inputTriggered',
    textPreserved: true, noncollapsedSelectionPreserved: true, oldAttachmentObjectPreserved: true});

  await focusRoundTrip(page);
  const nextTarget = await capture(page);
  check(nextTarget.documentID !== target.documentID, 'an operation-bearing lease requires a distinct retained state');
  equal(await page.evaluate(() => window.__riftletWebAcceptance20261027v13.count), 2,
    'operation-bearing state was retained instead of recycled');
  await rejects(page, {action: 'commit', target, identity: original, chunkIndex: 1}, 'TARGET_INVALID');
  const oldObservation = await command(page, {action: 'observe', target, identity: original});
  equal(oldObservation.observation.identity, original, 'observation stays bound to original operation');
  equal(oldObservation.observation.state, 'inputTriggered', 'old operation remains read-only observable');
  equal(await page.evaluate(operationID => ({
    sameObject: fixture.operationState.operations.get(operationID) === fixture.originalOperation,
    identityUnchanged: JSON.stringify(fixture.originalOperation.identity) === fixture.originalOperationIdentity,
    inputCount: fixture.originalOperation.inputCount, fileEvents: fixture.fileEvents.length,
    sends: fixture.submissions
  }), original.operationID), {sameObject: true, identityUnchanged: true, inputCount: 1, fileEvents: 1, sends: 0},
  'retained original operation never re-input or silently replaced');
  results.push({name: 'original_operation_retained', status: 'PASS', retainedStates: 2, originalInputCount: 1});

  await page.evaluate(({businessA, businessB}) => {
    fixture.setBusiness(businessB); fixture.setBusiness(businessA);
  }, {businessA, businessB});
  check(!(await valid(page, nextTarget)), 'real root setter A to B to A invalidates old binding');
  const afterABA = await capture(page);
  check(afterABA.draftGeneration !== nextTarget.draftGeneration, 'ABA uses a distinct newly observed binding');
  const abaObservation = await command(page, {action: 'observe', target, identity: original});
  equal(abaObservation.observation.state, 'invalidated', 'ABA cannot restore previous operation observation proof');
  equal(await page.evaluate(() => ({fileEvents: fixture.fileEvents.length, sends: fixture.submissions,
    oldOperationSame: fixture.operationState.operations.values().next().value === fixture.originalOperation})),
  {fileEvents: 1, sends: 0, oldOperationSame: true}, 'ABA retains the original record without another input');
  results.push({name: 'business_ABA_refusal', status: 'PASS', originalInputCount: 1, newInputs: 0});

  equal(unexpectedRequests, [], 'offline fixture requested no external resources or upload endpoint');
  await context.close();
  return {status: 'PASS', scope: 'OFFLINE_HEADLESS_CHROMIUM_SYNTHETIC_DOM', sourceSHA256,
    driverVersion, browserVersion, nodeVersion: process.version, checks, cases: results,
    environment: {freshNonPersistentContext: true, headless: true, offline: true, serviceWorkers: 'blocked',
      requestsOutsideFixture: unexpectedRequests.length, userProfileUsed: false},
    notRun: ['Apple Events', 'native pre-event ACK timing', 'AppKit/physical mouse',
      'OS app/tab activation', 'live ChatGPT React/real system screenshot', 'real uploadStarted/attached'],
    clocks: 'Only same-renderer event timestamps are inspected; no renderer-host clock subtraction or ACK claim.'};
}

let timer;
try {
  const timeout = new Promise((_, reject) => { timer = setTimeout(() => reject(Error('bounded browser regression deadline')), 60_000); });
  console.log(JSON.stringify(await Promise.race([run(), timeout]), null, 2));
} catch (error) {
  console.error(JSON.stringify({status: 'FAIL', sourceSHA256, driverVersion, checks, completedCases: results,
    reason: String(error.message), unexpectedRequestCount: unexpectedRequests.length}, null, 2));
  process.exitCode = 1;
} finally {
  clearTimeout(timer);
  await browser?.close();
}
