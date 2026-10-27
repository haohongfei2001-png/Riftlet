'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'progress-diagnostic-probe.js'),'utf8');
const ASSET='11111111-2222-4333-8444-555555555555',SECRET='PRIVATE_RAW_NAME_AND_TEXT';
function fixture() {
  let listener=null,observer=null,timeout=null,removed=0,disconnected=0,cleared=0,now=0,shown=false,raw=null;
  const node={getAttribute:key=>key==='aria-valuenow'?raw:key==='aria-label'?'正在上传 '+SECRET:'progressbar'};
  const card={getAttribute:()=>SECRET,querySelectorAll:()=>[node],contains:n=>n===node};
  const input={files:[{name:SECRET,size:99,type:'image/png'}]};
  const op={identity:{assetID:ASSET},name:SECRET,bytes:99,inputCount:0,inputSequence:0,committed:false};
  const generation={operations:new Map([['private',op]]),input,form:{querySelectorAll:()=>shown?[card]:[]},next:null};
  for(const name of ['sample','valid','observe','drain'])Object.defineProperty(generation,name,{get(){throw Error('MUST_NOT_CALL_ORIGINAL');}});
  const context=vm.createContext({__riftletWebAcceptance20261027v9:{head:generation},performance:{now:()=>++now},
    document:{addEventListener:(type,fn)=>{listener=fn;},removeEventListener:(type,fn)=>{assert.equal(fn,listener);listener=null;removed++;}},
    MutationObserver:class{constructor(fn){observer=fn;}observe(){}disconnect(){disconnected++;}},
    setTimeout:fn=>{timeout=fn;return 1;},clearTimeout:()=>{cleared++;}});
  const install=vm.runInContext('('+source+')',context);
  const api=()=>context.__riftletRound5ProgressProbe;
  return {install,api,op,generation,node,input,
    inputEvent:()=>listener?.({target:input}),otherEvent:()=>listener?.({target:{}}),
    inputReady:()=>{op.committed=true;op.inputCount=1;op.inputSequence=2;},
    show:()=>{shown=true;observer([{type:'childList',target:generation.form,addedNodes:[card],removedNodes:[]}]);},
    value:value=>{const oldValue=raw;raw=value;observer([{type:'attributes',target:node,attributeName:'aria-valuenow',oldValue}]);},
    timeout:()=>timeout(),cleanup:()=>({removed,disconnected,cleared}),
    manyRecords:()=>observer(Array.from({length:1025},()=>({type:'childList',target:card,removedNodes:[],addedNodes:[]})))};
}

test('selected new input records missing -> finite progress and oldValue history with no raw identity',()=>{
  const f=fixture();assert.equal(f.install({assetID:ASSET}).installed,true);f.otherEvent();assert.equal(f.api().query().state,'ARMED');
  f.inputReady();f.inputEvent();f.show();f.value('0');f.value('20');
  const q=f.api().query();assert.equal(q.state,'BOUND');
  assert.ok(q.events.some(e=>e.event==='mutation_snapshot'&&e.valueKind==='missing'&&e.nodeIsOriginal));
  const values=q.events.filter(e=>e.event==='progress_attribute');
  assert.equal(values[0].oldValueKind,'missing');assert.equal(values[0].value,0);assert.equal(values[1].oldValue,0);assert.equal(values[1].value,20);
  assert.equal(JSON.stringify(q).includes(SECRET),false);assert.equal(JSON.stringify(q).includes(ASSET),false);
  assert.equal(f.op.startDisqualified,undefined);assert.equal(f.op.uploadStart,undefined);
  const stopped=f.api().stop();assert.equal(stopped.state,'STOPPED');assert.deepEqual(f.cleanup(),{removed:1,disconnected:1,cleared:1});
});

test('previous committed operation refuses installation and uncorrelated input is never accepted',()=>{
  const f=fixture();f.op.committed=true;assert.equal(f.install({assetID:ASSET}).reason,'ASSET_ALREADY_DISPATCHED');
  const g=fixture();g.install({assetID:ASSET});g.inputEvent();assert.equal(g.api().query().reason,'INPUT_NOT_CORRELATED');
});

test('time, event and record bounds stop and release only probe resources',()=>{
  const timed=fixture();timed.install({assetID:ASSET});timed.timeout();assert.equal(timed.api().query().reason,'TIME_BOUND');
  const capped=fixture();capped.install({assetID:ASSET});capped.inputReady();capped.inputEvent();capped.show();
  for(let i=0;i<200;i++)capped.value('20');assert.equal(capped.api().query().reason,'EVENT_BOUND');assert.equal(capped.api().query().events.length,160);
  const records=fixture();records.install({assetID:ASSET});records.inputReady();records.inputEvent();records.manyRecords();
  assert.equal(records.api().query().reason,'RECORD_BOUND');assert.deepEqual(records.cleanup(),{removed:1,disconnected:1,cleared:1});
});

test('invalid numeric state is redacted, query copies logs and repeated input stops the diagnostic',()=>{
  const f=fixture();f.install({assetID:ASSET});f.inputReady();f.inputEvent();f.show();f.value(SECRET);
  const q=f.api().query();assert.equal(q.events.at(-1).valueKind,'invalid');assert.equal(q.events.at(-1).value,null);
  q.events[0].event=SECRET;assert.equal(JSON.stringify(f.api().query()).includes(SECRET),false);
  f.inputEvent();assert.equal(f.api().query().reason,'ADDITIONAL_INPUT');
});
