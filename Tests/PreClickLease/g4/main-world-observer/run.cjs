'use strict';

const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const {createHash} = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {setTimeout: delay} = require('node:timers/promises');
const {pathToFileURL} = require('node:url');
const {FixtureDriver} = require('../../../OriginalDocumentDelivery/renderer/driver.cjs');
const {cleanupOwnedChrome} = require('../../../WebPageProgram/native-chrome-cleanup.cjs');

const localPage = pathToFileURL(path.join(__dirname, 'fixture.html')).href;
const isolatedSource = fs.readFileSync(path.join(__dirname, 'isolated.js'), 'utf8');
const sha = value => createHash('sha256').update(value).digest('hex');
const browserPaths = {
  Chrome:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  Edge:'/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'
};

async function waitUntil(read, label) {
  const end = performance.now() + 4000;
  do {
    const ready = await read();
    if (ready) return ready;
    await delay(20);
  } while (performance.now() < end);
  throw Error(label);
}

// The local fixture emits only this one console marker. Count request schemes for this disposable
// renderer without retaining request URLs, headers, content or responses.
function observeFixture(child, tab) {
  let tail = '';
  const facts = {console: [], httpRequests: 0, httpUploads: 0};
  const receive = chunk => {
    const frames = (tail + chunk).split('\0');
    tail = frames.pop();
    for (const frame of frames) {
      if (!frame) continue;
      const msg = JSON.parse(frame);
      if (msg.sessionId !== tab.sessionId) continue;
      const data = msg.params;
      if (msg.method === 'Network.requestWillBeSent' && /^https?:/i.test(data.request.url)) {
        facts.httpRequests++;
        if (data.request.hasPostData || /^(POST|PUT|PATCH)$/i.test(data.request.method)) facts.httpUploads++;
      }
      if (msg.method === 'Runtime.consoleAPICalled' && data.args[0]?.value === 'owned-fixture-static-navigation') {
        facts.console.push({context: data.executionContextId, values: data.args.slice(1).map(arg => arg.value)});
      }
      if (msg.method === 'Runtime.executionContextCreated' && data.context.auxData?.isDefault) facts.mainContext = data.context.id;
    }
  };
  child.stdio[4].on('data', receive);
  return {facts, close: () => child.stdio[4].off('data', receive)};
}

