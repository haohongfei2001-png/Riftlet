'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {observeEdgeTimeline} = require('./edge-timeline.cjs');

const operation = '6e8c6238-d95f-4978-9b84-7485c7e1dabd', png = 'a'.repeat(64), targetSHA256 = 'b'.repeat(64);
const original = {operation:operation.toUpperCase(), png, targetSHA256, lockedDraftSHA256:'c'.repeat(64), storedStartAfterCreationSeconds:null, build:'53', bundle:'com.microsoft.edgemac',
  storedStartCount:0, handledRows:0, attempted:1, lastStoreUpdateSeconds:0.1};
const options = {operation, png, targetSHA256, durationMs:35,
  run:{edgePreviewSample: async name => {
    assert.equal(name, 'riftlet-' + original.operation + '.png');
    return {shape:{matchingPreviewCount:1,pixelWidth:123},lockedDraftSHA256:original.lockedDraftSHA256};
  }},
  readOperation:async (id, digest) => {
    assert.equal(id,original.operation); assert.equal(digest,png); return original;
  }};

test('matching preview with no start remains a timed observation',async()=>{
  const {stop,samples} = await observeEdgeTimeline(options);
  assert.equal(stop,'observationWindowEnded');
  assert.equal(samples.length,1);
  assert.equal(samples[0].storedStartCount,0);
  assert.ok(samples[0].pageReadStartMs <= samples[0].pageReadEndMs);
  assert.ok(samples[0].pageReadEndMs <= samples[0].storeReadEndMs);
  assert.equal(samples[0].storeUpdatedAfterCreationMs,100);
});

test('reports receipt appearance only for the original operation and target',async()=>{
  for (const [change,expected] of [
    [{storedStartCount:1,storedStartAfterCreationSeconds:0.05},'startRowObserved'], [{storedStartCount:2,storedStartAfterCreationSeconds:0.05},'duplicateStoreRows'],
    [{storedStartCount:1,targetSHA256:png},'originalOperationUnverified'],
    [{lockedDraftSHA256:png},'originalOperationUnverified'],
    [{operation:'different'},'originalOperationUnverified'], [{attempted:2},'originalOperationUnverified'],
  ]) {
    const result = await observeEdgeTimeline({...options,readOperation:async()=>({...original,...change})});
    assert.equal(result.stop,expected);
  }
});

test('losing the original page stops before reading a different receipt',async()=>{
  let reads=0;
  const result=await observeEdgeTimeline({...options,run:{edgePreviewSample:async()=>{throw Error();}},
    readOperation:async()=>{reads++;return original;}});
  assert.equal(result.stop,'pageObservationUnavailable');
  assert.deepEqual(result.samples,[]);
  assert.equal(reads,0);
});

test('a lost store read returns its page-only sample and stops without retry', async()=>{
  let calls=0;
  const result=await observeEdgeTimeline({...options,readOperation:()=>{calls++;return new Promise(()=>{});}});
  assert.equal(calls,1);
  assert.equal(result.stop,'storeReadTimedOut');
  assert.equal(result.samples.length,1);
  assert.equal(result.samples[0].storedStartCount,undefined);
});

test('stored START time is independent of later store updates',async()=>{
  const result=await observeEdgeTimeline({...options,readOperation:async()=>({...original,
    storedStartCount:1,storedStartAfterCreationSeconds:0.05})});
  assert.equal(result.samples[0].storeUpdatedAfterCreationMs,100);
  assert.equal(result.samples[0].storedStartAfterCreationMs,50);
});
