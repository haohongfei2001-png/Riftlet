'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, 'page-evidence-helper.js'), 'utf8');
const ASSET = '11111111-2222-4333-8444-555555555555';
const SECRET = 'PRIVATE_SENTINEL_MUST_NEVER_LEAVE_PAGE';
function fixture() {
  let forbiddenCalls = 0;
  const card = {isConnected:true, getAttribute:()=>SECRET};
  const image = {isConnected:true, alt:SECRET, closest:()=>card};
  const progress = {getAttribute:key=>key==='aria-valuenow'?'40':'正在上传 '+SECRET};
  card.querySelectorAll=()=>[progress];
  const identity = {assetID:ASSET, operationID:SECRET, target:{logicalDraftIdentity:{id:SECRET},url:SECRET}, attempt:1};
  const op = {identity, name:SECRET, card, image, progressNode:progress,
    inputCount:1,inputSequence:2,inputObservedAtMS:10,fileHashVerified:true,hashSequence:3,committed:true,
    uploading:true,startDisqualified:false,
    uploadStart:{version:1,signal:'correlatedProgress',inputCount:1,inputSequence:2,startSequence:6,
      previousProgress:20,currentProgress:40,startObservedAtMS:20,evidenceID:SECRET},
    proof:{identity,card,image,source:SECRET,completed:9,completedAtMS:30}};
  const generation = {operations:new Map([[SECRET,op]]),form:{contains:node=>node===card},next:null};
  for(const method of ['sample','valid','observe','invalidate','drain'])Object.defineProperty(generation,method,{get(){forbiddenCalls++;throw Error(SECRET);}});
  const registry={head:generation};
  Object.defineProperty(registry,'stopRootMonitors',{get(){forbiddenCalls++;throw Error(SECRET);}});
  const context=vm.createContext({__riftletWebAcceptance20261027v9:registry,performance:{now:()=>50,timeOrigin:1000}});
  const helper=vm.runInContext('('+source+')',context);
  return {helper,context,registry,generation,op,progress,card,forbiddenCalls:()=>forbiddenCalls};
}

test('extracts original timeline and equality booleans without exporting identifiers or calling observers',()=>{
  const f=fixture();Object.freeze(f.op);Object.freeze(f.op.uploadStart);Object.freeze(f.op.proof);Object.freeze(f.generation);Object.freeze(f.registry);
  const result=f.helper({assetID:ASSET.toLowerCase()}),r=result.operations[0];
  assert.equal(result.status,'OK');assert.equal(result.operationsRead,1);assert.equal(r.inputCount,1);
  assert.equal(r.inputObservedAtMS,10);assert.equal(r.startObservedAtMS,20);assert.equal(r.proofCompletedAtMS,30);
  assert.equal(r.inputBeforeStart,true);assert.equal(r.startBeforeFinal,true);assert.equal(r.proofIdentityIsOriginal,true);
  assert.equal(r.progressValueNow,40);assert.equal(r.originalProgressNode,true);assert.equal(r.exactProgressLabel,true);
  assert.equal(f.forbiddenCalls(),0);assert.equal(JSON.stringify(result).includes(SECRET),false);assert.equal(JSON.stringify(result).includes(ASSET),false);
});

test('absent registry, missing asset and malformed selectors return fixed diagnostics',()=>{
  const f=fixture();assert.equal(f.helper({assetID:SECRET}).status,'INVALID_ASSET_SELECTOR');
  assert.equal(f.helper({assetID:'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'}).status,'ASSET_NOT_OBSERVED');
  delete f.context.__riftletWebAcceptance20261027v9;assert.equal(f.helper({assetID:ASSET}).status,'NO_V9_REGISTRY');
});

test('nonfinite clocks and raw progress strings are not exported as evidence',()=>{
  const f=fixture();f.context.performance.now=()=>Infinity;f.op.proof.completedAtMS=NaN;
  f.progress.getAttribute=key=>key==='aria-valuenow'?SECRET:'unrelated';
  const result=f.helper({assetID:ASSET}),r=result.operations[0];
  assert.equal(result.nowMS,null);assert.equal(r.proofCompletedAtMS,null);assert.equal(r.progressValueNow,null);
  assert.equal(r.startBeforeFinal,false);assert.equal(r.exactProgressLabel,false);assert.equal(JSON.stringify(result).includes(SECRET),false);
});

test('generation, operation and result bounds cannot silently claim a complete snapshot',()=>{
  const generations=fixture();let tail=generations.generation;
  for(let i=0;i<40;i++){tail.next={operations:new Map(),next:null};tail=tail.next;}
  let result=generations.helper({assetID:ASSET});assert.equal(result.generationsRead,32);assert.equal(result.status,'BOUND_REACHED');
  const ops=fixture();for(let i=0;i<40;i++)ops.generation.operations.set(String(i),ops.op);
  result=ops.helper({assetID:ASSET});assert.equal(result.operationsRead,32);assert.equal(result.operations.length,32);assert.equal(result.boundedOut,true);
  const matches=fixture();matches.generation.next={operations:new Map(Array.from({length:32},(_,i)=>[String(i),matches.op])),next:null};
  result=matches.helper({assetID:ASSET});assert.equal(result.operations.length,32);assert.equal(result.status,'BOUND_REACHED');
});

test('cycles and thrown DOM reads emit only fixed incomplete-diagnostic status',()=>{
  const f=fixture();f.generation.next=f.generation;
  assert.equal(f.helper({assetID:ASSET}).status,'GENERATION_CYCLE');
  f.generation.next=null;f.card.querySelectorAll=()=>{throw Error(SECRET);};
  const result=f.helper({assetID:ASSET});assert.equal(result.status,'DIAGNOSTIC_UNAVAILABLE');assert.equal(JSON.stringify(result).includes(SECRET),false);
});

test('stored start and retained proof remain explicitly historical rather than revalidated admission',()=>{
  const f=fixture();f.op.startDisqualified=true;f.op.invalid=true;f.op.uploading=false;f.card.querySelectorAll=()=>[];
  const r=f.helper({assetID:ASSET}).operations[0];
  assert.equal(r.hasStoredStart,true);assert.equal(r.startDisqualified,true);assert.equal(r.invalid,true);
  assert.equal(r.uploadingSnapshot,false);assert.equal(r.progressCount,0);assert.equal(r.hasProof,true);
  assert.equal(r.state,undefined);assert.equal(r.safeToRetry,undefined);assert.equal(f.forbiddenCalls(),0);
});
