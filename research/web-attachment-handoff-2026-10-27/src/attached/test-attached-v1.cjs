const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {classify}=require('./attached-verdict-v1.cjs');
const actual=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../../evidence/normal/classifier-input.json')));
const copy=()=>structuredClone(actual);
function append(x,event,state){const es=x.trace.events,last=es.at(-1);es.push({...last,sequence:last.sequence+1,monotonicMs:last.monotonicMs+1,event,state});}
function truncate(x,n){x.trace.events=x.trace.events.slice(0,n);let e=[...x.trace.events].reverse().find(e=>(e.state.snapshot??e.state).cards);x.trace.snapshot=structuredClone(e.state.snapshot??e.state);}
test('ACTUAL: real trusted trace plus real final-preview hash -> ATTACHED, never strict READY or consume',()=>{const r=classify(actual);assert.equal(r.state,'ATTACHED');assert.equal(r.strictREADY,'NOT_PROVEN');assert.equal(r.automaticConsumeAllowed,false);assert.equal(r.retainOriginal,true);});
test('ACTUAL PREFIX: progress 100 remains UPLOADING',()=>{const x=copy();truncate(x,16);assert.equal(classify(x).state,'UPLOADING');});
test('ACTUAL PREFIX: progress disappearance without final image load remains UNKNOWN',()=>{const x=copy();truncate(x,18);assert.equal(classify(x).state,'UNKNOWN');});
test('SIMULATED: a loaded preview before upload ends cannot be borrowed as final load',()=>{const x=copy();x.trace.events=x.trace.events.map(e=>e.sequence>=19?{...e,event:'composer_mutation'}:e);assert.equal(classify(x).state,'UNKNOWN');});
test('SIMULATED: wrong final bytes reject filename-only identity',()=>{const x=copy();x.preview.previewSha256='f'.repeat(64);assert.equal(classify(x).state,'UNKNOWN');});
test('SIMULATED: identical content from another operation cannot supply preview proof',()=>{const x=copy();x.preview.operationId='another';assert.equal(classify(x).state,'UNKNOWN');});
test('SIMULATED: duplicate named card cannot be consumed',()=>{const x=copy();x.trace.snapshot.cards.push(structuredClone(x.trace.snapshot.cards[0]));x.trace.snapshot.exactNamedCards=2;assert.equal(classify(x).state,'UNKNOWN');});
test('SIMULATED: preexisting same-name card cannot be claimed',()=>{const x=copy();const s=x.trace.events[5].state;s.cards=structuredClone(x.trace.snapshot.cards);s.exactNamedCards=1;assert.equal(classify(x).state,'UNKNOWN');});
test('SIMULATED: parallel user file event blocks uncalibrated concurrency',()=>{const x=copy();append(x,'unexpected_file_name',{eventType:'change'});assert.equal(classify(x).state,'UNKNOWN');});
test('SIMULATED: second dispatch / duplicate screenshot operation is not success',()=>{const x=copy();append(x,'file_entered',structuredClone(x.trace.events[6].state));assert.equal(classify(x).state,'UNKNOWN');});
test('SIMULATED: correlated failure vetoes completed preview; no auto retry',()=>{const x=copy();append(x,'correlated_attachment_error',{kind:'simulated error retaining preview'});const r=classify(x);assert.equal(r.state,'ERROR_OBSERVED');assert.equal(r.automaticRetryAllowed,false);assert.equal(r.terminalFailureVerified,false);});
test('SIMULATED: image error after a successful load vetoes attachment success',()=>{const x=copy();append(x,'image_error',{nodeId:'node-7'});assert.equal(classify(x).state,'UNKNOWN');});
test('SIMULATED: switched document rejects delayed old receipts',()=>{const x=copy();x.trace.snapshot.documentNonce='new-document';assert.equal(classify(x).state,'UNKNOWN');});
test('SIMULATED: same URL with replaced composer rejects receipt',()=>{const x=copy();x.trace.snapshot.composerNode='new-composer';assert.equal(classify(x).state,'UNKNOWN');});
test('SIMULATED: reused DOM with observed epoch invalidation rejects receipt',()=>{const x=copy();append(x,'target_invalidated',{reason:'SAME_URL_NEW_DRAFT'});assert.equal(classify(x).state,'UNKNOWN');});
test('SIMULATED: removed attachment, dropped event and truncated buffer fail closed',()=>{
 for(const modify of [x=>{x.trace.snapshot.cards=[];x.trace.snapshot.exactNamedCards=0;},x=>x.trace.events.splice(10,1),x=>{x.trace.truncated=true;}]){const x=copy();modify(x);assert.equal(classify(x).state,'UNKNOWN');}
});
test('SIMULATED: restarting upload after final preview blocks consumption',()=>{const x=copy();const s=structuredClone(x.trace.events[15].state);append(x,'composer_mutation',s);x.trace.snapshot=s;assert.equal(classify(x).state,'UNKNOWN');});
test('SIMULATED: elapsed time does not upgrade or downgrade the same causal evidence',()=>{const x=copy();for(const e of x.trace.events)e.monotonicMs+=1000000;x.preview.hashCompletedMonotonicMs+=1000000;assert.equal(classify(x).state,'ATTACHED');});

test('SIMULATED: current card relabel or loss of input proof vetoes a historical good trace',()=>{for(const change of [x=>{x.trace.snapshot.cards[0].attributes['aria-label']='other.png';},x=>{x.trace.snapshot.hashVerified=false;}]){const x=copy();change(x);assert.equal(classify(x).state,'UNKNOWN');}});
