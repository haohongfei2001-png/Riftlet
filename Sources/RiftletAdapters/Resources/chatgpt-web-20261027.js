/* Riftlet synthetic Web acceptance integration, 2026-10-27.
 * Derived from the project's real experiment source at 6f4156988f32fa06d4df9f06a43f564b560e0a1d:
 * research/web-attachment-handoff-2026-10-27/src/input/shared-adapter.js,
 * src/observers/{normal-bound-observer,exception-observer}.template.js,
 * src/observers/compare-source-preview-pixels.template.js and the attached classifiers.
 * Narrow development candidates: observed Chinese Home/thread Chat, PNG.
 * This integrated program is NOT the archived program or a new live PASS.
 * No send, composer edits, attachment deletion, initiated request or retry command.
 */
function riftletWebAcceptance(command, native) {
  'use strict';
  // v13 may borrow one intact, known v9/v10/v12 root monitor without replacing its descriptor.
  // Its old native requests remain UNKNOWN instead of acquiring a new lease.
  const KEY = '__riftletWebAcceptance20261027v13';
  const MAX_GENERATIONS = 32; // Frozen legacy monitor compatibility bound.
  const MAX_ACTIVE_PAYLOADS = 32; // Concurrent retained byte payloads, not lifetime identities.
  const MAX_CHUNK_BYTES = 256 * 1024;
  const MAX_BYTES = 8 * 1024 * 1024, MAX_PIXELS = 16 * 1024 * 1024;
  const TARGET_KEYS = ['adapterID', 'surface', 'applicationID', 'sessionID', 'windowID', 'tabID', 'documentID', 'composerID', 'draftGeneration'];
  const sameLogical = (a, b) => (!a && !b) || (!!a && !!b && a.profileID === b.profileID && a.id === b.id);
  const sameTarget = (a, b) => !!a && !!b && TARGET_KEYS.every(k => a[k] === b[k])
    && sameLogical(a.logicalDraftIdentity, b.logicalDraftIdentity)
    && (a.clickBindingID || null) === (b.clickBindingID || null);
  const sameIdentity = (a, b) => !!a && !!b && a.operationID === b.operationID && a.assetID === b.assetID
    && a.attempt === b.attempt && a.assetSHA256 === b.assetSHA256 && sameTarget(a.target, b.target);
  const contextMatches = t => t && ['applicationID', 'sessionID', 'windowID', 'tabID'].every(k => t[k] === native[k]);
  const fail = label => { throw Error(label); };
  const hash = async bytes => [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))]
    .map(n => n.toString(16).padStart(2, '0')).join('');
  const blankObservation = (identity, state = 'invalidated') => ({
    schemaVersion: 2,
    provenance: {source: 'integratedDevelopment', evidenceID: 'W2-integrated-page-20261027'},
    observation: {identity, state, exactImageIdentity: false, belongsToOriginalDraft: false,
      hasError: false, isUploading: false, attachmentAbsent: false, automaticRetryExcluded: false,
      ...(state === 'invalidated' ? {reason: 'originalTargetInvalidated'} : {})}
  });

  // Exact original-File request facts only. No URL, headers, body reads, response
  // text, Request streams, API schema or platform completion semantics. Missing
  // hooks/identity are missing evidence, never a reason to change the input path.
  function originalFileRequests(registry) {
    if (registry.originalFileRequests) return registry.originalFileRequests;
    const files = new WeakMap(), operations = new WeakMap(), xhrs = new WeakMap(), cleaners = new WeakMap(), live = new Set();
    let nextRequest = 0, ended = false, fetchInstalled = false, xhrInstalled = false;
    const fetchDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'fetch');
    const xhrPrototype = typeof XMLHttpRequest === 'function' ? XMLHttpRequest.prototype : null;
    const sendDescriptor = xhrPrototype && Object.getOwnPropertyDescriptor(xhrPrototype, 'send');
    const openDescriptor = xhrPrototype && Object.getOwnPropertyDescriptor(xhrPrototype, 'open');
    const nativeFetch = fetchDescriptor?.value, nativeSend = sendDescriptor?.value, nativeOpen = openDescriptor?.value;
    const uuid = value => typeof value === 'string' && /^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$/.test(value);
    const close = (binding, reason) => {
      if (!binding.closed) { binding.closed = true; binding.reason = reason; }
      live.delete(binding);
      for (const cleanup of [...binding.cleanups]) { try { cleanup(); } catch {} }
      // A retired facts record must not keep a former document/form environment.
      binding.state = null; binding.tick = null;
    };
    const closeAll = reason => { for (const binding of [...live]) close(binding, reason); };
    const intact = () => !ended && (!fetchInstalled || globalThis.fetch === wrappedFetch)
      && (!xhrInstalled || (xhrPrototype.send === wrappedSend && xhrPrototype.open === wrappedOpen));
    const owner = binding => {
      if (binding.closed) return false;
      if (!intact()) { const reason = ended ? 'documentEnded' : 'hookReplaced'; closeAll(reason); close(binding, reason); return false; }
      if (!sameIdentity(binding.identity, binding.op.identity) || binding.invocationID !== binding.op.invocationID
          || binding.state.operations.get(binding.identity.operationID) !== binding.op
          || !binding.state.observationIdentityValid()) { close(binding, 'identityInvalid'); return false; }
      return true;
    };
    const stamp = binding => {
      const sequence = binding.tick(), time = performance.now();
      if (!Number.isSafeInteger(sequence) || sequence < 1 || !Number.isFinite(time) || time < 0
          || sequence <= binding.lastSequence || time < binding.lastTime) { close(binding, 'invalidEvent'); return null; }
      binding.lastSequence = sequence; binding.lastTime = time;
      return {sequence, time};
    };
    const begin = (binding, transport) => {
      if (!binding || !owner(binding)) return null;
      if (binding.requests.length >= 8 || nextRequest >= Number.MAX_SAFE_INTEGER - 1) {
        close(binding, 'requestBound'); return null;
      }
      const event = stamp(binding); if (!event) return null;
      const record = {requestID: ++nextRequest, transport, requestSequence: event.sequence,
        requestedAtMS: event.time, terminal: null};
      binding.requests.push(record); live.add(binding);
      // A second call is recorded, not interpreted as safe retry or a new input.
      // Keep earlier facts, but stop claiming a continuous one-request observer.
      if (binding.requests.length > 1) close(binding, 'duplicateSend');
      return record;
    };
    const terminal = (binding, record, kind, status) => {
      if (!record || record.terminal !== null || !owner(binding)) return;
      if (status !== undefined && (!Number.isSafeInteger(status) || status < 0 || status > 599)) {
        close(binding, 'invalidEvent'); return;
      }
      const event = stamp(binding); if (!event) return;
      record.terminal = kind; record.terminalSequence = event.sequence; record.terminalAtMS = event.time;
      if (status !== undefined) record.status = status;
      try { cleaners.get(record)?.(); } catch {}
      if (binding.requests.every(item => item.terminal !== null)) live.delete(binding);
    };
    function wrappedFetch(input, init) {
      let binding, record;
      try {
        // Do not invoke a body getter twice or consume a Request/stream.
        const descriptor = init && Object.getOwnPropertyDescriptor(init, 'body');
        binding = descriptor && Object.prototype.hasOwnProperty.call(descriptor, 'value') ? files.get(descriptor.value) : null;
        record = begin(binding, 'fetch');
      } catch { /* Unsupported arguments preserve the original request. */ }
      let result;
      try { result = Reflect.apply(nativeFetch, this, arguments); }
      catch (error) { try { terminal(binding, record, 'threw'); } catch {} throw error; }
      // Do not attach then/catch: even a passive rejection handler changes the
      // application's unhandledrejection behavior. Fetch response/terminal stays
      // intentionally unobserved; only native call entry or synchronous throw is known.
      return result;
    }
    function wrappedOpen() {
      try { const prior = xhrs.get(this); if (prior) close(prior.binding, 'duplicateSend'); } catch {}
      return Reflect.apply(nativeOpen, this, arguments);
    }
    function wrappedSend(body) {
      let binding, record;
      try {
        binding = files.get(body); const prior = xhrs.get(this);
        if (prior) { close(prior.binding, 'duplicateSend'); if (binding) close(binding, 'duplicateSend'); }
        else if (binding) {
          record = begin(binding, 'xhr');
          if (record && !binding.closed) {
            xhrs.set(this, {binding, record});
            const listeners = [];
            const cleanup = () => {
              for (const [target, type, handler] of listeners.splice(0)) {
                try { target.removeEventListener(type, handler); } catch {}
              }
              binding.cleanups.delete(cleanup); cleaners.delete(record);
            };
            binding.cleanups.add(cleanup); cleaners.set(record, cleanup);
            const listen = (target, type, handler, once = false) => {
              if (typeof target?.addEventListener !== 'function' || typeof target?.removeEventListener !== 'function') throw Error('REQUEST_EVENTS_UNAVAILABLE');
              target.addEventListener(type, handler, {once}); listeners.push([target, type, handler]);
            };
            const finish = kind => () => {
              try { terminal(binding, record, kind, this.status); } catch { close(binding, 'invalidEvent'); }
            };
            listen(this, 'load', finish('response'), true);
            listen(this, 'error', finish('error'), true);
            listen(this, 'abort', finish('aborted'), true);
            listen(this, 'timeout', finish('timeout'), true);
            // Do not even access xhr.upload: adding an upload listener can
            // change CORS preflight behavior. No progress or START is inferred.
          }
        }
      } catch { if (binding) close(binding, 'invalidEvent'); }
      try { return Reflect.apply(nativeSend, this, arguments); }
      catch (error) { try { terminal(binding, record, 'threw'); } catch {} throw error; }
    }
    try {
      if (typeof nativeFetch === 'function' && fetchDescriptor.writable === true) {
        Object.defineProperty(globalThis, 'fetch', {...fetchDescriptor, value: wrappedFetch});
        fetchInstalled = globalThis.fetch === wrappedFetch;
      }
    } catch { /* Ordinary input does not depend on optional request facts. */ }
    try {
      if (typeof nativeSend === 'function' && typeof nativeOpen === 'function'
          && sendDescriptor.writable === true && openDescriptor.writable === true) {
        Object.defineProperty(xhrPrototype, 'send', {...sendDescriptor, value: wrappedSend});
        Object.defineProperty(xhrPrototype, 'open', {...openDescriptor, value: wrappedOpen});
        xhrInstalled = xhrPrototype.send === wrappedSend && xhrPrototype.open === wrappedOpen;
      }
    } catch {
      try { if (xhrPrototype.send === wrappedSend) Object.defineProperty(xhrPrototype, 'send', sendDescriptor); } catch {}
      try { if (xhrPrototype.open === wrappedOpen) Object.defineProperty(xhrPrototype, 'open', openDescriptor); } catch {}
    }
    const snapshot = binding => {
      if (!binding.closed) owner(binding);
      if (!binding.verified || !binding.requests.length || binding.op.inputCount !== 1
          || !sameIdentity(binding.identity, binding.op.identity) || binding.invocationID !== binding.op.invocationID) return null;
      return {version: 1, invocationID: binding.invocationID, inputCount: 1,
        inputSequence: binding.inputSequence, inputObservedAtMS: binding.inputObservedAtMS,
        fileSHA256: binding.identity.assetSHA256, coverage: 'exactOriginalFileOnly',
        observationClosed: binding.closed, closeReason: binding.reason,
        requests: binding.requests.map(record => ({...record}))};
    };
    const monitor = Object.freeze({
      bind(file, state, op) {
        const prior = operations.get(op);
        if (prior) { close(prior, 'reentry'); return; }
        if ((!fetchInstalled && !xhrInstalled) || !intact() || !uuid(op.invocationID)
            || !op.committed || op.inputSideEffectEntered !== false || op.inputCount !== 0) return;
        const binding = {op, state, tick: state.tick, identity: {...op.identity, target: {...op.identity.target}},
          invocationID: op.invocationID, byteCount: op.bytes, requests: [], verified: false,
          closed: false, reason: null, lastSequence: 0, lastTime: 0, cleanups: new Set()};
        operations.set(op, binding); files.set(file, binding);
        op.requestFactSnapshot = () => snapshot(binding);
        if (live.size >= MAX_ACTIVE_PAYLOADS) close(binding, 'requestBound'); else live.add(binding);
      },
      verified(file, op) {
        const binding = files.get(file);
        if (!binding || binding.op !== op || binding.verified || !op.fileHashVerified
            || op.inputCount !== 1 || op.file !== file || !sameIdentity(binding.identity, op.identity)
            || binding.invocationID !== op.invocationID || !Number.isSafeInteger(op.inputSequence)
            || op.inputSequence < 1 || !Number.isFinite(op.inputObservedAtMS) || op.inputObservedAtMS < 0) return;
        binding.verified = true; binding.inputSequence = op.inputSequence; binding.inputObservedAtMS = op.inputObservedAtMS;
      },
      completed(op) {
        const binding = operations.get(op);
        if (binding && owner(binding) && binding.verified && op.proof
            && sameIdentity(binding.identity, op.proof.identity) && binding.invocationID === op.invocationID) {
          // Exact completion has its own proof. Release request observation only:
          // neither a fetch terminal nor irreversible server retirement is known.
          close(binding, 'completionObserved');
        }
      },
      retire(op) { const binding = operations.get(op); if (binding) close(binding, 'identityInvalid'); }
    });
    registry.originalFileRequests = monitor;
    try { if (fetchInstalled || xhrInstalled) globalThis.addEventListener('pagehide', () => {
      ended = true; closeAll('documentEnded');
      try { if (fetchInstalled && globalThis.fetch === wrappedFetch) Object.defineProperty(globalThis, 'fetch', fetchDescriptor); } catch {}
      try { if (xhrInstalled && xhrPrototype.send === wrappedSend) Object.defineProperty(xhrPrototype, 'send', sendDescriptor); } catch {}
      try { if (xhrInstalled && xhrPrototype.open === wrappedOpen) Object.defineProperty(xhrPrototype, 'open', openDescriptor); } catch {}
    }, {once: true}); } catch { ended = true; closeAll('documentEnded'); }
    return monitor;
  }

  // Pure bounded reader of the observed current committed React ancestry.
  // No pendingProps, endpoint calls, DOM text extraction or alternate guessing.
  function readThreadBinding(form, home = false) {
    const keys = Object.keys(form).filter(k => k.startsWith('__reactFiber$'));
    if (keys.length !== 1) return null;
    const installed = Object.getOwnPropertyDescriptor(form, keys[0])?.value;
    const chains = [];
    for (const leaf of [installed, installed?.alternate]) {
      if (!leaf || leaf.stateNode !== form) continue;
      const chain = [], seen = new Set(); let node = leaf, valid = true;
      // The observed real thread has 373 ancestors; keep a finite 512-node cap.
      while (node && chain.length < 512 && !seen.has(node)) {
        seen.add(node); chain.push(node);
        const parent = node.return;
        if (!parent) break;
        let child = parent.child, member = false, siblings = new Set();
        while (child && siblings.size < 512 && !siblings.has(child)) {
          if (child === node) { member = true; break; }
          siblings.add(child); child = child.sibling;
        }
        if (!member) { valid = false; break; }
        node = parent;
      }
      const root = chain[chain.length - 1];
      if (valid && root && !root.return && root.tag === 3 && root.stateNode?.current === root) chains.push(chain);
    }
    if (chains.length !== 1) return null;
    const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
    let modeSeen = false, draftSeen = false, identity = null, profileID = null;
    for (const fiber of chains[0]) {
      const props = fiber.memoizedProps;
      if (!props || typeof props !== 'object') continue;
      const mode = ['conversationId', 'isHome', 'isWork', 'readOnly'].every(k => own(props, k));
      const draft = ['conversationId', 'draftKey', 'isWorkConversation', 'isTemporaryChat', 'readOnly', 'surfacePlacement'].every(k => own(props, k));
      if (!mode && !draft) continue;
      const id = props.conversationId;
      // Both exact forms were observed in current committed ordinary-thread props.
      // Preserve the full value; a local-to-persisted transition is a new binding.
      const format = typeof id === 'string' && /^(local-chatgpt:)?[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$/.exec(id);
      if (!format || (home && !format[1]) || (identity !== null && identity !== id)) return null;
      identity = id;
      profileID = format[1] ? 'chatgpt-composer-react-20261027-v1' : 'chatgpt-composer-react-persisted-20261027-v1';
      if (mode) {
        if (props.isHome !== home || props.isWork !== false || props.readOnly !== false) return null;
        modeSeen = true;
      }
      if (draft) {
        if (props.draftKey !== id || props.isWorkConversation !== false || props.isTemporaryChat !== false
            || props.readOnly !== false || props.surfacePlacement?.kind !== (home ? 'home' : 'thread')) return null;
        draftSeen = true;
      }
    }
    return modeSeen && draftSeen ? {logical: {profileID, id: identity},
      root: chains[0][chains[0].length - 1].stateNode} : null;
  }

  // This candidate instruments only the proven root's ordinary current writes.
  // It does not claim coverage of defineProperty bypass-and-restore or in-place
  // props mutations. No document text, React callback or DOM write is involved.
  function ownedRootMonitor(registry, root) {
    const previous = registry.rootMonitors.get(root);
    if (previous) {
      if (!previous.intact()) fail('ROOT_MONITOR_LOST');
      return previous;
    }
    if (registry.rootMonitors.size >= 4) fail('ROOT_MONITOR_LIMIT');
    const original = Object.getOwnPropertyDescriptor(root, 'current');
    if (!original || !Object.prototype.hasOwnProperty.call(original, 'value')
        || original.configurable !== true || original.writable !== true) fail('UNOBSERVED_ROOT_DESCRIPTOR');
    let value = original.value, alive = true, checking = false;
    const groups = new Map();
    const diagnostics = {commits: 0, checks: 0, elapsedMs: 0, maxElapsedMs: 0, stopped: false, restored: false, reason: null};
    const clock = () => { try { return performance.now(); } catch { return 0; } };
    const invalidateGroup = group => {
      if (!group.alive) return;
      group.alive = false;
      for (const invalidate of group.invalidate) { try { invalidate(); } catch {} }
    };
    const disqualify = reason => {
      alive = false; diagnostics.stopped = true; diagnostics.reason ||= reason;
      for (const group of groups.values()) invalidateGroup(group);
    };
    const get = function() { return value; };
    const set = function(next) {
      // React sees its new value even when our diagnostic fails or reenters.
      // Never restore an earlier tree or throw a diagnostic into React.
      value = next;
      if (!alive) return;
      const started = clock();
      diagnostics.commits++;
      if (checking) { disqualify('REENTRANT_COMMIT'); return; }
      checking = true;
      try {
        if (diagnostics.commits > 1000000) { disqualify('COMMIT_BOUND'); return; }
        for (const group of groups.values()) {
          if (!group.alive) continue;
          diagnostics.checks++;
          if (!group.check()) invalidateGroup(group);
          if (!alive) break;
        }
      } catch { disqualify('CHECK_FAILED'); }
      finally {
        checking = false;
        const elapsed = Math.max(0, clock() - started);
        diagnostics.elapsedMs += elapsed; diagnostics.maxElapsedMs = Math.max(diagnostics.maxElapsedMs, elapsed);
      }
    };
    const intact = () => {
      if (!alive) return false;
      const descriptor = Object.getOwnPropertyDescriptor(root, 'current');
      if (!descriptor || descriptor.get !== get || descriptor.set !== set
          || descriptor.configurable !== original.configurable || descriptor.enumerable !== original.enumerable) {
        disqualify('DESCRIPTOR_LOST'); return false;
      }
      return true;
    };
    const stop = () => {
      disqualify('EXPLICIT_STOP');
      const descriptor = Object.getOwnPropertyDescriptor(root, 'current');
      if (descriptor?.get === get && descriptor.set === set && descriptor.configurable === true) {
        try { Object.defineProperty(root, 'current', {...original, value}); diagnostics.restored = true; } catch {}
      }
      return {...diagnostics};
    };
    const monitor = {intact, stop, diagnostics, bind(form, editor, input, logical, route, check, invalidate) {
      if (!intact()) fail('ROOT_MONITOR_LOST');
      let group = groups.get(form);
      if (group?.alive && (group.editor !== editor || group.input !== input || group.route !== route || !sameLogical(group.logical, logical))) {
        invalidateGroup(group);
      }
      if (!group?.alive) {
        group = {alive: true, editor, input, logical, route, check, invalidate: new Set()}; groups.set(form, group);
      }
      group.invalidate.add(invalidate);
      return () => intact() && group.alive;
    }};
    // New monitors can release our own invalidated binding without touching a
    // historical descriptor or removing any original operation identity.
    monitor.release = (form, invalidate) => {
      const group = groups.get(form);
      if (!group) return;
      group.invalidate.delete(invalidate);
      if (group.invalidate.size === 0) groups.delete(form);
    };
    // A retained failed monitor is a tombstone: descriptor loss cannot rearm it.
    registry.rootMonitors.set(root, monitor);
    try { Object.defineProperty(root, 'current', {get, set, enumerable: original.enumerable, configurable: original.configurable}); }
    catch { disqualify('INSTALL_FAILED'); fail('ROOT_MONITOR_UNAVAILABLE'); }
    return monitor;
  }

  // Only the frozen v9/v10/v12 monitor protocols are compatible. This is defensive
  // same-world compatibility, not authentication against arbitrary page code.
  // Do not call any historical method until its data shape and function bodies
  // match our unchanged owned-monitor implementation.
  function rootMonitor(registry, root) {
    const previous = registry.rootMonitors.get(root);
    if (previous) {
      if (!previous.intact()) fail('ROOT_MONITOR_LOST');
      return previous;
    }
    if (registry.rootMonitors.size >= 4) fail('ROOT_MONITOR_LIMIT');
    const data = (object, key) => {
      const d = Object.getOwnPropertyDescriptor(object, key);
      return d && Object.prototype.hasOwnProperty.call(d, 'value') ? d.value : undefined;
    };
    const owners = () => {
      const found = [];
      for (const version of [7, 8, 9, 10, 11, 12]) {
        const descriptor = Object.getOwnPropertyDescriptor(globalThis, '__riftletWebAcceptance20261027v' + version);
        if (!descriptor) continue;
        if (!Object.prototype.hasOwnProperty.call(descriptor, 'value') || descriptor.configurable || descriptor.writable) fail('UNOBSERVED_ROOT_DESCRIPTOR');
        const old = descriptor.value, map = old && data(old, 'rootMonitors');
        if (!(map instanceof Map) || map.size > 4) fail('UNOBSERVED_ROOT_DESCRIPTOR');
        if (Map.prototype.has.call(map, root)) found.push({version, registry: old, map, monitor: Map.prototype.get.call(map, root)});
      }
      return found;
    };
    let candidates;
    try { candidates = owners(); } catch { fail('UNOBSERVED_ROOT_DESCRIPTOR'); }
    if (!candidates.length) return ownedRootMonitor(registry, root);
    if (candidates.length !== 1 || ![9, 10, 12].includes(candidates[0].version)) fail('UNOBSERVED_ROOT_DESCRIPTOR');
    const owner = candidates[0], monitor = owner.monitor;
    const count = data(owner.registry, 'count'), seen = new Set();
    let state = data(owner.registry, 'head'), tail = null;
    for (let i = 0; state && i < MAX_GENERATIONS; i++) {
      if (seen.has(state) || !data(state, 'form') || !(data(state, 'operations') instanceof Map)) fail('UNOBSERVED_ROOT_DESCRIPTOR');
      seen.add(state); tail = state; state = data(state, 'next');
    }
    if (state || !Number.isSafeInteger(count) || count < 1 || count !== seen.size
        || tail !== data(owner.registry, 'tail')) fail('UNOBSERVED_ROOT_DESCRIPTOR');
    const rootDescriptor = Object.getOwnPropertyDescriptor(root, 'current');
    // Produce reference function bodies on an isolated plain object only. No
    // page root, DOM, callbacks or old registry is altered by this comparison.
    const referenceRoot = {current: null}, reference = ownedRootMonitor({rootMonitors: new Map()}, referenceRoot);
    const referenceDescriptor = Object.getOwnPropertyDescriptor(referenceRoot, 'current');
    const functionSource = fn => typeof fn === 'function' ? Function.prototype.toString.call(fn) : null;
    const functions = {};
    for (const key of ['intact', 'bind', 'stop']) {
      functions[key] = monitor && data(monitor, key);
      if (functionSource(functions[key]) !== functionSource(reference[key])) fail('UNOBSERVED_ROOT_DESCRIPTOR');
    }
    if (!rootDescriptor || rootDescriptor.configurable !== true
        || functionSource(rootDescriptor.get) !== functionSource(referenceDescriptor.get)
        || functionSource(rootDescriptor.set) !== functionSource(referenceDescriptor.set)) fail('UNOBSERVED_ROOT_DESCRIPTOR');
    const ownerDiagnostics = data(monitor, 'diagnostics');
    if (!ownerDiagnostics || data(ownerDiagnostics, 'stopped') !== false || data(ownerDiagnostics, 'restored') !== false
        || data(ownerDiagnostics, 'reason') !== null) fail('ROOT_MONITOR_LOST');
    let active = true;
    const groups = new Map();
    const diagnostics = {borrowedFrom: owner.version, groups: 0, commits: 0, checks: 0, elapsedMs: 0, maxElapsedMs: 0, stopped: false, restored: false, reason: null};
    const invalidateGroup = group => {
      if (!group.alive) return;
      group.alive = false;
      for (const invalidate of group.invalidators) { try { invalidate(); } catch {} }
    };
    const disqualify = reason => {
      active = false; diagnostics.stopped = true; diagnostics.reason ||= reason;
      for (const group of groups.values()) invalidateGroup(group);
    };
    const intact = () => {
      if (!active) return false;
      try {
        const candidates = owners(), descriptor = Object.getOwnPropertyDescriptor(root, 'current');
        if (candidates.length !== 1 || candidates[0].registry !== owner.registry || candidates[0].map !== owner.map
            || candidates[0].monitor !== monitor || data(monitor, 'diagnostics') !== ownerDiagnostics
            || ['intact', 'bind', 'stop'].some(key => data(monitor, key) !== functions[key])
            || !descriptor || descriptor.get !== rootDescriptor.get || descriptor.set !== rootDescriptor.set
            || descriptor.configurable !== rootDescriptor.configurable || descriptor.enumerable !== rootDescriptor.enumerable
            || data(ownerDiagnostics, 'stopped') !== false || data(ownerDiagnostics, 'restored') !== false
            || data(ownerDiagnostics, 'reason') !== null || !functions.intact()) { disqualify('OWNER_LOST'); return false; }
        return true;
      } catch { disqualify('OWNER_LOST'); return false; }
    };
    const makeBorrowedCheck = group => () => {
      if (!active || !group.alive || !group.check) return false;
      try { diagnostics.checks++; return intact() && group.check(); }
      catch { invalidateGroup(group); return false; }
    };
    const makeBorrowedInvalidator = group => () => invalidateGroup(group);
    const borrowed = {intact, diagnostics, release(form, invalidate) {
      const group = groups.get(form);
      if (!group) return;
      group.invalidators.delete(invalidate);
      if (group.invalidators.size === 0) {
        group.alive = false; group.check = null; group.editor = null; group.input = null;
        groups.delete(form); diagnostics.groups = groups.size;
      }
    }, stop() { disqualify('EXPLICIT_STOP'); return {...diagnostics}; },
      bind(form, editor, input, logical, route, check, invalidate) {
        if (!intact()) fail('ROOT_MONITOR_LOST');
        let group = groups.get(form);
        if (group?.alive && (group.editor !== editor || group.input !== input || group.route !== route || !sameLogical(group.logical, logical))) invalidateGroup(group);
        if (!group?.alive) {
          if (!group && groups.size >= MAX_GENERATIONS) fail('ROOT_MONITOR_LIMIT');
          // Private per-form token prevents the old bind implementation from
          // reusing an old generation's check or changing its invalidators.
          const token = group?.token || {};
          group = {token, editor, input, logical, route, check, alive: true, invalidators: new Set()};
          groups.set(form, group); diagnostics.groups = groups.size;
          const currentGroup = group;
          // The historical owner retains only a plain token and a detachable
          // data cell, never our form/editor/input or install closure.
          const safeCheck = makeBorrowedCheck(currentGroup);
          try { group.ownerAlive = functions.bind(token, token, token, logical, route, safeCheck, makeBorrowedInvalidator(currentGroup)); }
          catch { invalidateGroup(group); fail('ROOT_MONITOR_LOST'); }
        }
        // Retired callbacks belong only to invalidated new states, whose operation
        // records remain in the registry. They cannot observe this binding again.
        for (const callback of group.invalidators) if (callback.retired === true) group.invalidators.delete(callback);
        if (group.invalidators.size >= MAX_GENERATIONS) fail('ROOT_MONITOR_LIMIT');
        group.invalidators.add(invalidate);
        return () => {
          try { return intact() && group.alive && group.ownerAlive(); }
          catch { invalidateGroup(group); return false; }
        };
      }};
    // Retain the local stopped wrapper as a tombstone; never restore the owner.
    registry.rootMonitors.set(root, borrowed);
    if (!intact()) fail('ROOT_MONITOR_LOST');
    return borrowed;
  }

  function retiredBinding(targets, operations, next, continuityEvents) {
    const no = () => false, noop = () => {};
    return {retired: true, target: targets[targets.length - 1],
      ownsTarget: candidate => targets.some(t => sameTarget(t, candidate)),
      operations, next, continuityEvents: {...continuityEvents},
      valid: no, observationIdentityValid: no, drain: noop, revokeInput: noop, invalidate: noop, markBad: noop, sample: noop};
  }

  function pageRoute() {
    // Route is a bounded candidate classification, never a draft identity.
    // Project-owned conversations may also use ordinary /c/ paths. Candidate
    // Project paths require the same committed Chat identity and exact nodes
    // below; the pathname alone never establishes a supported composer.
    const official = /^https:\/\/chatgpt\.com(\/[^?#]*)?(?:[?#].*)?$/.exec(location.href);
    const pathname = official && (official[1] || '/');
    const home = pathname === '/';
    const thread = /^\/c\/[^/]+\/?$/.test(pathname || '');
    const projectThread = /^\/g\/g-p-[A-Za-z0-9_-]+\/c\/[^/]+\/?$/.test(pathname || '');
    const projectHome = /^\/g\/g-p-[A-Za-z0-9_-]+\/project\/?$/.test(pathname || '');
    return {supported: !!official && (home || thread || projectThread || projectHome), home, projectHome};
  }
  function requirePageSurface() {
    if (!pageRoute().supported) fail('PAGE_ROUTE_UNSUPPORTED');
    if (globalThis.top !== globalThis) fail('PAGE_NOT_TOP_LEVEL');
    if (document.visibilityState !== 'visible') fail('PAGE_NOT_VISIBLE');
    if (!document.hasFocus()) fail('PAGE_UNFOCUSED');
  }
  function install(registry) {
    requirePageSurface();
    const {home, projectHome} = pageRoute();
    if (native.applicationID !== 'com.google.Chrome' || !native.sessionID
        || !/^\d+$/.test(native.windowID) || !/^\d+$/.test(native.tabID)) fail('NATIVE_CONTEXT_REQUIRED');
    const modeSelector = '[role=group][aria-label="撰写器模式"]';
    const homeFormSelector = 'form[data-chatgpt-composer][data-composer-placement=home][data-thread-find-composer=true]';
    // The modern Home surface has an independently observed committed local
    // business identity. Never fall back to legacy header proof if it conflicts.
    const businessHome = (home || projectHome) && document.querySelectorAll(homeFormSelector).length > 0;
    const threadFormSelector = businessHome ? homeFormSelector
      : 'form[data-chatgpt-composer][data-composer-placement=thread][data-thread-find-composer=true]';
    const threadEditorSelector = '[contenteditable=true][role=textbox][aria-label="询问 ChatGPT"]';
    let modeGroup = null, modeHeader = null, chatMode = null, workMode = null;
    let form, editor, logicalDraftIdentity, boundRoot = null, monitorAlive = null, modeMatches;
    if (home && !businessHome) {
      const modeGroups = [...document.querySelectorAll(modeSelector)];
      if (modeGroups.length !== 1 || !modeGroups[0].closest('header')) fail('UNPROVEN_CHAT_MODE');
      modeGroup = modeGroups[0]; modeHeader = modeGroup.closest('header');
      const buttons = [...modeGroup.querySelectorAll('button[type=button]')];
      const chats = buttons.filter(n => n.textContent.trim() === '聊天');
      const works = buttons.filter(n => n.textContent.trim() === '工作');
      if (buttons.length !== 2 || chats.length !== 1 || works.length !== 1) fail('UNPROVEN_CHAT_MODE');
      chatMode = chats[0]; workMode = works[0];
      modeMatches = () => {
        const groups = document.querySelectorAll(modeSelector), current = modeGroup.querySelectorAll('button[type=button]');
        return groups.length === 1 && groups[0] === modeGroup && modeGroup.isConnected && modeHeader.isConnected
          && modeGroup.closest('header') === modeHeader && chatMode.isConnected && workMode.isConnected
          && modeGroup.contains(chatMode) && modeGroup.contains(workMode)
          && current.length === 2 && [...current].includes(chatMode) && [...current].includes(workMode)
          && chatMode.textContent.trim() === '聊天' && workMode.textContent.trim() === '工作'
          && chatMode.getAttribute('aria-pressed') === 'true' && workMode.getAttribute('aria-pressed') === 'false';
      };
      const editors = [...document.querySelectorAll('[contenteditable=true][role=textbox]')];
      if (!editors.length) fail('EDITOR_UNAVAILABLE');
      if (editors.length !== 1) fail('AMBIGUOUS_COMPOSER');
      editor = editors[0]; form = editor.closest('form');
    } else {
      const forms = [...document.querySelectorAll(threadFormSelector)];
      if (!forms.length) fail('EDITOR_UNAVAILABLE');
      if (forms.length !== 1) fail('AMBIGUOUS_COMPOSER');
      form = forms[0];
      const editors = [...form.querySelectorAll(threadEditorSelector)];
      if (!editors.length) fail('EDITOR_UNAVAILABLE');
      if (editors.length !== 1) fail('AMBIGUOUS_COMPOSER');
      editor = editors[0];
      const allEditors = document.querySelectorAll('[contenteditable=true][role=textbox]');
      if (allEditors.length !== 1 || allEditors[0] !== editor) fail('AMBIGUOUS_COMPOSER');
      const binding = readThreadBinding(form, businessHome);
      if (!binding) fail('UNPROVEN_THREAD_IDENTITY');
      logicalDraftIdentity = binding.logical; boundRoot = binding.root;
      modeMatches = () => {
        const forms = document.querySelectorAll(threadFormSelector);
        const binding = readThreadBinding(form, businessHome);
        return forms.length === 1 && forms[0] === form && binding?.root === boundRoot
          && sameLogical(binding?.logical, logicalDraftIdentity) && (!monitorAlive || monitorAlive());
      };
    }
    if (!modeMatches()) fail('UNPROVEN_CHAT_MODE');
    const inputs = form ? [...form.querySelectorAll('input[type=file][aria-label="附加文件"]')] : [];
    if (!form) fail('EDITOR_UNAVAILABLE');
    if (inputs.length !== 1) fail('ATTACHMENT_INPUT_UNAVAILABLE');
    const input = inputs[0], route = location.href, documentID = crypto.randomUUID();
    // Focus belongs to the document, not necessarily its editor. The selected
    // composer must nevertheless be usable at capture and at the final input.
    const blockedAncestor = (node, includeHidden = true, includeDisabled = true) => {
      let depth = 0;
      for (let current = node; current?.nodeType === 1; current = current.parentElement) {
        if (++depth > 256) return true;
        if (current.inert || current.hasAttribute('inert')
            || (includeHidden && (current.hidden || current.hasAttribute('hidden') || current.getAttribute('aria-hidden') === 'true'))
            || (includeDisabled && current.getAttribute('aria-disabled') === 'true')) return true;
      }
      return false;
    };
    const rendered = node => {
      const style = getComputedStyle(node);
      return node.getClientRects().length > 0 && style.display !== 'none'
        && style.visibility !== 'hidden' && style.visibility !== 'collapse';
    };
    const composerRefusal = () => {
      try {
        if (!form.isConnected || !editor.isConnected
            || !editor.isContentEditable || blockedAncestor(form) || blockedAncestor(editor)
            || !rendered(form) || !rendered(editor)) return 'EDITOR_UNAVAILABLE';
        if (!input.isConnected || input.form !== form || input.disabled || input.matches(':disabled')
            || blockedAncestor(input, false)) return 'ATTACHMENT_INPUT_UNAVAILABLE';
        // A file input is commonly visually hidden by design. Do not require
        // that node to render or focus; only its original attachment capability.
        if ([...document.querySelectorAll(':modal')].some(node => !node.contains(form))) return 'EDITOR_UNAVAILABLE';
        const modals = document.querySelectorAll('[role=dialog][aria-modal=true],[role=alertdialog][aria-modal=true]');
        return [...modals].some(node => !node.contains(form) && !blockedAncestor(node, true, false) && rendered(node))
          ? 'EDITOR_UNAVAILABLE' : null;
      } catch { return 'EDITOR_UNAVAILABLE'; }
    };
    const composerAvailable = () => composerRefusal() === null;
    const refusal = composerRefusal();
    if (refusal) fail(refusal);
    // Reject a missing/lost monitor before registering any generation listeners.
    const monitor = boundRoot ? rootMonitor(registry, boundRoot) : null;
    const ids = new WeakMap(), operations = new Map(), clickPins = new Map(), issuedPinIDs = new Set();
    let nextNode = 0, invalid = false, inputRevoked = false, sequence = 0;
    // Initial discovery is always focused. A native mouse-down may reach this
    // page after its Window blur; that single focus-loss epoch can only bind
    // the previously captured exact target, never discover or renew one.
    let prePressFocusEpoch = 'focused';
    const retiredTargets = [];
    const listeners = [];
    const listen = (owner, type, handler, options) => { owner.addEventListener(type, handler, options); listeners.push([owner,type,handler,options]); };
    let stopObservation = () => {};
    let state = null;
    const nodeID = n => { if (!ids.has(n)) ids.set(n, 'node-' + (++nextNode)); return ids.get(n); };
    let target = {adapterID: 'chatgpt-web', surface: 'webChat', ...native,
      documentID, composerID: nodeID(editor) + ':' + nodeID(form), draftGeneration: crypto.randomUUID(),
      ...(logicalDraftIdentity ? {logicalDraftIdentity} : {})};
    // Existing attachments are never read beyond node membership or changed.
    // If an original card disappears, conservatively invalidate this draft lease.
    const baseline = [...form.querySelectorAll('[role=button][aria-label]')].filter(c => c.querySelector('img'));
    const identitySnapshotValid = () => {
      const currentEditors = document.querySelectorAll('[contenteditable=true][role=textbox]');
      const currentInputs = form.querySelectorAll('input[type=file][aria-label="附加文件"]');
      return !invalid && modeMatches() && location.href === route && form.isConnected && editor.isConnected
        && input.isConnected && input.form === form && editor.closest('form') === form && form.contains(input)
        && currentEditors.length === 1 && currentEditors[0] === editor
        && currentInputs.length === 1 && currentInputs[0] === input
        && baseline.every(c => c.isConnected && form.contains(c));
    };
    const tick = () => { if (++sequence > Number.MAX_SAFE_INTEGER - 1) invalid = true; return sequence; };
    // Native selection and executing input are different resources. A retained
    // selection may be reused only when its exact File belongs to a normally
    // returned one-shot input and an independently observed original attachment
    // START. No filename-only match, clock, clear, prior-file replay or completion is
    // used to grant this capability. Application append semantics remain a
    // separately verified platform contract, not a claim about arbitrary apps.
    const preparedResources = new Map();
    const preparedResourceOperations = new Set();
    const filesDescriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'files');
    const valueDescriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
    const uuid = value => typeof value === 'string' && /^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$/.test(value);
    const data = (object, key) => {
      const descriptor = object && Object.getOwnPropertyDescriptor(object, key);
      return descriptor && Object.prototype.hasOwnProperty.call(descriptor, 'value') ? descriptor.value : undefined;
    };
    let lastResourceRefusal = null;
    let pendingSelectionQualification = null;
    for (const key of ['settledNativeSelections','nativeSelectionDigests']) {
      if (!Object.getOwnPropertyDescriptor(registry,key)) {
        Object.defineProperty(registry,key,{value:new WeakMap(),writable:false,configurable:false});
      }
    }
    if (!Object.getOwnPropertyDescriptor(registry,'nativeSelectionReads')) {
      Object.defineProperty(registry,'nativeSelectionReads',{value:new Set(),writable:false,configurable:false});
    }
    const nativeInputSelection = () => {
      try {
        const filesNow = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'files');
        const valueNow = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
        // React may track value with an own accessor. It is never consulted or
        // written here: the original native getter establishes emptiness. An
        // own files property is different because application change listeners
        // would read that shadow instead of the native FileList we submit.
        if (Object.getOwnPropertyDescriptor(input, 'files')
            || typeof filesDescriptor?.get !== 'function' || typeof filesDescriptor?.set !== 'function'
            || typeof valueDescriptor?.get !== 'function' || filesNow?.get !== filesDescriptor.get
            || filesNow?.set !== filesDescriptor.set || valueNow?.get !== valueDescriptor.get) {
          return {reason:'INPUT_RESOURCE_NATIVE_ACCESS_UNVERIFIED'};
        }
        const files = Reflect.apply(filesDescriptor.get, input, []);
        const value = Reflect.apply(valueDescriptor.get, input, []);
        if (!files || !Number.isSafeInteger(files.length) || files.length < 0 || typeof value !== 'string') {
          return {reason:'INPUT_RESOURCE_NATIVE_ACCESS_UNVERIFIED'};
        }
        if (files.length === 0) return value === '' ? {kind:'emptyNativeFileInput',file:null}
          : {reason:'INPUT_RESOURCE_NATIVE_VALUE_NONEMPTY'};
        if (files.length !== 1 || !files[0] || value === '') return {reason:'INPUT_RESOURCE_NATIVE_FILES_RETAINED'};
        return {kind:'settledOwnedNativeFileInput',file:files[0]};
      } catch { return {reason:'INPUT_RESOURCE_NATIVE_ACCESS_UNVERIFIED'}; }
    };
    const inputExecutionStatus = (currentOperation, selectedFile) => {
      try {
        // Old native calls can outlive the App. Inspect the source-owned page
        // executions by actual input-node identity, not a renewed target UUID.
        // A settled old one-shot execution needs no newer request fields.
        const selectedOwners = [], contentCandidates = [];
        const selections = data(registry,'settledNativeSelections');
        if (!(selections instanceof WeakMap)) return {reason:'INPUT_RESOURCE_REGISTRY_UNVERIFIED'};
        const settledSelection = selectedFile && WeakMap.prototype.get.call(selections,selectedFile);
        for (const version of [7, 8, 9, 10, 11, 12, 13]) {
          const descriptor = Object.getOwnPropertyDescriptor(globalThis, '__riftletWebAcceptance20261027v' + version);
          if (!descriptor) continue;
          if (!Object.prototype.hasOwnProperty.call(descriptor, 'value') || descriptor.configurable || descriptor.writable) return {reason:'INPUT_RESOURCE_REGISTRY_UNVERIFIED'};
          const ownerRegistry = descriptor.value, inputOwners = data(ownerRegistry, 'inputOwners');
          if (inputOwners !== undefined) {
            if (!(inputOwners instanceof WeakMap)) return {reason:'INPUT_RESOURCE_REGISTRY_UNVERIFIED'};
            const owner = WeakMap.prototype.get.call(inputOwners, input);
            if (owner && owner !== currentOperation) return {reason:'INPUT_RESOURCE_EXECUTION_BUSY'};
          }
          const seen = new Set(); let generation = data(ownerRegistry, 'head');
          if (!generation && data(ownerRegistry, 'count') !== 0) return {reason:'INPUT_RESOURCE_REGISTRY_UNVERIFIED'};
          while (generation) {
            if (seen.size >= 512 || seen.has(generation)) return {reason:'INPUT_RESOURCE_REGISTRY_UNVERIFIED'};
            seen.add(generation);
            const operations = data(generation, 'operations');
            if (!(operations instanceof Map)) return {reason:'INPUT_RESOURCE_REGISTRY_UNVERIFIED'};
            const retired = data(generation, 'retired') === true, originalInput = data(generation, 'input');
            if (!retired && !originalInput) return {reason:'INPUT_RESOURCE_REGISTRY_UNVERIFIED'};
            if (originalInput === input) for (const operation of Map.prototype.values.call(operations)) {
              if (operation === currentOperation) continue;
              if (selectedFile && (data(operation,'file') === selectedFile
                  || (settledSelection?.operation === operation && settledSelection.state === generation
                    && settledSelection.input === input && sameIdentity(settledSelection.identity,operation.identity)))) {
                selectedOwners.push({state:generation,operation});
              } else if (selectedFile && data(operation,'file') === null
                  && selectedFile.type === 'image/png' && selectedFile.size === data(operation,'bytes')
                  && selectedFile.size >= 8 && selectedFile.size <= MAX_BYTES
                  && uuid(data(operation,'identity')?.operationID)
                  && data(operation,'name') === 'riftlet-' + operation.identity.operationID + '.png'
                  && selectedFile.name === data(operation,'name')) {
                // Historical observers released their original File after a
                // completion attempt. Name/size only locate a candidate; they
                // never grant input without the separate immutable-byte digest.
                contentCandidates.push({state:generation,operation});
              }
              // finally settling is not evidence that a throwing setter/change
              // returned normally. Keep that ambiguity exclusive even if a
              // handler happened to reset the picker before it threw.
              if (data(operation,'inputSideEffectEntered') === true
                  && (!Number.isSafeInteger(data(operation,'callSettledSequence'))
                    || data(operation,'callSettledSequence') <= data(operation,'inputSequence'))) {
                return {reason:data(operation,'expectingInput') === true
                  ? 'INPUT_RESOURCE_EXECUTION_BUSY' : 'INPUT_RESOURCE_EXECUTION_UNCERTAIN'};
              }
              if (data(operation, 'commitWorkSettled') === true) continue;
              if (data(operation, 'committed') !== true) {
                if (data(operation, 'invalid') !== true) return {reason:'INPUT_RESOURCE_GENERATION_BUSY'};
              } else if (!(data(operation, 'inputCount') === 1 && data(operation, 'expectingInput') === false)) return {reason:'INPUT_RESOURCE_GENERATION_BUSY'};
            }
            generation = data(generation, 'next');
          }
        }
        if (selectedFile) {
          const candidates = selectedOwners.length ? selectedOwners : contentCandidates;
          if (candidates.length === 0) return {reason:'INPUT_RESOURCE_NATIVE_FILES_RETAINED'};
          if (candidates.length !== 1) return {reason:'INPUT_RESOURCE_PRIOR_ATTACHMENT_UNPROVEN'};
          const {state:ownerState,operation:op} = candidates[0];
          // The old input lease may have been focus-revoked or renewed. Its
          // original observation/card membership, not its old input authority,
          // proves the attachment still belongs to this same composer.
          ownerState.drain?.();
          if (ownerState.input !== input || ownerState.form !== form
              || !sameLogical(op.identity.target.logicalDraftIdentity,logicalDraftIdentity)
              || typeof ownerState.currentMember !== 'function' || !ownerState.currentMember(op)
              || op.commitWorkSettled !== true || op.inputSideEffectEntered !== true || op.expectingInput !== false
              || op.inputCount !== 1 || !op.fileHashVerified || !uuid(op.inputOwnershipID)
              || !Number.isSafeInteger(op.callSettledSequence) || op.callSettledSequence <= op.inputSequence
              || !op.uploadStart || op.uploadStart.inputCount !== 1
              || op.uploadStart.inputSequence !== op.inputSequence || op.uploadStart.startSequence <= op.inputSequence) {
            return {reason:'INPUT_RESOURCE_PRIOR_ATTACHMENT_UNPROVEN'};
          }
          if (!selectedOwners.length) return {reason:'INPUT_RESOURCE_QUALIFICATION_PENDING',
            qualification:{state:ownerState,operation:op,file:selectedFile}};
        }
        return {reason:null};
      } catch { return {reason:'INPUT_RESOURCE_REGISTRY_UNVERIFIED'}; }
    };
    const attachmentSnapshot = () => [...form.querySelectorAll('[role=button][aria-label]')].map(card => ({
      card, label: card.getAttribute('aria-label'), images: [...card.querySelectorAll('img')].map(image => ({image, alt: image.alt}))
    }));
    const attachmentsIntact = attachments => attachments.every(({card, label, images}) => card.isConnected
      && form.contains(card) && card.getAttribute('aria-label') === label
      && images.every(({image, alt}) => image.isConnected && card.contains(image) && image.alt === alt));
    const editorSnapshot = () => {
      const selection = document.getSelection();
      return {text: editor.textContent, selection: selection ? {anchorNode:selection.anchorNode, anchorOffset:selection.anchorOffset,
        focusNode:selection.focusNode, focusOffset:selection.focusOffset, rangeCount:selection.rangeCount, isCollapsed:selection.isCollapsed} : null,
        activeElement:document.activeElement};
    };
    const editorIntact = before => {
      const now = editorSnapshot();
      return now.text === before.text && now.activeElement === before.activeElement && (before.selection === null ? now.selection === null
        : now.selection !== null && Object.keys(before.selection).every(key => now.selection[key] === before.selection[key]));
    };
    const currentResourceStatus = (operation = null) => {
      const selection = nativeInputSelection();
      if (selection.reason) return selection;
      const execution = inputExecutionStatus(operation,selection.file);
      return execution.reason ? execution : selection;
    };
    const qualifyRetainedSelection = (identity,invocationID,candidate) => {
      const {state:ownerState,operation:op,file} = candidate;
      let pending = pendingSelectionQualification;
      if (pending?.status === 'failed' && sameIdentity(pending.identity,identity) && pending.invocationID === invocationID) {
        lastResourceRefusal=pending.reason;fail(pending.reason);
      }
      if (pending && (!sameIdentity(pending.identity,identity) || pending.invocationID !== invocationID
          || pending.file !== file || pending.ownerState !== ownerState || pending.operation !== op)) {
        // Only unused read-only work can be superseded. Its completion cannot
        // create a reservation, schedule input or publish an old qualification.
        pending.cancelled = true; preparedResourceOperations.add(pending.identity.operationID);
        pendingSelectionQualification = null; pending = null;
      }
      if (!pending) {
        const jobs=data(registry,'nativeSelectionDigests'),reads=data(registry,'nativeSelectionReads');
        if (!(jobs instanceof WeakMap) || !(reads instanceof Set)) fail('INPUT_RESOURCE_REGISTRY_UNVERIFIED');
        let job=jobs.get(file);
        if (!job) {
          if (reads.size >= MAX_ACTIVE_PAYLOADS) fail('INPUT_RESOURCE_QUALIFICATION_PENDING');
          job={status:'pending',digest:null};jobs.set(file,job);reads.add(job);
          // One bounded read per immutable native File, shared by superseding
          // read-only qualifications. Never read request bodies or chat content.
          job.promise=Promise.resolve().then(()=>file.arrayBuffer()).then(bytes=>{
            if (bytes.byteLength !== file.size || bytes.byteLength > MAX_BYTES) fail('INPUT_RESOURCE_QUALIFICATION_FAILED');
            return hash(bytes);
          }).then(digest=>{job.digest=digest;job.status='ready';})
            .catch(()=>{job.status='failed';}).finally(()=>{reads.delete(job);});
        }
        pending={identity:{...identity,target:{...identity.target}},invocationID,file,ownerState,operation:op,
          originalIdentity:{...op.identity,target:{...op.identity.target}},cancelled:false,status:'pending',reason:null};
        pendingSelectionQualification=pending;
        // A previous unused reservation must not survive a newer explicit click
        // while its selection is being checked. Already claimed tokens stay.
        for (const [id,prior] of preparedResources) if (!prior.claimed) preparedResources.delete(id);
        job.promise.then(()=>{
          if (pending.cancelled || pendingSelectionQualification !== pending) return;
          const refuse=reason=>{pending.status='failed';pending.reason=reason;
            pending.file=null;pending.ownerState=null;pending.operation=null;};
          if (job.status !== 'ready' || job.digest !== pending.originalIdentity.assetSHA256) {
            refuse('INPUT_RESOURCE_QUALIFICATION_FAILED');return;
          }
          drain();ownerState.drain?.();
          if (!validFor(pending.identity.target) || !contextMatches(pending.identity.target)
              || !sameIdentity(pending.originalIdentity,op.identity)) {refuse('INPUT_RESOURCE_TARGET_CHANGED');return;}
          const current=nativeInputSelection();
          if (current.reason) {refuse(current.reason);return;}
          if (current.file !== file) {refuse('INPUT_RESOURCE_NATIVE_FILES_RETAINED');return;}
          const execution=inputExecutionStatus(null,file);
          if (execution.reason !== 'INPUT_RESOURCE_QUALIFICATION_PENDING'
              || execution.qualification?.state !== ownerState || execution.qualification?.operation !== op) {
            refuse(execution.reason || 'INPUT_RESOURCE_PRIOR_ATTACHMENT_UNPROVEN');return;
          }
          const selections=data(registry,'settledNativeSelections');
          if (!(selections instanceof WeakMap)) {refuse('INPUT_RESOURCE_REGISTRY_UNVERIFIED');return;}
          // This is content re-identification of the CURRENT immutable native
          // File, not a claim to have recovered a lost original object identity.
          selections.set(file,{state:ownerState,operation:op,input,identity:pending.originalIdentity,
            qualification:'currentSelectionHashMatchesOriginalOperation'});
          pending.status='ready';
        }).catch(()=>{if(!pending.cancelled){pending.status='failed';pending.reason='INPUT_RESOURCE_QUALIFICATION_FAILED';
          pending.file=null;pending.ownerState=null;pending.operation=null;}});
      }
      if (pending.status === 'failed') {lastResourceRefusal=pending.reason;fail(pending.reason);}
      return {version:1,identity:{...identity,target:{...identity.target}},invocationID,pending:true};
    };
    const resourceAvailable = (resource, operation = null) => {
      let reason = !resource || resource.invalid ? 'INPUT_RESOURCE_RESERVATION_BUSY'
        : !sameTarget(resource.identity.target, operation?.identity.target || resource.identity.target)
          || !observationIdentityValid() || !composerAvailable() ? 'INPUT_RESOURCE_TARGET_CHANGED' : null;
      if (!reason) {
        const status = currentResourceStatus(operation);
        reason = status.reason || (status.file && status.file !== resource.selectedFile ? 'INPUT_RESOURCE_NATIVE_FILES_RETAINED' : null);
      }
      if (!reason && !attachmentsIntact(resource.attachments)) reason = 'INPUT_RESOURCE_BASELINE_CHANGED';
      lastResourceRefusal = reason;
      if (operation && reason) operation.resourceRefusalReason = reason;
      return !reason;
    };
    const prepareInputResource = (identity, invocationID) => {
      if (!uuid(identity?.operationID) || !uuid(identity.assetID) || !uuid(invocationID)
          || !Number.isSafeInteger(identity.attempt) || identity.attempt < 1
          || !/^[a-f0-9]{64}$/.test(identity.assetSHA256)) fail('INPUT_RESOURCE_UNAVAILABLE');
      if (preparedResourceOperations.has(identity.operationID)) fail('INPUT_RESOURCE_RESERVATION_BUSY');
      const selection = currentResourceStatus();
      if (selection.qualification) return qualifyRetainedSelection(identity,invocationID,selection.qualification);
      if (selection.reason) { lastResourceRefusal = selection.reason; fail(selection.reason); }
      if (pendingSelectionQualification) {
        if (!sameIdentity(pendingSelectionQualification.identity,identity)
            || pendingSelectionQualification.invocationID !== invocationID) {
          preparedResourceOperations.add(pendingSelectionQualification.identity.operationID);
        }
        pendingSelectionQualification.cancelled=true;pendingSelectionQualification=null;
      }
      const resource = {identity:{...identity,target:{...identity.target}}, invocationID, resourceID:crypto.randomUUID(),
        selectedFile:selection.file, attachments:attachmentSnapshot(), claimed:false, invalid:false};
      if (!resourceAvailable(resource)) fail(lastResourceRefusal);
      // A lost preparation reply is not an input. A new explicit operation may
      // supersede those unused tokens; their later BEGIN can no longer claim
      // them. This never retires staged/committed input, and no clock is used.
      for (const [id, prior] of preparedResources) if (!prior.claimed) preparedResources.delete(id);
      preparedResourceOperations.add(identity.operationID);
      preparedResources.set(resource.resourceID, resource);
      return {version:1, identity:resource.identity, invocationID, resourceID:resource.resourceID,
        inputElementID:documentID + ':' + nodeID(input), kind:selection.kind,
        observedSequence:tick(), baselineAttachmentCount:resource.attachments.length};
    };
    const claimInputResource = (identity, invocationID, resourceID) => {
      const resource = preparedResources.get(resourceID);
      if (!resource || resource.claimed || !sameIdentity(resource.identity,identity)
          || resource.invocationID !== invocationID) { lastResourceRefusal='INPUT_RESOURCE_RESERVATION_BUSY'; return null; }
      if (!resourceAvailable(resource)) return null;
      resource.claimed = true; return resource;
    };
    const releaseInputResource = (identity, invocationID, resourceID) => {
      const resource = preparedResources.get(resourceID);
      if (!resource || resource.claimed || !sameIdentity(resource.identity,identity) || resource.invocationID !== invocationID) return false;
      preparedResources.delete(resourceID); return true;
    };
    const enterInputResource = op => {
      const resource = op.inputResource;
      if (!resource || !resource.claimed || !sameIdentity(resource.identity,op.identity)
          || resource.invocationID !== op.invocationID) {
        op.resourceRefusalReason='INPUT_RESOURCE_RESERVATION_BUSY'; return false;
      }
      if (!resourceAvailable(resource,op)) return false;
      // Include attachments added after reservation; copy only local node
      // identities. Text/selection are compared within this synchronous input,
      // so typing normally between preparation and commit is not rejected.
      resource.attachments = attachmentSnapshot();
      resource.editor = editorSnapshot();
      op.preservedAttachments = resource.attachments;
      preparedResources.delete(resource.resourceID);
      return true;
    };
    const forgetInputResource = op => {
      if (!op.inputResource) return;
      preparedResources.delete(op.inputResource.resourceID);
      op.inputResource.editor = null; op.inputResource = null;
    };
    const revokeInput = (reason = 'other') => {
      if (reason === 'windowBlur' && prePressFocusEpoch === 'focused') prePressFocusEpoch = 'blurred';
      else if (reason !== 'windowBlur') prePressFocusEpoch = 'closed';
      inputRevoked = true;
      for (const op of operations.values()) if (!op.committed && !op.identity.target.clickBindingID) { op.file = null; op.chunks = []; op.invalid = true; }
    };
    const invalidate = () => {
      if (invalid) return;
      invalid = true; invalidate.retired = true; revokeInput(); tick(); stopObservation();
      preparedResources.clear();
      if (pendingSelectionQualification) {pendingSelectionQualification.cancelled=true;pendingSelectionQualification=null;}
      const audit = new Map();
      for (const [id, op] of operations) {
        try { registry.originalFileRequests?.retire(op); } catch {}
        const record = {};
        for (const key of ['identity','invocationID','name','bytes','nextChunk','received','committed',
          'error','inputCount','fileHashVerified','inputSequence','inputObservedAtMS','progressValue',
          'startDisqualified','uploadStart','started','hundred','ended','loaded','uploading','errorAttachmentID']) {
          if (op[key] !== undefined) record[key] = op[key];
        }
        record.invalid = true;
        if (op.proof) record.proofAudit = {identity:op.proof.identity, loadSequence:op.proof.loadSequence,
          completed:op.proof.completed, completedAtMS:op.proof.completedAtMS};
        if (op.card && op.image) record.lastAttachmentID = op.identity.target.documentID + ':' + nodeID(op.card) + ':' + nodeID(op.image);
        audit.set(id, record);
        op.file = null; op.chunks = []; op.proof = null;
        op.card = null; op.image = null; op.progressNode = null;
      }
      monitor?.release?.(form, invalidate);
      if (state) {
        const retired = retiredBinding([...retiredTargets,target,...[...clickPins.values()].map(p=>p.target)], audit, state.next, continuityEvents);
        for (const key of Object.keys(state)) delete state[key];
        Object.assign(state, retired);
      }
    };
    const observationIdentityValid = () => {
      if (!identitySnapshotValid()) { if (!invalid) invalidate(); return false; }
      return true;
    };
    const valid = () => {
      if (!observationIdentityValid() || inputRevoked) return false;
      if (!composerAvailable()) { revokeInput(); return false; }
      return globalThis.top === globalThis && document.visibilityState === 'visible' && document.hasFocus();
    };
    // Only a foreground native press can issue a capability. Later commands
    // must present this exact target; hidden state is not a change of draft.
    const pinTarget = (id, nativePressProof) => {
      if (!/^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$/.test(id || '')
          || issuedPinIDs.has(id)) fail('CLICK_PIN_REFUSED');
      if (!pageRoute().supported) { invalidate(); fail('PAGE_ROUTE_UNSUPPORTED'); }
      if (globalThis.top !== globalThis) { revokeInput('frame'); fail('PAGE_NOT_TOP_LEVEL'); }
      if (document.visibilityState !== 'visible') { revokeInput('visibility'); fail('PAGE_NOT_VISIBLE'); }
      const unavailable = composerRefusal();
      if (unavailable) { revokeInput('availability'); fail(unavailable); }
      if (!observationIdentityValid()) fail('CLICK_PIN_REFUSED');
      // This closed proof is emitted only by the synchronous native pinner
      // after verifying the original press timestamp, pre-press receipt, and
      // unchanged foreground process/window/selected tab. It is not accepted
      // by native capture or asynchronous adapter execution. No elapsed dwell
      // time can grant it; each press still owns its own one-use bounded pin.
      const attestedPress = nativePressProof?.kind === 'observed-target-before-press'
        && nativePressProof.clickBindingID === id;
      const focused = valid();
      const focusOnlyPress = attestedPress && prePressFocusEpoch !== 'closed' && !document.hasFocus()
        && observationIdentityValid() && composerAvailable();
      if (!focused && !focusOnlyPress) fail(!document.hasFocus() && prePressFocusEpoch !== 'closed'
        ? 'PAGE_UNFOCUSED' : 'CLICK_PIN_REFUSED');
      const now = performance.now();
      for (const [key,pin] of clickPins) if (!pin.operationID && pin.deadline <= now) clickPins.delete(key);
      if ([...clickPins.values()].filter(p => !p.operationID && p.deadline > now).length >= 16) fail('CLICK_PIN_LIMIT');
      const pinned = {...target, clickBindingID:id};
      issuedPinIDs.add(id);
      clickPins.set(id, {target:pinned, deadline:now+30000, operationID:null});
      return pinned;
    };
    const ownsPin = candidate => !!candidate?.clickBindingID && sameTarget(clickPins.get(candidate.clickBindingID)?.target, candidate);
    const validFor = candidate => candidate?.clickBindingID
      ? ownsPin(candidate) && (clickPins.get(candidate.clickBindingID).operationID || performance.now() < clickPins.get(candidate.clickBindingID).deadline)
        && observationIdentityValid() && composerAvailable()
      : sameTarget(candidate, target) && valid();
    const claimPin = identity => {
      if (!identity.target.clickBindingID) return;
      const pin = clickPins.get(identity.target.clickBindingID);
      if (!pin || !sameTarget(pin.target, identity.target) || pin.operationID || performance.now() >= pin.deadline) fail('CLICK_PIN_SPENT');
      pin.operationID = identity.operationID;
    };
    // A focus-only revocation need not consume another retained operation slot.
    // Renew only a continuously observed binding; original operation leases stay read-only. The old target object
    // is never changed or re-authorized, and native capture still must publish a
    // fresh ACK before a later click. Retained operations keep immutable original targets.
    const renewEmptyInputLease = () => {
      if (!inputRevoked || invalid || !observationIdentityValid()
          || !composerAvailable() || document.visibilityState !== 'visible' || !document.hasFocus()) return false;
      if (operations.size) retiredTargets.push(target);
      target = {...target, documentID: crypto.randomUUID(), draftGeneration: crypto.randomUUID()};
      inputRevoked = false;
      prePressFocusEpoch = 'focused';
      return true;
    };
    const markBad = (op, error = false, reason = 'attachmentIdentityChanged') => {
      // Preserve a previously proved, still-bound attachment's identity when its
      // own card/image reports a late error. Navigation, node replacement and
      // generic invalidation are not failure evidence and cannot mint this ID.
      if (error && op.proof && currentMember(op)
          && op.proof.card === op.card && op.proof.image === op.image
          && sameIdentity(op.proof.identity, op.identity)) {
        op.errorAttachmentID = op.identity.target.documentID + ':' + nodeID(op.card) + ':' + nodeID(op.image);
      }
      op.invalid = true; op.error ||= error; op.reason ||= error ? 'attachmentError' : reason;
      op.proof = null; op.file = null; op.chunks = [];
      op.preservedAttachments = null;
      // Detached attachment nodes cannot later prove this operation. Keep the
      // immutable identity/start/error audit, release detached preview payloads.
      if (!op.card?.isConnected || !form.contains(op.card)) { op.card = null; op.image = null; op.progressNode = null; }
    };
    const ownCards = name => [...form.querySelectorAll('[role=button][aria-label]')]
      .filter(c => c.getAttribute('aria-label') === name);
    const currentSource = image => image.currentSrc || image.src;
    const currentMember = op => observationIdentityValid() && !op.invalid && op.card?.isConnected && form.contains(op.card)
      && op.image?.isConnected && op.image.closest('[role=button]') === op.card
      && op.card.getAttribute('aria-label') === op.name && op.image.alt === op.name
      && ownCards(op.name).length === 1;
    // This is a browser-observed original request body, not a server task/file
    // identifier. The native profile separately admits the platform's observed
    // append semantics. A File reference, change return or card by itself never
    // produces continuation. No completion or retry authority is granted here.
    const continuationFor = (op, facts) => {
      if (!currentMember(op) || !op.uploadStart || op.startDisqualified || op.error
          || !op.uploading || op.ended || op.proof || op.inputCount !== 1 || !op.fileHashVerified
          || op.commitWorkSettled !== true || !op.inputOwnershipID
          || !Number.isSafeInteger(op.callSettledSequence) || op.callSettledSequence <= op.inputSequence
          || !facts || facts.observationClosed || facts.requests.length !== 1
          || facts.invocationID !== op.invocationID || facts.inputSequence !== op.inputSequence
          || facts.fileSHA256 !== op.identity.assetSHA256) return null;
      const request = facts.requests[0];
      if (!Number.isSafeInteger(request.requestID) || request.requestID < 1
          || !['xhr','fetch'].includes(request.transport)
          || !Number.isSafeInteger(request.requestSequence) || request.requestSequence <= op.inputSequence
          || request.requestSequence >= op.uploadStart.startSequence
          || (request.terminal !== null && request.terminal !== 'response')) return null;
      if (!op.inputIsolationProof) {
        op.inputIsolationProof = {version: 1, evidenceID: crypto.randomUUID(),
          binding: {version: 1, ...op.identity, target: {...op.identity.target}, invocationID: op.invocationID,
            attachmentID: op.identity.target.documentID + ':' + nodeID(op.card) + ':' + nodeID(op.image)},
          inputIsolation: {version: 1, ownershipID: op.inputOwnershipID,
            inputElementID: documentID + ':' + nodeID(input), kind: 'originalRequestBodyOwned',
            requestID: request.requestID, requestSequence: request.requestSequence, requestTransport: request.transport,
            originalSHA256: facts.fileSHA256, originalByteCount: op.bytes,
            startEvidenceID: op.uploadStart.evidenceID, inputSequence: op.inputSequence,
            callSettledSequence: op.callSettledSequence, startSequence: op.uploadStart.startSequence,
            observedSequence: tick()}};
      }
      const proof = op.inputIsolationProof;
      return sameIdentity(proof.binding, op.identity) && proof.binding.invocationID === op.invocationID
        && proof.inputIsolation.requestID === request.requestID
        && proof.inputIsolation.requestSequence === request.requestSequence
        ? {...proof, inputIsolation: {...proof.inputIsolation, observedSequence: tick()}} : null;
    };
    const associatedError = card => {
      const refs = [card, ...card.querySelectorAll('[aria-describedby],[aria-labelledby]')]
        .flatMap(e => ['aria-describedby', 'aria-labelledby'].flatMap(k => (e.getAttribute(k) || '').split(/\s+/).filter(Boolean)))
        .map(id => document.getElementById(id)).filter(Boolean);
      const nodes = [card, ...card.querySelectorAll('[role=alert],[data-state],[aria-label]'), ...refs];
      return nodes.some(n => n.getAttribute('role') === 'alert' || /error|failed/i.test(n.getAttribute('data-state') || '')
        || /上传失败|重试|Upload failed|Retry/i.test(n.getAttribute('aria-label') || '')
        || /上传失败|Upload failed/i.test(n.textContent || ''));
    };

    async function pixels(image, expected = null) {
      const width = image.naturalWidth, height = image.naturalHeight;
      if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width < 1 || height < 1
          || width * height > MAX_PIXELS) fail('UNSUPPORTED_PIXEL_SIZE');
      // A scaled preview cannot prove the full original image. Reject before
      // allocating its canvas; do not resample, crop or tolerate pixel changes.
      if (expected && (width !== expected.width || height !== expected.height)) fail('PREVIEW_DIMENSIONS_CHANGED');
      const canvas = new OffscreenCanvas(width, height);
      // Match the page's ordinary sRGB preview rendering. On the tested Mac,
      // willReadFrequently changes color-profile rounding by one channel level.
      // Keep exact RGBA equality; never use a tolerance or bless an old operation.
      const ctx = canvas.getContext('2d', {colorSpace: 'srgb'});
      if (!ctx) fail('PIXEL_CONTEXT_UNAVAILABLE');
      ctx.drawImage(image, 0, 0);
      return {width, height, sha256: await hash(ctx.getImageData(0, 0, width, height).data)};
    }
    async function decodeOriginal(file) {
      const image = new Image(), url = URL.createObjectURL(file);
      try {
        await new Promise((resolve, reject) => { image.onload = resolve; image.onerror = reject; image.src = url; });
        return await pixels(image);
      } finally { URL.revokeObjectURL(url); }
    }
    function beginProof(op) {
      if (op.proofPending || op.proof || op.completionUnavailable || !op.fileHashVerified || !op.loaded || !op.ended
          || !currentMember(op) || op.uploading || !op.image.complete) return;
      const source = currentSource(op.image), card = op.card, image = op.image;
      if (!/^data:image\/png;base64,/.test(source)) return;
      op.proofPending = true;
      const loadSequence = op.loaded, sourceFile = op.file;
      (async () => {
        let matched = false, completionDetails = null;
        // MAX_BYTES bounds the original input AND any additional base64 decode.
        // Re-encoding can enlarge a preview without changing one pixel. In that
        // case inspect the already loaded image under the existing pixel bound,
        // rather than copying/decoding its oversized Data URI or raising a cap.
        if (source.length - 'data:image/png;base64,'.length <= Math.floor(MAX_BYTES / 3) * 4) {
          const previewBytes = Uint8Array.from(atob(source.slice(source.indexOf(',') + 1)), c => c.charCodeAt(0));
          if (previewBytes.byteLength <= MAX_BYTES) {
            const previewHash = await hash(previewBytes);
            matched = previewBytes.byteLength === op.bytes && previewHash === op.identity.assetSHA256;
            if (matched) completionDetails = {kind: 'exactOriginalBytes', observedByteCount: previewBytes.byteLength,
              observedSHA256: previewHash};
          }
        }
        if (!matched) {
          const original = await decodeOriginal(sourceFile), preview = await pixels(image, original);
          matched = original.width === preview.width && original.height === preview.height && original.sha256 === preview.sha256;
          if (matched) completionDetails = {kind: 'exactSRGBPixels', originalWidth: original.width,
            originalHeight: original.height, originalPixelSHA256: original.sha256,
            previewWidth: preview.width, previewHeight: preview.height, previewPixelSHA256: preview.sha256};
        }
        // Async proof is bound to the full operation, original nodes/source and
        // final-load sequence. It cannot bless another card or a newer preview.
        if (!currentMember(op) || op.card !== card || op.image !== image || currentSource(image) !== source
            || op.loaded !== loadSequence || op.uploading || !image.complete || associatedError(card)) {
          markBad(op); return;
        }
        if (!matched) { op.completionUnavailable = 'previewPixelsUnproven'; op.file = null; return; }
        // Diagnostic clock only: not exported and never used to admit completion.
        const completionEvidence = typeof op.invocationID === 'string'
          && /^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$/.test(op.invocationID)
          ? {version: 1, evidenceID: crypto.randomUUID(), binding: {version: 1, ...op.identity,
              target: {...op.identity.target}, invocationID: op.invocationID,
              attachmentID: op.identity.target.documentID + ':' + nodeID(card) + ':' + nodeID(image)},
            originalByteCount: op.bytes, originalSHA256: op.identity.assetSHA256, ...completionDetails} : null;
        op.proof = {identity: op.identity, card, image, source, loadSequence, completed: tick(), completedAtMS: performance.now(), completionEvidence};
        op.preservedAttachments = null;
        // Earlier installed monitors have no completion-close capability. Keep
        // their original facts/closures rather than replacing a live singleton.
        try { registry.originalFileRequests?.completed?.(op); } catch { /* Optional observation never changes completion. */ }
        op.file = null;
      })().catch(error => {
        // A scaled, undecodable or unavailable preview cannot establish exact
        // completion. It is not an upload failure or a loss of this operation's
        // original input/START ownership, and must not retire another upload.
        // Keep the one-shot input tombstone and immutable START; no retry or
        // weakened pixel comparison is granted. Do not repeat an expensive
        // failed proof on every background poll.
        if (currentMember(op)) {
          op.completionUnavailable = error?.message === 'PREVIEW_DIMENSIONS_CHANGED'
            ? 'previewDimensionsUnproven' : 'previewProofUnavailable';
          op.file = null;
        }
        else markBad(op);
      }).finally(() => { op.proofPending = false; });
    }

    // Start evidence is independent from the final preview proof. Only snapshots
    // of the same original progress node, after our one file input, can advance
    // it. Invalid/replaced/regressing progress permanently loses start eligibility;
    // none of these observations grants retry or changes completion evidence.
    const progressNumber = raw => {
      const value = typeof raw === 'string' && /^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/.test(raw) ? Number(raw) : NaN;
      return Number.isFinite(value) && value >= 0 && value <= 100 ? value : NaN;
    };
    function sampleStart(op, progress, now) {
      if (op.startDisqualified) return;
      if (progress.length !== 1) {
        if (op.progressNode) op.startDisqualified = true;
        return;
      }
      const node = progress[0];
      if (op.progressNode && op.progressNode !== node) { op.startDisqualified = true; return; }
      if (!op.inputSequence || now <= op.inputSequence
          || !Number.isFinite(op.inputObservedAtMS) || op.inputObservedAtMS < 0) {
        op.startDisqualified = true; return;
      }
      // Real initial indeterminate progress has no aria-valuenow. Bind that
      // exact node now so removal/replacement during the wait cannot be hidden.
      // Missing is allowed only before any finite sample; it proves no start.
      op.progressNode = node;
      const raw = node.getAttribute('aria-valuenow');
      if (raw === null && op.progressValue === null) return;
      const value = progressNumber(raw);
      if (!Number.isFinite(value)) { op.startDisqualified = true; return; }
      const previous = op.progressValue;
      if (previous !== null && value < previous) { op.startDisqualified = true; return; }
      op.progressNode = node; op.progressValue = value;
      if (previous !== null && previous < value && value < 100 && op.fileHashVerified && !op.uploadStart) {
        const observedAt = performance.now();
        if (!Number.isFinite(observedAt) || observedAt <= op.inputObservedAtMS) { op.startDisqualified = true; return; }
        // Times are monotonic milliseconds within this document, not Unix time.
        op.uploadStart = {version: 1, signal: 'correlatedProgress', evidenceID: crypto.randomUUID(),
          inputCount: 1, inputSequence: op.inputSequence, startSequence: now,
          previousProgress: previous, currentProgress: value,
          inputObservedAtMS: op.inputObservedAtMS, startObservedAtMS: observedAt};
        // The submission's preservation check ends at its own first START.
        // A later independent error/removal/completion of A is not B's fate.
        op.preservedAttachments = null;
      }
    }

    function sample(op, eventType = 'query', eventImage = null) {
      if (!observationIdentityValid()) return;
      if (op.invalid || !op.committed) return;
      if (op.preservedAttachments && !attachmentsIntact(op.preservedAttachments)) { markBad(op, false, 'attachmentRemoved'); return; }
      const now = tick(), cards = ownCards(op.name);
      if (cards.length === 0) { if (op.card) markBad(op, false, 'attachmentRemoved'); return; }
      if (cards.length !== 1 || op.inputCount !== 1) { markBad(op); return; }
      const card = cards[0], images = [...card.querySelectorAll('img')];
      if (images.length !== 1 || images[0].alt !== op.name) { markBad(op); return; }
      const image = images[0];
      if ((op.card && op.card !== card) || (op.image && op.image !== image)) { markBad(op, false, 'attachmentReplaced'); return; }
      op.card = card; op.image = image;
      if (associatedError(card)) { markBad(op, true); return; }
      const progress = [...card.querySelectorAll('[role=progressbar]')];
      op.uploading = progress.length > 0;
      if (progress.length) {
        if (progress.length !== 1 || progress[0].getAttribute('aria-label') !== '正在上传 ' + op.name || op.ended) {
          markBad(op); return;
        }
        op.started ||= now;
        if (progress[0].getAttribute('aria-valuenow') === '100') op.hundred ||= now;
      } else if (op.hundred) op.ended ||= now;
      sampleStart(op, progress, now);
      if (eventType === 'error' && eventImage === image) { markBad(op, true); return; }
      if (eventType === 'load' && eventImage === image && op.ended && now > op.hundred
          && image.complete && image.naturalWidth > 0 && image.naturalHeight > 0
          && currentSource(image).startsWith('data:image/png;base64,')) {
        // A new load after a proof or a previous final-load event means a new
        // preview generation; it cannot reuse the old proof.
        if (op.loaded) { markBad(op, false, 'previewChanged'); return; }
        op.loaded = now;
      }
      if (op.proof && currentSource(image) !== op.proof.source) { markBad(op, false, 'previewChanged'); return; }
      beginProof(op);
    }
    const sampleAll = (type, image) => { for (const op of operations.values()) sample(op, type, image); };
    const containsNode = (container, node) => !!node && (container === node
      || (typeof container.contains === 'function' && container.contains(node)));
    const processRecords = records => {
      // Mutation batches can detach/reinsert nodes or change a source and restore
      // it before the callback. A final snapshot alone would hide that gap.
      let relevant = false;
      const progressOldValues = new Map(); // At most one entry per bounded operation.
      for (const record of records) {
        if (containsNode(form, record.target)) relevant = true;
        if (record.type === 'attributes' && ['aria-label','alt'].includes(record.attributeName)) {
          for (const resource of preparedResources.values()) if (resource.attachments.some(({card,images}) =>
              record.target === card || images.some(({image}) => record.target === image))) resource.invalid = true;
        }
        if (modeGroup && containsNode(modeGroup, record.target)) {
          relevant = true;
          // Observe the changes, not only their final value: Chat -> Work ->
          // Chat within one mutation batch permanently revokes this lease.
          if (record.type === 'characterData' || record.type === 'childList'
              || (record.type === 'attributes' && ['aria-pressed', 'role', 'aria-label', 'type'].includes(record.attributeName)
                && record.oldValue !== record.target.getAttribute(record.attributeName))) invalidate();
        }
        for (const removed of record.removedNodes || []) {
          for (const resource of preparedResources.values()) if (resource.attachments.some(({card, images}) =>
              containsNode(removed, card) || images.some(({image}) => containsNode(removed,image)))) resource.invalid = true;
          if ([editor, input, form, modeGroup, modeHeader, chatMode, workMode, ...baseline].some(node => containsNode(removed, node))) {
            invalidate(); relevant = true;
          }
          for (const op of operations.values()) {
            if (op.preservedAttachments?.some(({card,images}) => containsNode(removed,card)
                || images.some(({image}) => containsNode(removed,image)))) { markBad(op, false, 'attachmentRemoved'); relevant = true; }
            if (containsNode(removed, op.card) || containsNode(removed, op.image)) { markBad(op, false, 'attachmentRemoved'); relevant = true; }
          }
        }
        for (const op of operations.values()) {
          if (!op.startDisqualified && record.type === 'attributes' && record.target === op.progressNode
              && record.attributeName === 'aria-valuenow') {
            // oldValue records retain intermediate changes hidden by the final
            // DOM snapshot. Check both record order and every old-to-final edge;
            // 20 -> 80 -> 10 -> 90 must not look like one safe 20 -> 90 advance.
            const currentRaw = record.target.getAttribute('aria-valuenow');
            const oldValue = progressNumber(record.oldValue), currentValue = progressNumber(currentRaw);
            const previousOldValue = progressOldValues.get(op);
            // Initial missing -> first finite is only a baseline transition.
            // A finite oldValue anywhere in this batch ends the missing-value
            // allowance, including null -> finite -> null -> finite round trips.
            if (record.oldValue === null) {
              if (op.progressValue !== null || Number.isFinite(previousOldValue)
                  || (currentRaw !== null && !Number.isFinite(currentValue))) op.startDisqualified = true;
            } else if (!Number.isFinite(oldValue) || !Number.isFinite(currentValue) || oldValue > currentValue
                || (Number.isFinite(previousOldValue) && oldValue < previousOldValue)) op.startDisqualified = true;
            progressOldValues.set(op, record.oldValue === null ? null : oldValue);
          }
          if ([...(record.removedNodes || [])].some(node => containsNode(node, op.progressNode))
              || (record.type === 'attributes' && record.target === op.progressNode
                && ['aria-label', 'role'].includes(record.attributeName))) op.startDisqualified = true;
          if (record.type === 'attributes' && ((record.target === op.card && record.attributeName === 'aria-label')
              || (record.target === op.image && record.attributeName === 'alt'))) markBad(op);
          if (record.type === 'attributes' && op.loaded && record.target === op.image
              && ['src', 'srcset'].includes(record.attributeName)) markBad(op, false, 'previewChanged');
          if (op.ended && op.card && containsNode(op.card, record.target)) {
            const changed = [...(record.addedNodes || []), ...(record.removedNodes || [])];
            if (changed.some(node => node.getAttribute?.('role') === 'progressbar'
                || node.querySelector?.('[role=progressbar]'))) markBad(op);
          }
        }
      }
      if (relevant) sampleAll('mutation');
    };
    const observer = new MutationObserver(processRecords);
    stopObservation = () => {
      observer.disconnect();
      for (const [owner,type,handler,options] of listeners) owner.removeEventListener?.(type,handler,options);
      listeners.length = 0;
    };

    const drain = () => {
      // A hash Promise can run before an already queued MutationObserver
      // callback. Drain synchronously before target admission and final input
      // so a transient detach or mode round-trip cannot hide in that gap.
      const pending = observer.takeRecords();
      if (pending.length) processRecords(pending);
    };
    observer.observe(form, {subtree: true, childList: true, attributes: true, attributeOldValue: true, characterData: true});
    if (modeGroup) observer.observe(modeGroup, {subtree: true, childList: true, attributes: true, attributeOldValue: true,
      characterData: true, characterDataOldValue: true});
    // An entire form/ancestor can be detached and reinserted. Watch each parent
    // child-list only; avoid observing the rest of the page's subtree or text.
    for (const root of [form, modeGroup].filter(Boolean)) {
      for (let ancestor = root.parentNode; ancestor; ancestor = ancestor.parentNode) {
        observer.observe(ancestor, {childList: true});
      }
    }
    listen(document, 'change', event => {
      if (!observationIdentityValid() || event.target !== input || !(event.target instanceof HTMLInputElement)) return;
      for (const file of event.target.files || []) {
        const op = [...operations.values()].find(o => o.name === file.name);
        if (!op) continue; // Other user attachments cannot complete this operation.
        op.inputCount++;
        if (!op.committed || !op.expectingInput || op.inputCount !== 1 || file.size !== op.bytes || file.type !== 'image/png') {
          markBad(op, false, op.inputCount !== 1 ? 'repeatedInput' : 'attachmentIdentityChanged'); continue;
        }
        op.inputSequence = tick(); op.inputObservedAtMS = performance.now(); op.file = file;
        file.arrayBuffer().then(hash).then(digest => {
          if (!observationIdentityValid() || op.invalid || digest !== op.identity.assetSHA256 || op.inputCount !== 1) { markBad(op); return; }
          op.fileHashVerified = true; op.hashSequence = tick();
          try { registry.originalFileRequests?.verified(file, op); } catch { /* Optional facts cannot alter input. */ }
          sample(op, 'inputHash');
        }).catch(() => markBad(op));
      }
    }, true);
    for (const type of ['load', 'error']) listen(document, type, event => {
      if (event.target?.tagName === 'IMG') sampleAll(type, event.target);
    }, true);
    for (const type of ['pagehide', 'popstate', 'hashchange']) listen(globalThis, type, invalidate);
    listen(globalThis, 'pageshow', revokeInput);
    // The Window epoch changes across applications/windows even while both
    // pages remain visible. Input-to-input focus inside this draft is unrelated.
    for (const type of ['blur', 'focus']) listen(globalThis, type, event => {
      if (event.target === globalThis) revokeInput(type === 'blur' ? 'windowBlur' : 'windowFocus');
    });
    listen(document, 'visibilitychange', revokeInput);
    // A click in the body/sidebar is not a draft change. Recheck the same
    // binding after the page handles that interaction; navigation and root
    // commit guards independently revoke real transitions, including ABA.
    const continuityEvents = {outsideInteraction: 0, navigate: 0, currententrychange: 0};
    for (const type of ['pointerdown', 'click', 'keydown']) listen(document, type, event => {
      if (event.isTrusted === true && event.target && !form.contains(event.target)) {
        continuityEvents.outsideInteraction++;
        queueMicrotask(() => {
          drain();
          if (observationIdentityValid() && !composerAvailable()) revokeInput();
        });
      }
    }, true);
    if (typeof globalThis.navigation?.addEventListener === 'function') {
      for (const type of ['navigate', 'currententrychange']) listen(globalThis.navigation, type, () => {
        continuityEvents[type]++; invalidate();
      });
    }
    if (boundRoot) {
      const checkBinding = () => {
        const binding = readThreadBinding(form, businessHome), forms = document.querySelectorAll(threadFormSelector);
        const editors = document.querySelectorAll('[contenteditable=true][role=textbox]');
        const inputs = form.querySelectorAll('input[type=file][aria-label="附加文件"]');
        return binding?.root === boundRoot && sameLogical(binding?.logical, logicalDraftIdentity)
          && forms.length === 1 && forms[0] === form && location.href === route
          && form.isConnected && editor.isConnected && editor.closest('form') === form
          && editors.length === 1 && editors[0] === editor && input.isConnected
          && input.form === form && form.contains(input) && inputs.length === 1 && inputs[0] === input;
      };
      monitorAlive = monitor.bind(form, editor, input, logicalDraftIdentity, route, checkBinding, invalidate);
      if (!checkBinding() || !monitorAlive()) { invalidate(); fail('UNPROVEN_MONITORED_BINDING'); }
    }
    state = {lifecycleVersion: 1, proofProtocolVersion: 1, inputIsolationVersion: 1, inputResourceVersion:1, retainedInputVersion:1, prePressFocusVersion:1,
      prepareInputResource, claimInputResource, releaseInputResource, enterInputResource, forgetInputResource,
      resourceRefusalReason:() => lastResourceRefusal,
      settleNativeSelection:(file,op) => {
        // Weak keys do not retain screenshot bytes after the input/application
        // releases the File. Exact old operation fields remain unchanged.
        const selections = data(registry,'settledNativeSelections');
        if (selections instanceof WeakMap) selections.set(file,
          {state,operation:op,input,identity:{...op.identity,target:{...op.identity.target}}});
      },
      inputResourcePreserved:op => attachmentsIntact(op.inputResource.attachments) && editorIntact(op.inputResource.editor),
      continuationFor, pinTarget, validFor, claimPin, ownsTarget: candidate => ownsPin(candidate) || sameTarget(candidate,target) || retiredTargets.some(t => sameTarget(t,candidate)), get target() { return target; }, valid, observationIdentityValid, invalidate, revokeInput, drain, continuityEvents, operations, sample, tick, ownCards, markBad, currentMember,
      currentSource, input, form, nodeID, renewEmptyInputLease, next: null};
    if (registry.tail) registry.tail.next = state;
    else registry.head = state;
    registry.tail = state;
    registry.count++;
    return state;
  }

  let registry = globalThis[KEY];
  // All non-capture commands resolve the exact historical lease. They never
  // install/rearm a document, and cannot redirect an old UNKNOWN into a new one.
  const generations = function* () {
    let current = registry?.head;
    const seen = new Set();
    while (current && !seen.has(current)) { seen.add(current); yield current; current = current.next; }
  };
  if (command.action === 'captureTarget') {
    // A rejected background poll must not consume the last focused receipt.
    // Its existing observer still detects every route/draft/node transition;
    // only the native pre-press proof may use that exact focus-loss epoch.
    if (!pageRoute().supported) registry?.tail?.invalidate?.();
    if (globalThis.top !== globalThis || document.visibilityState !== 'visible') registry?.tail?.revokeInput?.();
    requirePageSurface();
    if (!registry) {
      registry = {head: null, tail: null, count: 0, rootMonitors: new Map()};
      registry.stopRootMonitors = () => [...registry.rootMonitors.values()].map(monitor => monitor.stop());
      Object.defineProperty(globalThis, KEY, {value: registry, configurable: false, writable: false});
    }
    let current = registry.tail;
    current?.drain();
    if (!current || current.proofProtocolVersion !== 1 || current.inputIsolationVersion !== 1 || current.inputResourceVersion !== 1 || current.retainedInputVersion !== 1 || current.prePressFocusVersion !== 1
        || !current.pinTarget || !current.valid() || !contextMatches(current.target)) {
      // Historical v13 closures have no renewal capability. Leave those states
      // and all their operations untouched and use their original bounded path.
      if (current?.proofProtocolVersion === 1 && current.inputIsolationVersion === 1 && current.inputResourceVersion === 1 && current.retainedInputVersion === 1 && current.prePressFocusVersion === 1
          && current.pinTarget && contextMatches(current.target) && current.renewEmptyInputLease?.()) return current.target;
      if (current) current.revokeInput();
      // Identity tombstones are retained; lifetime count is not a resource quota.
      current = install(registry);
    }
    return current.target;
  }
  if (command.action === 'pinTarget') {
    // No installation on a late page. A missing/legacy continuity observer is
    // a refusal, never permission to bind whatever document appears later.
    const current = registry?.tail;
    current?.drain();
    if (!current?.pinTarget || !contextMatches(current.target)
        || !sameTarget(command.target,current.target)) fail('CLICK_ROUTE_UNOBSERVED');
    return current.pinTarget(command.clickBindingID, command.nativePressProof);
  }
  const state = [...generations()].find(generation => (generation.ownsTarget?.(command.target) ?? sameTarget(command.target, generation.target)));
  state?.drain();
  if (command.action === 'validate') {
    return {target: command.target, valid: !!state && (command.target?.clickBindingID
      ? state.validFor?.(command.target) === true : state === registry.tail && sameTarget(command.target,state.target) && state.valid())
      && contextMatches(command.target)};
  }
  const identity = command.identity;
  if (!identity || !sameTarget(identity.target, command.target)) fail('IDENTITY_REQUIRED');
  if (command.action === 'releaseInputResource') {
    return {released: state?.releaseInputResource?.(identity,command.invocationID,command.inputResourceID) === true};
  }
  if (!state || !(command.action === 'observe' ? state.observationIdentityValid() : (identity.target.clickBindingID ? state.validFor?.(identity.target) : state.valid())) || !contextMatches(identity.target) || !(command.action === 'observe' ? (state.ownsTarget?.(identity.target) ?? sameTarget(identity.target,state.target)) : (identity.target.clickBindingID ? state.validFor?.(identity.target) : sameTarget(identity.target,state.target)))
      || (command.action !== 'observe' && !identity.target.clickBindingID && state !== registry.tail)) {
    if (command.action === 'observe') return blankObservation(identity);
    fail(command.action === 'prepareInputResource' ? 'INPUT_RESOURCE_TARGET_CHANGED' : 'TARGET_INVALID');
  }
  const acknowledge = (op, nextChunk) => ({operationID: op.identity.operationID, attempt: op.identity.attempt, nextChunk});
  let op = state.operations.get(identity.operationID);
  if (command.action === 'prepareInputResource') {
    if (op || state.inputResourceVersion !== 1 || state.retainedInputVersion !== 1 || typeof state.prepareInputResource !== 'function') fail('INPUT_RESOURCE_RESERVATION_BUSY');
    return state.prepareInputResource(identity,command.invocationID);
  }
  if (command.action === 'begin') {
    if ([...generations()].some(generation => generation.operations.has(identity.operationID)) || !Number.isSafeInteger(identity.attempt) || identity.attempt < 1
        || !/^[a-f0-9]{64}$/.test(identity.assetSHA256)
        || !/^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$/.test(identity.operationID) || !/^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$/.test(identity.assetID)
        || (command.invocationID !== undefined && (typeof command.invocationID !== 'string' || !/^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$/.test(command.invocationID)))
        || command.uploadName !== 'riftlet-' + identity.operationID + '.png'
        || command.mediaType !== 'image/png' || !Number.isSafeInteger(command.byteCount)
        || command.byteCount < 8 || command.byteCount > MAX_BYTES || state.ownCards(command.uploadName).length) fail('BEGIN_REFUSED');
    state.claimPin?.(identity);
    // Existing v13 observers keep their old operations and old proof protocol.
    // A stale pin must not dispatch a new upload through that old closure and
    // later fabricate v4 evidence. Retire only this fresh no-input invocation.
    if (state.proofProtocolVersion !== 1 || state.inputIsolationVersion !== 1) {
      if (state.lifecycleVersion !== 1 || typeof command.invocationID !== 'string'
          || !/^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$/.test(command.invocationID)) fail('BEGIN_REFUSED');
      state.operations.set(identity.operationID, {identity, invocationID: command.invocationID,
        name: command.uploadName, committed: false, invalid: true, inputCount: 0});
      return {identity, invocationID: command.invocationID, retiredBeforeInput: true, inputCount: 0,
        commitInvoked: false, rejectedBeforeBegin: true, reason: 'OBSERVER_UPGRADE_REQUIRED'};
    }
    if ([...generations()].flatMap(g => [...g.operations.values()]).filter(o => !o.invalid && (!o.committed || o.file || (o.committed && !o.fileHashVerified))).length >= MAX_ACTIVE_PAYLOADS) {
      if (state.lifecycleVersion !== 1 || typeof command.invocationID !== 'string' || !/^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$/.test(command.invocationID)) fail('BEGIN_REFUSED');
      state.operations.set(identity.operationID, {identity, invocationID:command.invocationID,
        name:command.uploadName, committed:false, invalid:true, inputCount:0});
      return {identity, invocationID:command.invocationID, retiredBeforeInput:true,
        inputCount:0, commitInvoked:false, rejectedBeforeBegin:true, reason:'ACTIVE_PAYLOAD_LIMIT'};
    }
    let inputResource = null;
    if (command.inputResourceID !== undefined) {
      inputResource = state.claimInputResource?.(identity,command.invocationID,command.inputResourceID);
      if (!inputResource) {
        if (!state.lifecycleVersion || typeof command.invocationID !== 'string') fail('BEGIN_REFUSED');
        state.operations.set(identity.operationID,{identity,invocationID:command.invocationID,name:command.uploadName,committed:false,invalid:true,inputCount:0});
        return {identity,invocationID:command.invocationID,retiredBeforeInput:true,inputCount:0,commitInvoked:false,
          rejectedBeforeBegin:true,reason:'INPUT_RESOURCE_UNAVAILABLE',resourceRefusalReason:state.resourceRefusalReason?.()};
      }
    }
    op = {identity, invocationID: command.invocationID, name: command.uploadName, bytes: command.byteCount, chunks: [], nextChunk: 0, received: 0,
      inputResource,
      committed: false, invalid: false, error: false, inputCount: 0, fileHashVerified: false,
      inputSideEffectEntered: false, commitWorkSettled: false, preInputRetirementReason: null,
      callSettledSequence: null, inputOwnershipID: null, inputIsolationProof: null,
      inputSequence: 0, inputObservedAtMS: null, progressNode: null, progressValue: null,
      startDisqualified: false, uploadStart: null,
      started: 0, hundred: 0, ended: 0, loaded: 0, uploading: false, proof: null};
    state.operations.set(identity.operationID, op);
    return {...acknowledge(op, 0), ...(state.lifecycleVersion === 1 && typeof op.invocationID === 'string' ? {allocated:true,identity:op.identity,invocationID:op.invocationID} : {})};
  }
  if (!op || !sameIdentity(identity, op.identity)) {
    if (command.action === 'observe') return blankObservation(identity);
    fail('ORIGINAL_OPERATION_REQUIRED');
  }
  if (command.action !== 'observe' && op.invocationID && command.invocationID !== op.invocationID) fail('INVOCATION_MISMATCH');
  // Upgrading the caller does not upgrade an old state's captured observers.
  // A staged historical operation must not acquire a new input through this
  // program. Keep observation and original-invocation discard available; an
  // already executing old commit retains its own one-shot closure and audit.
  if (state.proofProtocolVersion !== 1 && (command.action === 'chunk' || command.action === 'commit')) {
    fail(command.action === 'chunk' ? 'CHUNK_REFUSED' : 'COMMIT_REFUSED');
  }
  if (command.action === 'chunk') {
    if (op.committed || op.invalid || command.chunkIndex !== op.nextChunk
        || typeof command.chunkBase64 !== 'string' || command.chunkBase64.length > 4 * Math.ceil(MAX_CHUNK_BYTES / 3)
        || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(command.chunkBase64)) fail('CHUNK_REFUSED');
    const bytes = Uint8Array.from(atob(command.chunkBase64), c => c.charCodeAt(0));
    if (!bytes.length || bytes.length > MAX_CHUNK_BYTES || op.received + bytes.length > op.bytes) fail('CHUNK_SIZE');
    op.chunks.push(bytes); op.received += bytes.length; op.nextChunk++;
    return acknowledge(op, op.nextChunk);
  }
  if (command.action === 'discard') {
    if (!op.committed) { op.chunks = []; op.invalid = true; state.forgetInputResource?.(op); }
    return {discarded: !op.committed, ...(state.lifecycleVersion === 1 && !op.committed && op.inputCount === 0 && typeof op.invocationID === 'string' && command.invocationID === op.invocationID ? {identity:op.identity,invocationID:op.invocationID,retiredBeforeInput:true,inputCount:0,commitInvoked:false} : {})}; // Never remove an attachment or reset a dispatch tombstone.
  }
  if (command.action === 'commit') {
    if (op.committed || op.invalid || op.received !== op.bytes || command.chunkIndex !== op.nextChunk) fail('COMMIT_REFUSED');
    op.committed = true; // One-shot tombstone precedes every asynchronous step and side effect.
    const bytes = new Uint8Array(op.bytes);
    let offset = 0;
    for (const chunk of op.chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    op.chunks = [];
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    const retireBeforeInput = reason => {
      // Missing change is insufficient: a throwing setter may already have
      // changed files. The flag is written before entering that side effect.
      if (op.inputSideEffectEntered === false && op.inputCount === 0 && !op.preInputRetirementReason) {
        op.preInputRetirementReason = reason;
      }
      state.markBad(op);
      state.forgetInputResource?.(op);
    };
    if (!signature.every((n, i) => bytes[i] === n)) {
      retireBeforeInput('invalidPNGSignature'); op.commitWorkSettled = true;
    }
    else hash(bytes).then(digest => {
      state.drain();
      if (digest !== op.identity.assetSHA256) { retireBeforeInput('inputHashMismatch'); return; }
      if (op.invalid
          || (op.identity.target.clickBindingID ? !state.validFor?.(op.identity.target)
            : state !== registry.tail || !state.valid() || document.visibilityState !== 'visible' || !document.hasFocus()
              || !sameTarget(op.identity.target, state.target)) || state.ownCards(op.name).length) {
        retireBeforeInput('targetInvalidBeforeInput'); return;
      }
      // From this final lease/identity check through native setter+change there is
      // no await, focus, route change, selector fallback, send or composer edit.
      const file = new File([bytes], op.name, {type: 'image/png'}), transfer = new DataTransfer();
      transfer.items.add(file);
      if (op.inputResource && !state.enterInputResource?.(op)) { retireBeforeInput('inputPreparationFailed'); return; }
      try { originalFileRequests(registry).bind(file, state, op); } catch { /* No request evidence, ordinary input unchanged. */ }
      // Shared input access lasts only through the one native setter and its
      // synchronous change dispatch. Background observations never own it.
      // A reentrant handler cannot enter a second FileList assignment here.
      registry.inputOwners ||= new WeakMap();
      // Invalidation can retire the state's public fields inside a synchronous
      // change handler. Release the exact originally acquired node, never a
      // later state.input lookup that may now be undefined or replaced.
      const inputNode = state.input, inputTick = state.tick, forgetResource = state.forgetInputResource;
      const preserveResource = state.inputResourcePreserved, settleSelection = state.settleNativeSelection;
      const markInputBad = state.markBad;
      if (registry.inputOwners.has(inputNode)) { op.resourceRefusalReason='INPUT_RESOURCE_EXECUTION_BUSY'; retireBeforeInput('inputPreparationFailed'); return; }
      registry.inputOwners.set(inputNode, op);
      try {
        op.inputOwnershipID = crypto.randomUUID();
        op.expectingInput = true;
        op.inputSideEffectEntered = true;
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'files').set.call(inputNode, transfer.files);
        inputNode.dispatchEvent(new Event('change', {bubbles: true}));
        op.callSettledSequence = inputTick();
        settleSelection?.(file,op);
        if (op.inputResource && !preserveResource(op)) markInputBad(op, false, 'attachmentIdentityChanged');
      } finally {
        op.expectingInput = false;
        forgetResource?.(op);
        if (registry.inputOwners.get(inputNode) === op) registry.inputOwners.delete(inputNode);
      }
      if (op.inputCount !== 1) state.markBad(op);
      state.sample(op, 'dispatch');
    }).catch(() => retireBeforeInput('inputPreparationFailed')).finally(() => {
      // No retirement proof while the original async chain could still input.
      // A destroyed binding retains its old conservative audit; it is not healed.
      op.commitWorkSettled = true;
    });
  } else if (command.action !== 'observe') fail('UNKNOWN_ACTION');

  state.sample(op);
  const envelope = blankObservation(identity, 'unknown'), observation = envelope.observation;
  observation.belongsToOriginalDraft = state.observationIdentityValid() && (state.ownsTarget?.(identity.target) ?? sameTarget(identity.target,state.target));
  observation.hasError = op.error;
  observation.isUploading = op.uploading;
  if (op.resourceRefusalReason) observation.resourceRefusalReason = op.resourceRefusalReason;
  if (op.reason || op.completionUnavailable) observation.reason = op.reason || op.completionUnavailable;
  try {
    const facts = op.requestFactSnapshot?.();
    if (facts) { envelope.schemaVersion = 4; observation.requestEvidence = facts; }
  } catch { /* No request facts may be inferred from an observation failure. */ }
  if (!observation.belongsToOriginalDraft || op.invalid) {
    if (observation.belongsToOriginalDraft && op.invalid && op.committed
        && op.commitWorkSettled === true && op.inputSideEffectEntered === false && op.inputCount === 0
        && !op.fileHashVerified && !op.uploadStart && !op.error && !op.card && !op.image
        && ['invalidPNGSignature','inputHashMismatch','targetInvalidBeforeInput','inputPreparationFailed'].includes(op.preInputRetirementReason)
        && typeof op.invocationID === 'string' && /^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$/.test(op.invocationID)) {
      envelope.schemaVersion = 3;
      observation.preInputRetirement = {version: 1, invocationID: op.invocationID,
        commitInvoked: true, commitWorkSettled: true, irreversiblyRetired: true,
        inputSideEffectEntered: false, inputCount: 0, reason: op.preInputRetirementReason};
    }
    if (observation.belongsToOriginalDraft && op.error && op.errorAttachmentID
        && op.card?.isConnected && state.form.contains(op.card)
        && op.image?.isConnected && op.image.closest('[role=button]') === op.card
        && op.card.getAttribute('aria-label') === op.name && op.image.alt === op.name
        && state.ownCards(op.name).length === 1) {
      observation.attachmentID = op.errorAttachmentID;
      observation.exactImageIdentity = true;
    }
    observation.state = 'invalidated'; return envelope;
  }
  if (op.inputCount === 1 && !op.completionUnavailable) observation.state = 'inputTriggered';
  if (op.card && op.image) observation.attachmentID = op.identity.target.documentID + ':' + state.nodeID(op.card) + ':' + state.nodeID(op.image);
  // A stored start is not itself a current upload claim. Completion, errors,
  // missing/replaced progress, or an invalid original binding cannot replay it.
  if (op.uploadStart && !op.startDisqualified && !op.error && !op.proof && !op.ended
      && op.uploading && op.progressValue >= op.uploadStart.currentProgress && op.progressValue < 100
      && op.fileHashVerified && op.inputCount === 1 && state.currentMember(op)) {
    observation.state = 'uploadStarted'; observation.exactImageIdentity = true;
    observation.uploadStart = {...op.uploadStart};
    const continuation = state.continuationFor?.(op, observation.requestEvidence);
    if (continuation) { envelope.schemaVersion = 4; observation.continuationEvidence = continuation; }
  }
  const proof = op.proof;
  if (proof && sameIdentity(proof.identity, identity) && proof.completed > op.loaded && op.loaded > op.hundred
      && op.started && op.ended && op.fileHashVerified && op.inputCount === 1 && state.currentMember(op)
      && proof.card === op.card && proof.image === op.image && proof.source === state.currentSource(op.image)
      && proof.loadSequence === op.loaded && !op.uploading && op.image.complete) {
    const completion = proof.completionEvidence;
    const exactBinding = completion && completion.version === 1 && completion.binding?.version === 1
        && sameIdentity(completion.binding, identity) && completion.binding.invocationID === op.invocationID
        && completion.binding.attachmentID === observation.attachmentID
        && completion.originalSHA256 === identity.assetSHA256 && completion.originalByteCount === op.bytes;
    if (completion && !exactBinding) {
      state.markBad(op); observation.state = 'invalidated'; return envelope;
    }
    observation.state = 'attached'; observation.exactImageIdentity = true;
    if (exactBinding) {
      envelope.schemaVersion = 4; observation.completionEvidence = completion;
    }
  }
  return envelope;
}
