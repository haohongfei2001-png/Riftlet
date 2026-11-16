'use strict';
// Controlled DOM command tests only; these facts do not admit commercial upload
// START/completion, and no browser, private profile or service is contacted.
const test = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {fixture, native} = require('./independent-input-fixture.cjs');

function edgeFixture(options = {}) {
  const f = fixture({...options, nativeContext: {...native,
    applicationID:'com.microsoft.edgemac', sessionID:'edge-kernel-v1:7:10:1'}});
  const navigation = new EventTarget(); navigation.currentEntry = {id:randomUUID()};
  const activity = new EventTarget();
  f.context.navigation = navigation;
  f.context.addEventListener = activity.addEventListener.bind(activity);
  f.context.removeEventListener = activity.removeEventListener.bind(activity);
  f.context.setTimeout = (fn, delay) => setTimeout(fn, delay).unref();
  const bind = () => {
    const clickWitnessID = randomUUID(), location = new URL(f.context.location.href);
    assert.equal(f.call({action:'pinTarget', clickWitnessID, address:location.origin + location.pathname}), 'bound');
    return f.bind({target:f.call({action:'captureTarget', clickWitnessID})});
  };
  const observe = op => f.call(op.command('observe'));
  return {f, navigation, bind, observe};
}

function calibration(reply) {
  const value = reply.entryDiagnostics?.edgeCalibration;
  assert.ok(value);
  assert.equal(value.version, 1);
  assert.equal(value.samplingFailed, false);
  assert.ok(Buffer.byteLength(JSON.stringify(reply.entryDiagnostics)) <= 2048);
  assert.ok(Object.values(value).every(v => typeof v === 'boolean' || Number.isSafeInteger(v)));
  assert.equal(reply.observation.state, 'inputTriggered');
  assert.equal(reply.observation.uploadStart, undefined);
  assert.equal(reply.observation.completionEvidence, undefined);
  assert.equal(reply.observation.exactImageIdentity, false);
  assert.equal(reply.observation.automaticRetryExcluded, false);
  return value;
}

function captureBaseline(f) {
  f.call({action:'captureTarget'});
  return f.context.__riftletIndependentFileInput20261104.current.edgeCalibrationBaseline;
}

test('capture alone never scans a body, html or undeclared fallback as a calibration root', () => {
  for (const scope of ['body', 'html', 'undeclared', 'history-ancestor']) {
    const {f} = edgeFixture();
    if (scope === 'body' || scope === 'html') {
      f.body.append(f.editor, f.input, f.oldCard); f.form.remove();
      if (scope === 'html') f.body.tagName = 'HTML';
    } else if (scope === 'undeclared') f.form.tagName = 'DIV';
    else f.body.append(new f.Node('article')).append(f.form);
    const history = f.body.append(new f.Node('div', {'data-message-author-role':'assistant'}));
    history.append(new f.Node('div', {'data-file-name':'historical-private.png'}))
      .append(new f.Node('img', {src:'blob:historical-private'}));
    const baseline = captureBaseline(f);
    assert.equal(baseline === null, true, scope);
    assert.equal(f.setters, 0); assert.equal(f.changes, 0); assert.equal(f.sends, 0);
  }
});

test('capture prunes transcript, ancillary and nested composer subtrees inside a declared form', () => {
  const {f} = edgeFixture();
  const excluded = [
    ['article', {}], ['div', {'data-message-author-role':'assistant'}], ['aside', {}],
    ['nav', {}], ['header', {}], ['div', {role:'search'}], ['div', {role:'menu'}],
    ['div', {role:'dialog'}], ['form', {}], ['div', {'data-testid':'composer'}]
  ];
  for (const [tag, attributes] of excluded) {
    const subtree = f.form.append(new f.Node(tag, attributes));
    subtree.append(new f.Node('div', {'data-file-name':'historical-private.png', role:'button'}))
      .append(new f.Node('img', {src:'blob:historical-private'}));
  }
  const baseline = captureBaseline(f);
  assert.ok(baseline); assert.equal(baseline.nodes.length, 2);
  assert.equal(baseline.nodes.every(node => f.oldCard.contains(node)), true);
  assert.equal(f.setters, 0); assert.equal(f.changes, 0); assert.equal(f.sends, 0);
});

test('a declared non-form composer retains bounded local diagnostics', () => {
  const {f} = edgeFixture();
  f.form.tagName = 'DIV'; f.form.setAttribute('data-chatgpt-composer', '');
  assert.equal(captureBaseline(f)?.nodes.length, 2);
  assert.equal(f.setters, 0); assert.equal(f.changes, 0); assert.equal(f.sends, 0);
});

test('calibration never restarts descendant queries outside its single bounded traversal', async () => {
  const {f, bind, observe} = edgeFixture();
  const original = f.Node.prototype.querySelectorAll;
  let diagnosticQueries = 0;
  f.Node.prototype.querySelectorAll = function(selector) {
    if (new Error().stack.includes('edgeCalibration')) {
      diagnosticQueries++;
      throw new Error('diagnostic descendant query bypassed traversal budget');
    }
    return original.call(this, selector);
  };
  const op = bind(); f.stage(op); await f.commit(op);
  const facts = calibration(observe(op));
  assert.equal(facts.baselineAvailable, true); assert.equal(facts.baselineAttachmentNodes, 2);
  assert.equal(facts.progressNodes, 1); assert.equal(facts.progressPercentMaximum, 10);
  assert.equal(diagnosticQueries, 0);
  assert.equal(f.setters, 1); assert.equal(f.changes, 1); assert.equal(f.sends, 0);
});

