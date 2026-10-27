'use strict';
// Original shipped closures, synthetic DOM only. No browser/network/GUI claims.
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const legacy = fs.readFileSync(path.join(__dirname, '../../Sources/RiftletAdapters/Resources/legacy-web-observe.js'), 'utf8');
const native = {applicationID:'com.google.Chrome', sessionID:'4242:1', windowID:'17', tabID:'19'};
function fixture(version, options) {
  // Keep the historical fixture independent of the current page's evolving ABI.
  const original = fs.readFileSync(path.join(__dirname, '../RiftletAdaptersTests/Fixtures/LegacyWeb', version+'.js'), 'utf8');
  const make = ['v8','v9'].includes(version) ? require('../RiftletAdaptersTests/Fixtures/LegacyWeb/'+version+'-dom-fixture.cjs') : require('./legacy-dom-fixture.cjs');
  const f = make(original, version, options);
  f.legacy = vm.runInContext('('+legacy+')', f.context);
  f.read = op => f.legacy(op.command('observe'), native);
  f.registry = () => f.context['__riftletWebAcceptance20261027'+version];
  return f;
}
async function ready(version, options) {
  const f=fixture(version, options), op=f.bind(); f.stage(op); f.commit(op); await f.settle();
  const view=f.makeCard(op); f.finish(view); await f.settle();
  assert.equal(f.observe(op).state,'attached'); return {f,op,view};
}
for (const version of ['v6','v7','v8','v9']) {
  test(version+' historical positive progress never becomes schema2 or uploadStarted', async () => {
    const f=fixture(version),op=f.bind();f.stage(op);f.commit(op);await f.settle();f.makeCard(op);
    const stored=f.registry().head.operations.get(op.identity.operationID);
    assert.ok(stored.started>0);assert.equal(stored.inputCount,1);
    // Even accidental new fields on retained state cannot upgrade old evidence.
    stored.uploadStarted=true;stored.uploadStartEvidence={version:1,inputCount:1};
    const result=f.read(op), observation=result.observation;
    assert.equal(result.schemaVersion,1);assert.equal(observation.state,'inputTriggered');
    assert.equal(observation.isUploading,true);assert.equal(observation.exactImageIdentity,false);
    assert.deepEqual(Object.keys(observation).sort(),['identity','state','exactImageIdentity','belongsToOriginalDraft',
      'hasError','isUploading','attachmentAbsent','automaticRetryExcluded','attachmentID'].sort());
    assert.equal(f.input.inputCount,1);
  });
  test(version+' original committed proof survives background and rearm without new input', async () => {
    const {f,op}=await ready(version,{thread:true}), before=f.observe(op);
    f.windowEvent('blur'); f.focus(false); f.document.visibilityState='hidden';
    const background=f.read(op);
    assert.equal(background.observation.state,'attached');
    assert.equal(background.observation.attachmentID,before.attachmentID);
    assert.equal(background.provenance.evidenceID,(['v8','v9'].includes(version)?'W5':'W4')+'-legacy-'+version+'-original-observer');
    f.focus(true); f.document.visibilityState='visible'; const fresh=f.target();
    assert.notEqual(fresh.draftGeneration,op.target.draftGeneration);
    assert.equal(f.read(op).observation.state,'attached'); assert.equal(f.input.inputCount,1);
  });
  test(version+' exact original late failure preserves attachment identity and never retry authority', async () => {
    const {f,op,view}=await ready(version), before=f.read(op).observation;
    view.card.attrs['data-state']='error';
    f.queueMutation([{type:'attributes',target:view.card,attributeName:'data-state'}]);
    const failure=f.read(op).observation;
    assert.equal(failure.state,'invalidated'); assert.equal(failure.hasError,true);
    assert.equal(failure.belongsToOriginalDraft,true); assert.equal(failure.exactImageIdentity,true);
    assert.equal(failure.attachmentID,before.attachmentID); assert.equal(failure.automaticRetryExcluded,false);
    for(let i=0;i<3;i++) assert.equal(f.read(op).observation.attachmentID,before.attachmentID);
    assert.equal(f.input.inputCount,1);
  });
  test(version+' mismatched operation fields and foreign native context cannot borrow proof', async () => {
    const {f,op}=await ready(version);
    for(const field of ['operationID','assetID','attempt','assetSHA256']) {
      const command=op.command('observe'); command.identity={...op.identity,[field]:field==='attempt'?2:'wrong'};
      const result=f.legacy(command,native).observation;
      assert.equal(result.state,'invalidated'); assert.equal(result.exactImageIdentity,false);
    }
    assert.equal(f.legacy(op.command('observe'),{...native,tabID:'20'}).observation.belongsToOriginalDraft,false);
    for(const field of ['adapterID','surface','applicationID','sessionID','tabID','documentID','composerID','draftGeneration','windowID']) {
      const target={...op.target,[field]:'wrong'}, identity={...op.identity,target};
      assert.equal(f.legacy({action:'observe',target,identity},native),null);
    }
    const target={...op.target,logicalDraftIdentity:{profileID:'unproven',id:'different'}}, identity={...op.identity,target};
    assert.equal(f.legacy({action:'observe',target,identity},native),null);
    assert.equal(f.input.inputCount,1);
  });
  test(version+' failure of original operation does not change a different committed attachment', async () => {
    const {f,op,view}=await ready(version);
    const second=f.bind('33333333-3333-4333-8333-333333333333');
    f.stage(second);f.commit(second);await f.settle();const other=f.makeCard(second);f.finish(other);await f.settle();
    const before=f.read(second).observation;assert.equal(before.state,'attached');
    view.card.attrs['data-state']='error';f.queueMutation([{type:'attributes',target:view.card,attributeName:'data-state'}]);
    assert.equal(f.read(op).observation.hasError,true);
    const after=f.read(second).observation;
    assert.equal(after.state,'attached');assert.equal(after.attachmentID,before.attachmentID);
    assert.equal(after.hasError,false);assert.equal(f.input.inputCount,2);
  });
  test(version+' invalidation, missing proof and uncommitted original never gain authority', async () => {
    const {f,op}=await ready(version);
    const original=f.registry().head.operations.get(op.identity.operationID);
    original.proof=null; assert.equal(f.read(op).observation.exactImageIdentity,false);
    f.navigationEvent('navigate'); assert.equal(f.read(op).observation.belongsToOriginalDraft,false);
    const g=fixture(version), staged=g.bind();g.stage(staged);
    assert.equal(g.read(staged).observation.state,'invalidated');assert.equal(g.input.inputCount,0);
  });
  test(version+' only observe is routed; missing original registry does not install anything', () => {
    const f=fixture(version), before=Object.keys(f.context);
    for(const action of ['captureTarget','validate','begin','chunk','commit','discard'])
      assert.equal(f.legacy({action},native),null);
    const target={...native,adapterID:'chatgpt-web',surface:'webChat',documentID:'absent',composerID:'absent',draftGeneration:'absent'};
    assert.equal(f.legacy({action:'observe',target,identity:{target}},native),null);
    assert.deepEqual(Object.keys(f.context),before);assert.equal(f.input.inputCount,0);
  });
}
test('v7 stopped root remains invalidated; original proof cannot be reconstructed or revived', async () => {
  const {f,op}=await ready('v7',{thread:true}), state=f.registry().head;
  f.registry().stopRootMonitors();
  assert.equal(state.operations.get(op.identity.operationID).proof,null);
  for(let i=0;i<3;i++) {
    const result=f.read(op).observation;
    assert.equal(result.state,'invalidated');assert.equal(result.belongsToOriginalDraft,false);
    assert.equal(result.exactImageIdentity,false);
  }
  assert.equal(state.operations.get(op.identity.operationID).proof,null);assert.equal(f.input.inputCount,1);
});
test('v8 persisted operation keeps original proof and identity without restoring stopped monitors', async () => {
  const f=fixture('v8',{thread:true}),id=f.businessID.slice('local-chatgpt:'.length);
  const next=f.makeFibers(id);f.form.__reactFiber$fixture=next.leaf;
  const op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);f.finish(view);await f.settle();
  const before=JSON.stringify(op.identity), result=f.read(op);
  assert.equal(op.target.logicalDraftIdentity.profileID,'chatgpt-composer-react-persisted-20261027-v1');
  assert.equal(result.schemaVersion,1);assert.equal(result.observation.state,'attached');
  assert.equal(JSON.stringify(result.observation.identity),before);
  assert.equal(result.provenance.evidenceID,'W5-legacy-v8-original-observer');
  f.registry().stopRootMonitors();
  for(let i=0;i<3;i++) {
    const invalid=f.read(op);assert.equal(invalid.schemaVersion,1);
    assert.equal(invalid.observation.state,'invalidated');assert.equal(invalid.observation.exactImageIdentity,false);
    assert.equal(invalid.observation.belongsToOriginalDraft,false);
  }
  assert.equal(f.registry().head.operations.get(op.identity.operationID).proof,null);
  assert.equal(JSON.stringify(op.identity),before);assert.equal(f.input.inputCount,1);
});
test('v8 duplicate frozen target in an older registry cannot borrow authority', async () => {
  const {f,op}=await ready('v8');
  f.context.__riftletWebAcceptance20261027v6={head:f.registry().head};
  const result=f.read(op);assert.equal(result.schemaVersion,1);
  assert.equal(result.observation.state,'invalidated');assert.equal(result.observation.exactImageIdentity,false);
  assert.equal(f.input.inputCount,1);
});
test('broken historical callback and ambiguous duplicate registries fail closed', async () => {
  const {f,op}=await ready('v6'), state=f.registry().head;
  const sample=state.sample;state.sample=()=>{throw Error('private-detail');};
  const result=f.read(op);assert.equal(result.observation.exactImageIdentity,false);
  assert.equal(JSON.stringify(result).includes('private-detail'),false);state.sample=sample;
  f.context.__riftletWebAcceptance20261027v7={head:state};
  assert.equal(f.read(op).observation.exactImageIdentity,false);
  assert.equal(f.input.inputCount,1);
});

