import assert from "node:assert/strict";
import {test} from "node:test";
import {webcrypto, createHash} from "node:crypto";
import {readFile} from "node:fs/promises";
import {runInNewContext} from "node:vm";

const source = await readFile(new URL("./calibrate.js", import.meta.url), "utf8");
const pageURL = "https://chatgpt.com/?temporary-chat=true";
const createURL = "https://chatgpt.com/backend-api/files";
const signedURL = "https://media.example.test/blob?signature=PRIVATE-TEST-VALUE";
const digest = buf => createHash("sha256").update(buf).digest("hex");
const original = Buffer.from([137,80,78,71,13,10,26,10,1,2,3,4]);
const uuid = "baeb5783-4914-4bfb-a9ea-59180c452cef";
const pause = () => new Promise(r => setTimeout(r, 6));
class Bus {
  #listeners = new Map();
  addEventListener(type, fn) {
    if (!this.#listeners.has(type)) this.#listeners.set(type, new Set());
    this.#listeners.get(type).add(fn);
  }
  removeEventListener(type, fn) { this.#listeners.get(type)?.delete(fn); }
  emit(type, target) { for (const fn of [...(this.#listeners.get(type)||[])]) fn({type,target}); }
}
function harness(opts={}) {
  const doc = new Bus(), win = new Bus();
  const vis = {isConnected:true, getClientRects:()=>[{}], checkVisibility:()=>true};
  const form = {...vis, querySelectorAll:()=>[editor], contains(el) { return el===editor || el===input; }};
  const editor = {...vis, isContentEditable:true, isConnected:true, ownerDocument:doc, closest:()=>form, getClientRects:()=>[{}]};
  class Input {}
  const testFile = new File([original], 'riftlet-'+uuid+'.png', {type:"image/png"});
  const input = Object.assign(new Input(), {type:"file",files:[testFile],ownerDocument:doc,form,isConnected:true});
  doc.querySelectorAll=()=>[form]; doc.visibilityState="visible";
  const calls = [];
  let cloneReads=0, probeCancels=0;
  const raw = opts.response ?? {upload_url:signedURL};
  function freshResponse() {
    const response = new Response(JSON.stringify(raw),{headers:{"content-type":"application/json"}});
    Object.defineProperty(response,"url",{value:opts.redirect ?? createURL});
    const clone=response.clone.bind(response);
    Object.defineProperty(response,"clone",{value:() => {
      cloneReads++;
      if(opts.hangingClone){let resolve;
        return {body:{getReader:()=>({read:()=>new Promise(r=>{resolve=r;}),
          cancel:()=>{probeCancels++;resolve?.({done:true});return Promise.resolve();},releaseLock:()=>{}})}};
      }
      return clone();
    }});
    return response;
  }
  let lastPromise;
  function nativeFetch(url,init) {
    calls.push(["fetch",url]); const res = url === createURL ? freshResponse() : new Response();
    if(url!==createURL)Object.defineProperty(res,"url",{value:url});
    if(url===signedURL && opts.failBytes==="throw") throw new Error("native error");
    if(url===signedURL && opts.failBytes==="reject"){lastPromise=Promise.reject(new Error("failed"));return lastPromise;}
    if(url===signedURL && opts.failBytes==="pending"){lastPromise=new Promise(()=>{});return lastPromise;}
    lastPromise = Promise.resolve(res);
    return lastPromise;
  }
  class XHR extends Bus {
    send(body) {
      calls.push(["xhr",this.url]);
      if (this.url===createURL) {
        this.responseURL=createURL;
        this.responseType="text"; this.status=200; this.responseText=JSON.stringify(raw);
        this.emit("load",this);
      } else {
        this.responseURL=this.url;
        this.status=opts.failBytes==="http"?503:200;
        if (opts.failBytes==="throw") throw new Error("native error");
        this.emit("loadend",this);
      }
      return 17;
    }
    open(method,url){this.url=url; return 13;}
    getResponseHeader(key){return key==="content-type"?"application/json":null;}
  }
  const ctx = {window:win,top:win,document:doc,HTMLInputElement:Input,File,Blob,URL,Request,ArrayBuffer,FormData,Uint8Array,
    location:{href:opts.location??pageURL}, XMLHttpRequest:XHR, nativeFetch,fetch:nativeFetch,crypto:webcrypto,
    TextEncoder,TextDecoder, setTimeout, clearTimeout, getComputedStyle:()=>({display:"block",visibility:"visible"}),
    performance:{timeOrigin:1234},navigation:{currentEntry:{id:"fixture-entry"}},Promise};
  const config={nonce:"a".repeat(32),pngSHA256:opts.sourceHash??digest(original),pngBytes:original.length,
    entryID:"fixture-entry",timeOrigin:1234};
  const arm = runInNewContext(source,ctx);
  const nativeFns = [ctx.fetch,XHR.prototype.open,XHR.prototype.send];
  const armed = arm(config,editor);
  const api=()=>ctx[Symbol.for("riftlet.g4.passive.v1")];
  const sendFetch = (url,body,method=url===createURL?"POST":"PUT")=>{
    const before=calls.length;
    const promise=ctx.fetch(url,{body,method});
    assert.strictEqual(promise,lastPromise);
    assert.equal(calls.length,before+1);
    return promise;
  };
  const sendXHR = (url,body,method=url===createURL?"POST":"PUT")=>{
    const xhr=new XHR();
    assert.equal(xhr.open(method,url),13);
    const before=calls.length; assert.equal(xhr.send(body),17);
    assert.equal(calls.length,before+1);
  };
  function attach(){doc.emit("input",input);doc.emit("change",input);}
  const createBody=JSON.stringify({file_name:testFile.name,file_size_bytes:testFile.size});
  const sample=()=>api().sample(config.nonce);
  const finished=()=>api().finish(config.nonce);
  async function settled(read=sample) {
    let r=read();
    for(let i=0;i<50 && (r.pending || (r.creates && !r.responses && r.status==="OBSERVING"));i++){
      await pause(); r=read();
    }
    return r;
  }
  return {arm, armed,config,api, nativeFns,ctx,XHR, calls,cloneReads:()=>cloneReads,probeCancels:()=>probeCancels, sendFetch,sendXHR,
    attach,doc,input,editor,testFile,createBody,sample,finished,settled};
}
for (const create of ["fetch","xhr"]) for (const bytes of ["fetch","xhr"]) {
  test('exact PNG '+create+' -> '+bytes, async () => {
    const h=harness(); assert.equal(h.armed.status,"ARMED");
    h.attach();
    const sendCreate=create==="fetch"?h.sendFetch:h.sendXHR;
    const sendBytes=bytes==="fetch"?h.sendFetch:h.sendXHR;
    await sendCreate(createURL,h.createBody);
    await h.settled();
    await sendBytes(signedURL,h.testFile);
    await h.settled();
    const r=h.finished();
    assert.equal(r.status,"CALIBRATED"); assert.equal(r.operationHash,digest(uuid));
    assert.equal(r.create.urlSHA256,digest(createURL)); assert.equal(r.bytes.urlSHA256,digest(signedURL));
    assert.equal(r.bytes.pngSHA256,digest(original));
    assert.deepEqual([r.inputs,r.changes,r.creates,r.responses,r.byteRequests,r.pending],[1,1,1,1,1,0]);
    assert.deepEqual([r.sourceVerified,r.bytesVerified,r.sameFile,r.restored,r.cancelledByObserver],[true,true,true,true,0]);
    assert.equal(r.create.transport,create);assert.equal(r.bytes.transport,bytes);
    assert(!JSON.stringify(r).includes("PRIVATE"));assert(!JSON.stringify(r).includes(uuid));
    assert.deepEqual(h.nativeFns,[h.ctx.fetch,h.XHR.prototype.open,h.XHR.prototype.send]);assert.equal(h.api(),undefined);
  });
}
test('immutable Blob has independent full-byte correlation',async()=>{
  const h=harness(); h.attach(); await h.sendFetch(createURL,h.createBody); await h.settled();
  await h.sendFetch(signedURL,new Blob([original])); await h.settled();
  const r=h.finished(); assert.equal(r.status,"CALIBRATED"); assert.equal(r.sameFile,false); assert.equal(r.bytes.bodyType,"Blob");
});
test('exact original File before signed fetch response is available',async()=>{
  const h=harness();h.attach();const first=h.sendFetch(createURL,h.createBody);
  await h.sendFetch(signedURL,h.testFile); await first; await h.settled();
  assert.equal(h.finished().status,"CALIBRATED");
});
test('account route untouched with accessor sentinel',async()=>{
  const h=harness();h.attach();const init={method:"POST"};
  Object.defineProperty(init,"body",{get(){throw Error("observer accessed unrelated body");}});
  await h.ctx.fetch("https://chatgpt.com/backend-api/accounts/check",init);
  assert.equal(h.cloneReads(),0);assert.equal(h.sample().reason,null);
  assert.equal(h.calls.length,1);assert.equal(h.finished().status,"INCONCLUSIVE");
});
test('no access until source input',async()=>{
  const h=harness();await h.sendFetch(createURL,h.createBody);
  assert.equal(h.cloneReads(),0);assert.equal(h.sample().creates,0);h.finished();
});
test('preserve concurrent observer ownership',()=>{
  const h=harness();
  const p=Object.getOwnPropertyDescriptor(h.ctx,"fetch");
  Object.defineProperty(h.ctx,"fetch",{...p,value:()=>{throw new Error("native error");}});
  assert.throws(()=>h.ctx.fetch(),/native error/);
  assert.equal(h.finished().reason,"observer-restoration-conflict");
});
for (const k of ["different document","non-temp route","content replacement","foreign input","repeat input","wrong nonce","bad source",
                  "foreign name","multiple matching creates","two urls","redirect","wrong-PNG","two byte calls","unknown byte body","unlinked URI","blank","source only"]) {
  test(k,async()=>{
    const h=harness({sourceHash:k==="bad source"?"f".repeat(64):undefined,
      location:k==="non-temp route"?"https://chatgpt.com/":undefined,
      response:k==="two urls"?{upload_url:signedURL,uploadUrl:signedURL}:undefined,
      redirect:k==="redirect"?"https://media.example.test/nope":undefined});
    if(k==="non-temp route"){ assert.equal(h.armed.status,"BLOCKED_ENV"); assert.equal(h.api(),undefined); return; }
    if(k==="blank"){assert.equal(h.finished().status,"INCONCLUSIVE");return;}
    if(k==="wrong nonce") {assert.equal(h.api().finish("wrong").status,"BLOCKED_ENV");assert.equal(h.sample().status,"OBSERVING");h.finished();return;}
    if(k==="different document")h.ctx.navigation.currentEntry.id="new";
    if(k==="content replacement")h.doc.querySelectorAll=()=>[{...h.editor}];
    if(k==="foreign input"){const foreign=Object.assign(Object.create(Object.getPrototypeOf(h.input)),h.input,{form:{}});h.doc.emit("input",foreign);}
    else h.attach();
    if(k==="repeat input")h.attach();
    if(k==="bad source" || k==="source only")await pause();
    if (h.sample().status==="OBSERVING" && k!=="source only") {
      await h.sendFetch(createURL,k==="foreign name"?JSON.stringify({file_name:"unrelated.png"}):h.createBody);
      await h.settled();
      if(k==="multiple matching creates")await h.sendFetch(createURL,h.createBody);
      if(h.sample().status==="OBSERVING"){
        const body=k==="wrong-PNG"?new Blob([Buffer.alloc(original.length)]):
          k==="unknown byte body"?"non-binary":h.testFile;
        await h.sendFetch(k==="unlinked URI"?signedURL+"xx":signedURL,body);
        if(k==="two byte calls")await h.sendFetch(signedURL,h.testFile);
        await h.settled();
      }
    }
    const r=h.finished(); assert.equal(r.status,"INCONCLUSIVE");assert.equal(r.restored,true);
    assert.equal(r.cancelledByObserver,0);
  });
}
for(const [kind,payload,scope] of [
  ["ArrayBuffer",()=>new Uint8Array(original).buffer,"entire-body"],
  ["ArrayBufferView",()=>new Uint8Array(original),"entire-body"],
  ["FormData",h=>{const f=new FormData();f.append("file",h.testFile);return f;},"single-file-part"]]){
  test('native response and exact PNG '+kind,async()=>{
    const h=harness();h.attach();await h.sendFetch(createURL,h.createBody);await h.settled();
    await h.sendFetch(signedURL,payload(h));await h.settled();const r=h.finished();
    assert.equal(r.status,"CALIBRATED");assert.equal(r.byteReturned,true);assert.equal(r.byteCompleted,true);
    assert.equal(r.requestPending,false);assert.equal(r.bytes.responseStatus,200);assert.equal(r.bytes.bodyType,kind);assert.equal(r.bytes.bodyScope,scope);
  });
}
test('reject multipart with other field',async()=>{
  const h=harness();h.attach();await h.sendFetch(createURL,h.createBody);await h.settled();
  const f=new FormData();f.append("file",h.testFile);f.append("other","unread");
  await h.sendFetch(signedURL,f);await h.settled();const r=h.finished();
  assert.equal(r.status,"INCONCLUSIVE");assert.equal(r.bytes.bodyType,"FormData");
});
for(const [transport,mode] of [["fetch","reject"],["fetch","pending"],["fetch","throw"],["xhr","http"],["xhr","throw"]]){
  test('byte native '+transport+' '+mode,async()=>{
    const h=harness({failBytes:mode});h.attach(); await h.sendFetch(createURL,h.createBody);await h.settled();
    const send=transport==="xhr"?h.sendXHR:h.sendFetch;
    if(mode==="throw")assert.throws(()=>send(signedURL,h.testFile),/native error/);
    else if(mode==="reject")await assert.rejects(send(signedURL,h.testFile),/failed/);
    else send(signedURL,h.testFile);
    await h.settled();const before=h.sample();
    if(mode==="pending"){assert.equal(before.requestPending,true);assert.equal(before.byteReturned,true);assert.equal(before.observerPending,0);}
    const r=h.finished();assert.equal(r.status,"INCONCLUSIVE");assert.equal(r.byteCompleted,false);
  });
}
test('early XHR observed before linkage without consuming private response body',async()=>{
  const h=harness();h.attach();h.sendFetch(createURL,h.createBody);h.sendXHR(signedURL,h.testFile);
  await h.settled();assert.equal(h.finished().status,"CALIBRATED");
});
test('stop releases only the observer-owned hanging response clone',async()=>{
  const h=harness({hangingClone:true});h.attach();await h.sendFetch(createURL,h.createBody);
  await pause();assert.equal(h.sample().observerPending,1);
  assert.equal(h.finished().status,"INCONCLUSIVE");assert.equal(h.probeCancels(),1);
  assert.equal(h.calls.length,1);await pause();
});
test('unlinked early XHR does not read or retain its body',async()=>{
  const h=harness();h.attach();h.sendFetch(createURL,h.createBody);
  const poison=new Proxy({},{get(){throw Error("read unrelated body");},getPrototypeOf(){throw Error("inspected unrelated body");}});
  h.sendXHR("https://elsewhere.example.test/private",poison);
  await h.settled();
  h.sendXHR(signedURL,h.testFile);await h.settled();
  assert.equal(h.finished().status,"CALIBRATED");
});
test('two visible forms cannot be armed',()=>{
  const h=harness();h.doc.querySelectorAll=()=>[{...h.editor},{...h.editor}];
  assert.equal(h.sample().reason,"original-target-changed");assert.equal(h.finished().status,"INCONCLUSIVE");
});
