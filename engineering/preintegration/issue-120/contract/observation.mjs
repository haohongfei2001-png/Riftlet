// Preintegration fixture API. Correlation with the original operation is
// necessary for observation. It is never proof of START, failure, or READY.
export const protocolRevision = 1;
const fields = Object.freeze([
  'hostBundle', 'processBirth', 'window', 'tab', 'providerID', 'programDigest',
  'route', 'surface', 'mode', 'document', 'composer', 'draftEpoch',
  'operation', 'invocation', 'originalSHA256', 'payloadSHA256'
]);

export function isOriginalObservation(expected, observed) {
  if (!expected || !observed ||
      expected.protocolRevision !== protocolRevision || observed.protocolRevision !== protocolRevision ||
      !Number.isSafeInteger(expected.providerRevision) || expected.providerRevision <= 0 ||
      expected.providerRevision !== observed.providerRevision ||
      !Number.isSafeInteger(expected.attempt) || expected.attempt < 1 || expected.attempt !== observed.attempt) return false;
  return fields.every(key => typeof expected[key] === 'string' && expected[key].length > 0 &&
    Object.hasOwn(expected, key) && Object.hasOwn(observed, key) && expected[key] === observed[key]);
}
