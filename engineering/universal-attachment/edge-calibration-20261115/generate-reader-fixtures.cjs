'use strict';
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {fixture, native} = require('../../../Tests/WebPageProgram/independent-input-fixture.cjs');

function edge() {
  const f = fixture({nativeContext:{...native, applicationID:'com.microsoft.edgemac', sessionID:'edge-kernel-v1:7:10:1'}});
  const navigation = new EventTarget(); navigation.currentEntry = {id:randomUUID()};
  const activity = new EventTarget();
  f.context.navigation = navigation;
  f.context.addEventListener = activity.addEventListener.bind(activity);
  f.context.removeEventListener = activity.removeEventListener.bind(activity);
  f.context.setTimeout = (fn, delay) => setTimeout(fn, delay).unref();
  return f;
}

(async () => {
  const fixtures = [];
  for (const label of ['ready-looking-facts', 'undeclared-root', 'pruned-history', 'limited-scan']) {
    const f = edge();
    if (label === 'undeclared-root') f.form.tagName = 'DIV';
    const clickWitnessID = randomUUID();
    assert.equal(f.call({action:'pinTarget', clickWitnessID, address:f.context.location.href}), 'bound');
    const op = f.bind({target:f.call({action:'captureTarget', clickWitnessID})});
    f.stage(op); await f.commit(op);
    const card = f.form.querySelectorAll('[data-file-name]').find(node => node.getAttribute('data-file-name') === op.name);
    let expected;
    if (label === 'ready-looking-facts') {
      card.setAttribute('data-state','ready'); card.querySelector('[role="progressbar"]').setAttribute('aria-valuenow','100');
      expected = {baselineAvailable:true, originalDraftCurrent:true, originalTextUnchanged:true,
        originalSelectionUnchanged:true, matchedOriginalFormNodes:2, progressPercentMaximum:100, readyAttributeNodes:1};
    } else if (label === 'undeclared-root') {
      expected = {baselineAvailable:false, beforeInputBaselineAvailable:false, originalDraftCurrent:false,
        matchedNodes:0, progressNodes:0, readyAttributeNodes:0};
    } else if (label === 'pruned-history') {
      const history = card.append(new f.Node('article'));
      history.append(f.oldCard);
      history.append(new f.Node('div', {'data-file-name':op.name, 'data-state':'ready'}))
        .append(new f.Node('div', {role:'progressbar', 'aria-valuenow':'100'}));
      expected = {baselineAvailable:true, originalDraftCurrent:true, originalTextUnchanged:true,
        originalSelectionUnchanged:true, matchedNodes:2, retainedBaselineAttachmentNodes:0,
        progressPercentMaximum:10, readyAttributeNodes:0};
    } else {
      for (let index = 0; index < 513; index++) f.form.append(new f.Node('button', {type:'button'}));
      expected = {baselineAvailable:true, scanLimited:true, originalDraftCurrent:false, matchedNodes:0, progressNodes:0};
    }
    const reply = f.call(op.command('observe'));
    assert.equal(reply.observation.state,'inputTriggered');
    assert.equal(reply.observation.uploadStart,undefined); assert.equal(reply.observation.completionEvidence,undefined);
    for (const [key,value] of Object.entries(expected)) assert.equal(reply.entryDiagnostics.edgeCalibration[key],value,label + ':' + key);
    assert.equal(f.setters,1); assert.equal(f.changes,1); assert.equal(f.sends,0);
    fixtures.push({label, reply, expected});
  }
  process.stdout.write(JSON.stringify(fixtures,null,2) + '\n');
})().catch(error => { console.error(error); process.exitCode = 1; });