test('matching cards cannot lend indicators or retention through a historical descendant', async () => {
  const {f, bind, observe} = edgeFixture(), op = bind(); f.stage(op); await f.commit(op);
  const card = f.form.querySelectorAll('[data-file-name]').find(node => node.getAttribute('data-file-name') === op.name);
  const history = card.append(new f.Node('article'));
  history.append(new f.Node('div', {'data-file-name':op.name, 'data-state':'ready'}))
    .append(new f.Node('div', {role:'progressbar', 'aria-valuenow':'100'}));
  history.append(f.oldCard);
  const facts = calibration(observe(op));
  assert.equal(facts.matchedNodes, 2); assert.equal(facts.progressNodes, 1);
  assert.equal(facts.progressPercentMaximum, 10); assert.equal(facts.readyAttributeNodes, 0);
  assert.equal(facts.retainedBaselineAttachmentNodes, 0);
  assert.equal(f.setters, 1); assert.equal(f.changes, 1); assert.equal(f.sends, 0);
});

test('Edge sidecar binds two independent files to their original draft without granting START', async () => {
  const {f, bind, observe} = edgeFixture();
  f.document.activeElement = f.body;
  const text = f.editor.textContent, operations = [];
  for (let index = 0; index < 2; index++) {
    const op = bind(); operations.push(op); f.stage(op); await f.commit(op);
    const reply = observe(op), facts = calibration(reply);
    assert.equal(facts.baselineAvailable, true); assert.equal(facts.beforeInputBaselineAvailable, true);
    assert.equal(facts.originalDraftCurrent, true); assert.equal(facts.clickBound, true);
    assert.equal(facts.originalTextUnchanged, true); assert.equal(facts.selectionComparable, true);
    assert.equal(facts.originalSelectionUnchanged, true);
    assert.equal(facts.baselineAttachmentNodes, 2 + index * 2);
    assert.equal(facts.retainedBaselineAttachmentNodes, facts.baselineAttachmentNodes);
    assert.equal(facts.filenameMatchedNodes, 2); assert.equal(facts.newMatchedNodes, 2);
    assert.equal(facts.matchedOriginalFormNodes, 2); assert.equal(facts.progressNodes, 1);
    assert.equal(facts.progressValueKnown, true); assert.equal(facts.progressPercentMinimum, 10);
    assert.equal(facts.progressPercentMaximum, 10);
    const emitted = JSON.stringify(reply.entryDiagnostics);
    for (const forbidden of [text, op.name, 'blob:', 'existing.png']) assert.equal(emitted.includes(forbidden), false);
  }
  const first = calibration(observe(operations[0]));
  assert.equal(first.matchedNodes, 2); assert.equal(first.baselineAttachmentNodes, 2);
  assert.ok(first.sampleNumber > 2);
  assert.equal(f.setters, 2); assert.equal(f.changes, 2); assert.equal(f.sends, 0); assert.equal(f.chooserOpens, 0);
  assert.equal(f.editor.textContent, text); assert.equal(f.document.activeElement, f.body);
});

test('progress, ready attributes and loaded images remain separate untrusted facts', async () => {
  const {f, bind, observe} = edgeFixture(), op = bind(); f.stage(op); await f.commit(op);
  const card = f.form.querySelectorAll('[data-file-name]').find(node => node.getAttribute('data-file-name') === op.name);
  const progress = card.querySelector('[role="progressbar"]'), image = card.querySelector('img');
  card.setAttribute('aria-busy','true'); progress.setAttribute('aria-valuenow','80');
  const advancing = calibration(observe(op));
  assert.equal(advancing.progressPercentMaximum, 80); assert.equal(advancing.busyAttributeNodes, 1);
  card.removeAttribute('aria-busy'); card.setAttribute('data-state','ready');
  progress.setAttribute('aria-valuenow','100'); image.complete = true; image.naturalWidth = 1;
  const ready = calibration(observe(op));
  assert.equal(ready.progressPercentMaximum, 100); assert.equal(ready.readyAttributeNodes, 1);
  assert.equal(ready.loadedImageNodes, 1);
  progress.remove(); card.removeAttribute('data-state');
  const absent = calibration(observe(op));
  assert.equal(absent.progressNodes, 0); assert.equal(absent.progressValueKnown, false);
  assert.equal(absent.readyAttributeNodes, 0);
  card.setAttribute('data-state','failed');
  assert.equal(calibration(observe(op)).errorAttributeNodes, 1);
  assert.equal(f.setters, 1); assert.equal(f.changes, 1); assert.equal(f.sends, 0);
});

