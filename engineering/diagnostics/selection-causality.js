// Test-only read-only DOM observer. No text, HTML, image source, filename, URL,
// input setter, focus(), Range mutation or transfer hook. Never packaged in App.
(() => {
  'use strict';
  const key = '__riftletSelectionCausalityV1';
  if (globalThis[key]) return JSON.stringify({installed: false, reason: 'already-installed'});
  const editors = [...document.querySelectorAll('[contenteditable=true]')].filter(e => e.getClientRects().length);
  if (editors.length !== 1) return JSON.stringify({installed: false, reason: 'editor-not-unique'});
  const editor = editors[0], form = editor.closest('form');
  if (!form) return JSON.stringify({installed: false, reason: 'form-missing'});
  const ids = new WeakMap(); let id = 0, sequence = 0, userEpoch = 0, stopped = false, droppedSnapshots = 0;
  const events = [], subscriptions = [], MAX = 512;
  const node = n => {
    if (!n) return null;
    if (!ids.has(n)) ids.set(n, ++id);
    return {id: ids.get(n), type: n.nodeType, tag: n.nodeType === 1 ? n.tagName : null,
      connected: n.isConnected, inEditor: n === editor || editor.contains(n), inForm: n === form || form.contains(n)};
  };
  const snapshot = (phase, extra = {}) => {
    if (stopped) return null;
    if (events.length >= MAX) { droppedSnapshots++; return null; }
    const s = getSelection();
    const value = {sequence: ++sequence, nowMS: performance.now(), phase, userEpoch,
      documentFocused: document.hasFocus(), visible: document.visibilityState,
      active: node(document.activeElement), editor: node(editor), form: node(form),
      selection: {rangeCount: s?.rangeCount ?? 0, collapsed: s?.isCollapsed ?? null,
        anchor: node(s?.anchorNode), focus: node(s?.focusNode),
        anchorOffset: s?.anchorOffset ?? null, focusOffset: s?.focusOffset ?? null},
      attachmentCount: form.querySelectorAll('img').length,
      attachmentsTruncated: form.querySelectorAll('img').length > 40,
      attachments: [...form.querySelectorAll('img')].slice(0, 40).map(i => ({node: node(i), loaded: i.complete,
        width: i.naturalWidth, height: i.naturalHeight})), ...extra};
    events.push(value); return value;
  };
  const listen = (target, type, capture, fn) => {
    target.addEventListener(type, fn, capture); subscriptions.push(() => target.removeEventListener(type, fn, capture));
  };
  for (const type of ['pointerdown', 'pointerup', 'keydown', 'compositionstart', 'compositionend']) {
    listen(document, type, true, e => { if (e.isTrusted) userEpoch++;
      snapshot(type, {trusted: e.isTrusted, target: node(e.target), eventMS: e.timeStamp}); });
  }
  for (const type of ['selectionchange', 'focusin', 'focusout', 'visibilitychange']) {
    listen(document, type, true, e => snapshot(type, {trusted: e.isTrusted, target: node(e.target), eventMS: e.timeStamp}));
  }
  // Capture on window also receives element focus/blur. Never label those
  // as native window deactivation or infer an actor from isTrusted.
  for (const type of ['focus', 'blur']) listen(window, type, true, e => snapshot(
    (e.target === window ? 'window-' : 'element-') + type,
    {trusted: e.isTrusted, eventTargetScope: e.target === window ? 'window' : 'element',
      target: e.target === window ? null : node(e.target), eventMS: e.timeStamp}));
  for (const type of ['input', 'change']) {
    for (const capture of [true, false]) listen(document, type, capture, e => {
      if (!form.contains(e.target)) return;
      snapshot(type + (capture ? '-capture' : '-bubble'), {target: node(e.target), trusted: e.isTrusted,
        fileCount: e.target.type === 'file' ? e.target.files.length : null, eventMS: e.timeStamp});
      if (capture) {
        queueMicrotask(() => snapshot(type + '-microtask'));
        requestAnimationFrame(() => snapshot(type + '-frame'));
        setTimeout(() => snapshot(type + '-task'), 0);
      }
    });
  }
  const observer = new MutationObserver(records => snapshot('mutation', {mutations: records.slice(0, 16).map(m => ({
    type: m.type, target: node(m.target), added: [...m.addedNodes].slice(0, 8).map(node),
    removed: [...m.removedNodes].slice(0, 8).map(node), addedCount: m.addedNodes.length, removedCount: m.removedNodes.length}))}));
  observer.observe(form, {subtree: true, childList: true, characterData: true});
  const stop = () => { if (!stopped) snapshot('stop'); stopped = true; observer.disconnect(); subscriptions.forEach(f => f()); clearTimeout(timer); };
  const timer = setTimeout(stop, 120000);
  Object.defineProperty(globalThis, key, {configurable: true, value: {
    snapshot, read: () => ({version: 1, limit: MAX, stopped, capped: events.length >= MAX, droppedSnapshots, events: events.slice()}),
    dispose: () => { stop(); delete globalThis[key]; }
  }});
  snapshot('installed');
  return JSON.stringify({installed: true, limit: MAX, expiresMS: 120000, textCollected: false});
})()
