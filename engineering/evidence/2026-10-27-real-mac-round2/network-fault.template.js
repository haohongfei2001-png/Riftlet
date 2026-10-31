/* LAB ONLY. Evaluate in the proven MAIN world of the exact authorized test tab.
 * Replace __RIFTLET_NETWORK_CONFIG__ with {sessionId, operationID, name, bytes,
 * sha256, mode:"MID"|"POST100"}; or omit operationID/name and set
 * bindNextGeneratedInput:true. No requests, inputs or sends initiated here.
 * Root must bind config to its actual generated pending operation before use.
 * On this Mac, an isolated-world AE v4 global was absent from an evaluated
 * MAIN javascript: URL probe while remaining present to AE execute JavaScript.
 * Install this LAB bridge in the verified MAIN world; not in AE's isolated world.
 * Installation/UI100 alone is not interception proof. Zero matched request or
 * zero actual native abort means NOT_EXERCISED, never network-fault PASS.
 * Evidence-only template: never bundled or enabled in the production adapter.
 */
(() => {
  'use strict';
  const supplied = __RIFTLET_NETWORK_CONFIG__;
  const cfg = supplied && {...supplied};
  const bindNext = cfg?.bindNextGeneratedInput === true;
  const fixedIdentity = cfg && /^[A-Za-z0-9_-]{8,100}$/.test(cfg.operationID) && cfg.name === 'riftlet-' + cfg.operationID + '.png';
  if (!cfg || !/^[A-Za-z0-9_-]{8,100}$/.test(cfg.sessionId) ||
      (bindNext ? cfg.operationID !== undefined || cfg.name !== undefined : !fixedIdentity) ||
      !Number.isSafeInteger(cfg.bytes) || cfg.bytes < 8 || cfg.bytes > 8 * 1024 * 1024 ||
      !/^[a-f0-9]{64}$/.test(cfg.sha256) || !['MID', 'POST100'].includes(cfg.mode)) throw Error('INVALID_SYNTHETIC_CONFIG');
  if (location.origin !== 'https://chatgpt.com' || globalThis.__riftletRound2Network) throw Error('INSTALL_REFUSED');
  const nativeFetch = globalThis.fetch, proto = XMLHttpRequest.prototype;
  const nativeOpen = proto.open, nativeSend = proto.send;
  const events = [], meta = new WeakMap(), pending = new Set(), cloneReaders = new Set();
  let closed = false, inputCount = 0, changeHashOK = false, inputHash = Promise.resolve(false);
  let boundInput = null, boundForm = null, card = null, progress = null;
  let uploadURL = null, createCount = 0, createHashOK = false, faultInjected = false, ui100 = false;
  let nextRequest = 0, sequence = 0, observer = null, timer = null;
  let sink = document.createElement('script');
  sink.type = 'application/json'; sink.id = 'riftlet-round2-network-receipt'; sink.dataset.session = cfg.sessionId;
  if (document.getElementById(sink.id)) throw Error('SINK_EXISTS');
  document.documentElement.appendChild(sink);
  function snapshot() {
    return {schemaVersion: 1, sessionId: cfg.sessionId, operationID: cfg.operationID ?? null,
      uploadName: cfg.name ?? null, bindNextGeneratedInput: bindNext,
      state: closed ? 'STOPPED' : inputCount ? 'OBSERVING_INPUT' : 'ARMED', mode: cfg.mode,
      inputCount, changeHashOK, createCount, uniqueCreationURL: !!uploadURL, createHashOK,
      ui100, faultInjected, pendingRequests: pending.size, requestsInitiatedByBridge: 0,
      events: events.slice()};
  }
  function flush() { sink.textContent = JSON.stringify(snapshot()); }
  function log(event, facts = {}) {
    if (events.length >= 240) { if (!closed) stop('EVENT_BOUND'); return; }
    events.push({sequence: ++sequence, monotonicMs: performance.now(), event, ...facts}); flush();
  }
  function validOwner() { return !closed && inputCount === 1 && boundInput?.isConnected && boundForm?.isConnected && boundForm.contains(boundInput); }
  const hex = bytes => [...new Uint8Array(bytes)].map(x => x.toString(16).padStart(2, '0')).join('');
  async function hash(blob) { return hex(await crypto.subtle.digest('SHA-256', await blob.arrayBuffer())); }
  function exactNameJSON(body) {
    if (typeof body !== 'string' || body.length > 65536) return false;
    let value; try { value = JSON.parse(body); } catch { return false; }
    const scan = (v, depth) => depth <= 5 && (v === cfg.name ||
      (Array.isArray(v) ? v.some(x => scan(x, depth + 1)) :
      v && typeof v === 'object' && Object.values(v).some(x => scan(x, depth + 1))));
    return !!scan(value, 0);
  }
  function requestURL(input) {
    try { return typeof input === 'string' || input instanceof URL ? String(input) : input instanceof Request ? input.url : null; } catch { return null; }
  }
  function inputChanged(event) {
    const el = event.target;
    if (closed || !(el instanceof HTMLInputElement) || el.type !== 'file') return;
    const files = Array.from(el.files || []);
    if (!bindNext && !files.some(f => f.name === cfg.name)) return;
    inputCount++;
    const nextIdentity = bindNext && inputCount === 1 && files.length === 1
      ? /^riftlet-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.png$/.exec(files[0].name) : null;
    if (inputCount !== 1 || files.length !== 1 || files[0].size !== cfg.bytes || files[0].type !== 'image/png' || !el.form || (bindNext && !nextIdentity)) {
      log('own_input_refused', {inputCount}); stop('INPUT_IDENTITY'); return;
    }
    if (bindNext) { cfg.operationID = nextIdentity[1]; cfg.name = files[0].name; }
    boundInput = el; boundForm = el.form;
    log('own_input_observed', {inputCount, byteCount: files[0].size});
    inputHash = hash(files[0]).then(value => {
      changeHashOK = value === cfg.sha256;
      log('own_input_hash', {matched: changeHashOK});
      if (!changeHashOK) stop('INPUT_HASH');
      return changeHashOK;
    }, () => { log('own_input_hash_failed'); stop('INPUT_HASH'); return false; });
  }
  document.addEventListener('change', inputChanged, true);
  async function learnCreation(response, ordinal) {
    if (!validOwner() || ordinal !== 1 || !response.ok || !(await inputHash) || !validOwner()) return;
    // Only the exact generated-name creation response is cloned and bounded.
    let reader;
    try {
      reader = response.clone().body?.getReader(); if (!reader) return;
      cloneReaders.add(reader);
      const parts = []; let size = 0;
      while (true) {
        const part = await reader.read(); if (part.done) break;
        size += part.value.byteLength;
        if (size > 65536 || !validOwner()) { void reader.cancel(); log('creation_linkage_refused'); return; }
        parts.push(part.value);
      }
      const bytes = new Uint8Array(size); let offset = 0;
      for (const part of parts) { bytes.set(part, offset); offset += part.length; }
      const value = JSON.parse(new TextDecoder().decode(bytes)), urls = new Set();
      const scan = (v, depth = 0) => {
        if (!v || typeof v !== 'object' || depth > 5) return;
        for (const [key, item] of Object.entries(v)) {
          if (typeof item === 'string' && /url/i.test(key) && /^https:\/\//.test(item)) urls.add(item);
          else if (item && typeof item === 'object') scan(item, depth + 1);
        }
      };
      scan(value);
      if (!validOwner() || createCount !== 1 || urls.size !== 1) { log('creation_linkage_refused', {urlCount: urls.size}); return; }
      uploadURL = [...urls][0]; createHashOK = true;
      log('own_creation_linkage', {uniqueURL: true, inputHashMatched: true});
    } catch { log('creation_linkage_unavailable'); }
    finally { cloneReaders.delete(reader); try { reader?.releaseLock(); } catch {} }
  }
  async function ownBytes(body, url) {
    if (!validOwner() || !uploadURL || url !== uploadURL || !createHashOK || !(body instanceof Blob) || body.size !== cfg.bytes) return false;
    try {
      const result = await hash(body);
      const matched = validOwner() && createCount === 1 && createHashOK && url === uploadURL && result === cfg.sha256;
      log('own_bytes_hash', {matched}); return matched;
    } catch { log('own_bytes_hash_failed'); return false; }
  }
  function abortOne(r, trigger) {
    if (!validOwner() || !changeHashOK || !createHashOK || faultInjected || !r.pending || !r.hashMatched) return false;
    if (cfg.mode === 'MID' && !(r.loaded > 0 && r.total > r.loaded && r.lengthComputable)) return false;
    if (cfg.mode === 'POST100' && !ui100) return false;
    if (!r.canAbort()) { log('abort_too_late', {requestLocalId: r.id}); return false; }
    faultInjected = true;
    log('native_abort_requested', {requestLocalId: r.id, transport: r.transport, trigger,
      ui100, loaded: r.loaded ?? null, total: r.total ?? null});
    r.abort(); return true;
  }
  function started(transport, abort, canAbort) {
    const r = {id: ++nextRequest, transport, abort, canAbort, pending: true, hashMatched: true};
    pending.add(r); log('native_bytes_request_started', {requestLocalId: r.id, transport, afterFault: faultInjected}); return r;
  }
  function ended(r, event, facts = {}) {
    r.pending = false; pending.delete(r); log(event, {requestLocalId: r.id, transport: r.transport, ...facts});
  }
  function wrappedFetch(input, init) {
    const receiver = this, originalArgs = arguments, url = requestURL(input), body = init?.body;
    if (!validOwner()) return nativeFetch.apply(receiver, originalArgs);
    if (exactNameJSON(body)) {
      const ordinal = ++createCount;
      if (ordinal !== 1) { uploadURL = null; createHashOK = false; }
      log('own_creation_request', {ordinal, afterFault: faultInjected});
      return nativeFetch.apply(receiver, originalArgs).then(async response => {
        log('own_creation_response', {ordinal, status: response.status});
        await learnCreation(response, ordinal); return response;
      }, error => { log('own_creation_rejected', {ordinal}); throw error; });
    }
    // Cached-fetch/Request-body paths are not silently assumed covered.
    if (!uploadURL || url !== uploadURL || !(body instanceof Blob) || body.size !== cfg.bytes) return nativeFetch.apply(receiver, originalArgs);
    return ownBytes(body, url).then(matched => {
      if (!matched || !validOwner()) return nativeFetch.apply(receiver, originalArgs);
      const ac = new AbortController(), originalSignal = init?.signal || (input instanceof Request ? input.signal : null);
      const signal = originalSignal ? AbortSignal.any([originalSignal, ac.signal]) : ac.signal;
      const r = started('fetch', () => ac.abort(), () => r.pending && !ac.signal.aborted && !originalSignal?.aborted);
      let promise;
      try { promise = nativeFetch.call(receiver, input, {...init, signal}); }
      catch (error) { ended(r, 'native_bytes_sync_error'); throw error; }
      if (cfg.mode === 'POST100' && ui100) queueMicrotask(() => abortOne(r, 'own_ui100_pending_fetch'));
      return promise.then(response => { ended(r, 'native_bytes_response', {status: response.status}); return response; }, error => {
        ended(r, 'native_bytes_rejected', {abortedByProbe: ac.signal.aborted, abortError: error?.name === 'AbortError'}); throw error;
      });
    });
  }
  function wrappedOpen(method, url, async = true) {
    const result = nativeOpen.apply(this, arguments);
    meta.set(this, {url: String(url), async: async !== false}); return result;
  }
  function wrappedSend(body) {
    const xhr = this, originalArgs = arguments, info = meta.get(xhr);
    if (!validOwner() || !info?.async || !uploadURL || info.url !== uploadURL || !(body instanceof Blob) || body.size !== cfg.bytes) return nativeSend.apply(xhr, originalArgs);
    void ownBytes(body, info.url).then(matched => {
      if (meta.get(xhr) !== info || xhr.readyState !== 1) { log('own_xhr_cancelled_before_send'); return; }
      if (!matched || !validOwner()) { nativeSend.apply(xhr, originalArgs); return; }
      const r = started('xhr', () => xhr.abort(), () => xhr.readyState !== 0 && xhr.readyState !== 4 && r.pending);
      xhr.upload.addEventListener('progress', event => {
        r.loaded = event.loaded; r.total = event.total; r.lengthComputable = event.lengthComputable;
        log('native_upload_progress', {requestLocalId: r.id, loaded: event.loaded, total: event.total, lengthComputable: event.lengthComputable});
        if (cfg.mode === 'MID') abortOne(r, 'native_mid_upload_progress');
      });
      xhr.addEventListener('abort', () => log('native_abort_event', {requestLocalId: r.id}), {once: true});
      xhr.addEventListener('error', () => log('native_network_error', {requestLocalId: r.id}), {once: true});
      xhr.addEventListener('loadend', () => ended(r, 'native_loadend', {status: xhr.status}), {once: true});
      try { nativeSend.apply(xhr, originalArgs); }
      catch { ended(r, 'native_bytes_sync_error'); return; }
      if (cfg.mode === 'POST100' && ui100) queueMicrotask(() => abortOne(r, 'own_ui100_pending_xhr'));
    }).catch(() => log('own_xhr_bridge_error'));
  }
  function observeProgress() {
    if (!validOwner()) return;
    const cards = [...boundForm.querySelectorAll('[role="button"][aria-label]')].filter(node => node.getAttribute('aria-label') === cfg.name);
    if (cards.length !== 1 || (card && card !== cards[0])) return;
    card ||= cards[0];
    const bars = [...card.querySelectorAll('[role="progressbar"]')].filter(node => node.getAttribute('aria-label') === `正在上传 ${cfg.name}`);
    if (bars.length !== 1 || (progress && progress !== bars[0])) return;
    progress ||= bars[0];
    if (!ui100 && progress.hasAttribute('aria-valuenow') && Number(progress.getAttribute('aria-valuenow')) === 100) {
      ui100 = true; log('own_ui_progress100');
    }
    if (cfg.mode === 'POST100' && ui100) for (const r of pending) if (abortOne(r, 'own_ui_progress100')) break;
  }
  observer = new MutationObserver(observeProgress);
  observer.observe(document.documentElement, {subtree: true, childList: true, attributes: true, attributeFilter: ['aria-valuenow']});
  function stop(reason = 'EXPLICIT_STOP') {
    if (closed) return snapshot();
    closed = true; clearTimeout(timer); observer?.disconnect(); document.removeEventListener('change', inputChanged, true);
    // Cancel only our bounded clone consumers, never the original response or
    // its request. Do not await tee cancellation: the original can stay open.
    for (const reader of cloneReaders) { try { void reader.cancel().catch(() => {}); } catch {} }
    cloneReaders.clear();
    globalThis.removeEventListener('pagehide', onPageHide);
    if (globalThis.fetch === wrappedFetch) globalThis.fetch = nativeFetch;
    if (proto.open === wrappedOpen) proto.open = nativeOpen;
    if (proto.send === wrappedSend) proto.send = nativeSend;
    uploadURL = null;
    log('bridge_stopped', {reason, originalsRestored: globalThis.fetch === nativeFetch && proto.open === nativeOpen && proto.send === nativeSend,
      faultInjected, pendingRequests: pending.size});
    // Event-bound stop cannot append another log entry, but the DOM receipt
    // must still publish STOPPED and the final counters.
    flush();
    return snapshot();
  }
  function onPageHide() { stop('PAGEHIDE'); }
  globalThis.addEventListener('pagehide', onPageHide);
  globalThis.fetch = wrappedFetch; proto.open = wrappedOpen; proto.send = wrappedSend;
  globalThis.__riftletRound2Network = Object.freeze({sessionId: cfg.sessionId, query: snapshot, stop});
  timer = setTimeout(() => stop('DEADLINE_60S'), 60000);
  log('bridge_installed', {oneAbortMaximum: true, requestsInitiatedByBridge: 0});
  return {sessionId: cfg.sessionId, installed: true};
})();