test('original text, exact selection and original attachment nodes are compared without restoring user edits', async () => {
  const {f, bind, observe} = edgeFixture(), op = bind(); f.stage(op); await f.commit(op);
  f.editor.textContent = 'User changed this draft'; f.selection.setBaseAndExtent(f.editor, 0, f.editor, 0);
  f.oldCard.remove();
  const facts = calibration(observe(op));
  assert.equal(facts.originalDraftCurrent, true); assert.equal(facts.originalTextUnchanged, false);
  assert.equal(facts.selectionComparable, true); assert.equal(facts.originalSelectionUnchanged, false);
  assert.equal(facts.baselineAttachmentNodes, 2); assert.equal(facts.retainedBaselineAttachmentNodes, 0);
  assert.equal(f.editor.textContent, 'User changed this draft'); assert.equal(f.selection.anchorOffset, 0);
  assert.equal(f.oldCard.isConnected, false); assert.equal(f.setters, 1);
});

test('original operation cannot sample a replacement editor, document or navigation ABA', async () => {
  for (const change of ['editor', 'reattach', 'document', 'navigation']) {
    const {f, navigation, bind, observe} = edgeFixture(), op = bind(); f.stage(op); await f.commit(op);
    if (change === 'navigation') navigation.dispatchEvent(new Event('currententrychange'));
    else if (change === 'document') f.document.documentElement = new f.Node('html');
    else {
      f.editor.remove();
      f.form.append(change === 'reattach' ? f.editor : new f.Node('div',{id:'prompt-textarea',contenteditable:'true'}));
    }
    const facts = calibration(observe(op));
    assert.equal(facts.originalDraftCurrent, false, change);
    assert.equal(facts.originalTextUnchanged, false); assert.equal(facts.matchedNodes, 0);
    assert.equal(facts.progressNodes, 0); assert.equal(facts.readyAttributeNodes, 0);
    assert.equal(f.setters, 1); assert.equal(f.changes, 1);
  }
});

test('another operation identity never receives the original sidecar', async () => {
  const {f, bind, observe} = edgeFixture(), op = bind(); f.stage(op); await f.commit(op);
  const command = op.command('observe');
  command.identity = {...command.identity, operationID:randomUUID()};
  const wrong = f.call(command);
  assert.equal(wrong.observation.state, 'invalidated'); assert.equal(wrong.entryDiagnostics, undefined);
  assert.equal(calibration(observe(op)).matchedNodes, 2);
  assert.throws(() => f.commit(op), /COMMIT_REFUSED/);
  assert.equal(f.setters, 1); assert.equal(f.changes, 1);
});

test('unowned same-filename indicators cannot borrow original form ownership', async () => {
  const {f, bind, observe} = edgeFixture({accept:false}), op = bind(); f.stage(op); await f.commit(op);
  const outside = f.body.append(new f.Node('div',{'data-file-name':op.name, 'data-state':'ready'}));
  outside.append(new f.Node('div',{role:'progressbar','aria-valuenow':'100'}));
  f.addCard(op.name + '-unrelated');
  const facts = calibration(observe(op));
  assert.equal(facts.matchedNodes, 0); assert.equal(facts.matchedOriginalFormNodes, 0);
  assert.equal(facts.progressNodes, 0); assert.equal(facts.readyAttributeNodes, 0);
  assert.equal(facts.loadedImageNodes, 0); assert.equal(f.setters, 1);
});

test('placeholder and missing progress do not become positive upload evidence', async () => {
  const {f, bind, observe} = edgeFixture({accept:false}), op = bind(); f.stage(op); await f.commit(op);
  f.addCard(op.name,{placeholder:true,progress:false});
  const facts = calibration(observe(op));
  assert.equal(facts.matchedNodes, 1); assert.equal(facts.changedMatchedPreviews, 0);
  assert.equal(facts.progressNodes, 0); assert.equal(facts.loadedImageNodes, 0);
  assert.equal(facts.progressValueKnown, false); assert.equal(facts.readyAttributeNodes, 0);
});

test('bounded or unavailable calibration never prevents a responsible input', async () => {
  for (const limited of ['text', 'nodes', 'tree', 'undeclared-root', 'exception']) {
    const {f, bind, observe} = edgeFixture();
    if (limited === 'text') f.editor.textContent = 'x'.repeat(65537);
    else if (limited === 'nodes') for (let n = 0; n < 513; n++) f.form.append(new f.Node('img',{src:'blob:prior-' + n}));
    else if (limited === 'tree') for (let n = 0; n < 2049; n++) f.form.append(new f.Node('section'));
    else if (limited === 'undeclared-root') f.form.tagName = 'DIV';
    else {
      const matches = f.oldCard.matches.bind(f.oldCard);
      f.oldCard.matches = selector => {
        if (selector.includes('img[alt]')) throw new TypeError('private fixture exception');
        return matches(selector);
      };
    }
    const op = bind(); f.stage(op); await f.commit(op);
    const facts = calibration(observe(op));
    assert.equal(facts.baselineAvailable, false, limited);
    assert.equal(facts.originalDraftCurrent, false); assert.equal(facts.matchedNodes, 0);
    assert.equal(f.setters, 1); assert.equal(f.changes, 1); assert.equal(f.sends, 0);
  }
});

