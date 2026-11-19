// Read-only inspector. WKWebView uses a client-owned content world. Edge Apple
// Events returns advisory, page-world diagnostics without isolation guarantees.
// Page nodes, text, URLs and selections never leave this document. This program
// registers no transport and does not click, focus, paste, submit or pick a file.
function inspectConversationSurface(profile, expectedAddress, service, action, id) {
  'use strict';
  const reply = (status, fields = {}) => JSON.stringify({status, ...fields});
  if (window !== window.top) return reply('unavailable');
  const key = Symbol.for('Riftlet.conversationSurface.inspection.v1');
  const bindings = globalThis[key] || (globalThis[key] = new Map());
  const previous = bindings.get(id);
  if (action === 'release') {
    if (!previous || previous.service !== service || previous.expectedAddress !== expectedAddress) return reply('expired');
    previous.dispose();
    return reply('released');
  }
  if (action === 'revalidate' && !previous) return reply('expired');
  if (previous && (previous.service !== service || previous.expectedAddress !== expectedAddress)) return reply('changed');
  const url = new URL(location.href);
  const supported = url.href === new URL(expectedAddress).href && url.protocol === 'https:' && !url.username && !url.password && !url.port
    && profile.hosts.includes(url.hostname) && new RegExp(profile.route).test(url.pathname);
  // currententrychange observes a same-document A -> B -> A even when the
  // application keeps the editor mounted. An unsupported engine cannot bind.
  const navigation = window.navigation;
  const invalid = () => {
    if (previous) previous.changed = true;
    return reply(previous ? 'changed' : 'unavailable');
  };
  if (!supported) return previous ? invalid() : reply('unsupportedRoute');
  if (!navigation?.currentEntry) return invalid();
  const visible = node => {
    if (node.closest('[hidden],[inert],[aria-hidden="true"],[aria-disabled="true"]')) return false;
    const style = getComputedStyle(node);
    return style.visibility === 'visible' && node.getClientRects().length > 0;
  };
  const editors = [...document.querySelectorAll(profile.editor)].filter(node =>
    visible(node) && !node.matches(':disabled,[readonly],[aria-readonly="true"]')
    && (node.isContentEditable || node instanceof HTMLTextAreaElement)
    && !node.closest('nav,aside,header,article,[role="search"],[role="dialog"],[data-message-author-role]'));
  if (editors.length !== 1) {
    if (previous) return invalid();
    return reply(editors.length ? 'ambiguous' : 'unavailable');
  }
  const editor = editors[0];
  const container = editor.closest(profile.container);
  if (!container) return invalid();
  const entries = [...container.querySelectorAll(profile.entry)].filter(node =>
    visible(node) && !node.matches(':disabled,[type="submit"]') && node.closest(profile.container) === container);
  const attachments = [...container.querySelectorAll(profile.attachment)]
    .filter(node => node.closest(profile.container) === container);
  const entry = entries.length === 1 ? 'button' : entries.length ? 'ambiguous' : 'missing';
  const fields = {entry, attachmentCount: attachments.length};
  const text = editor instanceof HTMLTextAreaElement ? editor.value : editor.textContent;
  function selectionState() {
    if (editor instanceof HTMLTextAreaElement) {
      return [editor.selectionStart, editor.selectionEnd, editor.selectionDirection];
    }
    const selection = document.getSelection();
    if (selection && (editor.contains(selection.anchorNode) || editor.contains(selection.focusNode))) {
      return [selection.anchorNode, selection.anchorOffset, selection.focusNode, selection.focusOffset];
    }
    return [];
  }
  const selection = selectionState();
  const equal = (a, b) => a.length === b.length && a.every((value, i) => value === b[i]);
  function affectsDraft(record, binding) {
    // Reactivating a detached identical node also invalidates the snapshot.
    if ([...record.removedNodes].some(node => node.contains(binding.container)
        || node.contains(binding.editor) || binding.entries.some(entry => node.contains(entry)))) return true;
    if (binding.editor.contains(record.target)) return true;
    return binding.entries.some(node => node.contains(record.target))
      || binding.attachments.some(node => node.contains(record.target)
      || [...record.removedNodes].some(removed => removed.contains(node)));
  }
  if (previous) {
    if (previous.observer.takeRecords().some(record => affectsDraft(record, previous))) previous.changed = true;
    if (previous.changed || previous.url !== url.href || previous.navigationID !== navigation.currentEntry.id
        || previous.root !== document.documentElement || previous.container !== container || previous.editor !== editor
        || previous.text !== text || !equal(previous.selection, selection)
        || !equal(previous.attachments, attachments) || !equal(previous.entries, entries)) return invalid();
    return reply(action === 'bind' ? 'bound' : 'unchanged', fields);
  }
  if (action !== 'bind') return reply('expired');
  if (bindings.size >= 8 || text.length > 131072 || attachments.length > 128) return reply('capacity');
  // A document-local binding retains sensitive draft data only for its short
  // validation window. It is disposed on explicit release or expiry.
  const binding = {service, expectedAddress, url: url.href, navigationID: navigation.currentEntry.id, root: document.documentElement,
    container, editor, text, selection, attachments, entries, changed: false};
  const markChanged = () => { binding.changed = true; };
  binding.observer = new MutationObserver(records => {
    if (records.some(record => affectsDraft(record, binding))) markChanged();
  });
  // One short-lived binding owns its handlers. Expiry only frees memory.
  binding.observer.observe(document, {subtree: true, childList: true, characterData: true, attributes: true});
  navigation.addEventListener('currententrychange', markChanged);
  window.addEventListener('pagehide', markChanged);
  editor.addEventListener('input', markChanged);
  const expiry = setTimeout(() => binding.dispose(), 30000);
  binding.dispose = () => {
    clearTimeout(expiry);
    navigation.removeEventListener('currententrychange', markChanged);
    window.removeEventListener('pagehide', markChanged);
    editor.removeEventListener('input', markChanged);
    binding.observer.disconnect();
    bindings.delete(id);
  };
  bindings.set(id, binding);
  return reply('bound', fields);
}
