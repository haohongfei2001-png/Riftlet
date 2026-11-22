'use strict';

// Receives the URL object already parsed inside the passive observer's original
// create-response callback. This function never reads href, pathname, search,
// signatures, headers, or the response body. Its return has no reference to url.
function declaredExpiry(url) {
  if (url.protocol !== 'https:' || url.port !== '' ||
      !/^[a-z0-9]{3,24}\.blob\.core\.windows\.net$/.test(url.hostname)) return null;
  const q = url.searchParams;
  const [resource,version,expiry] = ['sr','sv','se'].map(name=>q.getAll(name));
  if (resource.length !== 1 || resource[0] !== 'b' || version.length !== 1 ||
      !/^\d{4}-\d{2}-\d{2}$/.test(version[0]) || expiry.length !== 1) return null;
  if (['Expires','expires','expires_at','X-Amz-Expires','X-Goog-Expires'].some(name=>q.has(name))) return null;
  const value = expiry[0];
  const match = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,7}))?Z$/.exec(value);
  if (!match) return null;
  const tick = new Date(match[1]+'.000Z');
  if (!Number.isFinite(tick.getTime()) || tick.toISOString() !== match[1]+'.000Z') return null;
  const day = new Date(version[0]+'T00:00:00.000Z');
  if (!Number.isFinite(day.getTime()) || day.toISOString() !== version[0]+'T00:00:00.000Z') return null;
  return {schema:'azure-storage-blob-sas-se', expiresUTC:value};
}

// The existing observer decides whether a normal transfer was uniquely
// correlated. The additional projection requires the actual whole original File.
function expiryReceipt(value, report) {
  const positive = report.status==='CALIBRATED' && report.restored===true && report.reason===null &&
    report.inputs===1 && report.changes===1 && report.creates===1 && report.responses===1 && report.byteRequests===1 &&
    report.pending===0 && report.observerPending===0 && report.requestPending===false &&
    report.cancelledByObserver===0 && report.byteReturned===true && report.byteCompleted===true &&
    report.sourceVerified===true && report.bytesVerified===true && report.sameFile===true &&
    report.create?.transport==='fetch' && report.create.method==='POST' && report.create.path==='/backend-api/files' &&
    report.create.responseStatus===200 && report.create.fileNameField==='file_name' && report.create.uploadURLField==='upload_url' &&
    report.bytes?.transport==='xhr' && report.bytes.method==='PUT' && report.bytes.bodyType==='File' &&
    report.bytes.bodyScope==='entire-body' && report.bytes.bodySize===report.bytes.pngBytes &&
    Number.isSafeInteger(report.bytes.pngBytes) && report.bytes.pngBytes>0 &&
    Number.isInteger(report.bytes.responseStatus) && report.bytes.responseStatus>=200 && report.bytes.responseStatus<300 &&
    [report.operationHash,report.bytes.urlSHA256,report.bytes.pngSHA256].every(h=>typeof h==='string' && /^[0-9a-f]{64}$/.test(h));
  if (!value || !positive) return null;
  return {schema:value.schema, expiresUTC:value.expiresUTC, operationSHA256:report.operationHash,
    uploadURLSHA256:report.bytes.urlSHA256, pngSHA256:report.bytes.pngSHA256};
}

module.exports = {declaredExpiry,expiryReceipt};
