/* Riftlet's document-local file handoff. Upload history never licenses new input.
 * Only commit writes a FileList; all other commands are read/staging operations.
 * No message send, editor mutation, attachment removal, request interception,
 * React inspection, prior-file hashing or automatic resubmission exists here.
 */
function riftletWebAcceptance(command, native) {
  'use strict';
  const KEY = '__riftletIndependentFileInput20261104';
  const MAX_BYTES = 8 * 1024 * 1024, MAX_CHUNK_BYTES = 256 * 1024;
  const targetKeys = ['adapterID', 'surface', 'applicationID', 'sessionID', 'windowID', 'tabID',
    'documentID', 'composerID', 'draftGeneration'];
  const fail = code => { throw Error(code); };
  const uuid = value => typeof value === 'string' && /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(value);
  const sameTarget = (a, b) => !!a && !!b && targetKeys.every(k => a[k] === b[k])
    && (a.clickBindingID || null) === (b.clickBindingID || null);
  const sameIdentity = (a, b) => !!a && !!b && a.operationID === b.operationID
    && a.assetID === b.assetID && a.attempt === b.attempt && a.assetSHA256 === b.assetSHA256
    && sameTarget(a.target, b.target);
  const contextMatches = target => target && ['applicationID', 'sessionID', 'windowID', 'tabID']
    .every(key => target[key] === native[key]);
  const route = () => {
    const url = new URL(location.href);
    if (url.protocol !== 'https:' || !['chatgpt.com', 'chat.openai.com'].includes(url.hostname)) fail('PAGE_ROUTE_UNSUPPORTED');
    return url.origin + url.pathname;
  };
  const blocked = node => {
    for (let current = node; current && current.nodeType === 1; current = current.parentElement) {
      if (current.inert || current.hasAttribute('inert') || current.getAttribute('aria-disabled') === 'true') return true;
    }
    return false;
  };
  const visible = node => {
    if (!node.isConnected || node.hidden || node.closest('[hidden],[aria-hidden="true"]')) return false;
    const style = getComputedStyle(node);
    return style.display !== 'none' && style.visibility !== 'hidden' && style.visibility !== 'collapse'
      && node.getClientRects().length > 0;
  };
  const usableInput = input => input.isConnected && input.type === 'file' && !input.disabled
    && !input.matches(':disabled') && !blocked(input)
    && (!input.accept || input.accept.split(',').some(value =>
      ['image/*', 'image/png', '.png', '*/*', '*'].includes(value.trim().toLowerCase())));
  function composer() {
    if (globalThis.top !== globalThis) fail('PAGE_NOT_TOP_LEVEL');
    route();
    const editors = [...document.querySelectorAll('#prompt-textarea,[contenteditable="true"][role="textbox"],textarea')]
      .filter(node => visible(node) && !blocked(node) && !node.disabled && !node.readOnly
        && (node.isContentEditable || node.tagName === 'TEXTAREA'));
    const candidates = [];
    for (const editor of editors) {
      let form = editor.closest('form') || editor.closest('[data-chatgpt-composer]');
      if (!form) {
        // Div-based composers are allowed when one local ancestor actually owns
        // both the editor and its attachment control. Never use a global picker.
        for (let node = editor.parentElement; node && node !== document.body; node = node.parentElement) {
          if (node.querySelector('input[type="file"]')) { form = node; break; }
        }
      }
      if (!form || blocked(form)) continue;
      const inputs = [...document.querySelectorAll('input[type="file"]')]
        .filter(input => (input.form === form || form.contains(input)) && usableInput(input));
      if (inputs.length > 1) fail('ATTACHMENT_INPUT_UNAVAILABLE');
      if (inputs.length === 1) candidates.push({form, editor, input: inputs[0]});
    }
    if (!editors.length) fail('EDITOR_UNAVAILABLE');
    if (candidates.length > 1) fail('AMBIGUOUS_COMPOSER');
    if (!candidates.length) fail('ATTACHMENT_INPUT_UNAVAILABLE');
    return candidates[0];
  }
  const blank = (identity, state = 'unknown') => ({schemaVersion: 2,
    provenance: {source: 'integratedDevelopment', evidenceID: 'independent-file-input-20261104-v14'},
    observation: {identity, state, exactImageIdentity: false, belongsToOriginalDraft: false,
      hasError: false, isUploading: false, attachmentAbsent: false, automaticRetryExcluded: false}});
  let registry = globalThis[KEY];
  if (!registry && command.action === 'captureTarget') {
    // Old upload observers remain untouched. None of their state is consulted.
    registry = {documentID: crypto.randomUUID(), root: document.documentElement, current: null,
      operations: new Map(), pins: new Map(), nodeIDs: new WeakMap(), nextNode: 0,
      sequence: 0, navigation: 0, path: route(), busy: new WeakSet(), files: new WeakMap()};
    Object.defineProperty(globalThis, KEY, {value: registry});
    const state = registry;
    const noteNavigation = () => {
      let next;
      try { next = route(); } catch { next = null; }
      if (next !== state.path) { state.path = next; state.navigation++; }
    };
    // Only actual pathname changes invalidate a saved conversation. This never
    // examines React, model parameters, upload state or previous generations.
    for (const name of ['pushState', 'replaceState']) {
      const original = history[name];
      try {
        history[name] = function () {
          const result = Reflect.apply(original, this, arguments); noteNavigation(); return result;
        };
      } catch { /* Direct route/node checks still protect every input. */ }
    }
    globalThis.addEventListener('popstate', noteNavigation);
    // Optional current-file preview attribution. A filename-labelled card works
    // without this hook. No network API or Request/body is inspected or changed.
    if (typeof URL.createObjectURL === 'function') {
      const original = URL.createObjectURL;
      try {
        URL.createObjectURL = function (file) {
          const value = Reflect.apply(original, this, arguments);
          const operation = state.files.get(file);
          if (operation && !operation.start) operation.urls.add(value);
          return value;
        };
      } catch { /* Preview attribution is optional, never an input permit. */ }
    }
  }
  const nodeID = node => {
    if (!registry.nodeIDs.has(node)) registry.nodeIDs.set(node, 'node-' + (++registry.nextNode));
    return registry.nodeIDs.get(node);
  };
  const tick = () => ++registry.sequence;
  function valid(binding) {
    try {
      if (!binding || registry.root !== document.documentElement || binding.navigation !== registry.navigation
          || binding.route !== route() || !contextMatches(binding.target)) return false;
      const current = composer();
      return current.form === binding.form && current.editor === binding.editor && current.input === binding.input;
    } catch { return false; }
  }
  function bindingFor(target) {
    if (!registry || !contextMatches(target)) return null;
    if (target?.clickBindingID) {
      const pin = registry.pins.get(target.clickBindingID);
      return pin && sameTarget(pin.target, target) ? pin.binding : null;
    }
    return sameTarget(registry.current?.target, target) ? registry.current : null;
  }
  function attachmentNodes(binding) {
    return [...binding.form.querySelectorAll('[data-file-name],[role="button"][aria-label],img[alt],img[src],[title]')]
      .filter(node => node !== binding.editor && !binding.editor.contains(node) && node !== binding.input);
  }
  function sample(op) {
    if (op.start || !op.changeReturned || !valid(op.binding)) return;
    const hasPreview = node => (node.tagName === 'IMG' && !!node.getAttribute('src')?.trim())
      || [...node.querySelectorAll('img[src]')].some(image => !!image.getAttribute('src')?.trim())
      || !!node.querySelector('progress,[role="progressbar"]');
    const hasError = node => {
      const card = node.closest('[data-file-name],[role="button"]') || node;
      const errors = '[role="alert"],[data-state="error"],[data-state="failed"]';
      return !!node.closest(errors) || !!card.querySelector(errors);
    };
    const matches = attachmentNodes(op.binding).filter(node => !op.baseline.has(node) && node.isConnected
      && hasPreview(node) && !hasError(node)
      && (['data-file-name', 'aria-label', 'title', 'alt'].some(key => node.getAttribute(key) === op.name)
        || (node.tagName === 'IMG' && op.urls.has(node.getAttribute('src')))));
    if (!matches.length) return;
    // A named card and its own img are one accepted attachment, not ambiguity.
    const roots = matches.filter(node => !matches.some(other => other !== node && other.contains(node)));
    if (roots.length !== 1) return;
    const accepted = roots[0];
    op.attachmentID = registry.documentID + ':' + nodeID(accepted);
    op.start = {version: 1, signal: 'attachmentAccepted', evidenceID: crypto.randomUUID(), inputCount: 1,
      inputSequence: op.inputSequence, startSequence: tick(), previousProgress: 0, currentProgress: 0,
      inputObservedAtMS: op.inputTime, startObservedAtMS: Math.max(op.inputTime, performance.now())};
    // This handoff is finished. No load/progress/COMPLETE watcher owns resources.
    op.baseline.clear(); op.urls.clear();
  }
  function observe(op) {
    sample(op);
    const result = blank(op.identity), item = result.observation;
    item.belongsToOriginalDraft = valid(op.binding);
    if (op.retirement) {
      result.schemaVersion = 3;
      item.state = 'invalidated';
      item.preInputRetirement = {version: 1, invocationID: op.invocationID, commitInvoked: true,
        commitWorkSettled: true, irreversiblyRetired: true, inputSideEffectEntered: false, inputCount: 0,
        reason: op.retirement};
      return result;
    }
    if (op.changeReturned) item.state = 'inputTriggered';
    if (op.start) {
      // A past positive handoff remains true if a later input rerenders cards.
      // This is an immutable acceptance fact, not a current upload-status claim.
      item.state = 'uploadStarted'; item.belongsToOriginalDraft = true;
      item.attachmentID = op.attachmentID; item.exactImageIdentity = true;
      item.uploadStart = {...op.start};
    }
    return result;
  }
  if (command.action === 'captureTarget') {
    if (native.applicationID !== 'com.google.Chrome' || !native.sessionID
        || !native.windowID || !native.tabID) fail('NATIVE_CONTEXT_REQUIRED');
    const parts = composer();
    if (!valid(registry.current)) {
      registry.current = {...parts, route: route(), navigation: registry.navigation,
        target: {adapterID: 'chatgpt-web', surface: 'webChat', ...native,
          documentID: registry.documentID, composerID: nodeID(parts.editor) + ':' + nodeID(parts.form),
          draftGeneration: crypto.randomUUID()}};
    }
    return registry.current.target;
  }
  if (command.action === 'pinTarget') {
    const binding = bindingFor(command.target);
    if (!valid(binding) || !uuid(command.clickBindingID) || registry.pins.has(command.clickBindingID)) fail('TARGET_INVALID');
    const target = {...binding.target, clickBindingID: command.clickBindingID};
    registry.pins.set(command.clickBindingID, {binding, target, operationID: null});
    return target;
  }
  const binding = bindingFor(command.target);
  if (command.action === 'validate') return {target: command.target, valid: valid(binding)};
  const identity = command.identity;
  if (!identity || !sameTarget(identity.target, command.target)) fail('TARGET_INVALID');
  const acknowledgement = (op, nextChunk) => ({operationID: op.identity.operationID, attempt: op.identity.attempt, nextChunk});
  let op = registry?.operations.get(identity.operationID);
  if (command.action === 'begin') {
    if (!valid(binding)) fail('TARGET_INVALID');
    if (op || !uuid(identity.operationID) || !uuid(identity.assetID) || !uuid(command.invocationID)
        || !Number.isSafeInteger(identity.attempt) || identity.attempt < 1 || !/^[a-f0-9]{64}$/.test(identity.assetSHA256)
        || command.uploadName !== 'riftlet-' + identity.operationID + '.png' || command.mediaType !== 'image/png'
        || !Number.isSafeInteger(command.byteCount) || command.byteCount < 8 || command.byteCount > MAX_BYTES) fail('BEGIN_REFUSED');
    const pin = identity.target.clickBindingID && registry.pins.get(identity.target.clickBindingID);
    if (pin && pin.operationID) fail('CLICK_PIN_SPENT');
    if (pin) pin.operationID = identity.operationID;
    op = {identity: JSON.parse(JSON.stringify(identity)), invocationID: command.invocationID, binding,
      name: command.uploadName, size: command.byteCount, chunks: [], received: 0, nextChunk: 0,
      committed: false, discarded: false, inputCount: 0, changeReturned: false, retirement: null,
      baseline: new Set(), urls: new Set(), start: null};
    registry.operations.set(identity.operationID, op);
    return acknowledgement(op, 0);
  }
  if (!op || !sameIdentity(op.identity, identity)) {
    if (command.action === 'observe') return blank(identity, 'invalidated');
    fail('ORIGINAL_OPERATION_REQUIRED');
  }
  if (command.action === 'observe') return observe(op);
  if (command.invocationID !== op.invocationID) fail('INVOCATION_MISMATCH');
  if (command.action === 'discard') {
    if (!op.committed) { op.chunks = []; op.discarded = true; }
    return {discarded: !op.committed, inputCount: op.inputCount};
  }
  if (command.action === 'chunk') {
    if (op.committed || op.discarded || command.chunkIndex !== op.nextChunk
        || typeof command.chunkBase64 !== 'string' || command.chunkBase64.length > 4 * Math.ceil(MAX_CHUNK_BYTES / 3)
        || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(command.chunkBase64)) fail('CHUNK_REFUSED');
    const bytes = Uint8Array.from(atob(command.chunkBase64), character => character.charCodeAt(0));
    if (!bytes.length || bytes.length > MAX_CHUNK_BYTES || op.received + bytes.length > op.size) fail('CHUNK_REFUSED');
    op.chunks.push(bytes); op.received += bytes.length; op.nextChunk++;
    return acknowledgement(op, op.nextChunk);
  }
  if (command.action !== 'commit') fail('UNKNOWN_ACTION');
  if (op.committed || op.discarded || op.received !== op.size || command.chunkIndex !== op.nextChunk) fail('COMMIT_REFUSED');
  op.committed = true; // Once-only before every possible file-input side effect.
  const retire = reason => { op.chunks = []; op.retirement = reason; return observe(op); };
  if (registry.busy.has(op.binding.input)) return retire('inputExecutionBusy');
  if (!valid(op.binding)) return retire('targetInvalidBeforeInput');
  const bytes = new Uint8Array(op.size); let offset = 0;
  for (const chunk of op.chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  op.chunks = [];
  if (![137, 80, 78, 71, 13, 10, 26, 10].every((value, index) => bytes[index] === value)) return retire('invalidPNGSignature');
  let file, transfer, setter;
  try {
    file = new File([bytes], op.name, {type: 'image/png'});
    transfer = new DataTransfer(); transfer.items.add(file);
    setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'files').set;
    if (typeof setter !== 'function') return retire('inputPreparationFailed');
  } catch { return retire('inputPreparationFailed'); }
  op.baseline = new Set(attachmentNodes(op.binding));
  registry.files.set(file, op);
  const input = op.binding.input;
  registry.busy.add(input);
  try {
    op.inputCount = 1; op.inputSequence = tick(); op.inputTime = performance.now();
    Reflect.apply(setter, input, [transfer.files]);
    input.dispatchEvent(new Event('change', {bubbles: true}));
    op.changeReturned = true;
  } catch {
    // A throwing setter/event can already have changed the control. Preserve
    // this operation as uncertain; never retry, clear, or restore its FileList.
  } finally {
    registry.busy.delete(input);
  }
  return observe(op);
}