async function inspect(driver, tab, listener) {
  const command = (name, args) => driver.call(name, args, tab.sessionId);
  async function evaluate(expression, contextId, returnByValue = true) {
    const result = await command('Runtime.evaluate', {expression, returnByValue, ...(contextId ? {contextId} : {})});
    assert.ok(!result.exceptionDetails, 'fixture evaluation was refused');
    return returnByValue ? result.result.value : result.result.objectId;
  }
  async function backendNode(expression, contextId) {
    const objectId = await evaluate(expression, contextId, false);
    const reply = await command('DOM.describeNode', {objectId});
    return reply.node.backendNodeId;
  }
  // Fixed read-only inventory. The harness never assigns or calls a network method.
  async function descriptors(contextId) {
    return evaluate(`(()=>{
      const result = {};
      for (const [name, receiver] of [['fetch', window], ['open', XMLHttpRequest.prototype],
                                      ['send', XMLHttpRequest.prototype], ['abort', XMLHttpRequest.prototype]]) {
        let owner = receiver;
        while (owner && !Object.hasOwn(owner, name)) owner=Object.getPrototypeOf(owner);
        const d=owner && Object.getOwnPropertyDescriptor(owner,name);
        if (!d || typeof d.value !== 'function') throw Error('Expected method data descriptor');
        result[name]={ownOnReceiver:owner===receiver,accessor:false,writable:d.writable,configurable:d.configurable,
          enumerable:d.enumerable,referenceMatchesOwnDescriptor:receiver[name]===d.value};
      }
      return result;
    })()`,contextId);
  }
  await command('Runtime.enable', {});
  await command('Network.enable', {});
  await command('Page.navigate', {url:localPage});
  await waitUntil(() => evaluate('typeof window.readOwnedMainFixture === "function"'), 'Local original document not ready');
  assert.equal(await evaluate('location.href'), localPage);
  const originalMain = listener.facts.mainContext;
  assert.ok(Number.isInteger(originalMain));
  const frame = (await command('Page.getFrameTree', {})).frameTree.frame;
  assert.equal(frame.url,localPage);
  const mainTag = await evaluate('window.ownedMainFixture.nonce', originalMain);
  const originalNode = await backendNode('window.ownedMainFixture.node', originalMain);

  const {executionContextId: isolated} = await command('Page.createIsolatedWorld', {
    frameId:frame.id, worldName:'Riftlet local QA isolated view'
  });
  assert.notEqual(isolated, originalMain);
  const originalDescriptors = {defaultMain:await descriptors(originalMain), devToolsIsolated:await descriptors(isolated)};
  await evaluate(isolatedSource, isolated);
  const isolatedTag = await evaluate('window.ownedIsolatedFixture.nonce', isolated);
  assert.notEqual(isolatedTag, mainTag);

  const main = await evaluate('window.readOwnedMainFixture()', originalMain);
  const other = await evaluate('window.readOwnedIsolatedFixture()', isolated);
  assert.equal(main.isolatedAttribute, isolatedTag);
  assert.equal(other.mainAttribute, mainTag);
  const {isolatedAttribute, ...mainProof} = main;
  const {mainAttribute, ...isolatedProof} = other;
  const common = ['originalInstance','distinctSecondInstance','ownPrototype','unopened','methodsUnchanged'];
  const expectedMain = [...common,'mainGlobal','isolatedGlobalAbsent','mainAttributeMatches','mainWrapperMatches',
    'isolatedWrapperAbsent','mainPrototype','isolatedPrototypeAbsent'];
  const expectedIsolated = [...common,'isolatedGlobal','mainGlobalAbsent','mainReaderAbsent','isolatedAttributeMatches',
    'mainWrapperAbsent','isolatedWrapperMatches','mainPrototypeAbsent','isolatedPrototype'];
  for (const [actual, expected] of [[mainProof,expectedMain],[isolatedProof,expectedIsolated]]) {
    assert.deepEqual(Object.keys(actual).sort(),expected.sort());
    assert.ok(expected.every(key=>actual[key] === true), 'Missing positive original-world proof');
  }
  const isolatedNode = await backendNode('window.ownedIsolatedFixture.node', isolated);
  assert.equal(isolatedNode, originalNode);

  // Native-style activation of the locally authored, fixed read-only link. No script or URL
  // from the caller is used as a navigation destination.
  const point = await evaluate(`(()=>{const r = document.querySelector('#observe').getBoundingClientRect();
    return {x:r.x+r.width/2,y:r.y+r.height/2}})()`, originalMain);
  for (const type of ['mousePressed','mouseReleased']) {
    await command('Input.dispatchMouseEvent', {type, ...point, button:'left', clickCount:1});
  }
  const messages = await waitUntil(() => listener.facts.console.length && listener.facts.console, 'Static navigation did not report');
  assert.equal(messages.length,1);
  assert.equal(messages[0].context,originalMain);
  assert.deepEqual(messages[0].values,[true,true,true,true,true,true,true]);
  assert.equal(await evaluate('window.ownedMainFixture.nonce', originalMain),mainTag);
  assert.equal(await evaluate('window.ownedIsolatedFixture.nonce', isolated),isolatedTag);
  assert.equal(await backendNode('window.ownedMainFixture.node', originalMain),originalNode);
  assert.deepEqual(await evaluate('window.readOwnedMainFixture()',originalMain),main);
  assert.deepEqual(await evaluate('window.readOwnedIsolatedFixture()',isolated),other);

  // Deliberately replace only the fixture's inert mark in this document. The main check must
  // reject its stale nonce while the isolated owner's original marker and all methods survive.
  const retired = await evaluate(`(()=>{XMLHttpRequest.prototype.mainPrototypeTag=crypto.randomUUID();
    return window.readOwnedMainFixture();})()`,originalMain);
  assert.equal(retired.mainPrototype,false);
  assert.equal(retired.methodsUnchanged,true);
  assert.equal(retired.originalInstance,true);
  assert.equal(retired.unopened,true);
  assert.deepEqual(await evaluate('window.readOwnedIsolatedFixture()',isolated),other);
  assert.deepEqual(await descriptors(originalMain),originalDescriptors.defaultMain);
  assert.deepEqual(await descriptors(isolated),originalDescriptors.devToolsIsolated);
  await command('Page.reload', {ignoreCache:true});
  await waitUntil(async () => {
    try {return await evaluate('typeof window.ownedMainFixture === "object" && window.ownedMainFixture.nonce !== '+JSON.stringify(mainTag));}
    catch {return false;}
  },'Reload did not yield a distinct document');
  assert.equal(await evaluate('location.href'),localPage);
  const newFrame = (await command('Page.getFrameTree',{})).frameTree.frame;
  assert.equal(frame.id,newFrame.id);
  assert.ok(frame.loaderId && newFrame.loaderId && frame.loaderId !== newFrame.loaderId);
  const newNode = await backendNode('window.ownedMainFixture.node');
  assert.notEqual(newNode,originalNode);
  assert.equal(await evaluate("document.querySelector('#shared').getAttribute('data-isolated-tag')"),null);
  const newTag = await evaluate('window.ownedMainFixture.nonce');
  assert.notEqual(newTag, mainTag);
  let staleRejected = false;
  try {await command('Runtime.evaluate',{expression:'true',contextId:isolated,returnByValue:true});}
  catch(error) {staleRejected=/cannot find context|context.*destroyed|context.*not found/i.test(error.message);}
  assert.ok(staleRejected,'Old isolated context unexpectedly remained addressable');
  return {mainProof, isolatedProof, originalMethodDescriptors:originalDescriptors,
    staleFixturePrototypeMarker:{mainOldNonceRejected:!retired.mainPrototype,isolatedMarkPreserved:true,originalMethodsPreserved:true},
    mainTagSHA256:sha(mainTag), isolatedTagSHA256:sha(isolatedTag),
    newMainTagSHA256:sha(newTag), sameOriginalBackendDOMNode:true, attributesSharedBothWays:true,
    protocolEvidence:{originalMainContext:originalMain,originalIsolatedContext:isolated,staticLinkConsoleContext:messages[0].context,
      mainBackendNode:originalNode,isolatedBackendNode:isolatedNode,reloadedBackendNode:newNode,
      originalDocumentLoaderSHA256:sha(frame.loaderId),newDocumentLoaderSHA256:sha(newFrame.loaderId)},
    distinctIsolatedContext:true, staticLink:{consoleEventCount:messages.length,executedInOriginalDefaultContext:true,
      originalNodeDocumentAndBothInstancesPreserved:true}, reload:{newNonce:true,differentBackendNode:true,oldIsolatedDOMAttributeAbsent:true,
      oldIsolatedContextRejected:staleRejected}};
}

