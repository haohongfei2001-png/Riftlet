'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, 'page-evidence-helper.js'), 'utf8');
const ASSET = '11111111-2222-4333-8444-555555555555';
const OPERATION = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const SELECTOR = {assetID:ASSET,operationID:OPERATION,attempt:1};
const SECRET = 'PRIVATE_SENTINEL_MUST_NEVER_LEAVE_PAGE';
function fixture(version=13) {
  let forbiddenCalls = 0;
  const card = {isConnected:true, getAttribute:()=>SECRET};
  const image = {isConnected:true, alt:SECRET, closest:()=>card};
  const progress = {getAttribute:key=>key==='aria-valuenow'?'40':'正在上传 '+SECRET};
  card.querySelectorAll=()=>[progress];
  const identity = {assetID:ASSET, operationID:OPERATION, target:{logicalDraftIdentity:{id:SECRET},url:SECRET}, attempt:1};
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
  const context=vm.createContext({['__riftletWebAcceptance20261027v'+version]:registry,performance:{now:()=>50,timeOrigin:1000}});
  const helper=vm.runInContext('('+source+')',context);
  return {helper,context,registry,generation,op,progress,card,forbiddenCalls:()=>forbiddenCalls};
}

test('extracts original timeline and equality booleans without exporting identifiers or calling observers',()=>{
  const f=fixture();Object.freeze(f.op);Object.freeze(f.op.uploadStart);Object.freeze(f.op.proof);Object.freeze(f.generation);Object.freeze(f.registry);
  const result=f.helper({...SELECTOR,assetID:ASSET.toLowerCase()}),r=result.operations[0];
  assert.equal(result.status,'OK');assert.equal(result.operationsRead,1);assert.equal(r.inputCount,1);
  assert.equal(r.inputObservedAtMS,10);assert.equal(r.startObservedAtMS,20);assert.equal(r.proofCompletedAtMS,30);
  assert.equal(r.inputBeforeStart,true);assert.equal(r.startBeforeFinal,true);assert.equal(r.proofIdentityIsOriginal,true);
  assert.equal(r.progressValueNow,40);assert.equal(r.originalProgressNode,true);assert.equal(r.exactProgressLabel,true);
  assert.equal(f.forbiddenCalls(),0);assert.equal(JSON.stringify(result).includes(SECRET),false);assert.equal(JSON.stringify(result).includes(ASSET),false);assert.equal(JSON.stringify(result).includes(OPERATION),false);
});

test('absent registry and malformed or incomplete original selectors return fixed diagnostics',()=>{
  const f=fixture();
  for(const selector of [{assetID:ASSET},{...SELECTOR,operationID:SECRET},{...SELECTOR,attempt:0},{...SELECTOR,attempt:1.5}])
    assert.equal(f.helper(selector).status,'INVALID_ORIGINAL_SELECTOR');
  delete f.context.__riftletWebAcceptance20261027v13;assert.equal(f.helper(SELECTOR).status,'NO_SUPPORTED_REGISTRY');
});

test('nonfinite clocks and raw progress strings are not exported as evidence',()=>{
  const f=fixture();f.context.performance.now=()=>Infinity;f.op.proof.completedAtMS=NaN;
  f.progress.getAttribute=key=>key==='aria-valuenow'?SECRET:'unrelated';
  const result=f.helper(SELECTOR),r=result.operations[0];
  assert.equal(result.nowMS,null);assert.equal(r.proofCompletedAtMS,null);assert.equal(r.progressValueNow,null);
  assert.equal(r.startBeforeFinal,false);assert.equal(r.exactProgressLabel,false);assert.equal(JSON.stringify(result).includes(SECRET),false);
});

test('generation, operation and result bounds cannot silently claim a complete snapshot',()=>{
  const generations=fixture();let tail=generations.generation;
  for(let i=0;i<40;i++){tail.next={operations:new Map(),next:null};tail=tail.next;}
  let result=generations.helper(SELECTOR);assert.equal(result.generationsRead,32);assert.equal(result.status,'BOUND_REACHED');
  const ops=fixture();for(let i=0;i<40;i++)ops.generation.operations.set(String(i),{identity:{...ops.op.identity,attempt:2}});
  result=ops.helper(SELECTOR);assert.equal(result.operationsRead,32);assert.equal(result.operations.length,1);assert.equal(result.boundedOut,true);
});

test('cycles and thrown DOM reads emit only fixed incomplete-diagnostic status',()=>{
  const f=fixture();f.generation.next=f.generation;
  assert.equal(f.helper(SELECTOR).status,'GENERATION_CYCLE');
  f.generation.next=null;f.card.querySelectorAll=()=>{throw Error(SECRET);};
  const result=f.helper(SELECTOR);assert.equal(result.status,'DIAGNOSTIC_UNAVAILABLE');assert.equal(JSON.stringify(result).includes(SECRET),false);
});

test('stored start and retained proof remain explicitly historical rather than revalidated admission',()=>{
  const f=fixture();f.op.startDisqualified=true;f.op.invalid=true;f.op.uploading=false;f.card.querySelectorAll=()=>[];
  const r=f.helper(SELECTOR).operations[0];
  assert.equal(r.hasStoredStart,true);assert.equal(r.startDisqualified,true);assert.equal(r.invalid,true);
  assert.equal(r.uploadingSnapshot,false);assert.equal(r.progressCount,0);assert.equal(r.hasProof,true);
  assert.equal(r.state,undefined);assert.equal(r.safeToRetry,undefined);assert.equal(f.forbiddenCalls(),0);
});


