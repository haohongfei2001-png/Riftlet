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
    provenance: {source: 'integratedDevelopment', evidenceID: 'attachment-handoff-20261105-v16'},
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
  function entryControls(binding) {
    const local = control => binding.form !== document.body && binding.form.contains(control);
    const candidates = controls(document).filter(control => !binding.editor.contains(control) && !control.contains(binding.editor)
      && !control.closest('[data-file-name],[role="menu"],[role="menuitem"]')
      && !outsidePurpose(control, binding)
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
  function otherOwner(input, binding, ownControls) {
    if (outsidePurpose(input, binding) || foreignPurpose.test(description(input))) return true;
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
  function directInput(binding, entries) {
    const own = node => entries.includes(node);
    const linked = new Set(entries.flatMap(relatedInputs).filter(input => input.isConnected && !otherOwner(input, binding, own)));
    if (linked.size === 1) return [...linked][0];
    const local = [...document.querySelectorAll('input[type="file"]')].filter(input => input.isConnected
      && usableInput(input) && binding.form !== document.body
      && (binding.form.contains(input) || input.form === binding.form) && !otherOwner(input, binding, own));
    if (local.length === 1) return local[0];
    // Multiple local fields are common. Prefer one labelled for the composer;
    // otherwise the actual entry identifies the object rather than DOM order.
    const named = local.filter(input => attachmentWords.test(description(input)));
    return named.length === 1 ? named[0] : null;
  }
  function preserveSelection(binding) {
    if (binding.editor.tagName === 'TEXTAREA') {
      const editor = binding.editor, value = editor.value, start = editor.selectionStart,
        end = editor.selectionEnd, direction = editor.selectionDirection, active = document.activeElement;
      return () => {
        if (!sameDraft(binding) || editor.value !== value || !Number.isInteger(start) || !Number.isInteger(end)) return;
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
    const anchored = (root, control) => {
      const r = root.getBoundingClientRect(), c = control.getBoundingClientRect();
      if (!r.width || !r.height || !c.width || !c.height) return false;
      // Portalled popovers typically share one axis with their invoker and
      // abut it on the other. Layout is one hint alongside DOM and focus.
      const acrossX = r.left < c.right && c.left < r.right;
      const acrossY = r.top < c.bottom && c.top < r.bottom;
      return (acrossX && Math.min(Math.abs(r.top - c.bottom), Math.abs(c.top - r.bottom)) <= 32)
        || (acrossY && Math.min(Math.abs(r.left - c.right), Math.abs(c.left - r.right)) <= 32);
    };
    const linked = (control, created) => {
      const named = control.id ? [...document.querySelectorAll('[aria-labelledby]')]
        .filter(node => referenced(node, ['aria-labelledby']).includes(control)) : [];
      for (const node of [...controlledElements(control), ...named]) add(node, created);
      if (control.getAttribute('aria-expanded') !== 'true' && control.getAttribute('data-state') !== 'open') return;
      const candidates = [...document.querySelectorAll(surfaceSelector)].filter(node => node !== control && eligible(node) && visible(node));
      const nearby = candidates.filter(node => node.parentElement === control.parentElement
        || node.contains(document.activeElement) || anchored(node, control));
      if (nearby.length === 1) add(nearby[0], created);
      const sibling = control.nextElementSibling;
      if (sibling && controls(sibling).length && fileWords.test(description(sibling))) add(sibling, created);
    };
    const changed = (node, fromControl, expanded, invoked) => {
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
      const nearTrigger = [...invoked].some(control => root.parentElement === control.parentElement
        && root.parentElement !== document.body);
      // Only synchronous control effects are automatically ours. Later page
      // mutations need a relationship with the opener, the focused popover
      // or its open transition. A timer changing an unrelated panel is common.
      const besideOpener = [...invoked].some(control => control.isConnected && anchored(root, control));
      const fileAction = controls(root).some(control => !nonFileAction.test(description(control))
        && !cloudFileWords.test(description(control)) && (relatedInputs(control).length || fileWords.test(description(control))))
        || fileWords.test((root.textContent || '').slice(0, 320));
      if (fromControl || nearTrigger || root.contains(document.activeElement)
        || (besideOpener && (fileAction || (expanded && root.matches(surfaceSelector))))) add(root, true);
    };
    const scan = (invoked, mutations, fromControl = false) => {
      const expanded = [...invoked].some(item => item.getAttribute('aria-expanded') === 'true');
      for (const item of invoked) linked(item, true);
      for (const node of mutations) changed(node, fromControl, expanded, invoked);
      mutations.clear();
      const current = new Map();
      for (const node of controls(document)) {
        if (!eligible(node) || !visible(node)) continue;
        const name = description(node);
        current.set(node, name);
        if (!invoked.has(node) && (!before.has(node) || before.get(node) !== name)) changed(node, fromControl, expanded, invoked);
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
      if (!owned && otherOwner(input, binding, own)) return false;
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
        return interrupted || !sameDraft(binding) || !control.isConnected || captured.size > 0
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
          if (interrupted || !sameDraft(binding) || !control.isConnected) return captured.size > 0;
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
        const valid = sameDraft(binding);
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
        const live = current.length ? current : picked;
        const tied = live.filter(([, fact]) => fact.tied);
        const choices = tied.length ? tied : live;
        if (choices.length > 1) return retire('attachmentInputAmbiguous', 'picker', 'ambiguous');
        if (choices.length === 1) {
          const [input] = choices[0];
          // An arbitrary renderer can create/call another picker later, even
          // if there were no file inputs at click time. Without an observable
          // connection to our action, arbitrate actual invocations within the
          // original deadline. Never use attachment to the DOM as a tiebreak.
          if (tied.length || ended) return execute(input, true);
          await waitForChange(); continue;
        }
        if (ended) break;
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
      if (!sameDraft(binding)) return retire('targetInvalidBeforeInput', diag.stage, 'targetChanged');
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
      if (!interrupted && sameDraft(binding)) {
        for (const root of [...surfaces.opened].reverse()) if (visible(root)) {
          const target = root.contains(document.activeElement) ? document.activeElement : root;
          target.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', code: 'Escape', bubbles: true, cancelable: true}));
        }
        restoreSelection();
      }
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
  const diag = op.entryDiagnostics = {version: 1, entryCandidates: 0, entryActivations: 0,
    openedContainers: 0, menuActivations: 0, pickerClicks: 0, pickerShows: 0,
    inputSeen: false, inputConnected: false, setterEntered: false, changeReturned: false,
    stage: 'prepare', cause: 'none', exceptionType: 'none'};
  const retire = (reason, stage, cause) => {
    op.chunks = []; op.retirement = reason; op.executionPending = false;
    diag.stage = stage; diag.cause = cause;
    return observe(op);
  };
  if (!validDraft(op.binding)) return retire('targetInvalidBeforeInput', 'prepare', 'targetChanged');
  if (registry.busy.has(op.binding.form)) return retire('inputExecutionBusy', 'prepare', 'executionBusy');
  const bytes = new Uint8Array(op.size); let offset = 0;
  for (const chunk of op.chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  op.chunks = [];
  if (![137, 80, 78, 71, 13, 10, 26, 10].every((value, index) => bytes[index] === value))
    return retire('invalidPNGSignature', 'prepare', 'invalidFile');
  let file, transfer, setter;
  try {
    file = new File([bytes], op.name, {type: 'image/png'});
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
    if (!invoked && op.discoveryDeadline && Date.now() >= op.discoveryDeadline)
      return retire('attachmentInputNotCreated', 'handoff', 'timeout');
    op.binding.input = input;
    op.baseline = new Set(attachmentNodes(op.binding));
    registry.files.set(file, op);
    try {
      op.inputCount = 1; op.inputSequence = tick(); op.inputTime = performance.now();
      diag.stage = 'setter'; diag.setterEntered = true;
      Reflect.apply(setter, input, [transfer.files]);
      diag.stage = 'change';
      input.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
      input.dispatchEvent(new Event('change', {bubbles: true}));
      op.changeReturned = true; diag.changeReturned = true; diag.stage = 'observation';
    } catch (error) {
      // The native setter or a receiver can have taken effect. Never switch
      // paths after entering it, including after a dropped native receipt.
      diag.exceptionType = exceptionName(error); diag.cause = 'deliveryUncertain';
    }
    op.executionPending = false;
    return observe(op);
  };
  registry.busy.add(op.binding.form);
  let pending = false;
  try {
    const entries = entryControls(op.binding);
    diag.entryCandidates = entries.length;
    const input = directInput(op.binding, entries);
    if (input) {
      const restore = preserveSelection(op.binding);
      try { diag.stage = 'direct'; return execute(input); }
      finally { restore(); }
    }
    diag.stage = 'entry';
    op.executionPending = true;
    // A page can replace its composer while an earlier entry is finishing.
    // Only one operation intercepts that document's picker methods at a time.
    // Other documents have independent registries. Network upload holds neither.
    const run = () => {
      op.discoveryDeadline = Date.now() + 3000;
      return discoverThroughEntry(op, entries, execute, retire);
    };
    const task = registry.entryTask ? registry.entryTask.then(run, run) : run();
    registry.entryTask = task; pending = true;
    return task.catch(error => {
      diag.exceptionType = exceptionName(error);
      if (diag.setterEntered) { diag.cause = 'deliveryUncertain'; return observe(op); }
      return retire('attachmentEntryFailed', diag.stage, 'exception');
    }).finally(() => {
      op.executionPending = false;
      if (registry.entryTask === task) delete registry.entryTask;
      registry.busy.delete(op.binding.form);
    });
  } finally {
    if (!pending) registry.busy.delete(op.binding.form);
  }
}