test('v9 genuine stored start is downgraded to schema1 while original completion and late error survive', async () => {
  const f=fixture('v9'),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);
  view.progress.attrs['aria-valuenow']='40';
  f.mutate([{type:'attributes',target:view.progress,attributeName:'aria-valuenow',oldValue:'20'}]);
  const original=f.observe(op);assert.equal(original.state,'uploadStarted');assert.ok(original.uploadStart);
  const stored=f.registry().head.operations.get(op.identity.operationID), start=JSON.stringify(stored.uploadStart);
  for(let i=0;i<3;i++) {
    const result=f.read(op);assert.equal(result.schemaVersion,1);assert.equal(result.observation.state,'inputTriggered');
    assert.equal(result.observation.exactImageIdentity,false);assert.equal(result.observation.automaticRetryExcluded,false);
    assert.equal(JSON.stringify(result).includes('uploadStart'),false);
  }
  assert.equal(JSON.stringify(stored.uploadStart),start);assert.equal(f.input.inputCount,1);
  f.finish(view);await f.settle();const completed=f.read(op).observation;
  assert.equal(completed.state,'attached');assert.equal(completed.exactImageIdentity,true);
  view.card.attrs['data-state']='error';f.queueMutation([{type:'attributes',target:view.card,attributeName:'data-state'}]);
  const failed=f.read(op).observation;assert.equal(failed.hasError,true);assert.equal(failed.exactImageIdentity,true);
  assert.equal(failed.attachmentID,completed.attachmentID);assert.equal(failed.automaticRetryExcluded,false);
  assert.equal(f.input.inputCount,1);
});

