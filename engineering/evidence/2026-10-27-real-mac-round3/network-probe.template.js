/* LAB ONLY, DIAGNOSTIC_ONLY; never bundled into Riftlet.
 * Increment of round2/network-fault.template.js for the unbound MID request.
 * Replace __RIFTLET_NETWORK_PROBE_CONFIG__ with {sessionId, bytes, sha256,
 * operationID, name}; or omit operationID/name and set bindNextGeneratedInput:true.
 * Only an authorized generated PNG input is eligible. No input/send/request/abort
 * is initiated here. Native fetch Promise, response and XHR arguments pass through.
 * URLs are temporary, private equality keys, never receipt fields. No headers or
 * response/request text is logged. Two exact-name requests are two candidates,
 * never proof of retry. Unmatched/cached-fetch/Request-stream paths remain unknown.
 */
(() => {
  'use strict';
  const supplied = __RIFTLET_NETWORK_PROBE_CONFIG__, cfg = supplied && {...supplied};
  const bindNext = cfg?.bindNextGeneratedInput === true;
  const operationPattern = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
  if (!cfg || !/^[A-Za-z0-9_-]{8,100}$/.test(cfg.sessionId)
      || (bindNext ? cfg.operationID !== undefined || cfg.name !== undefined
        : !operationPattern.test(cfg.operationID || '') || cfg.name !== 'riftlet-' + cfg.operationID + '.png')
      || !Number.isSafeInteger(cfg.bytes) || cfg.bytes < 8 || cfg.bytes > 8 * 1024 * 1024
      || !/^[a-f0-9]{64}$/.test(cfg.sha256)) throw Error('INVALID_SYNTHETIC_CONFIG');
  if (location.origin !== 'https://chatgpt.com' || globalThis.__riftletRound3NetworkProbe
      || (globalThis.__riftletRound2Network && globalThis.__riftletRound2Network.query().state !== 'STOPPED')) throw Error('INSTALL_REFUSED');
  const nativeFetch = globalThis.fetch, proto = XMLHttpRequest.prototype;
  const nativeOpen = proto.open, nativeSend = proto.send;
  const events = [], records = new Map(), urls = new Map(), readers = new Set();
  let xhrMeta = new WeakMap();
  const MAX_EVENTS = 240, MAX_RECORDS = 64, MAX_JSON = 65536, MAX_HASH = 8 * 1024 * 1024;
  let closed = false, timer = null, nextRequest = 0, sequence = 0, inputCount = 0, changeHashOK = false;
  let inputHash = Promise.resolve(false), boundInput = null, boundForm = null, namedRequests = 0;
  let sink = document.createElement('script');
  sink.type = 'application/json'; sink.id = 'riftlet-round3-network-probe-receipt'; sink.dataset.session = cfg.sessionId;
  if (document.getElementById(sink.id)) throw Error('SINK_EXISTS');
  document.documentElement.appendChild(sink);
  function validOwner() { return !closed && inputCount === 1 && boundInput?.isConnected && boundForm?.isConnected && boundForm.contains(boundInput); }
  function snapshot() {
    return {schemaVersion: 1, sessionId: cfg.sessionId, operationID: cfg.operationID ?? null,
      uploadName: cfg.name ?? null, mode: 'DIAGNOSTIC_ONLY', state: closed ? 'STOPPED' : inputCount ? 'OBSERVING_INPUT' : 'ARMED',
      inputCount, changeHashOK, exactNameRequestCandidates: namedRequests, requestsObserved: nextRequest,
      retainedRequestCandidates: records.size, cloneReaders: readers.size,
      requestsInitiatedByProbe: 0, abortsInitiatedByProbe: 0, retryConclusion: 'NOT_ESTABLISHED',
      originalsRestored: globalThis.fetch === nativeFetch && proto.open === nativeOpen && proto.send === nativeSend, events: events.slice()};
  }
  function flush() { sink.textContent = JSON.stringify(snapshot()); }
  function log(event, facts = {}) {
    if (closed) return;
    if (events.length >= MAX_EVENTS) { stop('EVENT_BOUND'); return; }
    events.push({sequence: ++sequence, monotonicMs: performance.now(), event, ...facts}); flush();
  }
  const digest = async blob => [...new Uint8Array(await crypto.subtle.digest('SHA-256', await blob.arrayBuffer()))]
    .map(x => x.toString(16).padStart(2, '0')).join('');
  function inputChanged(event) {
    const input = event.target;
    if (closed || !(input instanceof HTMLInputElement) || input.type !== 'file') return;
    const files = Array.from(input.files || []);
    if (!bindNext && !files.some(file => file.name === cfg.name)) return;
    inputCount++;
    const match = files.length === 1 ? /^riftlet-([0-9a-fA-F-]{36})\.png$/.exec(files[0].name) : null;
    if (inputCount !== 1 || files.length !== 1 || files[0].size !== cfg.bytes || files[0].type !== 'image/png'
        || !input.form || (bindNext && (!match || !operationPattern.test(match[1])))) {
      log('input_binding_refused'); stop('INPUT_IDENTITY'); return;
    }
    if (bindNext) { cfg.operationID = match[1]; cfg.name = files[0].name; }
    boundInput = input; boundForm = input.form;
    log('own_input_observed', {byteCount: files[0].size});
    inputHash = digest(files[0]).then(hash => {
      if (closed) return false;
      changeHashOK = hash === cfg.sha256;
      log('own_input_hash', {matched: changeHashOK});
      if (!changeHashOK) stop('INPUT_HASH');
      return changeHashOK;
    }, () => { if (!closed) { log('input_hash_unavailable'); stop('INPUT_HASH'); } return false; });
  }
  function exactNameJSON(body) {
    if (typeof body !== 'string' || body.length > MAX_JSON || !cfg.name) return false;
    let parsed; try { parsed = JSON.parse(body); } catch { return false; }
    let visited = 0;
    const scan = (value, depth) => {
      if (++visited > 1024 || depth > 5) return false;
      if (value === cfg.name) return true;
      if (Array.isArray(value)) return value.some(item => scan(item, depth + 1));
      if (value && typeof value === 'object') return Object.values(value).some(item => scan(item, depth + 1));
      return false;
    };
    return scan(parsed, 0);
  }
  function requestURL(input) {
    try {
      const raw = typeof input === 'string' || input instanceof URL ? String(input) : input instanceof Request ? input.url : null;
      return raw ? new URL(raw, location.href).href : null;
    } catch { return null; }
  }
  function shape(body, requestStream = false) {
    if (requestStream) return {kind: 'request-body-unread', size: null, blob: null, named: false};
    if (body == null) return {kind: 'none', size: 0, blob: null, named: false};
    if (typeof body === 'string' && body.length > MAX_JSON) return {kind: 'string-bounded-out', size: null, blob: null, named: false};
    if (typeof body === 'string') return {kind: 'string', size: new TextEncoder().encode(body).byteLength, blob: null, named: exactNameJSON(body)};
    if (body instanceof Blob) return {kind: typeof File !== 'undefined' && body instanceof File ? 'file' : 'blob',
      size: body.size, blob: body.size <= MAX_HASH ? body : null, named: body.name === cfg.name};
    if (typeof FormData !== 'undefined' && body instanceof FormData) {
      let count = 0, total = 0, named = false, ownBlob = null;
      for (const [, value] of body.entries()) {
        if (++count > 128) return {kind: 'form-data-bounded-out', size: null, blob: null, named: false};
        if (value instanceof Blob) {
          total += value.size;
          if (value.name === cfg.name) { named = true; ownBlob = ownBlob === null ? value : false; }
        } else { total += new TextEncoder().encode(value).byteLength; if (value === cfg.name) named = true; }
      }
      return {kind: 'form-data', size: total, blob: ownBlob && ownBlob.size <= MAX_HASH ? ownBlob : null, named};
    }
    if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) return {kind: 'mutable-buffer-unread', size: body.byteLength, blob: null, named: false};
    if (typeof URLSearchParams !== 'undefined' && body instanceof URLSearchParams) return {kind: 'url-search-params-unread', size: null, blob: null, named: false};
    if (typeof ReadableStream !== 'undefined' && body instanceof ReadableStream) return {kind: 'stream-unread', size: null, blob: null, named: false};
    return {kind: 'unsupported-unread', size: null, blob: null, named: false};
  }
  function facts(record) { return {requestLocalId: record.id, transport: record.transport, bodyKind: record.kind,
    bodyByteCount: record.size, sizeEqualsGenerated: record.size === cfg.bytes}; }
  function reportHash(record) {
    if (record.hashStarted || !record.blob) return;
    record.hashStarted = true;
    const blob = record.blob;
    void inputHash.then(ok => ok && validOwner() ? digest(blob) : null).then(hash => {
      if (!hash || !validOwner() || !records.has(record.id)) return;
      log('associated_body_hash', {...facts(record), hashByteCount: blob.size,
        hashScope: record.kind === 'form-data' ? 'own_named_file_part' : 'whole_body',
        sha256EqualsGenerated: hash === cfg.sha256});
    }, () => { if (validOwner() && records.has(record.id)) log('associated_body_hash_unavailable', facts(record)); });
  }
  function associate(record) {
    if (!validOwner() || !record.url) return;
    const origins = urls.get(record.url);
    if (!origins) return;
    for (const id of origins) {
      if (!validOwner()) return;
      if (record.linked.has(id) || record.id === id) continue;
      record.linked.add(id);
      log('response_route_candidate', {...facts(record), ownNameRequestLocalId: id,
        association: 'exact_own_name_response_route', concludedRetry: false,
        nativeRequestAlreadyFinished: record.finished});
      reportHash(record);
    }
  }
  function observeRequest(transport, input, body, requestStream = false) {
    if (!validOwner()) return null;
    const info = shape(body, requestStream);
    const record = {id: ++nextRequest, transport, ...info, url: requestURL(input), linked: new Set(),
      hashStarted: false, finished: false, response: null};
    if (records.size >= MAX_RECORDS) { stop('REQUEST_BOUND'); return null; }
    records.set(record.id, record);
    if (info.named) {
      namedRequests++;
      log('exact_name_request_candidate', {...facts(record), ordinal: namedRequests, concludedRetry: false});
      reportHash(record);
    }
    associate(record);
    return record;
  }
  async function learnRoutes(response, record) {
    if (!validOwner() || !record.named || !response.ok) return;
    let reader;
    try {
      // Clone immediately, before the application consumes its original response.
      reader = response.clone().body?.getReader(); if (!reader) return;
      readers.add(reader);
      const parts = []; let count = 0;
      while (true) {
        const item = await reader.read(); if (item.done) break;
        count += item.value.byteLength;
        if (count > MAX_JSON || !validOwner()) {
          void reader.cancel().catch(() => {});
          if (!closed) log('response_clone_bounded_out', {requestLocalId: record.id});
          return;
        }
        parts.push(item.value);
      }
      if (!(await inputHash) || !validOwner()) return;
      const bytes = new Uint8Array(count); let offset = 0;
      for (const part of parts) { bytes.set(part, offset); offset += part.byteLength; }
      const value = JSON.parse(new TextDecoder().decode(bytes)), found = new Set();
      let visited = 0;
      const scan = (item, depth = 0) => {
        if (++visited > 1024 || depth > 5 || !item || typeof item !== 'object') return;
        for (const [key, entry] of Object.entries(item)) {
          if (typeof entry === 'string' && /url/i.test(key) && /^https:\/\//.test(entry)) {
            try { const url = new URL(entry); if (url.protocol === 'https:' && found.size < 16) found.add(url.href); } catch {}
          } else if (entry && typeof entry === 'object') scan(entry, depth + 1);
        }
      };
      scan(value);
      if (!validOwner()) return;
      log('own_name_response_shape', {requestLocalId: record.id, status: response.status,
        responseByteCount: count, candidateRouteCount: found.size, concludedRetry: false});
      if (!validOwner()) return;
      for (const url of found) {
        if (!urls.has(url)) urls.set(url, new Set());
        urls.get(url).add(record.id);
      }
      for (const candidate of records.values()) associate(candidate);
    } catch { if (validOwner()) log('response_clone_unavailable', {requestLocalId: record.id}); }
    finally { readers.delete(reader); try { reader?.releaseLock(); } catch {} }
  }
  function wrappedFetch(input, init) {
    // No diagnostic await precedes native fetch; preserve its exact Promise.
    const result = nativeFetch.apply(this, arguments);
    let record;
    try { record = observeRequest('fetch', input, init?.body, init?.body === undefined && input instanceof Request && input.body !== null); }
    catch { return result; }
    if (record) void result.then(response => {
      if (!validOwner()) return;
      record.finished = true;
      if (record.named || record.linked.size) log('associated_fetch_response', {...facts(record), status: response.status});
      if (record.named) void learnRoutes(response, record);
    }, () => {
      if (!validOwner()) return;
      record.finished = true;
      if (record.named || record.linked.size) log('associated_fetch_rejected', facts(record));
    }).catch(() => {});
    return result;
  }
  function wrappedOpen(method, url, async = true) {
    const result = nativeOpen.apply(this, arguments);
    try { xhrMeta.set(this, {url: requestURL(url), async: async !== false}); } catch {}
    return result;
  }
  function wrappedSend(body) {
    let record = null;
    try {
      const info = xhrMeta.get(this);
      if (info) record = observeRequest('xhr', info.url, body);
      if (record) {
        this.addEventListener('loadend', () => {
          if (!validOwner()) return;
          record.finished = true;
          if (record.named || record.linked.size) log('associated_xhr_loadend', {...facts(record), status: this.status});
        }, {once: true});
      }
    } catch {}
    // No hash wait, no replacement body/signal, no native error suppression.
    return nativeSend.apply(this, arguments);
  }
  function stop(reason = 'EXPLICIT_STOP') {
    if (closed) return snapshot();
    closed = true; clearTimeout(timer);
    if (!['EXPLICIT_STOP', 'EVENT_BOUND', 'INPUT_IDENTITY', 'INPUT_HASH', 'REQUEST_BOUND', 'PAGEHIDE', 'DEADLINE_60S'].includes(reason)) reason = 'EXPLICIT_STOP';
    document.removeEventListener('change', inputChanged, true);
    globalThis.removeEventListener('pagehide', onPageHide);
    // Only our clone consumers are cancelled, never the original stream/request.
    for (const reader of readers) { try { void reader.cancel().catch(() => {}); } catch {} }
    readers.clear(); records.clear(); urls.clear(); xhrMeta = new WeakMap();
    if (globalThis.fetch === wrappedFetch) globalThis.fetch = nativeFetch;
    if (proto.open === wrappedOpen) proto.open = nativeOpen;
    if (proto.send === wrappedSend) proto.send = nativeSend;
    if (events.length < MAX_EVENTS) events.push({sequence: ++sequence, monotonicMs: performance.now(), event: 'probe_stopped', reason,
      originalsRestored: globalThis.fetch === nativeFetch && proto.open === nativeOpen && proto.send === nativeSend});
    flush(); return snapshot();
  }
  function onPageHide() { stop('PAGEHIDE'); }
  document.addEventListener('change', inputChanged, true);
  globalThis.addEventListener('pagehide', onPageHide);
  globalThis.fetch = wrappedFetch; proto.open = wrappedOpen; proto.send = wrappedSend;
  globalThis.__riftletRound3NetworkProbe = Object.freeze({sessionId: cfg.sessionId, query: snapshot, stop});
  timer = setTimeout(() => stop('DEADLINE_60S'), 60000);
  log('probe_installed', {readOnly: true, requestsInitiatedByProbe: 0, abortsInitiatedByProbe: 0});
  return {sessionId: cfg.sessionId, installed: true, mode: 'DIAGNOSTIC_ONLY'};
})();
