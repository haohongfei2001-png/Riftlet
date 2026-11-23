'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {sha} = require('./fixture.cjs');
const {payloadAssessment} = require('./run.cjs');

async function assess(source, reply, entries = []) {
  let lookups = 0;
  const request = {id:'local-request', inlineEntryBytes:entries};
  const facts = await payloadAssessment(async (method, params) => {
    assert.equal(method, 'Network.getRequestPostData');
    assert.equal(params.requestId, request.id);
    lookups++;
    if (reply instanceof Error) throw reply;
    return reply;
  }, request, source);
  assert.equal(lookups, 1);
  return facts;
}

test('base64 represents raw binary, including non-UTF-8 bytes', async () => {
  const bytes = Buffer.from([0x89, 0x50, 0xff, 0x00]);
  const result = await assess(bytes, {postData:bytes.toString('base64'), base64Encoded:true});
  assert.equal(result.returnedBodyBytes, bytes.length);
  assert.equal(result.observedPUTBodySHA256, sha(bytes));
});

test('UTF-8 text is counted and compared after decoding', async () => {
  const text = '本地', bytes = Buffer.from(text);
  const result = await assess(bytes, {postData:text, base64Encoded:false});
  assert.equal(result.returnedBodyBytes, bytes.length);
  assert.equal(result.observedPUTBodySHA256, sha(bytes));
});

test('no post data or equal-size different bytes do not certify the source', async () => {
  const bytes = Buffer.from('one');
  for (const reply of [new Error('No post data available'), {postData:'two', base64Encoded:false}]) {
    const result = await assess(bytes, reply);
    assert.equal(result.payloadHashUnavailable, true);
    assert.equal(result.observedPUTBodySHA256, null);
  }
});

test('a full set of identical inline bytes can independently establish the digest', async () => {
  const bytes = Buffer.from('split bytes');
  const entries = [bytes.subarray(0, 5), bytes.subarray(5)].map(part => part.toString('base64'));
  const result = await assess(bytes, new Error('No post data available'), entries);
  assert.equal(result.lookupResult, 'NO_POST_DATA');
  assert.equal(result.observedPUTBodySHA256, sha(bytes));
});

test('contradictory inline and lookup results cannot certify a digest in either direction', async () => {
  const original = Buffer.from('file'), other = Buffer.from('also');
  for (const [inline, lookup] of [[original, other], [other, original], [original, original.subarray(0, 2)]]) {
    const result = await assess(original, {postData:lookup.toString('base64'), base64Encoded:true},
      [inline.toString('base64')]);
    assert.equal(result.inlineMatchesSource, inline.equals(original));
    assert.equal(result.lookupMatchesSource, lookup.equals(original));
    assert.equal(result.representationsDisagree, true);
    assert.equal(result.payloadHashUnavailable, true);
    assert.equal(result.observedPUTBodySHA256, null);
  }
});

test('identical complete inline and lookup bytes agree on the digest', async () => {
  const original = Buffer.from([0xff, 0x00, 0xef]), encoded = original.toString('base64');
  const result = await assess(original, {postData:encoded, base64Encoded:true}, [encoded]);
  assert.equal(result.representationsDisagree, false);
  assert.equal(result.observedPUTBodySHA256, sha(original));
});
