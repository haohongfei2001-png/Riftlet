/* Riftlet synthetic Web acceptance integration, 2026-10-27.
 * Derived from the project's real experiment source at 6f4156988f32fa06d4df9f06a43f564b560e0a1d:
 * research/web-attachment-handoff-2026-10-27/src/input/shared-adapter.js,
 * src/observers/{normal-bound-observer,exception-observer}.template.js,
 * src/observers/compare-source-preview-pixels.template.js and the attached classifiers.
 * Narrow observed profile: Chat home, Chinese file-input/progress labels, PNG.
 * This integrated program is NOT the archived program or a new live PASS.
 * No send, composer edits, attachment deletion, network hooks or retry command.
 */
function riftletWebAcceptance(command, native) {
  'use strict';
  const KEY = '__riftletWebAcceptance20261027v1';
  const MAX_BYTES = 8 * 1024 * 1024, MAX_PIXELS = 16 * 1024 * 1024;
  const TARGET_KEYS = ['adapterID', 'surface', 'applicationID', 'sessionID', 'windowID', 'tabID', 'documentID', 'composerID', 'draftGeneration'];
  const sameTarget = (a, b) => !!a && !!b && TARGET_KEYS.every(k => a[k] === b[k]);
  const sameIdentity = (a, b) => !!a && !!b && a.operationID === b.operationID && a.assetID === b.assetID
    && a.attempt === b.attempt && a.assetSHA256 === b.assetSHA256 && sameTarget(a.target, b.target);
  const contextMatches = t => t && ['applicationID', 'sessionID', 'windowID', 'tabID'].every(k => t[k] === native[k]);
  const fail = label => { throw Error(label); };
  const hash = async bytes => [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))]
    .map(n => n.toString(16).padStart(2, '0')).join('');
  const blankObservation = (identity, state = 'invalidated') => ({
    schemaVersion: 1,
    provenance: {source: 'integratedDevelopment', evidenceID: 'W2-integrated-page-20261027'},
    observation: {identity, state, exactImageIdentity: false, belongsToOriginalDraft: false,
      hasError: false, isUploading: false, attachmentAbsent: false, automaticRetryExcluded: false}
  });

  function install() {
    // The archive did not establish arbitrary threads, Work, locales or frames.
    if (location.href !== 'https://chatgpt.com/' || globalThis.top !== globalThis
        || document.visibilityState !== 'visible' || !document.hasFocus()) fail('UNSUPPORTED_TEST_SURFACE');
    if (native.applicationID !== 'com.google.Chrome' || !native.sessionID
        || !/^\d+$/.test(native.windowID) || !/^\d+$/.test(native.tabID)) fail('NATIVE_CONTEXT_REQUIRED');
    // Observed on the local Chinese Home header, 2026-10-27. A legacy
    // account with no explicit mode control is unsupported, not assumed Chat.
    const modeSelector = '[role=group][aria-label="撰写器模式"]';
    const modeGroups = [...document.querySelectorAll(modeSelector)];
    if (modeGroups.length !== 1 || !modeGroups[0].closest('header')) fail('UNPROVEN_CHAT_MODE');
    const modeGroup = modeGroups[0], modeHeader = modeGroup.closest('header');
    const modeButtons = [...modeGroup.querySelectorAll('button[type=button]')];
    const chatButtons = modeButtons.filter(n => n.textContent.trim() === '聊天');
    const workButtons = modeButtons.filter(n => n.textContent.trim() === '工作');
    if (modeButtons.length !== 2 || chatButtons.length !== 1 || workButtons.length !== 1) fail('UNPROVEN_CHAT_MODE');
    const chatMode = chatButtons[0], workMode = workButtons[0];
    const modeMatches = () => {
      const groups = document.querySelectorAll(modeSelector), buttons = modeGroup.querySelectorAll('button[type=button]');
      return groups.length === 1 && groups[0] === modeGroup && modeGroup.isConnected && modeHeader.isConnected
        && modeGroup.closest('header') === modeHeader && chatMode.isConnected && workMode.isConnected
        && modeGroup.contains(chatMode) && modeGroup.contains(workMode)
        && buttons.length === 2 && [...buttons].includes(chatMode) && [...buttons].includes(workMode)
        && chatMode.textContent.trim() === '聊天' && workMode.textContent.trim() === '工作'
        && chatMode.getAttribute('aria-pressed') === 'true' && workMode.getAttribute('aria-pressed') === 'false';
    };
    if (!modeMatches()) fail('UNPROVEN_CHAT_MODE');
    const editors = [...document.querySelectorAll('[contenteditable=true][role=textbox]')];
    if (editors.length !== 1) fail('AMBIGUOUS_COMPOSER');
    const editor = editors[0], form = editor.closest('form');
    const inputs = form ? [...form.querySelectorAll('input[type=file][aria-label="附加文件"]')] : [];
    if (!form || inputs.length !== 1) fail('UNOBSERVED_INPUT_STRUCTURE');
    const input = inputs[0], route = location.href, documentID = crypto.randomUUID();
    const ids = new WeakMap(), operations = new Map();
    let nextNode = 0, invalid = false, sequence = 0;
    const nodeID = n => { if (!ids.has(n)) ids.set(n, 'node-' + (++nextNode)); return ids.get(n); };
    const target = {adapterID: 'chatgpt-web', surface: 'webChat', ...native,
      documentID, composerID: nodeID(editor) + ':' + nodeID(form), draftGeneration: crypto.randomUUID()};
    // Existing attachments are never read beyond node membership or changed.
    // If an original card disappears, conservatively invalidate this draft lease.
    const baseline = [...form.querySelectorAll('[role=button][aria-label]')].filter(c => c.querySelector('img'));
    const valid = () => {
      const currentEditors = document.querySelectorAll('[contenteditable=true][role=textbox]');
      const currentInputs = form.querySelectorAll('input[type=file][aria-label="附加文件"]');
      return !invalid && modeMatches() && location.href === route && document.visibilityState === 'visible' && form.isConnected && editor.isConnected
        && input.isConnected && input.form === form && editor.closest('form') === form && form.contains(input)
        && currentEditors.length === 1 && currentEditors[0] === editor
        && currentInputs.length === 1 && currentInputs[0] === input
        && baseline.every(c => c.isConnected && form.contains(c));
    };
    const tick = () => { if (++sequence > 4096) invalid = true; return sequence; };
    const invalidate = () => {
      invalid = true; tick();
      for (const op of operations.values()) { op.file = null; op.chunks = []; op.proof = null; }
    };
    const markBad = (op, error = false) => {
      // Preserve a previously proved, still-bound attachment's identity when its
      // own card/image reports a late error. Navigation, node replacement and
      // generic invalidation are not failure evidence and cannot mint this ID.
      if (error && op.proof && currentMember(op)
          && op.proof.card === op.card && op.proof.image === op.image
          && sameIdentity(op.proof.identity, op.identity)) {
        op.errorAttachmentID = target.documentID + ':' + nodeID(op.card) + ':' + nodeID(op.image);
      }
      op.invalid = true; op.error ||= error; op.proof = null; op.file = null; op.chunks = [];
    };
    const ownCards = name => [...form.querySelectorAll('[role=button][aria-label]')]
      .filter(c => c.getAttribute('aria-label') === name);
    const currentSource = image => image.currentSrc || image.src;
    const currentMember = op => valid() && !op.invalid && op.card?.isConnected && form.contains(op.card)
      && op.image?.isConnected && op.image.closest('[role=button]') === op.card
      && op.card.getAttribute('aria-label') === op.name && op.image.alt === op.name
      && ownCards(op.name).length === 1;
    const associatedError = card => {
      const refs = [card, ...card.querySelectorAll('[aria-describedby],[aria-labelledby]')]
        .flatMap(e => ['aria-describedby', 'aria-labelledby'].flatMap(k => (e.getAttribute(k) || '').split(/\s+/).filter(Boolean)))
        .map(id => document.getElementById(id)).filter(Boolean);
      const nodes = [card, ...card.querySelectorAll('[role=alert],[data-state],[aria-label]'), ...refs];
      return nodes.some(n => n.getAttribute('role') === 'alert' || /error|failed/i.test(n.getAttribute('data-state') || '')
        || /上传失败|重试|Upload failed|Retry/i.test(n.getAttribute('aria-label') || '')
        || /上传失败|Upload failed/i.test(n.textContent || ''));
    };

    async function pixels(image) {
      const width = image.naturalWidth, height = image.naturalHeight;
      if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width < 1 || height < 1
          || width * height > MAX_PIXELS) fail('UNSUPPORTED_PIXEL_SIZE');
      const canvas = new OffscreenCanvas(width, height);
      const ctx = canvas.getContext('2d', {colorSpace: 'srgb', willReadFrequently: true});
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
      if (op.proofPending || op.proof || !op.fileHashVerified || !op.loaded || !op.ended
          || !currentMember(op) || op.uploading || !op.image.complete) return;
      const source = currentSource(op.image), card = op.card, image = op.image;
      if (!/^data:image\/png;base64,/.test(source) || source.length > Math.ceil(MAX_BYTES * 4 / 3) + 64) return;
      op.proofPending = true;
      const loadSequence = op.loaded, sourceFile = op.file;
      (async () => {
        const previewBytes = Uint8Array.from(atob(source.slice(source.indexOf(',') + 1)), c => c.charCodeAt(0));
        const previewHash = await hash(previewBytes);
        let matched = previewBytes.byteLength === op.bytes && previewHash === op.identity.assetSHA256;
        if (!matched) {
          const original = await decodeOriginal(sourceFile), preview = await pixels(image);
          matched = original.width === preview.width && original.height === preview.height && original.sha256 === preview.sha256;
        }
        // Async proof is bound to the full operation, original nodes/source and
        // final-load sequence. It cannot bless another card or a newer preview.
        if (!currentMember(op) || op.card !== card || op.image !== image || currentSource(image) !== source
            || op.loaded !== loadSequence || op.uploading || !image.complete || associatedError(card)) {
          markBad(op); return;
        }
        if (!matched) { markBad(op); return; }
        op.proof = {identity: op.identity, card, image, source, loadSequence, completed: tick()};
        op.file = null;
      })().catch(() => markBad(op)).finally(() => { op.proofPending = false; });
    }

    function sample(op, eventType = 'query', eventImage = null) {
      if (!valid()) { invalidate(); return; }
      if (op.invalid || !op.committed) return;
      const now = tick(), cards = ownCards(op.name);
      if (cards.length === 0) { if (op.card) markBad(op); return; }
      if (cards.length !== 1 || op.inputCount !== 1) { markBad(op); return; }
      const card = cards[0], images = [...card.querySelectorAll('img')];
      if (images.length !== 1 || images[0].alt !== op.name) { markBad(op); return; }
      const image = images[0];
      if ((op.card && op.card !== card) || (op.image && op.image !== image)) { markBad(op); return; }
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
      if (eventType === 'error' && eventImage === image) { markBad(op, true); return; }
      if (eventType === 'load' && eventImage === image && op.ended && now > op.hundred
          && image.complete && image.naturalWidth > 0 && image.naturalHeight > 0
          && currentSource(image).startsWith('data:image/png;base64,')) {
        // A new load after a proof or a previous final-load event means a new
        // preview generation; it cannot reuse the old proof.
        if (op.loaded) { markBad(op); return; }
        op.loaded = now;
      }
      if (op.proof && currentSource(image) !== op.proof.source) { markBad(op); return; }
      beginProof(op);
    }
    const sampleAll = (type, image) => { for (const op of operations.values()) sample(op, type, image); };
    const containsNode = (container, node) => !!node && (container === node
      || (typeof container.contains === 'function' && container.contains(node)));
    const observer = new MutationObserver(records => {
      // Mutation batches can detach/reinsert nodes or change a source and restore
      // it before the callback. A final snapshot alone would hide that gap.
      let relevant = false;
      for (const record of records) {
        if (containsNode(form, record.target)) relevant = true;
        if (containsNode(modeGroup, record.target)) {
          relevant = true;
          // Observe the changes, not only their final value: Chat -> Work ->
          // Chat within one mutation batch permanently revokes this lease.
          if (record.type === 'characterData' || record.type === 'childList'
              || (record.type === 'attributes' && ['aria-pressed', 'role', 'aria-label', 'type'].includes(record.attributeName)
                && record.oldValue !== record.target.getAttribute(record.attributeName))) invalidate();
        }
        for (const removed of record.removedNodes || []) {
          if ([editor, input, form, modeGroup, modeHeader, chatMode, workMode, ...baseline].some(node => containsNode(removed, node))) {
            invalidate(); relevant = true;
          }
          for (const op of operations.values()) {
            if (containsNode(removed, op.card) || containsNode(removed, op.image)) { markBad(op); relevant = true; }
          }
        }
        for (const op of operations.values()) {
          if (record.type === 'attributes' && ((record.target === op.card && record.attributeName === 'aria-label')
              || (record.target === op.image && record.attributeName === 'alt')
              || (op.loaded && record.target === op.image && ['src', 'srcset'].includes(record.attributeName)))) markBad(op);
          if (op.ended && op.card && containsNode(op.card, record.target)) {
            const changed = [...(record.addedNodes || []), ...(record.removedNodes || [])];
            if (changed.some(node => node.getAttribute?.('role') === 'progressbar'
                || node.querySelector?.('[role=progressbar]'))) markBad(op);
          }
        }
      }
      if (relevant) sampleAll('mutation');
    });
    observer.observe(form, {subtree: true, childList: true, attributes: true, attributeOldValue: true, characterData: true});
    observer.observe(modeGroup, {subtree: true, childList: true, attributes: true, attributeOldValue: true,
      characterData: true, characterDataOldValue: true});
    // An entire form/ancestor can be detached and reinserted. Watch each parent
    // child-list only; avoid observing the rest of the page's subtree or text.
    for (const root of [form, modeGroup]) {
      for (let ancestor = root.parentNode; ancestor; ancestor = ancestor.parentNode) {
        observer.observe(ancestor, {childList: true});
      }
    }
    document.addEventListener('change', event => {
      if (!valid() || event.target !== input || !(event.target instanceof HTMLInputElement)) return;
      for (const file of event.target.files || []) {
        const op = [...operations.values()].find(o => o.name === file.name);
        if (!op) continue; // Other user attachments cannot complete this operation.
        op.inputCount++;
        if (!op.committed || !op.expectingInput || op.inputCount !== 1 || file.size !== op.bytes || file.type !== 'image/png') {
          markBad(op); continue;
        }
        op.inputSequence = tick(); op.file = file;
        file.arrayBuffer().then(hash).then(digest => {
          if (!valid() || op.invalid || digest !== op.identity.assetSHA256 || op.inputCount !== 1) { markBad(op); return; }
          op.fileHashVerified = true; op.hashSequence = tick(); sample(op, 'inputHash');
        }).catch(() => markBad(op));
      }
    }, true);
    for (const type of ['load', 'error']) document.addEventListener(type, event => {
      if (event.target?.tagName === 'IMG') sampleAll(type, event.target);
    }, true);
    for (const type of ['pagehide', 'popstate', 'hashchange']) addEventListener(type, invalidate);
    document.addEventListener('visibilitychange', () => { if (document.visibilityState !== 'visible') invalidate(); });
    const state = {target, valid, invalidate, operations, sample, tick, ownCards, markBad, currentMember,
      currentSource, input, form, nodeID};
    Object.defineProperty(globalThis, KEY, {value: state, configurable: false, writable: false});
    return state;
  }

  let state = globalThis[KEY];
  if (command.action === 'captureTarget') {
    state ||= install();
    if (!state.valid() || !contextMatches(state.target)) fail('TARGET_INVALID');
    return state.target;
  }
  if (command.action === 'validate') {
    return {target: command.target, valid: !!state && state.valid() && contextMatches(state.target)
      && sameTarget(command.target, state.target)};
  }
  const identity = command.identity;
  if (!identity || !sameTarget(identity.target, command.target)) fail('IDENTITY_REQUIRED');
  if (!state || !state.valid() || !contextMatches(state.target) || !sameTarget(identity.target, state.target)) {
    if (command.action === 'observe') return blankObservation(identity);
    fail('TARGET_INVALID');
  }
  const acknowledge = (op, nextChunk) => ({operationID: op.identity.operationID, attempt: op.identity.attempt, nextChunk});
  let op = state.operations.get(identity.operationID);
  if (command.action === 'begin') {
    if (op || state.operations.size >= 32 || !Number.isSafeInteger(identity.attempt) || identity.attempt < 1
        || !/^[a-f0-9]{64}$/.test(identity.assetSHA256)
        || !/^[a-fA-F0-9-]{36}$/.test(identity.operationID) || !/^[a-fA-F0-9-]{36}$/.test(identity.assetID)
        || command.uploadName !== 'riftlet-' + identity.operationID + '.png'
        || command.mediaType !== 'image/png' || !Number.isSafeInteger(command.byteCount)
        || command.byteCount < 8 || command.byteCount > MAX_BYTES || state.ownCards(command.uploadName).length) fail('BEGIN_REFUSED');
    op = {identity, name: command.uploadName, bytes: command.byteCount, chunks: [], nextChunk: 0, received: 0,
      committed: false, invalid: false, error: false, inputCount: 0, fileHashVerified: false,
      inputSequence: 0, started: 0, hundred: 0, ended: 0, loaded: 0, uploading: false, proof: null};
    state.operations.set(identity.operationID, op);
    return acknowledge(op, 0);
  }
  if (!op || !sameIdentity(identity, op.identity)) {
    if (command.action === 'observe') return blankObservation(identity);
    fail('ORIGINAL_OPERATION_REQUIRED');
  }
  if (command.action === 'chunk') {
    if (op.committed || op.invalid || command.chunkIndex !== op.nextChunk
        || typeof command.chunkBase64 !== 'string' || command.chunkBase64.length > 87384
        || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(command.chunkBase64)) fail('CHUNK_REFUSED');
    const bytes = Uint8Array.from(atob(command.chunkBase64), c => c.charCodeAt(0));
    if (!bytes.length || bytes.length > 65536 || op.received + bytes.length > op.bytes) fail('CHUNK_SIZE');
    op.chunks.push(bytes); op.received += bytes.length; op.nextChunk++;
    return acknowledge(op, op.nextChunk);
  }
  if (command.action === 'discard') {
    if (!op.committed) { op.chunks = []; op.invalid = true; }
    return {discarded: !op.committed}; // Never remove an attachment or reset a dispatch tombstone.
  }
  if (command.action === 'commit') {
    if (op.committed || op.invalid || op.received !== op.bytes || command.chunkIndex !== op.nextChunk) fail('COMMIT_REFUSED');
    op.committed = true; // One-shot tombstone precedes every asynchronous step and side effect.
    const bytes = new Uint8Array(op.bytes);
    let offset = 0;
    for (const chunk of op.chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    op.chunks = [];
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (!signature.every((n, i) => bytes[i] === n)) { state.markBad(op); }
    else hash(bytes).then(digest => {
      if (digest !== op.identity.assetSHA256 || !state.valid() || op.invalid
          || document.visibilityState !== 'visible' || !document.hasFocus()
          || !sameTarget(op.identity.target, state.target) || state.ownCards(op.name).length) {
        state.markBad(op); return;
      }
      // From this final lease/identity check through native setter+change there is
      // no await, focus, route change, selector fallback, send or composer edit.
      const file = new File([bytes], op.name, {type: 'image/png'}), transfer = new DataTransfer();
      transfer.items.add(file);
      op.expectingInput = true;
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'files').set.call(state.input, transfer.files);
      state.input.dispatchEvent(new Event('change', {bubbles: true}));
      op.expectingInput = false;
      if (op.inputCount !== 1) state.markBad(op);
      state.sample(op, 'dispatch');
    }).catch(() => state.markBad(op));
  } else if (command.action !== 'observe') fail('UNKNOWN_ACTION');

  state.sample(op);
  const envelope = blankObservation(identity, 'unknown'), observation = envelope.observation;
  observation.belongsToOriginalDraft = state.valid() && sameTarget(identity.target, state.target);
  observation.hasError = op.error;
  observation.isUploading = op.uploading;
  if (!observation.belongsToOriginalDraft || op.invalid) {
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
  if (op.inputCount === 1) observation.state = 'inputTriggered';
  if (op.card && op.image) observation.attachmentID = state.target.documentID + ':' + state.nodeID(op.card) + ':' + state.nodeID(op.image);
  const proof = op.proof;
  if (proof && sameIdentity(proof.identity, identity) && proof.completed > op.loaded && op.loaded > op.hundred
      && op.started && op.ended && op.fileHashVerified && op.inputCount === 1 && state.currentMember(op)
      && proof.card === op.card && proof.image === op.image && proof.source === state.currentSource(op.image)
      && proof.loadSequence === op.loaded && !op.uploading && op.image.complete) {
    observation.state = 'attached'; observation.exactImageIdentity = true;
  }
  return envelope;
}
