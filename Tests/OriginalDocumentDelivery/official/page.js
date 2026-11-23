'use strict';
(async () => {
  const element = id => document.getElementById(id);
  const doc = crypto.randomUUID(), editorID = crypto.randomUUID(), operations = new Map();
  const editor = element('editor'), input = element('png'), card = element('prior'), image = element('priorImage');
  const originalText = editor.value;
  const base64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
  image.src = 'data:image/png;base64,'+base64;
  editor.setSelectionRange(6,10,'forward');
  const counts = {semantic:0,setter:0,input:0,change:0,submit:0};
  element('draft').onsubmit = e => { e.preventDefault();counts.submit++; };
  const nativeFiles = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'files');
  Object.defineProperty(HTMLInputElement.prototype,'files',{...nativeFiles,set(list) {
    counts.setter++;return Reflect.apply(nativeFiles.set,this,[list]);
  }});
  const files = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'files');
  const allEvents={input:0,change:0,submit:0,keyDown:0,keyUp:0};
  for(const [event,label] of [['input','input'],['change','change'],['submit','submit'],['keydown','keyDown'],['keyup','keyUp']]) {
    document.addEventListener(event,()=>allEvents[label]++,true);
  }
  input.addEventListener('input',() => counts.input++);
  input.addEventListener('change',() => counts.change++);
  const snapshot = () => ({doc,editor:editorID,counts:{...counts},topLevel:window.top===window,
    navigation:performance.getEntriesByType('navigation')[0]?.type,
    originalText:editor.value===originalText,appendedQ:editor.value===originalText+'q',
    selection:[editor.selectionStart,editor.selectionEnd,editor.selectionDirection],
    oldCard:element('prior')===card && element('priorImage')===image && image.naturalWidth===1,
    fileCount:files.get.call(input).length});
  const result=element('result');
  function fail(error) {
    result.value='未通过：'+error.message;
    for(const id of ['original','replace','replacement']) element(id).disabled=true;
  }
  function check(condition,why) { if(!condition) throw Error(why); }
  async function api(endpoint, data) {
    const response=await fetch('./'+endpoint,data ? {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)} : {});
    if(!response.ok) throw Error('验收服务拒绝请求 '+response.status);
    return response.json();
  }
  // Genuine key evidence is collected only from the independent QA field.
  // The held screenshot/text operation has no keyboard API or focus fallback.
  let down=false,typed=false,up=false;
  const keyboard=element('keyboard');
  keyboard.addEventListener('keydown',e=>{if(e.isTrusted&&e.key==='q'&&!e.repeat) down=true;});
  keyboard.addEventListener('input',e=>{if(e.isTrusted&&e.inputType==='insertText'&&e.data==='q'&&keyboard.value==='q'&&down) typed=true;});
  keyboard.addEventListener('keyup',e=>{if(e.isTrusted&&e.key==='q'&&typed&&keyboard.value==='q') {
    up=true;element('keyResult').textContent=' 已观察到独立 q 按键';
  }});
  function keySample() { return {doc,observed:down&&typed&&up,down,typed,up}; }
  function stage() {
    const address={doc,editor:editorID,operation:crypto.randomUUID()};
    // The known button belonging to this same QA form triggers the replacement
    // barrier. Moving focus to another editor or window still retires the grant.
    const barrierButton=element('replace');
    const original=window.bindOriginalReceiver(editor,() => element('editor')===editor,true,
      next=>next===barrierButton && barrierButton.form===editor.form);
    const fileReceiver=window.bindOriginalReceiver(input,() => original.current() && element('png')===input);
    const semantic=original.once(function() {
      counts.semantic++;
      this.setRangeText('q',this.value.length,this.value.length,'preserve');
    });
    const range=[editor.selectionStart,editor.selectionEnd,editor.selectionDirection];
    const restoreSelection=original.once(HTMLTextAreaElement.prototype.setSelectionRange);
    const file=fileReceiver.once(function(list) {
      Reflect.apply(files.set,this,[list]);
    });
    const notifyInput=fileReceiver.once(EventTarget.prototype.dispatchEvent);
    const notifyChange=fileReceiver.once(EventTarget.prototype.dispatchEvent);
    operations.set(address.operation,{address,current:() => original.current()&&fileReceiver.current(),deliver:() => {
      const transfer=new DataTransfer();
      transfer.items.add(new File([Uint8Array.from(atob(base64),c=>c.charCodeAt(0))],address.operation+'.png',{type:'image/png'}));
      const setters=file(transfer.files);
      const inputEvent=setters&&notifyInput(new Event('input',{bubbles:true}));
      const changeEvent=inputEvent&&notifyChange(new Event('change',{bubbles:true}));
      const afterFile=snapshot();
      const text=semantic(), selection=text&&restoreSelection(...range);
      return {status:'DELIVERED',setters,inputEvent,changeEvent,text,selection,afterFile,after:snapshot()};
    }});
    return address;
  }
  function deliver(address) {
    // Only stage() grants authority. A transported envelope can only look up
    // an existing one-shot operation in the receiving document's own map.
    const held=operations.get(address.operation);
    if(!held||held.address.doc!==address.doc||held.address.editor!==address.editor) {
      return {status:'ORIGINAL_OPERATION_ABSENT',attempted:address,registryHit:!!held,after:snapshot()};
    }
    operations.delete(address.operation);
    return held.deliver();
  }
  async function positive() {
    const address=stage(), delivered=deliver(address), nativeFile=files.get.call(input)[0];
    const hash=nativeFile && await crypto.subtle.digest('SHA-256',await nativeFile.arrayBuffer());
    const sha256=hash ? Array.from(new Uint8Array(hash),b=>b.toString(16).padStart(2,'0')).join('') : null;
    if(nativeFile)element('fileResult').textContent='本次附件 '+nativeFile.name;
    return {address,delivered,sha256};
  }
  const state=await api('state'); const phase=state.phase;
  async function verifyUnsupportedOrigin() {
    const before=snapshot(),initial={setter:counts.setter,...allEvents},witness=crypto.randomUUID();
    let error='NO_REFUSAL';
    try {
      await window.riftletWebAcceptance({action:'pinTarget',clickWitnessID:witness,address:location.origin+location.pathname},{});
    } catch(e) { error=e.message==='PAGE_ROUTE_UNSUPPORTED' ? e.message : 'UNEXPECTED_ERROR'; }
    const after=snapshot(),current={setter:counts.setter,...allEvents};
    const delta=Object.fromEntries(Object.keys(current).map(k=>[k,current[k]-initial[k]]));
    const bytes=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(location.href));
    const urlSHA256=Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,'0')).join('');
    await api('route',{doc,editor:editorID,action:'pinTarget',witness,error,before,after,delta,urlSHA256,sourceSHA256:state.sourceSHA256});
    element('routeResult').textContent='完整产品程序已拒绝 QA 域名，输入次数为零。';
  }
  element('doc').textContent=state.family+' · '+(phase==='replace'?'新文档 B':'原稿 A')+' · '+doc;
  if(phase==='new') {
    let heldAddress;
    element('original').disabled=false;result.value='原稿就绪。';
    element('original').onclick=async()=>{
      element('original').disabled=true;
      try {
        await image.decode();await verifyUnsupportedOrigin();
        const baseline=snapshot(), pending=stage(), write=await positive();
        const heldCurrent=operations.get(pending.operation)?.current()===true;
        await api('original',{baseline,pending,heldCurrent,write,keyboard:keySample()});
        heldAddress=pending;
        element('replace').disabled=false;result.value='原稿已验证，另一项原稿操作尚未投递。';
      } catch(e) {fail(e);}
    };
    element('replace').onclick=async()=>{
      element('replace').disabled=true;
      try {
        const held=operations.get(heldAddress.operation);
        await api('barrier',{doc,pending:heldAddress,registryHit:!!held,heldCurrent:held?.current()===true});
        location.reload();
      }
      catch(e) {fail(e);}
    };
  } else if(phase==='replace') {
    element('replacement').disabled=false;result.value='文档已更换，可以投递保留的旧操作。';
    element('replacement').onclick=async()=>{
      element('replacement').disabled=true;
      try {
        await image.decode();await verifyUnsupportedOrigin();const baseline=snapshot();
        check(doc!==state.pending.doc,'文档未更换');
        const old=deliver(state.pending);
        const fresh=await positive();
        const final=await api('complete',{baseline,old,fresh,keyboard:keySample()});
        result.value=final.status==='PASS'?'已通过。旧操作零写入，新草稿独立正向对照通过。':'未通过。';
      } catch(e) {fail(e);}
    };
  } else result.value=phase==='done'?'本次验收已完成。':'已挂起旧操作；该页面已离开。';
})().catch(error=>{document.getElementById('result').value='验收页错误：'+error.message;});
