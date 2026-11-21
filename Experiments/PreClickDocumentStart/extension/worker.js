importScripts("scope.js");
const ids = new Map();
let native;
const uuid = value => typeof value === "string" && /^[a-f0-9-]{36}$/i.test(value);
// Browser-issued opaque document IDs use 32 hex characters on the tested builds.
const documentID = value => typeof value === "string" && /^[a-f0-9-]{32,36}$/i.test(value);
const targetKeys = ["windowId","tabId","documentId","ticket"];
const same = (a,b) => a && b && targetKeys.every(k=>a[k]===b[k]);
function sendHost(msg) { if (native) native.postMessage(msg); }
async function selected(id) {
  const [t,w] = await Promise.all([chrome.tabs.get(id.tabId),chrome.windows.get(id.windowId)]);
  return t.windowId === id.windowId && t.active && w.focused;
}
function retire(record) {
  if (record.key) sendHost({kind:"revoke",key:record.key});
  record.key=null;record.ack=null;
}
function nativePort() {
  if (native) return native;
  const link = chrome.runtime.connectNative("com.riftlet.preclick_lab");
  native=link;
  link.onDisconnect.addListener(()=>{
    const failure=chrome.runtime.lastError?.message;
    if (failure) console.info("RIFTLET_HELPER_NATIVE_DISCONNECTED", failure);
    for (const record of ids.values()) {
      record.port.postMessage({kind:"diagnostic",stage:failure?.includes("not found")?"native_host_not_found":"native_host_disconnected"});
      record.port.disconnect();
    }
    ids.clear(); native=null;
  });
  link.onMessage.addListener(async msg=>{
    const record = ids.get(msg.key?.documentId);
    if (msg.kind === "ack" && same(record?.key,msg.key)) {
      record.ack=msg.ack;
      record.port.postMessage({kind:"ack",ticket:msg.key.ticket,ack:msg.ack});
    }
    if (msg.kind !== "commit") return;
    let state="REFUSED";
    try {
      if (record && same(record.key,msg.key) && record.ack===msg.ack && await selected(msg.key) &&
          same(record.key,msg.key) && record.ack===msg.ack) {
        // Target the original browser-issued document ID. Activity/name/URL alone never select a receiver.
        state="UNKNOWN";
        const reply = await chrome.tabs.sendMessage(msg.key.tabId,{kind:"commit",ticket:msg.key.ticket,
          ack:msg.ack,op:msg.op,png:msg.png},{documentId:msg.key.documentId,frameId:0});
        if (["INPUT_RETURNED","REFUSED"].includes(reply?.state)) state=reply.state;
      }
    } catch { /* The first possible delivery owns the uncertainty. */ }
    // One test asks the host to exercise a lost result. The host alone
    // controls this fault, and never issues a second commit.
    if (native===link) sendHost({kind:"result",op:msg.op,key:msg.key,state});
  });
  return link;
}
chrome.runtime.onConnect.addListener(port=>{
  const s=port.sender;
  if (port.name!=="riftlet-preclick" || s.id!==chrome.runtime.id || !s.tab || s.frameId!==0 ||
      !documentID(s.documentId) || s.url!==globalThis.riftletLabURL || s.origin!==new URL(s.url).origin ||
      s.documentLifecycle!=="active" || ids.has(s.documentId)) {
    console.info("RIFTLET_HELPER_REFUSED_SENDER",Boolean(s.tab),s.frameId,Boolean(s.documentId),
      s.url===globalThis.riftletLabURL,s.documentLifecycle,"id",s.id===chrome.runtime.id,
      "docLength",s.documentId?.length,"validDocument",documentID(s.documentId),"origin",s.origin===new URL(s.url).origin,
      "port",port.name,"duplicate",ids.has(s.documentId));
    port.disconnect();return;
  }
  port.postMessage({kind:"diagnostic",stage:"sender_validated"});
  nativePort();
  const record={port,key:null,ack:null};
  ids.set(s.documentId,record);
  port.onDisconnect.addListener(()=>{ if(ids.get(s.documentId)===record) {retire(record);ids.delete(s.documentId);} });
  port.onMessage.addListener(async msg=>{
    if (!uuid(msg.ticket) || ids.get(s.documentId)!==record) return;
    if (msg.kind==="offer") {
      const key={windowId:s.tab.windowId,tabId:s.tab.id,documentId:s.documentId,ticket:msg.ticket};
      retire(record);
      record.key=key;
      try { if (await selected(key) && record.key===key) sendHost({kind:"offer",key}); }
      catch { if(record.key===key) retire(record); }
    }
    if (msg.kind==="revoke" && record.key?.ticket===msg.ticket) retire(record);
    if (msg.kind==="ready" && record.key?.ticket===msg.ticket && record.ack===msg.ack) {
      sendHost({kind:"ready",key:record.key,ack:msg.ack});
    }
  });
});
function refresh(changed) {
  for(const record of ids.values()) {
    if (!changed(record.port.sender.tab)) continue;
    retire(record);
    record.port.postMessage({kind:"retire"});
    record.port.postMessage({kind:"refresh"});
  }
}
chrome.tabs.onActivated.addListener(({windowId})=>refresh(t=>t.windowId===windowId));
chrome.tabs.onDetached.addListener(id=>refresh(t=>t.id===id));
chrome.windows.onFocusChanged.addListener(()=>refresh(()=>true));
