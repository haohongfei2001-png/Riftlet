/* LAB ONLY. Install BEFORE the next explicitly selected generated asset's input.
 * riftletRound5InstallV11ProgressProbe({assetID: '<private new asset UUID>'})
 * Then read __riftletRound5V11ProgressProbe.query(); stop with .stop().
 * Only this probe's listeners/observer/timer are installed or removed. No input,
 * requests, original-observer calls, progress writes or raw labels/IDs/text logs.
 * Fixed bounds: 60 seconds, 160 events, 1024 mutation records, 32x32 op lookup.
 */
function riftletRound5InstallV11ProgressProbe(options) {
  'use strict';
  const KEY = '__riftletRound5V11ProgressProbe';
  const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
  if (!options || !uuid.test(options.assetID || '')) return {installed:false,reason:'INVALID_ASSET'};
  if (globalThis[KEY]) return {installed:false,reason:'PROBE_ALREADY_PRESENT'};
  let wanted = options.assetID.toLowerCase();
  const lookup = () => {
    const matches = [], seen = new Set(); let g = globalThis.__riftletWebAcceptance20261027v11?.head, count = 0;
    for (; g && count < 32; count++, g = g.next) {
      if (seen.has(g)) throw Error('LOOKUP_BOUND'); seen.add(g);
      let n = 0;
      for (const op of Map.prototype.values.call(g.operations)) {
        if (++n > 32) throw Error('LOOKUP_BOUND');
        if (typeof op.identity?.assetID === 'string' && op.identity.assetID.toLowerCase() === wanted) {
          matches.push({generation:g,op}); if (matches.length > 1) throw Error('AMBIGUOUS_ASSET');
        }
      }
    }
    if (g) throw Error('LOOKUP_BOUND'); return matches[0] || null;
  };
  try {
    const previous = lookup();
    if (previous && (previous.op.committed || previous.op.inputCount > 0)) return {installed:false,reason:'ASSET_ALREADY_DISPATCHED'};
  } catch { return {installed:false,reason:'LOOKUP_UNAVAILABLE'}; }
  let stopped = false, reason = null, bound = null, originalCard = null, originalProgress = null, originalImage = null;
  let timer = null, observer = null, sequence = 0, recordsRead = 0, nextBatchID = 0, activeBatchID = null;
  const events = [];
  const numeric = raw => {
    if (raw === null) return {kind:'missing',value:null};
    if (typeof raw !== 'string' || !/^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/.test(raw)) return {kind:'invalid',value:null};
    const value = Number(raw);
    return Number.isFinite(value) && value >= 0 && value <= 100 ? {kind:'finite',value} : {kind:'invalid',value:null};
  };
  const clock = () => { const n = performance.now(); return Number.isFinite(n) && n >= 0 ? n : null; };
  const query = () => ({schemaVersion:1,mode:'PROGRESS_DIAGNOSTIC_ONLY',state:stopped?'STOPPED':bound?'BOUND':'ARMED',
    reason,recordsRead,events:events.map(event=>({...event}))});
  function stop(code = 'EXPLICIT_STOP') {
    if (!stopped) {
      stopped = true; reason = code;
      observer?.disconnect(); document.removeEventListener('change', inputChanged, true);
      for (const type of ['load','error']) document.removeEventListener(type,imageEvent,true);
      if (timer !== null) clearTimeout(timer);
      // Keep only sanitized scalar logs; release all page/operation references.
      observer = null; bound = null; originalCard = null; originalProgress = null; originalImage = null; wanted = null;
    }
    return query();
  }
  function log(event, fields = {}) {
    if (stopped) return;
    if (events.length >= 160) { stop('EVENT_BOUND'); return; }
    events.push({sequence:++sequence,atMS:clock(),batchID:activeBatchID,event,...fields});
  }
  function snapshot(event) {
    if (stopped || !bound) return;
    const {generation:g,op} = bound;
    const candidates = g.form.querySelectorAll('[role=button][aria-label]');
    if (candidates.length > 256) { stop('CARD_BOUND'); return; }
    const cards = [...candidates].filter(card=>card.getAttribute('aria-label')===op.name);
    const card = cards.length === 1 ? cards[0] : null;
    if (!originalCard && card) originalCard = card;
    const images = card ? card.querySelectorAll('img') : [];
    if (!originalImage && card === originalCard && images.length === 1 && images[0].alt === op.name) originalImage = images[0];
    const nodes = card ? card.querySelectorAll('[role=progressbar]') : [];
    const node = nodes.length === 1 ? nodes[0] : null;
    const exactLabel = !!node && node.getAttribute('aria-label') === '正在上传 ' + op.name;
    if (!originalProgress && card === originalCard && exactLabel) originalProgress = node;
    const value = node ? numeric(node.getAttribute('aria-valuenow')) : {kind:'no-node',value:null};
    log(event,{inputCount:op.inputCount,inputSequence:op.inputSequence,hashVerified:op.fileHashVerified===true,
      adapterStartDisqualified:op.startDisqualified===true,hasAdapterStart:!!op.uploadStart,hasAdapterProof:!!op.proof,
      cardCount:cards.length,cardIsOriginal:!!card && card===originalCard,
      progressCount:nodes.length,nodeIsOriginal:!!node && node===originalProgress,exactProgressLabel:exactLabel,
      valueKind:value.kind,value:value.value,imageCount:images.length,
      imageIsOriginal:images.length===1 && images[0]===originalImage});
  }
  function mutation(records) {
    if (stopped || !bound) return;
    activeBatchID = ++nextBatchID;
    try {
      if (recordsRead + records.length > 1024) { stop('RECORD_BOUND'); return; }
      recordsRead += records.length;
      // Identify an inserted original card/node before attributing this batch's
      // oldValue entries. Snapshot is callback-time; oldValue retains history.
      snapshot('mutation_snapshot');
      for (const record of records) {
        if (stopped || !bound) return;
        if (record.type === 'attributes' && record.target === originalProgress) {
          const current = numeric(record.target.getAttribute('aria-valuenow'));
          const old = record.attributeName === 'aria-valuenow' ? numeric(record.oldValue) : null;
          log('progress_attribute',{attribute:record.attributeName==='aria-valuenow'?'value':record.attributeName==='aria-label'?'label':'role',
            nodeIsOriginal:true,underOriginalCard:!!originalCard?.contains(record.target),
            exactProgressLabel:record.target.getAttribute('aria-label')==='正在上传 '+bound.op.name,
            oldValueKind:old?.kind ?? 'not-value',oldValue:old?.value ?? null,
            valueKind:current.kind,value:current.value});
        }
        if (record.type === 'childList' && originalProgress) {
          const contains = node=>node===originalProgress || (typeof node.contains==='function' && node.contains(originalProgress));
          if (record.removedNodes.length + record.addedNodes.length > 256) { stop('NODE_BOUND'); return; }
          const removed = [...record.removedNodes].some(contains), added = [...record.addedNodes].some(contains);
          if (removed || added) log('original_progress_membership',{removed,added,
            underOriginalCard:!!originalCard?.contains(originalProgress),
            valueKind:numeric(originalProgress.getAttribute('aria-valuenow')).kind,
            value:numeric(originalProgress.getAttribute('aria-valuenow')).value});
        }
      }
    } catch { stop('DIAGNOSTIC_UNAVAILABLE'); } finally { activeBatchID = null; }
  }
  function imageEvent(event) {
    if (stopped || !bound) return;
    try {
      if (!originalImage) snapshot('image_event_snapshot');
      if (stopped || event.target !== originalImage) return;
      const image=originalImage, source=image.currentSrc || image.src || '';
      const sourceKind=source.startsWith('data:image/png;base64,')?'data-png':source.startsWith('blob:')?'blob':source===''?'empty':'other';
      const size=n=>Number.isSafeInteger(n)&&n>=0?n:null;
      log(event.type==='load'?'original_image_load':'original_image_error',{
        imageIsOriginal:true,underOriginalCard:!!originalCard?.contains(image),
        exactImageLabel:image.alt===bound.op.name,complete:image.complete===true,
        naturalWidth:size(image.naturalWidth),naturalHeight:size(image.naturalHeight),sourceKind});
    } catch { stop('DIAGNOSTIC_UNAVAILABLE'); }
  }
  function inputChanged(event) {
    if (stopped) return;
    try {
      if (bound) {
        if (event.target === bound.generation.input) { log('additional_original_input'); stop('ADDITIONAL_INPUT'); }
        return;
      }
      const candidate = lookup();
      if (!candidate || event.target !== candidate.generation.input) return;
      const {op} = candidate, files = event.target.files;
      if (!op.committed || op.inputCount !== 1 || !op.inputSequence || !files || files.length !== 1
          || files[0].name !== op.name || files[0].size !== op.bytes || files[0].type !== 'image/png') {
        stop('INPUT_NOT_CORRELATED'); return;
      }
      bound = candidate;
      observer = new MutationObserver(mutation);
      observer.observe(candidate.generation.form,{subtree:true,childList:true,attributes:true,attributeOldValue:true,
        attributeFilter:['aria-valuenow','aria-label','role']});
      snapshot('original_input');
    } catch { stop('DIAGNOSTIC_UNAVAILABLE'); }
  }
  const api = Object.freeze({query,stop:()=>stop()});
  Object.defineProperty(globalThis,KEY,{value:api,configurable:true,writable:false});
  document.addEventListener('change',inputChanged,true);
  for (const type of ['load','error']) document.addEventListener(type,imageEvent,true);
  timer = setTimeout(()=>stop('TIME_BOUND'),60000);
  return {installed:true,mode:'PROGRESS_DIAGNOSTIC_ONLY',maxDurationMS:60000};
}
