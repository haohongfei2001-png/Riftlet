(() => {
 const cfg=__CONFIG__;
 if(globalThis.__riftletExceptions)throw Error('NO_REARM_EXISTING_SESSION');
 const editor=document.querySelector('[contenteditable=true][role=textbox]'),form=editor?.closest('form');
 if(!form||editor.textContent.trim()||form.querySelectorAll('img').length)throw Error('EMPTY_ISOLATED_TEST_DRAFT_REQUIRED');
 const nonce=crypto.randomUUID(),route=location.href,ids=new WeakMap(),events=[];let serial=0,seq=0,last='',invalid=false,active=null,armed=false;
 const id=n=>{if(!ids.has(n))ids.set(n,'n'+ ++serial);return ids.get(n);};
 const fixture=name=>cfg.fixtures.find(f=>f.name===name);
 const header=document.createElement('div');header.id='riftlet-exception-panel';header.dataset.session=cfg.sessionId;header.dataset.config=JSON.stringify(cfg);header.style.cssText='position:fixed;right:12px;top:10px;z-index:2147483647;padding:12px;max-width:510px;background:#fff4d6;color:#222;border:2px solid #9b731b;border-radius:9px;font:13px/1.5 system-ui;white-space:pre-line';document.body.append(header);
 const bridge=document.createElement('script');bridge.type='application/json';bridge.id='riftlet-network-receipt';bridge.dataset.session=cfg.sessionId;bridge.textContent=JSON.stringify({state:'NOT_INSTALLED'});document.body.append(bridge);
 const emit=(event,state={})=>{if(events.length>=3000){invalid=true;return;}events.push({sequence:++seq,monotonicMs:performance.now(),documentNonce:nonce,windowId:cfg.windowId,tabId:cfg.tabId,sessionId:cfg.sessionId,event,state});};
 const valid=()=>!invalid&&location.href===route&&editor.isConnected&&form.isConnected&&editor.closest('form')===form&&document.querySelectorAll('[contenteditable=true][role=textbox]').length===1;
 const show=s=>{header.textContent='RIFTLET 异常验证 · '+s+'\n只使用合成文件；不发送；原实验标签页保留';document.title='[Riftlet 异常验证] ChatGPT';};
 const safe=(k,v)=>/^(src|srcset|href|action|poster)$/.test(k)||/https?:\/\/|blob:|data:/.test(v)?'[PAYLOAD_NOT_COLLECTED]':v.length>1200?'[LONG]':v;
 function snapshot(){
  const own=[...form.querySelectorAll('[role=button][aria-label]')].filter(c=>fixture(c.getAttribute('aria-label')));
  return {valid:valid(),documentNonce:nonce,routeUnchanged:location.href===route,editorNode:id(editor),formNode:id(form),textLength:editor.textContent.length,textIsExpectedSynthetic:editor.textContent==='Riftlet synthetic typing during upload — DO NOT SEND',cards:own.map(c=>({name:c.getAttribute('aria-label'),cardNode:id(c),nodes:[c,...c.querySelectorAll('*')].slice(0,200).map(n=>({nodeId:id(n),tag:n.tagName,attrs:Object.fromEntries([...n.attributes].map(a=>[a.name,safe(a.name,a.value)])),text:n.childElementCount===0?n.textContent.slice(0,600):null,...(n.tagName==='IMG'?{image:{complete:n.complete,width:n.naturalWidth,height:n.naturalHeight,sourceKind:(n.currentSrc||n.src).split(':')[0]}}:{})}))})),active,armed,result:'UNKNOWN',retryAllowed:false};
 }
 function sample(why){const s=snapshot(),str=JSON.stringify(s);if(str!==last){last=str;emit(why,s);}if(!s.valid){invalid=true;show('UNKNOWN — 目标已变化，不重传');}return s;}
 const mo=new MutationObserver(()=>sample('composer_mutation'));mo.observe(form,{subtree:true,attributes:true,childList:true,characterData:true});
 document.addEventListener('change',e=>{if(!valid()||!(e.target instanceof HTMLInputElement)||e.target.type!=='file')return;for(const file of e.target.files||[]){const f=fixture(file.name);if(!f){emit('unrelated_file_ignored',{count:1});continue;}emit('file_entered',{label:f.label,name:f.name,isTrusted:e.isTrusted,bytes:file.size,inputNode:id(e.target)});file.arrayBuffer().then(b=>crypto.subtle.digest('SHA-256',b)).then(h=>emit('input_hash',{label:f.label,sha256:[...new Uint8Array(h)].map(x=>x.toString(16).padStart(2,'0')).join(''),bytes:file.size}));}},true);
 document.addEventListener('input',e=>{if(e.target===editor||editor.contains(e.target))emit('editor_input',{isTrusted:e.isTrusted,inputType:e.inputType??null,textLength:editor.textContent.length,snapshot:snapshot()});},true);
 for(const type of ['load','error'])document.addEventListener(type,e=>{if(e.target.tagName==='IMG'&&fixture(e.target.alt))emit('image_'+type,{name:e.target.alt,snapshot:snapshot()});},true);
 for(const type of ['pagehide','hashchange','popstate'])addEventListener(type,()=>{invalid=true;emit('target_invalidated',{event:type});show('UNKNOWN — 目标已变化');});
 const guardTimer=setInterval(()=>{if(!valid()){sample('target_invalidated');clearInterval(guardTimer);}},500);
 const operations=new Set();
 globalThis.__riftletExceptions={
  query:()=>({binding:{sessionId:cfg.sessionId,documentNonce:nonce,windowId:cfg.windowId,tabId:cfg.tabId},snapshot:sample('query'),events:events.slice(),network:JSON.parse(bridge.textContent),eventLimitReached:events.length>=3000}),
  arm(label){if(!valid())throw Error('INVALID_TARGET');active=label;armed=true;emit('case_armed',{label});show('ARMED — '+label);return {armed:true,documentNonce:nonce,label};},
  dispatch({label,base64,expectedNonce}){
   const f=cfg.fixtures.find(f=>f.label===label);if(!f||!armed||!valid()||expectedNonce!==nonce)throw Error('DISPATCH_GUARD');if(operations.has(f.operationId))throw Error('NO_REPLAY');
   const input=form.querySelector('input[type=file][aria-label="附加文件"]');if(!input)throw Error('NO_INPUT');const data=Uint8Array.from(atob(base64),x=>x.charCodeAt(0));if(data.length!==f.bytes||data[0]!==137||data[1]!==80)throw Error('WRONG_FILE');
   operations.add(f.operationId);emit('dispatch_intent',{label,operationId:f.operationId});const dt=new DataTransfer();dt.items.add(new File([data],f.name,{type:'image/png'}));Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'files').set.call(input,dt.files);input.dispatchEvent(new Event('change',{bubbles:true}));emit('dispatched',{label,operationId:f.operationId});return {dispatched:true,label};
  },
  typeSynthetic(){if(!valid())throw Error('INVALID_TARGET');if(editor.textContent.trim())throw Error('DO_NOT_OVERWRITE');editor.focus({preventScroll:true});const ok=document.execCommand('insertText',false,'Riftlet synthetic typing during upload — DO NOT SEND');emit('typing_action',{ok,snapshot:snapshot()});return {inserted:ok};},
  networkCommand(command){header.dataset.command=JSON.stringify({sessionId:cfg.sessionId,...command});header.dispatchEvent(new Event('riftlet-network-command'));return JSON.parse(bridge.textContent);},
  display(message){show(message);return {shown:true};}
 };
 emit('observer_installed',snapshot());show('监听已安装，准备异常用例');return JSON.stringify({installed:true,documentNonce:nonce,sessionId:cfg.sessionId});
})();