test('a failed diagnostic read after input cannot throw away the original observation or repeat input', async () => {
  const {f, bind, observe} = edgeFixture(), op = bind(); f.stage(op); await f.commit(op);
  const progress = f.form.querySelector('[role="progressbar"]'), get = progress.getAttribute.bind(progress);
  progress.getAttribute = key => {
    if (key === 'aria-valuenow') throw new TypeError('private fixture error');
    return get(key);
  };
  const reply = observe(op);
  assert.equal(reply.entryDiagnostics.edgeCalibration.samplingFailed, true);
  assert.equal(JSON.stringify(reply.entryDiagnostics).includes('private fixture error'), false);
  assert.equal(reply.observation.state, 'inputTriggered'); assert.equal(reply.observation.uploadStart, undefined);
  assert.equal(f.setters, 1); assert.equal(f.changes, 1);
});

test('an oversized later DOM scan reports its limit instead of a partial progress claim', async () => {
  const {f, bind, observe} = edgeFixture(), op = bind(); f.stage(op); await f.commit(op);
  for (let index = 0; index < 513; index++) f.form.append(new f.Node('button',{type:'button'}));
  const facts = calibration(observe(op));
  assert.equal(facts.baselineAvailable, true); assert.equal(facts.beforeInputBaselineAvailable, true);
  assert.equal(facts.scanLimited, true); assert.equal(facts.matchedNodes, 0);
  assert.equal(facts.progressNodes, 0); assert.equal(facts.progressValueKnown, false);
  assert.equal(f.setters, 1); assert.equal(f.changes, 1);
});

test('textarea comparison preserves reverse selection without keyboard focus', async () => {
  const {f, bind, observe} = edgeFixture({editorTag:'textarea'}); f.document.activeElement = f.body;
  const op = bind(); f.stage(op); await f.commit(op);
  const facts = calibration(observe(op));
  assert.equal(facts.originalTextUnchanged, true); assert.equal(facts.selectionComparable, true);
  assert.equal(facts.originalSelectionUnchanged, true); assert.equal(f.document.activeElement, f.body);
  f.editor.setSelectionRange(2,7,'forward');
  assert.equal(calibration(observe(op)).originalSelectionUnchanged, false);
});

test('capture-time snapshot is not overwritten by a later click on the same draft', async () => {
  const {f, bind, observe} = edgeFixture(), first = bind();
  f.editor.textContent = 'Later draft text'; const second = bind();
  f.stage(first); await f.commit(first); f.stage(second); await f.commit(second);
  assert.equal(calibration(observe(first)).originalTextUnchanged, false);
  assert.equal(calibration(observe(second)).originalTextUnchanged, true);
  assert.equal(f.setters, 2); assert.equal(f.changes, 2);
});

test('Chrome keeps its existing receipt behavior and has no Edge calibration sidecar', async () => {
  const f = fixture(), op = f.bind(); f.stage(op);
  const result = await f.commit(op);
  assert.equal(result.observation.state, 'uploadStarted'); assert.equal(result.entryDiagnostics.edgeCalibration, undefined);
  assert.equal(f.setters, 1); assert.equal(f.changes, 1); assert.equal(f.sends, 0);
});

const calibratedTemporary = 'https://chatgpt.com/?temporary-chat=true';
function edgeProgressFixture({route = calibratedTemporary, candidate = true, prepare, beforeInput, render} = {}) {
  const controls = edgeFixture({route, accept:false}), {f} = controls;
  const cards = [];
  prepare?.(f);
  f.setChange(file => {
    const url = f.context.URL.createObjectURL(file);
    const card = f.addCard(file.name);
    const image = card.querySelector('img'), bar = card.querySelector('[role="progressbar"]');
    image.setAttribute('src', url);
    const current = {card, image, bar, file};
    render?.(f, current); cards.push(current);
  });
  const submit = async () => {
    const op = controls.bind();
    beforeInput?.(f);
    f.stage(op, candidate ? {edgeProgressCandidate:true} : {});
    const reply = await f.commit(op);
    assert.equal(reply.observation.state, 'inputTriggered');
    return op;
  };
  return {...controls, cards, submit};
}

test('Edge START binds independent in-flight PNGs to their own fresh card, File URL and advancing control', async () => {
  const {f, cards, submit, observe} = edgeProgressFixture();
  const first = await submit(), second = await submit();
  const [a, b] = cards;
  b.bar.setAttribute('aria-valuenow','12.5');
  assert.equal(observe(first).observation.state, 'inputTriggered');
  const two = observe(second).observation;
  assert.equal(two.state, 'uploadStarted'); assert.equal(two.uploadStart.signal,'correlatedProgress');
  assert.equal(two.uploadStart.previousProgress,10); assert.equal(two.uploadStart.currentProgress,12.5);
  assert.ok(two.uploadStart.startObservedAtMS > two.uploadStart.inputObservedAtMS);
  assert.equal(two.uploadStart.inputCount,1); assert.equal(two.isUploading,true);
  assert.equal(two.exactImageIdentity,true); assert.equal(two.belongsToOriginalDraft,true);
  assert.equal(two.completionEvidence,undefined); assert.equal(two.automaticRetryExcluded,false);
  a.bar.setAttribute('aria-valuenow','19');
  const one = observe(first).observation;
  assert.equal(one.state,'uploadStarted'); assert.equal(one.uploadStart.currentProgress,19);
  assert.notEqual(one.attachmentID,two.attachmentID); assert.notEqual(one.uploadStart.evidenceID,two.uploadStart.evidenceID);
  assert.equal(observe(first).observation.uploadStart.evidenceID,one.uploadStart.evidenceID);
  assert.equal(f.setters,2); assert.equal(f.changes,2); assert.equal(f.sends,0);
});

