'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const vm = require('node:vm');
const {fixture, native, png} = require('./independent-input-fixture.cjs');
const {mountAttachmentEntryCase, readResidentV15Source} = require('./attachment-entry-application.cjs');

function mount(f, name) {
  // In particular, the application's async function and native await run in
  // the same realm as the page program, with its actual unscaled timers.
  const fn = vm.runInContext('(' + String(mountAttachmentEntryCase) + ')', f.context);
  return fn(name, f.form, f.input);
}

async function verifyHandoff(f, app, op) {
  const got = [];
  app.input.addEventListener('change', event => {
    got.push({target: event.target, file: event.target.files[0], connected: event.target.isConnected});
  });
  const oldCard = f.oldCard, text = f.editor.textContent;
  const click = f.context.HTMLElement.prototype.click;
  const showPicker = f.context.HTMLInputElement.prototype.showPicker;
  f.stage(op);
  const receipt = (await f.commit(op)).observation;
  assert.equal(receipt.state, 'uploadStarted', JSON.stringify({state: receipt.state,
    reason: receipt.preInputRetirement?.reason, setters: f.setters, changes: f.changes, ...app.counts}));
  assert.equal(receipt.identity.operationID, op.identity.operationID);
  assert.equal(receipt.uploadStart.inputCount, 1);
  assert.equal(got.length, 1, 'the handler on this exact application object received one change');
  assert.equal(got[0].target, app.input);
  assert.ok(got[0].file instanceof File);
  assert.equal(got[0].file.name, op.name);
  assert.deepEqual(Buffer.from(await got[0].file.arrayBuffer()), op.bytes);
  assert.equal(app.input.setterCount, 1);
  assert.equal(app.input.changeCount, 1);
  assert.equal(f.sends, 0);
  assert.ok(f.form.contains(oldCard));
  assert.equal(f.editor.textContent, text);
  assert.equal(f.selection.anchorNode, f.editor);
  assert.equal(f.selection.anchorOffset, 2);
  assert.equal(f.selection.focusOffset, 7);
  assert.equal(f.chooserOpens, 0, 'the system chooser default never ran');
  assert.equal(app.counts.cloudClicks, 0);
  assert.equal(app.counts.closeClicks, 0);
  assert.equal(app.counts.linkDefaultAllowed, 0);
  assert.equal(f.context.HTMLElement.prototype.click, click);
  assert.equal(f.context.HTMLInputElement.prototype.showPicker, showPicker);
  assert.equal(f.observe(op).uploadStart.evidenceID, receipt.uploadStart.evidenceID);
  assert.throws(() => f.commit(op), /COMMIT_REFUSED/);
  assert.equal(app.input.setterCount, 1);
  return got[0];
}

// Exactly the seven layouts from the prior installed-program study. Some have
// an unambiguous direct composer input in addition to an executable menu.
for (const name of ['direct', 'connected', 'detached', 'verb-menu', 'noun-menu',
  'no-role', 'await-existing']) {
  test('installed-program study layout receives the PNG through the application: ' + name, async () => {
    const f = fixture(), app = mount(f, name), op = f.bind();
    const result = await verifyHandoff(f, app, op);
    if (name === 'detached' || name === 'await-existing') {
      assert.equal(app.counts.entry, 1);
      assert.equal(app.counts.pickerCalls, 1);
      assert.equal(app.counts.pickerClicks, 1);
      assert.equal(app.counts.chooserDefaultAllowed, 0);
      assert.equal(result.connected, name !== 'detached', 'a detached input is used in place');
    }
  });
}

// Moving the existing input out of the composer makes the menu indispensable.
// Keeping the convenient direct picker in every case would mask menu failures.
for (const name of ['forced-noun', 'forced-no-role', 'nested', 'reused-open', 'reused-content',
  'short-label', 'plain-action', 'pointer-open', 'renamed-action', 'label-default', 'detached-showPicker',
  'focusable-menu', 'anchor-action', 'localized-opener']) {
  test('the application actually executes its attachment route: ' + name, async () => {
    const f = fixture(), app = mount(f, name);
    await verifyHandoff(f, app, f.bind());
    if (name === 'detached-showPicker') {
      assert.equal(app.input.isConnected, false);
      assert.equal(app.counts.pickerCalls, 1);
    } else {
      assert.equal(app.counts.menus, 1, 'the actual upload action ran once');
      if (!['renamed-action', 'label-default'].includes(name)) {
        assert.equal(app.counts.pickerCalls, 1);
        assert.equal(app.counts.pickerClicks, 1);
      }
    }
    if (name === 'reused-open') assert.equal(app.counts.entry, 0, 'the open menu was not toggled closed');
    if (name === 'nested') assert.equal(app.counts.submenus, 1, 'the parent opened its actual submenu');
  });
}

