import test from 'node:test';
import assert from 'node:assert/strict';
import {isOriginalObservation, protocolRevision} from './observation.mjs';
test('only the matching original invocation can reach provider evidence evaluation', () => {
  const x = {protocolRevision, attempt: 1, providerRevision: 2, hostBundle: 'fixtureHost',
    processBirth: 'pid-birth', window: 'w', tab: 't', providerID: 'fixture', programDigest: 'digest',
    route: '/draft', surface: 'chat', mode: 'image', document: 'd', composer: 'c', draftEpoch: 'e',
    operation: 'op', invocation: 'i', originalSHA256: 'original', payloadSHA256: 'payload'};
  assert.equal(isOriginalObservation(x, {...x}), true);
  for (const key of Object.keys(x)) {
    assert.equal(isOriginalObservation(x, {...x, [key]: null}), false, key);
    assert.equal(isOriginalObservation(x, {...x, [key]: x[key] + '1'}), false, key);
  }
  assert.equal(isOriginalObservation({}, {}), false);
});