test('Edge progress refuses historical sources, other routes, stale or ambiguous page evidence', async t => {
  const cases = {
    'not enrolled': {candidate:false},
    'ordinary draft': {route:'https://chatgpt.com/c/mock'},
    'similar temporary query': {route:'https://chatgpt.com/?temporary-chat=true&other=1'},
    'blob from another File': {render:(f,c) => c.image.setAttribute('src', f.context.URL.createObjectURL(new File(['x'], c.file.name)))},
    'prior preview': {render:(f,c) => {c.image.remove(); const old=f.oldCard.querySelector('img'); c.card.append(old); old.setAttribute('src',c.image.getAttribute('src'));}},
    'wrong filename': {render:(f,c) => {for(const n of [c.card,c.image]) for(const k of ['data-file-name','alt','title','aria-label']) n.setAttribute(k,'different.png');}},
    'second named card': {render:(f,c) => f.addCard(c.file.name)},
    'anonymous tray with differently named owners': {render:(f,c) => {
      const group = f.form.append(new f.Node('div')), sibling = group.append(new f.Node('div',{'data-file-name':'different.png'}));
      group.append(c.card); sibling.append(c.bar);
    }},
    'two bars': {render:(f,c) => c.card.append(new f.Node('div',{role:'progressbar','aria-valuenow':'5'}))},
    'extra change of the same File': {change:f => {f.setChange(null); f.input.dispatchEvent(new f.context.Event('change',{bubbles:true}));}, changes:2},
    'finish and reset between observations': {change:(f,c) => {c.bar.setAttribute('aria-valuenow','100'); c.bar.setAttribute('aria-valuenow','3');}},
    'remove and reinsert a prior attachment during staging': {beforeInput:f => {f.oldCard.remove(); f.form.append(f.oldCard);}},
    'replace bar': {change:(f,c) => {c.bar.remove(); c.bar=c.card.append(new f.Node('div',{role:'progressbar','aria-valuenow':'21'}));}},
    'move card and restore': {change:(f,c) => {c.card.remove(); f.form.append(c.card);}},
    'move bar and restore': {change:(f,c) => {c.bar.remove(); c.card.append(c.bar);}},
    'recycle previous bar': {prepare:f => {f.existingBar=f.oldCard.append(new f.Node('div',{role:'progressbar','aria-valuenow':'10'}));},
      render:(f,c) => {c.bar.remove(); c.bar=c.card.append(f.existingBar);}},
    'rename and restore': {change:(f,c) => {c.card.setAttribute('title','another'); c.card.setAttribute('title',c.file.name);}},
    'prior attachment removed': {change:f => f.oldCard.remove()},
    'original selection changed': {change:f => f.selection.setBaseAndExtent(f.editor,0,f.editor,0)},
    'original text changed': {change:f => {f.editor.textContent='updated';}},
    'original document replaced': {change:f => {f.document.documentElement=new f.Node('html');}},
    'error': {change:(f,c) => c.card.setAttribute('data-state','failed')},
    'ready': {change:(f,c) => c.card.setAttribute('data-state','ready')},
    'bar restarted': {intermediate:'2'},
    'unknown gap': {intermediate:''},
    '100 is not START': {intermediate:'100'},
    'static value': {final:'10'}, 'invalid later scale': {change:(f,c) => c.bar.setAttribute('aria-valuemax','50')},
    'no second instant': {prepare:f => {f.context.performance={now:()=>100};}}
  };
  for (const [name, options] of Object.entries(cases)) await t.test(name, async () => {
    const {f, cards, submit, observe} = edgeProgressFixture(options);
    const operation = await submit(), current = cards[0];
    options.change?.(f,current);
    if (options.intermediate !== undefined) {
      current.bar.setAttribute('aria-valuenow',options.intermediate);
      assert.equal(observe(operation).observation.state,'inputTriggered');
    }
    current.bar.setAttribute('aria-valuenow',options.final ?? '25');
    const result = observe(operation).observation;
    assert.equal(result.state,'inputTriggered'); assert.equal(result.uploadStart,undefined);
    assert.equal(result.completionEvidence,undefined); assert.equal(result.automaticRetryExcluded,false);
    assert.equal(f.setters,1); assert.equal(f.changes,options.changes ?? 1); assert.equal(f.sends,0);
  });
});


test('an input cannot reclaim another operation’s previously observed detached progressbar', async () => {
  let priorBar;
  const {f, cards, submit, observe} = edgeProgressFixture({render:(fixture,c) => {
    if (priorBar) { c.bar.remove(); c.bar=c.card.append(priorBar); }
    else priorBar=c.bar;
  }});
  const first = await submit(), original = cards[0];
  original.bar.setAttribute('aria-valuenow','14');
  assert.equal(observe(first).observation.state,'uploadStarted');
  original.card.remove(); priorBar.remove(); priorBar.setAttribute('aria-valuenow','10');
  const second = await submit();
  priorBar.setAttribute('aria-valuenow','28');
  assert.equal(observe(second).observation.state,'inputTriggered');
  assert.equal(f.setters,2); assert.equal(f.changes,2);
});

