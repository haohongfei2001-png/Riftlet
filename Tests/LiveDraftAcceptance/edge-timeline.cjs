'use strict';

const {performance} = require('node:perf_hooks');
const {setTimeout: delay} = require('node:timers/promises');

// Both sources observe the original operation. No click, setter, retry, or
// product acceptance decision belongs to the diagnostic.
async function observeEdgeTimeline({run, readOperation, operation, png, targetSHA256,
  durationMs = 12_000, intervalMs = 250}) {
  if (!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(operation) ||
      ![png, targetSHA256].every(digest => /^[0-9a-f]{64}$/.test(digest)) ||
      !Number.isInteger(durationMs) || durationMs < 0 || durationMs > 15_000 ||
      !Number.isInteger(intervalMs) || intervalMs < 100 || intervalMs > 2_000) {
    throw new Error('invalid Edge observation identity or duration');
  }
  const id = operation.toUpperCase();
  const filename = 'riftlet-' + id + '.png';
  const start = performance.now();
  const elapsed = () => Math.round(performance.now() - start);
  const samples = [];
  let stop = 'observationWindowEnded';
  do {
    const pageReadStartMs = elapsed();
    let shape;
    try {
      shape = await run.edgePreviewShape(filename);
    } catch {
      stop = 'pageObservationUnavailable';
      break;
    }
    const pageReadEndMs = elapsed();
    let record;
    try {
      record = await readOperation(id, png);
    } catch {
      stop = 'storeObservationUnavailable';
      break;
    }
    if (record?.build !== '53' || record.bundle !== 'com.microsoft.edgemac' ||
        record.operation !== id || record.png !== png || record.targetSHA256 !== targetSHA256 ||
        record.attempted !== 1 || !Number.isInteger(record.storedStartCount) ||
        !Number.isInteger(record.handledRows) || record.storedStartCount < 0 || record.handledRows < 0 ||
        !Number.isFinite(record.lastStoreUpdateSeconds) || record.lastStoreUpdateSeconds < 0) {
      stop = 'originalOperationUnverified';
      break;
    }
    const sample = {pageReadStartMs, pageReadEndMs, storeReadEndMs:elapsed(), shape,
      storedStartCount:record.storedStartCount, handledRows:record.handledRows,
      storeUpdatedAfterCreationMs:Math.round(1000 * record.lastStoreUpdateSeconds)};
    samples.push(sample);
    if (record.storedStartCount > 1 || record.handledRows > 1) { stop = 'duplicateStoreRows'; break; }
    if (record.storedStartCount === 1) { stop = 'startRowObserved'; break; }
    if (durationMs - elapsed() < intervalMs) break;
    await delay(intervalMs);
  } while (elapsed() <= durationMs);
  return {clockOrigin:'first observation after operation identification', stop, samples};
}

module.exports = {observeEdgeTimeline};
