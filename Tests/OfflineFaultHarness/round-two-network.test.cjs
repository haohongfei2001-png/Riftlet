'use strict';

// Offline fixture for the archived laboratory template. No live network requests.
const assert = require('node:assert/strict');
const { webcrypto } = require('node:crypto');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const { setTimeout: delay } = require('node:timers/promises');

const source = readFileSync(path.join(__dirname,
  '../../engineering/evidence/2026-10-27-real-mac-round2/network-fault.template.js'), 'utf8');
const bytes = new Uint8Array(32).fill(7);
const digest = webcrypto.subtle.digest('SHA-256', bytes).then(value => Buffer.from(value).toString('hex'));
const uniqueURL = 'https://example.invalid/unique';
const generatedID = '12345678-1234-1234-1234-123456789ABC';
const png = (contents = bytes) => new Blob([contents], { type: 'image/png' });

// The host timer only bounds a missing edge. Its expiration never constitutes success.
async function until(observed, edge) {
  const deadline = performance.now() + 5000;
  while (!observed()) {
    if (performance.now() >= deadline) assert.fail('Timed out waiting for ' + edge);
    await delay(5);
  }
}

async function setup({ mode = 'POST100', wrong = false, dynamic = false } = {}) {
  const cfg = {
    sessionId: 'lab-test-1234', operationID: 'operation-1234', name: 'riftlet-operation-1234.png',
    bytes: bytes.length, sha256: await digest, mode
  };
  const selectedName = dynamic ? 'riftlet-' + generatedID + '.png' : cfg.name;
  if (dynamic) {
    delete cfg.name;
    delete cfg.operationID;
    cfg.bindNextGeneratedInput = true;
  }

  class Input {}
  class XHR {
    constructor() {
      this.readyState = 1;
      this.status = 0;
      this.handlers = new Map();
      this.upload = { addEventListener: (_, callback) => { this.progress = callback; } };
    }
    open() { this.readyState = 1; }
    send() { this.sent = (this.sent || 0) + 1; }
    addEventListener(name, callback) { this.handlers.set(name, callback); }
    abort() {
      this.readyState = 0;
      this.handlers.get('abort')?.();
      this.handlers.get('loadend')?.();
    }
  }
  const originalSend = XHR.prototype.send;
  const originalOpen = XHR.prototype.open;
  const progress = {
    hasAttribute: () => true,
    getAttribute: name => name === 'aria-label' ? '正在上传 ' + selectedName : '100'
  };
  const card = { getAttribute: () => selectedName, querySelectorAll: () => [progress] };
  const form = { isConnected: true, contains: () => true, querySelectorAll: () => [card] };
  const input = Object.assign(new Input(), {
    type: 'file', isConnected: true, form,
    files: [Object.assign(png(wrong ? new Uint8Array(bytes.length) : bytes), { name: selectedName })]
  });
  const listeners = new Map();
  const wins = new Map();
  let response, sink, observe, deadline;
  let fetchCount = 0;
  function nativeFetch() {
    fetchCount++;
    return Promise.resolve(response || new Response(JSON.stringify({ upload_url: uniqueURL })));
  }
  const ctx = {
    __RIFTLET_NETWORK_CONFIG__: cfg, location: { origin: 'https://chatgpt.com' },
    document: {
      createElement: () => (sink = { dataset: {} }),
      getElementById: () => null,
      documentElement: { appendChild() {} },
      addEventListener: (name, callback) => listeners.set(name, callback),
      removeEventListener: (name, callback) => {
        if (listeners.get(name) === callback) listeners.delete(name);
      }
    },
    HTMLInputElement: Input, XMLHttpRequest: XHR, fetch: nativeFetch, crypto: webcrypto,
    performance: { now: () => 1 }, Blob, URL, Request, AbortController, AbortSignal,
    TextDecoder, Uint8Array, Set, WeakMap, console, queueMicrotask,
    setTimeout: callback => { deadline = callback; return 1; }, clearTimeout() {},
    addEventListener: (name, callback) => wins.set(name, callback),
    removeEventListener: name => wins.delete(name),
    MutationObserver: class {
      constructor(callback) { observe = callback; }
      observe() {}
      disconnect() {}
    }
  };
  vm.runInNewContext(source, ctx);
  return {
    ctx, input, selectedName, originalOpen, originalSend, nativeFetch,
    query: () => ctx.__riftletRound2Network.query(),
    sink: () => JSON.parse(sink.textContent),
    change: () => listeners.get('change')({ target: input }),
    create: () => ctx.fetch('/create', { body: JSON.stringify({ name: selectedName }) }),
    send: (url = uniqueURL) => {
      const xhr = new XHR();
      xhr.open('PUT', url, true);
      xhr.send(png());
      return xhr;
    },
    XHR, progress: () => observe(), deadline: () => deadline(), fetchCount: () => fetchCount,
    setResponse: value => { response = value; }
  };
}

