'use strict';
// VM fixtures only: no browser, file input, user data or production admission.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(__dirname + '/original-operation-snapshot.js', 'utf8');
function fixture(extra = '') {
  const context = vm.createContext({});
  vm.runInContext(source + `
    const secret = 'PRIVATE_SENTINEL_DO_NOT_EXPORT';
    const target = {adapterID:'chatgpt-web',surface:'webChat',applicationID:'chrome',sessionID:secret,
      windowID:'w',tabID:'t',documentID:secret,composerID:secret,draftGeneration:secret,
      logicalDraftIdentity:{profileID:secret,id:secret}};
    const identity={operationID:'11111111-1111-1111-1111-111111111111',assetID:'22222222-2222-2222-2222-222222222222',attempt:1,assetSHA256:'a'.repeat(64),target};
    const command={identity:JSON.parse(JSON.stringify(identity))}, native={...target};
    const op={identity,committed:true,invalid:true,error:false,inputCount:1,uploading:true,
      name:secret,proof:{private:secret},card:{isConnected:false,textContent:secret},image:{isConnected:false,complete:true,src:secret}};
    const state={operations:new Map([[identity.operationID,op]]),next:null,continuityEvents:{outsideInteraction:2}};
    for(const key of ['valid','drain','sample','observationIdentityValid','revokeInput']) state[key]=()=>{throw Error('state function called')};
    Object.defineProperty(state,'target',{get(){throw Error('state getter called')}});
    const registry={head:state,tail:state,count:1,rootMonitors:new Map([[{}, {diagnostics:{reason:secret,commits:3}}]])};
    globalThis.__riftletWebAcceptance20261027v13=registry;
    ${extra}
  `, context);
  return JSON.parse(vm.runInContext('JSON.stringify(riftletOriginalOperationSnapshot(command,native))', context));
}
test('distinguishes absent world from retained MAIN operation without invoking state functions', () => {
  assert.equal(fixture('delete globalThis.__riftletWebAcceptance20261027v13').status, 'registryAbsent');
  const found=fixture(); assert.equal(found.status,'matched');assert.equal(found.flags.invalid,true);
  assert.equal(found.numbers.inputCount,1);assert.equal(found.retired,false);
});
test('retired tombstone readable, with no proof body or private text exported', () => {
  const found=fixture('state.retired=true;op.proofAudit={private:secret};');
  assert.equal(found.retired,true);assert.equal(found.proofAuditPresent,true);
  assert.equal(found.rootDiagnostics[0].reason,'other');
  assert.ok(!JSON.stringify(found).includes('PRIVATE_SENTINEL'));
  assert.ok(!JSON.stringify(found).includes('assetSHA256'));
});
test('original identity and outer receiver must match exactly', () => {
  for(const mutation of ["command.identity.assetID='33333333-3333-3333-3333-333333333333'",'command.identity.attempt=2',"command.identity.assetSHA256='b'.repeat(64)","command.identity.target.draftGeneration='other'", "command.identity.target.logicalDraftIdentity.id='other'"]) {
    assert.equal(fixture(mutation).status,'identityMismatch');
  }
  assert.equal(fixture("native.tabID='other'").status,'nativeMismatch');
  assert.equal(fixture("command.target={...target,composerID:'other'}").status,'invalidRequest');
  assert.equal(fixture("command.identity.operationID='33333333-3333-3333-3333-333333333333'").status,'operationAbsent');
});
test('cycles, bounds and duplicate original identities are rejected', () => {
  assert.equal(fixture('state.next=state').status,'generationCycle');
  assert.equal(fixture('let tail=state;for(let i=0;i<512;i++){tail.next={operations:new Map(),next:null};tail=tail.next;}').status,'generationBound');
  assert.equal(fixture('state.next={operations:new Map([[identity.operationID,op]]),next:null}').status,'duplicateIdentity');
});
test('registry accessor and malformed scalar data cannot leak or execute', () => {
  assert.equal(fixture("Object.defineProperty(globalThis,'__riftletWebAcceptance20261027v13',{get(){throw Error('getter')}})").status,'registryUnrecognized');
  const found=fixture("op.progressValue=Infinity;op.loaded=secret;Object.defineProperty(op,'error',{get(){throw Error('getter')}})");
  assert.equal(found.numbers.progressValue,null);assert.equal(found.numbers.loaded,null);assert.equal(found.flags.error,null);
});