test('an independently usable direct composer input takes precedence over an inert attachment trigger', async () => {
  const f = fixture(), app = mount(f, 'ready-direct');
  await verifyHandoff(f, app, f.bind());
  assert.equal(app.counts.entry, 0, 'no menu activation needed');
});

test('an input-only recipient accepts and clears the native selection before change', async () => {
  const f = fixture({accept: false}), app = mount(f, 'detached'), op = f.bind();
  const order = [];
  let received;
  app.input.addEventListener('input', event => {
    order.push(event.type);
    assert.equal(event.composed, true);
    assert.equal(event.bubbles, true);
    received = event.target.files[0];
    f.addCard(received.name);
    event.target.value = '';
  });
  app.input.addEventListener('change', event => order.push(event.type));
  f.stage(op);
  assert.equal((await f.commit(op)).observation.state, 'uploadStarted');
  assert.deepEqual(order, ['input', 'change']);
  assert.deepEqual(Buffer.from(await received.arrayBuffer()), op.bytes);
  assert.equal(f.setters, 1);
  assert.equal(f.changes, 1);
  assert.equal(app.input.files.length, 0);
  assert.equal(app.input.isConnected, false);
});

test('page still running the installed v15 program adopts new file input on the same document', async () => {
  const source = readResidentV15Source();
  const f = fixture(), previous = vm.runInContext('(' + source + ')', f.context);
  const old = command => previous(command, native);
  const op = f.bind({target: old({action: 'captureTarget'})});
  old({...op.command('begin'), uploadName: op.name, mediaType: 'image/png', byteCount: png.length});
  old({...op.command('chunk'), chunkIndex: 0, chunkBase64: png.toString('base64')});
  const before = (await old({...op.command('commit'), chunkIndex: 1})).observation;
  assert.equal(before.state, 'uploadStarted');
  // A fresh picker with only an object-local change recipient after upgrade.
  const oldPicker = f.input;
  oldPicker.remove();
  const appInput = f.form.append(new f.context.HTMLInputElement());
  const install = vm.runInContext('(' + String(mountAttachmentEntryCase) + ')', f.context);
  const app = install('detached', f.form, appInput);
  const next = f.bind();
  await verifyHandoff(f, app, next);
  const after = old(op.command('observe')).observation;
  assert.equal(after.uploadStart.evidenceID, before.uploadStart.evidenceID);
  assert.equal(oldPicker.setterCount, 1);
  assert.equal(f.setters, 2);
  assert.equal(f.changes, 2);
});

for (const name of ['implicit-submit', 'detached-stop']) {
  test('normal application activation preserves its default-action boundary: ' + name, async () => {
    const f = fixture(), app = mount(f, name);
    await verifyHandoff(f, app, f.bind());
    assert.equal(app.counts.entry, 1);
    assert.equal(app.counts.pickerCalls, 1);
    assert.equal(app.counts.pickerClicks, 1);
    assert.equal(app.counts.chooserDefaultAllowed, 0);
  });
}

test('a detached picker invoked after native await receives its File even with an unused connected picker', async () => {
  const f = fixture(), app = mount(f, 'await-detached-with-rival');
  const delivered = await verifyHandoff(f, app, f.bind());
  assert.equal(delivered.connected, false);
  assert.equal(app.counts.pickerCalls, 1);
  assert.equal(app.rival.isConnected, true);
  assert.equal(app.rival.setterCount, 0);
  assert.equal(app.rival.changeCount, 0);
});

test('a replaced input calls its successor before File delivery; only the successor receives it', async () => {
  const f = fixture();
  const oldInput = f.body.append(f.input), replacement = new f.context.HTMLInputElement();
  const entry = f.form.append(new f.Node('button', {'aria-label': 'Attach files', type: 'button'}));
  entry.addEventListener('click', () => oldInput.click());
  oldInput.addEventListener('click', () => {
    oldInput.remove();
    f.body.append(replacement);
    replacement.click();
  });
  const op = f.bind();
  f.stage(op);
  const receipt = await f.commit(op);
  assert.equal(receipt.observation.state, 'uploadStarted');
  assert.equal(oldInput.setterCount, 0);
  assert.equal(replacement.setterCount, 1);
  assert.equal(replacement.changeCount, 1);
  assert.deepEqual(Buffer.from(await replacement.files[0].arrayBuffer()), op.bytes);
  assert.equal(f.chooserOpens, 0);
});

