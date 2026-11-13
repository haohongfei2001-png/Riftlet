// Reviewed page command for a disposable, loopback-only fixture. No selector or
// receipt in this file describes any commercial service.
function edgeFixtureCommand(action, targetURL, operation, bytes) {
  if (location.href !== targetURL || location.protocol !== 'http:' || location.hostname !== '127.0.0.1' ||
      !/^\/draft\/[0-9a-f]{32}$/.test(location.pathname) || !/^[0-9a-f]{32}$/.test(operation)) return 'refused';
  const forms = document.querySelectorAll('form[data-riftlet-fixture="edge-v1"]');
  if (forms.length !== 1) return 'refused';
  const form = forms[0];
  function unique(selector) {
    const nodes = form.querySelectorAll(selector);
    return nodes.length === 1 ? nodes[0] : null;
  }
  const editor = unique('textarea[name=draft]');
  const picker = unique('input[name=attachment][type=file]');
  const attachments = unique('[data-attachments]');
  if (!editor || !picker || !attachments || !picker.isConnected || picker.disabled || editor.readOnly || editor.disabled)
    return 'refused';
  const records = globalThis.__riftletEdgeLocalFixtureOperations ||= new Map();
  if (action === 'capture') {
    if (records.has(operation)) return 'refused';
    records.set(operation, {form, editor, picker, attachments, text: editor.value,
      start: editor.selectionStart, end: editor.selectionEnd, direction: editor.selectionDirection,
      prior: Array.from(attachments.children), consumed: false});
    return 'bound';
  }
  const lease = records.get(operation);
  if (!lease || lease.form !== form || lease.editor !== editor || lease.picker !== picker ||
      lease.attachments !== attachments || editor.value !== lease.text ||
      editor.selectionStart !== lease.start || editor.selectionEnd !== lease.end ||
      editor.selectionDirection !== lease.direction || !lease.prior.every((node,i) => attachments.children[i] === node))
    return 'refused';
  if (action === 'observe') {
    const matches = Array.from(attachments.children).filter(el => el.dataset.operation === operation);
    if (matches.length !== 1) return 'unknown';
    if (matches[0].dataset.state === 'complete') return 'attached';
    return matches[0].dataset.state === 'rejected' ? 'rejected' : 'unknown';
  }
  if (action !== 'commit' || lease.consumed || attachments.children.length !== lease.prior.length ||
      typeof bytes !== 'string' || bytes.length > 1024) return 'refused';
  const data = Uint8Array.from(atob(bytes), c => c.charCodeAt(0));
  const transfer = new DataTransfer();
  transfer.items.add(new File([data], operation + '.png', {type: 'image/png'}));
  lease.consumed = true; // The first setter entry consumes this operation even when an exception or reply loss follows.
  picker.files = transfer.files;
  picker.dispatchEvent(new Event('change', {bubbles: true}));
  return 'input-entered';
}
