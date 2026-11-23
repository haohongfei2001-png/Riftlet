(function armCalibration(config, editor) {
  "use strict";
  const key = Symbol.for("riftlet.g4.passive.v1");
  const reject = reason => ({kind: "g4-passive-v1", status: "BLOCKED_ENV", reason});
  const pageURL = "https://chatgpt.com/?temporary-chat=true";
  const createPath = "/backend-api/files";
  const createURL = "https://chatgpt.com" + createPath;
  const fileName = /^riftlet-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.png$/i;
  if (!config || !/^[0-9a-f]{32,128}$/i.test(config.nonce) ||
      !/^[0-9a-f]{64}$/.test(config.pngSHA256) || !Number.isSafeInteger(config.pngBytes) ||
      config.pngBytes < 1 || config.pngBytes > 16 * 1024 * 1024 ||
      typeof config.entryID !== "string" || !config.entryID ||
      !Number.isFinite(config.timeOrigin)) return reject("invalid-config");
  if (key in globalThis) return reject("occupied");
  const doc = document;
  const form = editor?.closest?.("form");
  const visible = node => node.isConnected && node.getClientRects().length > 0 &&
    node.checkVisibility({checkOpacity:true, checkVisibilityCSS:true});
  function scope() {
    try {
      const forms = [...doc.querySelectorAll("main form")].filter(visible);
      if (forms.length !== 1 || forms[0] !== form) return false;
      const editors = [...form.querySelectorAll("[contenteditable=true],textarea,[role=textbox]")]
        .filter(node => visible(node) && (node.isContentEditable || node.tagName === "TEXTAREA"));
      return window === top && doc === document && location.href === pageURL &&
        doc.visibilityState === "visible" && performance.timeOrigin === config.timeOrigin &&
        navigation.currentEntry?.id === config.entryID && editor?.ownerDocument === doc &&
        form?.contains(editor) && editor.closest("form") === form &&
        editors.length === 1 && editors[0] === editor;
    } catch { return false; }
  }
  if (!scope()) return reject("original-target-unproven");
  const xproto = XMLHttpRequest.prototype;
  const targets = [[globalThis, "fetch"], [xproto, "open"], [xproto, "send"]];
  const slots = targets.map(([owner, name]) => Object.getOwnPropertyDescriptor(owner, name));
  if (slots.some(s => !s || !s.writable || typeof s.value !== "function") ||
      typeof crypto.subtle?.digest !== "function") return reject("observer-unavailable");

  const [nativeFetch, nativeOpen, nativeSend] = slots.map(s => s.value);
  let file = null, input = null, signed = null, timer = null, active = true, reason = null;
  let creates = 0, responses = 0, byteRequests = 0, inputs = 0, changes = 0, pending = 0;
  let sourceVerified = false, bytesVerified = false, sameFile = null, operationHash = null;
  let endpointHash = null, signedHash = null, createTransport = null, byteTransport = null;
  let byteType = null, createNameField = null, responseField = null, responseStatus = null;
  let restored = false, carried = null, installed = 0, earlyXHR = null;
  let byteToken = null, byteReturned = false, byteCompleted = false, byteStatus = null;
  let bodyScope = null, bodySize = null, cloneReader = null;
  const requests = new WeakMap();
  const xhrListeners = new Map();
  let final = null;
  const enc = new TextEncoder();
  const dataProp = (obj, prop) => obj && Object.getOwnPropertyDescriptor(obj, prop)?.value;
  const hash = async bytes => [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map(v => v.toString(16).padStart(2, "0")).join("");
  function normalize(arg) {
    if (typeof arg !== "string" && !(arg instanceof URL)) return null;
    try { return new URL(arg, pageURL).href; } catch { return null; }
  }
  function work(job) {
    pending++;
    Promise.resolve().then(job).catch(() => stop("observer-read-error")).finally(() => { pending--; });
  }
  function observe(job) { try { job(); } catch { stop("observer-read-error"); } }
  function valid() {
    if (active && !scope()) stop("original-target-changed");
    return active;
  }
  function stop(why) {
    if (!active) return;
    reason ??= why;
    active = false;
    clearTimeout(timer);
    doc.removeEventListener("input", onFile, true);
    doc.removeEventListener("change", onFile, true);
    window.removeEventListener("pagehide", leave, true);
    document.removeEventListener("visibilitychange", onVisibility, true);
    for (const [xhr, [event, listener]] of xhrListeners) xhr.removeEventListener(event, listener);
    if (cloneReader) { void cloneReader.cancel().catch(() => {}); cloneReader = null; }
    xhrListeners.clear();
    restored = true;
    for (let i = installed - 1; i >= 0; i--) {
      const [owner, name] = targets[i];
      const current = Object.getOwnPropertyDescriptor(owner, name);
      if (current?.value !== wrappers[i]) { restored = false; continue; }
      try { Object.defineProperty(owner, name, slots[i]); } catch { restored = false; }
    }
    if (!restored) reason = "observer-restoration-conflict";
    file = input = signed = carried = earlyXHR = byteToken = null;
  }
  const leave = () => stop("page-left");
  const onVisibility = () => { if (doc.visibilityState !== "visible") stop("page-hidden"); };
  function onFile(ev) {
    observe(() => {
      const el = ev.target;
      if (!(el instanceof HTMLInputElement) || el.type !== "file" || !valid()) return;
      if (el.ownerDocument !== doc || !el.isConnected || !(el.form === form || form.contains(el)))
        return stop("input-owner-unproven");
      if (el.files.length !== 1) return stop("ambiguous-file-list");
      const next = el.files[0];
      const match = fileName.exec(next.name);
      if (!(next instanceof File) || !match || next.type !== "image/png" || next.size !== config.pngBytes)
        return stop("unexpected-input-file");
      if (ev.type === "change") {
        changes++;
        if (changes !== 1 || inputs !== 1 || el !== input || next !== file) stop("change-mismatch");
        return;
      }
      inputs++;
      if (inputs !== 1 || changes) return stop("repeated-input");
      input = el; file = next;
      work(async () => {
        const digest = await hash(await next.arrayBuffer());
        if (!active) return;
        if (digest !== config.pngSHA256) return stop("source-sha-mismatch");
        operationHash = await hash(enc.encode(match[1].toLowerCase()));
        if (active) sourceVerified = true;
      });
    });
  }
  function classifyCreate(body, transport) {
    if (!valid() || !file) return false;
    if (typeof body !== "string" || body.length > 8192) { stop("unverified-create-body"); return false; }
    let json;
    try { json = JSON.parse(body); } catch { stop("unverified-create-body"); return false; }
    if (!json || typeof json !== "object" || Array.isArray(json)) { stop("unverified-create-body"); return false; }
    const keys = ["file_name", "filename", "name"].filter(k => Object.hasOwn(json, k));
    if (keys.length !== 1 || json[keys[0]] !== file.name) { stop("create-file-binding-ambiguous"); return false; }
    for (const k of ["file_size", "size", "file_size_bytes"]) {
      if (Object.hasOwn(json, k) && json[k] !== file.size) { stop("create-size-mismatch"); return false; }
    }
    creates++;
    if (creates !== 1) { stop("repeated-create"); return false; }
    createTransport = transport; createNameField = keys[0];
    work(async () => { const h = await hash(enc.encode(createURL)); if (active) endpointHash = h; });
    return true;
  }
  function link(response, status) {
    if (!valid()) return;
    responses++;
    if (responses !== 1 || !Number.isInteger(status) || status < 200 || status > 299 ||
        !response || typeof response !== "object" || Array.isArray(response)) return stop("invalid-create-response");
    const keys = ["upload_url", "uploadUrl"].filter(k => Object.hasOwn(response, k));
    if (keys.length !== 1 || typeof response[keys[0]] !== "string" ||
        response[keys[0]].length > 8192) return stop("upload-url-field-unproven");
    let dest;
    try { dest = new URL(response[keys[0]]); } catch { return stop("invalid-upload-url"); }
    if (dest.protocol !== "https:" || dest.username || dest.password || dest.hash || dest.href === createURL)
      return stop("invalid-upload-url");
    signed = dest.href; responseField = keys[0]; responseStatus = status;
    work(async () => { const h = await hash(enc.encode(dest.href)); if (active) signedHash = h; });
    if (carried) {
      const early = carried; carried = null;
      if (early.url !== signed) {
        if (!early.unbound) return stop("unlinked-early-byte-request");
      } else if (early.unbound) return stop("early-byte-body-unproven");
      else admitBytes(early);
    }
  }
  async function fetchReply(res) {
    if (!valid()) return;
    if (res.redirected || res.url !== createURL || !/^application\/(?:[a-z+.-]*\+)?json\b/i.test(res.headers.get("content-type") || ""))
      return stop("create-response-origin-or-type");
    const len = Number(res.headers.get("content-length"));
    if (len > 65536) return stop("oversize-create-response");
    const reader = res.clone().body?.getReader();
    if (!reader) return stop("unreadable-create-response");
    cloneReader = reader;
    const decoder = new TextDecoder(); let count = 0, text = "";
    try {
      while (active) {
        const {done, value} = await reader.read();
        if (done) break;
        count += value.length;
        if (count > 65536) { stop("oversize-create-response"); break; }
        text += decoder.decode(value, {stream: true});
      }
      if (active) link(JSON.parse(text + decoder.decode()), res.status);
    } finally {
      // Only our response clone has this reader.
      if (cloneReader === reader) cloneReader = null;
      reader.releaseLock();
    }
  }
  function identifyBody(body) {
    if (body instanceof Blob) return [body instanceof File ? "File" : "Blob", body.size, "entire-body", body];
    if (body instanceof ArrayBuffer) return ["ArrayBuffer", body.byteLength, "entire-body", body];
    if (ArrayBuffer.isView(body)) return ["ArrayBufferView", body.byteLength, "entire-body", body];
    if (typeof FormData !== "undefined" && body instanceof FormData) {
      let only = null, count = 0;
      for (const value of body.values()) {
        count++;
        if (count > 1 || !(value instanceof File)) return ["FormData", null, "unverified", null];
        only = value;
      }
      return ["FormData", only?.size ?? null, "single-file-part", only];
    }
    return [typeof body === "string" ? "string" : body == null ? "absent" : "unsupported",
      typeof body === "string" ? body.length : null, "unverified", null];
  }
  function verifyCompletion(token) {
    if (!active || token !== byteToken || !token.returned || !token.reply) return;
    try {
      const {url, status, redirected} = token.reply();
      if (redirected || url !== signed || !Number.isInteger(status) || status < 200 || status > 299)
        return stop("byte-transport-unconfirmed");
      byteStatus = status; byteReturned = true; byteCompleted = true;
    } catch { stop("byte-transport-unconfirmed"); }
  }
  function admitBytes(token) {
    byteRequests++;
    if (byteRequests !== 1) return stop("repeated-byte-request");
    byteToken = token;
    byteTransport = token.transport;
    const [type, size, scope, value] = identifyBody(token.body);
    byteType = type; bodySize = size; bodyScope = scope;
    if (!value || size !== config.pngBytes) return stop("byte-body-unproven");
    sameFile = value === file;
    // The browser serializes mutable buffers/FormData at the native call. For a call
    // already dispatched before linkage, only an immutable original Blob can be compared.
    if (token.early && !(value instanceof Blob && token.body instanceof Blob)) return stop("early-mutable-body");
    // Snapshot mutable buffers synchronously at entry to send/fetch.
    let bytes = value;
    if (ArrayBuffer.isView(value)) {
      if (!(value.buffer instanceof ArrayBuffer)) return stop("shared-body-unproven");
      bytes = new Uint8Array(value.buffer, value.byteOffset, value.byteLength).slice();
    } else if (value instanceof ArrayBuffer) { bytes = new Uint8Array(value).slice(); }
    work(async () => {
      const digest = await hash(bytes instanceof Blob ? await bytes.arrayBuffer() : bytes);
      if (!active) return;
      if (digest !== config.pngSHA256) return stop("byte-sha-mismatch");
      bytesVerified = true;
    });
    if (token.returned) byteReturned = true;
    verifyCompletion(token);
  }
  function byteCandidate(url, method, body, transport, tentative = false) {
    if (signed && url === signed) {
      if (method !== "PUT") return stop("unexpected-byte-method");
      const token = {url, body, transport, early:false, returned:false, reply:null};
      admitBytes(token); return active ? token : null;
    }
    if (tentative && body !== file) {
      // Keep the URL metadata only. Do not hold or read an unbound request body.
      if (!signed && !carried) carried = {url, unbound:true};
      return null;
    }
    if (file && body === file && creates === 1) {
      if (!url || signed || carried || method !== "PUT") return stop("ambiguous-byte-route");
      carried = {url, body, transport, early:true, returned:false, reply:null};
      return carried;
    }
    return null;
  }
  function returned(token) {
    if (!token || !active) return;
    token.returned = true;
    if (token === byteToken) byteReturned = true;
    verifyCompletion(token);
  }
  function fetchWrapper(resource, init) {
    let create = false, token = null;
    observe(() => {
      if (!file || !valid()) return;
      const request = resource instanceof Request ? resource : null;
      const url = normalize(request ? request.url : resource);
      // Read plain data descriptors only. Never enumerate init, headers or account responses.
      const body = dataProp(init, "body");
      if (url !== createURL && url !== signed && body !== file) return;
      const method = String(dataProp(init, "method") || request?.method || "GET").toUpperCase();
      if (url === createURL && method === "POST") create = classifyCreate(body, "fetch");
      else token = byteCandidate(url, method, body, "fetch");
    });
    let result;
    try { result = Reflect.apply(nativeFetch, this, arguments); }
    catch (e) { if (create || token) stop("native-fetch-threw"); throw e; }
    returned(token);
    if (create) {
      // Register before the website receives its original promise. Clone immediately.
      observe(() => Promise.prototype.then.call(result, res => {
        if (!active) return;
        pending++;
        fetchReply(res).catch(() => stop("observer-read-error")).finally(() => { pending--; });
      }, () => stop("create-transport-failed")));
    } else if (token && active) {
      observe(() => Promise.prototype.then.call(result, res => {
        if (!active) return;
        token.reply = () => ({url: res.url, status: res.status, redirected: res.redirected});
        verifyCompletion(token);
      }, () => stop("byte-transport-rejected")));
    }
    return result;
  }
  function openWrapper(method, resource) {
    const result = Reflect.apply(nativeOpen, this, arguments);
    observe(() => {
      requests.delete(this);
      if (!file || !valid() || typeof method !== "string") return;
      const url = normalize(resource), m = method.toUpperCase();
      if (url === createURL && m === "POST") requests.set(this, {url, m});
      else if (signed && url === signed) requests.set(this, {url, m});
      // At most one in-flight PUT after the unique creation request. No headers,
      // response data or body bytes are read until its exact signed URL is linked.
      else if (!signed && creates === 1 && m === "PUT" && url?.startsWith("https://")) {
        if (earlyXHR) return stop("ambiguous-early-xhr");
        earlyXHR = this; requests.set(this, {url, m, tentative:true});
      }
    });
    return result;
  }
  function sendWrapper(body) {
    let token = null, create = false;
    observe(() => {
      const meta = requests.get(this);
      if (!file || !valid()) return;
      if (!meta) {
        if (body === file && creates === 1) stop("xhr-original-file-url-unproven");
        return;
      }
      if (meta.url !== createURL) {
        token = byteCandidate(meta.url, meta.m, body, "xhr", meta.tentative);
        if (!token || !active) return;
        const xhr = this;
        const completed = () => {
          xhrListeners.delete(xhr);
          if (!active) return;
          token.reply = () => ({url:xhr.responseURL, status:xhr.status, redirected:false});
          verifyCompletion(token);
        };
        xhrListeners.set(xhr, ["loadend", completed]);
        xhr.addEventListener("loadend", completed, {once:true});
        return;
      }
      create = classifyCreate(body, "xhr");
      if (!create) return;
      const xhr = this;
      const loaded = () => {
        xhrListeners.delete(xhr);
        observe(() => {
          if (!valid()) return;
          if (xhr.responseURL !== createURL || !/^application\/(?:[a-z+.-]*\+)?json\b/i.test(xhr.getResponseHeader("content-type") || ""))
            return stop("create-response-origin-or-type");
          const len = Number(xhr.getResponseHeader("content-length"));
          if (len > 65536) return stop("oversize-create-response");
          if (xhr.responseType === "json") { link(xhr.response, xhr.status); return; }
          if (xhr.responseType !== "" && xhr.responseType !== "text") return stop("unreadable-create-response");
          if (xhr.responseText.length > 65536) return stop("oversize-create-response");
          link(JSON.parse(xhr.responseText), xhr.status);
        });
      };
      xhrListeners.set(xhr, ["load", loaded]); xhr.addEventListener("load", loaded, {once: true});
    });
    let result;
    try { result = Reflect.apply(nativeSend, this, arguments); }
    catch (e) { if (create || token) stop("native-send-threw"); throw e; }
    returned(token);
    return result;
  }
  const wrappers = [fetchWrapper, openWrapper, sendWrapper];
  function report(status) {
    return {kind: "g4-passive-v1", status, reason, inputs, changes, creates, responses, byteRequests,
      pending, observerPending:pending, requestPending:Boolean((byteToken || carried) && !byteCompleted),
      byteReturned, byteCompleted, sourceVerified, bytesVerified, sameFile, operationHash,
      create: {transport: createTransport, method: creates ? "POST" : null, path: creates ? createPath : null,
        urlSHA256: endpointHash, fileNameField: createNameField, responseStatus, uploadURLField: responseField},
      bytes: {transport: byteTransport, method: byteTransport ? "PUT" : null, bodyType: byteType, bodyScope, bodySize, responseStatus:byteStatus,
        urlSHA256: signedHash, pngSHA256: sourceVerified ? config.pngSHA256 : null,
        pngBytes: sourceVerified ? config.pngBytes : null}, restored, cancelledByObserver: 0};
  }
  function sample(nonce) {
    if (nonce !== config.nonce) return reject("nonce-mismatch");
    valid(); return final || report(active ? "OBSERVING" : "INCONCLUSIVE");
  }
  function finish(nonce) {
    if (nonce !== config.nonce) return reject("nonce-mismatch");
    if (final) return final;
    const complete = valid() && !reason && !pending && inputs === 1 && changes === 1 &&
      creates === 1 && responses === 1 && byteRequests === 1 && byteReturned && byteCompleted && sourceVerified && bytesVerified &&
      !!operationHash && !!endpointHash && !!signedHash;
    stop(complete ? null : "incomplete-correlation");
    final = Object.freeze(report(complete && restored ? "CALIBRATED" : "INCONCLUSIVE"));
    if (globalThis[key] === api) delete globalThis[key];
    return final;
  }
  const api = Object.freeze({sample, finish});
  try {
    Object.defineProperty(globalThis, key, {value: api, configurable: true});
    for (let i = 0; i < targets.length; i++) {
      Object.defineProperty(targets[i][0], targets[i][1], {...slots[i], value: wrappers[i]});
      installed++;
    }
    doc.addEventListener("input", onFile, true); doc.addEventListener("change", onFile, true);
    window.addEventListener("pagehide", leave, true);
    doc.addEventListener("visibilitychange", onVisibility, true);
    timer = setTimeout(() => stop("deadline"), 60000);
    return {kind: "g4-passive-v1", status: "ARMED", deadlineMs: 60000, cancelledByObserver: 0};
  } catch {
    stop("installation-failed");
    if (globalThis[key] === api) delete globalThis[key];
    return reject("installation-failed");
  }
})
