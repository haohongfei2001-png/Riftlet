/* Riftlet's document-local file handoff. Upload history never licenses new input.
 * Only commit opens an attachment entry or writes a FileList. Target capture
 * does not require the application to have mounted its picker yet.
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
    // Restrict the product to ChatGPT, without a whitelist of conversation or
    // Project paths. A different service's editor is not an attachment target.
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
  // accept is a browser chooser hint, not permission to call the application's
  // file handler. Hidden/portalled inputs and unfamiliar accept strings work.
  const usableInput = input => input?.isConnected && input.type === 'file' && !input.disabled
    && !input.matches(':disabled') && !blocked(input) && !input.webkitdirectory;
  const description = node => ['aria-label', 'title', 'data-testid', 'id', 'name']
    .map(key => node.getAttribute(key) || '').join(' ') + ' ' + (node.textContent || '');
  const attachmentWords = /attach|upload|add.{0,20}(?:file|photo|image)|choose.{0,12}file|附件|上传|添加.{0,8}(?:文件|照片|图片)|选择文件/i;
  const destructiveWords = /\b(?:send|submit|remove|delete)\b|发送|提交|移除|删除/i;
  const localFileWords = /upload|from.{0,12}(?:computer|device)|add.{0,20}(?:file|photo|image)|choose.{0,12}file|上传|本地|添加.{0,8}(?:文件|照片|图片)|选择文件/i;
  const cloudFileWords = /google drive|onedrive|dropbox|sharepoint|连接|云盘|网盘/i;
  const controls = root => [...root.querySelectorAll('button,[role="button"],[role="menuitem"],label')];
  const usableControl = node => visible(node) && !blocked(node) && !node.disabled
    && !node.matches(':disabled') && !destructiveWords.test(description(node));
  const editorNodes = () => [...document.querySelectorAll('#prompt-textarea,[contenteditable],[role="textbox"],textarea')]
    .filter(node => visible(node)
      && (node.isContentEditable || node.tagName === 'TEXTAREA' || node.id === 'prompt-textarea'
        || node.getAttribute('role') === 'textbox'))
    .filter((node, index, list) => !list.some(other => other !== node && other.contains(node)));
  function composer() {
    if (globalThis.top !== globalThis) fail('PAGE_NOT_TOP_LEVEL');
    route();
    const editors = editorNodes();
    if (!editors.length) fail('EDITOR_UNAVAILABLE');
    const score = node => (node.id === 'prompt-textarea' ? 1000 : 0)
      + (node === document.activeElement || node.contains(document.activeElement) ? 200 : 0)
      + (node.getAttribute('role') === 'textbox' ? 20 : 0)
      + (/message|prompt|ask|消息|提问/i.test(description(node)) ? 40 : 0)
      + (node.closest('main,[role="main"]') ? 10 : 0);
    const ranked = editors.map(editor => ({editor, score: score(editor)})).sort((a, b) => b.score - a.score);
    // Multiple pickers never reject a target. Only genuinely indistinguishable
    // live editors need disambiguation to avoid choosing a different draft.
    if (ranked.length > 1 && ranked[0].score === ranked[1].score) fail('AMBIGUOUS_COMPOSER');
    const editor = ranked[0].editor;
    let form = editor.closest('form,[data-chatgpt-composer],[data-testid="composer"]');
    if (!form) {
      form = editor.parentElement;
      for (let node = editor.parentElement; node && node !== document.body; node = node.parentElement) {
        if (editors.some(other => other !== editor && node.contains(other))) break;
        if (controls(node).some(control => attachmentWords.test(description(control))
            || /composer.*(?:plus|attach)/i.test(description(control)))) { form = node; break; }
      }
    }
    return {form: form || editor, editor, input: null};
  }
  const blank = (identity, state = 'unknown') => ({schemaVersion: 2,
    provenance: {source: 'integratedDevelopment', evidenceID: 'attachment-entry-20261105-v15'},
    observation: {identity, state, exactImageIdentity: false, belongsToOriginalDraft: false,
      hasError: false, isUploading: false, attachmentAbsent: false, automaticRetryExcluded: false}});
  let registry = globalThis[KEY];
  if (!registry && command.action === 'captureTarget') {
    // Old upload observers remain untouched. None of their state is consulted.
    registry = {documentID: crypto.randomUUID(), root: document.documentElement, current: null,
      operations: new Map(), nodeIDs: new WeakMap(), nextNode: 0,
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
  function sameDraft(binding) {
    try {
      if (!binding || registry.root !== document.documentElement || binding.navigation !== registry.navigation
          || binding.route !== route() || !contextMatches(binding.target)) return false;
      return binding.form.isConnected && binding.editor.isConnected && binding.form.contains(binding.editor);
    } catch { return false; }
  }
  function validDraft(binding) {
    // The original editor is the destination. Opening its menu can move focus
    // or add search textboxes; reranking editors here would reject that very
    // interaction or switch to the menu's textbox.
    return sameDraft(binding);
  }
  function entryControls(binding) {
    const candidates = controls(document).filter(control => usableControl(control)
      && !binding.editor.contains(control) && !control.closest('[data-file-name]'));
    const local = control => binding.form !== document.body && binding.form.contains(control);
    const names = control => description(control);
    return candidates.filter(control => (attachmentWords.test(names(control))
        || /composer.*(?:plus|attach)|(?:plus|attach).*composer/i.test(names(control))
        || (local(control) && control.getAttribute('aria-haspopup') === 'menu'
          && /^\s*\+\s*$/.test(control.textContent || '')))
      && !cloudFileWords.test(names(control)) && !control.closest('[role="menu"],[role="dialog"]'))
      .filter(control => local(control) || /composer.*(?:plus|attach)/i.test(names(control))
        || (binding.editor.id && (control.getAttribute('aria-controls') || '').split(/\s+/).includes(binding.editor.id))
        || (binding.form.parentElement && binding.form.parentElement !== document.body
          && binding.form.parentElement.contains(control) && !control.closest('form,aside,nav,header')))
      .sort((a, b) => Number(local(b)) - Number(local(a)));
  }
  function relatedInputs(control) {
    const found = new Set([...control.querySelectorAll('input[type="file"]')]);
    for (const key of ['for', 'aria-controls', 'aria-owns']) {
      for (const id of (control.getAttribute(key) || '').split(/\s+/).filter(Boolean)) {
        const node = document.getElementById(id);
        if (node?.type === 'file') found.add(node);
        else if (node) for (const input of node.querySelectorAll('input[type="file"]')) found.add(input);
      }
    }
    return [...found].filter(usableInput);
  }
  function directInput(binding) {
    const inputs = [...document.querySelectorAll('input[type="file"]')].filter(usableInput);
    const entries = entryControls(binding), linked = new Set(entries.flatMap(relatedInputs));
    if (linked.size === 1) return [...linked][0];
    // With an actual attachment entry, let that entry identify its input.
    // Even the only input (or the one with image/*) can be an avatar picker;
    // containment/accept/uniqueness must not override the application's route.
    if (entries.length) return null;
    const local = inputs.filter(input => binding.form !== document.body
      && (binding.form.contains(input) || input.form === binding.form));
    if (local.length === 1) return local[0];
    return null;
  }
  function preserveSelection(binding) {
    if (binding.editor.tagName === 'TEXTAREA') {
      const editor = binding.editor, value = editor.value, start = editor.selectionStart,
        end = editor.selectionEnd, direction = editor.selectionDirection, active = document.activeElement;
      return () => {
        if (!sameDraft(binding) || editor.value !== value || !Number.isInteger(start) || !Number.isInteger(end)) return;
        if (active === editor) editor.focus?.({preventScroll: true});
        editor.setSelectionRange?.(start, end, direction);
      };
    }
    const selection = document.getSelection?.();
    if (!selection?.rangeCount || !binding.editor.contains(selection.anchorNode)
        || !binding.editor.contains(selection.focusNode)) return () => {};
    const saved = {anchor: selection.anchorNode, focus: selection.focusNode,
      anchorOffset: selection.anchorOffset, focusOffset: selection.focusOffset,
      text: binding.editor.textContent, active: document.activeElement};
    return () => {
      if (!sameDraft(binding) || binding.editor.textContent !== saved.text
          || !binding.editor.contains(saved.anchor) || !binding.editor.contains(saved.focus)) return;
      const current = document.getSelection?.();
      // The caller suppresses restoration after trusted user interaction. A
      // menu can collapse selection inside the editor as well as move it out.
      if (current?.anchorNode === saved.anchor && current.focusNode === saved.focus
          && current.anchorOffset === saved.anchorOffset && current.focusOffset === saved.focusOffset) return;
      if (saved.active === binding.editor) binding.editor.focus?.({preventScroll: true});
      current?.setBaseAndExtent?.(saved.anchor, saved.anchorOffset, saved.focus, saved.focusOffset);
    };
  }
  async function discoverThroughEntry(binding, deadline) {
    const inputsBeforeEntry = new Set(document.querySelectorAll('input[type="file"]'));
    const controlsBeforeEntry = controls(document);
    const beforeMenus = new Set([...document.querySelectorAll('[role="menu"],[role="dialog"]')].filter(visible));
    const invoked = new Set(), captured = new Set(), createdByEntry = new Set(), ownedMenus = new Set();
    const restoreSelection = preserveSelection(binding), restores = [];
    let entryInvoked = false, entryFailed = false, userInterrupted = false, handedOff = false, lastActivation = 0;
    let activating = 0, discovering = true;
    const finishUI = () => {
      if (userInterrupted) return;
      const menu = [...ownedMenus].find(visible);
      if (menu && typeof KeyboardEvent === 'function') {
        try { (document.activeElement && menu.contains(document.activeElement) ? document.activeElement : menu)
          .dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', code: 'Escape', bubbles: true, cancelable: true})); } catch { /* no file side effect */ }
      }
      restoreSelection();
    };
    const handoff = (input, path) => { handedOff = true; return {input, path, finishUI}; };
    // Follow the application's actual input invocation while suppressing ONLY
    // the OS file chooser. We do not synthesize DOM inputs or use React internals.
    const capture = input => {
      if (input?.type !== 'file') return false;
      // Async callbacks scheduled by OUR entry retain that call context. A
      // timer belonging to an avatar/project picker must keep its own behavior.
      const linked = [...invoked].some(control => relatedInputs(control).includes(input));
      const explicitlyElsewhere = !linked && (editorNodes().some(editor => editor !== binding.editor
          && input.form?.contains(editor))
        || controlsBeforeEntry.some(control => !invoked.has(control)
          && !binding.form.contains(control) && !entryControls(binding).includes(control)
          && relatedInputs(control).includes(input)));
      // Native async/await continuations do not call Promise.prototype.then.
      // Their actual invocation of a NEW picker after our entry activation is
      // also an executable route. Callback ancestry is not an upload permit.
      // Existing unrelated pickers and explicitly foreign controls stay out.
      const newInvokedPicker = entryInvoked && !inputsBeforeEntry.has(input) && !explicitlyElsewhere;
      const responsible = activating > 0 || (discovering && !userInterrupted
        && sameDraft(binding) && (linked || newInvokedPicker));
      if (!responsible) return false;
      if (discovering && !userInterrupted && sameDraft(binding) && Date.now() < deadline) captured.add(input);
      // A late callback of our cancelled/finished entry may not open a chooser.
      // It also cannot submit a File or resurrect the retired operation.
      return true;
    };
    const userInteraction = event => { if (event.isTrusted) userInterrupted = true; };
    const patch = (prototype, key, restoreInto = restores) => {
      const descriptor = Object.getOwnPropertyDescriptor(prototype, key);
      if (!descriptor || typeof descriptor.value !== 'function') return;
      const replacement = function () {
        if (capture(this)) {
          if (key === 'click') {
            // Keep the application's input click handlers (including its own
            // picker reset/render), cancelling only the native chooser default.
            const preventChooser = event => event.preventDefault();
            this.addEventListener('click', preventChooser, true);
            try { return Reflect.apply(descriptor.value, this, arguments); }
            finally { this.removeEventListener('click', preventChooser, true); }
          }
          return;
        }
        return Reflect.apply(descriptor.value, this, arguments);
      };
      Object.defineProperty(prototype, key, {...descriptor, value: replacement});
      restoreInto.push(() => {
        if (Object.getOwnPropertyDescriptor(prototype, key)?.value === replacement)
          Object.defineProperty(prototype, key, descriptor);
      });
    };
    const stopChooser = event => {
      const node = event.target;
      if (capture(node)) { event.preventDefault(); return; }
      const label = node?.closest?.('label');
      const input = label && (label.control || relatedInputs(label)[0]);
      if (input?.type === 'file' && capture(input)) event.preventDefault();
    };
    const activate = callback => {
      const temporary = [];
      const inputsBeforeCall = new Set(document.querySelectorAll('input[type="file"]'));
      activating++;
      try {
        if (!discovering) {
          patch(HTMLElement.prototype, 'click', temporary);
          patch(HTMLInputElement.prototype, 'click', temporary);
          patch(HTMLInputElement.prototype, 'showPicker', temporary);
          document.addEventListener('click', stopChooser, true);
          temporary.push(() => document.removeEventListener('click', stopChooser, true));
        }
        // Track only callbacks scheduled while running this attachment entry.
        // Restore APIs before yielding; unrelated timers/promises are untouched.
        for (const name of ['setTimeout', 'queueMicrotask', 'requestAnimationFrame']) {
          const original = globalThis[name];
          if (typeof original !== 'function') continue;
          const wrapped = function (fn, ...args) {
            return Reflect.apply(original, this, [typeof fn === 'function'
              ? function (...values) { return activate(() => Reflect.apply(fn, this, values)); } : fn, ...args]);
          };
          globalThis[name] = wrapped;
          temporary.push(() => { if (globalThis[name] === wrapped) globalThis[name] = original; });
        }
        const originalThen = Promise.prototype.then;
        const wrappedThen = function (success, failure) {
          const wrap = fn => typeof fn === 'function' ? function (...args) {
            return activate(() => Reflect.apply(fn, this, args));
          } : fn;
          return Reflect.apply(originalThen, this, [wrap(success), wrap(failure)]);
        };
        Promise.prototype.then = wrappedThen;
        temporary.push(() => { if (Promise.prototype.then === wrappedThen) Promise.prototype.then = originalThen; });
        return callback();
      } finally {
        if (discovering && !userInterrupted && sameDraft(binding)) {
          for (const input of document.querySelectorAll('input[type="file"]'))
            if (!inputsBeforeCall.has(input)) createdByEntry.add(input);
        }
        for (const restore of temporary.reverse()) restore();
        activating--;
      }
    };
    const choose = values => {
      const inputs = [...new Set(values)].filter(usableInput);
      if (inputs.length === 1) return inputs[0];
      return null;
    };
    try {
      patch(HTMLElement.prototype, 'click');
      patch(HTMLInputElement.prototype, 'click');
      patch(HTMLInputElement.prototype, 'showPicker');
      document.addEventListener('click', stopChooser, true);
      document.addEventListener('pointerdown', userInteraction, true);
      document.addEventListener('keydown', userInteraction, true);
      while (Date.now() < deadline) {
        if (!validDraft(binding)) return {reason: 'targetInvalidBeforeInput'};
        if (userInterrupted) return {reason: 'attachmentEntryFailed'};
        const invokedInput = choose(captured);
        if (invokedInput) return handoff(invokedInput, 'attachmentEntry');
        if (captured.size > 1) return {reason: 'attachmentInputAmbiguous'};
        const direct = directInput(binding);
        if (direct) return handoff(direct, entryInvoked ? 'attachmentEntry' : 'direct');
        const linkedNow = choose([...invoked].flatMap(relatedInputs));
        if (linkedNow) return handoff(linkedNow, 'attachmentEntry');
        const created = choose(createdByEntry);
        if (created) return handoff(created, 'attachmentEntry');
        for (const menu of document.querySelectorAll('[role="menu"],[role="dialog"]'))
          if (visible(menu) && !beforeMenus.has(menu)) ownedMenus.add(menu);
        const menuChoices = [...ownedMenus].flatMap(controls).filter(control => usableControl(control)
          && localFileWords.test(description(control))
          && !cloudFileWords.test(description(control)));
        const next = menuChoices.find(control => !invoked.has(control))
          || ((!entryInvoked || Date.now() - lastActivation >= 200)
            && entryControls(binding).find(control => !invoked.has(control)));
        if (next) {
          invoked.add(next); entryInvoked = true; lastActivation = Date.now();
          try { activate(() => {
            // Menu primitives commonly open on pointerdown, while ordinary
            // upload buttons open on click. This is the normal activation
            // sequence, with only the eventual native chooser intercepted.
            if (typeof PointerEvent === 'function') {
              next.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true, cancelable: true,
                button: 0, buttons: 1, pointerId: 1, pointerType: 'mouse', isPrimary: true}));
              next.dispatchEvent(new PointerEvent('pointerup', {bubbles: true, cancelable: true,
                button: 0, buttons: 0, pointerId: 1, pointerType: 'mouse', isPrimary: true}));
            }
            next.click();
          }); } catch { entryFailed = true; }
          // Let framework updates/microtasks mount their real input or menu.
          await new Promise(resolve => setTimeout(resolve, 25));
          continue;
        }
        if (!entryInvoked) return {reason: 'attachmentEntryUnavailable'};
        await new Promise(resolve => setTimeout(resolve, 25));
      }
      return {reason: captured.size > 1 ? 'attachmentInputAmbiguous'
        : entryFailed ? 'attachmentEntryFailed' : 'attachmentInputNotCreated'};
    } catch {
      return {reason: 'attachmentEntryFailed'};
    } finally {
      discovering = false;
      document.removeEventListener('click', stopChooser, true);
      document.removeEventListener('pointerdown', userInteraction, true);
      document.removeEventListener('keydown', userInteraction, true);
      for (const restore of restores.reverse()) restore();
      // A menu may own the discovered input. Close it only AFTER setter/change;
      // closing it here would unmount that valid input before the handoff.
      if (!handedOff) finishUI();
    }
  }
  function bindingFor(target) {
    if (!registry || !contextMatches(target)) return null;
    return sameTarget(registry.current?.target, target) ? registry.current : null;
  }
  function attachmentNodes(binding) {
    // Attachment cards can also be portalled outside the editor's form. The
    // current file's unique filename/blob and pre-input baseline bind START;
    // containment in a guessed form is not an acceptance prerequisite.
    return [...document.querySelectorAll('[data-file-name],[role="button"],button,img[alt],img[src],[title]')]
      .filter(node => node !== binding.editor && !binding.editor.contains(node) && node !== binding.input
        && (!node.closest('[role="menu"],[role="dialog"]')
          || node.closest('[role="dialog"]')?.contains(binding.editor)));
  }
  function sample(op) {
    // The app may disable or remove its picker after accepting this file.
    // Observing that handoff needs the original draft, not another input slot.
    if (op.start || !op.changeReturned || !sameDraft(op.binding)) return;
    const hasPreview = node => (node.tagName === 'IMG' && !!node.getAttribute('src')?.trim())
      || [...node.querySelectorAll('img[src]')].some(image => !!image.getAttribute('src')?.trim())
      || !!node.querySelector('progress,[role="progressbar"]');
    const hasError = node => {
      const card = node.closest('[data-file-name],[role="button"],button') || node;
      const errors = '[role="alert"],[data-state="error"],[data-state="failed"]';
      return !!node.closest(errors) || !!card.querySelector(errors);
    };
    const filename = new RegExp('(^|[^a-zA-Z0-9_.-])' + op.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '($|[^a-zA-Z0-9_.-])');
    const named = node => ['data-file-name', 'aria-label', 'title', 'alt'].some(key => filename.test(node.getAttribute(key) || ''))
      || ((node.hasAttribute('data-file-name') || node.getAttribute('role') === 'button' || node.tagName === 'BUTTON')
        && filename.test(node.textContent || ''));
    const matches = attachmentNodes(op.binding).filter(node => !op.baseline.has(node) && node.isConnected
      && hasPreview(node) && !hasError(node)
      && (named(node)
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
    item.belongsToOriginalDraft = sameDraft(op.binding);
    item.inputExecutionPending = op.executionPending === true;
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
    if (!validDraft(registry.current) || registry.current.editor !== parts.editor) {
      registry.current = {...parts, route: route(), navigation: registry.navigation,
        target: {adapterID: 'chatgpt-web', surface: 'webChat', ...native,
          documentID: registry.documentID, composerID: nodeID(parts.editor) + ':' + nodeID(parts.form),
          draftGeneration: crypto.randomUUID()}};
    }
    return registry.current.target;
  }
  const binding = bindingFor(command.target);
  if (command.action === 'validate') return {target: command.target, valid: validDraft(binding)};
  const identity = command.identity;
  if (!identity || !sameTarget(identity.target, command.target)) fail('TARGET_INVALID');
  const acknowledgement = (op, nextChunk) => ({operationID: op.identity.operationID, attempt: op.identity.attempt, nextChunk});
  let op = registry?.operations.get(identity.operationID);
  if (command.action === 'begin') {
    if (!validDraft(binding)) fail('TARGET_INVALID');
    if (op || !uuid(identity.operationID) || !uuid(identity.assetID) || !uuid(command.invocationID)
        || !Number.isSafeInteger(identity.attempt) || identity.attempt < 1 || !/^[a-f0-9]{64}$/.test(identity.assetSHA256)
        || command.uploadName !== 'riftlet-' + identity.operationID + '.png' || command.mediaType !== 'image/png'
        || !Number.isSafeInteger(command.byteCount) || command.byteCount < 8 || command.byteCount > MAX_BYTES) fail('BEGIN_REFUSED');
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
  const retire = reason => { op.chunks = []; op.retirement = reason; op.executionPending = false; return observe(op); };
  if (!validDraft(op.binding)) return retire('targetInvalidBeforeInput');
  if (registry.busy.has(op.binding.form)) return retire('inputExecutionBusy');
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
  registry.busy.add(op.binding.form);
  const execute = result => {
    try {
      if (!validDraft(op.binding)) return retire('targetInvalidBeforeInput');
      if (op.discoveryDeadline && Date.now() >= op.discoveryDeadline) return retire('attachmentInputNotCreated');
      if (!result.input || !usableInput(result.input)) return retire(result.reason || 'attachmentInputNotCreated');
      op.binding.input = result.input;
      op.baseline = new Set(attachmentNodes(op.binding));
      registry.files.set(file, op);
      try {
        op.inputCount = 1; op.inputSequence = tick(); op.inputTime = performance.now();
        Reflect.apply(setter, result.input, [transfer.files]);
        result.input.dispatchEvent(new Event('change', {bubbles: true}));
        op.changeReturned = true;
      } catch {
        // A throwing setter/event can already have changed the control. Preserve
        // this operation as uncertain; never try another path or restore FileList.
      }
    } finally {
      try { result.finishUI?.(); } catch { /* Input already settled; never replay it for UI cleanup. */ }
      op.executionPending = false;
    }
    return observe(op);
  };
  const input = directInput(op.binding);
  if (input) {
    try { return execute({input, path: 'direct', finishUI: preserveSelection(op.binding)}); }
    finally { registry.busy.delete(op.binding.form); }
  }
  // Only this no-input-yet branch may activate another native attachment entry.
  // The MAIN-world relay waits for this Promise, without re-executing commit.
  op.discoveryDeadline = Date.now() + 3000;
  op.executionPending = true;
  return discoverThroughEntry(op.binding, op.discoveryDeadline).then(execute, () => retire('attachmentEntryFailed')).finally(() => {
    op.executionPending = false;
    registry.busy.delete(op.binding.form);
  });
}