test('exact POST100 one-abort, app retry passthrough, deadline restoration', { timeout: 15000 }, async () => {
  const e = await setup();
  await e.ctx.fetch('https://example.invalid/other');
  assert.equal(e.fetchCount(), 1);
  assert.equal(e.query().createCount, 0);
  e.change();
  await e.ctx.fetch('/create', { body: JSON.stringify({ file_name: e.selectedName }) });
  assert.equal(e.query().uniqueCreationURL, true);
  const first = e.send();
  await until(() => first.sent !== undefined, 'first native XHR send');
  assert.equal(first.sent, 1);
  e.progress();
  assert.equal(e.query().faultInjected, true);
  assert.equal(e.query().events.filter(event => event.event === 'native_abort_event').length, 1);
  const retry = e.send();
  await until(() => retry.sent !== undefined, 'retry native XHR send');
  e.progress();
  assert.equal(retry.sent, 1);
  assert.equal(retry.readyState, 1);
  assert.equal(e.query().events.filter(event => event.event === 'native_abort_requested').length, 1);
  e.deadline();
  assert.equal(e.ctx.fetch, e.nativeFetch);
  assert.equal(e.XHR.prototype.send, e.originalSend);
  assert.equal(e.XHR.prototype.open, e.originalOpen);
  assert.equal(e.query().state, 'STOPPED');
});

test('MID native progress bound', { timeout: 15000 }, async () => {
  const e = await setup({ mode: 'MID' });
  e.change();
  await e.create();
  const xhr = e.send();
  await until(() => xhr.sent !== undefined, 'MID native XHR send');
  assert.equal(xhr.sent, 1);
  xhr.progress({ loaded: 8, total: 32, lengthComputable: true });
  assert.equal(e.query().faultInjected, true);
});

test('wrong File hash closes without fault', { timeout: 15000 }, async () => {
  const e = await setup({ wrong: true });
  e.change();
  await until(() => e.query().state === 'STOPPED', 'wrong-hash stop');
  assert.equal(e.query().state, 'STOPPED');
  assert.equal(e.query().faultInjected, false);
  assert.equal(e.query().events.some(event => event.event === 'own_input_hash' && !event.matched), true);
});

test('unrelated URL immediate pass, duplicate input closes', { timeout: 15000 }, async () => {
  const e = await setup();
  e.change();
  await e.create();
  const xhr = e.send('https://example.invalid/unrelated');
  e.progress();
  assert.equal(xhr.sent, 1);
  assert.equal(e.query().faultInjected, false);
  e.change();
  assert.equal(e.query().state, 'STOPPED');
});

test('next generated input freezes UUID/name, exact bytes abort, duplicate closes', { timeout: 15000 }, async () => {
  const e = await setup({ dynamic: true });
  assert.equal(e.query().operationID, null);
  e.change();
  await e.create();
  assert.equal(e.query().operationID, generatedID);
  const xhr = e.send();
  await until(() => xhr.sent !== undefined, 'generated input native XHR send');
  assert.equal(xhr.sent, 1);
  e.progress();
  assert.equal(e.query().faultInjected, true);
  e.change();
  assert.equal(e.query().state, 'STOPPED');
});

test('next-input unexpected name closes without adopting identity', { timeout: 15000 }, async () => {
  const e = await setup({ dynamic: true });
  e.input.files = [Object.assign(png(), { name: 'other.png' })];
  e.change();
  assert.equal(e.query().state, 'STOPPED');
  assert.equal(e.query().operationID, null);
  assert.equal(e.query().faultInjected, false);
});

test('event-bound stop publishes STOPPED receipt and restores hooks', { timeout: 15000 }, async () => {
  const e = await setup();
  e.change();
  await until(() => e.query().changeHashOK, 'input digest receipt');
  for (let i = 0; i < 125; i++) await e.create();
  assert.equal(e.query().state, 'STOPPED');
  assert.equal(e.sink().state, 'STOPPED');
  assert.equal(e.sink().events.length, 240);
  assert.equal(e.ctx.fetch, e.nativeFetch);
});

test('deadline releases pending clone reader without cancelling or consuming original', { timeout: 15000 }, async () => {
  const e = await setup();
  e.change();
  await until(() => e.query().changeHashOK, 'input digest receipt');
  let controller, cancelled = 0, cloneReadStarted = false;
  const original = new Response(new ReadableStream({
    start(value) { controller = value; },
    cancel() { cancelled++; }
  }));
  // Observe read() on the actual cloned branch. Do not resolve, drain or replace it.
  const clone = original.clone.bind(original);
  original.clone = () => {
    const copy = clone();
    const getReader = copy.body.getReader.bind(copy.body);
    copy.body.getReader = (...args) => {
      const reader = getReader(...args);
      const read = reader.read.bind(reader);
      reader.read = (...args) => {
        const pending = read(...args);
        cloneReadStarted = true;
        return pending;
      };
      return reader;
    };
    return copy;
  };
  e.setResponse(original);
  let returned = false;
  const waiting = e.create().then(value => { returned = true; return value; });
  await until(() => cloneReadStarted, 'pending read on the real cloned response');
  assert.equal(returned, false);
  e.deadline();
  // Preserve the original 200 ms release bound, starting from a proven pending read.
  let releaseTimer;
  const delivered = await Promise.race([waiting, new Promise((_, reject) => {
    releaseTimer = setTimeout(() => reject(new Error('Timed out waiting for deadline releasing clone reader')), 200);
  })]).finally(() => clearTimeout(releaseTimer));
  assert.equal(delivered, original);
  assert.equal(original.bodyUsed, false);
  assert.equal(cancelled, 0);
  controller.enqueue(new TextEncoder().encode('{"still":"original"}'));
  controller.close();
  assert.equal(await delivered.text(), '{"still":"original"}');
  assert.equal(cancelled, 0);
  assert.equal(e.sink().state, 'STOPPED');
});
