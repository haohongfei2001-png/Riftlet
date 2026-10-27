'use strict';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
// Chromium ExtensionApiFrameIdMap::DocumentId is UnguessableToken, 32 hex.
// It is distinct from the UUID format used by this lab's nonces and epochs.
const DOCUMENT_ID = /^(?!0{32}$)[0-9a-f]{32}$/i;
const channel = crypto.randomUUID();
let viewEpoch = crypto.randomUUID(), hostEpoch = null, sequence = 0, port = null, waiter = null;
let closed = false, serial = Promise.resolve(), events = [], sourcePorts = 0;
function note(event, fields = {}) {
  if (events.length < 100) events.push({event, ...fields});
}
globalThis.labSnapshot = () => ({channelPresent: !!hostEpoch, closed, inputAuthority: false, events: [...events]});
function request(message) {
  return new Promise((resolve, reject) => {
    if (closed || waiter) return reject(new Error('closed-or-concurrent'));
    const timer = setTimeout(() => { waiter = null; closed = true; port?.disconnect(); reject(new Error('timeout')); }, 3000);
    waiter = {resolve: m => { clearTimeout(timer); waiter = null; resolve(m); },
              reject: () => { clearTimeout(timer); waiter = null; reject(new Error('disconnected')); }};
    port.postMessage(message);
  });
}
async function connect() {
  if (hostEpoch) return;
  if (closed) throw new Error('closed');
  port = chrome.runtime.connectNative('org.riftlet.synthetic_cold_lab_r8');
  port.onMessage.addListener(m => {
    if (m?.inputAuthority !== false || m?.v !== 1) { closed = true; port.disconnect(); return; }
    waiter?.resolve(m);
  });
  port.onDisconnect.addListener(() => {
    void chrome.runtime.lastError; closed = true; hostEpoch = null; waiter?.reject(); note('nativeDisconnected');
  });
  const ack = await request({v: 1, kind: 'hello', channel});
  if (ack.kind !== 'helloAck' || ack.channel !== channel || !UUID.test(ack.hostEpoch)) throw new Error('bad-hello');
  hostEpoch = ack.hostEpoch; note('nativeConnected');
}
async function send(kind, view, fields = {}) {
  if (++sequence > 120) { closed = true; port.disconnect(); throw new Error('budget'); }
  const ack = await request({v: 1, kind, channel, hostEpoch, sequence, viewEpoch: view, ...fields});
  if (ack.kind !== kind + 'Ack' || ack.sequence !== sequence) throw new Error('bad-ack');
  note(ack.kind, {sequence, candidatePresent: ack.candidatePresent, publishedNS: ack.publishedNS,
    ...(kind === 'publish' ? {documentID: fields.documentID, phase: fields.phase} : {})});
}
function enqueue(work) {
  serial = serial.then(work).catch(() => { note('refused'); closed = true; port?.disconnect(); });
}
function invalidate() {
  const view = viewEpoch = crypto.randomUUID();
  note('sourceInvalidated');
  enqueue(async () => { if (hostEpoch && !closed) await send('invalidate', view); });
}
chrome.tabs.onActivated.addListener(invalidate);
chrome.windows.onFocusChanged.addListener(invalidate);
chrome.webNavigation.onCommitted.addListener(details => { if (details.frameId === 0) invalidate(); });
chrome.runtime.onConnect.addListener(source => {
  const sender = source.sender;
  let parsed;
  const reject = reason => {
    note('sourceRefused', {reason,
      documentIDLength: typeof sender?.documentId === 'string' ? sender.documentId.length : null,
      documentID32Hex: DOCUMENT_ID.test(sender?.documentId || ''),
      documentUUIDLowercase: UUID.test(sender?.documentId || ''),
      documentUUIDCaseInsensitive: /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(sender?.documentId || ''),
      lifecycleActive: sender?.documentLifecycle === 'active',
      lifecyclePresent: typeof sender?.documentLifecycle === 'string'});
    source.disconnect();
  };
  note('sourceConnection');
  try { parsed = new URL(sender?.url); } catch { reject('invalidURL'); return; }
  if (source.name !== 'riftlet-synthetic-cold-v1') { reject('portName'); return; }
  if (sender?.id !== chrome.runtime.id) { reject('extensionID'); return; }
  if (sender.frameId !== 0) { reject('frame'); return; }
  if (!DOCUMENT_ID.test(sender.documentId || '')) { reject('documentID'); return; }
  if (sender.documentLifecycle !== 'active') { reject('lifecycle'); return; }
  if (!Number.isInteger(sender.tab?.id) || !Number.isInteger(sender.tab?.windowId)) { reject('tabWindow'); return; }
  if (parsed.protocol !== 'http:' || parsed.hostname !== '127.0.0.1'
      || !parsed.pathname.startsWith('/riftlet-synthetic-cold-lab/')) { reject('scope'); return; }
  if (sourcePorts >= 4) { reject('capacity'); return; }
  sourcePorts++;
  let nonce = null, count = 0;
  source.onDisconnect.addListener(() => { sourcePorts--; invalidate(); });
  source.onMessage.addListener(message => {
    if (closed || ++count > 8 || !message || Object.keys(message).sort().join(',') !== 'nonce,phase'
        || !UUID.test(message.nonce) || !['document_start','dom_ready','visibility_change'].includes(message.phase)
        || (nonce && nonce !== message.nonce)) { source.disconnect(); return; }
    nonce = message.nonce;
    const view = viewEpoch;
    note('contentSignal', {phase: message.phase, documentID: sender.documentId, frameID: sender.frameId});
    enqueue(async () => {
      await connect();
      const tab = await chrome.tabs.get(sender.tab.id), win = await chrome.windows.get(sender.tab.windowId);
      if (view !== viewEpoch || !tab.active || !win.focused || tab.windowId !== sender.tab.windowId) {
        note('staleOrInactive'); return;
      }
      // Every candidate has a fresh acknowledged barrier; source-supplied IDs are never used.
      const barrier = viewEpoch = crypto.randomUUID();
      await send('invalidate', barrier);
      if (barrier !== viewEpoch) return;
      await send('publish', barrier, {documentID: sender.documentId, frameID: sender.frameId,
        tabID: sender.tab.id, windowID: sender.tab.windowId, documentNonce: nonce, phase: message.phase});
    });
  });
});