test('a named Remove sibling must share one new card with the popup that owns both the exact File image and bar', async t => {
  for (const arrangement of ['sibling', 'other parent', 'third sibling', 'unrelated action', 'sibling bar']) {
    await t.test(arrangement, async () => {
      const {f, cards, submit, observe} = edgeProgressFixture({route:'https://chatgpt.com:443/?temporary-chat=true', render:(f,c) => {
        const local = f.form.append(new f.Node('div'));
        // Build the final initial DOM before inserting it into the observed form.
        // addCard() already inserted its fresh contents in this small fixture.
        const popup = new f.Node('button',{'aria-haspopup':'dialog', 'aria-label':c.file.name});
        const image = popup.append(new f.Node('img',{src:c.image.getAttribute('src'),alt:c.file.name}));
        const bar = new f.Node('div',{role:'progressbar','aria-valuenow':'10'});
        c.card.remove(); c.card=popup; c.image=image; c.bar=bar;
        const container = arrangement === 'other parent' ? f.form.append(new f.Node('div')) : local;
        const remove = new f.Node('button',{'aria-label':(arrangement === 'unrelated action' ? 'Open ' : '移除 ') + c.file.name});
        if (arrangement === 'sibling bar') remove.append(bar); else popup.append(bar);
        local.append(popup); container.append(remove);
        if (arrangement === 'third sibling') local.append(new f.Node('button',{'aria-label':'Another file'}));
      }});
      const op = await submit();
      cards[0].bar.setAttribute('aria-valuenow','36');
      assert.equal(observe(op).observation.state,arrangement === 'sibling' ? 'uploadStarted' : 'inputTriggered');
      assert.equal(f.setters,1); assert.equal(f.changes,1);
    });
  }
});

test('all original-form inputs contribute detached node history, including an unsampled asynchronous card', async t => {
  for (const enrolled of [false, true]) for (const delayed of [false, true]) await t.test(
    'enrolled=' + enrolled + ' delayed=' + delayed, async () => {
      const {f, bind, observe} = edgeFixture({route:calibratedTemporary, accept:false});
      let pending, cardA, barA;
      const render = file => {
        const card = f.addCard(file.name), image = card.querySelector('img'), bar = card.querySelector('[role="progressbar"]');
        image.setAttribute('src',f.context.URL.createObjectURL(file));
        if (!cardA) {cardA=card; barA=bar;} else {bar.remove(); card.append(barA);}
      };
      f.setChange(file => { if (delayed && !pending) pending=file; else render(file); });
      const a = bind(); f.stage(a,enrolled ? {edgeProgressCandidate:true} : {}); await f.commit(a);
      if (delayed) render(pending);
      cardA.remove(); barA.remove();
      const b = bind(); f.stage(b,{edgeProgressCandidate:true}); await f.commit(b);
      barA.setAttribute('aria-valuenow','35');
      const result = observe(b);
      assert.equal(result.observation.state,'inputTriggered');
      assert.equal(result.entryDiagnostics.edgeCalibration.progressDecision,'nodeReused');
      assert.equal(f.setters,2); assert.equal(f.changes,2);
    });
});

test('the exact original File must be present at change dispatch and capture; the receiver can clear it afterwards', async t => {
  for (const timing of ['before dispatch', 'before capture', 'after capture']) await t.test(timing, async () => {
    const {f, bind, observe} = edgeFixture({route:calibratedTemporary, accept:false});
    let bar;
    f.input.addEventListener('input', () => {
      const file = f.input.files[0], card = f.addCard(file.name);
      card.querySelector('img').setAttribute('src',f.context.URL.createObjectURL(file));
      bar = card.querySelector('[role="progressbar"]');
      if (timing === 'before dispatch') f.input.value='';
    });
    if (timing !== 'before dispatch') f.input.addEventListener('change', () => { f.input.value=''; }, timing === 'before capture');
    const op = bind(); f.stage(op,{edgeProgressCandidate:true}); await f.commit(op);
    bar.setAttribute('aria-valuenow','35');
    const result = observe(op);
    assert.equal(result.observation.state,timing === 'after capture' ? 'uploadStarted' : 'inputTriggered');
    assert.equal(result.entryDiagnostics.edgeCalibration.progressDecision,timing === 'after capture' ? 'started' : 'inputCount');
    assert.equal(f.setters,1); assert.equal(f.changes,1);
  });
});

test('staging and actual input have separate bounded clocks and a damaged click baseline is never renewed', async t => {
  for (const scenario of ['slow', 'expired click', 'expired input', 'prior edit']) await t.test(scenario, async () => {
    let now=100;
    const setup = edgeProgressFixture({prepare:f => { f.context.performance={now:()=>now++}; },
      beforeInput:f => {
        now+=scenario === 'expired click' ? 61000 : 31000;
        if (scenario === 'prior edit') { const prior=f.editor.textContent; f.editor.textContent='changed'; f.editor.textContent=prior; }
      }});
    const op=await setup.submit();
    now+=scenario === 'expired input' ? 31000 : 100;
    setup.cards[0].bar.setAttribute('aria-valuenow','35');
    const result=setup.observe(op);
    assert.equal(result.observation.state,scenario === 'slow' ? 'uploadStarted' : 'inputTriggered');
    assert.equal(setup.f.setters,1); assert.equal(setup.f.changes,1);
  });
});