test('pre-input failures carry the exact entry stage and only a fixed exception type', async () => {
  async function attempt(kind) {
    const f = fixture(), op = f.bind();
    f.input.remove();
    if (kind !== 'entryUnavailable') {
      const entry = f.form.append(new f.Node('button', {'aria-label': 'Attach files', type: 'button'}));
      if (kind === 'exception') entry.click = () => { throw new TypeError('private sample'); };
      else if (kind === 'pickerRejected') {
        f.input.disabled = true;
        entry.addEventListener('click', () => f.input.click());
      } else {
        entry.addEventListener('click', () => {
          const menu = f.body.append(new f.Node('div', {role: 'menu'}));
          const item = menu.append(new f.Node('button', {type: 'button'}));
          item.textContent = kind === 'menuActionMissing' ? 'Google Drive' : 'Upload from computer';
        });
      }
    }
    f.stage(op);
    const {observation, entryDiagnostics: d} = await f.commit(op);
    assert.equal(observation.state, 'invalidated');
    assert.equal(observation.preInputRetirement.inputCount, 0);
    assert.equal(observation.uploadStart, undefined);
    assert.equal(f.setters, 0);
    assert.equal(f.changes, 0);
    assert.equal(d.cause, kind);
    assert.equal(d.exceptionType, kind === 'exception' ? 'TypeError' : 'none');
    assert.equal(d.inputSeen, kind === 'pickerRejected');
    assert.equal(d.setterEntered, false);
    assert.equal(d.changeReturned, false);
    assert.ok(!JSON.stringify(d).includes('private sample'));
    return d;
  }
  const [none, missing, uninvoked, rejected, thrown] = await Promise.all(
    ['entryUnavailable', 'menuActionMissing', 'pickerNotInvoked', 'pickerRejected', 'exception'].map(attempt));
  assert.equal(none.entryCandidates, 0);
  assert.equal(missing.openedContainers > 0, true);
  assert.equal(missing.menuActivations, 0);
  assert.equal(missing.stage, 'menu');
  assert.equal(uninvoked.menuActivations, 1);
  assert.equal(uninvoked.pickerClicks, 0);
  assert.equal(rejected.pickerClicks, 1);
  assert.equal(rejected.inputConnected, false);
  assert.equal(thrown.stage, 'entry');
});

const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const entryButton = (f, parent) => parent.append(new f.Node('button', {type: 'button', 'aria-label': 'Add files'}));

for (const kind of ['uninvoked-mount', 'unrelated-menu', 'unlinked-detached', 'competing-invocations']) {
  test('independent page activity cannot receive or redirect a pending attachment: ' + kind, async () => {
    const f = fixture({accept: false}), input = f.body.append(f.input);
    input.applicationAccept = true;
    const external = f.body.append(new f.Node('section')), foreign = new f.context.HTMLInputElement();
    foreign.applicationAccept = false;
    let unrelatedActions = 0, unrelatedDismissals = 0;
    if (kind === 'competing-invocations') external.append(foreign);
    // These callbacks belong to independent page work, scheduled before our
    // command. The real picker is invoked later by a native await handler.
    const pendingChange = pause(5).then(() => {
      if (kind === 'uninvoked-mount') external.append(foreign);
      else if (kind === 'unrelated-menu') {
        const menu = f.body.append(new f.Node('div', {role: 'menu'}));
        const signOut = menu.append(new f.Node('button', {type: 'button'}));
        signOut.textContent = 'Sign out';
        signOut.addEventListener('click', () => unrelatedActions++);
        menu.addEventListener('keydown', event => { if (event.key === 'Escape') unrelatedDismissals++; });
      } else foreign.click();
    });
    let invocation;
    const realInvocation = async () => { await pendingChange; await pause(45); input.click(); };
    entryButton(f, f.form).addEventListener('click', () => { invocation = realInvocation(); });
    const op = f.bind(); f.stage(op);
    const {observation} = await f.commit(op);
    await invocation;
    assert.equal(foreign.setterCount, 0, 'a concurrent page action cannot receive the screenshot');
    assert.equal(unrelatedActions, 0);
    assert.equal(unrelatedDismissals, 0);
    if (kind === 'competing-invocations' || kind === 'unlinked-detached') {
      // Both anonymous controls were actually invoked. Neither DOM placement
      // nor invocation order can authorize choosing between them.
      assert.equal(observation.state, 'invalidated');
      assert.equal(observation.preInputRetirement.reason, 'attachmentInputAmbiguous');
      assert.equal(observation.preInputRetirement.inputCount, 0);
      assert.equal(observation.uploadStart, undefined);
      assert.equal(f.setters, 0);
    } else {
      assert.equal(observation.state, 'uploadStarted');
      assert.equal(input.setterCount, 1);
      assert.deepEqual(Buffer.from(await input.files[0].arrayBuffer()), op.bytes);
    }
    assert.equal(input.chooserOpens, 0);
  });
}

