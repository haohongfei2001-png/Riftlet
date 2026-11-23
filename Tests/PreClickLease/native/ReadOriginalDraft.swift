// Fixed observational script used only on the newly created, exact temporary tab.
// The private QA sentence and the empty string are the only editor strings it returns.
let readOriginalDraft = #"""
(() => {
  if (top !== self || location.href !== 'https://chatgpt.com/?temporary-chat=true' ||
      !navigation.currentEntry?.id) return '';
  const visible = n => n?.getClientRects().length > 0 && n.checkVisibility({checkOpacity:true, checkVisibilityCSS:true});
  const elements = (root, selector) => [...root.querySelectorAll(selector)].filter(visible);
  const sentence = 'Riftlet QA: preserve this original draft while attaching images.';
  const forms = elements(document, 'main form');
  const form = forms.length === 1 ? forms[0] : null;
  const editors = form ? elements(form, '[contenteditable=true],textarea,[role=textbox]').filter(e=>e.isContentEditable || e.tagName==='TEXTAREA') : [];
  const editor = editors.length === 1 ? editors[0] : null;
  const rawText = editor ? (editor.isContentEditable ? editor.innerText : editor.value) : null;
  const text = rawText === '' || rawText === '\n' ? '' : rawText === sentence ? sentence : null;
  const selected = document.getSelection();
  let selection = null;
  if (editor && text === sentence && selected?.rangeCount === 1 &&
      editor.contains(selected.anchorNode) && editor.contains(selected.focusNode)) {
    const index = (node,offset) => {
      const r = document.createRange(); r.selectNodeContents(editor); r.setEnd(node,offset); return r.toString().length;
    };
    const anchor = index(selected.anchorNode,selected.anchorOffset), focus = index(selected.focusNode,selected.focusOffset);
    selection = {anchor,focus,start:Math.min(anchor,focus),end:Math.max(anchor,focus),
      anchorOffset:selected.anchorOffset,focusOffset:selected.focusOffset,
      direction:anchor === focus ? 'none' : anchor < focus ? 'forward' : 'backward',
      selectedText:text.slice(Math.min(anchor,focus),Math.max(anchor,focus))};
  }
  const account = elements(document, 'button[aria-label="Open profile menu"],button[aria-label="打开个人资料菜单"],button[data-testid="accounts-profile-button"],button[data-testid="user-menu-button"]').filter(n=>!n.closest('article,[data-message-author-role],form'));
  const label = n => (n.getAttribute('aria-label') || n.innerText || '').trim();
  const signedOut = elements(document,'button,a[href="/auth/login"],a[href="/auth/signup"]').some(n=>/^(Log in|Sign in|Sign up|登录|注册)$/i.test(label(n)));
  const btn = account.length === 1 ? account[0] : null;
  // Read only the public authStatus enum in the first-party bootstrap. Never serialize
  // its payload, return account identifiers, query a session API, or read storage.
  const nodes = document.querySelectorAll('script#client-bootstrap[type="application/json"]');
  let bootstrapStatus = 'unavailable';
  if (nodes.length === 1) {
    try {
      const status = JSON.parse(nodes[0].textContent).authStatus;
      if (status === 'logged_in' || status === 'logged_out') bootstrapStatus = status;
    } catch {}
  }
  const nav = elements(document, 'nav[aria-label="Account"],nav[aria-label="账户"]');
  const accountAction = nav.length === 1 && elements(nav[0],'a,button,[role=menuitem]').some(n=>
    !n.matches(':disabled,[aria-disabled=true]') && /^(Log out|Sign out|Manage account|Manage subscription|退出登录|管理账户|管理订阅)$/i.test(label(n)));
  const explicitPlan = btn && elements(btn,'[aria-label="Current plan"],[aria-label="当前套餐"]').some(n=>/^(?:ChatGPT\s+)?(?:Plus|Pro|Business|Enterprise)$/i.test(n.innerText.trim()));
  const signedIn = !!btn && !signedOut && bootstrapStatus !== 'logged_out' && (bootstrapStatus === 'logged_in' || accountAction || !!explicitPlan);
  const registry = globalThis.__riftletIndependentFileInput20261104;
  const me = editor && registry?.root === document.documentElement ? registry : null;
  const gen = me?.witnessGeneration;
  const own = !!gen && gen.editor === editor && gen.form?.isConnected && gen.form.contains(editor);
  const retained = [];
  if (me?.operations instanceof Map) for (const [id,op] of me.operations) {
    const b = op.binding, t = b?.target;
    if (b?.editor !== editor || !editor.isConnected || !b.form?.isConnected || !b.form.contains(editor) ||
        !t || op.identity?.operationID !== id || op.identity?.target?.documentID !== me.documentID ||
        op.identity.target.draftGeneration !== t.draftGeneration || op.identity.target.composerID !== t.composerID ||
        t.documentID !== me.documentID || me.nodeIDs.get(editor) + ':' + me.nodeIDs.get(b.form) !== t.composerID ||
        typeof t.draftGeneration !== 'string' || op.inputCount !== 1) continue;
    retained.push({operationID:id,documentID:t.documentID,composerID:t.composerID,draftEpoch:t.draftGeneration});
  }
  const active = own ? {documentID:me.documentID,composerID:me.nodeIDs.get(editor)+':'+me.nodeIDs.get(gen.form),draftEpoch:gen.id} : null;
  const original = active || retained.at(-1);
  const composerID = original?.composerID ?? null;
  const prepared = [];
  if (own && me.preparedTargets instanceof Map) for (const [key,binding] of me.preparedTargets) {
    const t = binding.target;
    if (binding.editor === editor && binding.form === gen.form && t?.documentID === me.documentID &&
        t.composerID === composerID && t.draftGeneration === gen.id && key === t.clickBindingID &&
        !binding.enrolled && !binding.expired?.() && binding.prepared && gen.form.contains(editor)) {
      prepared.push({target:{applicationID:t.applicationID,sessionID:t.sessionID,windowID:t.windowID,tabID:t.tabID,clickBindingID:key}});
    }
  }
  const images = form ? elements(form,'img[alt]').filter(n=>/^riftlet-[0-9a-f-]{36}\.(png|webp)$/i.test(n.alt)) : [];
  const uploadEntry = !!form && ([...form.querySelectorAll('input[type=file]')].some(n=>!n.disabled) ||
     elements(form,'button').some(n=>n.id === 'composer-plus-btn' || /^(Attach|Add files|添加文件)/i.test(label(n))));
  const watcherKey = '__riftletDraftQA_' + QA_ORIGINAL_DOCUMENT_NONCE;
  const watcher = Object.getOwnPropertyDescriptor(globalThis,watcherKey)?.value;
  const observationState = {visible:document.visibilityState === 'visible', focused:document.hasFocus(),
    mounted:!!watcher, stateReadable:typeof watcher?.state === 'function'};
  return JSON.stringify({observationState,entryID:navigation.currentEntry.id,timeOrigin:performance.timeOrigin,editor:!!editor,
    uploadEntry,signedIn,authSignals:{bootstrapStatus,accountButtons:account.length,hasAccountAction:accountAction,explicitPlan:!!explicitPlan,signedOut},
    activeEditor:!!editor && document.activeElement === editor,text,selection,
    documentID:original?.documentID ?? null, composerID,draftEpoch:original?.draftEpoch ?? null,
    registryState:{present:!!registry,originalRoot:!!me,hasGeneration:!!gen,activeGenerationOwnsEditor:own,
        retainedOperationCount:me?.operations instanceof Map ? me.operations.size : null,originalEditorTagged:!!me?.nodeIDs?.has(editor),
        preparedCount:me?.preparedTargets instanceof Map ? me.preparedTargets.size : null},epochSource:active ? 'preparedGeneration' : original ? 'retainedInputBinding' : null,retainedOriginals:retained,pending:prepared,
    cards:images.map(n=>({file:n.alt,width:n.naturalWidth,height:n.naturalHeight,complete:n.complete}))});
})()
"""#
