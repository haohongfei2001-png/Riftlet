'use strict';
// Offline evidence classifier. No DOM access, dispatch, network, deletion or retry.
// ATTACHED names an observed UI result; admission is independent and remains blocked
// until real failure / draft-transition calibration is supplied by a later audit.
const keys=['windowId','tabId','documentNonce','draftLeaseId','assetId','operationId'];
function classify({trace,preview,expected}) {
 const base={strictREADY:'NOT_PROVEN',automaticConsumeAllowed:false,automaticRetryAllowed:false,retainOriginal:true};
 const result=(state,reason,extra={})=>({...base,state,reason,...extra});
 const unknown=reason=>result('UNKNOWN',reason);
 const matches=x=>x&&keys.every(k=>x[k]===expected[k]);
 const snap=e=>e.state?.snapshot??e.state;
 const nodes=s=>s.cards?.[0]?.nodes??[];
 const progress=s=>nodes(s).filter(n=>n.attributes?.role==='progressbar');
 if(!trace||!Array.isArray(trace.events)||!trace.events.length||trace.truncated)return unknown('MISSING_OR_TRUNCATED_TRACE');
 if(!matches(trace.binding))return unknown('BOUND_TARGET_MISMATCH');
 const ev=trace.events;
 for(let i=0;i<ev.length;i++){
  const e=ev[i];if(e.sequence!==i+1)return unknown('EVENT_GAP');
  if(!matches(e))return unknown('MIXED_OPERATION_OR_DOCUMENT');
  if(i&&e.monotonicMs<ev[i-1].monotonicMs)return unknown('CLOCK_ORDER_INVALID');
 }
 if(ev.some(e=>e.event==='target_invalidated'))return unknown('LEASE_INVALIDATED');
 if(ev.some(e=>e.event==='unexpected_file_name'||e.event==='observed_concurrent_input'))return unknown('CONCURRENT_OR_UNEXPECTED_INPUT_UNCALIBRATED');
 if(ev.some(e=>e.event==='correlated_attachment_error'))return result('ERROR_OBSERVED','CORRELATED_ERROR_VETO', {terminalFailureVerified:false});
 if(ev.some(e=>e.event==='image_error'))return unknown('PREVIEW_LOAD_ERROR');
 const selected=ev.filter(e=>e.event==='file_entered'),arms=ev.filter(e=>e.event==='armed_verified');
 if(selected.length!==1)return unknown('INPUT_NOT_UNIQUE');
 const input=selected[0];
 if(arms.length!==1||arms[0].sequence>=input.sequence)return unknown('INPUT_NOT_ARMED');
 if(input.state.name!==expected.name||input.state.bytes!==expected.bytes||!input.state.targetInForm||input.state.ordinal!==1)return unknown('INPUT_IDENTITY_MISMATCH');
 const hashed=ev.filter(e=>e.event==='input_bytes_verified');
 if(hashed.length!==1||hashed[0].sequence<=input.sequence||!hashed[0].state.matches||hashed[0].state.name!==expected.name||hashed[0].state.sha256!==expected.sha256||hashed[0].state.bytes!==expected.bytes)return unknown('SELECTED_FILE_BYTES_UNVERIFIED');
 let cardId=null,imageId=null,composer=null,form=null,everCard=false,started=null,hundred=null,ended=null,finalLoad=null;
 for(const e of ev){
  const s=snap(e);if(!s||!Object.hasOwn(s,'cards'))continue;
  if(!matches(s)||s.valid!==true||s.baselinePreserved!==true||s.textUnchanged!==true)return unknown('DRAFT_OR_BASELINE_INVALID');
  composer??=s.composerNode;form??=s.formNode;
  if(composer!==s.composerNode||form!==s.formNode)return unknown('COMPOSER_REPLACED');
  if(s.inputCount>1)return unknown('MULTIPLE_INPUTS');
  if(s.exactNamedCards===0&&s.cards.length===0){if(everCard)return unknown('ATTACHMENT_REMOVED');continue;}
  if(s.exactNamedCards!==1||s.cards.length!==1)return unknown('ATTACHMENT_AMBIGUOUS');
  if(e.sequence<input.sequence)return unknown('ATTACHMENT_PREEXISTED');
  const card=s.cards[0],images=card.nodes.filter(n=>n.tag==='IMG');
  if(card.attributes?.['aria-label']!==expected.name||images.length!==1||images[0].attributes?.alt!==expected.name)return unknown('CARD_IDENTITY_MISMATCH');
  cardId??=card.nodeId;imageId??=images[0].nodeId;everCard=true;
  if(cardId!==card.nodeId||imageId!==images[0].nodeId)return unknown('ATTACHMENT_REPLACED');
  const ps=progress(s);
  if(ps.length){
   if(ps.length!==1||ps[0].attributes['aria-label']!==`正在上传 ${expected.name}`)return unknown('UPLOAD_SIGNAL_NOT_OWNED');
   if(ended!==null)return unknown('UPLOAD_RESTARTED_AFTER_END');
   started??=e.sequence;if(ps[0].attributes['aria-valuenow']==='100')hundred??=e.sequence;
  }else if(hundred!==null)ended??=e.sequence;
  if(e.event==='image_load'&&ended!==null&&e.sequence>hundred&&e.state.nodeId===imageId&&images[0].image?.sourceKind==='data'&&images[0].image?.complete===true&&images[0].image.naturalWidth>0&&images[0].image.naturalHeight>0)finalLoad=e.sequence;
 }
 const tail=trace.snapshot;
 if(!matches(tail)||!tail.valid||!tail.baselinePreserved||!tail.textUnchanged||tail.composerNode!==composer||tail.formNode!==form)return unknown('CURRENT_LEASE_INVALID');
 if(tail.exactNamedCards!==1||tail.cards.length!==1||tail.cards[0].nodeId!==cardId||tail.cards[0].attributes?.['aria-label']!==expected.name||tail.inputCount!==1||tail.hashVerified!==true)return unknown('CURRENT_ATTACHMENT_NOT_UNIQUE');
 if(progress(tail).length)return result('UPLOADING','OWN_ATTACHMENT_STILL_UPLOADING');
 if(started===null||hundred===null||ended===null||finalLoad===null)return unknown('INCOMPLETE_UI_LIFECYCLE');
 const img=nodes(tail).filter(n=>n.tag==='IMG');
 if(img.length!==1||img[0].nodeId!==imageId||img[0].attributes?.alt!==expected.name||!img[0].image?.complete||img[0].image.sourceKind!=='data')return unknown('FINAL_PREVIEW_UNAVAILABLE');
 if(!matches(preview)||preview.state!=='VERIFIED'||preview.filename!==expected.name||preview.cardNode!==cardId||!preview.currentLeaseValid||!preview.sameCardAndSource||preview.previewSha256!==expected.sha256||preview.previewBytes!==expected.bytes||!preview.previewBytesMatchSelectedFile)return unknown('FINAL_PREVIEW_CONTENT_UNVERIFIED');
 const lastTime=ev.find(e=>e.sequence===finalLoad).monotonicMs;
 if(preview.hashCompletedMonotonicMs<lastTime)return unknown('PREVIEW_PROOF_PREDATES_COMPLETION');
 return result('ATTACHED','OWNED_FILE_UI_LIFECYCLE_AND_PREVIEW_VERIFIED',{
  assurance:'OBSERVED_UI_COMPLETION_NOT_FAILURE_CALIBRATED',errorEvidence:'NO_CORRELATED_ERROR_OBSERVED_ERROR_CHANNEL_NOT_CALIBRATED',
  uploadBackendOutcome:'NOT_PROVEN',admission:'CONTROLLED_TRIAL_ONLY',cardNode:cardId,imageNode:imageId,
  evidenceSequences:{input:input.sequence,hash:hashed[0].sequence,uploading:started,progress100:hundred,progressEnded:ended,finalImageLoad:finalLoad},
  blockers:['REAL_FAILURE_FALSE_POSITIVE_CALIBRATION','REAL_DRAFT_SWITCH_AND_EXTERNAL_INPUT_CALIBRATION'],
  note:'No fixed wait threshold; time establishes order only. This is not strict READY or permission to consume.'
 });
}
module.exports={classify};
