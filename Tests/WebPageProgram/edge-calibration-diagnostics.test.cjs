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