test('an executing attachment does not replace the application scheduling primitives', async () => {
  const f = fixture(), input = f.body.append(f.input);
  const scheduling = () => [f.context.Promise.prototype.then, f.context.setTimeout,
    f.context.queueMicrotask, f.context.requestAnimationFrame];
  const before = scheduling();
  let during;
  entryButton(f, f.form).addEventListener('click', () => { during = scheduling(); input.click(); });
  const op = f.bind(); f.stage(op);
  assert.equal((await f.commit(op)).observation.state, 'uploadStarted');
  assert.deepEqual(during, before);
  assert.deepEqual(scheduling(), before);
});

test('the current entry may directly invoke an input with a project-like DOM ID', async () => {
  const f = fixture(), input = f.body.append(f.input);
  input.setAttribute('id', 'project-files');
  entryButton(f, f.form).addEventListener('click', () => input.click());
  const op = f.bind(); f.stage(op);
  assert.equal((await f.commit(op)).observation.state, 'uploadStarted');
  assert.equal(f.setters, 1);
  assert.deepEqual(Buffer.from(await input.files[0].arrayBuffer()), op.bytes);
  assert.equal(f.chooserOpens, 0);
});

test('modeled user interruption leaves the independent picker and cancels this entry', async () => {
  // In-memory fixture input to the cancellation branch. This is not a
  // native pointer assertion; no browser event is modified or used for upload.
  const f = fixture({accept: false}), input = f.body.append(f.input);
  let resume;
  const deferred = new Promise(resolve => { resume = resolve; });
  let actual;
  entryButton(f, f.form).addEventListener('click', () => { actual = deferred.then(() => input.click()); });
  const userButton = f.body.append(new f.Node('button', {type: 'button'}));
  const avatar = new f.context.HTMLInputElement();
  userButton.addEventListener('pointerdown', () => avatar.click());
  const op = f.bind(); f.stage(op);
  const commit = f.commit(op);
  await f.waitFor(() => actual && true, 'attachment trigger');
  userButton.dispatchEvent(new f.context.PointerEvent('pointerdown', {bubbles: true, cancelable: true, isTrusted: true}));
  // The user's own action runs before the original attachment callback resumes.
  await Promise.resolve(); resume(); await actual;
  const {entryDiagnostics, observation} = await commit;
  assert.equal(observation.state, 'invalidated');
  assert.equal(entryDiagnostics.cause, 'userInterrupted');
  assert.equal(avatar.setterCount, 0);
  assert.equal(avatar.chooserOpens, 1);
  assert.equal(input.setterCount, 0);
  assert.equal(input.chooserOpens, 0);
  assert.equal(observation.uploadStart, undefined);
});

test('an independent composer reached during discovery gets its own input budget', async () => {
  const f = fixture({accept: false});
  f.input.remove();
  let activate;
  const activated = new Promise(resolve => { activate = resolve; });
  entryButton(f, f.form).addEventListener('click', activate);
  const a = f.bind(); f.stage(a);
  const first = f.commit(a);
  await activated;
  f.setRoute('https://chatgpt.com/c/next-controlled-draft');
  f.form.remove();
  const form = f.body.append(new f.Node('form'));
  f.document.activeElement = form.append(new f.Node('div', {id:'prompt-textarea', role:'textbox', contenteditable:'true'}));
  const input = f.body.append(new f.context.HTMLInputElement());
  input.addEventListener('change', () => {
    const name = input.files[0].name;
    const card = form.append(new f.Node('div', {role:'button', 'data-file-name':name}));
    card.append(new f.Node('img', {alt:name, src:'blob:local-draft-b'}));
  });
  entryButton(f, form).addEventListener('click', () => setTimeout(() => input.click(), 25));
  const b = f.bind(); f.stage(b);
  const [retired, accepted] = await Promise.all([first, f.commit(b)]);
  assert.equal(retired.observation.preInputRetirement.reason, 'targetInvalidBeforeInput');
  assert.equal(retired.observation.preInputRetirement.inputCount, 0);
  assert.equal(accepted.observation.state, 'uploadStarted');
  assert.equal(accepted.observation.identity.operationID, b.identity.operationID);
  assert.equal(input.setterCount, 1);
  assert.equal(input.files[0].name, b.name);
  assert.equal(f.chooserOpens, 0);
});
