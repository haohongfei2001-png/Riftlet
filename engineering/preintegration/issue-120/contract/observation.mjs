// Preintegration fixture API. Correlation with the original operation is
// necessary for observation. It is never proof of START, failure, or READY.
export const protocolRevision = 1;
const fields = Object.freeze([
  'hostBundle', 'session', 'clickGeneration', 'processBirth', 'window', 'tab', 'providerID', 'programDigest',
  'route', 'surface', 'mode', 'document', 'composer', 'draftEpoch',
  'operation', 'invocation', 'originalSHA256', 'payloadSHA256'
]);

export function isOriginalObservation(expected, observed) {
  if (!expected || !observed ||
      !['protocolRevision', 'pid', 'attempt', 'providerRevision'].every(k => Object.hasOwn(expected, k) && Object.hasOwn(observed, k)) ||
      !Number.isSafeInteger(expected.pid) || expected.pid <= 0 || expected.pid !== observed.pid ||
      !['programDigest', 'payloadSHA256', 'originalSHA256'].every(k => typeof expected[k] === 'string' && /^[a-f0-9]{64}$/.test(expected[k])) ||
      expected.protocolRevision !== protocolRevision || observed.protocolRevision !== protocolRevision ||
      !Number.isSafeInteger(expected.providerRevision) || expected.providerRevision <= 0 ||
      expected.providerRevision !== observed.providerRevision ||
      !Number.isSafeInteger(expected.attempt) || expected.attempt < 1 || expected.attempt !== observed.attempt) return false;
  return fields.every(key => typeof expected[key] === 'string' && expected[key].length > 0 &&
    Object.hasOwn(expected, key) && Object.hasOwn(observed, key) && expected[key] === observed[key]);
}
