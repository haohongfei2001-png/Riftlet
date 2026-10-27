// Offline VM tests for a lab-only read-only probe. No real ChatGPT/network evidence.
'use strict';
const vm = require('node:vm'), fs = require('node:fs'), path = require('node:path');
const assert = require('node:assert/strict'), {webcrypto} = require('node:crypto');
const {File} = require('node:buffer');
const source = fs.readFileSync(path.join(__dirname, 'network-probe.template.js'), 'utf8');
const bytes = new Uint8Array(32).fill(7);
const id = '12345678-1234-4234-8234-123456789abc';
const route = 'https://example.invalid/private-signed-upload?token=NEVER_LOG_TOKEN';
const tick = () => new Promise(resolve => setTimeout(resolve, 20));

(async () => {
  const sha256 = Buffer.from(await webcrypto.subtle.digest('SHA-256', bytes)).toString('hex');
  function setup({dynamic = false, wrongInput = false, fetchFactory = null, activeFault = false} = {}) {
    let timer, sink, calls = 0, aborts = 0, lastFetchArgs, lastNativePromise, fetchOverride = fetchFactory;
    const listeners = new Map(), windowListeners = new Map();
    const cfg = {sessionId: 'readonly-probe-test', operationID: id, name: `riftlet-${id}.png`, bytes: bytes.length, sha256};
    if (dynamic) { delete cfg.operationID; delete cfg.name; cfg.bindNextGeneratedInput = true; }
    class Input {}
    class XHR {
      constructor() { this.handlers = new Map(); this.status = 0; this.readyState = 1; }
      open(...args) { this.openArgs = args; return 'native-open'; }
      send(...args) { this.sendArgs = args; this.sent = (this.sent || 0) + 1; if (this.throwOnSend) throw this.throwOnSend; return 'native-send'; }
      abort() { aborts++; }
      addEventListener(name, fn) { this.handlers.set(name, fn); }
      finish(status) { this.status = status; this.readyState = 4; this.handlers.get('loadend')?.(); }
    }
    const originalOpen = XHR.prototype.open, originalSend = XHR.prototype.send;
    const form = {isConnected: true, contains: candidate => candidate === input};
    const input = new Input(); Object.assign(input, {type: 'file', isConnected: true, form,
      files: [new File([wrongInput ? new Uint8Array(32) : bytes], `riftlet-${id}.png`, {type: 'image/png'})]});
    const nativeFetch = function (...args) {
      calls++; lastFetchArgs = args;
      lastNativePromise = fetchOverride ? fetchOverride(...args) : Promise.resolve(new Response(JSON.stringify({upload_url: route, private: 'NEVER_LOG_BODY'}), {status: 200}));
      return lastNativePromise;
    };
    const ctx = {__RIFTLET_NETWORK_PROBE_CONFIG__: cfg, location: {origin: 'https://chatgpt.com', href: 'https://chatgpt.com/c/generated-test'},
      document: {createElement: () => (sink = {dataset: {}}), getElementById: () => null,
        documentElement: {appendChild() {}}, addEventListener: (name, fn) => listeners.set(name, fn),
        removeEventListener: (name, fn) => { if (listeners.get(name) === fn) listeners.delete(name); }},
      HTMLInputElement: Input, XMLHttpRequest: XHR, fetch: nativeFetch, Blob, File, FormData, Request, URL, URLSearchParams,
      ReadableStream, ArrayBuffer, Uint8Array, TextDecoder, TextEncoder, crypto: webcrypto, performance: {now: () => 1},
      setTimeout: fn => (timer = fn, 1), clearTimeout() {},
      addEventListener: (name, fn) => windowListeners.set(name, fn), removeEventListener: name => windowListeners.delete(name)};
    if (activeFault) ctx.__riftletRound2Network = {query: () => ({state: 'OBSERVING_INPUT'})};
    vm.createContext(ctx); vm.runInContext(source, ctx);
    const query = () => ctx.__riftletRound3NetworkProbe.query();
    return {ctx, cfg, input, XHR, nativeFetch, originalOpen, originalSend, query,
      change: () => listeners.get('change')?.({target: input}), deadline: () => timer(),
      stop: () => ctx.__riftletRound3NetworkProbe.stop(), sink: () => JSON.parse(sink.textContent),
      calls: () => calls, aborts: () => aborts, nativePromise: () => lastNativePromise, args: () => lastFetchArgs,
      setFetch: fn => { fetchOverride = fn; }, pagehide: () => windowListeners.get('pagehide')?.()};
  }
  function byEvent(e, name) { return e.query().events.filter(event => event.event === name); }
  async function bind(e) { e.change(); await tick(); assert.equal(e.query().changeHashOK, true); }
  async function ownRequest(e) { await e.ctx.fetch('/create', {body: JSON.stringify({file_name: `riftlet-${id}.png`})}); await tick(); }
  function noPrivateData(e) {
    const receipt = JSON.stringify(e.query());
    for (const forbidden of ['NEVER_LOG_TOKEN', 'NEVER_LOG_BODY', 'upload_url', 'https://', 'headers', 'Authorization', 'responseText']) {
      assert.equal(receipt.includes(forbidden), false, `Leaked ${forbidden}`);
    }
    assert.equal(e.query().requestsInitiatedByProbe, 0); assert.equal(e.query().abortsInitiatedByProbe, 0);
    assert.equal(e.aborts(), 0); assert.equal(e.query().retryConclusion, 'NOT_ESTABLISHED');
  }

  let e = setup();
  const init = {body: 'unrelated', headers: {Authorization: 'NEVER_LOG_TOKEN'}};
  const promise = e.ctx.fetch('https://example.invalid/unrelated', init);
  assert.equal(promise, e.nativePromise()); assert.equal(e.args()[1], init); await promise;
  assert.equal(e.query().requestsObserved, 0); e.stop();
  console.log('PASS no inspection before own input; original fetch Promise and arguments preserved');

  e = setup(); await bind(e); await ownRequest(e);
  const body = new Blob([bytes], {type: 'image/png'}), signal = new AbortController().signal;
  const uploadInit = {method: 'PUT', body, signal};
  const upload = e.ctx.fetch(route, uploadInit);
  assert.equal(upload, e.nativePromise()); assert.equal(e.args()[1], uploadInit); await upload; await tick();
  const linked = byEvent(e, 'response_route_candidate'); assert.equal(linked.length, 1);
  assert.equal(linked[0].transport, 'fetch'); assert.equal(linked[0].bodyKind, 'blob'); assert.equal(linked[0].bodyByteCount, 32);
  assert.equal(byEvent(e, 'associated_body_hash')[0].sha256EqualsGenerated, true);
  noPrivateData(e); e.deadline(); assert.equal(e.ctx.fetch, e.nativeFetch); assert.equal(e.XHR.prototype.send, e.originalSend);
  console.log('PASS exact-name response association, immutable Blob hash, no request/signal replacement or abort');

  e = setup(); await bind(e);
  let controller, cancelled = 0;
  const original = new Response(new ReadableStream({start(c) { controller = c; }, cancel() { cancelled++; }}), {status: 200});
  e.setFetch(() => Promise.resolve(original));
  const waiting = e.ctx.fetch('/create', {body: JSON.stringify({name: `riftlet-${id}.png`})});
  assert.equal(waiting, e.nativePromise());
  const returned = await Promise.race([waiting, new Promise((_, reject) => setTimeout(() => reject(Error('response delivery delayed by clone')), 100))]);
  assert.equal(returned, original); assert.equal(original.bodyUsed, false); await tick();
  assert.equal(e.query().cloneReaders, 1); e.deadline();
  assert.equal(e.query().state, 'STOPPED'); assert.equal(e.query().cloneReaders, 0); assert.equal(e.query().originalsRestored, true);
  controller.enqueue(new TextEncoder().encode('{"untouched":"original"}')); controller.close();
  assert.equal(await original.text(), '{"untouched":"original"}'); assert.equal(cancelled, 0); await tick();
  assert.equal(e.sink().state, 'STOPPED'); assert.equal(byEvent(e, 'own_name_response_shape').length, 0);
  console.log('PASS slow clone never delays original response; deadline cancels clone only; no post-stop receipt mutation');

  e = setup(); await bind(e); await ownRequest(e); await ownRequest(e);
  const xhr = new e.XHR(); assert.equal(xhr.open('PUT', route, true), 'native-open');
  const sent = xhr.send(body); assert.equal(sent, 'native-send'); assert.equal(xhr.sent, 1); assert.equal(xhr.sendArgs[0], body);
  xhr.finish(201); await tick();
  assert.equal(e.query().exactNameRequestCandidates, 2); assert.equal(byEvent(e, 'response_route_candidate').length, 2);
  assert.equal(JSON.stringify(byEvent(e, 'response_route_candidate').map(x => x.ownNameRequestLocalId)), '[1,2]');
  assert.equal(byEvent(e, 'associated_body_hash').length, 1); noPrivateData(e); e.stop();
  console.log('PASS two own-name JSON requests remain separate route candidates; never labelled retry');

  e = setup(); await bind(e);
  let slow;
  const creation = new Response(new ReadableStream({start(c) { slow = c; }}), {status: 200});
  e.setFetch(() => Promise.resolve(creation));
  await e.ctx.fetch('/create', {body: JSON.stringify({name: `riftlet-${id}.png`})});
  const early = new e.XHR(); early.open('PUT', route); early.send(body); early.finish(200);
  assert.equal(early.sent, 1); assert.equal(byEvent(e, 'response_route_candidate').length, 0);
  slow.enqueue(new TextEncoder().encode(JSON.stringify({upload_url: route}))); slow.close(); await tick();
  assert.equal(byEvent(e, 'response_route_candidate').length, 1);
  assert.equal(byEvent(e, 'response_route_candidate')[0].nativeRequestAlreadyFinished, true);
  assert.equal(byEvent(e, 'associated_body_hash')[0].sha256EqualsGenerated, true); e.stop();
  console.log('PASS request preceding clone parse is associated later without delaying native send');

  e = setup(); await bind(e); await ownRequest(e);
  const altered = new e.XHR(); altered.open('PUT', route); altered.send(new Blob([new Uint8Array(17)])); await tick();
  const candidate = byEvent(e, 'associated_body_hash')[0];
  assert.equal(candidate.hashByteCount, 17); assert.equal(candidate.sha256EqualsGenerated, false);
  assert.equal(candidate.sizeEqualsGenerated, false); assert.equal(altered.sent, 1); noPrivateData(e); e.stop();
  console.log('PASS different-size body records hash mismatch only, without inferring compression/retry');

  e = setup(); await bind(e); await ownRequest(e);
  const nativeRequest = new Request(route, {method: 'POST', body: new Blob([bytes])});
  await e.ctx.fetch(nativeRequest); await tick();
  assert.equal(nativeRequest.bodyUsed, false); assert.equal(byEvent(e, 'response_route_candidate')[0].bodyKind, 'request-body-unread');
  assert.equal(byEvent(e, 'associated_body_hash').length, 0);
  const typed = new e.XHR(); typed.open('POST', route); typed.send(new Uint8Array(32)); await tick();
  assert.equal(byEvent(e, 'response_route_candidate')[1].bodyKind, 'mutable-buffer-unread');
  assert.equal(byEvent(e, 'associated_body_hash').length, 0); e.stop();
  console.log('PASS Request streams and mutable buffers remain unread; shape evidence does not invent hashes');

  e = setup(); await bind(e);
  const form = new FormData(); form.append('private-field', new File([bytes], `riftlet-${id}.png`, {type: 'image/png'}));
  const multipart = new e.XHR(); multipart.open('POST', '/multipart'); multipart.send(form); await tick();
  assert.equal(byEvent(e, 'exact_name_request_candidate')[0].bodyKind, 'form-data');
  assert.equal(byEvent(e, 'associated_body_hash')[0].hashScope, 'own_named_file_part');
  assert.equal(JSON.stringify(e.query()).includes('private-field'), false); noPrivateData(e); e.stop();
  console.log('PASS exact named multipart file-part hash; no field names or values logged');

  e = setup({dynamic: true}); assert.equal(e.query().operationID, null); await bind(e);
  assert.equal(e.query().operationID, id); e.change(); assert.equal(e.query().state, 'STOPPED'); assert.equal(e.query().originalsRestored, true);
  e = setup({wrongInput: true}); e.change(); await tick(); assert.equal(e.query().state, 'STOPPED'); assert.equal(e.query().changeHashOK, false);
  e = setup({dynamic: true}); e.input.files = [new File([bytes], 'unrelated.png', {type: 'image/png'})]; e.change();
  assert.equal(e.query().state, 'STOPPED'); assert.equal(e.query().operationID, null);
  console.log('PASS dynamic generated-input binding; duplicate/wrong-name/wrong-hash closes and restores');

  e = setup(); await bind(e);
  const exception = Error('native send failed'); const broken = new e.XHR(); broken.open('POST', '/other'); broken.throwOnSend = exception;
  assert.throws(() => broken.send(body), err => err === exception); assert.equal(broken.sent, 1);
  const rejected = Error('native fetch rejection'); e.setFetch(() => Promise.reject(rejected));
  await assert.rejects(e.ctx.fetch('/create', {body: JSON.stringify({name: `riftlet-${id}.png`})}), err => err === rejected);
  await tick(); e.setFetch(() => { throw exception; });
  assert.throws(() => e.ctx.fetch('/native-throw'), err => err === exception); e.stop();
  console.log('PASS native XHR exceptions and fetch rejections pass through unchanged');

  e = setup(); await bind(e);
  for (let i = 0; i < 65; i++) { const request = new e.XHR(); request.open('POST', '/unrelated-' + i); request.send(body); assert.equal(request.sent, 1); }
  assert.equal(e.query().state, 'STOPPED'); assert.equal(e.query().originalsRestored, true); assert.equal(e.query().retainedRequestCandidates, 0);
  e = setup(); await bind(e); await ownRequest(e); const replacement = function () {}; e.ctx.fetch = replacement; e.pagehide();
  assert.equal(e.ctx.fetch, replacement); assert.equal(e.query().originalsRestored, false); assert.equal(e.query().state, 'STOPPED');
  assert.throws(() => setup({activeFault: true}), /INSTALL_REFUSED/);
  e = setup(); await bind(e); for (let i = 0; i < 12; i++) await ownRequest(e);
  for (let i = 0; i < 30; i++) { const item = new e.XHR(); item.open('PUT', route); item.send(body); }
  await tick(); assert.equal(e.query().state, 'STOPPED'); assert.equal(e.query().events.length, 240);
  assert.equal(e.query().originalsRestored, true); assert.equal(e.sink().state, 'STOPPED');
  e = setup(); e.ctx.__riftletRound3NetworkProbe.stop('https://example.invalid/NEVER_LOG_TOKEN'); noPrivateData(e);
  console.log('PASS bounded temporary metadata, third-party hook preservation and active fault-hook refusal');

  e = setup(); await bind(e);
  e.setFetch(() => Promise.resolve(new Response('x'.repeat(70000), {status: 200})));
  const oversized = await e.ctx.fetch('/create', {body: JSON.stringify({name: `riftlet-${id}.png`})});
  assert.equal((await oversized.text()).length, 70000); await tick();
  assert.equal(byEvent(e, 'response_clone_bounded_out').length, 1); noPrivateData(e); e.stop();
  console.log('PASS bounded response clone reading does not truncate application response');
  console.log('12 read-only network-probe VM groups PASS; real MID interception/abort NOT_RUN');
})().catch(error => { console.error(error); process.exitCode = 1; });
