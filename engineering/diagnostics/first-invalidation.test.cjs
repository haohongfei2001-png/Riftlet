'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path'),Module=require('node:module');
const {transform,restore,record,KEY}=require('./first-invalidation.cjs');
const base=fs.readFileSync(path.join(__dirname,'../../Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js'),'utf8'),variant=transform(base);
// Reuse only the existing deterministic DOM fixture; do not register its full suite.
const fixtureFile=path.join(__dirname,'../../Tests/WebPageProgram/acceptance-program.test.cjs');
const mod=new Module(fixtureFile,module);mod.filename=fixtureFile;mod.paths=module.paths;
mod._compile(fs.readFileSync(fixtureFile,'utf8').split("test('bundled program")[0]+'\nmodule.exports=fixture;',fixtureFile);
const fixture=()=>mod.exports({programSource:variant});
const cause=(f,op)=>f.context[KEY]?.records.get(op.identity.operationID);
test('exact baseline and monitor bodies restored; wrong baseline rejected',()=>{
 assert.equal(restore(variant),base);assert.throws(()=>transform(base+'\n'),/BASE_SOURCE_MISMATCH/);
 new vm.Script('('+variant+')');
});
test('bound node removal records actual first branch once; subsequent cause cannot replace it',async()=>{
 const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const v=f.makeCard(op);
 f.mutate([{type:'childList',target:f.form,removedNodes:[v.card],addedNodes:[]}]);
 assert.equal(cause(f,op).reason,'MUTATION_ATTACHMENT_REMOVED');assert.equal(f.observe(op).state,'invalidated');
 const first=cause(f,op);f.windowEvent('pagehide');assert.equal(cause(f,op),first);assert.equal(f.input.inputCount,1);
 assert.equal(first.nodes.card.connected,true); // Removal record, even if node was reinserted before callback.
 assert.ok(Number.isFinite(first.atMS));assert.equal(first.identity,op.identity);
});
test('same-name replacement is a distinct sample branch',async()=>{
 const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const v=f.makeCard(op);
 f.form.children=f.form.children.filter(n=>n!==v.card);f.makeCard(op);
 assert.equal(cause(f,op).reason,'SAMPLE_NODE_REPLACED');assert.equal(f.observe(op).state,'invalidated');
});
test('binding invalidation wins over later markBad and uncommitted revocation',()=>{
 const f=fixture(),op=f.bind();f.stage(op);f.context.location.href='https://chatgpt.com/changed';f.observe(op);
 assert.equal(cause(f,op).reason,'BINDING_SNAPSHOT_REJECTED');assert.equal(f.input.inputCount,0);
});
test('normal one-input completion has no fabricated invalidation',async()=>{
 const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const v=f.makeCard(op);f.finish(v);await f.settle();
 assert.equal(f.observe(op).state,'attached');assert.equal(cause(f,op),undefined);assert.equal(f.input.inputCount,1);
});
test('broken diagnostic store cannot suppress original invalidation',async()=>{
 const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const v=f.makeCard(op);
 Object.defineProperty(f.context,KEY,{value:{version:1,records:new Proxy(new Map(),{get(){throw Error('fixture');}}),nodes:new WeakMap()}});
 f.mutate([{type:'childList',target:f.form,removedNodes:[v.card],addedNodes:[]}]);assert.equal(f.observe(op).state,'invalidated');
});
test('64-record bound; scalar snapshot excludes payload and node content',()=>{
 const c=vm.createContext({Map,WeakMap,performance:{now:()=>123}});vm.runInContext('globalThis.record='+record.toString(),c);
 for(let i=0;i<70;i++)c.record({identity:{operationID:String(i)},card:{isConnected:true,textContent:'PRIVATE',src:'PRIVATE'},file:'PRIVATE',name:'PRIVATE'},'SAMPLE_NODE_REPLACED',4);
 const d=c[KEY];assert.equal(d.records.size,64);assert.equal(d.dropped,6);assert.ok(!JSON.stringify([...d.records.values()]).includes('PRIVATE'));
});
test('MAIN readout matches full identity, omits target and sanitizes unknown fields',async()=>{
 const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const v=f.makeCard(op);
 f.mutate([{type:'childList',target:f.form,removedNodes:[v.card],addedNodes:[]}]);
 const read=vm.runInContext('('+fs.readFileSync(path.join(__dirname,'original-operation-snapshot.js'),'utf8')+')',f.context);
 const native={applicationID:'com.google.Chrome',sessionID:'4242:1',windowID:'17',tabID:'19'};
 cause(f,op).nodes.card.url='PRIVATE';cause(f,op).text='PRIVATE';
 const result=read({identity:op.identity},native);
 assert.equal(result.firstInvalidation.reason,'MUTATION_ATTACHMENT_REMOVED');assert.ok(!JSON.stringify(result).includes('PRIVATE'));
 assert.ok(!JSON.stringify(result).includes(op.identity.operationID));assert.ok(!JSON.stringify(result).includes('logicalDraftIdentity'));
 cause(f,op).identity={...op.identity,attempt:99};assert.equal(read({identity:op.identity},native).firstInvalidation,null);
});
test('late error markBad cannot overtake binding loss inside currentMember',async()=>{
 const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const v=f.makeCard(op);f.finish(v);await f.settle();
 const state=f.context.__riftletWebAcceptance20261027v13.tail,original=state.operations.get(op.identity.operationID);
 f.context.location.href='https://chatgpt.com/changed';state.markBad(original,true,'SAMPLE_ASSOCIATED_ERROR');
 assert.equal(cause(f,op).reason,'BINDING_SNAPSHOT_REJECTED');
});
