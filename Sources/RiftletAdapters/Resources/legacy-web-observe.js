/* Read-only compatibility for existing v6/v7/v8 operation registries.
 * Uses each original observer's closures and proofs; never installs, migrates,
 * rearms, grants input, clears a registry or reconstructs missing identity.
 * v7/v8 explicit-stop invalidation remains permanent, including lost proofs.
 */
function riftletLegacyWebObserve(command, native) {
  'use strict';
  if (command.action !== 'observe') return null;
  const targetKeys = ['adapterID', 'surface', 'applicationID', 'sessionID', 'windowID', 'tabID',
    'documentID', 'composerID', 'draftGeneration'];
  const sameLogical = (a, b) => (!a && !b) || (!!a && !!b && a.profileID === b.profileID && a.id === b.id);
  const sameTarget = (a, b) => !!a && !!b && targetKeys.every(k => a[k] === b[k])
    && sameLogical(a.logicalDraftIdentity, b.logicalDraftIdentity);
  const sameIdentity = (a, b) => !!a && !!b && a.operationID === b.operationID && a.assetID === b.assetID
    && a.attempt === b.attempt && a.assetSHA256 === b.assetSHA256 && sameTarget(a.target, b.target);
  const identity = command.identity;
  if (!identity || !sameTarget(identity.target, command.target)) throw Error('TARGET_INVALID');
  const blank = version => ({schemaVersion: 1,
    provenance: {source: 'integratedDevelopment', evidenceID: (version === 'v8' ? 'W5-legacy-' : 'W4-legacy-') + version + '-original-observer'},
    observation: {identity, state: 'invalidated', exactImageIdentity: false, belongsToOriginalDraft: false,
      hasError: false, isUploading: false, attachmentAbsent: false, automaticRetryExcluded: false}});
  let match = null;
  // Exact frozen target selects the historical implementation. A current page
  // installation or equal business ID is not a substitute for that target.
  for (const version of ['v6', 'v7', 'v8']) {
    const registry = globalThis['__riftletWebAcceptance20261027' + version];
    if (!registry) continue;
    const seen = new Set(); let current = registry.head;
    for (let i = 0; current && i < 32; i++, current = current.next) {
      if (seen.has(current)) return blank(version);
      seen.add(current);
      if (sameTarget(command.target, current.target)) {
        if (match) return blank('ambiguous');
        match = {state: current, version};
      }
    }
    if (current) return blank(version);
  }
  if (!match) return null;
  const {state, version} = match, envelope = blank(version), observation = envelope.observation;
  try {
    if (!['applicationID', 'sessionID', 'windowID', 'tabID'].every(k => state.target[k] === native[k])) return envelope;
    const op = state.operations.get(identity.operationID);
    if (!op || !sameIdentity(identity, op.identity) || !op.committed || op.inputCount !== 1) return envelope;
    // Drain retained event records and sample only through the old code. These
    // callbacks may advance original proof bookkeeping, but cannot dispatch input.
    state.drain();
    if (!state.observationIdentityValid()) return envelope;
    state.sample(op);
    observation.belongsToOriginalDraft = state.observationIdentityValid() && sameTarget(identity.target, state.target);
    observation.hasError = op.error;
    observation.isUploading = op.uploading;
    if (!observation.belongsToOriginalDraft || op.invalid) {
      if (observation.belongsToOriginalDraft && op.error && op.errorAttachmentID
          && op.card?.isConnected && state.form.contains(op.card)
          && op.image?.isConnected && op.image.closest('[role=button]') === op.card
          && op.card.getAttribute('aria-label') === op.name && op.image.alt === op.name
          && state.ownCards(op.name).length === 1) {
        observation.attachmentID = op.errorAttachmentID;
        observation.exactImageIdentity = true;
      }
      return envelope;
    }
    observation.state = 'inputTriggered';
    if (op.card && op.image) observation.attachmentID = state.target.documentID + ':'
      + state.nodeID(op.card) + ':' + state.nodeID(op.image);
    const proof = op.proof;
    if (proof && sameIdentity(proof.identity, identity) && proof.completed > op.loaded && op.loaded > op.hundred
        && op.started && op.ended && op.fileHashVerified && op.inputCount === 1 && state.currentMember(op)
        && proof.card === op.card && proof.image === op.image && proof.source === state.currentSource(op.image)
        && proof.loadSequence === op.loaded && !op.uploading && op.image.complete) {
      observation.state = 'attached'; observation.exactImageIdentity = true;
    }
    return envelope;
  } catch {
    // A broken historical closure is missing evidence, never fresh authority.
    return blank(version);
  }
}
