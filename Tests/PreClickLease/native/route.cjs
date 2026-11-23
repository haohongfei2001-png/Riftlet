'use strict';
const fs=require('node:fs'),http=require('node:http'),path=require('node:path'),crypto=require('node:crypto');
const assert=require('node:assert/strict');
const [source,output]=process.argv.slice(2);
assert.ok(source && output && path.isAbsolute(source) && path.isAbsolute(output));
const bytes=fs.readFileSync(source),text=bytes.toString(),a='// RIFTLET_ORIGINAL_RECEIVER_BEGIN',b='// RIFTLET_ORIGINAL_RECEIVER_END';
assert.equal(text.split(a).length,2);assert.equal(text.split(b).length,2);
const receiver=text.slice(text.indexOf(a)+a.length,text.indexOf(b));
const hash=x=>crypto.createHash('sha256').update(x).digest('hex');
const runs=Object.fromEntries(['chrome','edge'].map(f=>[crypto.randomBytes(24).toString('hex'),{family:f,sourceSHA256:hash(bytes),receiverSHA256:hash(receiver)}]));
const page='<!doctype html><html lang="en"><meta charset="utf-8"><title>Preparing Riftlet QA</title><h1>Riftlet pre-click QA</h1><label for="draft">Isolated QA draft</label><textarea id="draft">QA fixture only</textarea><p>Document <output id="doc"></output></p><section id="grants" hidden></section><p id="state">Waiting for original document</p><script src="./runtime.js"></script></html>';
const runtime=receiver+`
(() => {
const doc=crypto.randomUUID(), editor=document.querySelector('#draft');
const range=editor.value;
document.querySelector('#doc').textContent=doc;
function announce() {
 if(document.visibilityState!=='visible'||!document.hasFocus())return;
 const lease=bindOriginalReceiver(editor,()=>document.querySelector('#draft')===editor&&editor.value===range,true);
 if(!lease.current())return;
 window.removeEventListener('focus',announce);
 document.removeEventListener('visibilitychange',announce);
 // The marker belongs to this one document and can be queried read-only by native code.
 // If the document loses focus/identity, a second grant is never created.
 const published='Riftlet QA '+doc;
 const grants=document.querySelector('#grants');
 const entries=Array.from({length:4},(_,i)=>{
  const bound=bindOriginalReceiver(editor,()=>lease.current(),true);
  const label=document.createElement('output');label.id='g'+i;
  if(bound.current())label.textContent=crypto.randomUUID();grants.append(label);
  return {bound,label};
 });
 document.title=published;
 document.querySelector('#state').textContent='Original receiver ready';
 function retire() { for(const {bound,label} of entries){bound.close();label.textContent='';}document.title='Retired QA receiver';document.querySelector('#state').textContent='Receiver retired';lease.close(); }
 window.addEventListener('blur',retire,{once:true});
 window.addEventListener('pagehide',retire,{once:true});
 document.addEventListener('visibilitychange',()=>{if(document.visibilityState!=='visible')retire()});
 window.navigation?.addEventListener('currententrychange',retire,{once:true});
 new MutationObserver(()=>{if(document.title===published&&!lease.current())retire()}).observe(document.documentElement,{subtree:true,childList:true});
 fetch('./armed',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({doc})}).catch(()=>{});
}
window.addEventListener('focus',announce);document.addEventListener('visibilitychange',announce);announce();
})();`;
let origin;
const server=http.createServer(async(req,res)=>{
 function reply(code,type,body) {res.writeHead(code,{'content-type':type,'cache-control':'no-store','x-content-type-options':'nosniff',
   'content-security-policy':"default-src 'self'; object-src 'none'; form-action 'none'; frame-ancestors 'none'",'referrer-policy':'no-referrer'});res.end(body);}
 if(req.headers.host!==origin.slice(7))return reply(403,'text/plain','host');
 const m=/^\/([a-f0-9]{48})\/(|runtime\.js|armed)$/.exec(req.url);if(!m||!runs[m[1]])return reply(404,'text/plain','absent');
 const run=runs[m[1]];
 if(req.method==='GET' && m[2]==='')return reply(200,'text/html;charset=utf-8',page);
 if(req.method==='GET' && m[2]==='runtime.js')return reply(200,'text/javascript;charset=utf-8',runtime);
 if(req.method==='POST'&&m[2]==='armed'&&req.headers.origin===origin&&req.headers['content-type']==='application/json'){
  try {const chunks=[];let n=0;for await(const chunk of req){n+=chunk.length;if(n>256)return reply(413,'text/plain','body');chunks.push(chunk);}
   const {doc}=JSON.parse(Buffer.concat(chunks));assert.match(doc,/^[\da-f]{8}-[\da-f]{4}-4[\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/);
   const receipt={...run,doc,receivedUTC:new Date().toISOString()};fs.writeFileSync(path.join(output,run.family+'-'+doc+'-armed.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600,flag:'wx'});return reply(200,'text/plain','OK');
  } catch {return reply(409,'text/plain','invalid');}
 }
 return reply(403,'text/plain','forbidden');
});
server.listen(0,'127.0.0.1',()=>{origin='http://127.0.0.1:'+server.address().port;console.log(JSON.stringify(Object.fromEntries(Object.entries(runs).map(([nonce,r])=>[r.family,origin+'/'+nonce+'/']))));});
