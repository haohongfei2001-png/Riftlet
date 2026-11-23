'use strict';
const assert = require('node:assert/strict');

module.exports = async function selectionCase(qa, driver, tab, direction) {
  const text = 'Riftlet QA: preserve this original draft while attaching images.';
  const phrase = 'preserve this original draft';
  async function attach(index) {
    const input = await qa('commit', index);
    assert.equal(input.commit, 'inputTriggered');
    assert.equal(input.repeat, 'COMMIT_REFUSED');
    assert.equal(input.pending.start, false);
    const published = await qa('publish', index);
    assert.deepEqual(published.decoded, [36,24]);
    assert.deepEqual(published.pixelProof, {pixels:864,differentPixels:0,partialAlpha:288,differentAlpha:0});
    const accepted = await qa('settle', index, 1800);
    assert.ok(accepted.start && accepted.original && accepted.exact && accepted.inputCount === 1);
    assert.equal(accepted.state, 'uploadStarted');
    assert.ok(accepted.startSequence > accepted.inputSequence && accepted.inputSequence > 0);
    for (const id of [input.opID, input.inv, input.sha, accepted.attachmentID, accepted.evidenceID]) {
      assert.ok(typeof id === 'string' && id.length > 0);
    }
    return {operation:input.opID, invocation:input.inv, fileSHA256:input.sha,
      attachmentID:accepted.attachmentID, evidenceID:accepted.evidenceID};
  }
  async function arrow(key, select = false) {
    for (const type of ['rawKeyDown','keyUp']) {
      await driver.call('Input.dispatchKeyEvent', {type, key, code:key, modifiers:select ? 8 : 0,
        windowsVirtualKeyCode:key === 'ArrowLeft' ? 37 : 39}, tab.sessionId);
    }
  }
  assert.equal(await qa('prepare'), 0);
  const seed = await attach(0);
  assert.equal(await qa('editorReady', ''), true);
  await driver.call('Input.insertText', {text}, tab.sessionId);
  assert.equal(await qa('editorReady', text), true);
  const start = text.indexOf(phrase), end = start + phrase.length;
  const anchor = direction === 'forward' ? start : end;
  for (let i = text.length; i > anchor; i--) await arrow('ArrowLeft');
  await assert.rejects(qa('selectionBefore', text, phrase), /original QA text or selection missing/);
  for (let i = 0; i < phrase.length; i++) await arrow(direction === 'forward' ? 'ArrowRight' : 'ArrowLeft', true);
  const before = await qa('selectionBefore', text, phrase);
  assert.deepEqual(before, {text,selectedText:phrase,start,end,anchor,focus:direction === 'forward' ? end : start,direction});
  assert.equal(await qa('prepare'), 1);
  const prior = await qa('selectionContext', 1);
  assert.ok(prior.documentID && prior.composerID && prior.draftEpoch && prior.original && prior.cardsExact && prior.seedPresent && prior.oldCardsIntact && prior.priorCards === 2);
  assert.deepEqual(prior.counts, {setter:1,input:1,change:1,send:0});
  assert.equal(prior.sendClicks, 0);
  const added = await attach(1);
  for (const key of Object.keys(seed)) assert.notEqual(seed[key], added[key]);
  const after = await qa('selectionAfter');
  assert.deepEqual(after, before);
  const final = await qa('selectionContext', 1);
  assert.deepEqual(final, {...prior, counts:{setter:2,input:2,change:2,send:0}});
  await qa('replacePriorForControl');
  assert.equal((await qa('selectionContext', 1)).oldCardsIntact, false);
  await qa('reverseSelectionForControl');
  await assert.rejects(qa('selectionAfter'), /selection endpoints changed/);
  await arrow('ArrowLeft');
  await assert.rejects(qa('selectionAfter'), /original QA text or selection missing/);
  return {before,after,prior,final,seed,added,collapsedSelectionRejectedBeforeAndAfter:true, identicalPriorCardCloneRejected:true, reversedDirectionRejected:true};
};
