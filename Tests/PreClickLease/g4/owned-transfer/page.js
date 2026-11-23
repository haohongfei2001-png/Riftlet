'use strict';

(async () => {
  const input = document.querySelector('input[type=file]');
  const mode = document.body.dataset.case;
  const pagePath = '/case/' + mode;
  if (location.hostname !== '127.0.0.1' || location.pathname !== pagePath ||
      !['complete', 'partial'].includes(mode) || window.top !== window) throw Error('Fixture origin required');
  const counts = {input: 0, change: 0, create: 0, sends: 0, abortCalls: 0, formSubmit: 0, sendButton: 0};
  const inputEvents = [];
  const listeners = [];
  const inflight = new Set();
  const events = [];
  const hash = async bytes => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)),
    part => part.toString(16).padStart(2, '0')).join('');
  const listen = (target, type, callback) => {
    target.addEventListener(type, callback);
    listeners.push(() => target.removeEventListener(type, callback));
  };
  const form = document.querySelector('form');
  listen(form, 'submit', event => { counts.formSubmit++; event.preventDefault(); });
  listen(form.querySelector('button'), 'click', () => counts.sendButton++);
  listen(input, 'input', event => { counts.input++; inputEvents.push({type: event.type, trusted: event.isTrusted}); });
  listen(input, 'change', async event => {
    counts.change++;
    inputEvents.push({type: event.type, trusted: event.isTrusted});
    try {
      const [file] = input.files;
      if (counts.change !== 1 || input.files.length !== 1 || !(file instanceof File) || file.type !== 'image/png')
        throw Error('Expected one native PNG File');
      const fileSHA256 = await hash(await file.arrayBuffer());
      counts.create++;
      const reply = await fetch(pagePath + '/create', {method: 'POST', credentials: 'omit', redirect: 'error',
        headers: {'Content-Type': 'application/json'}, body: JSON.stringify({fileSHA256, bytes: file.size})});
      if (reply.status !== 201) throw Error('Expected a new local upload');
      const {requestID, putPath} = await reply.json();
      if (!/^[a-f0-9-]{36}$/.test(requestID) || putPath !== pagePath + '/png/' + requestID) throw Error('Unexpected target');
      const putURL = new URL(putPath, location.origin).href;
      const urlSHA256 = await hash(new TextEncoder().encode(putURL));
      const xhr = new XMLHttpRequest();
      const upload = xhr.upload;
      const owned = {requestID, urlSHA256, xhr, upload, file};
      let sendReturned = false, abortReturned = false, trigger = null, terminal = false;
      const record = (phase, e) => {
        const target = phase === 'request' ? xhr : upload;
        const data = {phase, type: e.type, trusted: e.isTrusted, sameTarget: e.target === target && e.currentTarget === target,
          elapsedMS: Math.round(performance.now()), readyState: xhr.readyState, status: xhr.status};
        if (typeof e.loaded === 'number') Object.assign(data, {loaded: e.loaded, total: e.total, lengthComputable: e.lengthComputable});
        events.push(data);
        return data;
      };
      for (const phase of ['upload', 'request']) {
        const emitter = phase === 'request' ? xhr : upload;
        const types = ['loadstart', 'progress', 'abort', 'error', 'timeout', 'load', 'loadend'];
        if (phase === 'request') types.push('readystatechange');
        for (const type of types) listen(emitter, type, e => {
          const data = record(phase, e);
          if (mode === 'partial' && phase === 'upload' && type === 'progress' && !terminal && counts.abortCalls === 0 &&
              sendReturned && xhr.readyState === XMLHttpRequest.OPENED && xhr.status === 0 && !xhr.responseURL &&
              data.trusted && data.sameTarget && e.lengthComputable && e.total === file.size &&
              e.loaded >= 0.10 * file.size && e.loaded <= 0.50 * file.size && owned.file === input.files[0] &&
              xhr === owned.xhr && upload === owned.upload) {
            trigger = {...data, fraction: e.loaded / file.size, sendReturned, originalFile: true, originalInstance: true};
            counts.abortCalls++;
            xhr.abort();
            abortReturned = true;
          }
          if (phase === 'request' && type === 'loadend' && data.trusted && data.sameTarget && inflight.delete(xhr)) {
            terminal = true;
            queueMicrotask(() => {
              const registered = listeners.length;
              for (const remove of listeners.splice(0)) remove();
              window.result = {mode, requestID, urlSHA256, fileSHA256, fileBytes: file.size, createStatus: reply.status,
                counts, inputEvents, events, trigger, sendReturned, abortReturned, listenersRemoved: registered,
                listenersRemaining: listeners.length, pendingXHR: inflight.size, terminalEvent: type};
            });
          }
        });
      }
      xhr.open('PUT', putURL);
      if (input.files[0] !== owned.file || xhr !== owned.xhr) throw Error('Selected original changed');
      counts.sends++;
      inflight.add(xhr);
      xhr.send(owned.file);
      sendReturned = true;
    } catch (err) {
      for (const remove of listeners.splice(0)) remove();
      window.result = {refused: String(err.message)};
    }
  });
  window.ready = true;
})();
