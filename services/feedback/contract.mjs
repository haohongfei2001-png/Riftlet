export const MAX_BODY = 32768;
export const FACTS = new Set(`sessionStarted previousSessionUnclean initializationIssue captureSourceUnavailable captureImportIssue captureUnsupported privateStorageIssue queueReadIssue selectionAccepted selectionRejected permissionUnavailable visibilityVisible visibilitySwallowed visibilityArchived visibilityRemoved queuePending queueTransferring queueUnknown queueFailed queueUsed queueMissing phasePrepared phaseDispatchIntent phaseInputTriggered phaseAttachmentPresent phaseUnknown phaseCompensated phaseFailed phaseSucceeded reasonCapture reasonUploadStarted reasonLegacyCompletion reasonAutomaticArchive reasonUserRemoved reasonUserRestored reasonSafeFailure uiProjectionDeferred uiProjectionMismatchCandidate`.split(' '));
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
export const validID = id => typeof id === 'string' && uuid.test(id);
export function keys(value, required, optional = []) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    && required.every(k => Object.hasOwn(value,k))
    && Object.keys(value).every(k => required.includes(k) || optional.includes(k));
}
const bounded = n => Number.isSafeInteger(n) && n >= 0 && n <= 9999;
export function validate(value) {
  if (!keys(value,['schema','id','kind','text','appVersion','createdAt'],['diagnostic'])
      || value.schema !== 1 || !validID(value.id) || !['problem','suggestion'].includes(value.kind)
      || typeof value.text !== 'string' || !value.text.trim() || [...value.text].length > 4000
      || new TextEncoder().encode(value.text).length > 16384
      || typeof value.appVersion !== 'string' || !/^[0-9]{1,4}(\.[0-9]{1,4}){0,3}$/.test(value.appVersion)
      || !Number.isSafeInteger(value.createdAt) || value.createdAt < 0) throw new Error('schema');
  if (Object.hasOwn(value,'diagnostic')) {
    const d = value.diagnostic;
    if (!keys(d,['schema','coverage','events','dropped']) || d.schema !== 1 || d.coverage !== 'session-sampled-v1'
        || !bounded(d.dropped) || !Array.isArray(d.events) || d.events.length > 64
        || !d.events.every(e => keys(e,['fact','count']) && FACTS.has(e.fact) && bounded(e.count))) throw new Error('diagnostic');
  }
  // Explicit reconstruction, not object spreading: new fields never pass through.
  const result = {schema:1,id:value.id,kind:value.kind,text:value.text,appVersion:value.appVersion,createdAt:value.createdAt};
  if (value.diagnostic) result.diagnostic = {schema:1,coverage:'session-sampled-v1',events:value.diagnostic.events.map(e=>({fact:e.fact,count:e.count})),dropped:value.diagnostic.dropped};
  return result;
}
export async function digest(value) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))].map(b=>b.toString(16).padStart(2,'0')).join('');
}
export async function ipBucket(ip, hour, secret) {
  const key = await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  const bytes = new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(hour+'|'+ip)));
  return 'ip:'+hour+':'+[...bytes].map(b=>b.toString(16).padStart(2,'0')).join('');
}
export const json = (value,status=200,extra={}) => new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff',...extra}});
export function receipt(row) {
  const state = {pending:'received',attempting:'delivery_uncertain',uncertain:'delivery_uncertain',delivered:'delivered',deletion_pending:'deletion_pending',deleted:'deleted',expired:'delivery_expired'}[row.state];
  return {id:row.id,state,durable:true};
}
