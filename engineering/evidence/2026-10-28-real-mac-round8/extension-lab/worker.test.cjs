const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const crypto = require('node:crypto');
const path = require('node:path');
const code = fs.readFileSync(path.join(__dirname,'extension/worker.js'),'utf8');
function event() { const handlers=[]; return {addListener:f=>handlers.push(f),emit:(...args)=>handlers.forEach(f=>f(...args))}; }
function fixture() {
  const writes=[], native={onMessage:event(),onDisconnect:event(),disconnect(){this.onDisconnect.emit();}};
  native.postMessage=m=>{writes.push(m);queueMicrotask(()=>native.onMessage.emit(m.kind==='hello'
    ?{v:1,kind:'helloAck',hostEpoch:crypto.randomUUID(),channel:m.channel,inputAuthority:false}
    :{v:1,kind:m.kind+'Ack',sequence:m.sequence,candidatePresent:m.kind==='publish',publishedNS:'100',inputAuthority:false}));};
  const chrome={runtime:{id:'a'.repeat(32),onConnect:event(),connectNative:()=>native},
    tabs:{onActivated:event(),get:async()=>({active:true,windowId:2})},
    windows:{onFocusChanged:event(),get:async()=>({focused:true})},webNavigation:{onCommitted:event()}};
  const context=vm.createContext({chrome,crypto:crypto.webcrypto,URL,setTimeout,clearTimeout});vm.runInContext(code,context);
  function source(patch={}) {
    const p={name:'riftlet-synthetic-cold-v1',sender:{id:chrome.runtime.id,documentId:crypto.randomBytes(16).toString("hex").toUpperCase(),
      frameId:0,documentLifecycle:'active',tab:{id:1,windowId:2},url:'http://127.0.0.1:1234/riftlet-synthetic-cold-lab/one',...patch},
      onMessage:event(),onDisconnect:event(),disconnected:false,disconnect(){this.disconnected=true;this.onDisconnect.emit();}};
    chrome.runtime.onConnect.emit(p);return p;
  }
  return {chrome,native,writes,source,drain:()=>vm.runInContext('serial',context),snapshot:()=>context.labSnapshot()};
}
test('browser-owned sender identity is used, phase signal conveys no draft or input authority',async()=>{
  const f=fixture(),p=f.source();p.onMessage.emit({phase:'document_start',nonce:crypto.randomUUID()});await f.drain();
  assert.deepEqual(f.writes.map(x=>x.kind),['hello','invalidate','publish']);
  assert.equal(f.writes[2].documentID,p.sender.documentId);assert.equal(f.writes[2].frameID,0);
  assert.equal(f.snapshot().inputAuthority,false);
});
test('wrong origin, subframe, inactive lifecycle or unknown document refused before native connection',()=>{
  for(const patch of [{url:'https://chatgpt.com/'},{frameId:1},{documentLifecycle:'prerender'},{documentId:undefined}]) {
    const f=fixture();assert.equal(f.source(patch).disconnected,true);assert.equal(f.writes.length,0);
  }
});
test('payload cannot replace browser identity or inject a click timestamp',async()=>{
  const f=fixture(),p=f.source();p.onMessage.emit({phase:'document_start',nonce:crypto.randomUUID(),documentID:crypto.randomUUID()});await f.drain();
  assert.equal(p.disconnected,true);assert.equal(f.writes.length,0);
});
test('activation during asynchronous metadata query invalidates captured view before publication',async()=>{
  const f=fixture();let resolve,entered;
  const started=new Promise(r=>entered=r);
  f.chrome.tabs.get=()=>new Promise(r=>{resolve=r;entered();});
  const p=f.source();p.onMessage.emit({phase:'document_start',nonce:crypto.randomUUID()});await started;
  f.chrome.tabs.onActivated.emit({tabId:99});resolve({active:true,windowId:2});await f.drain();
  assert.equal(f.writes.filter(x=>x.kind==='publish').length,0);
});
test('native disconnect cannot replay old content through a replacement channel',async()=>{
  const f=fixture(),p=f.source(),nonce=crypto.randomUUID();p.onMessage.emit({phase:'document_start',nonce});await f.drain();
  f.native.disconnect();p.onMessage.emit({phase:'dom_ready',nonce});await f.drain();
  assert.equal(f.writes.filter(x=>x.kind==='hello').length,1);assert.equal(f.snapshot().closed,true);
});

test('late first-document ACK does not count as a second-document publication',async()=>{
  const {hasNewDocumentPublication}=await import('./publication-check.mjs');
  const original=new Set(['original-document']);
  assert.equal(hasNewDocumentPublication({events:[
    {event:'publishAck',documentID:'original-document',phase:'document_start'},
    {event:'publishAck',documentID:'original-document',phase:'dom_ready'},
    {event:'publishAck',documentID:'original-document',phase:'visibility_change'}]},original),false);
  assert.equal(hasNewDocumentPublication({events:[{event:'publishAck'}]},original),false);
  assert.equal(hasNewDocumentPublication({events:[{event:'publishAck',documentID:'different-document'}]},original),true);
});

test('browser 32-hex document token is distinct from UUID nonce and malformed IDs refuse',()=>{
  for (const documentId of [crypto.randomUUID(),'0'.repeat(32),'a'.repeat(31),'g'.repeat(32)]) {
    const f=fixture(),p=f.source({documentId});assert.equal(p.disconnected,true);
    assert.equal(f.snapshot().events.find(e=>e.event==='sourceRefused').reason,'documentID');
  }
});
