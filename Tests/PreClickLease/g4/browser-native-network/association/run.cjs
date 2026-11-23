'use strict';

const assert = require('node:assert/strict');
const {execFileSync, spawn, spawnSync} = require('node:child_process');
const {randomUUID} = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {setTimeout: delay} = require('node:timers/promises');
const {FixtureDriver} = require('../../../../OriginalDocumentDelivery/renderer/driver.cjs');
const {cleanupOwnedChrome} = require('../../../../WebPageProgram/native-chrome-cleanup.cjs');
const {makePNG, sha, startFixture} = require('./fixture.cjs');

const families = [
  {name:'Chrome', app:'Google Chrome', bundle:'com.google.Chrome', team:'EQHXZ8M8AV'},
  {name:'Edge', app:'Microsoft Edge', bundle:'com.microsoft.edgemac', team:'UBF8T346G9'},
];
const maxPostDataSize = 4 * 1024 * 1024;

function contentLength(headers) {
  const length = headers?.['Content-Length'] ?? headers?.['content-length'];
  if (length === undefined) return null;
  const value = String(length);
  if (!/^(0|[1-9][0-9]*)$/.test(value) || !Number.isSafeInteger(Number(value))) throw Error('invalid request length');
  return Number(value);
}

// All messages arrive from the inherited pipe of the process created below. There
// is no listener port, endpoint parameter, HAR export, or existing account here.
function watchOwnedSession(child, tab, fixture) {
  const requests = [], extraLengths = new Map(), responses = new Map(), terminals = new Map();
  let partial = '', unexpectedWrites = 0, order = 0;
  const receive = chunk => {
    const frames = (partial + chunk).split('\0');
    partial = frames.pop();
    for (const frame of frames) {
      if (!frame) continue;
      const m = JSON.parse(frame);
      if (m.sessionId !== tab.sessionId || !m.method?.startsWith('Network.')) continue;
      const e = m.params;
      order++;
      if (m.method === 'Network.requestWillBeSentExtraInfo') {
        // This cookie-free fixture retains exactly one named numeric header.
        const length = contentLength(e.headers);
        if (length !== null) extraLengths.set(e.requestId, length);
      } else if (m.method === 'Network.requestWillBeSent') {
        if (!['POST','PUT'].includes(e.request.method)) continue;
        if (e.request.url !== fixture.create && e.request.url !== fixture.put) { unexpectedWrites++; continue; }
        const initiatorSource = e.initiator.stack?.callFrames?.[0]?.url;
        requests.push({id:e.requestId, method:e.request.method, url:e.request.url, resourceType:e.type,
          frameId:e.frameId, loaderId:e.loaderId, time:e.timestamp, order, redirect:!!e.redirectResponse,
          initiatorType:e.initiator.type, initiatorIsLocalPage:initiatorSource === fixture.page,
          requestLength:contentLength(e.request.headers), hasPostData:e.request.hasPostData === true,
          inlineEntryBytes:(e.request.postDataEntries ?? []).map(entry => entry.bytes ?? null)});
      } else if (m.method === 'Network.responseReceived') {
        if (!requests.some(r => r.id === e.requestId)) continue;
        responses.set(e.requestId, {status:e.response.status, time:e.timestamp, order, url:e.response.url,
          frameId:e.frameId, loaderId:e.loaderId});
      } else if (m.method === 'Network.loadingFinished' || m.method === 'Network.loadingFailed') {
        if (!requests.some(r => r.id === e.requestId)) continue;
        terminals.set(e.requestId, {event:m.method, time:e.timestamp, order});
      }
    }
  };
  child.stdio[4].on('data', receive);
  return {requests, extraLengths, responses, terminals, unexpected:() => unexpectedWrites,
    close:() => child.stdio[4].off('data', receive)};
}

async function waitFor(read, label) {
  const deadline = performance.now() + 10000;
  do {
    const result = await read();
    if (result) return result;
    await delay(25);
  } while (performance.now() < deadline);
  throw Error(label);
}

function describe(row, stream) {
  const response = stream.responses.get(row.id), end = stream.terminals.get(row.id);
  assert.ok(response && end, 'native response and terminal event required');
  assert.equal(response.url, row.url);
  assert.equal(response.frameId, row.frameId);
  assert.equal(response.loaderId, row.loaderId);
  assert.equal(end.event, 'Network.loadingFinished');
  assert.ok(row.order < response.order && response.order < end.order, 'unexpected protocol delivery order');
  const extra = stream.extraLengths.get(row.id) ?? null;
  if (row.requestLength !== null && extra !== null) assert.equal(row.requestLength, extra);
  return {requestId:row.id, fetchNetworkId:null, frameId:row.frameId, loaderId:row.loaderId, method:row.method,
    resourceType:row.resourceType, initiatorType:row.initiatorType, initiatorIsLocalPage:row.initiatorIsLocalPage,
    urlSHA256:sha(row.url), requestTime:row.time, responseTime:response.time, terminalTime:end.time,
    requestSequence:row.order, responseSequence:response.order, terminalSequence:end.order,
    requestContentLength:row.requestLength ?? extra, basicRequestContentLength:row.requestLength,
    extraInfoRequestContentLength:extra, status:response.status, terminal:end.event, hasPostData:row.hasPostData};
}

