import test from 'node:test';
import assert from 'node:assert/strict';
import {isOriginalObservation, protocolRevision} from './observation.mjs';
test('only the matching original invocation can reach provider evidence evaluation', () => {
  const x = {protocolRevision, attempt: 1, providerRevision: 2, hostBundle: 'fixtureHost',
    pid: 22, session: 's', clickGeneration: 'g', processBirth: 'pid-birth', window: 'w', tab: 't', providerID: 'fixture', programDigest: 'a'.repeat(64),
    route: '/draft', surface: 'chat', mode: 'image', document: 'd', composer: 'c', draftEpoch: 'e',
    operation: 'op', invocation: 'i', originalSHA256: 'b'.repeat(64), payloadSHA256: 'c'.repeat(64)};
  assert.equal(isOriginalObservation(x, {...x}), true);
  for (const key of Object.keys(x)) {
    assert.equal(isOriginalObservation(x, {...x, [key]: null}), false, key);
    assert.equal(isOriginalObservation(x, {...x, [key]: x[key] + '1'}), false, key);
  }
  for (const key of ['programDigest', 'originalSHA256', 'payloadSHA256']) {
    const malformed = {...x, [key]:'a'};
    assert.equal(isOriginalObservation(malformed, malformed), false);
  }
  assert.equal(isOriginalObservation(Object.create(x), Object.create(x)), false);
  assert.equal(isOriginalObservation({}, {}), false);
});
