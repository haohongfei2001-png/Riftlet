'use strict';
// Review probes only. No browser, network or source edits. Native DOM containment
// is modelled through ancestor identity so content-read traps distinguish contains
// from subtree traversal (the project's lightweight fixture uses recursion).
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {fixture,native} = require('../../../Tests/WebPageProgram/independent-input-fixture.cjs');
const results = [];
function setup() {
  const context = {...native,applicationID:'com.microsoft.edgemac',sessionID:'review-edge-session'};
  const f = fixture({nativeContext:context});
  f.Node.prototype.contains = function(node) { for(let n=node;n;n=n.parentElement) if(n===this)return true;return false; };
  const activity = new EventTarget(), navigation = new EventTarget(); navigation.currentEntry = {id:randomUUID()};
  f.context.navigation=navigation; f.context.addEventListener=activity.addEventListener.bind(activity);
  f.context.removeEventListener=activity.removeEventListener.bind(activity);
  f.context.setTimeout=(fn,ms)=>setTimeout(fn,ms).unref();
  const bind=()=>{const clickWitnessID=randomUUID(),url=new URL(f.context.location.href);
    assert.equal(f.call({action:'pinTarget',clickWitnessID,address:url.origin+url.pathname}),'bound');
    return f.bind({target:f.call({action:'captureTarget',clickWitnessID})});};
  const observe=op=>f.call(op.command('observe'));
  return {f,context,navigation,bind,observe};
}
const diagnosticStack = () => new Error().stack.includes('edgeCalibration');
async function run() {
  {
    const {f,bind,observe}=setup(); let reads=0, mutations=0;
    const excluded=[['article',{}],['div',{'data-message-author-role':'assistant'}],['aside',{}],['nav',{}],['header',{}],['div',{role:'search'}],['div',{role:'menu'}],['div',{role:'dialog'}],['form',{}],['div',{'data-chatgpt-composer':''}],['div',{contenteditable:'true'}],['div',{role:'textbox'}],['textarea',{}]];
    for(const [tag,attrs] of excluded){
      const root=f.form.append(new f.Node(tag,attrs)); root.rendered=false;
      const child=root.append(new f.Node('img',{'data-file-name':'private-history.png',src:'blob:private-history'}));
      const children=root.children;
      Object.defineProperty(root,'children',{get(){if(diagnosticStack()){reads++;throw Error('history children read');}return children;},set(v){throw Error('review fixture mutation');}});
      const get=child.getAttribute;
      child.getAttribute=function(key){if(diagnosticStack()){reads++;throw Error('history attribute read');}return get.call(this,key);};
    }
    for(const name of ['setAttribute','removeAttribute','append','remove','focus','setSelectionRange']){
      const original=f.Node.prototype[name];
      f.Node.prototype[name]=function(...args){if(diagnosticStack()){mutations++;throw Error('diagnostic mutation');}return original.apply(this,args);};
    }
    const op=bind();f.stage(op);await f.commit(op);const reply=observe(op),facts=reply.entryDiagnostics.edgeCalibration;
    assert.equal(facts.baselineAvailable,true);assert.equal(facts.originalDraftCurrent,true);assert.equal(facts.samplingFailed,false);
    assert.equal(facts.baselineAttachmentNodes,2);assert.equal(facts.progressNodes,1);
    assert.equal(reads,0);assert.equal(mutations,0);assert.equal(f.setters,1);assert.equal(f.changes,1);assert.equal(f.sends,0);
    results.push({probe:'excluded-content-read-and-mutation-traps',pass:true,excludedRoots:excluded.length,historyReads:reads,diagnosticMutations:mutations});
  }
  {
    const {f,context,bind,observe}=setup();const op=bind();f.stage(op);await f.commit(op);
    context.sessionID='different-process-session';
    for(let i=0;i<5;i++){
      const reply=observe(op),facts=reply.entryDiagnostics.edgeCalibration;
      assert.equal(facts.originalDraftCurrent,false);assert.equal(facts.matchedNodes,0);assert.equal(facts.progressValueKnown,false);
      assert.equal(reply.observation.state,'inputTriggered');assert.equal(reply.observation.uploadStart,undefined);
    }
    assert.equal(f.setters,1);assert.equal(f.changes,1);assert.equal(f.sends,0);
    results.push({probe:'original-process-session-mismatch-repeated-observation',pass:true,observations:5,setters:f.setters,changes:f.changes});
  }
  {
    const {f,bind,observe}=setup();const op=bind();f.stage(op);await f.commit(op);
    const stored=f.context.__riftletIndependentFileInput20261104.operations.get(op.identity.operationID);
    stored.edgeCalibration.invocationID=randomUUID();
    const reply=observe(op);assert.equal(reply.entryDiagnostics.edgeCalibration,undefined);
    assert.equal(reply.observation.state,'inputTriggered');assert.equal(f.setters,1);assert.equal(f.changes,1);
    results.push({probe:'calibration-invocation-mismatch-does-not-lend-sidecar',pass:true});
  }
  {
    const {f,bind,observe}=setup();const op=bind();f.stage(op);await f.commit(op);
    const card=f.form.querySelectorAll('[data-file-name]').find(node=>node.getAttribute('data-file-name')===op.name);
    card.setAttribute('data-state','complete');card.querySelector('[role="progressbar"]').setAttribute('aria-valuenow','100');
    const image=card.querySelector('img');image.complete=true;image.naturalWidth=1;
    for(let i=0;i<5;i++){
      const reply=observe(op),facts=reply.entryDiagnostics.edgeCalibration;
      assert.equal(facts.readyAttributeNodes,1);assert.equal(facts.progressPercentMaximum,100);assert.equal(facts.loadedImageNodes,1);
      assert.equal(reply.observation.state,'inputTriggered');assert.equal(reply.observation.uploadStart,undefined);
      assert.equal(reply.observation.completionEvidence,undefined);assert.equal(reply.observation.automaticRetryExcluded,false);
      assert.equal(Object.values(facts).every(v=>typeof v==='boolean'||Number.isSafeInteger(v)),true);
      assert.equal(JSON.stringify(reply.entryDiagnostics).includes(op.name),false);
    }
    assert.throws(()=>f.commit(op),/COMMIT_REFUSED/);assert.equal(f.setters,1);assert.equal(f.changes,1);assert.equal(f.sends,0);
    results.push({probe:'complete-looking-facts-never-admit-start-completion-or-retry',pass:true,observations:5});
  }
  console.log(JSON.stringify({scope:'independent controlled DOM review probes; not commercial acceptance',results},null,2));
}
run().catch(error=>{console.error(error);process.exitCode=1;});