test('v10 and historical v9 route only the exact asset, operation and attempt without migration',()=>{
  const f=fixture(10),legacy=fixture(9),otherOperation='99999999-8888-4777-8666-555555555555';
  legacy.op.identity.operationID=otherOperation;legacy.op.identity.attempt=2;
  f.context.__riftletWebAcceptance20261027v9=legacy.registry;
  let result=f.helper(SELECTOR);assert.equal(result.status,'OK');assert.equal(result.operations.length,1);assert.equal(result.operations[0].programVersion,10);
  result=f.helper({...SELECTOR,operationID:otherOperation,attempt:2});
  assert.equal(result.status,'OK');assert.equal(result.operations[0].programVersion,9);assert.equal(result.registriesRead,2);
  for(const wrong of [{...SELECTOR,attempt:2},{...SELECTOR,operationID:otherOperation},{...SELECTOR,assetID:otherOperation}]) {
    result=f.helper(wrong);assert.equal(result.status,'ORIGINAL_OPERATION_NOT_OBSERVED');assert.equal(result.operations.length,0);
  }
  assert.equal(f.forbiddenCalls(),0);assert.equal(legacy.forbiddenCalls(),0);
  delete f.context.__riftletWebAcceptance20261027v10;
  result=f.helper({...SELECTOR,operationID:otherOperation.toUpperCase(),attempt:2});
  assert.equal(result.operations[0].programVersion,9);assert.equal(result.status,'OK');
});

test('ambiguous exact operation in both versions refuses instead of choosing the current registry',()=>{
  const f=fixture(10),legacy=fixture(9);f.context.__riftletWebAcceptance20261027v9=legacy.registry;
  const result=f.helper(SELECTOR);assert.equal(result.status,'AMBIGUOUS_ORIGINAL_OPERATION');assert.equal(result.operations.length,0);
  assert.equal(f.forbiddenCalls(),0);assert.equal(legacy.forbiddenCalls(),0);
});


test('v11 current route coexists with untouched exact historical v10 and v9 operations',()=>{
  const current=fixture(11),v10=fixture(10),v9=fixture(9);
  v10.op.identity.attempt=2;v9.op.identity.attempt=3;
  current.context.__riftletWebAcceptance20261027v10=v10.registry;
  current.context.__riftletWebAcceptance20261027v9=v9.registry;
  for(const [attempt,version] of [[1,11],[2,10],[3,9]]) {
    const result=current.helper({...SELECTOR,attempt});assert.equal(result.status,'OK');assert.equal(result.operations.length,1);
    assert.equal(result.operations[0].programVersion,version);assert.equal(result.registriesRead,3);
  }
  assert.equal(current.forbiddenCalls()+v10.forbiddenCalls()+v9.forbiddenCalls(),0);
  v10.op.identity.attempt=1;
  const ambiguous=current.helper(SELECTOR);assert.equal(ambiguous.status,'AMBIGUOUS_ORIGINAL_OPERATION');assert.equal(ambiguous.operations.length,0);
});


test('v13 retained end state distinguishes stored start from final proof without reconstructing old events',()=>{
  const f=fixture(13);f.op.started=4;f.op.hundred=8;f.op.ended=9;f.op.loaded=10;f.op.progressValue=40;
  f.op.startDisqualified=true;f.progress.isConnected=false;f.card.querySelectorAll=()=>[];
  f.card.contains=()=>false;f.progress.getAttribute=key=>key==='aria-valuenow'?'100':SECRET;
  const result=f.helper(SELECTOR),r=result.operations[0];
  assert.equal(r.programVersion,13);assert.equal(r.hasStoredStart,true);assert.equal(r.hasProof,true);
  assert.equal(r.startDisqualified,true);assert.equal(r.sampledProgressValue,40);
  assert.equal(r.boundProgressValueNow,100);assert.equal(r.boundProgressConnected,false);
  assert.equal(r.boundProgressUnderOriginalCard,false);assert.equal(r.progressCount,0);
  assert.equal(r.hundredSequence,8);assert.equal(r.loadedSequence,10);
  assert.equal(r.historicalMutationRecordsAvailable,false);assert.equal(r.disqualificationReason,'NOT_RECORDED');
  assert.equal(f.forbiddenCalls(),0);assert.equal(JSON.stringify(result).includes(SECRET),false);
});

test('v13 and v12 exact routing refuses ambiguous history and never returns raw missing/invalid progress text',()=>{
  const current=fixture(13),old=fixture(12);old.op.identity.attempt=2;
  current.context.__riftletWebAcceptance20261027v12=old.registry;
  for(const [attempt,version] of [[1,13],[2,12]])assert.equal(current.helper({...SELECTOR,attempt}).operations[0].programVersion,version);
  current.progress.getAttribute=()=>null;
  let r=current.helper(SELECTOR).operations[0];assert.equal(r.boundProgressValueKind,'MISSING');assert.equal(r.boundProgressValueNow,null);
  current.progress.getAttribute=()=>SECRET;
  r=current.helper(SELECTOR).operations[0];assert.equal(r.boundProgressValueKind,'INVALID');assert.equal(r.boundProgressValueNow,null);
  old.op.identity.attempt=1;assert.equal(current.helper(SELECTOR).status,'AMBIGUOUS_ORIGINAL_OPERATION');
});
