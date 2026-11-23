(function armOneXHR(c,editor) {
  "use strict";
  const key=Symbol.for("riftlet.g4.once.v1");
  const refused=reason=>({kind:"g4-once-v1",status:"BLOCKED_ENV",reason});
  const page="https://chatgpt.com/?temporary-chat=true", endpoint="https://chatgpt.com/backend-api/files";
  if(!c || !/^[0-9a-f]{32,128}$/i.test(c.nonce) || !/^[0-9a-f]{64}$/.test(c.pngSHA256) ||
      !Number.isSafeInteger(c.pngBytes) || c.pngBytes<=0 || c.pngBytes>16*1024*1024 ||
      !c.entryID || !Number.isFinite(c.timeOrigin)) return refused("invalid-config");
  if(key in globalThis || Symbol.for("riftlet.g4.passive.v1") in globalThis) return refused("occupied");
  const doc=document, form=editor?.closest?.("form"), root=doc.documentElement;
  const visible=n=>n.isConnected && n.getClientRects().length>0 && n.checkVisibility({checkOpacity:true,checkVisibilityCSS:true});
  function scope(){
    try {
      const forms=[...doc.querySelectorAll("main form")].filter(visible);
      if(forms.length!==1 || forms[0]!==form) return false;
      const es=[...form.querySelectorAll("[contenteditable=true],textarea,[role=textbox]")]
        .filter(e=>visible(e)&&(e.isContentEditable||e.tagName==="TEXTAREA"));
      return es.length===1 && es[0]===editor && editor.ownerDocument===doc && form.contains(editor) &&
        doc===document && root===doc.documentElement && window===top && doc.visibilityState==="visible" &&
        doc.hasFocus() && location.href===page && navigation.currentEntry?.id===c.entryID && performance.timeOrigin===c.timeOrigin;
    } catch {return false;}
  }
  if(!scope()) return refused("original-target-unproven");
  const proto=XMLHttpRequest.prototype, slots=[[globalThis,"fetch"],[proto,"open"],[proto,"send"]];
  const desc=slots.map(([o,k])=>Object.getOwnPropertyDescriptor(o,k)), abort=Object.getOwnPropertyDescriptor(proto,"abort")?.value;
  if(desc.some(d=>!d?.writable || typeof d.value!=="function") || typeof abort!=="function" ||
      typeof crypto.subtle?.digest!=="function") return refused("observer-unavailable");
  const [fetch0,open0,send0]=desc.map(d=>d.value);
  const opened=new WeakMap(), listeners=[], at=()=>Math.round(performance.now()*1000)/1000;
  const enc=new TextEncoder(), data=(o,k)=>o && Object.getOwnPropertyDescriptor(o,k)?.value;
  const hash=async data=>[...new Uint8Array(await crypto.subtle.digest("SHA-256",data))].map(n=>n.toString(16).padStart(2,"0")).join("");
  const resolveURL=v=>typeof v==="string" || v instanceof URL ? new URL(v,page).href : null;
  let source=null, input=null, earlyXHR=null, signed=null, target=null, reader=null, timer=null, installed=0;
  let active=true,reason=null,observerPending=0,restored=false,final=null, sourceVerified=false;
  let operationHash=null,urlSHA256=null,createHash=null,inputCount=0,changeCount=0,creates=0,responses=0,byteRequests=0;
  let byteReturned=false, byteStarted=false, sentAt=null, progress=0, uploadEnded=false,responseStarted=false;
  let abortCalls=0,abortEvents=0,loadendEvents=0,trigger=null,abortReceipt=null,terminal=null,progressEvents=0;
  let nativePending=false, scheduled=false, closing=false, generation=0, loadstarts=0, insideNativeSend=false;
  function scheduleClose(cause){
    if(scheduled || closing || final || !active)return;
    scheduled=true;queueMicrotask(()=>{scheduled=false;if(!final && active)freeze(cause);});
  }
  function fail(r){reason??=r;scheduleClose("UNSAFE_OR_INCOMPLETE");}
  function guard(fn){try{fn();}catch{fail("observer-exception");}}
  function ready(){if(active&&!scope())fail("original-target-changed");return active&&!reason;}
  function observing(){return active && !terminal && ready();}
  function asyncJob(fn){
    observerPending++;
    const run=Promise.resolve().then(fn);
    run.catch(()=>fail("observer-read-error")).finally(()=>{observerPending--;guard(maybeAbort);});
  }
  function listen(obj,event,fn){
    obj.addEventListener(event,fn);listeners.push([obj,event,fn]);
  }
  function teardown(){
    if(!active)return;
    active=false; clearTimeout(timer);
    for(const [obj,type,fn] of listeners)obj.removeEventListener(type,fn);
    listeners.length=0;
    if(reader){void reader.cancel().catch(()=>{});reader=null;}
    doc.removeEventListener("input",fileEvent,true); doc.removeEventListener("change",fileEvent,true);
    restored=true;
    for(let i=installed-1;i>=0;i--){
      const [owner,name]=slots[i];
      if(Object.getOwnPropertyDescriptor(owner,name)?.value!==hooks[i]){restored=false;continue;}
      try{Object.defineProperty(owner,name,desc[i]);}catch{restored=false;}
    }
    if(!restored)fail("observer-restoration-conflict");
    source=input=target=earlyXHR=signed=null;
  }
  function fileEvent(e){guard(()=>{
    if(!(e.target instanceof HTMLInputElement) || e.target.type!=="file" || !ready())return;
    const el=e.target;
    if(el.ownerDocument!==doc || !el.isConnected || !(el.form===form || form.contains(el)) || el.files.length!==1)
      return fail("unowned-file-input");
    const f=el.files[0];
    if(!(f instanceof File) || f.type!=="image/png" || f.size!==c.pngBytes) return fail("unexpected-file");
    const match=/^riftlet-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.png$/i.exec(f.name);
    if(!match)return fail("unexpected-file-name");
    if(e.type==="change"){
      changeCount++;if(changeCount!==1 || inputCount!==1 || el!==input || f!==source)fail("change-mismatch");return;
    }
    inputCount++; if(inputCount!==1 || changeCount)return fail("repeated-input");
    source=f;input=el;
    asyncJob(async()=>{
      if(await hash(await f.arrayBuffer())!==c.pngSHA256)return fail("source-sha-mismatch");
      const h=await hash(enc.encode(match[1].toLowerCase()));
      if(active){operationHash=h;sourceVerified=true;}
    });
  });}
  function validateCreate(body){
    if(typeof body!=="string" || body.length>8192){fail("create-body-unproven");return false;}
    let j;try{j=JSON.parse(body);}catch{fail("create-body-unproven");return false;}
    if(!j || j.file_name!==source.name || Object.hasOwn(j,"name") || Object.hasOwn(j,"filename") ||
        ["size","file_size","file_size_bytes"].some(k=>Object.hasOwn(j,k)&&j[k]!==source.size)){
      fail("create-file-mismatch");return false;
    }
    creates++;if(creates!==1){fail("repeated-create");return false;}
    return true;
  }
  async function responseOf(res){
    if(!ready())return;
    if(res.url!==endpoint || res.redirected || res.status!==200 || !/^application\/json\b/i.test(res.headers.get("content-type")||"") ||
       Number(res.headers.get("content-length"))>65536)return fail("create-response-unproven");
    const own=res.clone().body?.getReader();if(!own)return fail("unreadable-create-response");
    reader=own;const decoder=new TextDecoder();let text="",length=0;
    try{
      while(active && !reason){
        const {value,done}=await own.read();if(done)break;
        length+=value.length;if(length>65536){void own.cancel().catch(()=>{});return fail("oversize-create-response");}
        text+=decoder.decode(value,{stream:true});
      }
      if(!ready())return;
      const j=JSON.parse(text+decoder.decode());
      if(!j || typeof j.upload_url!=="string" || j.upload_url.length>8192 || Object.hasOwn(j,"uploadUrl"))return fail("signed-field-unproven");
      const u=new URL(j.upload_url);
      if(u.protocol!=="https:" || u.username || u.password || u.hash || u.href===endpoint)return fail("signed-url-unproven");
      responses++;if(responses!==1)return fail("repeated-create-response");
      signed=u.href; urlSHA256=await hash(enc.encode(signed));createHash=await hash(enc.encode(endpoint));
      if(target && target.url!==signed)return fail("early-url-mismatch");
    }finally{if(reader===own)reader=null;own.releaseLock();}
  }
  function wrappedFetch(resource,init){
    let own=false;
    guard(()=>{
      if(!source || !observing())return;
      const req=resource instanceof Request?resource:null, url=resolveURL(req?req.url:resource);
      const body=data(init,"body");
      if(url!==endpoint && (!signed || url!==signed) && body!==source)return;
      const method=String(data(init,"method")||req?.method||"GET").toUpperCase();
      if(url===endpoint && method==="POST")own=validateCreate(body);
      else if(body===source || (signed && url===signed))fail("unexpected-fetch-byte-route");
    });
    let ret;try{ret=Reflect.apply(fetch0,this,arguments);}catch(e){if(own)fail("create-native-threw");throw e;}
    if(own)guard(()=>Promise.prototype.then.call(ret,res=>{
      if(!active)return;
      observerPending++;
      responseOf(res).catch(()=>fail("create-read-error")).finally(()=>{observerPending--;guard(maybeAbort);});
    },()=>fail("create-rejected")));
    return ret;
  }
  function wrappedOpen(method,urlArg){
    // Invalidate this generation before native open can reuse the same XHR
    // and dispatch events against the old listeners. Always forward the call.
    if(active && !terminal && target?.xhr===this)fail("bound-xhr-reopened");
    opened.delete(this);
    const ret=Reflect.apply(open0,this,arguments);
    guard(()=>{
      if(!source || !observing() || typeof method!=="string")return;
      const url=resolveURL(urlArg),m=method.toUpperCase();
      if(url===endpoint && m==="POST")return fail("changed-create-transport");
      if(signed && url===signed){if(m!=="PUT")return fail("changed-byte-method");opened.set(this,{url,method:m,generation:++generation});return;}
      if(!signed && creates===1 && m==="PUT" && url?.startsWith("https://")){
        if(earlyXHR)return fail("multiple-early-put");earlyXHR=this;opened.set(this,{url,method:m,generation:++generation});
      }
    });return ret;
  }
  function snap(xhr,e){
    return {at:at(),readyState:xhr.readyState,status:xhr.status,loaded:Number.isFinite(e?.loaded)?e.loaded:null,
      total:e?.lengthComputable&&Number.isFinite(e.total)?e.total:null};
  }
  function maybeAbort(){
    if(!target || !ready() || !sourceVerified || !operationHash || !urlSHA256 || !createHash || observerPending ||
       inputCount!==1||changeCount!==1||creates!==1||responses!==1||byteRequests!==1||
       !byteStarted||loadstarts!==1||!byteReturned||abortCalls||!nativePending)return;
    const {xhr,url,body,record}=target;
    if(opened.get(xhr)!==record || record.method!=="PUT" || record.url!==url ||
       record.generation!==target.generation)return fail("original-xhr-generation-changed");
    if(url!==signed || body!==source || !input.isConnected || input.ownerDocument!==doc ||
       !(input.form===form || form.contains(input)))return fail("target-binding-changed");
    if(!xhr || responseStarted || uploadEnded || progress>=c.pngBytes || xhr.readyState!==1 || xhr.status!==0)
      return fail("pre-response-window-ended");
    // Reserve this sole native call before invoking it. abort can synchronously fire events.
    abortCalls=1;
    trigger={...snap(xhr),kind:"AFTER_NATIVE_SEND_BEFORE_RESPONSE",nativeSendReturned:true,
      nativeReturnedAt:sentAt,requestGeneration:record.generation,requestGenerationVerified:true,observedUploadLoaded:progress,uploadProgressEvents:progressEvents,
      uploadState:progress>0?"PARTIAL_PROGRESS_OBSERVED":"NO_POSITIVE_PROGRESS_OBSERVED"};
    try{Reflect.apply(abort,xhr,[]);}catch{fail("native-abort-threw");}
  }
  function bindXHR(xhr,record,body){
    const url=record.url;
    byteRequests++;if(byteRequests!==1){fail("repeated-byte-request");return false;}
    if(body!==source || !(body instanceof File)){fail("byte-file-object-mismatch");return false;}
    target={xhr,url,body,record,generation:record.generation};nativePending=true;
    listen(xhr,"loadstart",e=>{
      if(!e.isTrusted)return;
      loadstarts++;
      if(loadstarts!==1 || !insideNativeSend || byteReturned)return fail("unowned-xhr-loadstart");
      byteStarted=true;
    });
    listen(xhr,"readystatechange",e=>{if(e.isTrusted && xhr.readyState>=2 && !abortCalls)responseStarted=true;});
    listen(xhr,"progress",e=>{if(e.isTrusted && !abortCalls)responseStarted=true;});
    listen(xhr.upload,"progress",e=>{if(!e.isTrusted)return;progressEvents++;progress=Math.max(progress,e.loaded||0);});
    listen(xhr.upload,"load",e=>{if(e.isTrusted)uploadEnded=true;});
    listen(xhr,"abort",e=>{if(!e.isTrusted)return;abortEvents++;abortReceipt=snap(xhr,e);if(abortCalls!==1)fail("external-abort");});
    listen(xhr,"loadend",e=>{
      if(!e.isTrusted)return;
      loadendEvents++;nativePending=false;terminal=snap(xhr,e);
      if(abortCalls!==1||abortEvents!==1||terminal.status!==0)fail("terminal-without-own-abort");
      else scheduleClose("ORIGINAL_ABORT_AND_LOADEND");
    });
    return true;
  }
  function wrappedSend(body){
    let owned=false;
    guard(()=>{
      if(!source || !observing())return;
      const record=opened.get(this),url=record?.url;
      if(!url){if(body===source)fail("original-file-route-unproven");return;}
      if(!signed && body!==source)return;
      if(signed && url!==signed){if(body===source)fail("original-file-url-mismatch");return;}
      owned=bindXHR(this,record,body);
    });
    if(owned)insideNativeSend=true;
    let ret;try{ret=Reflect.apply(send0,this,arguments);}
    catch(e){if(owned){nativePending=false;fail("native-send-threw");}throw e;}
    finally{if(owned)insideNativeSend=false;}
    if(owned){byteReturned=true;sentAt=at();queueMicrotask(()=>guard(maybeAbort));}
    return ret;
  }
  const hooks=[wrappedFetch,wrappedOpen,wrappedSend];
  function report(status){
    return {kind:"g4-once-v1",status,reason,inputs:inputCount,changes:changeCount,creates,responses,byteRequests,
      abortCalls,abortEvents,loadendEvents,cancelledByObserver:abortCalls,observerPending,requestPending:nativePending,
      nativeSendReturned:byteReturned,byteLoadstart:byteStarted,byteLoadstartCount:loadstarts,sourceVerified,operationHash,restored,trigger,
      abortReceipt,terminal,create:{transport:creates?"fetch":null,method:creates?"POST":null,path:creates?"/backend-api/files":null,
        fileNameField:creates?"file_name":null,responseStatus:responses?200:null,uploadURLField:responses?"upload_url":null,urlSHA256:createHash},
      bytes:{transport:byteRequests?"xhr":null,method:byteRequests?"PUT":null,bodyType:target?"File":null,
        sameFile:Boolean(target && target.body===source),bodyScope:target?"entire-body":null,bodySize:target?c.pngBytes:null,
        pngSHA256:sourceVerified?c.pngSHA256:null,urlSHA256,responseStatus:terminal?.status??null}};
  }
  function freeze(cause){
    if(final || closing)return;
    closing=true;
    const ok=ready() && !observerPending && !nativePending && abortCalls===1 && abortEvents===1 && loadendEvents===1 &&
      byteStarted && loadstarts===1 && byteReturned && sourceVerified && operationHash && trigger &&
      abortReceipt?.status===0 && terminal?.status===0;
    if(!ok)reason??="incomplete-single-fault";
    const evidence=report("INCONCLUSIVE");teardown();
    final=Object.freeze({...evidence,restored,reason,status:ok&&restored?"TRANSPORT_FAULT_OBSERVED":"INCONCLUSIVE",
      teardownCause:cause,stoppedAt:at(),autoRestored:cause!=="HOST_FINISH" && restored});
    closing=false;
  }
  function sample(n){
    if(n!==c.nonce)return refused("nonce-mismatch");
    if(!final)ready();
    return final||report("OBSERVING");
  }
  function finish(n){
    if(n!==c.nonce)return refused("nonce-mismatch");
    if(!final)freeze("HOST_FINISH");
    if(globalThis[key]===api)delete globalThis[key];return final;
  }
  const api=Object.freeze({sample,finish});
  try{
    Object.defineProperty(globalThis,key,{value:api,configurable:true});
    for(let i=0;i<slots.length;i++){
      Object.defineProperty(slots[i][0],slots[i][1],{...desc[i],value:hooks[i]});installed++;
    }
    doc.addEventListener("input",fileEvent,true);doc.addEventListener("change",fileEvent,true);
    listen(window,"pagehide",()=>{fail("page-left");freeze("PAGE_LEFT");});
    listen(doc,"visibilitychange",()=>{if(doc.visibilityState!=="visible"){fail("page-hidden");freeze("PAGE_HIDDEN");}});
    timer=setTimeout(()=>{fail("deadline");freeze("DEADLINE");},60000);
    return {kind:"g4-once-v1",status:"ARMED",deadlineMs:60000,cancelledByObserver:0};
  }catch{fail("installation-failed");teardown();if(globalThis[key]===api)delete globalThis[key];return refused("installation-failed");}
})
