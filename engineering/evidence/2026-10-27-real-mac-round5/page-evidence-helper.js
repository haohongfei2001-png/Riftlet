/* LAB ONLY — bounded read-only snapshot, not bundled or auto-executed.
 * Invoke through the already authorized, exact-tab MAIN nonce bridge:
 *   riftletRound5PageEvidence({assetID: '<original private asset UUID>'})
 * No capture/validate/sample/observe, input, retry, request, listener or DOM write.
 * Do not serialize the registry or operation objects. This return value is an
 * explicit allowlist; original receipt/target identities belong in private DB
 * evidence. A snapshot does not grant start, completion, retry or production use.
 */
function riftletRound5PageEvidence(options) {
  'use strict';
  const MAX_GENERATIONS = 32, MAX_OPERATIONS = 32, MAX_MATCHES = 32;
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const finite = value => typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null;
  const sequence = value => Number.isSafeInteger(value) && value >= 0 ? value : null;
  const progressValue = raw => {
    if (typeof raw !== 'string' || !/^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/.test(raw)) return null;
    const value = Number(raw);
    return Number.isFinite(value) && value >= 0 && value <= 100 ? value : null;
  };
  const result = {schemaVersion: 1, helper: 'riftlet-round5-page-evidence-v1',
    mode: 'READ_ONLY_DIAGNOSTIC', status: 'OK', registryPresent: false,
    clock: 'document-performance-milliseconds', nowMS: null, timeOriginMS: null,
    generationsRead: 0, operationsRead: 0, boundedOut: false, operations: []};
  if (!options || !uuid.test(options.assetID || '')) {
    result.status = 'INVALID_ASSET_SELECTOR'; return result;
  }
  try {
    result.nowMS = finite(performance.now()); result.timeOriginMS = finite(performance.timeOrigin);
    const registry = globalThis.__riftletWebAcceptance20261027v9;
    result.registryPresent = !!registry;
    if (!registry) { result.status = 'NO_V9_REGISTRY'; return result; }
    const wanted = options.assetID.toLowerCase(), seen = new Set();
    let generation = registry.head;
    while (generation && result.generationsRead < MAX_GENERATIONS) {
      if (seen.has(generation)) { result.boundedOut = true; result.status = 'GENERATION_CYCLE'; break; }
      seen.add(generation); const generationIndex = result.generationsRead++;
      let operationIndex = 0;
      for (const op of Map.prototype.values.call(generation.operations)) {
        if (operationIndex >= MAX_OPERATIONS) { result.boundedOut = true; break; }
        const index = operationIndex++; result.operationsRead++;
        if (typeof op.identity?.assetID !== 'string' || op.identity.assetID.toLowerCase() !== wanted) continue;
        if (result.operations.length >= MAX_MATCHES) { result.boundedOut = true; break; }
        const card = op.card, image = op.image, start = op.uploadStart, proof = op.proof;
        const progress = card ? card.querySelectorAll('[role=progressbar]') : [];
        const only = progress.length === 1 ? progress[0] : null;
        const inputAt = finite(op.inputObservedAtMS), startAt = finite(start?.startObservedAtMS);
        const finalAt = finite(proof?.completedAtMS);
        result.operations.push({generationIndex, operationIndex: index, attempt: sequence(op.identity.attempt),
          inputCount: sequence(op.inputCount), inputSequence: sequence(op.inputSequence), inputObservedAtMS: inputAt,
          hashVerified: op.fileHashVerified === true, hashSequence: sequence(op.hashSequence),
          committed: op.committed === true, invalid: op.invalid === true, error: op.error === true,
          uploadingSnapshot: op.uploading === true, startDisqualified: op.startDisqualified === true,
          hasStoredStart: !!start, startSignalMatches: start?.version === 1 && start?.signal === 'correlatedProgress',
          startInputCount: sequence(start?.inputCount), startInputSequence: sequence(start?.inputSequence),
          startSequence: sequence(start?.startSequence), startObservedAtMS: startAt,
          previousProgress: finite(start?.previousProgress), currentProgress: finite(start?.currentProgress),
          inputBeforeStart: inputAt !== null && startAt !== null && inputAt < startAt,
          hasProof: !!proof, proofPending: op.proofPending === true,
          proofCompletedSequence: sequence(proof?.completed), proofCompletedAtMS: finalAt,
          startBeforeFinal: startAt !== null && finalAt !== null && startAt < finalAt,
          proofIdentityIsOriginal: !!proof && proof.identity === op.identity,
          proofNodesAreOriginal: !!proof && proof.card === card && proof.image === image,
          originalCardConnected: !!card?.isConnected && !!generation.form?.contains(card),
          originalImageConnected: !!image?.isConnected && image.closest('[role=button]') === card,
          exactCardLabel: !!card && card.getAttribute('aria-label') === op.name,
          exactImageLabel: !!image && image.alt === op.name,
          progressCount: progress.length, originalProgressNode: !!only && only === op.progressNode,
          exactProgressLabel: !!only && only.getAttribute('aria-label') === '正在上传 ' + op.name,
          progressValueNow: only ? progressValue(only.getAttribute('aria-valuenow')) : null});
      }
      generation = generation.next;
    }
    if (generation) result.boundedOut = true;
    if (result.boundedOut && result.status === 'OK') result.status = 'BOUND_REACHED';
    if (!result.boundedOut && result.operations.length === 0) result.status = 'ASSET_NOT_OBSERVED';
  } catch {
    // Never return exception messages, object serialization or partially exposed
    // page data. Fixed diagnostic failure is not an upload/failure conclusion.
    result.status = 'DIAGNOSTIC_UNAVAILABLE';
  }
  return result;
}