test('a bounded history overflow keeps later detached identities uncertain without blocking input', async () => {
  const {f, bind, observe} = edgeFixture({route:calibratedTemporary, accept:false});
  const a=bind(); f.stage(a); await f.commit(a);
  const transient=new f.Node('div');
  for(let i=0;i<2050;i++) transient.append(new f.Node('span'));
  f.form.append(transient); transient.remove();
  let bar;
  f.setChange(file=>{const card=f.addCard(file.name);card.querySelector('img').setAttribute('src',f.context.URL.createObjectURL(file));bar=card.querySelector('[role="progressbar"]');});
  const b=bind();f.stage(b,{edgeProgressCandidate:true});await f.commit(b);bar.setAttribute('aria-valuenow','35');
  const reply=observe(b);
  assert.equal(reply.observation.state,'inputTriggered');assert.equal(reply.entryDiagnostics.edgeCalibration.progressDecision,'historyUnavailable');
  assert.equal(f.setters,2);assert.equal(f.changes,2);
});

test('Edge progress names must agree across the original card, control and accessible labels', async t => {
  const cases = [
    ...['aria-label','title','aria-description','aria-valuetext'].map(attr => ['control',attr]),
    ...['aria-label','title','aria-description'].map(attr => ['group',attr]),
    ...['alt','title','aria-label'].map(attr => ['image',attr]),
    ['card','title'], ['text'], ['reference','aria-labelledby'], ['reference','aria-describedby'],
    ['mixed names'], ['temporary','aria-valuetext'], ['temporary','data-file-name'],
    ['external reference'], ['native external label'], ['outside owner'], ['missing reference'], ['cyclic reference']
  ];
  for (const [kind, attr] of cases) for (const mode of ['current','generic','foreign']) {
    await t.test([kind,attr,mode].filter(Boolean).join(' / '), async () => {
      const {f, bind, observe} = edgeFixture({route:calibratedTemporary, accept:false});
      let previous, bar, name, label;
      f.setChange(file => {
        if (!previous) { previous = file.name; return; }
        name = file.name;
        label = mode === 'current' ? name : mode === 'foreign' ? previous : '上传进度 · 35.5%';
        const card = f.addCard(name,{progress:false}), image = card.querySelector('img');
        image.setAttribute('src',f.context.URL.createObjectURL(file));
        const group = card.append(new f.Node('div',{role:'group'}));
        bar = group.append(kind === 'native external label' ? new f.Node('progress',{value:'10',max:'100',id:'bar'})
          : new f.Node('div',{role:'progressbar','aria-valuenow':'10',id:'bar'}));
        const target = {card, group, image, control:bar}[kind];
        if (target) target.setAttribute(attr,label);
        if (kind === 'text') bar.textContent = label;
        if (kind === 'mixed names') group.setAttribute('title',name + ', ' + label);
        if (kind === 'reference' || kind === 'external reference' || kind === 'cyclic reference') {
          const root = kind === 'external reference' ? f.body : group;
          const ref = root.append(new f.Node('span',{id:'label'}));
          ref.textContent = label;
          if (kind === 'cyclic reference') ref.setAttribute('aria-labelledby','bar');
          bar.setAttribute(attr || 'aria-labelledby','label');
        }
        if (kind === 'native external label') f.body.append(new f.Node('label',{for:'bar'})).textContent = label;
        if (kind === 'outside owner') f.form.append(new f.Node('div',{'aria-owns':'bar','aria-label':label}));
        if (kind === 'missing reference') bar.setAttribute('aria-describedby','missing');
      });
      const first = bind(); f.stage(first,{edgeProgressCandidate:true}); await f.commit(first);
      const second = bind(); f.stage(second,{edgeProgressCandidate:true}); await f.commit(second);
      if (kind === 'temporary') bar.setAttribute(attr,label);
      bar.setAttribute(kind === 'native external label' ? 'value' : 'aria-valuenow','35');
      if (kind === 'temporary') bar.removeAttribute(attr);
      const reply = observe(second);
      const unknownOwner = ['external reference','native external label','outside owner','missing reference','cyclic reference'].includes(kind);
      const expected = !unknownOwner && mode !== 'foreign' && !(attr === 'data-file-name' && mode === 'generic');
      assert.equal(reply.observation.state,expected ? 'uploadStarted' : 'inputTriggered');
      assert.equal(reply.entryDiagnostics.edgeCalibration.progressDecision,expected ? 'started' : 'conflictingFileLabel');
      assert.equal(reply.observation.completionEvidence,undefined);
      assert.deepEqual([f.setters,f.changes,f.sends],[2,2,0]);
    });
  }
});

