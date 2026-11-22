import assert from "node:assert/strict";
import {test} from "node:test";
import {webcrypto,createHash} from "node:crypto";
import {readFile} from "node:fs/promises";
import {runInNewContext} from "node:vm";
const src=await readFile(new URL("./late-once.js",import.meta.url),"utf8");
const page="https://chatgpt.com/?temporary-chat=true",create="https://chatgpt.com/backend-api/files",signed="https://store.example.test/test?secret=PRIVATE";
const uuid="a5cdb255-e1b9-4548-8454-7cfb32cf6894";
const bytes=Buffer.from([137,80,78,71,13,10,26,10,101,102,103]);
const sha=x=>createHash("sha256").update(x).digest("hex"),delay=()=>new Promise(r=>setTimeout(r,5));
class Bus{
  listeners=new Map();
  addEventListener(k,fn){if(!this.listeners.has(k))this.listeners.set(k,new Set());this.listeners.get(k).add(fn);}
  removeEventListener(k,fn){this.listeners.get(k)?.delete(fn);}
  emit(type,target=this,extra={}){for(const fn of [...(this.listeners.get(type)||[])])fn({type,target,currentTarget:this,isTrusted:true,...extra});}
}
function setup(o={}){
  const doc=new Bus(),win=new Bus(), calls=[];
  let now=1000,expires,probeCancels=0;
  const visible={isConnected:true,getClientRects:()=>[{}],checkVisibility:()=>true};
  const form={...visible,querySelectorAll:()=>[editor],contains:e=>e===editor||e===input};
  const editor={...visible,isContentEditable:true,ownerDocument:doc,closest:()=>form};
  class Input{}
  const f=new File([bytes],"riftlet-"+uuid+".png",{type:"image/png"});
  const input=Object.assign(new Input(),{form,ownerDocument:doc,type:"file",isConnected:true,files:[f]});
  doc.querySelectorAll=()=>[form];doc.hasFocus=()=>true;doc.visibilityState="visible";doc.documentElement={};
  let lastPromise,reading=false;
  function nativeFetch(url,init){
    calls.push("fetch");const res=new Response(JSON.stringify(o.response||{upload_url:signed}),{status:o.createStatus||200,headers:{"content-type":"application/json"}});
    Object.defineProperty(res,"url",{value:url});
    if(o.hangingClone)Object.defineProperty(res,"clone",{value:()=>({body:{getReader:()=>{let done;return{
      read:()=>{reading=true;return new Promise(r=>{done=r;});},cancel:()=>{probeCancels++;done?.({done:true});return Promise.resolve();},releaseLock:()=>{}
    };}}})});
    lastPromise=Promise.resolve(res);return lastPromise;
  }
  class XHR extends Bus{
    upload=new Bus(); readyState=0;status=0;
    open(method,url){this.url=url;this.method=method;this.readyState=1;calls.push("open");return 13;}
    send(body){
      calls.push("send");if(o.throwSend)throw new Error("native-send");
      if(o.start!==false)this.emit("loadstart",this,{isTrusted:o.trusted!==false});
      if(o.progress)this.upload.emit("progress",this.upload,{loaded:o.progress,total:bytes.length,lengthComputable:true});
      if(o.uploadEnd)this.upload.emit("load",this.upload,{loaded:bytes.length,total:bytes.length,lengthComputable:true});
      if(o.headers){this.readyState=2;this.status=200;this.emit("readystatechange");}
      if(o.websiteComplete){this.readyState=4;this.status=201;this.emit("loadend");}
      return 17;
    }
    abort(){
      calls.push("abort");
      if(o.throwAbort)throw Error("native-abort");
      this.status=0;this.readyState=4;
      if(!o.noAbortEvent)this.emit("abort",this,{isTrusted:!o.fakeAbort});
      if(!o.noEnd)this.emit("loadend");this.readyState=0;
    }
  }
  const ctx={document:doc,window:win,top:win,location:{href:page},navigation:{currentEntry:{id:"qa-entry"}},performance:{timeOrigin:123,now:()=>++now},
    XMLHttpRequest:XHR,HTMLInputElement:Input,crypto:webcrypto,fetch:nativeFetch,TextDecoder,TextEncoder,URL,Request,File,Promise,
    setTimeout:fn=>{expires=fn;return 1;},clearTimeout:()=>{},queueMicrotask};
  const originals=[ctx.fetch,XHR.prototype.open,XHR.prototype.send,XHR.prototype.abort];
  const config={triggerMode:o.mode??"NATIVE_UPLOAD_PARTIAL",nonce:"f".repeat(40),entryID:"qa-entry",timeOrigin:123,pngBytes:bytes.length,pngSHA256:o.badHash?"b".repeat(64):sha(bytes)};
  const arm=runInNewContext(src,ctx),armed=arm(config,editor);
  if(o.rejected)return {armed,calls};
  assert.equal(armed.status,"ARMED");
  const api=ctx[Symbol.for("riftlet.g4.once.v1")];
  const sample=()=>api.sample(config.nonce);
  const finish=()=>{const r=api.finish(config.nonce);assert.deepEqual(originals,[ctx.fetch,XHR.prototype.open,XHR.prototype.send,XHR.prototype.abort]);return r;};
  const attach=()=>{doc.emit("input",input);doc.emit("change",input);};
  const createReq=(body=JSON.stringify({file_name:f.name,file_size_bytes:f.size}))=>{
    const promise=ctx.fetch(create,{method:"POST",body});assert.equal(promise,lastPromise);return promise;};
  const send=(url=signed,body=f,method="PUT")=>{const x=new XHR();assert.equal(x.open(method,url),13);assert.equal(x.send(body),17);return x;};
  async function settle(wanted){for(let i=0;i<25;i++){const s=sample();if(s.reason||(!s.observerPending&&wanted(s)))return s;await delay();}return sample();}
  return {originals,attach,createReq,send,sample,finish,ctx,doc,input,f,calls,arm,editor,config,api,settle,expires:()=>expires(),reading:()=>reading,cancels:()=>probeCancels};
}
const MID="NATIVE_UPLOAD_PARTIAL", SENT="NATIVE_UPLOAD_LOAD_BEFORE_RESPONSE";
const ev=(x,kind,loaded,total=bytes.length,extra={})=>x.upload.emit(kind,x.upload,{loaded,total,lengthComputable:true,...extra});
const complete=(x,status=201)=>{x.readyState=4;x.status=status;x.emit("readystatechange");x.emit("loadend");};
async function eligible(o={}){const h=setup(o);h.attach();await h.createReq();await h.settle(s=>s.responses===1&&s.sourceVerified);return h;}
for(const mode of [MID,SENT]){
  const event=mode===MID?"progress":"load",loaded=mode===MID?4:bytes.length;
  test(mode+" single genuine original event and automatic restoration",async()=>{
    const h=await eligible({mode});const x=h.send();await delay();assert.equal(h.sample().abortCalls,0);
    ev(x,event,loaded);await delay();const r=h.sample();
    assert.equal(r.status,"TRANSPORT_FAULT_OBSERVED");assert.equal(r.triggerMode,mode);
    assert.deepEqual([r.trigger.kind,r.trigger.eventType,r.trigger.eventTrusted,r.trigger.eventTarget,r.trigger.loaded,r.trigger.total,r.trigger.lengthComputable],
      [mode,event,true,"original-xhr.upload",loaded,bytes.length,true]);
    assert.deepEqual([r.trigger.readyState,r.trigger.status,r.trigger.responseStarted,r.nativeSendReturned,r.byteLoadstartCount,r.trigger.requestGenerationVerified],[1,0,false,true,1,true]);
    assert.deepEqual([r.bytes.pngSHA256,r.bytes.urlSHA256,r.operationHash,r.bytes.sameFile,r.bytes.bodyScope],[sha(bytes),sha(signed),sha(uuid),true,"entire-body"]);
    assert.deepEqual([r.abortCalls,r.abortEvents,r.loadendEvents,r.autoRestored,r.restored,r.observerPending,r.requestPending],[1,1,1,true,true,0,false]);
    assert.equal(r.uploadObservation.eligibleEvents,1);assert.equal(r.uploadObservation.uploadLoadCount,mode===MID?0:1);
    assert.equal(h.api.sample("wrong").status,"BLOCKED_ENV");assert.equal(h.finish(),r);
    const stranger=h.send(signed+"different",new Blob(["public fixture"]));
    assert.equal(stranger.status,0);assert.equal(h.calls.filter(v=>v==="abort").length,1);
  });
  for(const variant of ["wrong-total","untrusted","wrong-current-target","wrong-event-target","noncomputable","zero","oversize",
     "unrelated-xhr","headers-first","download-progress-first","before-native-return","before-file-sha","after-natural-completion","after-expiry",
     "wrong-file","wrong-url","site-ui-100","cached-same-url","cached-new-url","reopened-same-url","reopened-new-url","missing-loadstart","invalid-sha","duplicate-create","replaced-editor"]){
    test(mode+" "+variant,async()=>{
      const h=variant==="before-file-sha"?setup({mode}):await eligible({mode,badHash:variant==="invalid-sha",start:variant!=="missing-loadstart",
        progress:variant==="before-native-return" && mode===MID?3:0,uploadEnd:variant==="before-native-return" && mode===SENT});
      if(variant==="before-file-sha"){h.attach();h.createReq();}
      if(variant==="duplicate-create")await h.createReq();
      const x=h.send(variant==="wrong-url"?signed+"other":signed,variant==="wrong-file"?new File([bytes],h.f.name,{type:"image/png"}):h.f);
      let triggerTarget=x;
      if(variant==="unrelated-xhr")triggerTarget=h.send(signed+"unrelated",new Blob(["other-file"]));
      if(variant==="headers-first"){x.readyState=2;x.status=200;x.emit("readystatechange");}
      if(variant==="download-progress-first")x.emit("progress",x,{loaded:1});
      if(variant==="after-natural-completion")complete(x);
      if(variant==="after-expiry")h.expires();
      if(variant==="replaced-editor")h.doc.querySelectorAll=()=>[{}];
      if(variant.startsWith("cached-") || variant.startsWith("reopened-")){
        const u=variant.endsWith("same-url")?signed:signed+"next";
        if(variant.startsWith("cached-")){h.originals[1].call(x,"PUT",u);h.originals[2].call(x,new Blob(["new"]));}
        else{x.open("PUT",u);x.send(new Blob(["new"]));}
      }
      if(variant==="site-ui-100")h.doc.emit("progress",h.doc,{loaded:bytes.length,total:bytes.length,lengthComputable:true});
      else if(variant!=="before-native-return"){
        const amount=variant==="zero"?0:variant==="oversize"?bytes.length+1:loaded;
        ev(triggerTarget,event,amount,variant==="wrong-total"?bytes.length+1:bytes.length,
          variant==="noncomputable"?{lengthComputable:false}:variant==="untrusted"?{isTrusted:false}:
          variant==="wrong-current-target"?{currentTarget:x}:variant==="wrong-event-target"?{target:x}:{});
      }
      await delay();
      if(h.sample().status==="OBSERVING")complete(x);
      await delay();
      const r=h.finish();assert.equal(r.status,"INCONCLUSIVE");assert.equal(r.abortCalls,0);assert.equal(r.restored,true);
      if(variant==="before-native-return"){assert.equal(r.uploadObservation.eligibleEvents,1);assert.equal(r.uploadObservation.unreadyEvents,1);}
      assert.equal(h.calls.includes("abort"),false);
    });
  }
  test(mode+" deadline preserves real pending value",async()=>{
    const h=await eligible({mode});h.send();h.expires();const r=h.finish();
    assert.equal(r.status,"INCONCLUSIVE");assert.equal(r.requestPending,true);assert.equal(r.restored,true);assert.equal(r.terminal,null);
  });
}
test("middle strategy rejects full progress and later upload load and reports natural completion",async()=>{
  const h=await eligible({mode:MID});const x=h.send();ev(x,"progress",bytes.length);ev(x,"load",bytes.length);
  complete(x);await delay();const r=h.finish();assert.equal(r.status,"INCONCLUSIVE");assert.equal(r.abortCalls,0);
  assert.equal(r.uploadObservation.fullProgressCount,1);assert.equal(r.uploadObservation.uploadLoadCount,1);
  assert.equal(r.terminal.status,201);assert.equal(r.requestPending,false);
});
test("native upload load strategy ignores even complete trusted upload progress",async()=>{
  const h=await eligible({mode:SENT});const x=h.send();ev(x,"progress",bytes.length);complete(x);
  await delay();const r=h.finish();assert.equal(r.abortCalls,0);assert.equal(r.uploadObservation.uploadLoadCount,0);
  assert.equal(r.uploadObservation.fullProgressCount,1);
});
test("native upload load must attest entire original byte length",async()=>{
  const h=await eligible({mode:SENT});const x=h.send();ev(x,"load",bytes.length-1);complete(x);await delay();
  const r=h.finish();assert.equal(r.abortCalls,0);assert.equal(r.uploadObservation.eligibleEvents,0);
});
test("frozen opaque, unwitnessed, or retired strategy is refused before installation",()=>{
  for(const mode of ["POST100","MID","NATIVE_UPLOAD_LOAD",""]){
    const h=setup({mode,rejected:true});assert.equal(h.armed.status,"BLOCKED_ENV");assert.equal(h.calls.length,0);
  }
});
