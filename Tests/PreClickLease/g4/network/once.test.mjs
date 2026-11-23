import assert from "node:assert/strict";
import {test} from "node:test";
import {webcrypto,createHash} from "node:crypto";
import {readFile} from "node:fs/promises";
import {runInNewContext} from "node:vm";
const src=await readFile(new URL("./once.js",import.meta.url),"utf8");
const page="https://chatgpt.com/?temporary-chat=true",create="https://chatgpt.com/backend-api/files",signed="https://store.example.test/test?secret=PRIVATE";
const uuid="a5cdb255-e1b9-4548-8454-7cfb32cf6894";
const bytes=Buffer.from([137,80,78,71,13,10,26,10,101,102,103]);
const sha=x=>createHash("sha256").update(x).digest("hex"),delay=()=>new Promise(r=>setTimeout(r,5));
class Bus{
  listeners=new Map();
  addEventListener(k,fn){if(!this.listeners.has(k))this.listeners.set(k,new Set());this.listeners.get(k).add(fn);}
  removeEventListener(k,fn){this.listeners.get(k)?.delete(fn);}
  emit(type,target=this,extra={}){for(const fn of [...(this.listeners.get(type)||[])])fn({type,target,isTrusted:true,...extra});}
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
      if(o.uploadEnd)this.upload.emit("load",this.upload);
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
  const config={nonce:"f".repeat(40),entryID:"qa-entry",timeOrigin:123,pngBytes:bytes.length,pngSHA256:o.badHash?"b".repeat(64):sha(bytes)};
  const arm=runInNewContext(src,ctx),armed=arm(config,editor);
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
async function act(h){h.attach();await h.createReq();await h.settle(s=>s.responses===1&&s.sourceVerified);h.send();await h.settle(s=>!!s.abortCalls);}
for(const progress of [0,2])test("exact original File once; upload progress "+progress,async()=>{
  const h=setup({progress});await act(h);
  const r=h.finish();assert.equal(r.status,"TRANSPORT_FAULT_OBSERVED");
  assert.deepEqual([r.inputs,r.changes,r.creates,r.responses,r.byteRequests,r.abortCalls,r.abortEvents,r.loadendEvents],[1,1,1,1,1,1,1,1]);
  assert.deepEqual([r.nativeSendReturned,r.sourceVerified,r.bytes.sameFile,r.byteLoadstart,r.requestPending,r.restored],[true,true,true,true,false,true]);
  assert.deepEqual([r.trigger.readyState,r.trigger.status,r.abortReceipt.status,r.terminal.status],[1,0,0,0]);assert.equal(r.observerPending,0);
  assert.equal(r.operationHash,sha(uuid)); assert.equal(r.bytes.urlSHA256,sha(signed));assert.equal(r.bytes.pngSHA256,sha(bytes));
  assert.equal(r.trigger.observedUploadLoaded,progress);assert.deepEqual(h.calls,["fetch","open","send","abort"]);
  assert(!JSON.stringify(r).includes("PRIVATE"));assert(!JSON.stringify(r).includes(uuid));assert.equal(r.abortReceipt.readyState,4);
});
test("early bound XHR waits for signed URL and SHA",async()=>{
  const h=setup();h.attach();h.createReq();h.send();
  await h.settle(s=>s.abortEvents===1);assert.equal(h.finish().status,"TRANSPORT_FAULT_OBSERVED");
});
for(const [label,opts] of Object.entries({
  hash:{badHash:true},"HTTP 201 create":{createStatus:201},"field conflict":{response:{upload_url:signed,uploadUrl:signed}},
  "no loadstart":{start:false},"synthetic loadstart":{trusted:false},"full upload":{progress:bytes.length},"upload ended":{uploadEnd:true},
  "response headers":{headers:true},"already complete":{websiteComplete:true},"native send threw":{throwSend:true},
  "send abort throws":{throwAbort:true},"no real abort event":{fakeAbort:true},"terminal never received":{noEnd:true}
})){
  test(label,async()=>{
    const h=setup(opts);h.attach();await h.createReq();await h.settle(s=>s.responses===1&&s.sourceVerified);
    if(opts.throwSend)assert.throws(()=>h.send(),/native-send/);else h.send();
    await delay();const r=h.finish();assert.equal(r.status,"INCONCLUSIVE");
    assert.equal(h.calls.filter(x=>x==="abort").length,opts.throwAbort||opts.fakeAbort||opts.noEnd?1:0);
    assert.equal(r.restored,true);if(opts.noEnd)assert.equal(r.requestPending,true);
  });
}
for(const variant of ["foreign-file","foreign-url","duplicate-create","alternate-fetch","replaced-editor","duplicate-input","early-wrong-url","preexisting-observer","deadline","untrusted-file-type"]){
  test(variant,async()=>{
    const h=setup();
    if(variant==="preexisting-observer")assert.equal(h.arm(h.config,h.editor).status,"BLOCKED_ENV");
    if(variant==="untrusted-file-type")h.input.files=[new File([bytes],"wrong.jpg",{type:"image/jpeg"})];
    h.attach();if(variant==="duplicate-input")h.attach();h.createReq();
    if(variant==="early-wrong-url")h.send(signed+"other");
    await h.settle(s=>s.responses===1&&s.sourceVerified);
    if(variant==="replaced-editor")h.doc.querySelectorAll=()=>[{}];
    if(variant==="deadline")h.expires();
    if(variant==="duplicate-create")await h.createReq();
    if(variant==="alternate-fetch")await h.ctx.fetch(signed,{method:"PUT",body:h.f});
    if(variant==="foreign-file")h.send(signed,new File([bytes],h.f.name,{type:"image/png"}));
    if(variant==="foreign-url")h.send(signed+"other",h.f);
    if(variant==="duplicate-create"||variant==="replaced-editor"||variant==="duplicate-input"||variant==="deadline"||variant==="untrusted-file-type")h.send();
    await delay();assert.equal(h.finish().status,"INCONCLUSIVE");assert.equal(h.calls.includes("abort"),false);
  });
}
test("never abort web page's second request",async()=>{
  const h=setup();await act(h);h.send();await delay();
  const r=h.finish();assert.equal(r.teardownCause,"ORIGINAL_ABORT_AND_LOADEND");assert.equal(r.status,"TRANSPORT_FAULT_OBSERVED");
  assert.equal(r.abortCalls,1);assert.equal(h.calls.filter(x=>x==="send").length,2);
});
test("owned reader released on deadline",async()=>{
  const h=setup({hangingClone:true});h.attach();await h.createReq();await delay();assert.equal(h.reading(),true);
  h.expires();await delay();assert.equal(h.cancels(),1);assert.equal(h.finish().status,"INCONCLUSIVE");assert.equal(h.calls.includes("abort"),false);
});
for(const uri of [signed,signed+"other"]){
  test("reopened original XHR generation cannot abort replacement "+(uri===signed?"same-url":"different-url"),async()=>{
    const h=setup();h.attach();h.createReq();const x=h.send();x.open("PUT",uri);x.send(h.f);
    await delay();const r=h.finish();assert.equal(r.status,"INCONCLUSIVE");assert.equal(r.reason,"bound-xhr-reopened");
    assert.equal(r.abortCalls,0);assert.equal(h.calls.filter(k=>k==="send").length,2);
  });
}
test("auto-restores all hooks before unrelated requests; nonce alone reads frozen result",async()=>{
  const h=setup();await act(h);const s=h.sample();assert.equal(s.status,"TRANSPORT_FAULT_OBSERVED");
  assert.equal(s.autoRestored,true);assert.equal(s.restored,true);assert.equal(s.teardownCause,"ORIGINAL_ABORT_AND_LOADEND");
  assert.equal(h.api.sample("wrong").status,"BLOCKED_ENV");
  h.send("https://other.example.test/ordinary","other-body");
  assert.equal(h.sample().byteRequests,1);assert.equal(h.finish(),s);
});
test("other instance cannot steal pending target",async()=>{
  const h=setup();h.attach();await h.createReq();await h.settle(s=>s.responses===1);
  h.send();h.send("https://other.example.test/ordinary","other-body");await delay();
  const r=h.finish();assert.equal(r.status,"TRANSPORT_FAULT_OBSERVED");assert.equal(r.abortCalls,1);assert.equal(r.byteRequests,1);
});
test("unsafe pending HEADERS_RECEIVED preserves terminal uncertainty",async()=>{
  const h=setup({headers:true});await act(h);const r=h.sample();assert.equal(r.status,"INCONCLUSIVE");assert.equal(r.restored,true);
  assert.equal(r.requestPending,true);assert.equal(r.abortCalls,0);assert.equal(r.terminal,null);h.finish();
});
test("cached open/send same instance new generation rejects trusted second loadstart",async()=>{
  const h=setup();h.attach();await h.createReq();await h.settle(s=>s.responses===1&&s.sourceVerified);
  const x=h.send();h.originals[1].call(x,"PUT",signed+"other");h.originals[2].call(x,new Blob(["unrelated"]));
  await delay();const r=h.finish();assert.equal(r.status,"INCONCLUSIVE");
  assert.equal(r.byteLoadstartCount,2);assert.equal(r.reason,"unowned-xhr-loadstart");assert.equal(r.abortCalls,0);
});
test("trusted first loadstart appearing after native send returned cannot arm abort",async()=>{
  const h=setup({start:false});h.attach();await h.createReq();await h.settle(s=>s.responses===1&&s.sourceVerified);
  const x=h.send();x.emit("loadstart");await delay();const r=h.finish();
  assert.equal(r.reason,"unowned-xhr-loadstart");assert.equal(r.abortCalls,0);
});