async function payloadAssessment(cmd, request, png) {
  let result = 'unavailable', returnedTextBytes = null, observedHash = null;
  if (request.inlineEntryBytes.length && request.inlineEntryBytes.every(v => typeof v === 'string')) {
    const bytes = Buffer.concat(request.inlineEntryBytes.map(v => Buffer.from(v, 'base64')));
    if (bytes.equals(png)) observedHash = sha(bytes);
  }
  try {
    const response = await cmd('Network.getRequestPostData', {requestId:request.id});
    const bytes = Buffer.from(response.postData, 'utf8');
    returnedTextBytes = bytes.length;
    result = 'text returned';
    if (bytes.equals(png)) observedHash = sha(bytes);
  } catch (error) {
    result = /no post data/i.test(error.message) ? 'NO_POST_DATA' : 'backend error';
  }
  return {lookupCount:1, lookupResult:result, returnedTextBytes, inlineEntryCount:request.inlineEntryBytes.length,
    payloadHashUnavailable:observedHash === null, observedPUTBodySHA256:observedHash};
}

async function measure(driver, child, png, file, fixture) {
  const tab = await driver.open('about:blank');
  const cmd = (name, args={}) => driver.call(name, args, tab.sessionId);
  const stream = watchOwnedSession(child, tab, fixture);
  async function readDocument() {
    const target = (await driver.call('Target.getTargetInfo', {targetId:tab.targetId})).targetInfo;
    const win = await driver.call('Browser.getWindowForTarget', {targetId:tab.targetId});
    const frame = (await cmd('Page.getFrameTree')).frameTree.frame;
    if (target.url !== fixture.page || frame.url !== fixture.page || target.targetId !== tab.targetId) return null;
    const {result} = await cmd('Runtime.evaluate', {
      expression:"[document.getElementById('result')?.dataset.documentId, performance.timeOrigin, navigation.currentEntry?.id]",
      returnByValue:true});
    if (!result.value?.every(Boolean)) return null;
    return {targetId:target.targetId, attachedSessionId:tab.sessionId, protocolWindowId:win.windowId, frameId:frame.id,
      loaderId:frame.loaderId, documentSHA256:sha(JSON.stringify(result.value)), pageURLSHA256:sha(fixture.page)};
  }
  try {
    await cmd('Page.enable');
    await cmd('Network.enable', {maxPostDataSize, maxTotalBufferSize:16 * 1024 * 1024});
    await cmd('Page.navigate', {url:fixture.page});
    const original = await waitFor(readDocument, 'original fixture document unavailable');
    assert.equal(stream.requests.length, 0);
    const root = (await cmd('DOM.getDocument')).root;
    const {nodeId} = await cmd('DOM.querySelector', {nodeId:root.nodeId, selector:'#file'});
    assert.ok(nodeId > 0);
    await cmd('DOM.setFileInputFiles', {nodeId, files:[file]});
    const pageResult = await waitFor(async () => {
      const {result} = await cmd('Runtime.evaluate', {expression:"document.getElementById('result').dataset.result", returnByValue:true});
      return result.value && JSON.parse(result.value);
    }, 'authored page terminal unavailable');
    await waitFor(() => stream.requests.length === 2 && stream.requests.every(r => stream.terminals.has(r.id)), 'two terminal requests required');
    const after = await readDocument();
    assert.deepEqual(after, original);
    assert.deepEqual(pageResult, {input:1, change:1, fileSHA256:sha(png), terminalStatus:201});
    assert.equal(stream.unexpected(), 0);
    const [create, put] = stream.requests;
    assert.equal(create.method, 'POST'); assert.equal(create.url, fixture.create);
    assert.equal(put.method, 'PUT'); assert.equal(put.url, fixture.put);
    assert.notEqual(create.id, put.id);
    for (const request of [create, put]) {
      assert.equal(request.frameId, original.frameId);
      assert.equal(request.loaderId, original.loaderId);
      assert.equal(request.redirect, false);
      assert.equal(request.initiatorType, 'script');
      assert.equal(request.initiatorIsLocalPage, true);
    }
    const created = describe(create, stream), uploaded = describe(put, stream);
    assert.equal(created.status, 200);
    assert.equal(uploaded.status, 201);
    assert.ok(created.responseTime < uploaded.requestTime);
    assert.ok(created.responseSequence < uploaded.requestSequence);
    assert.equal(uploaded.requestContentLength, png.length);
    // Only the fixed, credential-free creation resource on our own loopback server
    // is readable. Its single-field response names one public local resource.
    const raw = await cmd('Network.getResponseBody', {requestId:create.id});
    const response = JSON.parse(Buffer.from(raw.body, raw.base64Encoded ? 'base64' : 'utf8').toString('utf8'));
    assert.deepEqual(Object.keys(response), ['upload_url']);
    assert.equal(response.upload_url, fixture.put);
    assert.equal(response.upload_url, put.url);
    const destination = new URL(response.upload_url);
    assert.equal(destination.origin, fixture.origin); assert.equal(destination.hostname, '127.0.0.1');
    assert.equal(destination.search, ''); assert.equal(destination.username + destination.password, '');
    assert.equal(fixture.records.creates.length, 1); assert.equal(fixture.records.puts.length, 1);
    assert.equal(fixture.records.puts[0].bodySHA256, sha(png)); assert.equal(fixture.records.puts[0].bytes, png.length);
    return {original, after, fileSelection:'single disposable local file input', page:pageResult, create:created, put:uploaded,
      creationResponse:{readable:true, host:destination.hostname, destinationURLSHA256:sha(response.upload_url), fullDestinationComparedInMemory:true},
      payload:await payloadAssessment(cmd, put, png), candidateCreates:1, candidatePUTs:1, otherWrites:stream.unexpected(),
      server:fixture.records, source:{sha256:sha(png),bytes:png.length}, maxPostDataSize,
      limits:'The server confirmed receipt separately. Only browser-exposed bytes can populate observedPUTBodySHA256.'};
  } finally {
    stream.close();
    await driver.call('Target.closeTarget', {targetId:tab.targetId});
  }
}

