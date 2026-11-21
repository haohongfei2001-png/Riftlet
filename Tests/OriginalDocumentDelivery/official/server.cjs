'use strict';
const assert=require('node:assert/strict');
const {createHash,randomBytes}=require('node:crypto');
const fs=require('node:fs'),http=require('node:http'),path=require('node:path');
const [resource,expected,outdir]=process.argv.slice(2);
assert.ok(resource&&outdir&&path.isAbsolute(resource)&&path.isAbsolute(outdir)&&/^[a-f0-9]{64}$/.test(expected),
  'usage: node server.cjs <absolute installed JS> <expected SHA256> <new absolute output directory>');
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const code=fs.readFileSync(resource); assert.equal(hash(code),expected,'installed JS hash differs');
const begin='// RIFTLET_ORIGINAL_RECEIVER_BEGIN',end='// RIFTLET_ORIGINAL_RECEIVER_END';
const js=code.toString('utf8');assert.equal(js.split(begin).length,2);assert.equal(js.split(end).length,2);
const receiver=js.slice(js.indexOf(begin)+begin.length,js.indexOf(end));assert.match(receiver,/function bindOriginalReceiver\(/);
const files={'':['text/html',fs.readFileSync(path.join(__dirname,'page.html'),'utf8').replace('PRODUCT_SRI','sha256-'+Buffer.from(expected,'hex').toString('base64'))],
  'product.js':['text/javascript',code],
  'page.js':['text/javascript',fs.readFileSync(path.join(__dirname,'page.js'))],
  'receiver.js':['text/javascript',receiver+'\nwindow.bindOriginalReceiver=bindOriginalReceiver;']};
const families={};
for(const family of ['chrome','edge']) {
  const token=randomBytes(24).toString('hex');
  families[token]={family,phase:'new',status:'NOT_RUN',createdUTC:new Date().toISOString(),events:[],
    sourceSHA256:expected,receiverSHA256:hash(receiver),keyboard:'NOT_RUN',routeChecks:[],nativeIdentity:'NOT_VERIFIED_BY_PAGE',
    scope:'Same URL, independent top-level QA Documents. Product receiver excerpt; semantic q and PNG. Separate trusted q field.'};
}
fs.mkdirSync(outdir,{mode:0o700});
function persist(run) {
  const name=path.join(outdir,run.family+'.json'),temp=name+'.tmp';
  fs.writeFileSync(temp,JSON.stringify(run,null,2)+'\n',{mode:0o600});fs.renameSync(temp,name);
}
for(const run of Object.values(families)) persist(run);
const uuid=s=>typeof s==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(s);
const pngSHA=hash(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=','base64'));
const zeros={semantic:0,setter:0,input:0,change:0,submit:0},ones={semantic:1,setter:1,input:1,change:1,submit:0};
function expectedSnapshot(s,doc,editor,counts) {
  assert.ok(uuid(doc)&&uuid(editor));assert.equal(s.doc,doc);assert.equal(s.editor,editor);
  assert.equal(s.topLevel,true);assert.deepEqual(s.counts,counts);assert.deepEqual(s.selection,[6,10,'forward']);
  assert.equal(s.oldCard,true);assert.equal(s.originalText,counts.semantic===0);
  assert.equal(s.appendedQ,counts.semantic===1);assert.equal(s.fileCount,counts.setter);
}
function address(a,doc,editor) {
  assert.ok(uuid(a.operation));assert.equal(a.doc,doc);assert.equal(a.editor,editor);
}
function positive(write,base) {
  const {doc,editor}=base;address(write.address,doc,editor);assert.equal(write.sha256,pngSHA);
  const d=write.delivered;assert.equal(d.status,'DELIVERED');
  for(const field of ['setters','inputEvent','changeEvent','text','selection'])assert.equal(d[field],true);
  expectedSnapshot(d.afterFile,doc,editor,{...ones,semantic:0});
  expectedSnapshot(d.after,doc,editor,ones);
}
function noteKey(run,k,doc) {
  assert.equal(k.doc,doc);
  for(const key of ['up','down','typed','observed'])assert.equal(typeof k[key],'boolean');
  assert.equal(k.observed,k.up&&k.typed&&k.down);
  if(k.observed)run.keyboard='OBSERVED_TRUSTED_Q';
}
function update(run,kind,data) {
  if(kind==='route') {
    assert.ok(['new','replace'].includes(run.phase));
    assert.ok(uuid(data.doc)&&uuid(data.editor)&&uuid(data.witness));
    assert.equal(data.error,'PAGE_ROUTE_UNSUPPORTED');assert.equal(data.action,'pinTarget');
    assert.equal(data.sourceSHA256,expected);assert.match(data.urlSHA256,/^[a-f0-9]{64}$/);
    assert.deepEqual(data.delta,{setter:0,input:0,change:0,submit:0,keyDown:0,keyUp:0});
    expectedSnapshot(data.before,data.doc,data.editor,zeros);
    expectedSnapshot(data.after,data.doc,data.editor,zeros);
    if(run.phase==='replace')assert.equal(data.urlSHA256,run.routeChecks[0].urlSHA256);
    assert.ok(!run.routeChecks.some(previous=>previous.doc===data.doc));
    run.routeChecks.push({...data,utc:new Date().toISOString()});persist(run);return;
  }
  const phaseFor={original:'new',barrier:'held',complete:'replace'};
  assert.equal(run.phase,phaseFor[kind],'out of order');
  if(kind==='barrier') {
    assert.equal(data.doc,run.pending.doc);assert.deepEqual(data.pending,run.pending);
    assert.equal(data.registryHit,true);assert.equal(data.heldCurrent,true);run.phase='replace';
  }
  else {
    const base=data.baseline;expectedSnapshot(base,base.doc,base.editor,zeros);
    assert.equal(run.routeChecks.at(-1)?.doc,base.doc);noteKey(run,data.keyboard,base.doc);
    if(kind==='original') {
      address(data.pending,base.doc,base.editor);assert.equal(data.heldCurrent,true);positive(data.write,base);
      assert.notEqual(data.write.address.operation,data.pending.operation);
      run.pending=data.pending;run.firstOperation=data.write.address.operation;run.phase='held';run.status='PARTIAL';
    } else {
      assert.notEqual(base.doc,run.pending.doc);assert.notEqual(base.editor,run.pending.editor);
      assert.equal(base.navigation,'reload');assert.deepEqual(data.old.attempted,run.pending);assert.equal(data.old.registryHit,false);
      assert.equal(data.old.status,'ORIGINAL_OPERATION_ABSENT');expectedSnapshot(data.old.after,base.doc,base.editor,zeros);
      positive(data.fresh,base);assert.ok(![run.firstOperation,run.pending.operation].includes(data.fresh.address.operation));
      run.firstWitnessBoundary={
        originalDocument:run.pending.doc,replacementDocument:data.fresh.address.doc,
        originalEditor:run.pending.editor,replacementEditor:data.fresh.address.editor,
        pendingOriginalOperation:run.pending.operation,freshReplacementOperation:data.fresh.address.operation,
        oldRegistryPresentInA:true,oldRegistryPresentInB:false,
        newGrantInB:'delivered on B only',nativeCorrelation:'requires independent before/after receipt',
        observation:'A new grant first acquired after replacement addresses B. This QA page did not reproduce a product misdelivery or a physical click.'};
      run.phase='done';run.status='PASS';
    }
  }
  run.events.push({kind,utc:new Date().toISOString(),data});persist(run);
}
let origin;
const server=http.createServer(async(req,res)=>{
  function reply(status,body,type='application/json') {
    res.writeHead(status,{'Content-Type':type+'; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff',
      'Referrer-Policy':'no-referrer','Content-Security-Policy':"default-src 'self'; img-src data:; style-src 'unsafe-inline'; form-action 'none'; frame-ancestors 'none'"});
    res.end(type==='application/json'?JSON.stringify(body):body);
  }
  if(req.headers.host!==origin.slice(7))return reply(403,{error:'unknown host'});
  const match=/^\/([a-f0-9]{48})\/([a-z.]*)$/.exec(req.url||'');
  const run=match&&families[match[1]],kind=match&&match[2];
  if(!run)return reply(404,{error:'unknown QA session'});
  if(req.method==='GET'&&Object.hasOwn(files,kind))return reply(200,files[kind][1],files[kind][0]);
  if(req.method==='GET'&&kind==='state')return reply(200,{family:run.family,phase:run.phase,pending:run.pending,sourceSHA256:expected});
  if(req.method!=='POST'||req.headers.origin!==origin||!['route','original','barrier','complete'].includes(kind)||
     !req.headers['content-type']?.startsWith('application/json'))return reply(403,{error:'not permitted'});
  const chunks=[];let size=0;
  try {
    for await(const chunk of req) {
      size+=chunk.length;if(size>16384)return reply(413,{error:'too large'});chunks.push(chunk);
    }
    const data=JSON.parse(Buffer.concat(chunks));update(run,kind,data);
    return reply(200,{phase:run.phase,status:run.status});
  } catch(e) {
    // Do not export arbitrary HTTP input or client error descriptions.
    if(run.phase!=='done') {
      run.status='FAIL';run.events.push({kind,result:'REJECTED',utc:new Date().toISOString()});persist(run);
    }
    return reply(409,{error:'failed QA checks'});
  }
});
server.on('connect',(_,s)=>s.destroy());server.on('upgrade',(_,s)=>s.destroy());
server.listen(0,'127.0.0.1',()=>{
  origin='http://127.0.0.1:'+server.address().port;
  const urls=Object.fromEntries(Object.entries(families).map(([token,run])=>[run.family,origin+'/'+token+'/']));
  console.log(JSON.stringify({urls,output:outdir,sourceSHA256:expected,receiverSHA256:hash(receiver)}));
});
