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
  const me = form && editor && globalThis.__riftletIndependentFileInput20261104;
  const gen = me?.root === document.documentElement ? me.witnessGeneration : null;
  const own = !!gen && gen.editor === editor && gen.form.contains(editor) && gen.form.isConnected;
  const nodeIDs = own && me.nodeIDs, eid = nodeIDs && nodeIDs.get(editor), fid = nodeIDs && nodeIDs.get(gen.form);
  const composerID = eid && fid ? eid + ':' + fid : null;
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
  return JSON.stringify({entryID:navigation.currentEntry.id,timeOrigin:performance.timeOrigin,editor:!!editor,
    uploadEntry,signedIn,authSignals:{bootstrapStatus,accountButtons:account.length,hasAccountAction:accountAction,explicitPlan:!!explicitPlan,signedOut},
    activeEditor:!!editor && document.activeElement === editor,text,selection,
    documentID:own ? me.documentID : null, composerID,draftEpoch:own ? gen.id : null,pending:prepared,
    cards:images.map(n=>({file:n.alt,width:n.naturalWidth,height:n.naturalHeight,complete:n.complete}))});
})()
"""#
