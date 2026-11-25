function riftletConversationAttachment(command, native, profile) {
  'use strict';
  const reject = reason => { throw new Error(reason); };
  const uuid = value => typeof value === 'string' && /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i.test(value);
  const href = location.href;
  const url = new URL(href);
  if (self !== top || url.protocol !== 'https:' || url.username || url.password ||
      !profile?.origins?.includes(url.origin) || profile.adapterID !== profile.id + '-web' ||
      !profile.routes.some(route => new RegExp('^(?:' + route + ')$').test(url.pathname))) reject('PAGE_ROUTE_UNSUPPORTED');

  // Site-owned structures observed on the public entry pages. Sites exposing
  // only sign-in or a challenge can use explicit accessible form relationships.
  const sites = {
    claude: {brand:'Claude|克劳德'},
    copilot: {brand:'(?:Microsoft )?Copilot|微软 Copilot'},
    grok: {brand:'Grok'},
    poe: {brand:'Poe'},
    deepseek: {brand:'DeepSeek|深度求索'},
    spark: {brand:'讯飞星火|星火(?:认知大模型|助手)?|iFlytek Spark', guestEditor:'#login-askwindow-textarea'},
    meta: {brand:'Meta AI'},
    mistral: {brand:'Mistral(?: (?:Vibe|AI))?|Le Chat'},
    gemini: {editor:'rich-textarea .ql-editor[contenteditable="true"]', root:'fieldset.input-area-fieldset,input-area-v2', opener:'button[aria-haspopup="menu"][aria-label]'},
    perplexity: {editor:'[role="textbox"][contenteditable="true"][aria-label]', root:'[class~="group/composer-row"]'},
    kimi: {editor:'.chat-input-editor[contenteditable="true"]', root:'.chat-editor,#chat-box', input:'input.hidden-input[type="file"]', opener:'[data-testid="toolkit-trigger-btn"]'},
    qianwen: {editor:'#input-island-owner [role="textbox"][contenteditable="true"]', root:'#input-island-owner'},
    qwen: {editor:'textarea.message-input-textarea', root:'.message-input-container,.message-input,#dropzone-container', input:'input#filesUpload[type="file"]'},
    doubao: {editor:'.guidance-input-surface .tiptap[contenteditable="true"],#input-engine-container .tiptap[contenteditable="true"]', root:'.guidance-input-surface,#input-engine-container', opener:'[data-testid="upload_file_button"]'},
    yuanbao: {editor:'#searchbar-editor .ql-editor[contenteditable="true"]', root:'#searchbar-editor', opener:'button[aria-label="Add"],button[aria-label="添加"]'},
    qingyan: {editor:'.chat-sender textarea.el-textarea__inner', root:'.chat-sender,.input-box-wrapper', input:'.upload-attachment-picker input.file-input[type="file"]'},
    wenxin: {editor:'textarea#chat-textarea', root:'#ci-main,.ci-root,#chat-input-home', opener:'.ci-merge-upload-wrapper #ci-merge-upload-btn'},
    zai: {editor:'textarea#chat-input', root:'.messageInputContainer,form', opener:'button#upload-file-button'}
  };
  const site = Object.hasOwn(sites, profile.id) && sites[profile.id];
  if (!site) reject('PAGE_ROUTE_UNSUPPORTED');
  const all = (parent, selector) => Array.from(parent.querySelectorAll(selector));
  const visible = node => node.isConnected && !node.closest('[hidden],[inert],[aria-hidden="true"]') &&
    node.getClientRects().length > 0 && getComputedStyle(node).visibility === 'visible';
  const enabled = node => !node.matches(':disabled,[aria-disabled="true"]') && !node.closest('[inert]');
  const editables = 'textarea,[contenteditable="true"],[contenteditable="plaintext-only"]';
  const caption = node => (node.getAttribute('aria-label') || node.getAttribute('title') ||
    node.getAttribute('data-placeholder') || node.getAttribute('placeholder') || node.innerText || '').trim().slice(0, 160);
  const prompt = /ask (?:me|anything|a question)|(?:message|chat with) (?:an? |the )?(?:assistant|claude|gemini|copilot|grok|poe|deepseek|mistral|meta|ai)|send a message|type (?:your|a) (?:message|question)|输入(?:你|您|问题|消息)|请输入|向.{1,12}提问|发消息|问问/iu;
  const fileLabel = /^\s*(?:attach(?:ments?)?\b|upload\b|(?:add|choose|select) (?:local )?(?:files?|photos?|images?|pictures?)\b|(?:添加)?附件|上传|本地文件|添加(?:文件|图片|照片)|选择(?:文件|图片|照片))/iu;
  const otherAction = /(?:\bsend\b|submit|subscribe|upgrade|manage|download|clear|generate|create image|delete|remove|drive|dropbox|sharepoint|onedrive|camera|avatar|profile|folder|audio|video|voice|url|link|project|反馈|发送|删除|移除|网盘|链接|头像|生成|项目|拍照|音频|视频|语音|文件夹|订阅|升级|下载|清除)/iu;
  const controls = 'button,[role="button"],label[for],[role="menuitem"],[role="option"]';
  const excluded = 'nav,aside,article,a[href],[role="log"],[role="dialog"],[role="toolbar"][aria-label*="format" i]';
  function namedConversation(editor) {
    const roleName = node => [node.getAttribute('aria-label'),node.getAttribute('data-placeholder'),
      node.getAttribute('placeholder'),...(node.getAttribute('aria-labelledby') || '').split(/\s+/).filter(Boolean)
        .map(id => document.getElementById(id)?.textContent?.slice(0,160))].filter(Boolean).join(' ');
    const brand = '(?:' + site.brand + ')';
    const explicit = new RegExp('(?:ask|message|talk to|chat with)\\s+' + brand + '(?:\\s|[\\p{P}]|$)|' +
      '(?:与|和|向|给)\\s*' + brand + '\\s*(?:对话|交谈|提问|发送消息|发消息)|' + brand + '\\s*(?:的)?(?:对话|聊天)|' +
      brand + '\\s+(?:chat|conversation|composer)(?:\\s|$)','iu');
    const name = roleName(editor);
    if (explicit.test(name)) return true;
    const group = editor.closest('form,fieldset,[role="form"],[role="group"]');
    return !!group && explicit.test(roleName(group)) && prompt.test(name);
  }
  const fileInput = node => node instanceof HTMLInputElement && node.type === 'file' && enabled(node) &&
    !node.webkitdirectory && !otherAction.test([node.id, node.name, node.getAttribute('aria-label')].join(' '));
  function ownControl(node) {
    if (!visible(node) || !enabled(node) || node.matches('[type="submit"],[type="reset"]') ||
        (node instanceof HTMLButtonElement && node.form && node.type === 'submit') ||
        node.closest(excluded) || otherAction.test(caption(node))) return false;
    if (site.opener && node.matches(site.opener)) {
      return profile.id !== 'gemini' || fileLabel.test(caption(node));
    }
    return fileLabel.test(caption(node));
  }
  function entries(root, recognized) {
    const openers = all(root, recognized && site.opener ? controls + ',' + site.opener : controls).filter(ownControl);
    const accepted = new Set();
    if (recognized && site.input) for (const field of all(root, site.input)) if (fileInput(field)) accepted.add(field);
    for (const entry of openers) {
      if (entry instanceof HTMLLabelElement && fileInput(entry.control)) accepted.add(entry.control);
      const id = entry.getAttribute('aria-controls');
      if (id && !/\s/.test(id)) {
        const field = document.getElementById(id);
        if (fileInput(field)) accepted.add(field);
      }
    }
    // A named image/file input inside the actual composer can itself be the
    // entry. Unrelated hidden fields elsewhere in the document never qualify.
    for (const field of all(root, 'input[type="file"]')) {
      const label = [field.getAttribute('aria-label'), ...Array.from(field.labels || [], caption)].join(' ');
      if (fileInput(field) && fileLabel.test(label) && !otherAction.test(label)) accepted.add(field);
    }
    if (accepted.size > 1 || (!accepted.size && openers.length > 1)) return null;
    const input = Array.from(accepted)[0];
    return input ? {input, opener:null} : openers.length === 1 ? {input:null, opener:openers[0]} : null;
  }
  function surface() {
    const candidates = all(document, editables).filter(node => visible(node) && enabled(node) && !node.readOnly &&
      !node.closest(excluded) && !(site.guestEditor && node.matches(site.guestEditor)) &&
      (site.editor ? node.matches(site.editor) : namedConversation(node)));
    if (candidates.length !== 1) return null;
    const editor = candidates[0];
    for (let root = editor.parentElement; root && root !== document.body; root = root.parentElement) {
      const recognized = !!(site.editor && editor.matches(site.editor) && root.matches(site.root));
      if (!recognized && (site.editor || !root.matches('form,fieldset,[role="form"],[role="group"]'))) continue;
      if (root.matches(excluded) || root.querySelector('input[type="password"]') ||
          all(root, editables).some(node => node !== editor && visible(node) && enabled(node) && !node.matches('.ql-clipboard'))) continue;
      const entry = entries(root, recognized);
      if (entry && (!entry.input?.form || entry.input.form.contains(editor))) return {editor, root, ...entry};
    }
    return null;
  }
  const eventName = (pin, role) => 'riftlet-conversation-' + pin + '-' + role;
  const objects = parts => [parts.editor, parts.root, parts.input || parts.opener];
  const sameParts = (a,b) => !!a && !!b && a.editor === b.editor && a.root === b.root &&
    a.input === b.input && a.opener === b.opener;
  const hasOriginal = (parts, address) => document === parts.editor.ownerDocument && location.href === address &&
    parts.editor.isConnected && parts.root.contains(parts.editor);
  if (command.action === 'pinTarget') {
    const pin = command.clickWitnessID;
    if (!uuid(pin) || command.address !== href || document.visibilityState !== 'visible' ||
        !window.navigation?.currentEntry) return 'refused';
    const parts = surface();
    if (!parts) return 'refused';
    const original = objects(parts);
    const abort = new AbortController();
    let timer;
    function close() { clearTimeout(timer); observer.disconnect(); abort.abort(); }
    const changed = records => records.some(record => Array.from(record.removedNodes).some(removed =>
      original.some(node => removed === node || removed.contains(node))));
    const observer = new MutationObserver(records => { if (changed(records)) close(); });
    observer.observe(document, {childList:true,subtree:true});
    original.forEach((node,i) => node.addEventListener(eventName(pin,i), event => {
      if (event.target === node && hasOriginal(parts,href) && !changed(observer.takeRecords())) {
        event.preventDefault();
      } else close();
    }, {signal:abort.signal}));
    parts.editor.addEventListener(eventName(pin,'close'), close, {signal:abort.signal});
    for (const name of ['pagehide','popstate','hashchange']) addEventListener(name, close, {signal:abort.signal});
    window.navigation?.addEventListener('navigate', close, {signal:abort.signal});
    window.navigation?.addEventListener('currententrychange',close,{signal:abort.signal});
    // The relay installs its own original-node lifetime guard when it adopts
    // this pin. Abandoned, unadopted cross-world listeners expire on their own.
    timer = setTimeout(close,60000);
    return 'bound';
  }
  // RIFTLET_CLICK_PIN_END
  const blank = (identity, state = 'unknown') => ({schemaVersion:2,
    provenance:{source:'integratedDevelopment',evidenceID:'conversation-provider-20261125-v1'},
    observation:{identity,state,exactImageIdentity:false,belongsToOriginalDraft:false,hasError:false,
      isUploading:false,attachmentAbsent:false,automaticRetryExcluded:false}});
  const browserIDs = ['com.google.Chrome','com.microsoft.edgemac','com.apple.Safari'];
  const nativeKeys = ['applicationID','sessionID','windowID','tabID'];
  const targetKeys = [...nativeKeys,'surface','adapterID','documentID','composerID','draftGeneration','clickBindingID'];
  function sameTarget(a,b) {
    return !!a && !!b && targetKeys.every(key => a[key] === b[key]) &&
      a.logicalDraftIdentity?.id === b.logicalDraftIdentity?.id &&
      a.logicalDraftIdentity?.profileID === b.logicalDraftIdentity?.profileID;
  }
  const key = Symbol.for('riftlet.conversation.providers.20261125.' + profile.id);
  let registry = document[key];
  if (!registry && command.action === 'captureTarget') {
    registry = {id:crypto.randomUUID(), sequence:0, bindings:new Map(), operations:new Map(), generations:new WeakMap(), busy:new WeakSet()};
    Object.defineProperty(document,key,{value:registry});
  }
  function observeLifetime(parts) {
    const {editor, root} = parts;
    const previous = registry.generations.get(editor);
    if (previous?.original() && previous.root === root) return previous;
    let live = true, users = 0;
    const epoch = crypto.randomUUID(), composer = crypto.randomUUID();
    const abort = new AbortController();
    const removed = list => list.some(m => Array.from(m.removedNodes).some(n => n.contains(editor) || n.contains(root)));
    const observer = new MutationObserver(list => { if (removed(list)) close(); });
    observer.observe(document,{subtree:true,childList:true});
    function close() { live = false; abort.abort(); observer.disconnect(); }
    for (const name of ['pagehide','popstate','hashchange']) addEventListener(name,close,{signal:abort.signal});
    window.navigation?.addEventListener('navigate',close,{signal:abort.signal});
    window.navigation?.addEventListener('currententrychange',close,{signal:abort.signal});
    const generation = {root,epoch,composer, original() {
      if (live && (removed(observer.takeRecords()) || !hasOriginal(parts,href))) close();
      return live;
    }, retain() { users++; }, release() { if (--users === 0) close(); }};
    registry.generations.set(editor,generation);
    return generation;
  }
  if (command.action === 'captureTarget') {
    if (!browserIDs.includes(native?.applicationID) || !nativeKeys.every(k => typeof native[k] === 'string' && native[k])) reject('NATIVE_CONTEXT_REQUIRED');
    const pin = command.clickWitnessID, parts = surface();
    if (!uuid(pin) || !parts || registry.bindings.has(pin) || document.visibilityState !== 'visible') reject('CLICK_PIN_REFUSED');
    if (!objects(parts).every((node,i) => !node.dispatchEvent(new Event(eventName(pin,i),{cancelable:true})))) reject('CLICK_PIN_REFUSED');
    parts.editor.dispatchEvent(new Event(eventName(pin,'close')));
    let pendingCount = 0;
    for (const pending of registry.bindings.values()) {
      if (pending.enrolled) continue;
      if (!original(pending) || !pending.entryCurrent()) pending.close();
      else pendingCount++;
    }
    if (pendingCount >= 3) reject('CLICK_PIN_LIMIT');
    const generation = observeLifetime(parts);
    generation.retain();
    const target = {adapterID:profile.adapterID,surface:'webChat',applicationID:native.applicationID,
      sessionID:native.sessionID,windowID:native.windowID,tabID:native.tabID,documentID:registry.id,
      composerID:generation.composer,draftGeneration:generation.epoch,clickBindingID:pin,
      logicalDraftIdentity:{profileID:'conversation-composer-20261125-v1',id:profile.id + ':' + generation.epoch}};
    const entry = parts.input || parts.opener;
    let continuous = true;
    const disconnected = records => records.some(m => Array.from(m.removedNodes).some(node => node.contains(entry)));
    const entryObserver = new MutationObserver(records => { if (disconnected(records)) continuous = false; });
    entryObserver.observe(document,{subtree:true,childList:true});
    const binding = {parts,generation,target,enrolled:false,finishInput:() => entryObserver.disconnect(),entryCurrent() {
      if (disconnected(entryObserver.takeRecords())) continuous = false;
      return continuous;
    }};
    let timer;
    binding.close = () => {
      if (registry.bindings.get(pin) !== binding) return;
      clearTimeout(timer); entryObserver.disconnect(); registry.bindings.delete(pin); generation.release();
    };
    binding.renew = () => {
      clearTimeout(timer);
      binding.deadline = Date.now() + 600000;
      timer = setTimeout(binding.close,600000);
    };
    registry.bindings.set(pin,binding);
    binding.renew();
    return target;
  }
  const identity = command.identity;
  const target = command.target || identity?.target;
  const bound = registry?.bindings.get(target?.clickBindingID);
  const binding = bound && sameTarget(target,bound.target) && nativeKeys.every(k => target[k] === native?.[k]) ? bound : null;
  function original(b) { return !!b && b.deadline > Date.now() && b.generation.original(); }
  function writable(b) { return original(b) && b.entryCurrent() && document.visibilityState === 'visible' && sameParts(b.parts,surface()); }
  if (command.action === 'releasePreparedTarget') {
    if (!binding || binding.enrolled) return {released:false};
    binding.close(); return {released:true};
  }
  if (command.action === 'validate' || command.action === 'renewPreparedTarget') {
    const recovery = command.recoverySource || command.recoveryInspection;
    const valid = !recovery && (binding?.enrolled
      ? command.action === 'validate' && original(binding) : writable(binding));
    if (valid && command.action === 'renewPreparedTarget') binding.renew();
    return recovery ? {target,valid:false,recoveryChecked:true,attachmentPresence:'unknown'} : {target,valid};
  }
  if (!identity || !target || !sameTarget(identity.target,target)) reject('ORIGINAL_OPERATION_REQUIRED');
  const ack = op => ({operationID:op.identity.operationID,attempt:op.identity.attempt,nextChunk:op.nextChunk});
  let op = registry?.operations.get(identity.operationID);
  if (command.action === 'begin') {
    if (!writable(binding) || binding.enrolled || command.recoverySource) reject('TARGET_INVALID');
    if (op || !uuid(identity.operationID) || !uuid(identity.assetID) || !uuid(command.invocationID) ||
        !Number.isSafeInteger(identity.attempt) || identity.attempt < 1 || !/^[a-f0-9]{64}$/i.test(identity.assetSHA256) ||
        typeof command.uploadName !== 'string' || !command.uploadName.toLowerCase().startsWith('riftlet-' + identity.operationID.toLowerCase() + '.') ||
        !/^riftlet-[a-f0-9-]{36}\.[a-z0-9]{1,12}$/i.test(command.uploadName) ||
        !/^image\/[a-z0-9][a-z0-9.+-]{0,63}$/i.test(command.mediaType) ||
        !Number.isSafeInteger(command.byteCount) || command.byteCount < 1 || command.byteCount > 128*1024*1024) reject('BEGIN_REFUSED');
    op = {identity,binding,invocation:command.invocationID,name:command.uploadName,size:command.byteCount,
      mediaType:command.mediaType,parts:[],received:0,nextChunk:0,inputCount:0,committed:false};
    registry.operations.set(identity.operationID,op);
    binding.enrolled = true; binding.renew();
    setTimeout(() => { op.stopWatch?.(); op.stopMember?.(); op.parts = []; op.file = null; registry.operations.delete(identity.operationID); binding.close(); },600000);
    return ack(op);
  }
  if (!op || !binding || op.binding !== binding || identity.assetID !== op.identity.assetID || identity.attempt !== op.identity.attempt ||
      identity.assetSHA256 !== op.identity.assetSHA256) {
    if (command.action === 'observe') return blank(identity,'invalidated');
    reject('ORIGINAL_OPERATION_REQUIRED');
  }
  if (command.action === 'observe') {
    if (command.requireLiveOriginal && (op.invocation !== command.invocationID || !original(binding) ||
        (op.start && !op.liveMember?.()))) return blank(identity,'invalidated');
    return sample(op);
  }
  if (op.invocation !== command.invocationID) reject('INVOCATION_MISMATCH');
  if (command.action === 'discard') {
    if (!op.committed) { op.discarded = true; op.parts = []; binding.finishInput(); }
    return {discarded:!op.committed,inputCount:op.inputCount};
  }
  if (command.action === 'chunk') {
    const data = command.chunkBase64;
    if (op.discarded || op.committed || command.chunkIndex !== op.nextChunk || typeof data !== 'string' ||
        data.length > 4 * Math.ceil(262144/3) || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(data)) reject('CHUNK_REFUSED');
    const bytes = Uint8Array.from(atob(data),char => char.charCodeAt(0));
    if (!bytes.length || bytes.length > 262144 || op.received + bytes.length > op.size) reject('CHUNK_REFUSED');
    op.parts.push(bytes); op.received += bytes.length; op.nextChunk++;
    return ack(op);
  }
  if (command.action !== 'commit') reject('UNKNOWN_ACTION');
  if (op.committed || op.discarded || op.received !== op.size || command.chunkIndex !== op.nextChunk) reject('COMMIT_REFUSED');
  op.committed = true;
  op.executionPending = true;
  return commit(op);

  // A single, synchronous activation can reveal the actual input, even when
  // the site's handler creates it detached. Restore both methods before any
  // promise can yield. Never pick a field from an unrelated global scan.
  function preserveSelection(parts, control, action) {
    const {editor,root} = parts, active = document.activeElement, selection = getSelection();
    const textInput = editor instanceof HTMLTextAreaElement;
    const selectedHere = textInput || (selection?.anchorNode && selection.focusNode &&
      editor.contains(selection.anchorNode) && editor.contains(selection.focusNode));
    if (!selectedHere) return action();
    const text = textInput ? editor.value : editor.textContent;
    const anchor = textInput ? editor.selectionStart : selection.anchorNode;
    const focus = textInput ? editor.selectionEnd : selection.focusNode;
    const direction = textInput ? editor.selectionDirection : null;
    const a = selection?.anchorOffset, f = selection?.focusOffset;
    try { return action(); }
    finally {
      // Only restore synchronous effects of our one original receiver. A real
      // user's subsequent edits, focus and selection are never observed or reset.
      if (hasOriginal(parts,href) && (textInput ? editor.value : editor.textContent) === text) {
        const now = document.activeElement;
        const ownFocus = now === active || now === document.body || root.contains(now) || now === control || control?.contains(now);
        if (ownFocus) {
          if (now !== active && editor.contains(active)) active.focus({preventScroll:true});
          if (textInput) {
            if (editor.selectionStart !== anchor || editor.selectionEnd !== focus || editor.selectionDirection !== direction)
              editor.setSelectionRange(anchor,focus,direction);
          } else if (editor.contains(anchor) && editor.contains(focus) &&
              (selection.anchorNode !== anchor || selection.focusNode !== focus || selection.anchorOffset !== a || selection.focusOffset !== f))
            selection.setBaseAndExtent(anchor,a,focus,f);
        }
      }
    }
  }
  function activate(entry, parts) {
    const calls = new Set(), cleanups = [];
    const proto = HTMLInputElement.prototype;
    function intercept(method) {
      if (typeof proto[method] !== 'function') return;
      const descriptor = Object.getOwnPropertyDescriptor(proto,method);
      const originalMethod = proto[method];
      Object.defineProperty(proto,method,{configurable:true,writable:true,value:function(...args) {
        if (this instanceof HTMLInputElement && this.type === 'file') { calls.add(this); return; }
        return Reflect.apply(originalMethod,this,args);
      }});
      cleanups.push(() => descriptor ? Object.defineProperty(proto,method,descriptor) : delete proto[method]);
    }
    try {
      intercept('click'); intercept('showPicker');
      const click = new MouseEvent('click',{bubbles:true,cancelable:true,composed:true,view:window});
      preserveSelection(parts,entry,() => entry.dispatchEvent(click));
    } finally { for (const restore of cleanups.reverse()) restore(); }
    return calls;
  }
  async function discover(b) {
    const parts = b.parts, opener = parts.opener;
    if (parts.input) return {input:parts.input,valid:() => writable(b) && fileInput(parts.input)};
    if (!opener || !writable(b) || !ownControl(opener)) return {reason:'attachmentEntryUnavailable'};
    const popups = '[role="menu"],[role="listbox"],[popover]';
    function linkedTo(entry,node) {
      for (const key of ['aria-controls','aria-owns','popovertarget']) {
        const ids = (entry.getAttribute(key) || '').split(/\s+/).filter(Boolean);
        if (ids.some(id => document.getElementById(id) === node)) return true;
      }
      return !!entry.id && (node.getAttribute('aria-labelledby') || '').split(/\s+/).includes(entry.id);
    }
    function ownedPopup(node) {
      return visible(node) && !node.closest('nav,aside,article,[role="dialog"]') &&
        linkedTo(opener,node);
    }
    const rootOriginal = () => original(b) && b.entryCurrent() && document.visibilityState === 'visible' && opener.isConnected && parts.root.contains(opener);
    function linkedFields(entry) {
      const nodes = new Set();
      if (entry instanceof HTMLLabelElement) nodes.add(entry.control);
      for (const key of ['aria-controls','aria-owns']) {
        for (const id of (entry.getAttribute(key) || '').split(/\s+/).filter(Boolean))
          nodes.add(document.getElementById(id));
      }
      return Array.from(nodes).filter(field => fileInput(field) && field.ownerDocument === document &&
        (!field.form || field.form.contains(parts.editor)) && !field.closest(excluded));
    }
    function fromCall(calls,entry,popup = null) {
      if (!calls.size) return null;
      const [field] = calls;
      if (calls.size !== 1 || !fileInput(field) || (field.isConnected && !parts.root.contains(field) &&
          !popup?.contains(field) && !linkedTo(entry,field)) ||
          (field.form && !field.form.contains(parts.editor))) return {reason:'attachmentInputAmbiguous'};
      return {input:field,valid:() => rootOriginal() && fileInput(field) &&
        (!field.isConnected || parts.root.contains(field) || popup?.contains(field) || linkedTo(entry,field))};
    }
    let direct;
    try {
      direct = fromCall(activate(opener,parts),opener);
    } catch { return {reason:'attachmentEntryFailed'}; }
    if (direct) return direct;
    let activatedMenu = null, activatedItem = null;
    const deadline = performance.now() + 1100;
    while (rootOriginal()) {
      const entry = activatedItem || opener;
      const entryStillOwned = () => rootOriginal() && (!activatedItem ||
        (ownedPopup(activatedMenu) && activatedMenu.contains(activatedItem)));
      if (!entryStillOwned()) return {reason:'attachmentEntryUnavailable'};
      const fields = linkedFields(entry);
      if (fields.length > 1) return {reason:'attachmentInputAmbiguous'};
      if (fields.length === 1) return {input:fields[0],valid:() => {
        const current = linkedFields(entry);
        return entryStillOwned() && current.length === 1 && current[0] === fields[0];
      }};
      if (!activatedItem) {
        const menus = all(document,popups).filter(ownedPopup);
        if (menus.length > 1) return {reason:'attachmentInputAmbiguous'};
        if (menus.length === 1) {
          const menu = menus[0], items = all(menu,controls).filter(item => visible(item) && enabled(item) &&
            fileLabel.test(caption(item)) && !otherAction.test(caption(item)) &&
            !(item instanceof HTMLButtonElement && item.form && item.type === 'submit') && !item.closest('a[href]'));
          if (items.length > 1) return {reason:'attachmentInputAmbiguous'};
          if (items.length === 1) {
            const item = items[0]; activatedItem = item; activatedMenu = menu;
            if (item instanceof HTMLLabelElement && fileInput(item.control)) {
              const field = item.control;
              return {input:field,valid:() => rootOriginal() && ownedPopup(menu) && item.control === field && fileInput(field)};
            }
            try { direct = fromCall(activate(item,parts),item,menu); }
            catch { return {reason:'attachmentEntryFailed'}; }
            if (direct) return direct;
            continue;
          }
        }
      }
      const remaining = deadline - performance.now();
      if (remaining <= 0) break;
      await new Promise(resolve => {
        const observer = new MutationObserver(done);
        const timer = setTimeout(done,remaining);
        function done() { clearTimeout(timer); observer.disconnect(); resolve(); }
        observer.observe(document,{subtree:true,childList:true,attributes:true,attributeFilter:['aria-expanded','aria-controls','aria-owns','aria-labelledby','popovertarget','for','hidden','style','class']});
      });
    }
    return {reason:rootOriginal() ? 'attachmentInputNotCreated' : 'targetInvalidBeforeInput'};
  }
  // Capture only local attachment members, never page transcripts or remote
  // images. The old set cannot be replaced/removed then reinserted to certify
  // that a second screenshot preserved the first one.
  function watchMembers(op) {
    const {root,editor} = op.binding.parts;
    const chipSelector = '[data-filename],[data-file-name],[aria-label*="attachment" i],figure,[class*="attachment" i],[class*="file-chip" i],[class*="file-preview" i]';
    const filter = node => !editor.contains(node) && !node.contains(editor) && !node.closest('nav,article,aside,[role="log"],a[href],[role="menu"]');
    const images = () => all(root,'img[src],img[srcset]').filter(filter);
    const chips = () => all(root,chipSelector).filter(node => filter(node) && !node.matches(controls) && !node.querySelector(editables));
    const initial = new Map();
    const keys = ['src','srcset','alt','data-filename','data-file-name','title','aria-label'];
    const attrs = node => keys.map(k => node.getAttribute(k));
    for (const node of [...images(),...chips()]) initial.set(node,attrs(node));
    const changed = new WeakSet(), proofs = new WeakMap();
    let oldGood = true;
    const claimed = registry.claimed ||= new WeakSet();
    const inspect = records => {
      for (const m of records) {
        if (m.type === 'attributes') {
          if (m.oldValue !== m.target.getAttribute(m.attributeName)) {
            if (initial.has(m.target)) oldGood = false;
            changed.add(m.target);
          }
        } else {
          for (const removed of m.removedNodes) {
            for (const node of initial.keys()) if (removed.contains(node)) oldGood = false;
            if (removed.nodeType === 1) {
              changed.add(removed);
              for (const img of all(removed,'img')) changed.add(img);
            }
          }
        }
      }
    };
    const observer = new MutationObserver(inspect);
    observer.observe(root,{childList:true,subtree:true,attributes:true,attributeOldValue:true,attributeFilter:keys});
    const timer = setTimeout(stop,12000);
    function stop() {
      clearTimeout(timer); observer.disconnect(); initial.clear(); op.inspect = null; op.file = null;
      op.decoded?.close?.(); op.decoded = null; op.decoding = null;
    }
    const initialIntact = () => oldGood && [...initial].every(([n,values]) =>
      root.contains(n) && keys.every((k,i) => n.getAttribute(k) === values[i]));
    const failed = node => /(?:upload failed|failed to upload|error uploading|couldn.t upload|上传失败|上传出错)/iu.test(
      ((node.getAttribute('aria-label') || '') + ' ' + (node.innerText || '')).slice(0,1024)) ||
      !!node.querySelector('[data-state="error"],[data-state="failed"]') || node.matches('[data-state="error"],[data-state="failed"]');
    const progress = node => !!node.querySelector('progress,[role="progressbar"],[aria-busy="true"]') || node.matches('[aria-busy="true"]');
    const source = img => [img.currentSrc,img.getAttribute('src'),img.getAttribute('srcset')].join('\n');
    function member(image) {
      if (!visible(image) || !image.complete || !image.naturalWidth || !image.naturalHeight || initial.has(image) || claimed.has(image)) return null;
      let named = false, card = null;
      for (let node = image; node && node !== root && !node.contains(editor); node = node.parentElement) {
        if (([...attrs(node),node.childElementCount === 0 ? node.textContent : null]).some(value => value && value.trim() === op.name)) {
          named = true; card = node.tagName === 'IMG' ? node.parentElement : node; break;
        }
        if (node.matches(chipSelector) && !node.matches(controls)) {
          if (all(node,'[data-filename],[data-file-name],[title],[aria-label],span').some(part =>
            [...attrs(part),part.childElementCount ? null : part.textContent].some(value => value?.trim() === op.name))) named = true;
          card = node; break;
        }
      }
      if (!card || card === root || initial.has(card) || !filter(card) || all(card,'img').length !== 1) return null;
      return {image,card,named,src:source(image)};
    }
    op.stopWatch = stop;
    op.inspect = async () => {
      inspect(observer.takeRecords());
      if (!original(op.binding) || !initialIntact() || !op.file) return;
      const candidates = images().map(member).filter(Boolean);
      const exactName = candidates.filter(m => m.named);
      if (exactName.length > 1 || (!exactName.length && (candidates.length !== 1 || op.requiresName))) return;
      const candidate = exactName[0] || candidates[0];
      if (!candidate) return;
      const {image,card,src} = candidate;
      // Changes prior to the start of this comparison are fine (lazy-loaded
      // images). During comparison, any change/removal makes this result stale.
      changed.delete(image); changed.delete(card);
      let proof = proofs.get(image);
      if (!proof || proof.src !== src) {
        proof = {src,pixels:equalPixels(op,image)}; proofs.set(image,proof);
      }
      if (!await proof.pixels) return;
      inspect(observer.takeRecords());
      if (!op.file || !original(op.binding) || !initialIntact() || changed.has(image) || changed.has(card) ||
          !card.contains(image) || !root.contains(card) || source(image) !== src ||
          !member(image) || claimed.has(image) || (failed(card) && progress(card))) return;
      let continuous = true;
      const breaksMember = records => records.some(m => m.type === 'childList'
        ? Array.from(m.removedNodes).some(node => node.contains(card) || node.contains(image))
        : m.target === image && m.oldValue !== image.getAttribute(m.attributeName));
      const memberObserver = new MutationObserver(records => {
        if (breaksMember(records)) { continuous = false; memberObserver.disconnect(); }
      });
      memberObserver.observe(root,{childList:true,subtree:true,attributes:true,attributeOldValue:true,attributeFilter:['src','srcset','alt']});
      op.stopMember = () => memberObserver.disconnect();
      const liveMember = () => {
        if (breaksMember(memberObserver.takeRecords())) continuous = false;
        return continuous && original(op.binding) && root.contains(card) && card.contains(image) && source(image) === src;
      };
      const hasFailure = () => liveMember() && failed(card) && !progress(card);
      op.memberID = registry.id + ':' + crypto.randomUUID();
      op.liveMember = liveMember; op.hasFailure = hasFailure;
      claimed.add(image);
      if (!hasFailure()) {
        op.start = {version:1,signal:'attachmentAccepted',evidenceID:crypto.randomUUID(),inputCount:1,
          inputSequence:op.inputSequence,startSequence:++registry.sequence,previousProgress:0,currentProgress:0,
          inputObservedAtMS:op.inputTime,startObservedAtMS:Math.max(op.inputTime,performance.now())};
      }
      stop();
    };
  }
  async function equalPixels(op,image) {
    try {
      if (!op.decoding) {
        const file = op.file;
        op.decoding = (async () => {
          if (typeof createImageBitmap === 'function') return createImageBitmap(file);
          const url = URL.createObjectURL(file);
          try { const img = new Image(); img.src = url; await img.decode(); return img; }
          finally { URL.revokeObjectURL(url); }
        })().then(decoded => {
          if (!op.file) { decoded.close?.(); return null; }
          op.decoded = decoded; return decoded;
        });
      }
      const originalImage = await op.decoding;
      const width = image.naturalWidth, height = image.naturalHeight;
      if (!originalImage || (originalImage.naturalWidth || originalImage.width) !== width ||
          (originalImage.naturalHeight || originalImage.height) !== height || width * height > 32000000) return false;
      // Read a bounded stripe at a time. A cross-origin preview with no canvas
      // access stays unproven. Creating the proof never fetches a remote URL.
      const stripe = Math.max(1,Math.min(height,Math.floor(65536/width)));
      const canvas = document.createElement('canvas');
      canvas.width = width; canvas.height = stripe;
      const ctx = canvas.getContext('2d',{willReadFrequently:true});
      const read = (object,y,h) => {
        ctx.clearRect(0,0,width,h);
        ctx.drawImage(object,0,y,width,h,0,0,width,h);
        return new Uint32Array(ctx.getImageData(0,0,width,h).data.buffer);
      };
      for (let y = 0; y < height; y += stripe) {
        const h = Math.min(stripe,height-y);
        const a = read(originalImage,y,h), b = read(image,y,h);
        for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
      }
      return true;
    } catch { return false; }
  }
  async function sample(op) {
    if (op.inspect && op.changeReturned) {
      // Concurrent read-only observations must share one comparison and one
      // immutable START receipt.
      if (!op.sampling) op.sampling = op.inspect().finally(() => { op.sampling = null; });
      await op.sampling;
    }
    const result = blank(op.identity), item = result.observation;
    item.belongsToOriginalDraft = original(op.binding);
    item.inputExecutionPending = op.executionPending === true;
    if (op.retirement) {
      result.schemaVersion = 3; item.state = 'invalidated';
      item.preInputRetirement = {version:1,invocationID:op.invocation,commitInvoked:true,commitWorkSettled:true,
        irreversiblyRetired:true,inputSideEffectEntered:false,inputCount:0,reason:op.retirement};
    } else if (op.hasFailure?.() && !(op.start && command.preferStartReceipt)) {
      item.state = 'originalCardFailed'; item.hasError = true; item.exactImageIdentity = true;
      item.attachmentID = op.memberID; item.originalCardFailureInvocationID = op.invocation;
    } else if (op.start) {
      item.state = 'uploadStarted'; item.uploadStart = op.start; item.exactImageIdentity = true;
      item.belongsToOriginalDraft = true; item.attachmentID = op.memberID;
    } else if (op.changeReturned) item.state = 'inputTriggered';
    return result;
  }
  async function commit(op) {
    function retire(reason) {
      op.retirement = reason; op.executionPending = false; op.parts = []; op.file = null; op.stopWatch?.(); op.binding.finishInput();
      return sample(op);
    }
    const b = op.binding, parts = b.parts;
    if (!writable(b)) return retire('targetInvalidBeforeInput');
    if (registry.busy.has(parts.root)) return retire('inputExecutionBusy');
    registry.busy.add(parts.root);
    try {
      op.file = new File(op.parts,op.name,{type:op.mediaType}); op.parts = [];
      if (op.mediaType === 'image/png') {
        const header = new Uint8Array(await op.file.slice(0,8).arrayBuffer());
        if (![137,80,78,71,13,10,26,10].every((value,i) => header[i] === value)) return retire('invalidPNGSignature');
      }
      const transfer = new DataTransfer(); transfer.items.add(op.file);
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'files')?.set;
      if (typeof setter !== 'function') return retire('inputPreparationFailed');
      const entry = await discover(b);
      if (entry.reason) return retire(entry.reason);
      if (!entry.valid()) return retire('targetInvalidBeforeInput');
      for (const pending of registry.operations.values()) {
        if (pending !== op && pending.inputCount && pending.inspect && pending.identity.assetSHA256 === op.identity.assetSHA256 &&
            pending.binding.parts.root === parts.root) { op.requiresName = true; pending.requiresName = true; }
      }
      watchMembers(op);
      const input = entry.input;
      if (!entry.valid()) return retire('targetInvalidBeforeInput');
      op.inputCount = 1; op.inputSequence = ++registry.sequence; op.inputTime = performance.now();
      const inputParent = input.parentNode, inputForm = input.form;
      Reflect.apply(setter,input,[transfer.files]);
      const receiver = () => original(b) && document.visibilityState === 'visible' &&
        input.ownerDocument === document && input.parentNode === inputParent && input.form === inputForm && entry.valid();
      if (receiver()) {
        preserveSelection(parts,input,() => input.dispatchEvent(new Event('input',{bubbles:true,composed:true})));
        if (receiver()) {
          preserveSelection(parts,input,() => input.dispatchEvent(new Event('change',{bubbles:true})));
          op.changeReturned = true;
        }
      }
    } catch {
      if (!op.inputCount) return retire('inputPreparationFailed');
      // A setter or handler can have taken effect even when it throws.
    } finally { registry.busy.delete(parts.root); b.finishInput(); op.executionPending = false; }
    return sample(op);
  }
}
