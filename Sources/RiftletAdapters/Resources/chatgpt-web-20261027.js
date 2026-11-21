/* Riftlet's document-local file handoff. Upload history never licenses new input.
 * Only commit opens an attachment entry or writes a FileList. Target capture
 * does not require the application to have mounted its picker yet.
 * No message send, editor mutation, attachment removal, request interception,
 * React inspection, prior-file hashing or automatic resubmission exists here.
 */
function riftletWebAcceptance(command, native) {
  'use strict';
  const fail = code => { throw Error(code); };
  const uuid = value => typeof value === 'string' && /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(value);
  const route = () => {
    const url = new URL(location.href);
    // Restrict the product to ChatGPT, without a whitelist of conversation or
    // Project paths. A different service's editor is not an attachment target.
    if (url.username || url.password || !['https://chatgpt.com', 'https://chat.openai.com'].includes(url.origin)) fail('PAGE_ROUTE_UNSUPPORTED');
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
  const usableInput = input => input instanceof HTMLInputElement && input.type === 'file'
    && !input.disabled && !input.matches(':disabled') && !blocked(input) && !input.webkitdirectory;
  const hints = node => ['aria-label', 'title', 'data-testid', 'id', 'name']
    .map(key => node.getAttribute(key) || '').join(' ');
  const referenced = (node, keys) => keys.flatMap(key => (node.getAttribute(key) || '').split(/\s+/))
    .filter(Boolean).map(id => document.getElementById(id)).filter(Boolean);
  const description = node => hints(node) + ' ' + referenced(node, ['aria-labelledby'])
    .map(label => label.textContent || '').join(' ') + ' ' + (node.textContent || '');
  // Names help rank actions inside the interface the opener actually controls.
  // A label/native control, an explicit relationship or a sole local action can
  // identify the route without a translation of its visible text.
  const fileWords = /\b(?:files?|uploads?|attachments?|photos?|pictures?|images?)\b|上传|附件|文件|照片|图片/i;
  const attachmentWords = /attach|upload|add.{0,20}(?:file|photo|image)|choose.{0,12}file|附件|上传|添加.{0,8}(?:文件|照片|图片)|选择文件/i;
  const destructiveWords = /\b(?:send|submit|remove|delete)\b|发送|提交|移除|删除/i;
  const cloudFileWords = /google[\s_-]*drive|one[\s_-]*drive|dropbox|sharepoint|connector|云盘|网盘|连接器/i;
  const foreignPurpose = /avatar|profile[\s_-]*(?:photo|picture|image|upload)|(?:change|edit)[\s_-]*profile|account[\s_-]*settings|project[\s_-]*(?:files?|upload|sources)|(?:files?|upload).{0,16}(?:to|for)[\s_-]*(?:the[\s_-]*)?project|头像|项目文件|个人资料/i;
  const nonFileAction = /\b(?:close|cancel|logout|settings|help)\b|sign[\s_-]*out|log[\s_-]*out|关闭|取消|退出|(?:create|generate|draw|search|edit|analy[sz]e).{0,15}(?:image|photo|file)|生成(?:图片|图像)|绘图|拍照|\bcamera\b/i;
  const controlSelector = 'button,label,[role="button"],[role="menuitem"],[role="option"],[tabindex],[aria-haspopup],[aria-controls],[onclick],a[href]';
  const controls = root => [...root.querySelectorAll(controlSelector)];
  const usableControl = node => typeof node.click === 'function' && visible(node) && !blocked(node)
    && !node.disabled && !node.matches(':disabled') && node.type !== 'file'
    && !node.matches('input[type="submit"],button[type="submit"]')
    && (!node.matches('a[href]') || /^(?:#|$)/.test(node.getAttribute('href')))
    && !destructiveWords.test(description(node));
  const composerSurface = '[data-composer-placement],[data-chatgpt-composer],[data-testid="composer"]';
  const editorNodes = () => {
    const visibleEditors = [...document.querySelectorAll('#prompt-textarea,[contenteditable],[role="textbox"],textarea')]
      .filter(node => visible(node) && (node.isContentEditable || node.tagName === 'TEXTAREA'
        || node.id === 'prompt-textarea' || node.getAttribute('role') === 'textbox'));
    // A wrapper with role=textbox and its nested editable represent one editing
    // surface. Use the real editing host instead of treating them as competitors.
    return visibleEditors.filter(node => !visibleEditors.some(other => other !== node && node.contains(other)
      && (other.isContentEditable || other.tagName === 'TEXTAREA' || other.id === 'prompt-textarea')));
  };
  function composerForm(editor, editors) {
    const declared = editor.closest(composerSurface) || editor.closest('form');
    if (declared) return declared;
    for (let node = editor.parentElement; node && node !== document.body; node = node.parentElement) {
      if (editors.some(other => other !== editor && node.contains(other))) break;
      const siblingPicker = [...node.querySelectorAll('input[type="file"]')].some(input =>
        input.parentElement === node && (!input.form || input.form.contains(editor)));
      if (siblingPicker || controls(node).some(control =>
        attachmentWords.test(description(control)) || /composer.*(?:plus|attach)/i.test(hints(control)))) return node;
    }
    return editor.parentElement || editor;
  }
  function composer() {
    if (globalThis.top !== globalThis) fail('PAGE_NOT_TOP_LEVEL');
    route();
    const editors = editorNodes();
    if (!editors.length) fail('EDITOR_UNAVAILABLE');
    // First establish the actual chat surface. Search, settings, conversation
    // transcript edits and focus proxies can all render visible textboxes.
    // Focus is useful only among candidates, never required for a cold click.
    const partsFor = editor => ({editor, form: composerForm(editor, editors)});
    if (editors.length === 1) return partsFor(editors[0]);
    const pageControls = controls(document), pageInputs = [...document.querySelectorAll('input[type="file"]')];
    const destinations = editors.map(editor => {
      const parts = partsFor(editor);
      const canonical = editor.id === 'prompt-textarea';
      const marked = !!editor.closest(composerSurface);
      const ancillary = !!editor.closest('aside,nav,header,article,[role="search"],[data-message-author-role]');
      const ownedEntries = entryControls(parts, pageControls).filter(control => parts.form.contains(control)
        || referenced(control, ['aria-controls', 'aria-owns']).includes(editor));
      const attaches = ownedEntries.length > 0 || !!directInput(parts, ownedEntries, pageInputs);
      const rank = (attaches ? 64 : 0) + (marked ? 32 : 0) + (canonical ? 16 : 0)
        - (ancillary && !marked && !canonical ? 16 : 0)
        + (editor === document.activeElement || editor.contains(document.activeElement) ? 8 : 0)
        + (editor.isContentEditable || editor.tagName === 'TEXTAREA' ? 4 : 0)
        + (/message|prompt|ask|消息|提问/i.test(hints(editor)) ? 2 : 0)
        + (editor.closest('main,[role="main"]') ? 1 : 0);
      return {parts, rank};
    }).sort((a, b) => b.rank - a.rank);
    const tied = destinations.filter(item => item.rank === destinations[0].rank).map(item => item.parts);
    if (tied.length === 1) return tied[0];
    // Two mounted layouts can look alike in markup while only one is actually
    // shown. Use the visible editing surface as a tie-break, not a focus gate.
    const displayed = tied.filter(({editor}) => {
      if (typeof document.elementFromPoint !== 'function') return false;
      const r = editor.getBoundingClientRect();
      const left = Math.max(0, r.left), top = Math.max(0, r.top);
      const right = Math.min(globalThis.innerWidth, r.right), bottom = Math.min(globalThis.innerHeight, r.bottom);
      if (left >= right || top >= bottom) return false;
      const hit = document.elementFromPoint((left + right) / 2, (top + bottom) / 2);
      return !!hit && editor.contains(hit);
    });
    if (displayed.length === 1) return displayed[0];
    // Mirrors within the same declared composer share its single attachment
    // destination. Prefer the user's actual selection, even without focus.
    const choices = displayed.length ? displayed : tied, form = choices[0].form;
    if (form.matches(composerSurface) && choices.every(item => item.form === form)) {
      const input = directInput(choices[0], entryControls(choices[0], pageControls), pageInputs);
      if (input && choices.every(item => directInput(item, entryControls(item, pageControls), pageInputs) === input)) {
        const anchor = document.getSelection?.()?.anchorNode;
        return choices.find(item => anchor && item.editor.contains(anchor)) || choices[0];
      }
    }
    fail('AMBIGUOUS_COMPOSER');
  }
  const outsidePurpose = (node, binding) => {
    for (let at = node; at && at !== document.body && at !== binding.form; at = at.parentElement) {
      if (foreignPurpose.test(hints(at)) || cloudFileWords.test(hints(at))) return true;
    }
    return false;
  };
  const controlledElements = node => [...new Set([
    ...referenced(node, ['for', 'aria-controls', 'aria-owns', 'popovertarget']),
    node.control, node.popoverTargetElement
  ].filter(Boolean))];
  function relatedInputs(control) {
    const found = new Set(control.querySelectorAll('input[type="file"]'));
    for (const node of controlledElements(control)) {
      if (node.type === 'file') found.add(node);
      else for (const input of node.querySelectorAll('input[type="file"]')) found.add(input);
    }
    return [...found].filter(usableInput);
  }
  function entryControls(binding, available = controls(document)) {
    const local = control => binding.form !== document.body && binding.form.contains(control);
    const belongsElsewhere = control => {
      const owner = control.closest(composerSurface) || control.closest('form');
      if (!owner || owner.contains(binding.editor) || referenced(control, ['aria-controls', 'aria-owns']).includes(binding.editor)) return false;
      return editorNodes().some(editor => owner.contains(editor));
    };
    const candidates = available.filter(control => !binding.editor.contains(control) && !control.contains(binding.editor)
      && !control.closest('[data-file-name],[role="menu"],[role="menuitem"]')
      && !outsidePurpose(control, binding) && !belongsElsewhere(control)
      && (local(control) || /composer.*(?:plus|attach)/i.test(hints(control))
        || referenced(control, ['aria-controls']).includes(binding.editor)
        || (binding.form.parentElement && binding.form.parentElement !== document.body
          && binding.form.parentElement.contains(control) && !control.closest('form,aside,nav,header'))))
      .filter(control => {
        if (!usableControl(control)) return false;
        const text = description(control);
        return !foreignPurpose.test(text) && !cloudFileWords.test(text) && !nonFileAction.test(text)
          && (attachmentWords.test(text) || /composer.*(?:plus|attach)|(?:plus|attach).*composer/i.test(text)
            || (local(control) && (/^\s*\+\s*$/.test(control.textContent || '')
              || relatedInputs(control).length > 0
              || (control.hasAttribute('aria-haspopup') && (fileWords.test(control.getAttribute('aria-controls') || '')
                || controlledElements(control).some(panel => fileWords.test(description(panel))))))));
      }).sort((a, b) => Number(local(b)) - Number(local(a)));
    // A label's association proves which field that label owns. It does
    // not make an independent subwidget the chat's attachment entry.
    const primary = candidates.filter(node => /composer.*(?:plus|attach)|(?:plus|attach).*composer/i.test(hints(node))
      || referenced(node, ['aria-controls']).includes(binding.editor));
    if (primary.length) return primary;
    const named = candidates.filter(node => attachmentWords.test(description(node)) || /^\s*\+\s*$/.test(node.textContent || ''));
    return named.length ? named : candidates;
  }
  function hasSeparateOwner(input, binding, ownControls) {
    if (input.form && input.form !== binding.form && editorNodes().some(editor => input.form.contains(editor))) return true;
    // Another labelled/controlled application task is positive contrary
    // evidence. A portal, an unlabelled input or a separate plain form is not.
    const labels = [...(input.labels || [])];
    const parentLabel = input.closest('label');
    if (parentLabel) labels.push(parentLabel);
    if (input.id) {
      for (const control of document.querySelectorAll('[for],[aria-controls],[aria-owns]'))
        if (controlledElements(control).includes(input)) labels.push(control);
    }
    return labels.some(label => !ownControls(label));
  }
  function otherOwner(input, binding, ownControls) {
    return outsidePurpose(input, binding) || foreignPurpose.test(description(input))
      || hasSeparateOwner(input, binding, ownControls);
  }
  function directInput(binding, entries, available = document.querySelectorAll('input[type="file"]')) {
    const own = node => entries.includes(node);
    const linked = new Set(entries.flatMap(relatedInputs).filter(input => input.isConnected && !otherOwner(input, binding, own)));
    if (linked.size === 1) return [...linked][0];
    const local = [...available].filter(input => input.isConnected
      && usableInput(input) && !input.hasAttribute('capture') && binding.form !== document.body
      && (input.form === binding.form || (binding.form.contains(input) && (!input.form || input.form.contains(binding.editor))))
      && !otherOwner(input, binding, own));
    if (local.length === 1) return local[0];
    // ChatGPT can expose camera, media library, photo-only and ordinary file
    // inputs side by side. Prefer the named general file action when present.
    // Accept is a chooser hint for comparing siblings, never a PNG permission.
    const fields = linked.size ? [...linked] : local;
    const general = fields.filter(input => !input.hasAttribute('capture')
      && (!input.accept.trim() || input.accept.trim() === '*/*') && fileWords.test(description(input)));
    if (general.length === 1) return general[0];
    const named = fields.filter(input => !input.hasAttribute('capture') && attachmentWords.test(description(input)));
    return named.length === 1 ? named[0] : null;
  }

  // RIFTLET_ORIGINAL_RECEIVER_BEGIN
  function bindOriginalReceiver(node, permits, trackDraftFocus = false, acceptsAuxiliaryFocus = () => false) {
    const root = document.documentElement, owner = node.ownerDocument;
    const parent = item => item.parentNode || (item.nodeType === 11 ? item.host : null) || null;
    const lineage = [];
    for (let item = node; item; item = parent(item)) lineage.push(item);
    const originals = new Set(lineage);
    const entry = globalThis.navigation?.currentEntry?.id;
    const moved = records => records.some(record =>
      Array.from(record.removedNodes).some(item => originals.has(item)) ||
      Array.from(record.addedNodes).some(item => originals.has(item)));
    let live = true;
    const observer = new MutationObserver(records => { if (moved(records)) close(); });
    // Shadow roots have their own mutation trees. Observe a detached picker
    // too when its application explicitly handed that exact object to us.
    const roots = new Set([document]);
    for (const item of lineage) if (item.nodeType === 11) roots.add(item);
    if (!node.isConnected) roots.add(lineage[lineage.length - 1]);
    for (const tree of roots) observer.observe(tree, {childList: true, subtree: true});
    function visibilityChanged() { if (document.visibilityState !== 'visible') close(); }
    function focusChanged(event) {
      const next = event.composedPath?.()[0] || event.target;
      if (next === node) return;
      // Even a plain div can be the retargeted host of a closed shadow editor.
      try { if (!acceptsAuxiliaryFocus(next)) close(); } catch { close(); }
    }
    function close() {
      if (!live) return;
      live = false;
      observer.disconnect();
      globalThis.removeEventListener('pagehide', close);
      globalThis.navigation?.removeEventListener('currententrychange', close);
      if (trackDraftFocus) {
        globalThis.removeEventListener('blur', close);
        document.removeEventListener('visibilitychange', visibilityChanged);
        document.removeEventListener('focusin', focusChanged, true);
      }
    }
    globalThis.addEventListener('pagehide', close);
    globalThis.navigation?.addEventListener('currententrychange', close);
    if (trackDraftFocus) {
      globalThis.addEventListener('blur', close);
      document.addEventListener('visibilitychange', visibilityChanged);
      document.addEventListener('focusin', focusChanged, true);
    }
    function current() {
      if (!live) return false;
      // permits may synchronously invoke another event listener. Drain the
      // mutation queue and check the captured references after it returns.
      try {
        if (!permits() || !live || moved(observer.takeRecords()) || document.documentElement !== root ||
            node.ownerDocument !== owner || owner !== root.ownerDocument ||
            globalThis.navigation?.currentEntry?.id !== entry ||
            !lineage.every((item, index) => parent(item) === (lineage[index + 1] || null)) ||
            (trackDraftFocus && (!node.isConnected || document.visibilityState !== 'visible' || !document.hasFocus()))) close();
      } catch (error) { close(); throw error; }
      return live;
    }
    return {current, close, once(method) {
      let used = false;
      return (...args) => {
        if (used) return false;
        used = true;
        if (!current()) return false;
        Reflect.apply(method, node, args);
        return true;
      };
    }};
  }
  // RIFTLET_ORIGINAL_RECEIVER_END

  if (command.action === 'pinTarget') {
    if (!uuid(command.clickWitnessID) || command.address !== route() || !globalThis.navigation?.currentEntry)
      fail('CLICK_PIN_REFUSED');
    const parts = composer(), address = location.href;
    const editorEvent = 'riftlet-witness-editor-' + command.clickWitnessID;
    const formEvent = 'riftlet-witness-form-' + command.clickWitnessID;
    const openEvent = 'riftlet-entry-begin-' + command.clickWitnessID;
    const endEvent = 'riftlet-entry-end-' + command.clickWitnessID;
    let opening = null;
    const menuSelector = '[role="menu"],[role="listbox"]';
    const openingChanged = event => {
      opening = null;
      if (event.type === openEvent && entryControls(parts).includes(event.target)) {
        opening = {entry: event.target, before: new Set(document.querySelectorAll(menuSelector))};
      }
    };
    const acceptsAuxiliaryFocus = next => {
      // These native elements cannot host an author-created closed shadow root.
      if (!next?.matches?.('button,a[href],label,input[type="file"],li') ||
          next.isContentEditable || parts.editor.contains(next) || outsidePurpose(next, parts)) return false;
      const entries = entryControls(parts);
      if (entries.some(entry => entry === next || controlledElements(entry).some(panel => panel.contains(next)))) return true;
      if (!opening || !entries.includes(opening.entry) || !usableControl(next) ||
          !(fileWords.test(description(next)) || attachmentWords.test(description(next)))) return false;
      const fresh = [...document.querySelectorAll(menuSelector)].filter(menu => !opening.before.has(menu) && visible(menu));
      return fresh.length === 1 && fresh[0].contains(next) && !fresh[0].contains(parts.editor) &&
        !fresh[0].closest('[data-file-name],[data-message-author-role],article,aside,nav,header');
    };
    const receiver = bindOriginalReceiver(parts.editor, () => location.href === address &&
      parts.form.isConnected && parts.form.contains(parts.editor) &&
      (parts.editor.closest(composerSurface) || parts.editor.closest('form') || parts.form) === parts.form, true, acceptsAuxiliaryFocus);
    if (!receiver.current()) fail('CLICK_PIN_REFUSED');
    const handle = e => {
      if (e.target === (e.type === editorEvent ? parts.editor : parts.form) && receiver.current()) e.preventDefault();
    };
    setTimeout(() => {
      receiver.close();
      parts.editor.removeEventListener(editorEvent, handle);
      parts.form.removeEventListener(formEvent, handle);
      document.removeEventListener(openEvent, openingChanged, true);
      document.removeEventListener(endEvent, openingChanged, true);
    }, 60000);
    parts.editor.addEventListener(editorEvent, handle);
    parts.form.addEventListener(formEvent, handle);
    document.addEventListener(openEvent, openingChanged, true);
    document.addEventListener(endEvent, openingChanged, true);
    return 'bound';
  }

  // RIFTLET_CLICK_PIN_END
  const KEY = '__riftletIndependentFileInput20261104';
  const MAX_BYTES = 128 * 1024 * 1024, MAX_CHUNK_BYTES = 256 * 1024;
  const targetKeys = ['adapterID', 'surface', 'applicationID', 'sessionID', 'windowID', 'tabID',
    'documentID', 'composerID', 'draftGeneration'];
  const sameTarget = (a, b) => !!a && !!b && targetKeys.every(k => a[k] === b[k])
    && (a.historyConversationID || '').toLowerCase() === (b.historyConversationID || '').toLowerCase()
    && (a.clickBindingID || null) === (b.clickBindingID || null);
  const sameIdentity = (a, b) => !!a && !!b && a.operationID === b.operationID
    && a.assetID === b.assetID && a.attempt === b.attempt && a.assetSHA256 === b.assetSHA256
    && sameTarget(a.target, b.target);
  const contextMatches = target => target && ['applicationID', 'sessionID', 'windowID', 'tabID']
    .every(key => target[key] === native[key]);
  const blank = (identity, state = 'unknown') => ({schemaVersion: 2,
    provenance: {source: 'integratedDevelopment', evidenceID: 'browser-handoff-20261120-v30'},
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
  }
  // In an already-open document an earlier program may have installed its
  // own attribution hook. Chain once, preserving that program's File map.
  if (registry && !registry.blobOwners && typeof URL.createObjectURL === 'function') {
    const state = registry, original = URL.createObjectURL;
    state.blobOwners = new Map();
    state.blobSerial = 0;
    try {
      URL.createObjectURL = function (file) {
        const value = Reflect.apply(original, this, arguments);
        const operation = state.files.get(file);
        if ((operation || performance.now() < state.blobWindowUntil)
            && value.startsWith('blob:') && value.length <= 256) {
          if (state.blobOwners.size >= 256) {
            state.blobOwners.delete(state.blobOwners.keys().next().value);
          }
          state.blobOwners.set(value, {owner: operation?.identity.operationID, serial: ++state.blobSerial});
          if (operation && !operation.discarded && !operation.start && operation.urls.size < 64) operation.urls.add(value);
        }
        return value;
      };
    } catch { /* Signed/remote URLs and File bytes are never copied here. */ }
  }
  // Timers are created by one document-scoped function, so timer closures
  // cannot capture individual input commands, staged bytes, or composer locals.
  if (registry && !registry.scheduleRetirement) {
    registry.scheduleRetirement = (operations, id, operation) => {
      const idleBudget = 10 * 60 * 1000;
      operation.lastActivity = Date.now();
      function expire() {
        const remaining = operation.lastActivity + idleBudget - Date.now();
        if (remaining > 0 || operation.executionPending) {
          setTimeout(expire, Math.max(5000, remaining))?.unref?.();
          return;
        }
        operation.discarded = true; operation.chunks = [];
        operation.binding = null; operation.failureWatch = null;
        operation.urls.clear(); operation.baseline.clear(); operation.previewBaseline = null;
        operations.set(id, {committed: true});
      }
      setTimeout(expire, idleBudget)?.unref?.();
    };
  }
  const nodeID = node => {
    if (!registry.nodeIDs.has(node)) registry.nodeIDs.set(node, 'node-' + (++registry.nextNode));
    return registry.nodeIDs.get(node);
  };
  const tick = () => ++registry.sequence;
  function sameDraft(binding, writing = false) {
    try {
      if (!binding || registry.root !== document.documentElement || binding.navigation !== registry.navigation
          || binding.route !== route() || !contextMatches(binding.target)) return false;
      if (binding.target.clickBindingID) {
        if (!writing && binding.readOriginal) return binding.readOriginal();
        return binding.form.contains(binding.editor) && binding.editor.isConnected &&
          !binding.editor.dispatchEvent(new Event('riftlet-witness-editor-' + binding.target.clickBindingID, {cancelable: true})) &&
          !binding.form.dispatchEvent(new Event('riftlet-witness-form-' + binding.target.clickBindingID, {cancelable: true}));
      }
      if (binding.form.isConnected && binding.editor.isConnected && binding.form.contains(binding.editor)) return true;
      // A live editing host can be moved into a rebuilt wrapper without
      // changing its destination. For an entirely replaced editor, the same
      // saved conversation and composer must both still identify the owner.
      const current = composer();
      if (binding.editor !== current.editor) {
        const savedConversation = /\/c\/[^/]+\/?$/.test(new URL(binding.route).pathname);
        const sameSurface = binding.form === current.form || (!binding.form.isConnected
          && ((binding.form.matches(composerSurface) && current.form.matches(composerSurface))
            || (binding.editor.id === 'prompt-textarea' && current.editor.id === binding.editor.id)));
        if (!savedConversation || binding.editor.isConnected || !sameSurface
            || current.editor.closest('aside,nav,header,article,[role="menu"],[role="search"],[data-message-author-role]')) return false;
      }
      binding.form = current.form; binding.editor = current.editor;
      return true;
    } catch { return false; }
  }
  function validDraft(binding) {
    // The original editor is the destination. Opening its menu can move focus
    // or add search textboxes; reranking editors here would reject that very
    // interaction or switch to the menu's textbox.
    return sameDraft(binding, true) && (!binding.target.clickBindingID ||
      (document.visibilityState === 'visible' && document.hasFocus() && visible(binding.editor) && !blocked(binding.form)));
  }
  function preserveSelection(binding) {
    if (binding.editor.tagName === 'TEXTAREA') {
      const editor = binding.editor, value = editor.value, start = editor.selectionStart,
        end = editor.selectionEnd, direction = editor.selectionDirection, active = document.activeElement;
      return () => {
        if (!validDraft(binding) || binding.editor !== editor || editor.value !== value || !Number.isInteger(start) || !Number.isInteger(end)) return;
        if (active === editor && document.hasFocus()) editor.focus?.({preventScroll: true});
        if (!validDraft(binding)) return;
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
      if (!validDraft(binding) || binding.editor.textContent !== saved.text
          || !binding.editor.contains(saved.anchor) || !binding.editor.contains(saved.focus)) return;
      const current = document.getSelection?.();
      // The caller suppresses restoration after trusted user interaction. A
      // menu can collapse selection inside the editor as well as move it out.
      if (current?.anchorNode === saved.anchor && current.focusNode === saved.focus
          && current.anchorOffset === saved.anchorOffset && current.focusOffset === saved.focusOffset) return;
      if (saved.active === binding.editor && document.hasFocus()) binding.editor.focus?.({preventScroll: true});
      if (!validDraft(binding)) return;
      current?.setBaseAndExtent?.(saved.anchor, saved.anchorOffset, saved.focus, saved.focusOffset);
    };
  }
  // Follow only the interface exposed by the current attachment control. Some
  // popovers are ordinary divs, some are reused, and a submenu can use a second
  // portal. A role or localized menu caption alone cannot establish ownership.
  function entrySurfaces(binding) {
    const roots = new Set(), opened = new Set(), before = new Map(), parents = new Set();

    const surfaceSelector = '[role="menu"],[role="dialog"],[popover],[data-state="open"]';
    const beforeOpen = new Set([...document.querySelectorAll(surfaceSelector)].filter(visible));
    const eligible = node => node && node.nodeType === 1 && node !== document.body
      && !node.contains(binding.editor) && !binding.editor.contains(node)
      && !node.closest('[data-file-name],[data-message-author-role],article,aside,nav,header') && !outsidePurpose(node, binding);
    for (const node of controls(document)) {
      if (!eligible(node)) continue;
      if (visible(node)) before.set(node, description(node));
      for (let at = node; at && !parents.has(at); at = at.parentElement) parents.add(at);
    }
    parents.add(binding.form); parents.add(document.body);
    const add = (node, created) => {
      if (!eligible(node) || node.type === 'file' || !visible(node)) return;
      if (!roots.has(node) && created && !beforeOpen.has(node)) opened.add(node);
      roots.add(node);
    };
    const linked = (control, created) => {
      const named = control.id ? [...document.querySelectorAll('[aria-labelledby]')]
        .filter(node => referenced(node, ['aria-labelledby']).includes(control)) : [];
      for (const node of [...controlledElements(control), ...named]) add(node, created);
    };
    // Synchronous changes made by the opener may introduce an unlabelled portal.
    // Later changes can only populate a surface already bound to this action.
    const changed = (node, invoked) => {
      if (!eligible(node) || invoked.has(node) || roots.has(node) || !visible(node)) return;
      let root = node.closest(surfaceSelector);
      if (!eligible(root)) {
        root = node;
        while (eligible(root.parentElement) && !parents.has(root.parentElement)) root = root.parentElement;
        // Inserting an item in a previously mounted portal updates that panel.
        if (root === node && eligible(node.parentElement) && !binding.form.contains(node.parentElement))
          root = node.parentElement;
      }
      if (!eligible(root) || [...roots].some(known => known === root || known.contains(root))) return;
      add(root, true);
    };
    const scan = (invoked, mutations, fromControl = false) => {
      for (const item of invoked) linked(item, true);
      if (fromControl) for (const node of mutations) changed(node, invoked);
      mutations.clear();
      const current = new Map();
      for (const node of controls(document)) {
        if (!eligible(node) || !visible(node)) continue;
        const name = description(node);
        current.set(node, name);
        if (fromControl && (!before.has(node) || before.get(node) !== name)) changed(node, invoked);
      }
      before.clear();
      for (const [node, name] of current) before.set(node, name);
    };
    const contains = node => [...roots].some(root => root.contains(node));
    return {roots, opened, linked, contains, scan};
  }
  function menuAction(root, binding, invoked) {
    if (!visible(root)) return null;
    const safe = node => usableControl(node) && !invoked.has(node) && !outsidePurpose(node, binding)
      && !node.closest('[data-file-name]') && !cloudFileWords.test(description(node))
      && !foreignPurpose.test(description(node)) && !nonFileAction.test(description(node));
    const items = [root, ...controls(root)].filter(node => node.matches(controlSelector) && safe(node)
      && !node.matches('form,[role="menu"],[role="dialog"],[role="listbox"]')
      && (node !== root || node.matches('button,label,a[href],[role="button"],[role="menuitem"],[role="option"],[onclick]')));
    // Plain delegated rows may have neither tabindex nor a role. Dispatch at
    // their text so the application's own listener/default bubbling is used.
    const leaves = [root, ...root.querySelectorAll('*')].filter(node => !node.children.length
      && typeof node.click === 'function' && !items.some(item => item.contains(node))
      && fileWords.test(node.textContent || '') && safe(node));
    items.push(...leaves);
    const actions = items.filter(node => !items.some(child => child !== node && node.contains(child)));
    const score = node => {
      if (relatedInputs(node).length) return 4;
      if (/from.{0,12}(?:computer|device)|本地|从.{0,6}(?:电脑|设备)/i.test(description(node))) return 3.5;
      if (fileWords.test(description(node)) || attachmentWords.test(description(node))) return 3;
      if (controlledElements(node).length || node.hasAttribute('aria-haspopup')
        || node.hasAttribute('aria-expanded')) return 2;
      // A single native menu action in the opener's own popup can be localized.
      // An arbitrary unrelated button added somewhere in the page cannot.
      return actions.length === 1 && (node.tagName === 'BUTTON' || node.getAttribute('role') === 'menuitem') ? 1 : 0;
    };
    const ranked = actions.map(node => ({node, rank: score(node)})).filter(item => item.rank > 0).sort((a, b) => b.rank - a.rank);
    if (!ranked.length) return null;
    return ranked.length === 1 || ranked[0].rank >= 3 || ranked[0].rank > ranked[1].rank ? ranked[0].node : null;
  }
  // Dispatch one already-cancelled activation to the application's own DOM
  // handlers. Cancelling before dispatch covers a detached listener which
  // stops immediate propagation before any later chooser guard could run.
  function clickWithoutDefault(node) {
    const Click = globalThis.PointerEvent || globalThis.MouseEvent || Event;
    const click = new Click('click', {bubbles: true, cancelable: true, composed: true, button: 0});
    click.preventDefault();
    node.dispatchEvent(click);
  }
  function pickerHooks(intercept, canActivate, restores) {
    const clicking = new WeakSet();
    const proto = HTMLInputElement.prototype;
    for (const method of ['click', 'showPicker']) {
      const own = Object.getOwnPropertyDescriptor(proto, method), original = proto[method];
      if (typeof original !== 'function') continue;
      const value = function (...args) {
        if (!intercept(this, method)) return Reflect.apply(original, this, args);
        if (method === 'showPicker' || !canActivate()) return;
        if (clicking.has(this)) return;
        clicking.add(this);
        try { clickWithoutDefault(this); }
        finally { clicking.delete(this); }
      };
      // In Chrome click is inherited from HTMLElement. Shadow it only on
      // input elements and restore the exact descriptor (or its absence).
      Object.defineProperty(proto, method, own ? {...own, value} : {value, writable: true, configurable: true});
      restores.push(() => {
        if (proto[method] !== value) return;
        if (own) Object.defineProperty(proto, method, own);
        else delete proto[method];
      });
    }
  }
  function exceptionName(error) {
    const known = ['Error','TypeError','RangeError','ReferenceError','SyntaxError',
      'SecurityError','NotAllowedError','InvalidStateError','NotSupportedError','AbortError','DOMException'];
    return known.includes(error?.name) ? error.name : 'other';
  }
  async function discoverThroughEntry(op, entries, execute, retire) {
    const binding = op.binding, diag = op.entryDiagnostics, deadline = op.discoveryDeadline;
    const surfaces = entrySurfaces(binding), restoreSelection = preserveSelection(binding);
    const invoked = new Set(), entryAttempts = new Set(), usedRoots = new Set(), mutations = new Set();
    const captured = new Map(), syncMounted = new Set(), restores = [];
    const beforeInputs = new Set(document.querySelectorAll('input[type="file"]'));
    let lastEntryAt = 0, interrupted = false, insideControl = false, handlingForeignEvent = false;
    let menuLocated = false;
    let wake, changed = false;
    const canActivate = () => !interrupted && validDraft(binding);
    const signal = () => { changed = true; wake?.(); };
    const waitForChange = async () => {
      // A timeout only schedules another DOM check (including CSS visibility).
      // The observed picker or application action, never the delay, decides.
      if (!changed) await new Promise(resolve => {
        const timer = setTimeout(resolve, Math.max(0, Math.min(100, deadline - Date.now())));
        wake = () => { clearTimeout(timer); resolve(); };
      });
      wake = null; changed = false;
    };
    const own = node => invoked.has(node) || entries.includes(node) || surfaces.contains(node);
    const capture = (input, method) => {
      if (!(input instanceof HTMLInputElement) || input.type !== 'file' || !invoked.size || handlingForeignEvent) return false;
      const owned = insideControl || surfaces.contains(input) || syncMounted.has(input)
        || [...invoked].some(control => relatedInputs(control).includes(input));
      if (hasSeparateOwner(input, binding, own)
        || (!owned && (outsidePurpose(input, binding) || foreignPurpose.test(description(input))))) return false;
      if (method === 'showPicker') diag.pickerShows++;
      else diag.pickerClicks++;
      diag.inputSeen = true; diag.inputConnected = input.isConnected;
      if (Date.now() < deadline) captured.set(input, {wasConnected: input.isConnected,
        tied: owned || captured.get(input)?.tied});
      signal();
      return true;
    };
    const onClick = event => {
      const node = event.target;
      if (node?.type === 'file') {
        if (!event.defaultPrevented && capture(node, 'event')) event.preventDefault();
        return;
      }
      if (!insideControl && !own(node) && node?.closest?.(controlSelector)) {
        // Let independently activated avatar/Project controls run their own
        // click handlers and chooser, including during this operation's wait.
        handlingForeignEvent = true;
        queueMicrotask(() => { handlingForeignEvent = false; });
      }
    };
    const userInteraction = event => {
      if (event.isTrusted) {
        interrupted = true; handlingForeignEvent = true; signal();
        queueMicrotask(() => { handlingForeignEvent = false; });
      }
    };
    const records = list => {
      for (const record of list) {
        if (record.type === 'childList') {
          for (const node of record.addedNodes) mutations.add(node);
          if (!record.addedNodes.length) mutations.add(record.target);
        } else mutations.add(record.target.nodeType === 1 ? record.target : record.target.parentElement);
      }
    };
    const observer = new MutationObserver(list => { records(list); signal(); });
    const scan = (fromControl = false) => {
      records(observer.takeRecords()); surfaces.scan(invoked, mutations, fromControl);
      diag.openedContainers = surfaces.roots.size;
    };
    const fire = (control, callback) => {
      scan(); // Account for any preceding independent mutation before attributing this dispatch.
      const previous = new Set(document.querySelectorAll('input[type="file"]'));
      if (!canActivate() || !control.isConnected) return false;
      insideControl = true;
      // The pin lives in the Apple Event world. Expose only this exact
      // opener's synchronous dispatch; a later unrelated portal cannot qualify.
      const pin = binding.target.clickBindingID;
      const opening = pin && entries.includes(control);
      try {
        if (opening) control.dispatchEvent(new Event('riftlet-entry-begin-' + pin, {bubbles: true}));
        return callback(control);
      }
      finally {
        if (opening) document.dispatchEvent(new Event('riftlet-entry-end-' + pin));
        insideControl = false;
        scan(true);
        for (const input of document.querySelectorAll('input[type="file"]'))
          if (!previous.has(input)) syncMounted.add(input);
      }
    };
    const activate = async control => {
      const wasOpen = control.getAttribute('aria-expanded'), priorRoots = surfaces.roots.size;
      const advanced = () => {
        scan();
        return !canActivate() || !control.isConnected || captured.size > 0
          || surfaces.roots.size > priorRoots || control.getAttribute('aria-expanded') !== wasOpen;
      };
      // These are programmatic, untrusted events. Pointer-triggered primitives
      // can open on down/up; ordinary controls need their native click behavior.
      // Do not click a second time if the pointer phase already advanced the UI.
      let clicked = false;
      const onControlClick = event => {
        clicked = true;
        if (control.tagName === 'BUTTON' && control.type === 'submit') event.preventDefault();
      };
      control.addEventListener('click', onControlClick, true);
      try {
        if (typeof PointerEvent === 'function') {
          const pointer = (type, buttons) => fire(control, node => node.dispatchEvent(new PointerEvent(type, {
            bubbles: true, cancelable: true, composed: true, button: 0, buttons, pointerId: 1, pointerType: 'mouse', isPrimary: true
          })));
          const mouse = (type, buttons) => {
            if (typeof MouseEvent === 'function') fire(control, node => node.dispatchEvent(new MouseEvent(type, {
              bubbles: true, cancelable: true, composed: true, button: 0, buttons
            })));
          };
          const compat = pointer('pointerdown', 1);
          if (compat && control.isConnected) mouse('mousedown', 1);
          await Promise.resolve();
          if (!canActivate() || !control.isConnected) return captured.size > 0;
          const handledOnDown = advanced();
          pointer('pointerup', 0);
          if (compat && control.isConnected) mouse('mouseup', 0);
          await Promise.resolve();
          if (clicked || handledOnDown || advanced()) return clicked || captured.size > 0 || control.isConnected;
        }
        fire(control, node => {
          if (node.matches('a[href]') || (node.tagName === 'BUTTON' && node.type === 'submit')) clickWithoutDefault(node);
          else node.click();
        });
        return clicked;
      } finally { control.removeEventListener('click', onControlClick, true); }
    };
    try {
      pickerHooks(capture, canActivate, restores);
      observer.observe(document.documentElement, {subtree: true, childList: true, attributes: true, characterData: true});
      document.addEventListener('click', onClick, true);
      document.addEventListener('pointerdown', userInteraction, true);
      document.addEventListener('keydown', userInteraction, true);
      for (const entry of entries) surfaces.linked(entry, false);
      while (true) {
        const ended = Date.now() >= deadline;
        const valid = validDraft(binding);
        if (interrupted || !valid) {
          // An entry already started by this operation may finish its own
          // asynchronous picker call after navigation. Cancel just its chooser
          // within the original deadline, without delivering into the new draft.
          if (ended || !invoked.size || captured.size) break;
          await waitForChange(); continue;
        }
        scan();
        const picked = [...captured].filter(([input]) => usableInput(input));
        // A click handler may replace the field. Prefer its current invocation
        // over the now-unmounted old one; originally detached objects work too.
        const current = picked.filter(([input, fact]) => !fact.wasConnected || input.isConnected);
        const tied = current.filter(([input, fact]) => fact.tied && !hasSeparateOwner(input, binding, own));
        if (tied.length > 1) return retire('attachmentInputAmbiguous', 'picker', 'ambiguous');
        if (ended) {
          if (current.length > 1) return retire('attachmentInputAmbiguous', 'picker', 'ambiguous');
          break;
        }
        if (tied.length === 1) return execute(tied[0][0], true);
        entries = entryControls(binding);
        diag.entryCandidates = Math.max(diag.entryCandidates, entries.length);
        const local = directInput(binding, entries);
        if (local) return execute(local);
        const mounted = [...document.querySelectorAll('input[type="file"]')].filter(input =>
          !beforeInputs.has(input) && usableInput(input) && !otherOwner(input, binding, own));
        const inPopup = mounted.filter(input => surfaces.contains(input));
        const mountedHere = inPopup.length ? inPopup : mounted.filter(input => syncMounted.has(input));
        if (invoked.size && mountedHere.length === 1) return execute(mountedHere[0]);
        let next, menuRoot;
        for (const root of [...surfaces.roots].reverse()) {
          if (usedRoots.has(root)) continue;
          next = menuAction(root, binding, invoked);
          if (next) { menuRoot = root; menuLocated = true; diag.stage = 'menu'; break; }
        }
        const canOpen = !surfaces.roots.size || (!invoked.size && entries.some(entry =>
          entry.getAttribute('aria-expanded') !== 'true'));
        if (!next && canOpen && (!entryAttempts.size || Date.now() - lastEntryAt >= 200) && entryAttempts.size < 2) {
          next = entries.find(entry => !invoked.has(entry)
            && (!surfaces.roots.size || entry.getAttribute('aria-expanded') !== 'true'));
          if (next) { entryAttempts.add(next); lastEntryAt = Date.now(); diag.entryActivations++; diag.stage = 'entry'; }
        }
        if (next) {
          invoked.add(next);
          const activated = await activate(next);
          if (menuRoot && activated) { usedRoots.add(menuRoot); diag.menuActivations++; }
          continue;
        }
        if (!invoked.size && !surfaces.roots.size) return retire('attachmentEntryUnavailable', 'entry', 'entryUnavailable');
        await waitForChange();
      }
      if (interrupted) return retire('attachmentEntryFailed', diag.stage, 'userInterrupted');
      if (!validDraft(binding)) return retire('targetInvalidBeforeInput', diag.stage, 'targetChanged');
      if (captured.size) return retire('attachmentInputNotCreated', 'picker', 'pickerRejected');
      if (diag.menuActivations) return retire('attachmentInputNotCreated', 'picker', 'pickerNotInvoked');
      if (surfaces.roots.size) return retire('attachmentInputNotCreated', 'menu', menuLocated ? 'menuActionNotRun' : 'menuActionMissing');
      return retire('attachmentInputNotCreated', 'entry', 'pickerNotInvoked');
    } catch (error) {
      diag.exceptionType = exceptionName(error);
      if (diag.setterEntered) { diag.cause = 'deliveryUncertain'; return observe(op); }
      return retire('attachmentEntryFailed', diag.stage, 'exception');
    } finally {
      observer.disconnect();
      document.removeEventListener('click', onClick, true);
      document.removeEventListener('pointerdown', userInteraction, true);
      document.removeEventListener('keydown', userInteraction, true);
      for (const restore of restores.reverse()) restore();
      if (canActivate()) {
        for (const root of [...surfaces.opened].reverse()) if (visible(root)) {
          const target = root.contains(document.activeElement) ? document.activeElement : root;
          if (!canActivate()) break;
          target.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', code: 'Escape', bubbles: true, cancelable: true}));
        }
        restoreSelection();
      }
    }
  }
  function bindingFor(target) {
    if (!registry || !contextMatches(target)) return null;
    if (target.clickBindingID) {
      const pinned = registry.clickBindings?.get(target.clickBindingID);
      return sameTarget(pinned?.target, target) ? pinned : null;
    }
    return sameTarget(registry.current?.target, target) ? registry.current : null;
  }
  function attachmentNodes(binding, root = document) {
    // Attachment cards can also be portalled outside the editor's form. The
    // current file's unique filename/blob and pre-input baseline bind START;
    // containment in a guessed form is not an acceptance prerequisite.
    return [...root.querySelectorAll('[data-file-name],[role="button"],button,img[alt],img[src],[title]')]
      .filter(node => node !== binding.editor && !binding.editor.contains(node)
        && !(node instanceof HTMLInputElement && node.type === 'file')
        && (!node.closest('[role="menu"],[role="dialog"]')
          || node.closest('[role="dialog"]')?.contains(binding.editor)));
  }
  const previewSelector = 'img[src],progress,[role="progressbar"]';
  function previewValue(node) {
    if (node.tagName === 'IMG') return (node.getAttribute('src') || '').trim();
    const native = node.tagName === 'PROGRESS';
    const value = node.getAttribute(native ? 'value' : 'aria-valuenow');
    if (!value?.trim()) return true;
    const min = native ? 0 : Number(node.getAttribute('aria-valuemin') ?? 0);
    const max = Number(node.getAttribute(native ? 'max' : 'aria-valuemax') ?? (native ? 1 : 100));
    const current = Number(value);
    return Number.isFinite(min) && Number.isFinite(max) && max > min && current >= min && current <= max
      ? {min, max, current} : true;
  }
  function blobIssue(src) {
    if (!src || src.length > 256 || !src.startsWith('blob:')) return undefined;
    return registry.blobOwners?.get(src);
  }
  function currentFileURL(op, src) {
    const owner = blobIssue(src)?.owner;
    return owner === undefined ? op.urls.has(src) : owner === op.identity.operationID;
  }
  // For a page-derived blob, names establish member ownership while issuance
  // establishes freshness. An expired or evicted record cannot certify either
  // a pre-existing URL or a URL fabricated in a different JavaScript realm.
  function usablePreviewSource(op, src) {
    if (!src || !src.startsWith('blob:') || currentFileURL(op, src)) return true;
    const issue = blobIssue(src);
    return !!issue && !issue.owner && issue.serial > op.blobSerialBeforeInput;
  }
  function renderedPreview(node) {
    if (!visible(node)) return false;
    if (typeof node.checkVisibility === 'function') {
      if (!node.checkVisibility({opacityProperty: true, visibilityProperty: true, contentVisibilityAuto: true})) return false;
    } else {
      for (let at = node; at; at = at.parentElement) {
        if (getComputedStyle(at).opacity === '0') return false;
      }
    }
    const bounds = node.getBoundingClientRect();
    return bounds.width > 0 && bounds.height > 0;
  }
  function independentCardPortal(card, binding) {
    return !card.closest(composerSurface + ',form,article,aside,nav,header,[role="menu"],[role="dialog"],[data-message-author-role]')
      && !outsidePurpose(card, binding);
  }
  const fileNamePattern = name => new RegExp('(^|[^a-zA-Z0-9_.-])' + name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '($|[^a-zA-Z0-9_.-])');
  const cardSelector = '[data-file-name],[role="button"],button';
  function inOriginalCardContainer(card, binding) {
    if (!binding.form.contains(card) || binding.editor.contains(card) || card.contains(binding.editor)) return false;
    const scope = card.closest(composerSurface + ',form,article,aside,nav,header,[role="menu"],[role="dialog"],[data-message-author-role]');
    return !scope || scope === binding.form || scope.contains(binding.editor);
  }
  // A reused card may still display the old blob while its other labels
  // already identify a different upload. Check the small card only; a complex
  // or changing subtree is insufficient evidence for an error hint.
  function consistentCardLabels(card, name) {
    const uploadName = /riftlet-[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}\.[a-z0-9]{1,16}/gi;
    const expected = name.toLowerCase();
    const consistent = value => !value || (value.length <= 1024
      && [...value.matchAll(uploadName)].every(match => match[0].toLowerCase() === expected));
    const nodes = [card];
    let textLength = 0;
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i], declared = node.getAttribute('data-file-name');
      if (declared !== null && declared !== name) return false;
      if (!['aria-label', 'title', 'alt'].every(key => consistent(node.getAttribute(key)))) return false;
      // Inspect direct text as well as accessible names. Cap the traversal
      // before expanding a collection or joining an arbitrarily large subtree.
      if (node.childNodes.length > 32) return false;
      for (const child of node.childNodes) {
        if (child.nodeType === 3) {
          textLength += child.nodeValue.length;
          if (textLength > 1024) return false;
        }
      }
      if (nodes.length + node.children.length > 32) return false;
      for (const child of node.children) nodes.push(child);
    }
    // Filenames can be split across styled spans. The traversal bounded the
    // complete text before joining it in document order.
    return consistent(card.textContent);
  }
  // Only a visible status inside the verified member can describe its failure.
  // Labels on page notices, neighbouring uploads and nested actions have other owners.
  function visibleFailureText(card, excluded = cardSelector + ',input,textarea,[contenteditable="true"]', shown = visible) {
    const nodes = [card];
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];
      if (!node.children.length && node.textContent.length <= 32
          && /^(上传未成功|上传失败|upload failed)$/i.test(node.textContent.trim()) && shown(node)) return true;
      if (nodes.length + node.children.length > 32) return false;
      for (const child of node.children) {
        if (!child.matches(excluded)) nodes.push(child);
      }
    }
    return false;
  }
  function composerPreview(card, image, name) {
    return card?.matches('button[type="button"][data-assistant-image-link]')
      && card.parentElement?.matches('figure[data-composer-image-attachment]')
      && card.getAttribute('aria-label') === name && card.children.length === 1
      && image?.parentElement === card && image.matches('img[src][data-assistant-image][data-composer-image-attachment-preview]')
      && image.getAttribute('alt') === name;
  }
  // The real upload error is on a sibling of the image button. Only the
  // figure containing this exact preview can own its filename-specific Retry.
  function ownUploadRetry(card, image, name, requireEnabled = true) {
    if (!composerPreview(card, image, name) || !renderedPreview(card) || !renderedPreview(image)) return false;
    const figure = card.parentElement;
    if (figure.children.length > 3 || !consistentCardLabels(figure, name)
        || figure.querySelectorAll('img').length !== 1) return false;
    let retry = null;
    for (const child of figure.children) {
      if (child === card || child.matches('button[type="button"][data-composer-remove-image]')) continue;
      if (retry || !child.matches('button[type="button"][data-composer-image-upload-retry]')) return false;
      retry = child;
    }
    if (!retry || !renderedPreview(retry)
        || (requireEnabled && (retry.disabled || blocked(retry) || retry.matches(':disabled')))) return false;
    return namedFailedRetry(retry, name);
  }
  function namedFailedRetry(retry, name) {
    const label = retry.getAttribute('aria-label') || '', title = retry.getAttribute('title') || '';
    if (label === 'Retry uploading ' + name) return title === 'Failed to upload file.';
    // The filename must be the complete operand of the localized retry action.
    // A filename mentioned in a description or a generic retry is insufficient.
    return label.endsWith(name) && /^(?:重试(?:上传)?|重新上传)(?:文件)?[ ：:]*$/.test(label.slice(0, -name.length))
      && /^(?:上传未成功|上传失败|上传文件失败|文件上传失败|无法上传文件)。?$/.test(title);
  }
  // Keep only a weak node and a change bit, never a signed URL or inline
  // payload. The narrow observer expires even on documents with older registries.
  function unchangedPreview(imageRef, shellRef, name, boundBlob, figurePreview = false, edgeNodes = null) {
    let changed = false;
    let placement;
    const invalidate = () => { changed = true; observer.disconnect(); placement?.disconnect(); clearTimeout(timer); };
    const inspect = records => {
      if (!records.length) return;
      const image = imageRef?.deref(), shell = shellRef.deref();
      if (!shell?.isConnected || records.length > 32) return invalidate();
      for (const record of records) {
        if (edgeNodes) {
          const removed = record.removedNodes || [];
          if (removed.length > 32 || edgeNodes.some(ref => {
            const node = ref.deref();
            return !node || (record.type === 'attributes' && record.target === node)
              || [...removed].some(previous => previous === node || previous.contains(node));
          })) return invalidate();
        }
        if (figurePreview && (record.type === 'attributes' && (record.target === shell || record.target === image)
            || record.removedNodes?.length > 32 || [...(record.removedNodes || [])].includes(image))) return invalidate();
        if (record.type === 'attributes' && record.target.tagName === 'IMG'
            && ['src', 'srcset', 'alt'].includes(record.attributeName)) return invalidate();
        for (const node of record.addedNodes || []) {
          if (node.nodeType !== 1 || node === image) continue;
          // Two renderings of the exact bound blob can coexist. Only the
          // original node may report its own failure while both are present.
          if (boundBlob && node.tagName === 'IMG' && node.getAttribute('src') === boundBlob
              && fileNamePattern(name).test(node.getAttribute('alt') || '')) continue;
          if (!consistentCardLabels(node, name) || node.matches('img[src]') || node.querySelector('img[src]')) return invalidate();
        }
      }
      // Losing the original preview without a complete local failure in this
      // render ends the binding. A later occupant cannot revive that old slot.
      if (imageRef && (!image || !shell.contains(image))) {
        if (!consistentCardLabels(shell, name) || !completeOwnName(shell, name)
            || !visibleFailureText(shell) || shell.querySelector('img[src]')) invalidate();
      }
    };
    const observer = new MutationObserver(inspect);
    observer.observe(shellRef.deref(), {subtree: true, childList: true, attributes: true, characterData: true,
      attributeFilter: ['src', 'srcset', 'alt', 'data-file-name', 'title', 'aria-label', ...(figurePreview ? ['data-assistant-image-link', 'data-assistant-image', 'data-composer-image-attachment-preview'] : [])]});
    const moved = records => {
      if (!records.length) return;
      if (records.length > 32 || records.some(record => record.type === 'attributes'
          || record.removedNodes.length > 32 || [...record.removedNodes].includes(shellRef.deref()))) invalidate();
    };
    if (figurePreview || edgeNodes) {
      placement = new MutationObserver(moved);
      placement.observe(shellRef.deref().parentElement, figurePreview
        ? {childList:true, attributes:true, attributeFilter:['data-composer-image-attachment']} : {childList:true});
    }
    const timer = setTimeout(invalidate, 600000);
    timer?.unref?.();
    return () => { if (placement) moved(placement.takeRecords()); inspect(observer.takeRecords()); return !changed; };
  }
  function completeOwnName(card, name) {
    // Call only after consistentCardLabels has bounded this subtree.
    const filename = fileNamePattern(name);
    return card.getAttribute('data-file-name') === name || filename.test(card.textContent)
      || ['title', 'aria-label'].some(key => filename.test(card.getAttribute(key) || ''));
  }
  // The ordinary progress card can identify itself only by its accessible
  // name. Keep that exact shell through the transition to its error label.
  function watchMeterCard(shellRef, meterRef, name) {
    let retired = false;
    const stop = () => {
      retired = true;
      contents.disconnect(); placement.disconnect(); clearTimeout(timer);
    };
    const checkPlacement = records => {
      const shell = shellRef.deref();
      if (!shell?.isConnected || records.length > 32
          || records.some(record => record.removedNodes.length > 32 || [...record.removedNodes].includes(shell))) stop();
    };
    const meterSelector = 'progress,[role="progressbar"]';
    const checkContents = records => {
      const card = shellRef.deref(), meter = meterRef.deref();
      if (!card?.isConnected || records.length > 32) return stop();
      for (const record of records) {
        if (record.type === 'attributes') {
          if (record.target === card || record.attributeName === 'role'
              || !consistentCardLabels(record.target, name)) return stop();
        }
        if (record.addedNodes?.length > 32) return stop();
        for (const node of record.addedNodes || []) {
          if (node.nodeType !== 1) continue;
          if (!consistentCardLabels(node, name) || node.matches(previewSelector)
              || node.querySelector(previewSelector)) return stop();
        }
      }
      if (card.getAttribute('aria-label') !== name || !consistentCardLabels(card, name)) return stop();
      if (!card.contains(meter) && !visibleFailureText(card, independentMemberContent, renderedPreview)) {
        // Frameworks can clear the meter in one render and add the error in
        // another. The empty shell keeps its identity but proves no live state.
        const text = card.textContent.trim();
        if ((text && text !== name) || card.querySelector(independentMemberContent)) stop();
      }
    };
    const contents = new MutationObserver(checkContents);
    contents.observe(shellRef.deref(), {subtree:true, childList:true, characterData:true, attributes:true,
      attributeFilter:['role','aria-label','data-file-name','title','alt','src','srcset']});
    const placement = new MutationObserver(checkPlacement);
    placement.observe(shellRef.deref().parentElement, {childList:true});
    const timer = setTimeout(stop, 600000);
    timer?.unref?.();
    return requireError => {
      if (retired) return false;
      checkPlacement(placement.takeRecords());
      checkContents(contents.takeRecords());
      const card = shellRef.deref();
      if (retired || !renderedPreview(card)) return false;
      const meters = card.querySelectorAll(meterSelector);
      if (card.querySelector('img[src]') || meters.length > 1 || (meters.length && meters[0] !== meterRef.deref())) return false;
      return visibleFailureText(card, independentMemberContent, renderedPreview) || (!requireError && meters.length === 1 && renderedPreview(meters[0]));
    };
  }
  const errorShellSelector = 'span[class~="group/composer-attachment"]';
  function failureShellParts(shell, binding, name) {
    if (!shell || !binding || !shell.matches(errorShellSelector) || shell.hasAttribute('role')
        || shell.hasAttribute('aria-label') || shell.hasAttribute('data-file-name') || shell.children.length !== 2
        || shell.parentElement?.closest(errorShellSelector + ',' + cardSelector + ',[role="dialog"],[role="menu"],article,aside')
        || !inOriginalCardContainer(shell, binding)) return null;
    const row = shell.parentElement, lane = row?.parentElement, layout = lane?.parentElement;
    if (!row?.matches('div.flex') || !lane?.classList || ![...lane.classList].some(c => c.startsWith('ComposerLayoutAttachments-'))
        || !layout?.matches('[data-composer-layout]') || !layout.contains(binding.editor)
        || layout !== binding.editor.closest('[data-composer-layout]')) return null;
    const [surface, remove] = shell.children;
    if (!surface.matches('span.composer-attachment-surface') || !remove.matches('button[type="button"]')
        || !['移除 ' + name, 'Remove ' + name].includes(remove.getAttribute('aria-label'))
        || remove.disabled || remove.matches(':disabled') || blocked(shell) || blocked(remove) || !visible(remove) || !renderedPreview(surface)) return null;
    return {surface, remove};
  }
  function originalMemberSelectors(name) {
    // begin validates the generated file name before it can reach a selector.
    return ['button[aria-label="移除 ' + name + '"]', 'button[aria-label="Remove ' + name + '"]',
      'button[aria-label="Retry uploading ' + name + '"]', 'span[role="alert"][aria-label="' + name + '"]'];
  }
  function failureShellBeforeInput(name) {
    // Remember shells and their individual identifying members, including
    // ones the page could later reparent into a newly mounted tile.
    const selectors = [errorShellSelector, 'span.composer-attachment-surface', 'span.truncate', ...originalMemberSelectors(name)];
    const nodes = document.querySelectorAll(selectors.join(','));
    return nodes.length <= 256 ? new WeakSet(nodes) : null;
  }
  function hasOriginalFailureLanes(surface) {
    if (surface.children.length === 2) return true;
    if (surface.children.length !== 3) return false;
    // The live tile can append an empty, noninteractive border above its two
    // content lanes. Never ignore arbitrary siblings or their descendants.
    const ring = surface.lastElementChild;
    return ring.matches('span.composer-attachment-surface.pointer-events-none.absolute.inset-0.rounded-2xl.ring-1.ring-inset.ring-border')
      && !ring.childNodes.length
      && [...ring.attributes].every(attr => attr.name === 'class' || (attr.name === 'aria-hidden' && attr.value === 'true'))
      && getComputedStyle(ring).pointerEvents === 'none';
  }
  function currentNamedFailure(op, binding) {
    if (!binding?.target.clickBindingID || !op.oldErrorMembers || op.inputCount !== 1 || !op.changeReturned) return null;
    const [zhRemove, enRemove, retrySelector, alertSelector] = originalMemberSelectors(op.name);
    const alerts = document.querySelectorAll(alertSelector);
    if (alerts.length !== 1) return null;
    const alert = alerts[0], status = alert.parentElement, visual = status?.parentElement;
    const surface = visual?.parentElement, shell = surface?.parentElement;
    const parts = failureShellParts(shell, binding, op.name);
    if (!parts || parts.surface !== surface || !consistentCardLabels(shell, op.name) || !hasOriginalFailureLanes(surface) || surface.children[0] !== visual
        || visual.tagName !== 'SPAN' || visual.children.length !== 1 || status.tagName !== 'SPAN'
        || status.children.length !== 2 || status.children[0] !== alert || alert.children.length !== 1
        || shell.querySelector('img,progress,[role="progressbar"],input,[contenteditable],'+errorShellSelector)
        || shell.querySelectorAll('button,[role="button"]').length !== 2 || shell.querySelectorAll('[role="alert"]').length !== 1) return null;
    const retry = status.children[1], message = alert.children[0], names = surface.children[1].querySelectorAll('span.truncate');
    if (surface.children[1].tagName !== 'SPAN' || names.length !== 1 || names[0].parentElement !== surface.children[1]
        || names[0].children.length || names[0].textContent.trim() !== op.name
        || message.tagName !== 'SPAN' || message.children.length || !/^(?:上传未成功|上传失败|upload failed)$/i.test(message.textContent.trim())
        || !retry.matches('button[type="button"]') || retry.getAttribute('aria-label') !== 'Retry uploading ' + op.name
        || !/^(?:Retry|重试)$/i.test(retry.textContent.trim()) || retry.disabled || retry.matches(':disabled') || blocked(retry)
        || retry.tabIndex < 0 || (getComputedStyle(retry).pointerEvents === 'none'
          && (!visual.classList.contains('pointer-events-none') || getComputedStyle(status).pointerEvents !== 'none'
            || retry.style.pointerEvents === 'none' || retry.classList.contains('pointer-events-none')))
        || ![alert, message, names[0], retry].every(renderedPreview)
        || [shell,surface,alert,names[0],retry,parts.remove].some(el => op.oldErrorMembers.has(el))) return null;
    for (const node of shell.querySelectorAll('[aria-label],[data-file-name],[title]')) {
      if ((node.hasAttribute('aria-label') && ![alert,retry,parts.remove].includes(node))
          || ['data-file-name','title'].some(attr => node.hasAttribute(attr) && node.getAttribute(attr) !== op.name)) return null;
    }
    const sameName = ['aria-label','data-file-name','title','alt'].map(attr => '[' + attr + '="' + op.name + '"]').join(',');
    if ([...document.querySelectorAll(sameName)].some(node => !shell.contains(node))) return null;
    const removes = document.querySelectorAll(zhRemove + ',' + enRemove);
    const retries = document.querySelectorAll(retrySelector);
    return removes.length === 1 && removes[0] === parts.remove && retries.length === 1 && retries[0] === retry ? shell : null;
  }
  // Changing the contents of the surface can legitimately replace a preview
  // with an error. Losing or reusing the original shell/placement cannot.
  function liveOriginalFailure(op, binding, retained) {
    const shell = retained?.();
    return !!shell && sameDraft(binding) && currentNamedFailure(op, binding) === shell;
  }
  function liveAcceptedErrorShell(op) {
    return liveOriginalFailure(op, op.acceptedErrorBinding?.deref(), op.acceptedErrorShell);
  }
  function retainFailureShell(shell, parts) {
    const weak = new WeakRef(shell), remove = new WeakRef(parts.remove), surface = new WeakRef(parts.surface);
    const chain = [];
    for (let node = shell; node; node = node.parentElement) chain.push(new WeakRef(node));
    let retired = false;
    const stop = () => { retired = true; observer.disconnect(); clearTimeout(timer); };
    const check = records => {
      for (const record of records) {
        if (record.type === 'attributes' || [...record.removedNodes].some(node =>
          node === surface.deref() || node === remove.deref() || chain.some(ref => ref.deref() === node))) { stop(); return; }
      }
    };
    const observer = new MutationObserver(check);
    const timer = setTimeout(stop, 600000); timer?.unref?.();
    for (const ref of chain) observer.observe(ref.deref(), {childList:true});
    observer.observe(parts.remove, {attributes:true,attributeFilter:['aria-label']});
    return () => { check(observer.takeRecords()); return retired ? null : weak.deref(); };
  }
  function captureFailureWatch(op, accepted, matches) {
    if (typeof WeakRef !== 'function') return;
    const filename = fileNamePattern(op.name), views = [], cards = new Set();
    // Secondary views are optional. A busy document cannot enlarge the
    // post-START scan beyond 16 candidates or the retained set beyond four.
    for (const match of [accepted, ...matches.slice(0, 16)]) {
      const {node, card} = match;
      const image = match.preview.tagName === 'IMG' ? match.preview : null;
      const labelledImage = image && filename.test(image.getAttribute('alt') || '')
        && visible(image) && !!image.getAttribute('src');
      if (!card || cards.has(card)) continue;
      const local = inOriginalCardContainer(card, op.binding);
      if (!local && (!card.parentElement || !independentCardPortal(card, op.binding))) continue;

      const declared = card.getAttribute('data-file-name');
      if (declared !== null && declared !== op.name) continue;
      const namedCard = declared === op.name;
      const label = ['aria-label', 'title', 'alt'].find(key => filename.test(node.getAttribute(key) || ''));
      // Never retain inline image data, signed remote URLs or page text.
      const imageSource = image?.getAttribute('src');
      const preview = imageSource?.startsWith('blob:') && imageSource.length <= 256 ? image : null;
      const src = preview?.getAttribute('src');
      // Only the actual START node may rely on its own filename and preview.
      // A separate view must show an object URL minted from this exact File.
      const sameFile = !!src && currentFileURL(op, src);
      if (match !== accepted && !sameFile) continue;
      const opaqueImage = match === accepted && labelledImage && !preview
        && inOriginalCardContainer(card, op.binding) && card.querySelectorAll('img[src]').length === 1;
      const accessibleMeter = match === accepted && local && !image && declared === null
        && card.matches('button,[role="button"]') && card.getAttribute('aria-label') === op.name
        && match.preview.closest(cardSelector) === card && card.querySelectorAll(previewSelector).length === 1;
      if (!accessibleMeter && !opaqueImage && !namedCard && !sameFile && (!label || !preview)) continue;
      if (!consistentCardLabels(card, op.name)) continue;
      cards.add(card);
      const initialImage = image;
      const figurePreview = local && match === accepted && composerPreview(card, image, op.name);
      let edgeNodes = null;
      if (local && match === accepted && native.applicationID === 'com.microsoft.edgemac'
          && image && edgeImageCard(image, op, filename) === card) {
        edgeNodes = [...card.children].map(child => new WeakRef(child));
        for (let node = image; node !== card; node = node.parentElement) edgeNodes.push(new WeakRef(node));
        edgeNodes.push(new WeakRef(card));
      }
      views.push({meterCard: accessibleMeter ? watchMeterCard(new WeakRef(card), new WeakRef(match.preview), op.name) : null,
        opaqueImage: opaqueImage ? new WeakRef(image) : null,
        figurePreview, edgeMember: edgeNodes !== null,
        unchanged: opaqueImage || namedCard || figurePreview || edgeNodes ? unchangedPreview(initialImage && new WeakRef(initialImage), new WeakRef(card), op.name, src, figurePreview, edgeNodes) : null,
        startedWithoutImage: !initialImage,
        imageParent: opaqueImage ? new WeakRef(image.parentElement) : null, card: new WeakRef(card), parent: new WeakRef(card.parentElement), namedCard, label, witness: new WeakRef(node),
        preview: preview ? new WeakRef(preview) : null, src, sameFile,
        portalParent: local ? null : new WeakRef(card.parentElement)});
      if (views.length === 4) break;
    }
    if (views.length) op.failureWatch = {binding: new WeakRef(op.binding), views};
  }

  function matchesOriginalCard(op, view, binding, requireError = true) {
    let card = view.card.deref();
    const retainedPreview = view.preview?.deref();
    if (!card?.isConnected && view.sameFile && retainedPreview?.isConnected
        && retainedPreview.getAttribute('src') === view.src) {
      // A component can replace its shell while moving the very same preview.
      // The original File URL, node, parent and full generated name must agree.
      const next = retainedPreview.closest(cardSelector);
      if (next && next.parentElement === view.parent?.deref() && next.getAttribute('data-file-name') === op.name) card = next;
    }
    if (!card?.isConnected || (view.portalParent
        ? view.portalParent.deref() !== card.parentElement || !independentCardPortal(card, binding)
        : !inOriginalCardContainer(card, binding))) return false;
    const declared = card.getAttribute('data-file-name');
    // v18 watches in an already-open document used only data-file-name and
    // the card itself. Preserve that read path without expanding its evidence.
    if (view.namedCard === undefined) {
      return declared === op.name && (!requireError || ['error', 'failed'].includes(card.getAttribute('data-state')))
        && consistentCardLabels(card, op.name);
    }
    if (view.parent.deref() !== card.parentElement) return false;
    if (view.namedCard ? declared !== op.name : declared !== null && declared !== op.name) return false;
    if (card === view.card.deref() && view.unchanged && !view.unchanged()) return false;
    // Old watches did not record whether the button left its figure or the
    // filename changed and changed back. Do not promote those records.
    if (view.figurePreview === true && card === view.card.deref() && !view.portalParent) {
      const originalImage = view.opaqueImage?.deref() || retainedPreview;
      if ((view.opaqueImage || originalImage && originalImage.getAttribute('src') === view.src)
          && ownUploadRetry(card, originalImage, op.name)) return true;
    }
    // A named, active retry on this continuously tracked Edge image card
    // describes a local failure. An adjacent card or generic Retry is unrelated.
    if (view.edgeMember && card === view.card.deref() && !view.portalParent
        && ['failed', 'error'].includes(card.getAttribute('data-state')) && card.children.length === 3) {
      const image = view.opaqueImage?.deref() || retainedPreview;
      const retries = [...card.children].filter(child => child.matches('button[type="button"]') && namedFailedRetry(child, op.name));
      if (image && image.isConnected && card.contains(image) && renderedPreview(image)
          && card.querySelectorAll('img').length === 1 && consistentCardLabels(card, op.name)
          && retries.length === 1 && renderedPreview(retries[0]) && !blocked(retries[0])
          && !retries[0].matches(':disabled')) return true;
    }
    if (view.meterCard) return view.meterCard(requireError);
    if (view.startedWithoutImage && card.querySelector('img[src]')) return false;
    // Some failed cards keep their exact named shell but replace the image
    // with a local error status and filename. A different preview vetoes it.
    if (!view.opaqueImage && view.namedCard && !card.querySelector('img[src]') && visibleFailureText(card)
        && consistentCardLabels(card, op.name)) return true;
    if (view.opaqueImage) {
      if (!consistentCardLabels(card, op.name)) return false;
      const image = view.opaqueImage.deref();
      if (image?.isConnected) {
        return card.contains(image) && card.querySelectorAll('img[src]').length === 1 && image.parentElement === view.imageParent.deref()
          && fileNamePattern(op.name).test(image.getAttribute('alt') || '')
          && (!requireError || visibleFailureText(card));
      }
      // A failed member can replace the image with a label and filename. Its
      // original shell, parent and draft must survive, with no successor image.
      return !card.querySelector('img[src]') && completeOwnName(card, op.name) && visibleFailureText(card);
    }
    if (view.preview || !view.namedCard) {
      const preview = view.preview?.deref();
      if (!preview || preview.closest(cardSelector) !== card || preview.getAttribute('src') !== view.src) return false;
      if ((!view.namedCard || view.sameFile) && view.label && card === view.card.deref()) {
        const witness = view.witness.deref();
        if (!witness || witness.closest(cardSelector) !== card
            || !fileNamePattern(op.name).test(witness.getAttribute(view.label) || '')) return false;
      }
    }
    const failed = node => ['failed', 'error'].includes(node.getAttribute('data-state'));
    if (!requireError || (card.querySelectorAll('img[src]').length <= 1 && (failed(card) || visibleFailureText(card)))) return consistentCardLabels(card, op.name);
    // Only the initially bound, still-identical preview can contribute a
    // descendant's error. An inserted status, toast, or sibling cannot.
    const preview = view.preview?.deref();
    return !!preview && preview.closest(cardSelector) === card && preview.getAttribute('src') === view.src
      && (view.sameFile || fileNamePattern(op.name).test(preview.getAttribute('alt') || ''))
      && failed(preview) && consistentCardLabels(card, op.name);
  }
  // A visible preview can be replaced with an error between native reads. Only
  // sample the live original surface at mutation delivery. Never infer a START
  // from removed nodes, a transient mutation record, or a pending request.
  function watchHandoff(op) {
    const surface = op.binding.form;
    if (surface === document.body || surface === document.documentElement) return;
    const deadline = performance.now() + 10000;
    let batches = 0;
    const stop = () => {
      observer.disconnect();
      clearTimeout(timer);
      op.stopHandoffWatch = null;
    };
    const observer = new MutationObserver(() => {
      if (++batches > 64 || performance.now() >= deadline || !surface.isConnected
          || !sameDraft(op.binding) || op.binding.form !== surface) return stop();
      sample(op, surface);
    });
    const timer = setTimeout(stop, 10000);
    timer?.unref?.();
    op.stopHandoffWatch = stop;
    observer.observe(surface, {subtree: true, childList: true, attributes: true, characterData: true,
      attributeFilter: ['src', 'alt', 'title', 'aria-label', 'role', 'data-file-name', 'value', 'max',
        'aria-valuenow', 'aria-valuemin', 'aria-valuemax', 'hidden', 'class', 'style']});
  }
  const independentMemberContent = cardSelector + ',' + controlSelector
    + ',input,select,textarea,summary,[role="link"],[role="tab"],[role="checkbox"],[role="switch"],[contenteditable="true"]';
  // A derived data URL must encode the exact input image rendered by this browser.
  function watchEdgeEncodedPreview(file, name) {
    // The collector permits 128 MiB and 160M pixels. Comparing encoded bytes
    // needs no extra pixel buffer. Re-encoding uses a smaller display budget.
    const maxEncodedBytes = MAX_BYTES, maxRenderPixels = 16 * 1024 * 1024;
    if (!(file instanceof File) || !['image/png', 'image/jpeg'].includes(file.type)
        || !file.size || file.size > maxEncodedBytes || file.name !== name
        || !/^riftlet-[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.(?:png|jpe?g)$/i.test(name)
        || top !== self) return null;
    const address = location.href, root = document.documentElement, entry = navigation.currentEntry?.id;
    if (!entry) return null;
    let image = null, source = null, shell = null, monitor = null, state = 'unavailable', closed = false;
    const timer = setTimeout(close, 60000);
    const current = () => !closed && document.documentElement === root && navigation.currentEntry?.id === entry
      && location.href === address;
    function close() {
      clearTimeout(timer); closed = true;
      monitor?.disconnect(); monitor = null; file = null; image = null; shell = null; source = null; state = 'unavailable';
    }
    // Each slice ends on a three-byte boundary. Do not materialize another
    // full-size URL, byte array or digest input in the browser process.
    async function identical(blob, url, prefix) {
      if (!blob.size || blob.size > maxEncodedBytes || url.length !== prefix.length + 4 * Math.ceil(blob.size / 3)) return false;
      const chunk = 48 * 1024;
      for (let offset = 0; offset < blob.size; offset += chunk) {
        const bytes = new Uint8Array(await blob.slice(offset, offset + chunk).arrayBuffer());
        if (!current()) return false;
        const encoded = btoa(String.fromCharCode(...bytes));
        if (!url.startsWith(encoded, prefix.length + offset / 3 * 4)) return false;
      }
      return true;
    }
    async function dimensions(original) {
      if (original.type === 'image/png') {
        const h = new DataView(await original.slice(0, 24).arrayBuffer());
        if (h.byteLength >= 24 && h.getUint32(0) === 0x89504e47 && h.getUint32(4) === 0x0d0a1a0a
            && h.getUint32(8) === 13 && h.getUint32(12) === 0x49484452) return [h.getUint32(16), h.getUint32(20)];
        return null;
      }
      // Bound header work even for JPEGs with very large metadata segments.
      const h = new DataView(await original.slice(0, 512 * 1024).arrayBuffer());
      if (h.byteLength < 4 || h.getUint16(0) !== 0xffd8) return null;
      let at = 2;
      while (at + 4 <= h.byteLength && h.getUint8(at++) === 0xff) {
        let marker = h.getUint8(at++);
        while (marker === 0xff && at < h.byteLength) marker = h.getUint8(at++);
        if (at + 2 > h.byteLength || marker === 0xda || marker === 0xd9) return null;
        const length = h.getUint16(at);
        if (length < 2 || at + length > h.byteLength) return null;
        if ([0xc0, 0xc1, 0xc2].includes(marker) && length >= 8) return [h.getUint16(at + 5), h.getUint16(at + 3)];
        at += length;
      }
      return null;
    }
    async function matches(original, url) {
      const originalPrefix = 'data:' + original.type + ';base64,', pngPrefix = 'data:image/png;base64,';
      if (url.startsWith(originalPrefix) && await identical(original, url, originalPrefix)) return true;
      if (!current() || !url.startsWith(pngPrefix) || typeof OffscreenCanvas !== 'function'
          || typeof createImageBitmap !== 'function') return false;
      const size = await dimensions(original);
      if (!current() || !size || !size[0] || !size[1] || size.some(value => value > 50000)
          || size[0] * size[1] > maxRenderPixels) return false;
      const bitmap = await createImageBitmap(original);
      let canvas, png;
      try {
        if (!current() || bitmap.width * bitmap.height !== size[0] * size[1]
            || bitmap.width !== image.naturalWidth || bitmap.height !== image.naturalHeight) return false;
        canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
        const context = canvas.getContext('2d', {colorSpace: 'srgb'});
        if (!context) return false;
        context.drawImage(bitmap, 0, 0);
        png = await canvas.convertToBlob({type:'image/png'});
      } finally {
        bitmap.close();
        if (canvas) canvas.width = canvas.height = 0;
      }
      return current() && png.type === 'image/png' && identical(png, url, pngPrefix);
    }
    const altered = record => record.type === 'attributes' || record.target !== shell?.parentElement
      || [...record.removedNodes, ...record.addedNodes].includes(shell);
    function inspect(candidate, card, settled) {
      try {
        if (!current()) { close(); return 'unavailable'; }
        if (!(candidate instanceof HTMLImageElement) || !candidate.isConnected
            || !candidate.complete || candidate.naturalWidth <= 0) return 'unavailable';
        const src = candidate.getAttribute('src');
        if (image && (candidate !== image || card !== shell || src !== source || monitor.takeRecords().some(altered))) {
          close(); return 'mismatch';
        }
        if (image) return candidate.currentSrc === source ? state : 'unavailable';
        if (!src || !(src.startsWith('data:image/png;base64,') || src.startsWith('data:image/jpeg;base64,'))
            || candidate.currentSrc !== src || src.length > 23 + 4 * Math.ceil(maxEncodedBytes / 3)) return 'unavailable';
        image = candidate; shell = card; source = src; state = 'encoding';
        monitor = new MutationObserver(records => { if (records.some(altered)) close(); });
        monitor.observe(shell, {subtree:true, childList:true, attributes:true,
          attributeFilter:['src','srcset','alt','title','aria-label','data-file-name']});
        monitor.observe(shell.parentElement, {childList:true});
        // Never re-read a changed/replaced card and never start another encode for this input.
        // Serialize only the content comparison, never the user's next input.
        // Waiting jobs do not decode pixels and drop their work when retired.
        const pending = Promise.resolve(registry.edgeComparisonTail).then(() => current() && matches(file, source));
        const tail = pending.catch(() => false);
        registry.edgeComparisonTail = tail;
        tail.then(() => { if (registry.edgeComparisonTail === tail) registry.edgeComparisonTail = null; });
        tail.then(ok => {
          if (!closed) state = ok ? 'matched' : 'mismatch';
        }).catch(() => { if (!closed) state = 'unavailable'; }).then(() => { if (!closed) settled(); });
        return state;
      } catch { close(); return 'unavailable'; }
    }
    return {inspect, close};
  }
  // Edge's encoded preview can be inside a plain span or a named nested
  // popup. Its named Remove button identifies the outer, single-image tile.
  function edgeImageCard(image, op, filename) {
    if (image.tagName !== 'IMG' || !filename.test(image.getAttribute('alt') || '')) return null;
    for (let node = image.parentElement, depth = 0; node && depth++ < 8 && node !== op.binding.form; node = node.parentElement) {
      if (node.tagName !== 'DIV' || node.children.length !== 2) continue;
      const remove = [...node.children].find(child => child.matches('button,[role="button"]') &&
        ['aria-label','title'].some(key => {
          const label = child.getAttribute(key) || '';
          return /(?:\bremove\b|移除|删除)/i.test(label) && filename.test(label);
        }));
      if (!remove || remove.contains(image) || !renderedPreview(node)
          || node.querySelectorAll('img').length !== 1 || !consistentCardLabels(node, op.name)) continue;
      const visual = [...node.children].find(child => child !== remove);
      if (node.matches('.composer-attachment-surface')) {
        // This popup's named Remove button is transparent until hover. The
        // preview itself must be visible, and both must belong to this tile.
        if (node.matches('[role="button"][aria-haspopup="dialog"]') && node.getAttribute('aria-label') === op.name
            && remove.matches('button[type="button"]') && visual.tagName === 'SPAN' && image.parentElement === visual
            && image.getAttribute('alt') === op.name && renderedPreview(visual)) return node;
        continue;
      }
      if (!renderedPreview(remove)) continue;
      const named = element => ['aria-label','data-file-name','title'].some(key => filename.test(element.getAttribute(key) || ''));
      if (!visual.contains(image) || !renderedPreview(visual)) continue;
      const labels = [node, ...node.querySelectorAll('[aria-label],[alt],[data-file-name],[title]')]
        .filter(el => named(el) || filename.test(el.getAttribute('alt') || ''));
      const popups = labels.filter(el => el !== node && el.tagName === 'DIV' && visual.contains(el) && el.contains(image));
      if (popups.length === 1 && labels.every(el => [popups[0], remove, image].includes(el))) return node;
      if (visual.tagName === 'SPAN' && labels.length === 3 && [node, image, remove].every(el => labels.includes(el)))
        return node;
    }
    return null;
  }
  // Labels, pixels and progress belong to one attachment member.
  function startMember(op, card, filename) {
    const nodes = [card], images = [], meters = [];
    const otherFile = /riftlet-[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}\.[a-z0-9]{1,16}/gi;
    const conflicts = value => [...value.matchAll(otherFile)].some(match => match[0].toLowerCase() !== op.name.toLowerCase());
    let text = '', labelNode = null;
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];
      if (node.childNodes.length > 32 || nodes.length + node.children.length > 32) return null;
      const declared = node.getAttribute('data-file-name');
      if (declared && declared !== op.name && /\.[a-z0-9]{1,16}$/i.test(declared)) return null;
      for (const key of ['data-file-name', 'aria-label', 'title', 'alt']) {
        const value = node.getAttribute(key);
        if (!value) continue;
        if (value.length > 1024 || conflicts(value)) return null;
        if (!labelNode && filename.test(value)) labelNode = node;
      }
      if (node.tagName === 'IMG' && node.getAttribute('src')) {
        const src = node.getAttribute('src');
        if (!usablePreviewSource(op, src) || !usablePreviewSource(op, node.currentSrc)) return null;
        if (node.hasAttribute('srcset') && node.currentSrc !== src) return null;
        images.push(node);
      } else if (node.matches('progress,[role="progressbar"]')) {
        meters.push(node);
      }
      for (const child of node.childNodes) {
        if (child.nodeType === 3) {
          if (text.length + child.nodeValue.length > 1024) return null;
          text += child.nodeValue;
        } else if (child.nodeType === 1 && !child.matches(independentMemberContent)) {
          nodes.push(child);
        }
      }
    }
    if (conflicts(text)) return null;
    if (!labelNode && filename.test(text)) labelNode = card;
    for (const image of images) {
      const src = image.getAttribute('src').trim();
      if (!src || !renderedPreview(image)) continue;
      const ownFile = currentFileURL(op, src);
      const explicitlyNamed = ['data-file-name', 'alt', 'aria-label', 'title'].some(key => filename.test(image.getAttribute(key) || ''));
      const alt = (image.getAttribute('alt') || '').trim();
      const genericPreview = !alt || /^(?:(?:uploaded |attachment )?image preview|preview of (?:the )?uploaded image|(?:上传(?:的)?|附件)?(?:图片|图像)(?:的)?预览)$/i.test(alt);
      if (!ownFile && !explicitlyNamed && (!labelNode || images.length !== 1 || !genericPreview)) continue;
      if (op.previewBaseline ? op.previewBaseline.get(image) === src : op.baseline.has(image)) continue;
      if (native.applicationID === 'com.microsoft.edgemac') {
        if (!inOriginalCardContainer(card, op.binding) || !image.complete || !image.naturalWidth
            || (image.currentSrc || '') !== src) continue;
        if (!ownFile && (!explicitlyNamed || op.previewBaseline?.has(image)
            || (!composerPreview(card, image, op.name) && edgeImageCard(image, op, filename) !== card)
            || op.encodedPreview?.inspect(image, card, () => sample(op)) !== 'matched')) continue;
      }
      return {node: labelNode || image, preview: image, card};
    }
    if (native.applicationID === 'com.microsoft.edgemac' || !labelNode || images.length > 1) return null;
    for (const meter of meters) {
      const value = previewValue(meter);
      if (!renderedPreview(meter) || typeof value !== 'object' || value.current <= value.min) continue;
      const previous = op.previewBaseline?.get(meter);
      if (previous !== undefined && (typeof previous !== 'object' || previous.min !== value.min
          || previous.max !== value.max || value.current <= previous.current)) continue;
      if (!op.previewBaseline && op.baseline.has(card)) continue;
      return {node: labelNode, preview: meter, card};
    }
    return null;
  }
  function sample(op, surface = null) {
    // The app may disable or remove its picker after accepting this file.
    // Observing that handoff needs the original draft, not another input slot.
    if (op.start || op.reportedCardFailure || !op.changeReturned || !sameDraft(op.binding)) return;
    const failedShell = currentNamedFailure(op, op.binding);
    if (failedShell) {
      op.reportedCardFailure = retainFailureShell(failedShell, failureShellParts(failedShell, op.binding, op.name));
      op.failureMemberID = registry.documentID + ':' + nodeID(failedShell);
      op.stopHandoffWatch?.(); op.encodedPreview?.close(); op.encodedPreview = null;
      return;
    }
    if (!surface) registry.blobWindowUntil = performance.now() + 10000;
    const hasError = node => {
      const card = node.closest('[data-file-name],[role="button"],button') || node;
      const errors = '[role="alert"],[data-state="error"],[data-state="failed"]';
      return !!node.closest(errors) || !!card.querySelector(errors) || visibleFailureText(card)
        || ownUploadRetry(card, card.children[0], op.name, false);
    };
    const filename = fileNamePattern(op.name);
    const named = node => ['data-file-name', 'aria-label', 'title', 'alt'].some(key => filename.test(node.getAttribute(key) || ''))
      || ((node.hasAttribute('data-file-name') || node.getAttribute('role') === 'button' || node.tagName === 'BUTTON')
        && filename.test(node.textContent || ''));
    const identifiesFile = node => named(node) || (node.tagName === 'IMG' && currentFileURL(op, node.getAttribute('src')));
    const identified = attachmentNodes(op.binding, surface || document).filter(node => node.isConnected && identifiesFile(node));
    if (identified.some(hasError)) return;
    const matches = [];
    const seen = new Set();
    for (const node of identified) {
      const edgeImage = native.applicationID === 'com.microsoft.edgemac' && node.tagName === 'IMG';
      const encodedCard = edgeImage && edgeImageCard(node, op, filename);
      const card = encodedCard || node.closest(cardSelector) || (node.tagName === 'IMG' ? node.parentElement : node);
      if (!card || seen.has(card)) continue;
      seen.add(card);
      const shell = node.closest(errorShellSelector);
      if (shell && (!op.oldErrorMembers || op.oldErrorMembers.has(shell)
          || [...shell.children].some(child => op.oldErrorMembers.has(child)))) continue;
      if (native.applicationID === 'com.microsoft.edgemac' && card.parentElement?.closest('.composer-attachment-surface')) continue;
      if (!inOriginalCardContainer(card, op.binding) && !independentCardPortal(card, op.binding)) continue;
      if (card === document.body || card === document.documentElement || card.contains(op.binding.editor)
          || card.parentElement?.closest(cardSelector + ',a[href],[role="menuitem"],[role="option"]')) continue;
      const match = startMember(op, card, filename);
      if (match && native.applicationID === 'com.microsoft.edgemac' && (hasError(card) || visibleFailureText(card))) continue;
      if (match) matches.push(match);
    }
    if (!matches.length) return;
    // Keep the ordinary whole-document veto for conflicting same-file error
    // views, while unrelated composer edits only inspect the composer.
    if (surface && attachmentNodes(op.binding).some(node => identifiesFile(node) && hasError(node))) return;
    op.stopHandoffWatch?.();
    // A compact tray and expanded view can both present this same exact
    // File. START needs one positive handoff; duplicate views are not inputs.
    const accepted = matches.find(match => op.binding.form.contains(match.card)) || matches[0];
    op.attachmentID = registry.documentID + ':' + nodeID(accepted.node);
    op.start = {version: 1, signal: 'attachmentAccepted', evidenceID: crypto.randomUUID(), inputCount: 1,
      inputSequence: op.inputSequence, startSequence: tick(), previousProgress: 0, currentProgress: 0,
      inputObservedAtMS: op.inputTime, startObservedAtMS: Math.max(op.inputTime, performance.now())};
    // A retained, same-name card may subsequently expose a local failure. Weak
    // references cannot keep a detached composer, input, or attachment alive.
    captureFailureWatch(op, accepted, matches);
    const shell = accepted.node.closest(errorShellSelector);
    const parts = failureShellParts(shell, op.binding, op.name);
    if (parts && !op.oldErrorMembers?.has(shell)) {
      op.acceptedErrorShell = retainFailureShell(shell, parts);
      op.acceptedErrorBinding = new WeakRef(op.binding);
    }
    op.encodedPreview?.close(); op.encodedPreview = null;
    op.binding = null; op.baseline.clear(); op.previewBaseline = null; op.urls.clear();
  }
  function observe(op) {
    sample(op);
    const result = blank(op.identity), item = result.observation;
    if (op.entryDiagnostics) result.entryDiagnostics = {...op.entryDiagnostics};
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
    if (op.reportedCardFailure) {
      item.state = 'unknown';
      if (liveOriginalFailure(op, op.binding, op.reportedCardFailure)) {
        item.state = 'originalCardFailed'; item.hasError = true; item.exactImageIdentity = true;
        item.attachmentID = op.failureMemberID; item.originalCardFailureInvocationID = op.invocationID;
      }
    }
    if (op.start) {
      // A past positive handoff remains true if a later input rerenders cards.
      // This is an immutable acceptance fact, not a current upload-status claim.
      item.state = 'uploadStarted'; item.belongsToOriginalDraft = true;
      item.attachmentID = op.attachmentID; item.exactImageIdentity = true;
      item.uploadStart = {...op.start};
      const watch = op.failureWatch, original = watch?.binding.deref();
      if (command.preferStartReceipt !== true && ((watch && sameDraft(original) && (watch.views || [watch]).some(view => matchesOriginalCard(op, view, original)))
          || liveAcceptedErrorShell(op))) {
        item.state = 'failed'; item.hasError = true;
        delete item.uploadStart;
      }
    }
    return result;
  }
  if (command.action === 'captureTarget') {
    if (!['com.google.Chrome', 'com.microsoft.edgemac'].includes(native.applicationID) || !native.sessionID
        || !native.windowID || !native.tabID) fail('NATIVE_CONTEXT_REQUIRED');
    const parts = composer();
    if (command.clickWitnessID != null) {
      const pin = command.clickWitnessID;
      if (!uuid(pin)) fail('CLICK_PIN_REFUSED');
      // Multiple clicks on the same continuously mounted editor share their
      // scheduling generation. The per-click input authority remains distinct.
      const generation = registry.witnessGeneration;
      if (!generation || generation.editor !== parts.editor || generation.form !== parts.form
          || generation.navigationID !== navigation.currentEntry.id || generation.address !== location.href) {
        registry.witnessGeneration = {editor: parts.editor, form: parts.form, navigationID: navigation.currentEntry.id,
          address: location.href, id: crypto.randomUUID()};
      }
      const target = {adapterID: 'chatgpt-web', surface: 'webChat', ...native, clickBindingID: pin,
        documentID: registry.documentID, composerID: nodeID(parts.editor) + ':' + nodeID(parts.form),
        draftGeneration: registry.witnessGeneration.id};
      const address = new URL(route());
      const id = address.origin === 'https://chatgpt.com' && /^\/(?:g\/[a-zA-Z0-9_-]+\/)?c\/([^/]+)\/?$/.exec(address.pathname)?.[1];
      if (uuid(id)) target.historyConversationID = id.toUpperCase();
      const pinned = {...parts, target, route: route(), navigation: registry.navigation};
      if (registry.clickBindings?.has(pin) || !validDraft(pinned)) fail('CLICK_PIN_REFUSED');
      // The write witness expires on blur. A read may continue on that same
      // document and composer until navigation or removal, including after focus returns.
      const href = location.href;
      const reader = bindOriginalReceiver(parts.editor, () => location.href === href &&
        parts.form.isConnected && parts.editor.isConnected && parts.form.contains(parts.editor));
      pinned.readOriginal = reader.current;
      setTimeout(() => { reader.close(); registry.clickBindings.delete(pin); }, 600000)?.unref?.();
      registry.clickBindings ||= new Map();
      registry.clickBindings.set(pin, pinned);
      return target;
    }
    if (native.applicationID === 'com.microsoft.edgemac') fail('CLICK_PIN_REFUSED');
    if (!validDraft(registry.current) || registry.current.editor !== parts.editor) {
      const address = new URL(route());
      const id = address.origin === 'https://chatgpt.com' && /^\/(?:g\/[a-zA-Z0-9_-]+\/)?c\/([^/]+)\/?$/.exec(address.pathname)?.[1];
      registry.current = {...parts, route: route(), navigation: registry.navigation,
        target: {adapterID: 'chatgpt-web', surface: 'webChat', ...native,
          ...(uuid(id) ? {historyConversationID: id.toUpperCase()} : {}),
          documentID: registry.documentID, composerID: nodeID(parts.editor) + ':' + nodeID(parts.form),
          draftGeneration: crypto.randomUUID()}};
    }
    return registry.current.target;
  }
  const binding = bindingFor(command.target);
  if (command.action === 'validate') {
    const readPinnedOriginal = command.requireLiveOriginal === true && binding?.target.clickBindingID;
    return {target: command.target, valid: readPinnedOriginal ? sameDraft(binding) : validDraft(binding)};
  }
  const identity = command.identity;
  if (!identity || !sameTarget(identity.target, command.target)) fail('TARGET_INVALID');
  const acknowledgement = (op, nextChunk) => ({operationID: op.identity.operationID, attempt: op.identity.attempt, nextChunk});
  let op = registry?.operations.get(identity.operationID);
  if (command.action === 'begin') {
    if (!validDraft(binding) || (binding.target.clickBindingID && binding.enrolled)) fail('TARGET_INVALID');
    const namePrefix = 'riftlet-' + identity.operationID + '.';
    if (op || !uuid(identity.operationID) || !uuid(identity.assetID) || !uuid(command.invocationID)
        || !Number.isSafeInteger(identity.attempt) || identity.attempt < 1 || !/^[a-f0-9]{64}$/.test(identity.assetSHA256)
        || typeof command.uploadName !== 'string' || !command.uploadName.startsWith(namePrefix)
        || !/^[a-z0-9]{1,16}$/i.test(command.uploadName.slice(namePrefix.length))
        || typeof command.mediaType !== 'string' || !/^image\/[a-z0-9][a-z0-9.+-]{0,63}$/i.test(command.mediaType)
        || !Number.isSafeInteger(command.byteCount) || command.byteCount < 1 || command.byteCount > MAX_BYTES) fail('BEGIN_REFUSED');
    op = {identity: JSON.parse(JSON.stringify(identity)), invocationID: command.invocationID, binding,
      name: command.uploadName, mediaType: command.mediaType, size: command.byteCount, chunks: [], received: 0, nextChunk: 0,
      committed: false, discarded: false, inputCount: 0, changeReturned: false, retirement: null,
      baseline: new Set(), urls: new Set(), start: null};
    if (binding.target.clickBindingID) binding.enrolled = true;
    registry.operations.set(identity.operationID, op);
    registry.scheduleRetirement(registry.operations, identity.operationID, op);
    return acknowledgement(op, 0);
  }
  if (!op || !sameIdentity(op.identity, identity)) {
    if (command.action === 'observe') return blank(identity, 'invalidated');
    fail('ORIGINAL_OPERATION_REQUIRED');
  }
  if (command.action === 'observe') {
    // Manual historical checks additionally bind the persisted invocation and
    // require the original live draft/member. A past START alone is insufficient.
    if (command.requireLiveOriginal === true) {
      if (!uuid(command.invocationID) || command.invocationID !== op.invocationID) return blank(identity, 'invalidated');
      const watch = op.failureWatch, original = watch?.binding.deref();
      const available = op.start
        ? (watch && sameDraft(original) && (watch.views || [watch]).some(view => matchesOriginalCard(op, view, original, false))) || liveAcceptedErrorShell(op)
        : op.reportedCardFailure ? liveOriginalFailure(op, op.binding, op.reportedCardFailure) : sameDraft(op.binding);
      if (!available) return blank(identity, 'invalidated');
    }
    return observe(op);
  }
  if (command.invocationID !== op.invocationID) fail('INVOCATION_MISMATCH');
  if (command.action === 'discard') {
    if (!op.committed) { op.chunks = []; op.discarded = true; op.binding = null; }
    return {discarded: !op.committed, inputCount: op.inputCount};
  }
  if (command.action === 'chunk') {
    if (op.committed || op.discarded || command.chunkIndex !== op.nextChunk
        || typeof command.chunkBase64 !== 'string' || command.chunkBase64.length > 4 * Math.ceil(MAX_CHUNK_BYTES / 3)
        || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(command.chunkBase64)) fail('CHUNK_REFUSED');
    const bytes = Uint8Array.from(atob(command.chunkBase64), character => character.charCodeAt(0));
    if (!bytes.length || bytes.length > MAX_CHUNK_BYTES || op.received + bytes.length > op.size) fail('CHUNK_REFUSED');
    op.lastActivity = Date.now(); op.chunks.push(bytes); op.received += bytes.length; op.nextChunk++;
    return acknowledgement(op, op.nextChunk);
  }
  if (command.action !== 'commit') fail('UNKNOWN_ACTION');
  if (op.committed || op.discarded || op.received !== op.size || command.chunkIndex !== op.nextChunk) fail('COMMIT_REFUSED');
  if ((op.mediaType || 'image/png') === 'image/png') {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10], header = [];
    for (const part of op.chunks) {
      for (const byte of part.subarray(0, 8 - header.length)) header.push(byte);
      if (header.length === 8) break;
    }
    if (header.length !== 8 || header.some((byte, index) => byte !== signature[index])) fail('INVALID_FILE');
  }
  op.lastActivity = Date.now();
  op.committed = true; // Once-only before every possible file-input side effect.
  const diag = op.entryDiagnostics = {version: 1, entryCandidates: 0, entryActivations: 0,
    openedContainers: 0, menuActivations: 0, pickerClicks: 0, pickerShows: 0,
    inputSeen: false, inputConnected: false, setterEntered: false, changeReturned: false,
    stage: 'prepare', cause: 'none', exceptionType: 'none'};
  const retire = (reason, stage, cause) => {
    op.chunks = []; op.retirement = reason; op.executionPending = false;
    diag.stage = stage; diag.cause = cause;
    const result = observe(op); op.binding = null;
    return result;
  };
  if (!validDraft(op.binding)) return retire('targetInvalidBeforeInput', 'prepare', 'targetChanged');
  if (registry.busy.has(op.binding.form)) return retire('inputExecutionBusy', 'prepare', 'executionBusy');
  let file, transfer, setter;
  try {
    // File accepts the existing chunks. No full second contiguous allocation
    // and no relabeling of JPEG bytes. Older staged product inputs were PNG.
    file = new File(op.chunks, op.name, {type: op.mediaType || 'image/png'});
    op.chunks = [];
    transfer = new DataTransfer(); transfer.items.add(file);
    setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'files').set;
    if (typeof setter !== 'function') return retire('inputPreparationFailed', 'prepare', 'unsupportedInput');
  } catch (error) {
    diag.exceptionType = exceptionName(error);
    return retire('inputPreparationFailed', 'prepare', 'exception');
  }
  // Only an application's actual click/showPicker may supply a detached
  // object. Deliver to that same object, including its own event handlers.
  const execute = (input, invoked = false) => {
    if (!validDraft(op.binding)) return retire('targetInvalidBeforeInput', 'handoff', 'targetChanged');
    diag.inputSeen = true; diag.inputConnected = input.isConnected;
    if (!usableInput(input) || (!invoked && !input.isConnected))
      return retire('attachmentInputNotCreated', 'handoff', 'inputLost');
    if (op.discoveryDeadline && Date.now() >= op.discoveryDeadline)
      return retire('attachmentInputNotCreated', 'handoff', 'timeout');
    op.oldErrorMembers = failureShellBeforeInput(op.name);
    op.previewBaseline = new WeakMap([...document.querySelectorAll(previewSelector)].map(node => [node, previewValue(node)]));
    if (native.applicationID === 'com.microsoft.edgemac') op.encodedPreview = watchEdgeEncodedPreview(file, op.name);
    registry.files.set(file, op);
    const writingForm = op.binding.form;
    registry.writingInputs ||= new WeakSet();
    if (registry.busy.has(writingForm) || registry.writingInputs.has(input)) return retire('inputExecutionBusy', 'setter', 'executionBusy');
    registry.busy.add(writingForm); registry.writingInputs.add(input);
    let receiver;
    try {
      const originalForm = input.form;
      receiver = bindOriginalReceiver(input, () => validDraft(op.binding) && usableInput(input) &&
        input.form === originalForm && (invoked || input.isConnected));
      const writeFiles = receiver.once(function(files) {
        op.inputCount = 1; op.inputSequence = tick(); op.inputTime = performance.now();
        op.blobSerialBeforeInput = registry.blobSerial ?? 0;
        registry.blobWindowUntil = op.inputTime + 10000;
        diag.stage = 'setter'; diag.setterEntered = true;
        Reflect.apply(setter, this, [files]);
      });
      const notifyInput = receiver.once(input.dispatchEvent), notifyChange = receiver.once(input.dispatchEvent);
      if (!writeFiles(transfer.files)) return retire('targetInvalidBeforeInput', 'setter', 'targetChanged');
      diag.stage = 'change';
      if (notifyInput(new Event('input', {bubbles: true, composed: true})) &&
          notifyChange(new Event('change', {bubbles: true}))) {
        op.changeReturned = true; diag.changeReturned = true; diag.stage = 'observation';
      } else {
        diag.cause = 'deliveryUncertain';
      }
    } catch (error) {
      // The native setter or a receiver can have taken effect. Never switch
      // paths after entering it, including after a dropped native receipt.
      diag.exceptionType = exceptionName(error); diag.cause = 'deliveryUncertain';
    } finally {
      receiver?.close();
      registry.busy.delete(writingForm); registry.writingInputs.delete(input);
    }
    op.executionPending = false;
    const result = observe(op);
    if (op.changeReturned && !op.start && !op.reportedCardFailure && sameDraft(op.binding)) watchHandoff(op);
    return result;
  };
  const run = () => {
    if (!validDraft(op.binding)) return retire('targetInvalidBeforeInput', 'prepare', 'targetChanged');
    const entries = entryControls(op.binding);
    diag.entryCandidates = entries.length;
    const input = directInput(op.binding, entries);
    if (input) {
      const restore = preserveSelection(op.binding);
      try { diag.stage = 'direct'; return execute(input); }
      finally { restore(); }
    }
    diag.stage = 'entry'; op.executionPending = true;
    op.discoveryDeadline = Date.now() + 3000;
    return discoverThroughEntry(op, entries, execute, retire);
  };
  // One active discovery may observe page-wide picker methods. Another
  // screenshot queues its own original command; discovering the first picker
  // is not a synchronous file write and does not retire the next click.
  let result;
  if (registry.entryTask) {
    op.executionPending = true;
    result = registry.entryTask.then(run, run);
  } else result = run();
  if (!result || typeof result.then !== 'function') return result;
  registry.entryTask = result;
  return result.catch(error => {
    diag.exceptionType = exceptionName(error);
    if (diag.setterEntered) { diag.cause = 'deliveryUncertain'; return observe(op); }
    return retire('attachmentEntryFailed', diag.stage, 'exception');
  }).finally(() => {
    op.executionPending = false;
    if (registry.entryTask === result) delete registry.entryTask;
  });
}