test('an extra change inspects the entire bounded FileList for the original operation', async t => {
  for (const [name,count,originalIndex,otherField,started] of [
    ['empty',0,-1,false,true], ['other files at the limit',32,-1,false,true],
    ['original first',3,0,false,false], ['original middle',3,1,false,false],
    ['original last',32,31,false,false], ['over limit',33,-1,false,false],
    ['rebuilt input, other files',2,-1,true,true], ['rebuilt input, mixed files',2,1,true,false]
  ]) await t.test(name,async () => {
    const {f,cards,submit,observe} = edgeProgressFixture();
    const original = await submit(), [{file,bar}] = cards;
    f.setChange(() => {});
    const field = otherField ? f.form.append(f.document.createElement('input')) : f.input;
    const transfer = new f.context.DataTransfer();
    for (let i = 0; i < count; i++) transfer.items.add(i === originalIndex ? file : new f.context.File(['other'],file.name));
    field.files = transfer.files;
    field.dispatchEvent(new f.context.Event('change',{bubbles:true}));
    bar.setAttribute('aria-valuenow','35');
    const result = observe(original);
    assert.equal(result.observation.state,started ? 'uploadStarted' : 'inputTriggered');
    assert.equal(result.entryDiagnostics.edgeCalibration.progressDecision,started ? 'started' : 'inputCount');
    assert.equal(f.sends,0);
  });
});

test('Edge examines complete local labels in DOM order before attributing progress', async t => {
  for (const structure of ['adjacent text','inline spans','nested referenced spans','progress contents']) {
    for (const mode of ['current','foreign','localized']) await t.test(structure+' / '+mode,async () => {
      const {f,bind,observe} = edgeFixture({route:calibratedTemporary,accept:false});
      let former, bar;
      f.setChange(file => {
        if (!former) { former = file.name; return; }
        const card = f.addCard(file.name,{progress:false});
        card.querySelector('img').setAttribute('src',f.context.URL.createObjectURL(file));
        bar = card.append(new f.Node('div',{role:'progressbar','aria-valuenow':'10'}));
        let label = bar;
        if (structure !== 'progress contents') {
          label = card.append(new f.Node('span',{id:'name'})); bar.setAttribute('aria-labelledby','name');
        }
        const value = mode === 'current' ? file.name : mode === 'foreign' ? former : '正在上传 · 10%';
        if (structure === 'nested referenced spans') label = label.append(new f.Node('span'));
        // Split through both the UUID and extension. The last suffix alone
        // can itself look like a file, although the full name belongs to B.
        for (const part of [value.slice(0,9),value.slice(9,-2),value.slice(-2)]) {
          const parent = structure === 'adjacent text' ? label : label.append(new f.Node('span'));
          f.appendText(parent,part);
        }
      });
      const first = bind(); f.stage(first,{edgeProgressCandidate:true}); await f.commit(first);
      const second = bind(); f.stage(second,{edgeProgressCandidate:true}); await f.commit(second);
      bar.setAttribute('aria-valuenow','35');
      const result = observe(second);
      assert.equal(result.observation.state,mode === 'foreign' ? 'inputTriggered' : 'uploadStarted');
      assert.equal(result.entryDiagnostics.edgeCalibration.progressDecision,mode === 'foreign' ? 'conflictingFileLabel' : 'started');
      assert.deepEqual([f.setters,f.changes,f.sends],[2,2,0]);
    });
  }
});

test('Edge refuses uncertain prior text between increasing progress samples', async t => {
  for (const variety of ['foreign then restored','missing prior value','readable generic text','overlong assembled name'])
    await t.test(variety,async () => {
      const {f,bind,observe} = edgeFixture({route:calibratedTemporary,accept:false});
      let original, label, bar, changed;
      f.setChange(file => {
        if (!original) { original = file.name; return; }
        const card = f.addCard(file.name,{progress:false});
        card.querySelector('img').setAttribute('src',f.context.URL.createObjectURL(file));
        bar = card.append(new f.Node('div',{role:'progressbar','aria-valuenow':'10','aria-labelledby':'label'}));
        label = card.append(new f.Node('span',{id:'label'}));
        if (variety === 'foreign then restored') {
          changed = f.appendText(label,file.name.slice(0,-4)); f.appendText(label,'.png');
        } else if (variety === 'overlong assembled name') {
          f.appendText(label,'a'.repeat(600)); f.appendText(label,'b'.repeat(600));
        } else changed = f.appendText(label,'上传进度 10%');
      });
      const a = bind(); f.stage(a,{edgeProgressCandidate:true}); await f.commit(a);
      const b = bind(); f.stage(b,{edgeProgressCandidate:true}); await f.commit(b);
      if (variety === 'foreign then restored') {
        const before = changed.data; changed.replace(original.slice(0,-4)); changed.replace(before);
      } else if (changed) changed.replace('上传进度 35%',variety !== 'missing prior value');
      bar.setAttribute('aria-valuenow','35');
      const reply = observe(b);
      assert.equal(reply.observation.state,variety === 'readable generic text' ? 'uploadStarted' : 'inputTriggered');
      assert.equal(reply.entryDiagnostics.edgeCalibration.progressDecision,variety === 'readable generic text' ? 'started' : 'conflictingFileLabel');
    });
});
