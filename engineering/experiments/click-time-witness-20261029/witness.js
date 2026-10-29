/*
 * Offline architecture experiment only. Not imported by any Riftlet product.
 * The entry belongs to this document; it is NOT an NSPanel, extension popup,
 * side panel, forwarded native click, or production input authorization.
 */
globalThis.createClickTimeWitnessExperiment = function (options) {
  'use strict';
  const {entry, form, editor, fileInput, captureTarget, validateTarget,
    readAsset, readHost, requestAsset, syntheticInput} = options;
  if (entry.ownerDocument !== document || form.ownerDocument !== document)
    throw Error('EXPERIMENT_DOCUMENT_REQUIRED');
  const docNonce = crypto.randomUUID();
  const receipts = [], consumed = new Set();
  const limits = {maximumWaitMS: 2_000, maximumReceipts: 64};
  let witness = null, pending = null, boundaryEpoch = 0, captureCount = 0;
  let publicationCount = 0, frozenCount = 0, sinkInvocationCount = 0;

  const copy = value => JSON.parse(JSON.stringify(value));
  const freeze = value => {
    for (const child of Object.values(value)) if (child && typeof child === 'object') freeze(child);
    return Object.freeze(value);
  };
  const hostKey = host => JSON.stringify([host.connectionEpoch, host.permissionEpoch, host.allowed]);
  const assetKey = asset => JSON.stringify([asset.assetID, asset.sha256, asset.byteCount,
    asset.visibilityRevision, asset.attempt]);
  const sameHost = original => hostKey(readHost()) === hostKey(original) && readHost().allowed === true;
  const sameAsset = original => assetKey(readAsset()) === assetKey(original);
  const localNodesValid = () => entry.isConnected && form.isConnected && editor.isConnected
    && fileInput.isConnected && fileInput.form === form && editor.closest('form') === form
    && document.getElementById(entry.id) === entry;
  const originalValid = value => {
    if (!localNodesValid() || value.docNonce !== docNonce || value.boundaryEpoch !== boundaryEpoch
        || !document.hasFocus() || document.visibilityState !== 'visible'
        || !sameHost(value.host) || !sameAsset(value.asset)) return false;
    // The supplied production validate drains the ORIGINAL monitor. It never
    // captures/rearms, installs a new lease, or selects a replacement target.
    try { return validateTarget(value.target) === true; } catch { return false; }
  };
  const record = (status, reason, details = {}) => {
    if (receipts.length >= limits.maximumReceipts) throw Error('BOUNDED_LAB_RECEIPTS');
    receipts.push({status, reason, at: performance.now(), ...details});
  };
  const cancel = reason => {
    if (!pending) return;
    const original = pending;
    pending = null;
    clearTimeout(original.timeout);
    // Once the sink was invoked, a boundary cannot turn this into a pre-input
    // refusal. Keep the consumed ledger and do not promote a late sink reply.
    record(original.phase === 'consumed' ? 'UNKNOWN' : 'REFUSED',
      original.phase === 'consumed' ? 'CONSUMED_BOUNDARY_INVALIDATED' : reason,
      {tokenID: original.tokenID, phase: original.phase, boundaryReason: reason});
  };
  const boundary = event => {
    if ((event.type === 'blur' || event.type === 'focus') && event.target !== window) return;
    boundaryEpoch++;
    cancel('DOCUMENT_BOUNDARY_CHANGED');
  };
  for (const name of ['blur', 'focus', 'pagehide']) window.addEventListener(name, boundary);
  document.addEventListener('visibilitychange', boundary);

  // This method is the independent PRE-EVENT observer entry. Pointer handlers
  // below deliberately have no path to this function or captureTarget.
  function publishWitness() {
    if (pending) throw Error('PENDING_CLICK_CANNOT_REBIND');
    const host = freeze(copy(readHost())), asset = freeze(copy(readAsset()));
    if (!host.allowed || !Number.isSafeInteger(host.connectionEpoch)
        || !Number.isSafeInteger(host.permissionEpoch) || !Number.isSafeInteger(asset.visibilityRevision)
        || !Number.isSafeInteger(asset.attempt) || asset.attempt < 1 || !/^[a-f0-9]{64}$/.test(asset.sha256))
      throw Error('INVALID_PRE_EVENT_METADATA');
    captureCount++;
    const target = freeze(copy(captureTarget()));
    const candidate = {docNonce, target, host, asset, boundaryEpoch,
      witnessID: crypto.randomUUID(), monitorGeneration: target.draftGeneration};
    if (!originalValid(candidate)) throw Error('PRE_EVENT_TARGET_INVALID');
    // Completion is sampled after capture and validation, in this renderer's
    // time origin. Equal/quantized timestamp evidence will be refused later.
    witness = Object.freeze({...candidate, completedAt: performance.now()});
    publicationCount++;
    return {witnessID: witness.witnessID, completedAt: witness.completedAt};
  }

  const ownedPointer = event => event instanceof PointerEvent && event.isTrusted === true
    && event.isPrimary === true && event.pointerType === 'mouse' && event.button === 0
    && event.target === entry && event.composedPath()[0] === entry
    && entry.ownerDocument === document;

  function pointerDown(event) {
    const handlerAt = performance.now();
    if (!ownedPointer(event)) { record('REFUSED', 'NOT_ORIGINAL_TRUSTED_PRIMARY_POINTER'); return; }
    if (pending) { record('REFUSED', 'ORIGINAL_CLICK_ALREADY_PENDING'); return; }
    const original = witness;
    if (!original) { record('REFUSED', 'NO_PRE_EVENT_WITNESS'); return; }
    if (!Number.isFinite(event.timeStamp) || !(original.completedAt < event.timeStamp)
        || !(event.timeStamp <= handlerAt)) {
      record('REFUSED', 'WITNESS_NOT_PRE_EVENT', {witnessCompletedAt: original.completedAt,
        eventAt: event.timeStamp, handlerAt}); return;
    }
    if (!originalValid(original)) { record('REFUSED', 'ORIGINAL_WITNESS_INVALID'); return; }
    if (consumed.has(original.asset.assetID)) { record('REFUSED', 'ASSET_ALREADY_CONSUMED'); return; }
    // preventDefault preserves the selection; it never focuses the editor.
    event.preventDefault();
    pending = {tokenID: crypto.randomUUID(), requestID: crypto.randomUUID(), witness: original,
      target: original.target, pointerID: event.pointerId, eventAt: event.timeStamp, handlerAt,
      phase: 'down', operationID: crypto.randomUUID(), timeout: null};
    const selected = pending;
    pending.timeout = setTimeout(() => { if (pending === selected) cancel('BOUNDED_WAIT_EXPIRED'); }, limits.maximumWaitMS);
    frozenCount++;
    record('FROZEN', 'ORIGINAL_PAGE_EVENT', {tokenID: pending.tokenID, witnessID: original.witnessID,
      witnessCompletedAt: original.completedAt, eventAt: pending.eventAt, handlerAt,
      source: 'HEADLESS_CDP_UA_POINTER_NOT_PHYSICAL'});
  }

  async function finish(original) {
    const value = original.witness;
    const request = freeze({requestID: original.requestID, tokenID: original.tokenID,
      docNonce, witnessID: value.witnessID, operationID: original.operationID,
      target: original.target, asset: value.asset, host: value.host});
    try {
      const response = await requestAsset(request);
      if (pending !== original) return;
      if (!response || JSON.stringify(response.request) !== JSON.stringify(request)) {
        cancel('ASSET_REPLY_IDENTITY_MISMATCH'); return;
      }
      const bytes = Uint8Array.from(response.bytes);
      const digest = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))]
        .map(value => value.toString(16).padStart(2, '0')).join('');
      if (pending !== original) return;
      if (bytes.length !== value.asset.byteCount || digest !== value.asset.sha256) {
        cancel('ASSET_BYTES_MISMATCH'); return;
      }
      if (original.target !== value.target || witness !== value || !originalValid(value)
          || performance.now() - original.eventAt > limits.maximumWaitMS) {
        cancel('ORIGINAL_WITNESS_CHANGED_BEFORE_INPUT'); return;
      }
      // Consume BEFORE the sink. Neither attempt/hash nor hide/show revision
      // changes reauthorize this asset. No retry or durable recovery is modeled.
      consumed.add(value.asset.assetID);
      original.phase = 'consumed';
      clearTimeout(original.timeout);
      sinkInvocationCount++;
      await syntheticInput({request, bytes, originalTarget: original.target});
      if (pending !== original) return;
      pending = null;
      record('CONSUMED', 'SYNTHETIC_FIXTURE_INPUT_ONLY', {tokenID: original.tokenID,
        witnessID: value.witnessID, uniqueInput: true});
    } catch {
      if (pending === original) {
        if (original.phase === 'consumed') {
          pending = null; record('UNKNOWN', 'CONSUMED_SINK_RESULT_UNKNOWN', {tokenID: original.tokenID});
        } else cancel('ASSET_REQUEST_FAILED');
      }
    }
  }

  function pointerUp(event) {
    if (!pending || pending.phase !== 'down') return;
    if (!ownedPointer(event) || event.pointerId !== pending.pointerID || event.timeStamp < pending.eventAt) {
      cancel('POINTER_UP_DOES_NOT_MATCH'); return;
    }
    if (!originalValid(pending.witness)) { cancel('ORIGINAL_WITNESS_INVALID_AT_RELEASE'); return; }
    event.preventDefault();
    pending.phase = 'asset';
    void finish(pending);
  }
  function pointerCancel(event) {
    if (pending && event.pointerId === pending.pointerID) cancel('POINTER_CANCEL_OR_CAPTURE_LOST');
  }
  entry.addEventListener('pointerdown', pointerDown);
  window.addEventListener('pointerup', pointerUp, true);
  entry.addEventListener('pointercancel', pointerCancel);
  entry.addEventListener('lostpointercapture', pointerCancel);
  const preserveClick = event => { if (event.target === entry) event.preventDefault(); };
  entry.addEventListener('click', preserveClick);

  return Object.freeze({publishWitness,
    // Comparison model, not actual AppKit/host timing evidence. A page witness
    // cannot attribute an unrelated native event to this document/draft.
    nativeClickWithoutHostACK() {
      record('REFUSED', 'NATIVE_EVENT_HAS_NO_DOCUMENT_ROUTE_OR_HOST_ACK');
      return false;
    },
    snapshot() {
      return copy({captureCount, publicationCount, frozenCount, sinkInvocationCount,
        pending: pending ? {phase: pending.phase, tokenID: pending.tokenID} : null,
        witness: witness ? {witnessID: witness.witnessID, completedAt: witness.completedAt,
          target: witness.target} : null, receipts,
        productionInputAuthority: false, liveInputAuthority: false, productionAdmission: false});
    },
    dispose() {
      cancel('LAB_DISPOSED');
      entry.removeEventListener('pointerdown', pointerDown);
      window.removeEventListener('pointerup', pointerUp, true);
      entry.removeEventListener('pointercancel', pointerCancel);
      entry.removeEventListener('lostpointercapture', pointerCancel);
      entry.removeEventListener('click', preserveClick);
      for (const name of ['blur', 'focus', 'pagehide']) window.removeEventListener(name, boundary);
      document.removeEventListener('visibilitychange', boundary);
    }
  });
};
