'use strict';
// INTERNAL ONLY. Exact-source, insert-only instrumentation; never an admission.
const fs=require('node:fs'),crypto=require('node:crypto');
const BASE='9b04975b7ee41a0f59cfc1e1ceb47e6855dd4c43e153e9304fb1f38996432e23';
const KEY='__riftletFirstInvalidationInternalV1';
const reasons={559:'PROOF_CONTINUITY_REJECTED',561:'PROOF_CONTENT_MISMATCH',565:'PROOF_EXCEPTION',614:'SAMPLE_CARD_DISAPPEARED',615:'SAMPLE_CARD_OR_INPUT_COUNT_INVALID',617:'SAMPLE_IMAGE_IDENTITY_INVALID',619:'SAMPLE_NODE_REPLACED',621:'SAMPLE_ASSOCIATED_ERROR',626:'SAMPLE_PROGRESS_STRUCTURE_INVALID',632:'SAMPLE_IMAGE_ERROR',638:'SAMPLE_REPEATED_FINAL_LOAD',641:'SAMPLE_PROOF_SOURCE_CHANGED',667:'MUTATION_ATTACHMENT_REMOVED',694:'MUTATION_ATTACHMENT_ATTRIBUTE_CHANGED',698:'MUTATION_PROGRESS_AFTER_END',735:'INPUT_EVENT_IDENTITY_INVALID',739:'INPUT_HASH_OR_BINDING_REJECTED',741:'INPUT_HASH_EXCEPTION',886:'COMMIT_PNG_SIGNATURE_INVALID',892:'COMMIT_FINAL_GUARD_REJECTED',902:'COMMIT_INPUT_COUNT_INVALID',904:'COMMIT_ASYNC_EXCEPTION'};
const wrap=s=>'/*RIFTLET_DIAG_BEGIN*/'+s+'/*RIFTLET_DIAG_END*/';
const hash=s=>crypto.createHash('sha256').update(s).digest('hex');
function restore(s){return s.replace(/\/\*RIFTLET_DIAG_BEGIN\*\/[\s\S]*?\/\*RIFTLET_DIAG_END\*\//g,'');}
// All side effects are confined to a separate bounded diagnostic store. No
// target, valid(), drain(), currentMember(), nodeID() or evidence methods run.
function record(op,reason,sequence=null){try{
  if(!op||op.invalid||!op.identity)return;
  const key='__riftletFirstInvalidationInternalV1';
  let d=Object.getOwnPropertyDescriptor(globalThis,key)?.value;
  if(!d){d={version:1,records:new Map(),nodes:new WeakMap(),nextNode:0,dropped:0};Object.defineProperty(globalThis,key,{value:d});}
  if(d.version!==1||!(d.records instanceof Map)||!(d.nodes instanceof WeakMap))return;
  if(d.records.has(op.identity.operationID))return;
  if(d.records.size>=64){d.dropped=Math.min(Number.MAX_SAFE_INTEGER,d.dropped+1);return;}
  const node=n=>{if(!n)return null;let id=d.nodes.get(n);if(!id){id=++d.nextNode;d.nodes.set(n,id);}return {id,connected:n.isConnected===true};};
  const flags={};for(const k of ['committed','fileHashVerified','startDisqualified','uploading','proofPending'])flags[k]=typeof op[k]==='boolean'?op[k]:null;
  const numbers={};for(const k of ['inputCount','inputSequence','progressValue','started','hundred','ended','loaded'])numbers[k]=Number.isFinite(op[k])?op[k]:null;
  d.records.set(op.identity.operationID,{identity:op.identity,reason,atMS:performance.now(),sequence,
    flags,numbers,nodes:{card:node(op.card),image:node(op.image),progress:node(op.progressNode)}});
}catch(_){/* Diagnostic failure must not change the original algorithm. */}}
function transform(s){
 if(hash(s)!==BASE)throw Error('BASE_SOURCE_MISMATCH');
 const lines=s.split('\n');
 const edit=(n,a,b)=>{if(lines[n-1].split(a).length!==2)throw Error('ANCHOR_'+n);lines[n-1]=lines[n-1].replace(a,b);};
 edit(11,"'use strict';","'use strict';"+wrap('\nconst diagRecord='+record.toString()+';\n'));
 for(const [line,reason] of Object.entries(reasons)){
   const n=Number(line),m=lines[n-1].match(/markBad\(op(, true)?\)/);if(!m)throw Error('CALLSITE_'+n);
   edit(n,m[0],m[0].slice(0,-1)+wrap((m[1]?'':', false')+', '+JSON.stringify(reason))+')');
 }
 edit(489,'error = false','error = false'+wrap(', diagReason = "MARK_BAD_UNCLASSIFIED"'));
 edit(498,'op.invalid = true;',wrap('diagRecord(op,diagReason,sequence);')+'op.invalid = true;');
 edit(440,'op.invalid = true;',wrap('diagRecord(op,"REVOKE_UNCOMMITTED_OPERATION",sequence);')+'op.invalid = true;');
 edit(442,'() =>','('+wrap('diagCause = "BINDING_INVALIDATE_CALLBACK"')+') =>');
 for(const [n,r] of Object.entries({469:'BINDING_SNAPSHOT_REJECTED',660:'BINDING_MODE_MUTATION',664:'BINDING_REQUIRED_NODE_REMOVED',770:'BINDING_NAVIGATION_EVENT',785:'BINDING_MONITOR_ADMISSION_REJECTED'}))edit(Number(n),'invalidate()','invalidate('+wrap(JSON.stringify(r))+')');
 edit(444,'invalid = true;',wrap('try { for (const item of operations.values()) diagRecord(item,typeof diagCause === "string" ? diagCause : "BINDING_INVALIDATE_CALLBACK",sequence); } catch (_) {}')+'invalid = true;');
 edit(437,'invalid = true','invalid = '+wrap('( (()=>{try{for(const item of operations.values())diagRecord(item,"BINDING_SEQUENCE_EXHAUSTED",sequence);}catch(_){}})(),')+'true'+wrap(')'));
 edit(875,'op.invalid = true;',wrap('diagRecord(op,"DISCARD_UNCOMMITTED_OPERATION");')+'op.invalid = true;');
 const out=lines.join('\n');if(restore(out)!==s)throw Error('RESTORE_MISMATCH');return out;
}
module.exports={BASE,KEY,reasons,record,transform,restore};
if(require.main===module){if(process.argv.length!==4)throw Error('usage: node first-invalidation.cjs BASE_JS NEW_OUTPUT');const input=fs.readFileSync(process.argv[2],'utf8');fs.writeFileSync(process.argv[3],transform(input),{flag:'wx'});}
