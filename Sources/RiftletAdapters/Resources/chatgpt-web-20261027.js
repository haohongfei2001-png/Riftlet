/* Riftlet's document-local file handoff. Upload history never licenses new input.
 * Only commit opens an attachment entry or writes a FileList. Target capture
 * does not require the application to have mounted its picker yet.
 * No message send, editor mutation, attachment removal, request interception,
 * React inspection, prior-file hashing or automatic resubmission exists here.
 */
function riftletWebAcceptance(command, native) {
  'use strict';
  const KEY = '__riftletIndependentFileInput20261104';
  const MAX_BYTES = 128 * 1024 * 1024, MAX_CHUNK_BYTES = 256 * 1024;
  const targetKeys = ['adapterID', 'surface', 'applicationID', 'sessionID', 'windowID', 'tabID',
    'documentID', 'composerID', 'draftGeneration', 'webDraftRoute'];
  const fail = code => { throw Error(code); };
  const uuid = value => typeof value === 'string' && /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(value);
  const sameTarget = (a, b) => !!a && !!b && targetKeys.every(k => a[k] === b[k])
    && (a.historyConversationID || '').toLowerCase() === (b.historyConversationID || '').toLowerCase()
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
    if (url.protocol !== 'https:' || url.username || url.password
        || !['https://chatgpt.com', 'https://chat.openai.com'].includes(url.origin))
      fail('PAGE_ROUTE_UNSUPPORTED');
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
  const blank = (identity, state = 'unknown') => ({schemaVersion: 2,
    provenance: {source: 'integratedDevelopment', evidenceID: 'click-document-witness-20261118-v25'},
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
          if (operation && !operation.discarded && !operation.start) operation.urls.add(value);
          return value;
        };
      } catch { /* Preview attribution is optional, never an input permit. */ }
    }
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
        operation.binding?.endObservation?.();
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
  function sameDraft(binding, observing = false) {
    try {
      if (!binding || registry.root !== document.documentElement || binding.navigation !== registry.navigation
          || binding.route !== route() || !contextMatches(binding.target)) return false;
      if (binding.target.clickBindingID) {
        if (observing && binding.readOriginal) return binding.readOriginal();
        return binding.form.isConnected && binding.editor.isConnected && binding.form.contains(binding.editor)
          && !binding.editor.dispatchEvent(new Event('riftlet-witness-editor-' + binding.target.clickBindingID, {cancelable: true}))
          && !binding.form.dispatchEvent(new Event('riftlet-witness-form-' + binding.target.clickBindingID, {cancelable: true}));
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
    // An authenticated pinned click cannot write its old tab after an app,
    // window or tab switch during a queued/awaited attachment entry. This is
    // document focus, never keyboard focus of the draft editor itself.
    return sameDraft(binding) && (!binding.target.clickBindingID
      || (document.visibilityState === 'visible' && document.hasFocus() && visible(binding.editor)
        && !binding.editor.closest('[inert]') && !blocked(binding.form)));
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
  function preserveSelection(binding) {
    if (binding.editor.tagName === 'TEXTAREA') {
      const editor = binding.editor, value = editor.value, start = editor.selectionStart,
        end = editor.selectionEnd, direction = editor.selectionDirection, active = document.activeElement;
      return () => {
        if (!sameDraft(binding) || binding.editor !== editor || editor.value !== value || !Number.isInteger(start) || !Number.isInteger(end)) return;
        if (active === editor && document.hasFocus()) editor.focus?.({preventScroll: true});
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
      if (saved.active === binding.editor && document.hasFocus()) binding.editor.focus?.({preventScroll: true});
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
  function pickerHooks(intercept, restores) {
    const clicking = new WeakSet();
    const proto = HTMLInputElement.prototype;
    for (const method of ['click', 'showPicker']) {
      const own = Object.getOwnPropertyDescriptor(proto, method), original = proto[method];
      if (typeof original !== 'function') continue;
      const value = function (...args) {
        if (!intercept(this, method)) return Reflect.apply(original, this, args);
        if (method === 'showPicker') return;
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
      insideControl = true;
      try { return callback(control); }
      finally {
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
        return interrupted || !validDraft(binding) || !control.isConnected || captured.size > 0
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
          if (interrupted || !validDraft(binding) || !control.isConnected) return captured.size > 0;
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
      pickerHooks(capture, restores);
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
      if (!interrupted && validDraft(binding)) {
        for (const root of [...surfaces.opened].reverse()) if (visible(root)) {
          const target = root.contains(document.activeElement) ? document.activeElement : root;
          target.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', code: 'Escape', bubbles: true, cancelable: true}));
        }
        restoreSelection();
      }
    }
  }
  // Isolated-world click callback. The listening DOM node and closure are
  // original object identities. An identical-looking rebuilt document or
  // cloned editor has no listener. Never read or write any account data.
  if (command.action === 'pinTarget') {
    if (!uuid(command.clickWitnessID) || command.address !== route() || !globalThis.navigation?.currentEntry)
      fail('CLICK_PIN_REFUSED');
    const parts = composer(), root = document.documentElement, address = location.href;
    const navigationID = navigation.currentEntry.id;
    const editorEvent = 'riftlet-witness-editor-' + command.clickWitnessID;
    const formEvent = 'riftlet-witness-form-' + command.clickWitnessID;
    const removed = records => records.some(record => [...record.removedNodes].some(node =>
      node.contains(parts.editor) || node.contains(parts.form)));
    const handle = e => {
      if (removed(observer.takeRecords())) { dispose(); return; }
      if (e.target !== (e.type === editorEvent ? parts.editor : parts.form) || document.documentElement !== root
          || location.href !== address || navigation.currentEntry?.id !== navigationID || !parts.editor.isConnected
          || !parts.form.isConnected || !parts.form.contains(parts.editor)
          || (parts.editor.closest(composerSurface) || parts.editor.closest('form') || parts.form) !== parts.form) return;
      e.preventDefault();
    };
    const dispose = () => {
      clearTimeout(timer);
      observer.disconnect();
      navigation.removeEventListener('currententrychange', dispose);
      globalThis.removeEventListener('pagehide', dispose);
      globalThis.removeEventListener('blur', dispose);
      document.removeEventListener('visibilitychange', visibilityChanged);
      parts.editor.removeEventListener(editorEvent, handle);
      parts.form.removeEventListener(formEvent, handle);
    };
    const observer = new MutationObserver(records => {
      if (removed(records)) dispose();
    });
    const visibilityChanged = () => { if (document.visibilityState !== 'visible') dispose(); };
    const timer = setTimeout(dispose, 60000);
    observer.observe(document, {subtree: true, childList: true});
    navigation.addEventListener('currententrychange', dispose);
    globalThis.addEventListener('pagehide', dispose);
    globalThis.addEventListener('blur', dispose);
    document.addEventListener('visibilitychange', visibilityChanged);
    parts.editor.addEventListener(editorEvent, handle);
    parts.form.addEventListener(formEvent, handle);
    return 'bound';
  }

  function bindingFor(target) {
    if (!registry || !contextMatches(target)) return null;
    if (target.clickBindingID) {
      const pinned = registry.clickBindings?.get(target.clickBindingID);
      return sameTarget(pinned?.target, target) ? pinned : null;
    }
    return sameTarget(registry.current?.target, target) ? registry.current : null;
  }
  function attachmentNodes(binding) {
    // Attachment cards can also be portalled outside the editor's form. The
    // current file's unique filename/blob and pre-input baseline bind START;
    // containment in a guessed form is not an acceptance prerequisite.
    return [...document.querySelectorAll('[data-file-name],[role="button"],button,img[alt],img[src],[title]')]
      .filter(node => node !== binding.editor && !binding.editor.contains(node)
        && !(node instanceof HTMLInputElement && node.type === 'file')
        && (!node.closest('[role="menu"],[role="dialog"]')
          || node.closest('[role="dialog"]')?.contains(binding.editor)));
  }
  const previewSelector = 'img[src],progress,[role="progressbar"]';
  const previewValue = node => node.tagName === 'IMG' ? (node.getAttribute('src') || '').trim() : true;
  const previewsOf = node => node.matches(previewSelector)
    ? [node] : [...node.querySelectorAll(previewSelector)];
  // The Edge diagnostic contains aggregate counts only. The independently
  // scoped START witness below requires actual, stable node and File identities.
  // A missing/oversized snapshot never vetoes the input.
  const edgeCalibrationLimit = 512;
  const isEdgeTemporary = () => new URL(location.href).href === 'https://chatgpt.com/?temporary-chat=true';
  const edgeCalibrationExcluded = 'article,[data-message-author-role],aside,nav,header,[role="search"],[role="menu"],[role="dialog"]';
  function edgeCalibrationScan(binding) {
    // composerForm deliberately accepts responsible input without a declared
    // wrapper. Diagnostics are narrower: that fallback may be body or contain
    // transcript history, so only an explicit form/composer is a local root.
    const form = binding.form;
    if (!form || form === document.body || form === document.documentElement || form.matches('body,html')
        || !form.matches('form,' + composerSurface)) return null;
    let ancestors = 0;
    for (let node = form; node; node = node.parentElement) {
      if (++ancestors > 2048 || node.matches(edgeCalibrationExcluded)) return null;
    }
    // One traversal supplies candidates, previews and indicators. Descendant
    // queries after this pass would bypass both pruning and the visit budget.
    const pending = [{node: form, parent: -1}], entries = [], candidates = [];
    let visited = 0, editorFound = false;
    while (pending.length) {
      const {node, parent} = pending.pop();
      if (++visited > 2048) return null;
      if (node === binding.editor) { editorFound = true; continue; }
      if (node === binding.input || (node !== form && node.matches(edgeCalibrationExcluded + ',form,' + composerSurface
          + ',[contenteditable],[role="textbox"],textarea'))) continue;
      const entry = {node, parent, hasPreview: node.matches(previewSelector),
        indicator: node.matches('img,progress,[role="progressbar"],[aria-busy],[data-state],[data-status],[data-upload-status],[role="alert"]')};
      const position = entries.length;
      entries.push(entry);
      if (node !== form && node.matches('[data-file-name],[role="button"],button,img[alt],img[src],[title]')) {
        if (candidates.length === edgeCalibrationLimit) return null;
        candidates.push(entry);
      }
      const children = node.children;
      if (visited + pending.length + children.length > 2048) return null;
      for (let index = children.length - 1; index >= 0; index--) pending.push({node: children[index], parent: position});
    }
    if (!editorFound) return null;
    for (let index = entries.length - 1; index >= 0; index--) {
      const entry = entries[index];
      if (entry.hasPreview && entry.parent >= 0) entries[entry.parent].hasPreview = true;
    }
    return {entries, candidates, nodes: candidates.map(entry => entry.node)};
  }
  // This draft's child-list observer records object birth for *all* inputs,
  // including cards mounted and removed before any operation gets a poll.
  // Weak keys retain no detached DOM. Only the original declared form is read.
  function edgeHistoryFor(form, scan) {
    let history = registry.edgeProgressHistory;
    if (!history) {
      const nodes = new WeakMap(), forms = new WeakSet();
      const mark = node => {
        if (!nodes.has(node)) nodes.set(node, {first: history.generation});
        return nodes.get(node);
      };
      const excluded = edgeCalibrationExcluded + ',form,' + composerSurface + ',[contenteditable],[role="textbox"],textarea';
      const record = records => {
        if (!history.complete) return;
        let budget = 2048;
        const visit = (root, removed) => {
          const pending = [root];
          while (pending.length && budget >= 0) {
            const node = pending.pop();
            if (--budget < 0 || node.nodeType !== 1 || node.matches(excluded)) continue;
            const entry = mark(node);
            if (removed) entry.removed = true;
            if (node.children.length > budget - pending.length) { budget = -1; return; }
            for (const child of node.children) pending.push(child);
          }
        };
        for (const entry of records) {
          if (--budget < 0 || entry.addedNodes.length + entry.removedNodes.length > budget) { budget = -1; break; }
          const owner = entry.target.closest?.(excluded);
          if (owner && !forms.has(owner)) continue;
          // A null owner is possible when the whole card was detached before
          // delivery. Its earlier child records still identify the actual bar.
          for (const node of entry.addedNodes) {
            if (node.nodeType !== 1) continue;
            const first = mark(node);
            if (first.added) first.removed = true;
            first.added = true;
            visit(node, false);
          }
          for (const node of entry.removedNodes) visit(node, true);
        }
        if (budget < 0) { history.complete = false; observer.disconnect(); }
      };
      const observer = new MutationObserver(record);
      history = registry.edgeProgressHistory = {generation: 0, complete: true, nodes, flush: () => record(observer.takeRecords()),
        add: (root, entries) => {
          if (!history.complete) return;
          if (!forms.has(root)) { observer.observe(root, {subtree: true, childList: true}); forms.add(root); }
          for (const {node} of entries) mark(node);
        }};
    }
    history.flush(); history.add(form, scan.entries);
    return history;
  }
  function edgeCalibrationBaseline(binding) {
    try {
      const editor = binding.editor, form = binding.form;
      const scan = edgeCalibrationScan(binding);
      if (!scan) return null;
      const history = edgeHistoryFor(binding.form, scan);
      const text = editor.tagName === 'TEXTAREA' ? editor.value : editor.textContent;
      if (typeof text !== 'string' || text.length > 65536) return null;
      const nodes = scan.candidates.filter(({node, hasPreview}) => node.hasAttribute('data-file-name')
        || node.tagName === 'IMG' || hasPreview).map(entry => entry.node);
      const current = document.getSelection?.();
      const selection = editor.tagName === 'TEXTAREA'
        ? {textarea: true, start: editor.selectionStart, end: editor.selectionEnd, direction: editor.selectionDirection}
        : current?.rangeCount && editor.contains(current.anchorNode) && editor.contains(current.focusNode)
          ? {anchor: current.anchorNode, focus: current.focusNode, anchorOffset: current.anchorOffset,
            focusOffset: current.focusOffset, rangeCount: current.rangeCount} : null;
      const originals = nodes.map(node => ({node, parent: node.parentElement, src: node.getAttribute('src'),
        name: node.getAttribute('data-file-name'), alt: node.getAttribute('alt')}));
      const baseline = {editor, form, text, selection, nodes, originals, history, emptySelection: current?.rangeCount === 0,
        root: document.documentElement, target: {...binding.target}, route: binding.route, navigation: binding.navigation};
      if (binding.target.clickBindingID && isEdgeTemporary()) baseline.witness = watchEdgeProgress(baseline);
      return baseline;
    } catch { return null; }
  }
  function edgeCalibrationBeforeInput(op, file) {
    if (!op.edgeCalibration) return;
    try {
      const saved = op.edgeCalibration;
      saved.baseline?.history.flush();
      const scan = edgeCalibrationScan(op.binding);
      if (!scan) { registry.edgeHistoryIncomplete = true; return; }
      const history = edgeHistoryFor(op.binding.form, scan);
      saved.beforeInput = new WeakSet(scan.entries.map(entry => entry.node));
      saved.generation = ++history.generation;
      if (saved.trackProgress && saved.baseline?.witness?.active && history.complete && !registry.edgeHistoryIncomplete) {
        saved.progress = saved.baseline.witness;
        saved.progress.bind(op, file);
      }
    } catch { /* Diagnostics cannot change the once-only input path. */ }
  }
  function edgeProgressValue(node, raw = node.getAttribute(node.tagName === 'PROGRESS' ? 'value' : 'aria-valuenow')) {
    const nativeBar = node.tagName === 'PROGRESS';
    const numeric = raw => raw !== null && raw.length <= 32 && /^(?:\d+(?:\.\d*)?|\.\d+)$/.test(raw.trim()) ? Number(raw) : NaN;
    const value = numeric(raw);
    const low = nativeBar ? 0 : numeric(node.getAttribute('aria-valuemin') ?? '0');
    const high = numeric(node.getAttribute(nativeBar ? 'max' : 'aria-valuemax') ?? (nativeBar ? '1' : '100'));
    if (![low, high, value].every(Number.isFinite) || high <= low || value < low || value > high) return null;
    return {percent: 100 * (value - low) / (high - low), low, high};
  }
  const edgeLabelAttributes = ['alt', 'title', 'aria-label', 'aria-description', 'aria-valuetext'];
  const edgeLabelRelations = ['aria-labelledby', 'aria-describedby', 'aria-owns', 'for', 'id'];
  // Inspect visible ownership claims only inside the already proven new single-file
  // scope. An external label or owner can veto a sample, never supply its name.
  function edgeProgressLabels(filename, members, originals) {
    if (members.length > 128) return null;
    const own = new RegExp(filename.source, 'g');
    const fileSuffix = /\S\.(?:png|jpe?g|gif|webp|avif|hei[cf]|bmp|svg|tiff?|ico|pdf|docx?|xlsx?|pptx?|csv|txt|md|json|zip)(?![a-z0-9_-])/iu;
    const prior = [...new Set(originals.map(item => item.name).filter(Boolean))];
    if (prior.length > 32 || prior.some(name => name.length > 256)) return null;
    const exactPrior = prior.length ? new RegExp('(?:^|[^a-zA-Z0-9_.-])(?:'
      + prior.map(name => name.replace(/[\\^$.*+?()[\]{}|]/g, '\\$&')).join('|') + ')(?=$|[^a-zA-Z0-9_.-])') : null;
    const conflicts = text => typeof text !== 'string' || text.length > 1024 || !!exactPrior?.test(text)
      || fileSuffix.test(text.replace(own, '$1'));
    let budget = 16384, referenceCount = 0;
    const accepts = text => (budget -= text.length) >= 0 && !conflicts(text);
    const ids = new Map(), refs = new Map(), nodes = new Set(members.map(entry => entry.node));
    for (const {node} of members) {
      if (node.children.length > 128 || [...node.children].some(child => !nodes.has(child))) return null;
      if (node.id) {
        if (ids.size === 32 || !/^[a-zA-Z0-9_:.-]{1,128}$/.test(node.id) || ids.has(node.id)
            || document.getElementById(node.id) !== node) return null;
        ids.set(node.id, node);
      }
      if (node.hasAttribute('aria-owns')) return null;
      for (const attr of edgeLabelAttributes) {
        const value = node.getAttribute(attr);
        if (value !== null && !accepts(value)) return null;
      }
    }
    for (const [id, node] of ids) {
      // Exact reverse associations only. No document text, list of controls, or
      // content of an external accessible label is read.
      if (document.querySelector('[aria-owns~="' + id + '"]')) return null;
      if (document.querySelector('label[for="' + id + '"]')) {
        const labels = node.labels;
        if (!labels?.length || labels.length > 8 || [...labels].some(label => !nodes.has(label))) return null;
      }
    }
    for (const {node} of members) {
      const destinations = [];
      for (const attr of ['aria-labelledby', 'aria-describedby', 'for']) {
        const value = node.getAttribute(attr);
        if (value === null) continue;
        if (value.length > 512 || !value.trim()) return null;
        for (const id of value.trim().split(/\s+/)) {
          if (++referenceCount > 32 || !ids.has(id)) return null;
          // A native label's 'for' identifies a control. It is not a recursive
          // accessible-name reference from the label back to its control.
          if (attr !== 'for') destinations.push(ids.get(id));
        }
      }
      if (destinations.length) refs.set(node, destinations);
    }
    const done = new Set(), visiting = new Set();
    const resolved = node => {
      if (done.has(node)) return true;
      if (visiting.has(node)) return false;
      visiting.add(node);
      if (!(refs.get(node) || []).every(resolved)) return false;
      visiting.delete(node); done.add(node); return true;
    };
    if (![...refs.keys()].every(resolved)) return null;
    const referenced = new Set([...refs.values()].flat());
    const roots = new Set([members[0].node, ...referenced, ...members.map(entry => entry.node).filter(node =>
      node.matches('button,label,progress,[role="button"],[role="group"],[role="progressbar"]'))]);
    // Read each complete local name in DOM order. Inline elements and adjacent
    // Text nodes are one label; independent controls have separate names.
    // An explicitly referenced element contributes its entire vetted subtree.
    let steps = 2048;
    const simpleText = new Set(), compoundText = new Set();
    for (const root of roots) {
      let value = '', fragments = [];
      const flush = () => {
        if (!accepts(value)) return false;
        for (const node of fragments) (fragments.length === 1 ? simpleText : compoundText).add(node);
        value = ''; fragments = []; return true;
      };
      const append = (node, data) => {
        if (typeof data !== 'string' || value.length + data.length > 1024) return false;
        fragments.push(node); value += data; return true;
      };
      const pending = [root];
      while (pending.length) {
        const node = pending.pop();
        if (--steps < 0) return null;
        if (node.nodeType === 3) {
          if (node.length > 1024 || !append(node, node.data)) return null;
          continue;
        }
        if (node.nodeType === 8) continue;
        if (!nodes.has(node)) return null;
        if (node !== root && roots.has(node) && !referenced.has(root)) {
          if (!flush()) return null;
          continue;
        }
        const children = node.childNodes || node.children;
        if (children.length > 128 || pending.length + children.length > steps) return null;
        if (!node.childNodes && !children.length && !append(node, node.textContent)) return null;
        for (let i = children.length - 1; i >= 0; i--) pending.push(children[i]);
      }
      if (!flush()) return null;
    }
    for (const node of compoundText) simpleText.delete(node);
    return {conflicts, simpleText};
  }
  // Bound to this original input only. A removed and reinserted node is not a
  // continuous witness, even when two polls see the same object and parent.
  function watchEdgeProgress(baseline) {
    const {form, editor, originals} = baseline, moved = new WeakSet();
    const originalNodes = new Set(originals.map(item => item.node));
    const identityAttributes = ['data-file-name', 'alt', 'src', 'title', 'aria-label'];
    const statusAttributes = ['data-state', 'data-status', 'data-upload-status'];
    let held = null, op = null, input = null, originalFile = null, expectedChange = null, changes = 0, expires;
    let deadline = performance.now() + 60000;
    const close = (reason = 'historyUnavailable') => {
      witness.decision = reason;
      observer.disconnect(); clearTimeout(expires); held = null; expectedChange = null;
      input?.removeEventListener('change', onChange, true);
      document.removeEventListener('change', onDocumentChange, true);
      document.removeEventListener('selectionchange', onSelection);
      if (op) op.edgeCalibration.progress = null;
      witness.active = false; op = null; input = null; originalFile = null;
    };
    const holdsOriginalFile = () => input.files?.length === 1 && input.files[0] === originalFile
      && registry.files.get(originalFile) === op;
    const checkExtraChange = field => {
      const files = field.files, count = files?.length;
      if (!Number.isSafeInteger(count) || count < 0 || count > 32) return close('inputCount');
      for (let index = 0; index < count; index++) {
        if (!files[index] || registry.files.get(files[index]) === op) return close('inputCount');
      }
    };
    const onDocumentChange = event => {
      // Capture before a target handler can clear a mixed selection. A rebuilt
      // field in this original draft can also receive the same File again.
      const field = event.target;
      if (event !== expectedChange && field instanceof HTMLInputElement && field.type === 'file'
          && (field === input || field.form === form || form.contains(field))) checkExtraChange(field);
    };
    const onChange = event => {
      if (event === expectedChange) {
        if (!holdsOriginalFile() || ++changes !== 1) close('inputCount');
      } else checkExtraChange(input);
    };
    const onSelection = () => {
      if (!edgeSelectionUnchanged(baseline)) close('selectionChanged');
    };
    const changed = records => {
      if (records.length > 2048 || performance.now() >= deadline) return close();
      let removedCount = 0;
      for (const record of records) {
        if (editor.contains(record.target)) return close('draftChanged');
        if (record.type === 'attributes') {
          const node = record.target, key = record.attributeName;
          if (originalNodes.has(node) && identityAttributes.includes(key)) return close('retainedBaseline');
          if (!held || !held.scope.contains(node)) continue;
          if ((key === 'data-file-name' && [record.oldValue, node.getAttribute(key)].some(value => value != null && value !== op.name))
              || edgeLabelRelations.includes(key) || (edgeLabelAttributes.includes(key) &&
              (held.conflicts(record.oldValue || '') || held.conflicts(node.getAttribute(key) || '')))) return close('conflictingFileLabel');
          if (node === held.bar && ['value', 'aria-valuenow'].includes(key)) {
            // Old values also catch a finish/reset/reuse between two polls.
            if (record.oldValue !== undefined) {
              const previous = edgeProgressValue(node, record.oldValue);
              if (!previous || previous.percent < held.highest || previous.percent >= 100) return close('progressUnavailable');
              held.highest = previous.percent;
            }
            continue;
          }
          if ((held.labels.includes(node) && identityAttributes.includes(key))
              || (node === held.image && key === 'src') || statusAttributes.includes(key)
              || (node === held.bar && ['role', 'aria-valuemin', 'aria-valuemax', 'max'].includes(key))) return close('nodeReused');
        } else if (held && held.scope.contains(record.target) && record.type === 'characterData') {
          // An isolated old/current fragment cannot establish the former name
          // of a multi-part label. Only a complete, unchanged text boundary
          // admits direct character-data changes between the two samples.
          if (!held.simpleText.has(record.target) || held.conflicts(record.oldValue)
              || held.conflicts(record.target.data)) return close('conflictingFileLabel');
        } else if (record.type === 'childList') {
          if (held && held.scope.contains(record.target)) {
            const count = record.addedNodes.length + record.removedNodes.length;
            if (!count || count > 128) return close('conflictingFileLabel');
            for (const list of [record.addedNodes, record.removedNodes]) for (const node of list) {
              // A child-list record has no former text value. Inserting or
              // replacing part of a name cannot attest its intermediate owner.
              if (node.nodeType === 3) return close('conflictingFileLabel');
              if (node.nodeType === 1) return close('nodeReused');
            }
          }
          for (const removed of record.removedNodes) {
            if (++removedCount > 2048) return close();
            moved.add(removed);
            if (originals.some(item => removed.contains(item.node))
                || (held && [held.scope, held.card, held.image, held.bar, held.remove].some(node => node && removed.contains(node)))) return close('nodeReused');
          }
        }
      }
    };
    const observer = new MutationObserver(changed);
    observer.observe(form, {childList: true, characterData: true, characterDataOldValue: true, attributes: true, attributeOldValue: true, subtree: true,
      attributeFilter: [...identityAttributes, 'aria-description', 'aria-valuetext', ...edgeLabelRelations, ...statusAttributes, 'role', 'aria-valuemin', 'aria-valuemax', 'max', 'value', 'aria-valuenow']});
    const witness = {active: true, decision: 'awaitingInput', close, moved, flush: () => changed(observer.takeRecords()),
      bind: (original, file) => {
        witness.flush();
        if (!witness.active) { original.edgeCalibration.progress = null; return; }
        op = original; originalFile = file; input = op.binding.input;
        document.addEventListener('change', onDocumentChange, true); input.addEventListener('change', onChange, true);
        deadline = performance.now() + 30000;
        clearTimeout(expires); expires = setTimeout(close, 30000);
      },
      expect: event => {
        if (event && !holdsOriginalFile()) { close('inputCount'); return; }
        expectedChange = event;
        if (!event) originalFile = null;
      }, get changes() { return changes; },
      get held() { return held; }, hold: value => { held = value; }};
    document.addEventListener('selectionchange', onSelection);
    expires = setTimeout(close, 60000);
    return witness;
  }
  function edgeSelectionUnchanged(baseline) {
    const {editor, selection} = baseline;
    if (selection?.textarea) return Number.isInteger(selection.start) && Number.isInteger(selection.end)
      && editor.selectionStart === selection.start && editor.selectionEnd === selection.end
      && editor.selectionDirection === selection.direction;
    const current = document.getSelection?.();
    if (!selection) return baseline.emptySelection && current?.rangeCount === 0;
    return current?.rangeCount === 1 && selection.rangeCount === 1 && current.anchorNode === selection.anchor
      && current.anchorOffset === selection.anchorOffset && current.focusNode === selection.focus
      && current.focusOffset === selection.focusOffset;
  }
  function observeEdgeProgress(op, result, scan, filename, named, blob, matched) {
    const saved = op.edgeCalibration, proof = saved.progress;
    if (!proof || op.start || !op.changeReturned || op.inputCount !== 1) return;
    proof.flush();
    if (saved.progress !== proof) return;
    const {baseline, beforeInput} = saved;
    baseline.history.flush();
    if (!baseline.history.complete || registry.edgeHistoryIncomplete) return proof.close('historyUnavailable');
    if (proof.changes !== 1) return proof.close('inputCount');
    if (!result.originalDraftCurrent || !result.originalTextUnchanged) return proof.close('draftChanged');
    if (!edgeSelectionUnchanged(baseline)) return proof.close('selectionChanged');
    if (result.retainedBaselineAttachmentNodes !== result.baselineAttachmentNodes
        || baseline.originals.some(({node, parent, name, src, alt}) => node.parentElement !== parent
          || node.getAttribute('data-file-name') !== name || node.getAttribute('src') !== src || node.getAttribute('alt') !== alt)
        || matched.some(node => beforeInput.has(node))) return proof.close('retainedBaseline');
    const labels = matched.filter(named), images = matched.filter(blob);
    // The DOM may mount an image before the numeric progress control. Once we
    // have sampled one, we may never replace it, cross a gap or start over.
    const held = proof.held;
    if (result.errorAttributeNodes || result.readyAttributeNodes) return proof.close('terminal');
    if (images.length > 1) return proof.close('ownershipTopology');
    if (!images.length || !labels.length) {
      proof.decision = !images.length ? 'fileBlobMissing' : 'ownershipTopology';
      if (held) proof.close(proof.decision); return;
    }
    const image = images[0];
    // An existing tray or a newly mounted group cannot lend a sibling's bar.
    // The exact filename must identify the card that owns every matching facet.
    let card = labels.find(node => node !== image && node.contains(image) && labels.every(label => node.contains(label)));
    let scope = card, remove = null;
    if (!card) {
      // ChatGPT can expose the image popup and its specifically named Remove
      // button as siblings in one new attachment. The progress bar still has
      // to be inside the same named popup as the original File-backed image.
      const popup = labels.find(node => node.hasAttribute('aria-haspopup') && node.contains(image));
      const parent = popup?.parentElement;
      if (parent && !beforeInput.has(parent) && parent.children.length === 2) {
        const sibling = [...parent.children].find(node => node !== popup);
        const removesFile = sibling?.matches('button,[role="button"]') && ['aria-label', 'title'].some(key => {
          const label = sibling.getAttribute(key) || '';
          return /(?:\bremove\b|移除|删除)/i.test(label) && filename.test(label);
        });
        if (removesFile && labels.every(node => popup.contains(node) || sibling.contains(node))) {
          card = popup; scope = parent; remove = sibling;
        }
      }
    }
    if (!card) {
      proof.decision = 'ownershipTopology';
      if (held || labels.some(node => !node.contains(image) && !image.contains(node))) proof.close(proof.decision); return;
    }
    const members = scan.entries.filter(({node}) => scope.contains(node));
    const controls = members.filter(({node}) => node.matches('progress,[role="progressbar"]'));
    const failed = ['error', 'failed', 'errored', 'aborted', 'canceled', 'cancelled', 'rejected'];
    const terminal = [...failed, 'ready', 'complete', 'completed', 'done'];
    const hasState = (node, values) => ['data-state', 'data-status', 'data-upload-status']
      .some(key => values.includes((node.getAttribute(key) || '').trim().toLowerCase()));
    if (controls.length > 1 || members.filter(({node}) => node.tagName === 'IMG').length !== 1
        || members.some(({node}) => beforeInput.has(node) || proof.moved.has(node) || hasState(node, terminal)
          || (node.hasAttribute('data-file-name') && node.getAttribute('data-file-name') !== op.name))
        || scan.entries.some(({node}) => hasState(node, failed)
          || (node.getAttribute('role') === 'alert' && visible(node) && node.textContent.trim().length > 0)))
      return proof.close('ownershipTopology');
    if (!controls.length) { proof.decision = 'progressUnavailable'; if (held) proof.close(proof.decision); return; }
    const names = edgeProgressLabels(filename, members, baseline.originals);
    if (!names) return proof.close('conflictingFileLabel');
    const bar = controls[0].node, url = image.getAttribute('src');
    // A detached node might be absent from this input's baseline and still
    // belong to an earlier file. A later independent input may see our own
    // pending nodes in its baseline without taking their ownership.
    for (const node of [card, image, bar]) {
      const history = baseline.history.nodes.get(node);
      if (!history || history.removed || history.first < saved.generation || (history.owner && history.owner !== saved.generation)) return proof.close('nodeReused');
    }
    for (const node of [card, image, bar]) baseline.history.nodes.get(node).owner = saved.generation;
    for (let node = card; node !== baseline.form; node = node.parentElement)
      if (!node || proof.moved.has(node)) return proof.close('nodeReused');
    if (!card.contains(bar) || (held?.remove && held.remove !== remove)
        || op.previewBaseline.has(image) || op.previewBaseline.has(bar) || !visible(image) || !visible(bar)
        || (held && (held.card !== card || held.image !== image || held.bar !== bar || held.url !== url))) return proof.close('nodeReused');
    const reading = edgeProgressValue(bar), now = performance.now();
    if (!reading) { proof.decision = 'progressUnavailable'; if (held) proof.close(proof.decision); return; }
    if (held && (held.low !== reading.low || held.high !== reading.high)) return proof.close('progressUnavailable');
    const value = reading.percent;
    if (value >= 100 || now < op.inputTime || (held && (value < held.highest || now < held.at))) return proof.close('progressUnavailable');
    if (value <= 0 || now === op.inputTime) { proof.decision = 'progressUnavailable'; return; }
    if (!held) { proof.decision = 'firstProgress'; proof.hold({card, scope, remove, image, bar, labels, ...names, url, value, highest: value, low: reading.low, high: reading.high, at: now}); return; }
    if (value === held.value || now === held.at) return;
    const current = composer();
    if (current.form !== baseline.form || current.editor !== baseline.editor) return proof.close('draftChanged');
    op.attachmentID = registry.documentID + ':' + nodeID(card);
    op.start = {version: 1, signal: 'correlatedProgress', evidenceID: crypto.randomUUID(), inputCount: 1,
      inputSequence: op.inputSequence, startSequence: tick(), previousProgress: held.value, currentProgress: value,
      inputObservedAtMS: op.inputTime, startObservedAtMS: now};
    proof.close('started'); op.binding.endObservation?.(); op.baseline.clear(); op.previewBaseline = null; op.urls.clear();
  }
  function edgeCalibrationSample(op, originalDraftCurrent) {
    const saved = op.edgeCalibration;
    if (!saved || saved.invocationID !== op.invocationID) return null;
    const baseline = saved.baseline;
    const result = {version: 1, sampleNumber: saved.samples = Math.min(65535, saved.samples + 1),
      baselineAvailable: !!baseline, beforeInputBaselineAvailable: !!saved.beforeInput,
      originalDraftCurrent: false, clickBound: !!op.identity.target.clickBindingID,
      originalTextUnchanged: false, selectionComparable: false, originalSelectionUnchanged: false,
      baselineAttachmentNodes: baseline?.nodes.length || 0, retainedBaselineAttachmentNodes: 0,
      matchedNodes: 0, matchedOriginalFormNodes: 0, newMatchedNodes: 0, filenameMatchedNodes: 0,
      blobMatchedNodes: 0, progressNodes: 0, progressValueKnown: false,
      progressPercentMinimum: 0, progressPercentMaximum: 0, busyAttributeNodes: 0,
      readyAttributeNodes: 0, errorAttributeNodes: 0, loadedImageNodes: 0,
      changedMatchedPreviews: 0, scanLimited: false, samplingFailed: false};
    try {
      // Do not let legacy sameDraft's wrapper recovery lend a replacement
      // editor to this diagnostic, or sample another operation's file.
      if (!baseline || !originalDraftCurrent || registry.root !== baseline.root || document.documentElement !== baseline.root
          || !sameTarget(baseline.target, op.identity.target) || !sameTarget(baseline.target, op.binding.target)
          || !contextMatches(baseline.target) || baseline.route !== route() || baseline.navigation !== registry.navigation
          || op.binding.editor !== baseline.editor || op.binding.form !== baseline.form) {
        saved.progress?.close('draftChanged'); return result;
      }
      const scan = edgeCalibrationScan(op.binding);
      if (!scan) { saved.progress?.close(); result.scanLimited = true; return result; }
      result.originalDraftCurrent = true;
      const {editor, form, selection} = baseline;
      result.originalTextUnchanged = (editor.tagName === 'TEXTAREA' ? editor.value : editor.textContent) === baseline.text;
      const currentNodes = new Set(scan.nodes);
      result.retainedBaselineAttachmentNodes = baseline.nodes.filter(node => node.isConnected && currentNodes.has(node)).length;
      if (selection?.textarea) {
        result.selectionComparable = Number.isInteger(selection.start) && Number.isInteger(selection.end);
        result.originalSelectionUnchanged = result.selectionComparable && editor.selectionStart === selection.start
          && editor.selectionEnd === selection.end && editor.selectionDirection === selection.direction;
      } else if (selection) {
        const current = document.getSelection?.();
        result.selectionComparable = true;
        result.originalSelectionUnchanged = !!current && current.rangeCount === selection.rangeCount
          && current.anchorNode === selection.anchor && current.focusNode === selection.focus
          && current.anchorOffset === selection.anchorOffset && current.focusOffset === selection.focusOffset;
      }
      if (!op.inputCount || !saved.beforeInput) return result;
      const nodes = scan.nodes;
      const filename = new RegExp('(^|[^a-zA-Z0-9_.-])' + op.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(?=$|[^a-zA-Z0-9_.-])');
      const named = node => ['data-file-name', 'aria-label', 'title', 'alt'].some(key => filename.test(node.getAttribute(key) || ''));
      const blob = node => node.tagName === 'IMG' && op.urls.has(node.getAttribute('src'));
      const matched = nodes.filter(node => node.isConnected && (named(node) || blob(node)));
      const owned = matched.filter(node => form.contains(node));
      result.matchedNodes = matched.length; result.matchedOriginalFormNodes = owned.length;
      result.newMatchedNodes = matched.filter(node => !saved.beforeInput.has(node)).length;
      result.filenameMatchedNodes = matched.filter(named).length; result.blobMatchedNodes = matched.filter(blob).length;
      // A filename alone is not an upload signal. Inspect only its candidate
      // nodes in the original form; no guessed portal lends ownership here.
      const ownedNodes = new Set(owned), indicators = [];
      for (const entry of scan.entries) {
        entry.matchedAncestor = ownedNodes.has(entry.node)
          || (entry.parent >= 0 && scan.entries[entry.parent].matchedAncestor);
        if (!entry.matchedAncestor || (!entry.indicator && !ownedNodes.has(entry.node))) continue;
        if (indicators.length === edgeCalibrationLimit) { saved.progress?.close(); result.scanLimited = true; return result; }
        indicators.push(entry.node);
      }
      const progress = [];
      for (const node of indicators) {
        if (node.matches('progress,[role="progressbar"]')) {
          result.progressNodes++;
          const reading = edgeProgressValue(node);
          if (reading) progress.push(Math.round(reading.percent));
        }
        const states = ['data-state', 'data-status', 'data-upload-status'].map(key => node.getAttribute(key));
        if (node.getAttribute('aria-busy') === 'true' || states.some(value => ['loading', 'uploading', 'pending'].includes(value))) result.busyAttributeNodes++;
        if (states.some(value => ['ready', 'complete', 'completed', 'done'].includes(value))) result.readyAttributeNodes++;
        if (node.getAttribute('role') === 'alert' || states.some(value => ['error', 'failed'].includes(value))) result.errorAttributeNodes++;
        if (node.tagName === 'IMG' && node.complete === true && node.naturalWidth > 0) result.loadedImageNodes++;
        if (node.matches(previewSelector) && previewValue(node) && op.previewBaseline?.get(node) !== previewValue(node)) result.changedMatchedPreviews++;
      }
      if (progress.length) {
        result.progressValueKnown = true;
        result.progressPercentMinimum = Math.min(...progress); result.progressPercentMaximum = Math.max(...progress);
      }
      observeEdgeProgress(op, result, scan, filename, named, blob, matched);
    } catch { saved.progress?.close(); result.samplingFailed = true; }
    finally {
      if (saved.trackProgress) result.progressDecision = op.start ? 'started'
        : !baseline?.history?.complete || registry.edgeHistoryIncomplete ? 'historyUnavailable'
        : baseline.witness?.decision || 'historyUnavailable';
    }
    return result;
  }
  // One document observer covers only the actual draft pairs with pending
  // observations. Removing a transcript subtree never enumerates its contents.
  function observationMonitor() {
    if (registry.observationMonitor) return registry.observationMonitor;
    const drafts = new Set();
    const remove = draft => {
      if (!drafts.delete(draft) || drafts.size) return;
      observer.disconnect();
      navigation.removeEventListener('currententrychange', navigated);
      globalThis.removeEventListener('pagehide', navigated);
      registry.observationMonitor = null;
    };
    const navigated = () => { for (const draft of drafts) remove(draft); };
    const reconcile = records => {
      for (const record of records) for (const removed of record.removedNodes) {
        for (const draft of drafts) if (removed.contains(draft.editor) || removed.contains(draft.form)) remove(draft);
        if (!drafts.size) return;
      }
    };
    const observer = new MutationObserver(reconcile);
    observer.observe(document, {subtree: true, childList: true});
    navigation.addEventListener('currententrychange', navigated);
    globalThis.addEventListener('pagehide', navigated);
    registry.observationMonitor = {drafts, remove, flush: () => reconcile(observer.takeRecords())};
    return registry.observationMonitor;
  }
  function retainObservation(current) {
    // Flush outstanding changes before adding the just-verified binding.
    registry.observationMonitor?.flush();
    const monitor = observationMonitor(), root = document.documentElement, address = location.href;
    const navigationID = navigation.currentEntry.id;
    let draft;
    for (const item of monitor.drafts) if (item.form === current.form && item.editor === current.editor) {
      draft = item; break;
    }
    if (!draft) {
      draft = {form: current.form, editor: current.editor, users: 0};
      monitor.drafts.add(draft);
    }
    draft.users++;
    current.endObservation = () => {
      if (!current.endObservation) return;
      current.endObservation = null;
      current.readOriginal = () => false;
      if (--draft.users === 0) monitor.remove(draft);
    };
    current.readOriginal = () => {
      monitor.flush();
      const valid = monitor.drafts.has(draft) && document.documentElement === root
        && location.href === address && navigation.currentEntry?.id === navigationID
        && draft.form.isConnected && draft.editor.isConnected && draft.form.contains(draft.editor)
        && (draft.editor.closest(composerSurface) || draft.editor.closest('form') || draft.form) === draft.form;
      if (!valid) { monitor.remove(draft); current.endObservation?.(); }
      return valid;
    };
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
  function captureFailureWatch(op, accepted, matches) {
    if (typeof WeakRef !== 'function') return;
    const filename = fileNamePattern(op.name), views = [], cards = new Set();
    // Secondary views are optional. A busy document cannot enlarge the
    // post-START scan beyond 16 candidates or the retained set beyond four.
    for (const node of [accepted, ...matches.slice(0, 16)]) {
      const card = node.closest(cardSelector);
      if (!card || cards.has(card)) continue;
      const local = inOriginalCardContainer(card, op.binding);
      if (!local && (!card.parentElement || !independentCardPortal(card, op.binding))) continue;

      const declared = card.getAttribute('data-file-name');
      if (declared !== null && declared !== op.name) continue;
      const namedCard = declared === op.name;
      const label = ['aria-label', 'title', 'alt'].find(key => filename.test(node.getAttribute(key) || ''));
      // Never retain inline image data, signed remote URLs or page text.
      const preview = previewsOf(node).find(image => {
        if (image.tagName !== 'IMG' || image.closest(cardSelector) !== card) return false;
        const src = image.getAttribute('src');
        return src && src.length <= 256 && src.startsWith('blob:') && op.previewBaseline?.get(image) !== src;
      });
      const src = preview?.getAttribute('src');
      // Only the actual START node may rely on its own filename and preview.
      // A separate view must show an object URL minted from this exact File.
      const sameFile = !!src && op.urls.has(src);
      if (node !== accepted && !sameFile) continue;
      if (!namedCard && !sameFile && (!label || !preview)) continue;
      if (!consistentCardLabels(card, op.name)) continue;
      cards.add(card);
      views.push({card: new WeakRef(card), parent: new WeakRef(card.parentElement), namedCard, label, witness: new WeakRef(node),
        preview: preview ? new WeakRef(preview) : null, src, sameFile,
        portalParent: local ? null : new WeakRef(card.parentElement)});
      if (views.length === 4) break;
    }
    if (views.length) op.failureWatch = {binding: new WeakRef(op.binding), views};
  }

  function reportsOriginalError(op, view, binding) {
    const card = view.card.deref();
    if (!card?.isConnected || (view.portalParent
        ? view.portalParent.deref() !== card.parentElement || !independentCardPortal(card, binding)
        : !inOriginalCardContainer(card, binding))) return false;
    const declared = card.getAttribute('data-file-name');
    // v18 watches in an already-open document used only data-file-name and
    // the card itself. Preserve that read path without expanding its evidence.
    if (view.namedCard === undefined) {
      return declared === op.name && ['error', 'failed'].includes(card.getAttribute('data-state'))
        && consistentCardLabels(card, op.name);
    }
    if (view.parent.deref() !== card.parentElement) return false;
    if (view.namedCard ? declared !== op.name : declared !== null && declared !== op.name) return false;
    if (view.sameFile || !view.namedCard) {
      const preview = view.preview?.deref();
      if (!preview || preview.closest(cardSelector) !== card || preview.getAttribute('src') !== view.src) return false;
      if (view.label) {
        const witness = view.witness.deref();
        if (!witness || witness.closest(cardSelector) !== card
            || !fileNamePattern(op.name).test(witness.getAttribute(view.label) || '')) return false;
      }
    }
    const failed = node => ['failed', 'error'].includes(node.getAttribute('data-state'));
    if (failed(card)) return consistentCardLabels(card, op.name);
    // Only the initially bound, still-identical preview can contribute a
    // descendant's error. An inserted status, toast, or sibling cannot.
    const preview = view.preview?.deref();
    return !!preview && preview.closest(cardSelector) === card && preview.getAttribute('src') === view.src
      && (view.sameFile || fileNamePattern(op.name).test(preview.getAttribute('alt') || ''))
      && failed(preview) && consistentCardLabels(card, op.name);
  }
  function sample(op) {
    // Chrome's preview acceptance cannot supply Edge's correlated progress.
    if (native.applicationID === 'com.microsoft.edgemac') return;
    // The app may disable or remove its picker after accepting this file.
    // Observing that handoff needs the original draft, not another input slot.
    if (op.start || !op.changeReturned || !sameDraft(op.binding, true)) return;
    const newPreview = node => previewsOf(node).some(preview => {
      const value = previewValue(preview);
      if (!value) return false;
      // Original resident operations have a node-identity baseline. New
      // handoffs also recognize a framework filling an existing preview slot.
      return op.previewBaseline ? op.previewBaseline.get(preview) !== value : !op.baseline.has(node);
    });
    const hasError = node => {
      const card = node.closest('[data-file-name],[role="button"],button') || node;
      const errors = '[role="alert"],[data-state="error"],[data-state="failed"]';
      return !!node.closest(errors) || !!card.querySelector(errors);
    };
    const filename = fileNamePattern(op.name);
    const named = node => ['data-file-name', 'aria-label', 'title', 'alt'].some(key => filename.test(node.getAttribute(key) || ''))
      || ((node.hasAttribute('data-file-name') || node.getAttribute('role') === 'button' || node.tagName === 'BUTTON')
        && filename.test(node.textContent || ''));
    const identifiesFile = node => named(node) || (node.tagName === 'IMG' && op.urls.has(node.getAttribute('src')));
    const identified = attachmentNodes(op.binding).filter(node => node.isConnected && identifiesFile(node));
    if (identified.some(hasError)) return;
    const matches = identified.filter(newPreview);
    if (!matches.length) return;
    // A compact tray and expanded view can both present this same exact
    // File. START needs one positive handoff; duplicate views are not inputs.
    const accepted = matches.find(node => op.binding.form.contains(node)) || matches[0];
    op.attachmentID = registry.documentID + ':' + nodeID(accepted);
    op.start = {version: 1, signal: 'attachmentAccepted', evidenceID: crypto.randomUUID(), inputCount: 1,
      inputSequence: op.inputSequence, startSequence: tick(), previousProgress: 0, currentProgress: 0,
      inputObservedAtMS: op.inputTime, startObservedAtMS: Math.max(op.inputTime, performance.now())};
    // A retained, same-name card may subsequently expose a local failure. Weak
    // references cannot keep a detached composer, input, or attachment alive.
    captureFailureWatch(op, accepted, matches);
    op.binding.endObservation?.();
    op.binding = null; op.baseline.clear(); op.previewBaseline = null; op.urls.clear();
  }
  function observe(op) {
    sample(op);
    const result = blank(op.identity), item = result.observation;
    if (op.entryDiagnostics) result.entryDiagnostics = {...op.entryDiagnostics};
    item.belongsToOriginalDraft = sameDraft(op.binding, true);
    if (native.applicationID === 'com.microsoft.edgemac') {
      const calibration = edgeCalibrationSample(op, item.belongsToOriginalDraft);
      if (calibration && result.entryDiagnostics) result.entryDiagnostics.edgeCalibration = calibration;
    }
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
      item.uploadStart = {...op.start}; item.isUploading = op.start.signal === 'correlatedProgress';
      const watch = op.failureWatch, original = watch?.binding.deref();
      if (watch && sameDraft(original) && (watch.views || [watch]).some(view => reportsOriginalError(op, view, original))) {
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
      if (native.applicationID === 'com.microsoft.edgemac' && isEdgeTemporary())
        target.webDraftRoute = 'chatGPTTemporaryHome';
      if (native.applicationID === 'com.google.Chrome') {
        const address = new URL(route());
        const id = address.origin === 'https://chatgpt.com' && /^\/c\/([^/]+)\/?$/.exec(address.pathname)?.[1];
        if (uuid(id)) target.historyConversationID = id.toUpperCase();
      }
      const pinned = {...parts, target, route: route(), navigation: registry.navigation};
      if (!sameDraft(pinned)) fail('CLICK_PIN_REFUSED');
      if (native.applicationID === 'com.microsoft.edgemac') pinned.edgeCalibrationBaseline = edgeCalibrationBaseline(pinned);
      registry.clickBindings ||= new Map();
      if (registry.clickBindings.has(pin)) fail('CLICK_PIN_SPENT');
      registry.clickBindings.set(pin, pinned);
      // The operation retains its original binding independently after begin.
      setTimeout(() => registry.clickBindings.delete(pin), 60000);
      return target;
    }
    if (!validDraft(registry.current) || registry.current.editor !== parts.editor) {
      const address = new URL(route());
      const id = address.origin === 'https://chatgpt.com' && /^\/c\/([^/]+)\/?$/.exec(address.pathname)?.[1];
      registry.current = {...parts, route: route(), navigation: registry.navigation,
        target: {adapterID: 'chatgpt-web', surface: 'webChat', ...native,
          ...(uuid(id) ? {historyConversationID: id.toUpperCase()} : {}),
          documentID: registry.documentID, composerID: nodeID(parts.editor) + ':' + nodeID(parts.form),
          draftGeneration: crypto.randomUUID()}};
    }
    if (native.applicationID === 'com.microsoft.edgemac') registry.current.edgeCalibrationBaseline = edgeCalibrationBaseline(registry.current);
    return registry.current.target;
  }
  const binding = bindingFor(command.target);
  if (command.action === 'validate') return {target: command.target, valid: validDraft(binding)};
  const identity = command.identity;
  if (!identity || !sameTarget(identity.target, command.target)) fail('TARGET_INVALID');
  const acknowledgement = (op, nextChunk) => ({operationID: op.identity.operationID, attempt: op.identity.attempt, nextChunk});
  let op = registry?.operations.get(identity.operationID);
  if (command.action === 'begin') {
    if (!validDraft(binding) || binding.begun) fail('TARGET_INVALID');
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
    if (native.applicationID === 'com.microsoft.edgemac') op.edgeCalibration = {
      baseline: binding.edgeCalibrationBaseline, invocationID: op.invocationID, beforeInput: null, samples: 0,
      trackProgress: command.edgeProgressCandidate === true && binding.target.webDraftRoute === 'chatGPTTemporaryHome'
        && isEdgeTemporary()
        && !!binding.target.clickBindingID
        && op.mediaType === 'image/png' && op.name === 'riftlet-' + op.identity.operationID + '.png'};
    if (op.edgeCalibration && !op.edgeCalibration.trackProgress) op.edgeCalibration.baseline?.witness?.close();
    registry.operations.set(identity.operationID, op);
    if (binding.target.clickBindingID) binding.begun = true;
    registry.scheduleRetirement(registry.operations, identity.operationID, op);
    return acknowledgement(op, 0);
  }
  if (!op || !sameIdentity(op.identity, identity)) {
    if (command.action === 'observe') return blank(identity, 'invalidated');
    fail('ORIGINAL_OPERATION_REQUIRED');
  }
  if (command.action === 'observe') return observe(op);
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
    op.edgeCalibration?.progress?.close();
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
    // A SPA can retain the old editor and its file input while another visible
    // composer takes over. Repeat the original resolver at actual handoff.
    if (op.binding.target.clickBindingID) {
      let current;
      try { current = composer(); } catch { return retire('targetInvalidBeforeInput', 'handoff', 'targetChanged'); }
      if (current.editor !== op.binding.editor || current.form !== op.binding.form)
        return retire('targetInvalidBeforeInput', 'handoff', 'targetChanged');
    }
    diag.inputSeen = true; diag.inputConnected = input.isConnected;
    if (!usableInput(input) || (!invoked && !input.isConnected))
      return retire('attachmentInputNotCreated', 'handoff', 'inputLost');
    if (op.discoveryDeadline && Date.now() >= op.discoveryDeadline)
      return retire('attachmentInputNotCreated', 'handoff', 'timeout');
    op.previewBaseline = new WeakMap([...document.querySelectorAll(previewSelector)].map(node => [node, previewValue(node)]));
    edgeCalibrationBeforeInput(op, file);
    registry.files.set(file, op);
    const writingForm = op.binding.form;
    registry.writingInputs ||= new WeakSet();
    if (registry.busy.has(writingForm) || registry.writingInputs.has(input)) return retire('inputExecutionBusy', 'setter', 'executionBusy');
    registry.busy.add(writingForm); registry.writingInputs.add(input);
    try {
      if (op.binding.target.clickBindingID) retainObservation(op.binding);
      op.inputCount = 1; op.inputSequence = tick(); op.inputTime = performance.now();
      diag.stage = 'setter'; diag.setterEntered = true;
      Reflect.apply(setter, input, [transfer.files]);
      diag.stage = 'change';
      input.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
      const change = new Event('change', {bubbles: true});
      op.edgeCalibration?.progress?.expect(change);
      input.dispatchEvent(change);
      op.edgeCalibration?.progress?.expect(null);
      op.changeReturned = true; diag.changeReturned = true; diag.stage = 'observation';
    } catch (error) {
      // The native setter or a receiver can have taken effect. Never switch
      // paths after entering it, including after a dropped native receipt.
      diag.exceptionType = exceptionName(error); diag.cause = 'deliveryUncertain';
      op.edgeCalibration?.progress?.close();
      op.binding.endObservation?.(); // No returned change can yield a positive START.
    } finally {
      registry.busy.delete(writingForm); registry.writingInputs.delete(input);
    }
    op.executionPending = false;
    return observe(op);
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
