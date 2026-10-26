(() => {
 'use strict';
 const cfg=__CONFIG__;
 if(globalThis.__riftletBoundReady)throw Error('EXISTING_OBSERVER_NO_REARM');
 if(location.href!=='https://chatgpt.com/')throw Error('TARGET_ROUTE_MISMATCH');
 const editors=[...document.querySelectorAll('[contenteditable=true][role=textbox]')];
 if(editors.length!==1||editors[0].textContent.trim()!=='')throw Error('EXPECTED_EMPTY_TEXT_TEST_DRAFT');
 const editor=editors[0],form=editor.closest('form'),imgs=form?[...form.querySelectorAll('img')]:[];
 if(imgs.length!==1||imgs[0].alt!=='download.png')throw Error('EXPECTED_EXISTING_SYNTHETIC_BASELINE');
 const baselineImage=imgs[0],baselineCard=baselineImage.closest('[role=button]'),baselineSrc=baselineImage.src;
 const nativeInputs=[...form.querySelectorAll('input[type=file]')];
 const input=nativeInputs.find(e=>e.getAttribute('aria-label')==='附加文件');
 if(!baselineCard||!input)throw Error('BASELINE_OR_NATIVE_FILE_INPUT_MISSING');
 const documentNonce=crypto.randomUUID(),draftLeaseId=crypto.randomUUID(),route=location.href;
 const binding={windowId:cfg.windowId,tabId:cfg.tabId,documentNonce,nativeDocumentId:null,documentTimeOrigin:performance.timeOrigin,draftLeaseId,assetId:cfg.assetId,operationId:cfg.operationId};
 let phase='ARMING',invalidReason=null,sequence=0,last='',nodeSerial=0,hashVerified=false,inputCount=0,truncated=false,probeReceipt=null,mutationReceipt=null,profileReceipt=null;
 const events=[],ids=new WeakMap(),seenFiles=new WeakSet();
 const id=n=>{if(!ids.has(n))ids.set(n,'node-'+(++nodeSerial));return ids.get(n);};
 const valid=()=>!invalidReason&&location.href===route&&form.isConnected&&editor.isConnected&&editor.closest('form')===form&&document.querySelectorAll('[contenteditable=true][role=textbox]').length===1&&editor.textContent.trim()===''&&baselineCard.isConnected&&form.contains(baselineCard)&&baselineImage.isConnected&&baselineImage.closest('[role=button]')===baselineCard&&baselineImage.src===baselineSrc;
 const host=document.createElement('div');host.id='riftlet-ready-r27c-status';
 host.style.cssText='position:fixed;top:12px;right:18px;z-index:2147483647;max-width:440px;pointer-events:none';
 const shadow=host.attachShadow({mode:'open'}),panel=document.createElement('div');panel.setAttribute('role','status');
 panel.style.cssText='font:13px/1.5 system-ui,sans-serif;padding:12px 16px;border-radius:12px;border:2px solid #719f7e;background:#e9fff0;color:#13271c;box-shadow:0 3px 16px #0003;white-space:pre-line';shadow.append(panel);document.body.append(host);
 const oldTitle=document.title;
 function show(){panel.textContent=`RIFTLET ${cfg.targetLabel} · ${phase}\n${phase==='ARMED'?'监听链路已验证；可正常添加一次':phase==='CAPTURING'?'正在记录；请勿再次添加':phase==='UNKNOWN'?'绑定失效；不要上传':'正在验证；暂勿上传'}\n${cfg.name}\n保留现有蓝色图片 · 不发送`;
  panel.style.background=phase==='ARMED'?'#e9fff0':phase==='UNKNOWN'?'#fff0ef':'#fff8e3';
  document.title=`[Riftlet ${cfg.targetLabel} ${phase}] ChatGPT`;
 }
 function emit(event,state){if(events.length>=4000){truncated=true;invalidReason='EVENT_BUFFER_EXHAUSTED';phase='UNKNOWN';show();return;}events.push({sequence:++sequence,monotonicMs:performance.now(),clockId:`browser-performance:${documentNonce}`,...binding,event,state});}
 function invalidate(reason){if(invalidReason)return;invalidReason=reason;phase='UNKNOWN';emit('target_invalidated',{reason,result:'UNKNOWN',retryAllowed:false});show();}
 function guard(){if(!valid()){invalidate('DRAFT_LEASE_OR_BASELINE_CHANGED');return false;}return true;}
 const clean=(k,v)=>/^(src|srcset|href|action|poster)$/i.test(k)||/https?:\/\/|blob:|data:|url\(/i.test(v)?'[URL_OR_PAYLOAD_NOT_COLLECTED]':/token|cookie|authorization|secret|password/i.test(k)?'[SENSITIVE_ATTRIBUTE_NOT_COLLECTED]':v.length>2048?`[LONG_VALUE_${v.length}]`:v;
 const attrs=e=>Object.fromEntries([...e.attributes].map(a=>[a.name,clean(a.name,a.value)]));
 const ownedCards=()=>[...form.querySelectorAll('[role=button]')].filter(e=>e.getAttribute('aria-label')===cfg.name);
 function snapshot(){
  if(!guard())return {valid:false,result:'UNKNOWN',reason:invalidReason};
  const cards=ownedCards();
  const records=cards.map(c=>({nodeId:id(c),attributes:attrs(c),text:c.textContent.slice(0,1000),nodes:[c,...c.querySelectorAll('*')].slice(0,300).map(e=>({nodeId:id(e),tag:e.tagName,attributes:attrs(e),leafText:e.childElementCount===0?e.textContent.slice(0,1000):null,...(e.tagName==='IMG'?{image:{complete:e.complete,naturalWidth:e.naturalWidth,naturalHeight:e.naturalHeight,sourceKind:(e.currentSrc||e.src).split(':')[0]}}:{})})),referencedStatus:[...c.querySelectorAll('[aria-describedby],[aria-labelledby]'),c].flatMap(e=>['aria-describedby','aria-labelledby'].flatMap(a=>(e.getAttribute(a)||'').split(/\s+/).filter(Boolean))).map(ref=>document.getElementById(ref)).filter(Boolean).map(e=>({nodeId:id(e),role:e.getAttribute('role'),text:e.textContent.slice(0,1000)}))}));
  const uploading=cards.length===1&&[...cards[0].querySelectorAll('[role=progressbar]')].some(p=>p.getAttribute('aria-label')===`正在上传 ${cfg.name}`);
  return {valid:true,...binding,composerNode:id(editor),formNode:id(form),baselineCardNode:id(baselineCard),baselinePreserved:true,textUnchanged:true,exactNamedCards:cards.length,cards:records,inputCount,hashVerified,phase,result:uploading?'UPLOADING':'UNKNOWN',positiveReady:null,retryAllowed:false,verifiedServerDraftEpoch:null};
 }
 function sample(event){const s=snapshot(),encoded=JSON.stringify(s);if(encoded!==last){last=encoded;emit(event,s);}return s;}
 function captured(e){
  if(!guard())return;
  if(e.type==='riftlet:listener-probe'){
   if(e.target!==input||e.detail?.documentNonce!==documentNonce)return;
   probeReceipt={challenge:e.detail.challenge,documentNonce,receivedAt:performance.now(),targetNode:id(e.target),capturePhase:e.eventPhase===Event.CAPTURING_PHASE,isTrusted:e.isTrusted};
   emit('listener_probe_received',probeReceipt);return;
  }
  if(phase!=='ARMED'&&phase!=='CAPTURING'){emit('input_before_armed_refused',{result:'UNKNOWN'});invalidate('INPUT_BEFORE_ARMED');return;}
  const files=e.type==='change'&&e.target instanceof HTMLInputElement?e.target.files:e.type==='drop'?e.dataTransfer?.files:e.clipboardData?.files;
  if(!files?.length)return;
  for(const file of files){
   if(file.name!==cfg.name){emit('unexpected_file_name',{eventType:e.type,expectedName:cfg.name,result:'UNKNOWN'});continue;}
   if(seenFiles.has(file)){emit('same_file_object_event_duplicate',{eventType:e.type});continue;}seenFiles.add(file);
   inputCount++;phase='CAPTURING';show();
   emit('file_entered',{name:file.name,bytes:file.size,mime:file.type,eventType:e.type,isTrusted:e.isTrusted,inputNode:id(e.target),targetInForm:form.contains(e.target),ordinal:inputCount});
   if(inputCount>1){invalidate('MULTIPLE_INPUT_ATTEMPTS_NO_REPLAY');return;}
   file.arrayBuffer().then(b=>crypto.subtle.digest('SHA-256',b)).then(d=>{
    if(!guard())return;const sha=[...new Uint8Array(d)].map(n=>n.toString(16).padStart(2,'0')).join('');hashVerified=sha===cfg.sha256&&file.size===cfg.bytes;
    emit('input_bytes_verified',{name:file.name,bytes:file.size,sha256:sha,matches:hashVerified});if(!hashVerified)invalidate('FIXTURE_BYTES_MISMATCH');sample('hash_result');
   }).catch(()=>invalidate('INPUT_HASH_FAILED'));
  }
 }
 const onImage=e=>{if(!guard()||e.target.tagName!=='IMG')return;const c=e.target.closest('[role=button]');if(c?.getAttribute('aria-label')===cfg.name){emit('image_'+e.type,{nodeId:id(e.target),snapshot:snapshot()});sample('image_property_change');}};
 const observer=new MutationObserver(records=>{
  if(!guard())return;
  if(records.some(r=>r.target===input&&r.attributeName==='data-riftlet-probe')){mutationReceipt={documentNonce,inputNode:id(input),observedAt:performance.now()};emit('mutation_probe_received',mutationReceipt);}
  const own=ownedCards(),names=[...new Set(records.filter(r=>own.some(c=>c===r.target||c.contains(r.target))).map(r=>r.attributeName).filter(Boolean))];
  if(names.length)emit('owned_attribute_names_changed',{names});sample('composer_mutation');
 });
 observer.observe(form,{subtree:true,childList:true,attributes:true,characterData:true});
 for(const t of ['change','drop','paste','riftlet:listener-probe'])document.addEventListener(t,captured,true);
 for(const t of ['load','error'])document.addEventListener(t,onImage,true);
 for(const t of ['pagehide','popstate','hashchange'])addEventListener(t,()=>invalidate('DOCUMENT_OR_ROUTE_EVENT_'+t));
 const timer=setInterval(()=>{if(!guard())clearInterval(timer);},1000);
 const channel=new BroadcastChannel(cfg.profileChannel);
 channel.onmessage=e=>{const d=e.data;if(d?.challenge===cfg.profileChallenge&&d?.kind==='original-test-document-reply'){
  profileReceipt={sameOriginStoragePartitionRoundTrip:true,originalDocumentNonce:d.documentNonce,originalWindowId:cfg.originalObserverWindowId,originalTabId:cfg.originalObserverTabId,nativeProfileName:null,nativeProfileDirectory:null};emit('profile_partition_receipt',profileReceipt);channel.close();
 }};
 globalThis.__riftletBoundReady={
  query:()=>({binding,snapshot:sample('query'),events:events.slice(),truncated,probeReceipt,mutationReceipt,profileReceipt,visibleStatus:panel.textContent,fixture:{name:cfg.name,sha256:cfg.sha256,bytes:cfg.bytes},nativeDocumentId:null}),
  probe:challenge=>{if(!guard())throw Error('TARGET_INVALID');input.dispatchEvent(new CustomEvent('riftlet:listener-probe',{bubbles:true,detail:{challenge,documentNonce}}));const key='data-riftlet-probe',prior=input.getAttribute(key);input.setAttribute(key,challenge);if(prior===null)input.removeAttribute(key);else input.setAttribute(key,prior);return {binding,challenge,eventDelivered:probeReceipt?.challenge===challenge,mutationPending:true};},
  profilePing:()=>{if(!guard())throw Error('TARGET_INVALID');channel.postMessage({kind:'bound-test-document-ping',challenge:cfg.profileChallenge,documentNonce});return {sent:true};},
  arm:challenge=>{if(!guard()||!probeReceipt||probeReceipt.challenge!==challenge||!probeReceipt.capturePhase||!mutationReceipt||mutationReceipt.documentNonce!==documentNonce)throw Error('ARMING_PROOF_MISSING');if(phase!=='ARMING')throw Error('ALREADY_ARMED_OR_INVALID');phase='ARMED';emit('armed_verified',{probeReceipt,mutationReceipt,binding});show();return {armed:true,binding,visibleStatus:panel.textContent,probeReceipt,mutationReceipt};},
  stop:()=>{observer.disconnect();clearInterval(timer);channel.close();for(const t of ['change','drop','paste','riftlet:listener-probe'])document.removeEventListener(t,captured,true);for(const t of ['load','error'])document.removeEventListener(t,onImage,true);invalidate('STOPPED');return {stopped:true};}
 };
 emit('observer_installed',snapshot());show();return JSON.stringify({installed:true,phase,binding,existingImagePreserved:true});
})();
