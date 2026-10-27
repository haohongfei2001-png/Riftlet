// Synthetic loopback only. Reads no text, form, cookie, storage or attachment.
(() => {
  if (location.hostname !== '127.0.0.1' || !location.pathname.startsWith('/riftlet-synthetic-cold-lab/')) return;
  const port = chrome.runtime.connect({name: 'riftlet-synthetic-cold-v1'});
  const nonce = crypto.randomUUID();
  let stopped = false;
  port.onDisconnect.addListener(() => { stopped = true; });
  function push(phase) { if (!stopped) port.postMessage({phase, nonce}); }
  push('document_start');
  document.addEventListener('DOMContentLoaded', () => push('dom_ready'), {once: true});
  document.addEventListener('visibilitychange', () => push('visibility_change'));
  addEventListener('pagehide', () => { stopped = true; port.disconnect(); }, {once: true});
})();