async function run(family, binary) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-local-world-'));
  let child, exited, version, proof, facts;
  try {
    child = spawn(binary,['--headless=new','--remote-debugging-pipe','--user-data-dir='+path.join(root,'profile'),
      '--no-first-run','--no-default-browser-check','--disable-sync','--disable-extensions','--disable-background-networking',
      '--disable-component-update','--host-resolver-rules=MAP * ~NOTFOUND','about:blank'],
      {detached:true,stdio:['ignore','ignore','ignore','pipe','pipe']});
    exited = new Promise(resolve=>{child.once('exit',resolve);child.once('error',resolve);});
    const driver = new FixtureDriver(child);
    version = await driver.call('Browser.getVersion');
    const tab = await driver.open('about:blank');
    const listener = observeFixture(child,tab);
    try {
      proof = await inspect(driver,tab,listener);
      facts = listener.facts;
      assert.equal(facts.httpRequests,0);
      assert.equal(facts.httpUploads,0);
    } finally {
      listener.close();
      await driver.call('Target.closeTarget',{targetId:tab.targetId});
    }
  } finally {
    if (child) await cleanupOwnedChrome(child,exited);
    fs.rmSync(root,{recursive:true,force:true});
  }
  assert.ok(!fs.existsSync(root));
  return {family, product:version.product, revision:version.revision, userAgentHasEdgeVersion:/Edg\//.test(version.userAgent),
    httpRequestsInOriginalTab:facts.httpRequests,httpUploadsInOriginalTab:facts.httpUploads, proof,
    cleanup:{ownedChildProcessGroupExited:true,disposableProfileRemoved:true}};
}

async function main() {
  assert.equal(process.argv.length,2,'This test accepts no parameters');
  const results=[];
  for (const [family,binary] of Object.entries(browserPaths)) results.push(await run(family,binary));
  const sources={};
  for (const file of ['fixture.html','isolated.js','run.cjs']) sources[file]=sha(fs.readFileSync(path.join(__dirname,file)));
  return {scope:'Local file in two fresh ordinary vendor headless profiles using an inherited private pipe',
    status:'PASS',sources,results,
    executionContexts:{defaultMain:'Owner-authored local file',isolated:'Chromium Page.createIsolatedWorld',macOSAppleScript:'NOT_RUN'},
    methodLifetime:'Descriptor flags are direct reads. Methods were never assigned. Writable or configurable flags permit later changes; lasting ownership is unproven.',
    limits:'These observations apply to these two local documents. Website visibility, extension and Apple Event execution contexts, authenticated sessions and transport ownership were not tested.'};
}
main().then(r=>console.log(JSON.stringify(r,null,2)),e=>{console.error(e.message);process.exitCode=1;});
