/* Riftlet isolated-page diagnostic. Run once in this test tab's DevTools Console.
   No uploads are initiated here. No private endpoint is invoked. No headers,
   cookies, message text, raw URLs or response bodies are retained in the log.
   Only exact synthetic filenames / hashes and their observed request linkage
   can be faulted. One native abort per case; no retry or fake success response. */
(() => {
 'use strict';
 const session=__EXPECTED_LAB_SESSION__; // explicit isolated test configuration required
 const panel=document.getElementById('riftlet-exception-panel'),sink=document.getElementById('riftlet-network-receipt');
 if(!panel||panel.dataset.session!==session||!sink||sink.dataset.session!==session)throw Error('WRONG_TAB: expected the labelled Riftlet exception page');
 if(globalThis.__riftletNativeFault)throw Error('ALREADY_INSTALLED: do not run twice');
 const cfg=JSON.parse(panel.dataset.config),nativeFetch=globalThis.fetch,nativeOpen=XMLHttpRequest.prototype.open,nativeSend=XMLHttpRequest.prototype.send;
 const events=[],pending=new Set(),xhrMeta=new WeakMap(),used=new Set();let active=null,seq=0,serial=0,closed=false;
 function flush(){sink.textContent=JSON.stringify({state:closed?'STOPPED':active?'CASE_ARMED':'BRIDGE_ARMED',sessionId:session,mainWorldBridge:true,active:active?{label:active.f.label,mode:active.mode,faultInjected:active.faultInjected,ui100:active.ui100,deadlineReached:active.deadlineReached}:null,events:events.slice(),requestsInitiatedByBridge:0});}
 function log(event,data={}){if(events.length>=500){closed=true;restore();return;}events.push({sequence:++seq,monotonicMs:performance.now(),event,operationId:active?.f.operationId??null,...data});flush();}
 const containsExact=(obj,value,depth=0)=>depth<5&&(obj===value||Array.isArray(obj)&&obj.some(x=>containsExact(x,value,depth+1))||obj&&typeof obj==='object'&&Object.values(obj).some(x=>containsExact(x,value,depth+1)));
 const jsonOf=body=>{if(typeof body!=='string'||body.length>65536)return null;try{return JSON.parse(body);}catch{return null;}};
 const matchedRef=(url,body,a)=>{if(!a)return false;try{const parts=new URL(String(url),location.href).pathname.split('/');return [...a.ids].some(id=>parts.includes(id));}catch{return false;}};
 function kind(url,body,a){if(!a)return null;if(containsExact(jsonOf(body),a.f.name))return 'create-exact-name';if(a.urls.has(String(url)))return 'bytes-observed-upload-url';if(matchedRef(url,body,a))return 'followup-observed-file-id';return null;}
 async function matchedBlob(body,a){
  if(!a||!(body instanceof Blob)||body.size!==a.f.bytes)return false;
  // Only the isolated test page's exact-sized synthetic request is inspected.
  const h=await crypto.subtle.digest('SHA-256',await body.arrayBuffer());
  return [...new Uint8Array(h)].map(x=>x.toString(16).padStart(2,'0')).join('')===a.f.sha256;
 }
 function learn(obj,a,depth=0){if(depth>5||!obj||typeof obj!=='object')return;for(const [k,v] of Object.entries(obj)){
  if(typeof v==='string'&&/^(id|file_id|fileId)$/i.test(k)&&/^[a-zA-Z0-9_-]{6,120}$/.test(v))a.ids.add(v);
  if(typeof v==='string'&&/url/i.test(k)&&/^https:\/\//.test(v))a.urls.add(v);
  if(typeof v==='object')learn(v,a,depth+1);
 }}
 async function learnResponse(response,a){try{const text=await response.clone().text();if(text.length<=65536){learn(JSON.parse(text),a);log('own_creation_linkage_observed',{idCount:a.ids.size,urlCount:a.urls.size});}}catch{log('creation_linkage_unavailable');}}
 function abortOne(r,trigger){const a=r.owner;if(closed||a!==active||a.faultInjected||a.deadlineReached||!r.pending)return false;
  if(a.mode==='MID'&&!r.kind.startsWith('bytes'))return false;
  if(a.mode==='POST100'&&(!a.ui100||r.kind==='create-exact-name'))return false;
  // Real native abort only while the associated request remains pending.
  a.faultInjected=true;log('native_abort_requested',{requestLocalId:r.id,transport:r.transport,kind:r.kind,trigger,ui100:a.ui100,loaded:r.loaded??null,total:r.total??null});r.abort();return true;
 }
 function maybePost100(r){if(active?.mode==='POST100'&&active.ui100)queueMicrotask(()=>abortOne(r,'request_after_ui100'));}
 globalThis.fetch=async function(input,init){
  const a=active,body=init?.body,url=typeof input==='string'||input instanceof URL?String(input):input.url;
  let k=kind(url,body,a);if(!k&&await matchedBlob(body,a))k='bytes-exact-sha256';
  if(!a||!k||closed||a.deadlineReached)return nativeFetch.apply(this,arguments);
  const ac=new AbortController(),originalSignal=init?.signal||(input instanceof Request?input.signal:null),signal=originalSignal?AbortSignal.any([originalSignal,ac.signal]):ac.signal;
  const r={id:++serial,owner:a,kind:k,transport:'fetch',pending:true,abort:()=>ac.abort()};pending.add(r);log('native_request_started',{requestLocalId:r.id,transport:r.transport,kind:k});
  let request;try{request=nativeFetch.call(this,input,{...init,signal});maybePost100(r);const response=await request;r.pending=false;pending.delete(r);log('native_response',{requestLocalId:r.id,status:response.status,kind:k});if(k==='create-exact-name')await learnResponse(response,a);return response;}
  catch(e){r.pending=false;pending.delete(r);log('native_request_rejected',{requestLocalId:r.id,kind:k,errorName:e?.name??'unknown',errorMessage:String(e?.message??'').replace(/https?:\/\/\S+/g,'[URL]').slice(0,160),abortedByProbe:ac.signal.aborted});throw e;}
 };
 XMLHttpRequest.prototype.open=function(method,url){xhrMeta.set(this,{url:String(url)});return nativeOpen.apply(this,arguments);};
 XMLHttpRequest.prototype.send=function(body){
  const xhr=this,a=active,m=xhrMeta.get(xhr)||{},sendNow=async()=>{
   let k=kind(m.url,body,a);if(!k&&await matchedBlob(body,a))k='bytes-exact-sha256';
   if(!a||!k||closed||a.deadlineReached)return nativeSend.call(xhr,body);
   const r={id:++serial,owner:a,kind:k,transport:'xhr',pending:true,abort:()=>{if(xhr.readyState!==4)xhr.abort();else log('abort_too_late_no_fault',{requestLocalId:r.id});}};
   pending.add(r);log('native_request_started',{requestLocalId:r.id,transport:r.transport,kind:k});
   xhr.upload.addEventListener('progress',e=>{r.loaded=e.loaded;r.total=e.total;log('native_upload_progress',{requestLocalId:r.id,loaded:e.loaded,total:e.total,lengthComputable:e.lengthComputable});if(a.mode==='MID'&&e.lengthComputable&&e.loaded>0&&e.loaded<e.total)abortOne(r,'native_mid_upload_progress');});
   xhr.addEventListener('abort',()=>log('native_abort_event',{requestLocalId:r.id,kind:k}));
   xhr.addEventListener('error',()=>log('native_network_error',{requestLocalId:r.id,kind:k}));
   xhr.addEventListener('loadend',()=>{r.pending=false;pending.delete(r);log('native_loadend',{requestLocalId:r.id,status:xhr.status,kind:k});if(k==='create-exact-name'&&xhr.status>=200&&xhr.status<300){try{const obj=xhr.responseType==='json'?xhr.response:JSON.parse(xhr.responseText);learn(obj,a);log('own_creation_linkage_observed',{idCount:a.ids.size,urlCount:a.urls.size});}catch{log('creation_linkage_unavailable');}}});
   nativeSend.call(xhr,body);maybePost100(r);
  };
  // Unrelated traffic remains synchronous and untouched. Delay only exact-size
  // fixture candidates or requests already linked to the current synthetic file.
  if(!a||(!kind(m.url,body,a)&&(!(body instanceof Blob)||body.size!==a.f.bytes)))return nativeSend.apply(this,arguments);
  void sendNow().catch(e=>log('bridge_send_exception',{errorName:e?.name??'unknown'}));
 };
 const mo=new MutationObserver(()=>{const a=active;if(!a||a.deadlineReached||closed)return;const cards=[...document.querySelectorAll('[role=button][aria-label]')].filter(e=>e.getAttribute('aria-label')===a.f.name);if(cards.length!==1)return;
  const p=cards[0].querySelector('[role=progressbar]');if(!p||p.getAttribute('aria-label')!==`正在上传 ${a.f.name}`)return;
  const n=Number(p.getAttribute('aria-valuenow'));if(p.hasAttribute('aria-valuenow')&&n===100&&!a.ui100){a.ui100=true;log('own_ui_progress100');}
  for(const r of pending){if(r.owner!==a)continue;if(a.mode==='POST100'&&a.ui100&&abortOne(r,'own_ui_progress100'))break;if(a.mode==='MID'&&n>0&&n<100&&abortOne(r,'own_ui_mid_progress'))break;}
 });mo.observe(document.body,{subtree:true,childList:true,attributes:true,attributeFilter:['aria-valuenow']});
 function command(){const c=JSON.parse(panel.dataset.command||'{}');if(c.sessionId!==session)return;
  if(c.kind==='ping'){log('bridge_ping_received',{challenge:c.challenge});return;}
  if(c.kind==='arm'){
   const f=cfg.fixtures.find(f=>f.label===c.label);if(!f||!['MID','POST100'].includes(c.label)||used.has(f.operationId)||pending.size||closed)throw Error('CASE_ARM_REFUSED');
   if(active&&!active.deadlineReached)throw Error('PREVIOUS_CASE_NOT_CLOSED');used.add(f.operationId);active={f,mode:c.label,ids:new Set(),urls:new Set(),ui100:false,faultInjected:false,deadlineReached:false};const a=active;log('fault_case_armed',{label:f.label,name:f.name,mode:c.label});
   setTimeout(()=>{if(active===a){a.deadlineReached=true;log('case_deadline',{faultInjected:a.faultInjected,pendingRequests:[...pending].filter(r=>r.owner===a).length});}},60000);return;
  }
  if(c.kind==='close-case'){if(active)active.deadlineReached=true;log('case_closed',{pendingRequests:pending.size});return;}
  if(c.kind==='stop'){closed=true;restore();}
 }
 function restore(){globalThis.fetch=nativeFetch;XMLHttpRequest.prototype.open=nativeOpen;XMLHttpRequest.prototype.send=nativeSend;mo?.disconnect();panel.removeEventListener('riftlet-network-command',command);flush();}
 panel.addEventListener('riftlet-network-command',command);
 globalThis.__riftletNativeFault={stop:()=>{closed=true;restore();},query:()=>JSON.parse(sink.textContent)};
 log('bridge_installed',{scope:'this document only',oneAbortPerCase:true,requestsInitiatedByBridge:0});
 panel.textContent='RIFTLET 异常验证 · FAULT BRIDGE ARMED\n诊断桥已就绪；等待 Codex 执行；请勿手动上传或发送';
 return {bridge:'ARMED',sessionId:session,requestsInitiatedByBridge:0};
})();