async function run(family) {
  const bundle = '/Applications/' + family.app + '.app', binary = path.join(bundle,'Contents/MacOS', family.app);
  const requirement = 'anchor apple generic and identifier "' + family.bundle + '" and certificate leaf[subject.OU] = "' + family.team + '"';
  const verification = spawnSync('/usr/bin/codesign', ['--verify','--verbose=4','-R='+requirement,bundle], {encoding:'utf8'});
  if (verification.status !== 0) {
    const prefix = 'file missing: ' + bundle + '/';
    const missing = (verification.stderr ?? '').split('\n').find(line => line.startsWith(prefix));
    return {family:family.name, vendorBundle:family.bundle, status:'NOT_RUN_INSTALLED_BUNDLE_VERIFICATION',
      verificationExit:verification.status, vendorSignatureVerified:false, browserStarted:false,
      missingSealedResource:missing ? missing.slice(prefix.length) : null};
  }
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'riftlet-local-association-'));
  const png = makePNG(), name = randomUUID() + '.png', file = path.join(tmp, name);
  let fixture, child, exited, evidence, version, birth;
  try {
    fs.writeFileSync(file, png, {flag:'wx', mode:0o600});
    fixture = await startFixture(png, name);
    child = spawn(binary, ['--headless=new','--remote-debugging-pipe','--user-data-dir='+path.join(tmp,'profile'),
      '--no-first-run','--no-default-browser-check','--disable-extensions','--disable-sync','--disable-background-networking',
      '--disable-component-update','--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','about:blank'],
      {detached:true,stdio:['ignore','ignore','ignore','pipe','pipe']});
    exited = new Promise(resolve => { child.once('exit', resolve); child.once('error', resolve); });
    const processInfo = () => execFileSync('/bin/ps', ['-p', String(child.pid), '-o','lstart=','-o','comm='], {encoding:'utf8'}).trim();
    birth = processInfo();
    assert.ok(birth.includes(binary), 'disposable browser PID and executable must match');
    const driver = new FixtureDriver(child);
    version = await driver.call('Browser.getVersion');
    evidence = await measure(driver, child, png, file, fixture);
    assert.equal(processInfo(), birth);
  } finally {
    try { if (child) await cleanupOwnedChrome(child, exited); }
    finally {
      try { if (fixture) await fixture.close(); }
      finally { fs.rmSync(tmp,{force:true,recursive:true}); }
    }
  }
  return {family:family.name, status:'LOCAL_CORRELATION_PASS', vendorBundle:family.bundle, vendorSignatureVerified:true, version:version.product,
    revision:version.revision, processBirthFingerprint:sha(birth), ...evidence,
    cleanup:{ownedProcessGroupExited:true, listenerClosed:true, profileRemoved:!fs.existsSync(tmp)}};
}

async function main() {
  assert.equal(process.argv.length, 2, 'no target, URL, input or connection parameters accepted');
  const browsers = [];
  for (const family of families) {
    try { browsers.push(await run(family)); }
    catch (error) { browsers.push({family:family.name, status:'LOCAL_CHECK_FAILED', reason:error.message}); }
  }
  const passed = browsers.filter(browser => browser.status === 'LOCAL_CORRELATION_PASS').length;
  return {scope:'Owned synthetic PNG, disposable headless profiles, private inherited pipes, public loopback object only',
    observedAtUTC:new Date().toISOString(), resultCounts:{passed, total:browsers.length}, browsers,
    authenticatedWebsiteTests:0, signedStorageURLsRead:0, accountHeadersPersisted:0, faultInjections:0,
    sources:Object.fromEntries(['fixture.cjs','run.cjs'].map(n => [n, sha(fs.readFileSync(path.join(__dirname,n)))]))};
}

main().then(result => {
  console.log(JSON.stringify(result,null,2));
  if (result.resultCounts.passed !== result.resultCounts.total) process.exitCode = 1;
}, error => { console.error(error.message); process.exitCode=1; });
