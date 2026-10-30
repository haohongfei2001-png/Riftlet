/* Read-only original-operation diagnostic. Run in MAIN through the existing
 * nonce receipt envelope. Never an admission, lease refresh or input command. */
function riftletOriginalOperationSnapshot(command, native) {
  'use strict';
  const read = (object, key) => {
    if (!object || (typeof object !== 'object' && typeof object !== 'function')) return undefined;
    const descriptor = Object.getOwnPropertyDescriptor(object, key);
    return descriptor && Object.prototype.hasOwnProperty.call(descriptor, 'value') ? descriptor.value : undefined;
  };
  const result = status => ({schemaVersion: 1, status});
  const targetKeys = ['adapterID', 'surface', 'applicationID', 'sessionID', 'windowID', 'tabID', 'documentID', 'composerID', 'draftGeneration'];
  const logicalEqual = (a, b) => (!a && !b) || (!!a && !!b && read(a, 'profileID') === read(b, 'profileID') && read(a, 'id') === read(b, 'id'));
  const targetEqual = (a, b) => !!a && !!b && targetKeys.every(k => read(a, k) === read(b, k))
    && logicalEqual(read(a, 'logicalDraftIdentity'), read(b, 'logicalDraftIdentity'));
  const identity = read(command, 'identity'), target = read(identity, 'target');
  const uuid = value => typeof value === 'string' && /^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$/.test(value);
  if (!identity || !uuid(read(identity, 'operationID')) || !uuid(read(identity, 'assetID'))
      || !Number.isSafeInteger(read(identity, 'attempt')) || read(identity, 'attempt') < 1
      || !/^[a-f0-9]{64}$/.test(read(identity, 'assetSHA256') || '')
      || !target || targetKeys.some(k => typeof read(target, k) !== 'string' || !read(target, k))
      || read(target, 'adapterID') !== 'chatgpt-web' || read(target, 'surface') !== 'webChat'
      || (read(command, 'target') && !targetEqual(read(command, 'target'), target))) return result('invalidRequest');
  const logical = read(target, 'logicalDraftIdentity');
  if (logical && ['profileID', 'id'].some(k => typeof read(logical, k) !== 'string' || !read(logical, k))) return result('invalidRequest');
  if (['applicationID', 'sessionID', 'windowID', 'tabID'].some(k => read(native, k) !== read(target, k))) return result('nativeMismatch');
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, '__riftletWebAcceptance20261027v13');
  if (!descriptor) return result('registryAbsent');
  const registry = read(globalThis, '__riftletWebAcceptance20261027v13');
  if (!registry) return result('registryUnrecognized');
  const sameIdentity = candidate => !!candidate && ['operationID', 'assetID', 'attempt', 'assetSHA256'].every(k => read(candidate, k) === read(identity, k))
    && targetEqual(read(candidate, 'target'), target);
  const seen = new Set();
  let state = read(registry, 'head'), matched = null, matchedState = null, count = 0;
  while (state) {
    if (seen.has(state)) return result('generationCycle');
    if (count >= 512) return result('generationBound');
    seen.add(state); count++;
    const operations = read(state, 'operations');
    if (!(operations instanceof Map)) return result('registryUnrecognized');
    const op = Map.prototype.get.call(operations, read(identity, 'operationID'));
    if (op) {
      if (!sameIdentity(read(op, 'identity'))) return result('identityMismatch');
      if (matched) return result('duplicateIdentity');
      matched = op; matchedState = state;
    }
    state = read(state, 'next');
  }
  if (!matched) return {...result('operationAbsent'), generations: count};
  const flags = {};
  for (const key of ['committed', 'invalid', 'error', 'fileHashVerified', 'startDisqualified', 'uploading', 'proofPending']) {
    const value = read(matched, key); flags[key] = typeof value === 'boolean' ? value : null;
  }
  const numbers = {};
  for (const key of ['inputCount', 'inputSequence', 'inputObservedAtMS', 'progressValue', 'started', 'hundred', 'ended', 'loaded']) {
    const value = read(matched, key); numbers[key] = typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null;
  }
  const exists = key => !!read(matched, key);
  const continuity = {};
  for (const key of ['outsideInteraction', 'navigate', 'currententrychange']) {
    const value = read(read(matchedState, 'continuityEvents'), key);
    continuity[key] = Number.isSafeInteger(value) && value >= 0 ? value : null;
  }
  // Do not evaluate state getters/methods (target, valid, drain, sample, etc.).
  // Node membership is diagnostic only; never emit node text/attributes/source.
  const card = read(matched, 'card'), image = read(matched, 'image');
  const nodes = {cardPresent: !!card, imagePresent: !!image,
    cardConnected: card ? card.isConnected === true : null,
    imageConnected: image ? image.isConnected === true : null,
    imageComplete: image ? image.complete === true : null};
  const monitors = read(registry, 'rootMonitors'), rootDiagnostics = [];
  if (monitors instanceof Map) {
    let index = 0;
    for (const monitor of Map.prototype.values.call(monitors)) {
      if (index++ >= 4) break;
      const diagnostic = read(monitor, 'diagnostics'), item = {};
      for (const key of ['commits', 'checks', 'elapsedMs', 'maxElapsedMs', 'groups', 'borrowedFrom']) {
        const value = read(diagnostic, key); item[key] = typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null;
      }
      for (const key of ['stopped', 'restored']) {
        const value = read(diagnostic, key); item[key] = typeof value === 'boolean' ? value : null;
      }
      const reason = read(diagnostic, 'reason');
      item.reason = reason == null ? 'none' : ['REENTRANT_COMMIT', 'COMMIT_BOUND', 'CHECK_FAILED', 'DESCRIPTOR_LOST', 'EXPLICIT_STOP', 'OWNER_LOST'].includes(reason) ? reason : 'other';
      rootDiagnostics.push(item);
    }
  }
  // Optional INTERNAL first-cause store. It is volatile, not journal/admission.
  let firstInvalidation = null;
  const diagnostic = read(globalThis, '__riftletFirstInvalidationInternalV1');
  const records = read(diagnostic, 'records');
  if (read(diagnostic, 'version') === 1 && records instanceof Map && records.size <= 64) {
    const entry = Map.prototype.get.call(records, read(identity, 'operationID'));
    if (entry && sameIdentity(read(entry, 'identity'))) {
      const allowedReasons = ["BINDING_INVALIDATE_CALLBACK", "BINDING_MODE_MUTATION", "BINDING_MONITOR_ADMISSION_REJECTED", "BINDING_NAVIGATION_EVENT", "BINDING_REQUIRED_NODE_REMOVED", "BINDING_SEQUENCE_EXHAUSTED", "BINDING_SNAPSHOT_REJECTED", "COMMIT_ASYNC_EXCEPTION", "COMMIT_FINAL_GUARD_REJECTED", "COMMIT_INPUT_COUNT_INVALID", "COMMIT_PNG_SIGNATURE_INVALID", "DISCARD_UNCOMMITTED_OPERATION", "INPUT_EVENT_IDENTITY_INVALID", "INPUT_HASH_EXCEPTION", "INPUT_HASH_OR_BINDING_REJECTED", "MARK_BAD_UNCLASSIFIED", "MUTATION_ATTACHMENT_ATTRIBUTE_CHANGED", "MUTATION_ATTACHMENT_REMOVED", "MUTATION_PROGRESS_AFTER_END", "PROOF_CONTENT_MISMATCH", "PROOF_CONTINUITY_REJECTED", "PROOF_EXCEPTION", "REVOKE_UNCOMMITTED_OPERATION", "SAMPLE_ASSOCIATED_ERROR", "SAMPLE_CARD_DISAPPEARED", "SAMPLE_CARD_OR_INPUT_COUNT_INVALID", "SAMPLE_IMAGE_ERROR", "SAMPLE_IMAGE_IDENTITY_INVALID", "SAMPLE_NODE_REPLACED", "SAMPLE_PROGRESS_STRUCTURE_INVALID", "SAMPLE_PROOF_SOURCE_CHANGED", "SAMPLE_REPEATED_FINAL_LOAD"];
      const reason = read(entry, 'reason'), atMS = read(entry, 'atMS');
      if (allowedReasons.includes(reason) && typeof atMS === 'number' && Number.isFinite(atMS) && atMS >= 0) {
        const safeNumbers = (object, keys) => Object.fromEntries(keys.map(k => {
          const v = read(object, k); return [k, typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : null];
        }));
        const safeFlags = (object, keys) => Object.fromEntries(keys.map(k => {
          const v = read(object, k); return [k, typeof v === 'boolean' ? v : null];
        }));
        firstInvalidation = {reason, atMS, ...safeNumbers(entry, ['sequence']),
          flags: safeFlags(read(entry, 'flags'), ['committed','fileHashVerified','startDisqualified','uploading','proofPending']),
          numbers: safeNumbers(read(entry, 'numbers'), ['inputCount','inputSequence','progressValue','started','hundred','ended','loaded']), nodes: {}};
        for (const key of ['card','image','progress']) {
          const node = read(read(entry, 'nodes'), key);
          firstInvalidation.nodes[key] = node ? {...safeNumbers(node, ['id']), ...safeFlags(node, ['connected'])} : null;
        }
      }
    }
  }
  return {...result('matched'), firstInvalidation, rootDiagnostics, generations: count, retired: read(matchedState, 'retired') === true,
    flags, numbers, continuity, nodes,
    proofPresent: exists('proof'), proofAuditPresent: exists('proofAudit'), uploadStartPresent: exists('uploadStart')};
}
