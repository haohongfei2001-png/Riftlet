'use strict';

(() => {
  const mode = document.body.dataset.case;
  const cases = ['complete', 'partial', 'expired', 'source-changed', 'request-released', 'pagehide'];
  const pagePath = '/case/' + mode;
  const pageURL = location.href;
  if (!cases.includes(mode) || location.origin !== 'http://127.0.0.1:' + location.port ||
      location.pathname !== pagePath || window.top !== window || location.search || location.hash) {
    throw Error('Fixture origin required');
  }
  const form = document.querySelector('form');
  const input = form?.querySelector('input[type=file]');
  const documentRoot = document.documentElement;
  if (!form || !input) throw Error('Fixture form required');

  const counts = {input: 0, change: 0, create: 0, sends: 0, abortCalls: 0, formSubmit: 0, sendButton: 0};
  const inputEvents = [], events = [], listeners = [], inflight = new Set();
  const reservations = new Map();
  const hash = async bytes => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)),
    part => part.toString(16).padStart(2, '0')).join('');
  let file, transfer, deadline, timer, poll, changes, disposition, trigger = null;
  let createPending = 0, sendReturned = false, abortReturned = false;
  let requestStarts = 0, uploadStarts = 0, nativeTerminal = null;
  const listen = (node, type, handler) => {
    node.addEventListener(type, handler);
    listeners.push(() => node.removeEventListener(type, handler));
  };

  function reportWithoutPUT() {
    if (!disposition || nativeTerminal || counts.sends !== 0 || createPending !== 0 || inflight.size !== 0) return;
    window.result = {refused: disposition.reason, disposition, pendingCreates: createPending, pendingXHR: inflight.size};
  }
  function withdraw(reason, pagehideTrusted) {
    if (disposition) return;
    const removed = listeners.length;
    while (listeners.length) listeners.pop()();
    changes.disconnect();
    clearTimeout(timer);
    clearInterval(poll);
    disposition = {reason, atMS: performance.now(), deadlineMS: deadline, listenersRemoved: removed,
      observerListenersRemaining: listeners.length, mutationObserverDisconnected: true,
      pendingXHRAtWithdrawal: inflight.size, pendingCreatesAtWithdrawal: createPending};
    if (reason === 'pagehide') disposition.pagehideTrusted = pagehideTrusted;
    reservations.clear();
    reportWithoutPUT();
  }
  function armDeadline(duration) {
    clearTimeout(timer);
    deadline = performance.now() + duration;
    const expire = () => {
      if (disposition) return;
      const remaining = deadline - performance.now();
      if (remaining <= 0) withdraw('expired');
      else timer = setTimeout(expire, Math.ceil(remaining));
    };
    timer = setTimeout(expire, duration);
  }
  function checkOriginal() {
    if (disposition) return false;
    let reason;
    if (performance.now() >= deadline) reason = 'expired';
    else if (location.href !== pageURL || document.documentElement !== documentRoot || !form.isConnected ||
             !input.isConnected || !form.contains(input) || document.querySelectorAll('form input[type=file]').length !== 1 ||
             (file && (input.files.length !== 1 || input.files[0] !== file))) reason = 'source-changed';
    else if (transfer && (reservations.size !== 1 || reservations.get(transfer.requestID) !== transfer ||
             transfer.file !== file || transfer.upload !== transfer.xhr.upload ||
             counts.create !== 1 || counts.sends > 1 || requestStarts > 1 || uploadStarts > 1 ||
             (sendReturned && !nativeTerminal && (inflight.size !== 1 || !inflight.has(transfer.xhr))))) reason = 'request-changed';
    if (reason) withdraw(reason);
    return !disposition;
  }
  function record(phase, event, target) {
    const xhr = transfer.xhr;
    const row = {phase, type: event.type, trusted: event.isTrusted, sameTarget: event.target === target && event.currentTarget === target,
      elapsedMS: Math.round(performance.now()), readyState: xhr.readyState, status: xhr.status};
    if (typeof event.loaded === 'number') Object.assign(row, {loaded: event.loaded, total: event.total, lengthComputable: event.lengthComputable});
    events.push(row);
    return row;
  }

  // The normal local application owns this one completion handler. It performs no cancellation and
  // stays installed during an ordinary in-flight PUT after the independent observer is withdrawn.
  function finish(event) {
    const {xhr, fileSHA256, requestID, urlSHA256} = transfer;
    if (!event.isTrusted || event.target !== xhr || event.currentTarget !== xhr || !inflight.delete(xhr)) return;
    nativeTerminal = {type: event.type, trusted: true, originalInstance: true, status: xhr.status};
    xhr.onloadend = null;
    queueMicrotask(() => {
      withdraw('native-terminal');
      window.result = {mode, requestID, urlSHA256, fileSHA256, fileBytes: file.size, createStatus: 201, counts,
        inputEvents, events, trigger, sendReturned, abortReturned, disposition, nativeTerminal, pendingCreates: createPending,
        listenersRemoved: disposition.listenersRemoved, listenersRemaining: listeners.length, pendingXHR: inflight.size,
        normalCompletionHandlerRemoved: xhr.onloadend === null, terminalEvent: nativeTerminal.type};
    });
  }
  function observeRequest() {
    const {xhr, upload} = transfer;
    for (const phase of ['upload', 'request']) {
      const emitter = phase === 'request' ? xhr : upload;
      const types = ['loadstart', 'progress', 'abort', 'error', 'timeout', 'load', 'loadend'];
      if (phase === 'request') types.push('readystatechange');
      for (const type of types) listen(emitter, type, event => {
        if (event.type === 'loadstart') {
          if (phase === 'request') requestStarts++; else uploadStarts++;
        }
        if (!checkOriginal()) return;
        const s = record(phase, event, emitter);
        if (!s.trusted || !s.sameTarget) { withdraw('request-changed'); return; }
        if (mode === 'complete' || phase !== 'upload' || type !== 'progress' || counts.abortCalls !== 0 ||
            !sendReturned || xhr.readyState !== XMLHttpRequest.OPENED || xhr.status !== 0 || xhr.responseURL ||
            requestStarts !== 1 || uploadStarts !== 1 || !event.lengthComputable || event.total !== file.size ||
            event.loaded < 0.10 * file.size || event.loaded > 0.50 * file.size) return;
        if (!checkOriginal()) return;
        trigger = {...s, fraction: event.loaded / file.size, sendReturned, originalFile: transfer.file === input.files[0],
          originalInstance: transfer.xhr === xhr && transfer.upload === xhr.upload};
        counts.abortCalls++;
        xhr.abort();
        abortReturned = true;
      });
    }
    xhr.onloadend = finish;
  }

  armDeadline(8000);
  changes = new MutationObserver(checkOriginal);
  changes.observe(documentRoot, {childList: true, subtree: true});
  poll = setInterval(checkOriginal, 25);
  listen(window, 'pagehide', event => withdraw('pagehide', event.isTrusted));
  listen(form, 'submit', event => { counts.formSubmit++; event.preventDefault(); });
  listen(form.querySelector('button'), 'click', () => counts.sendButton++);
  listen(input, 'input', event => {
    if (file) {withdraw('source-changed');return;}
    counts.input++;
    inputEvents.push({type: event.type, trusted: event.isTrusted});
  });
  listen(input, 'change', async event => {
    counts.change++;
    inputEvents.push({type: event.type, trusted: event.isTrusted});
    try {
      if (file || !event.isTrusted || counts.input !== 1 || counts.change !== 1 || input.files.length !== 1 ||
          !(input.files[0] instanceof File) || input.files[0].type !== 'image/png') throw Error('Unexpected original File');
      file = input.files[0];
      const fileSHA256 = await hash(await file.arrayBuffer());
      if (!checkOriginal()) return;
      counts.create++;
      createPending++;
      let granted;
      try {
        const r = await fetch(pagePath + '/create', {method: 'POST', credentials: 'omit', redirect: 'error',
          headers: {'Content-Type': 'application/json'}, body: JSON.stringify({fileSHA256, bytes: file.size})});
        if (r.status !== 201) throw Error('Original transfer unavailable');
        granted = await r.json();
      } finally { createPending--; reportWithoutPUT(); }
      if (!checkOriginal()) return;
      const {requestID, putPath} = granted;
      if (!/^[a-f0-9-]{36}$/.test(requestID) || putPath !== pagePath + '/png/' + requestID) throw Error('Unexpected local target');
      const putURL = new URL(putPath, location.origin).href;
      const urlSHA256 = await hash(new TextEncoder().encode(putURL));
      if (!checkOriginal()) return;
      const xhr = new XMLHttpRequest();
      transfer = Object.freeze({xhr, upload: xhr.upload, file, requestID, fileSHA256, urlSHA256});
      reservations.set(requestID, transfer);
      observeRequest();
      xhr.open('PUT', putURL);
      if (!checkOriginal()) return;
      counts.sends++;
      inflight.add(xhr);
      try {
        xhr.send(transfer.file);
      } catch (error) {
        // A synchronous native rejection before the request starts leaves no dispatched request.
        if (requestStarts === 0 && xhr.readyState === XMLHttpRequest.OPENED) {
          inflight.delete(xhr);
          xhr.onloadend = null;
        }
        throw error;
      }
      sendReturned = true;
      // The negative controls belong exclusively to their fixed loopback fixture pages.
      if (mode === 'expired') armDeadline(12);
      if (mode === 'source-changed') input.replaceWith(input.cloneNode(false));
      if (mode === 'request-released') {
        reservations.delete(requestID);
        checkOriginal();
      }
      if (mode === 'pagehide') window.dispatchEvent(new PageTransitionEvent('pagehide'));
    } catch (err) {
      withdraw('preparation-refused');
      if (inflight.size === 0) window.result = {refused: err.message, disposition, pendingCreates: createPending, pendingXHR: inflight.size};
    }
  });
  window.ready = true;
})();