test('v9 indeterminate start rejection stays original but does not block original final proof', async () => {
  const f=fixture('v9'),op=f.bind();f.stage(op);f.commit(op);await f.settle();
  const view=f.makeCard(op,null); // Historical v9 rejects a missing initial aria-valuenow permanently.
  assert.equal(view.progress.getAttribute('aria-valuenow'),null);
  const stored=f.registry().head.operations.get(op.identity.operationID);
  assert.equal(stored.startDisqualified,true);
  for(const value of ['20','40']) {
    view.progress.attrs['aria-valuenow']=value;
    f.mutate([{type:'attributes',target:view.progress,attributeName:'aria-valuenow'}]);
    const result=f.read(op);assert.equal(result.schemaVersion,1);assert.equal(result.observation.state,'inputTriggered');
    assert.equal(result.observation.uploadStart,undefined);assert.equal(stored.startDisqualified,true);
  }
  f.finish(view);await f.settle();assert.equal(f.read(op).observation.state,'attached');assert.equal(f.input.inputCount,1);
});

test('v9 stopped monitor and ambiguous historical target cannot regain final or start authority', async () => {
  const {f,op}=await ready('v9',{thread:true}), state=f.registry().head;
  f.context.__riftletWebAcceptance20261027v8={head:state};
  assert.equal(f.read(op).observation.exactImageIdentity,false);
  delete f.context.__riftletWebAcceptance20261027v8;
  f.registry().stopRootMonitors();
  for(let i=0;i<3;i++) {
    const result=f.read(op);assert.equal(result.schemaVersion,1);assert.equal(result.observation.state,'invalidated');
    assert.equal(result.observation.belongsToOriginalDraft,false);assert.equal(result.observation.exactImageIdentity,false);
    assert.equal(result.observation.uploadStart,undefined);
  }
  assert.equal(state.operations.get(op.identity.operationID).proof,null);assert.equal(f.input.inputCount,1);
});
