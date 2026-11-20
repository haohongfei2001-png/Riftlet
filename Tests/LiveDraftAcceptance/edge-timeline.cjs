'use strict';

const {performance} = require('node:perf_hooks');
const {setTimeout: delay} = require('node:timers/promises');

// Both sources observe the original operation. No click, setter, retry, or
// product acceptance decision belongs to the diagnostic.
async function observeEdgeTimeline({run, readOperation, operation, png, targetSHA256,
  durationMs = 12_000, intervalMs = 250}) {
  if (!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(operation) ||
      ![png, targetSHA256].every(digest => /^[0-9a-f]{64}$/.test(digest)) ||
      !Number.isInteger(durationMs) || durationMs < 1 || durationMs > 15_000 ||
      !Number.isInteger(intervalMs) || intervalMs < 100 || intervalMs > 2_000) {
    throw new Error('invalid Edge observation identity or duration');
  }
  const id = operation.toUpperCase();
  const filename = 'riftlet-' + id + '.png';
  const start = performance.now();
  const elapsed = () => Math.round(performance.now() - start);
  const samples = [];
  const expired = Symbol('observation deadline');
  // A late read can settle, but the run issues no subsequent call once timed out.
  async function bounded(read) {
    const remaining = durationMs - (performance.now() - start);
    if (remaining <= 0) throw expired;
    let timer;
    try {
      const deadline = new Promise((_, reject) => {
        timer = setTimeout(() => reject(expired), Math.ceil(remaining));
      });
      const value = await Promise.race([Promise.resolve().then(read), deadline]);
      // A synchronous collector can delay timer delivery past the deadline.
      if (performance.now() - start >= durationMs) throw expired;
      return value;
    } finally { clearTimeout(timer); }
  }
  let stop = 'observationWindowEnded';
  do {
    const pageReadStartMs = elapsed();
    let page;
    try {
      page = await bounded(() => run.edgePreviewSample(filename));
    } catch (error) {
      stop = error === expired ? 'pageReadTimedOut' : 'pageObservationUnavailable';
      break;
    }
    const pageReadEndMs = elapsed();
    if (!page?.shape || !/^[0-9a-f]{64}$/.test(page.lockedDraftSHA256)) {
      stop = 'pageIdentityUnavailable';
      break;
    }
    const sample = {pageReadStartMs,pageReadEndMs,shape:page.shape};
    samples.push(sample);
    let record;
    try {
      record = await bounded(() => readOperation(id, png));
    } catch (error) {
      stop = error === expired ? 'storeReadTimedOut' : 'storeObservationUnavailable';
      break;
    }
    if (record?.build !== '53' || record.bundle !== 'com.microsoft.edgemac' ||
        record.operation !== id || record.png !== png || record.targetSHA256 !== targetSHA256 ||
        record.lockedDraftSHA256 !== page.lockedDraftSHA256 ||
        record.attempted !== 1 || !Number.isInteger(record.storedStartCount) ||
        !Number.isInteger(record.handledRows) || record.storedStartCount < 0 || record.handledRows < 0 ||
        !Number.isFinite(record.lastStoreUpdateSeconds) || record.lastStoreUpdateSeconds < 0 ||
        (record.storedStartCount === 0 ? record.storedStartAfterCreationSeconds !== null :
          !Number.isFinite(record.storedStartAfterCreationSeconds) || record.storedStartAfterCreationSeconds < 0)) {
      stop = 'originalOperationUnverified';
      break;
    }
    Object.assign(sample, {storeReadEndMs:elapsed(), storedStartCount:record.storedStartCount,
      handledRows:record.handledRows, storeUpdatedAfterCreationMs:Math.round(1000 * record.lastStoreUpdateSeconds),
      storedStartAfterCreationMs:record.storedStartAfterCreationSeconds === null ? null :
        Math.round(1000 * record.storedStartAfterCreationSeconds)});
    if (record.storedStartCount > 1 || record.handledRows > 1) { stop = 'duplicateStoreRows'; break; }
    if (record.storedStartCount === 1) { stop = 'startRowObserved'; break; }
    if (durationMs - elapsed() < intervalMs) break;
    await delay(intervalMs);
  } while (elapsed() < durationMs);
  return {clockOrigin:'first observation after operation identification', stop, samples};
}

module.exports = {observeEdgeTimeline};
