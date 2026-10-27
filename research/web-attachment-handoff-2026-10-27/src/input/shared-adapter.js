/* Riftlet bounded diagnostic adapter v0.1. No send, no private API, no network hooks.
   Loaded unchanged through Apple Events or the optional experiment extension.
   No READY profile is asserted: positiveReady is null until live evidence exists. */
(() => {
  if (globalThis.__riftletProbe) return JSON.stringify({installed:true,reused:true});
  if (location.origin !== 'https://chatgpt.com' || location.pathname !== '/') throw Error('ONLY_FRESH_HOME_DRAFT');
  const editors = [...document.querySelectorAll('[contenteditable=true][role=textbox]')];
  if (editors.length !== 1 || editors[0].textContent.trim()) throw Error('REQUIRE_ONE_EMPTY_TEST_EDITOR');
  const editor = editors[0], root = editor.closest('form');
  if (!root || root.querySelectorAll('img').length) throw Error('REQUIRE_EMPTY_TEST_FORM');
  const route = location.href, nonce = crypto.randomUUID(), nodes = new WeakMap();
  let nodeSerial=0, seq=0, allowed=new Set(), events=[], invalid=false, last='', baselineText='', observedClicks=[];
  const operations = new Map();
  const nodeId = e => {if(!nodes.has(e))nodes.set(e, 'n'+(++nodeSerial));return nodes.get(e);};
  const filenames = s => [...allowed].filter(n=>String(s||'').includes(n));
  const emit = (event,state={},operationId=null) => {
    if(events.length>=1000){invalid=true;return;}
    events.push({sequence:++seq,monotonicMs:performance.now(),documentNonce:nonce,operationId,event,state});
  };
  const valid = () => !invalid && location.href===route && root.isConnected && editor.isConnected && editor.closest('form')===root && document.querySelectorAll('[contenteditable=true][role=textbox]').length===1;
  function snapshot() {
    if(!valid()){invalid=true;return {valid:false,result:'UNKNOWN',reason:'TARGET_LEASE_INVALID'};}
    const signals=[];
    for(const el of root.querySelectorAll('*')) {
      if(el===editor||editor.contains(el)||el.tagName==='INPUT')continue;
      const role=el.getAttribute('role'), attrs={};
      for(const a of ['aria-label','title','alt','data-state','aria-busy','aria-valuenow','aria-valuemax','data-testid','data-file-id']) {
        const v=el.getAttribute(a);if(v===null)continue;
        const ns=filenames(v);
        if(ns.length) attrs[a]={names:ns};
        else if(['data-state','aria-busy','aria-valuenow','aria-valuemax','data-testid'].includes(a)) attrs[a]=/^[\w .:\-]{0,100}$/.test(v)?v:'[redacted]';
        else if(a==='data-file-id')attrs[a]=/^file-[\w-]+$/.test(v)?v:'[redacted]';
        else if(/^(已上传的图片|移除|移除文件|删除|删除文件|上传中|正在上传|上传失败|重试|已完成|已就绪|Remove file|Remove image|Uploaded image|Uploading|Upload failed|Ready|Retry)$/i.test(v))attrs[a]=v;
      }
      const ns=filenames(el.childElementCount===0?el.textContent:'');
      const css=typeof el.className==='string'?el.className.split(/\s+/).filter(c=>/spin|progress|loading|upload|error|success|complete/i.test(c)).slice(0,10):[];
      if(Object.keys(attrs).length||ns.length||role==='progressbar'||role==='alert'||el.tagName==='IMG'||css.length) {
        const item={nodeId:nodeId(el),tag:el.tagName,role,attrs,names:ns,css};
        if(el.tagName==='IMG'){item.image={complete:el.complete,naturalWidth:el.naturalWidth,naturalHeight:el.naturalHeight,sourceKind:el.currentSrc.startsWith('blob:')?'blob':el.currentSrc.startsWith('data:')?'data':el.currentSrc.startsWith('https:')?'https':'other'};}
        signals.push(item);
      }
      if(signals.length>=150)break;
    }
    return {valid:true,documentNonce:nonce,composerNode:nodeId(editor),formNode:nodeId(root),textUnchanged:editor.textContent===baselineText,signals,positiveReady:null,result:'UNKNOWN',draftIdentity:'PARTIAL_NO_VERIFIED_DRAFT_EPOCH'};
  }
  function sample(reason) { const s=snapshot(), encoded=JSON.stringify(s);if(encoded!==last){last=encoded;emit(reason,s);}return s; }
  const obs=new MutationObserver(()=>sample('composer_mutation'));
  obs.observe(root,{subtree:true,childList:true,attributes:true,characterData:true});
  const onInput=e=>{if(e.target instanceof HTMLInputElement&&e.target.type==='file')emit('file_input_event',{inputNode:nodeId(e.target),label:e.target.getAttribute('aria-label'),isTrusted:e.isTrusted,files:[...e.target.files].map(f=>({name:allowed.has(f.name)?f.name:'[unrelated]',bytes:f.size,mime:f.type}))});};
  const onClick=e=>{if(e.target instanceof HTMLInputElement&&e.target.type==='file'){observedClicks.push({inputNode:nodeId(e.target),label:e.target.getAttribute('aria-label')});emit('file_picker_requested',observedClicks.at(-1));}};
  root.addEventListener('change',onInput,true);root.addEventListener('click',onClick,true);
  const invalidate=()=>{invalid=true;emit('target_invalidated',{result:'UNKNOWN'});};
  addEventListener('popstate',invalidate);addEventListener('hashchange',invalidate);addEventListener('pagehide',invalidate);
  globalThis.__riftletProbe={
    configure(names){if(!Array.isArray(names)||!names.every(n=>/^Riftlet_[a-f0-9-]{36}\.png$/.test(n)))throw Error('SYNTHETIC_NAMES_ONLY');allowed=new Set(names);baselineText=editor.textContent;emit('baseline',snapshot());return {documentNonce:nonce,composerNode:nodeId(editor)};},
    baseline(){if(!valid())throw Error('INVALID_TARGET');baselineText=editor.textContent;const s=snapshot();emit('baseline',s);return s;},
    query(){return sample('query');},
    events(after=0){return events.filter(e=>e.sequence>after);},
    dispatch({operationId,name,base64,mime,expectedNonce}){
      if(operations.has(operationId))return {result:'UNKNOWN',reason:'ALREADY_DISPATCHED_NO_REPLAY'};
      if(!valid()||nonce!==expectedNonce)throw Error('TARGET_LEASE_INVALID');
      if(!allowed.has(name)||mime!=='image/png'||base64.length>7000000)throw Error('INVALID_FIXTURE');
      const matches=[...root.querySelectorAll('input[type=file][aria-label="附加文件"]')];
      if(matches.length!==1)throw Error('UNVERIFIED_INPUT_STRUCTURE');
      const input=matches[0], bytes=Uint8Array.from(atob(base64),c=>c.charCodeAt(0));
      if(bytes[0]!==137||bytes[1]!==80||bytes[2]!==78||bytes[3]!==71)throw Error('PNG_SIGNATURE_REQUIRED');
      const file=new File([bytes],name,{type:mime}),dt=new DataTransfer();dt.items.add(file);
      const before=snapshot();operations.set(operationId,{name,result:'UNKNOWN'});
      emit('dispatch_intent',{name,before},operationId);
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'files').set.call(input,dt.files);
      input.dispatchEvent(new Event('change',{bubbles:true}));
      emit('change_dispatched',{name,inputNode:nodeId(input),result:'UNKNOWN'},operationId);
      return {dispatched:true,operationId,result:'UNKNOWN'};
    },
    stop(){obs.disconnect();root.removeEventListener('change',onInput,true);root.removeEventListener('click',onClick,true);removeEventListener('popstate',invalidate);removeEventListener('hashchange',invalidate);removeEventListener('pagehide',invalidate);emit('observer_stopped');invalid=true;return {stopped:true};}
  };
  emit('observer_installed',snapshot());return JSON.stringify({installed:true,documentNonce:nonce});
})();
