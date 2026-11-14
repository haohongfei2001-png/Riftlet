'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {fixture} = require('./independent-input-fixture.cjs');

function witnessed(options = {}) {
  const f = fixture(options);
  const navigation = new EventTarget();
  navigation.currentEntry = {id: randomUUID()};
  f.context.navigation = navigation;
  const activity = new EventTarget();
  f.context.addEventListener = activity.addEventListener.bind(activity);
  f.context.removeEventListener = activity.removeEventListener.bind(activity);
  // Expiring an in-memory capability never holds the test process alive.
  const expiries = [];
  f.context.setTimeout = (callback, delay) => {
    if (delay === 60000) { expiries.push(callback); return 0; }
    return setTimeout(callback, delay).unref();
  };
  const pin = () => {
    const clickWitnessID = randomUUID();
    const location = new URL(f.context.location.href);
    assert.equal(f.call({action:'pinTarget', clickWitnessID, address:location.origin + location.pathname}), 'bound');
    return clickWitnessID;
  };
  const capture = clickWitnessID => f.call({action:'captureTarget', clickWitnessID});
  return {f, navigation, activity, pin, capture, expire: () => expiries.splice(0).forEach(fn => fn())};
}

test('two click-time editor witnesses survive independent capture, staging and input', async () => {
  const {f, pin, capture} = witnessed({route:'https://chatgpt.com/g/project/c/prior-chat'});
  f.document.activeElement=f.body;
  const a=pin(), b=pin();
  const first=f.bind({target:capture(a)}), second=f.bind({target:capture(b)});
  assert.equal(first.target.clickBindingID, a); assert.equal(second.target.clickBindingID, b);
  assert.equal(first.target.draftGeneration, second.target.draftGeneration);
  f.stage(first); f.stage(second);
  assert.equal((await f.commit(first)).observation.state, 'uploadStarted');
  assert.equal((await f.commit(second)).observation.state, 'uploadStarted');
  assert.equal(f.setters,2); assert.equal(f.changes,2); assert.equal(f.sends,0);
});

test('same-route reload and editor replacement before capture cannot receive the click', () => {
  const {f,pin,capture} = witnessed(), id=pin();
  assert.throws(()=>witnessed().capture(id), /CLICK_PIN_REFUSED/);
  f.editor.remove();
  f.form.append(new f.Node('div', {id:'prompt-textarea',contenteditable:'true'}));
  assert.throws(()=>capture(id), /CLICK_PIN_REFUSED/);
  assert.equal(f.setters,0);
});

test('a new closest composer around the same connected editor cannot capture the original click', () => {
  const {f,pin,capture}=witnessed(), id=pin();
  // Change the closest composer without moving the original editor DOM node.
  f.editor.setAttribute('data-chatgpt-composer', 'replacement');
  assert.throws(()=>capture(id), /CLICK_PIN_REFUSED/);
  assert.equal(f.setters,0);
});

test('a new composer using the original editor after begin retires before input', async () => {
  const {f,pin,capture}=witnessed(), op=f.bind({target:capture(pin())});
  f.stage(op); f.editor.setAttribute('data-chatgpt-composer','replacement');
  const result=(await f.commit(op)).observation;
  assert.equal(result.preInputRetirement?.reason, 'targetInvalidBeforeInput');
  assert.equal(f.setters,0);
});

test('a same-route SPA round trip or detached and reinserted original invalidates the witness', () => {
  for (const routeChanged of [true,false]) {
    const {f,pin,capture,navigation}=witnessed(), id=pin();
    if (routeChanged) navigation.dispatchEvent(new Event('currententrychange'));
    else {f.editor.remove(); f.form.append(f.editor);}
    assert.throws(()=>capture(id), /CLICK_PIN_REFUSED/);
    assert.equal(f.setters,0);
  }
});

test('an opaque draft replacement while the attachment entry awaits a picker retires before setter', async () => {
  const {f,pin,capture} = witnessed(), op=f.bind({target:capture(pin())});
  f.stage(op); f.input.remove();
  const button=f.form.append(new f.Node('button',{type:'button','data-testid':'composer-plus-button','aria-label':'Add files'}));
  button.addEventListener('click', async () => {
    await Promise.resolve(); f.editor.remove();
    f.form.append(new f.Node('div',{id:'prompt-textarea',contenteditable:'true'}));
    f.form.append(f.input); f.input.click();
  });
  const result = (await f.commit(op)).observation;
  assert.equal(result.preInputRetirement?.inputCount,0);
  assert.equal(result.preInputRetirement?.reason,'targetInvalidBeforeInput');
  assert.equal(f.setters,0); assert.equal(f.changes,0); assert.equal(f.chooserOpens,0);
});


test('a late original START survives expired input permission, without authorizing a new begin', async () => {
  const {f,pin,capture,expire}=witnessed({accept:false}), id=pin(), op=f.bind({target:capture(id)});
  f.stage(op);
  assert.throws(()=>f.stage(f.bind({target:op.target})), /TARGET_INVALID/);
  assert.equal((await f.commit(op)).observation.state,'inputTriggered');
  expire();
  assert.throws(()=>capture(id), /CLICK_PIN_REFUSED/);
  f.addCard(op.name);
  assert.equal(f.observe(op).state,'uploadStarted');
  assert.equal(f.setters,1); assert.equal(f.changes,1);
});

test('late matching cards cannot prove an original START after editor reattachment or route ABA', async () => {
  for (const routeChanged of [true,false]) {
    const {f,pin,capture,expire,navigation}=witnessed({accept:false}), op=f.bind({target:capture(pin())});
    f.stage(op); await f.commit(op); expire();
    if (routeChanged) navigation.dispatchEvent(new Event('currententrychange'));
    else { f.editor.remove(); f.form.append(f.editor); }
    f.addCard(op.name);
    const result=f.observe(op);
    assert.equal(result.state,'inputTriggered'); assert.equal(result.belongsToOriginalDraft,false);
    assert.equal(f.setters,1); assert.equal(f.changes,1);
  }
});


test('a switch to another application or hidden tab prevents direct handoff without focusing the draft editor', async () => {
  for (const away of ['application','tab']) {
    const {f,pin,capture}=witnessed(); f.document.activeElement=f.body;
    const op=f.bind({target:capture(pin())}); f.stage(op);
    if (away==='application') f.setFocused(false); else f.document.visibilityState='hidden';
    const result=(await f.commit(op)).observation;
    assert.equal(result.preInputRetirement?.reason,'targetInvalidBeforeInput');
    assert.equal(f.setters,0); assert.equal(f.changes,0); assert.equal(f.sends,0);
  }
});

test('a window switch during asynchronous picker discovery retires before the first setter', async () => {
  const {f,pin,capture}=witnessed(), op=f.bind({target:capture(pin())});
  f.stage(op); f.input.remove();
  const button=f.form.append(new f.Node('button',{type:'button','data-testid':'composer-plus-button','aria-label':'Add files'}));
  button.addEventListener('click', async () => {
    await Promise.resolve(); f.setFocused(false); f.form.append(f.input); f.input.click();
  });
  const result=(await f.commit(op)).observation;
  assert.equal(result.preInputRetirement?.reason,'targetInvalidBeforeInput');
  assert.equal(f.setters,0); assert.equal(f.changes,0); assert.equal(f.chooserOpens,0);
});

test('pending operations on one draft share one observer and the last START disconnects it', async () => {
  const {f,pin,capture,expire}=witnessed({accept:false});
  const a=f.bind({target:capture(pin())}), b=f.bind({target:capture(pin())});
  f.stage(a); f.stage(b); await f.commit(a); await f.commit(b); expire();
  const registry=f.context.__riftletIndependentFileInput20261104;
  assert.equal(registry.observationMonitor.drafts.size,1);
  const subtree=f.body.append(new f.Node('article'));
  subtree.remove();
  f.addCard(a.name);
  assert.equal(f.observe(a).state,'uploadStarted');
  assert.equal(registry.observationMonitor.drafts.size,1);
  f.addCard(b.name);
  assert.equal(f.observe(b).state,'uploadStarted');
  assert.equal(registry.observationMonitor,null);
  assert.equal(f.setters,2);
});

test('switching away and back before a pending setter permanently revokes that click', async () => {
  const {f,pin,capture,activity}=witnessed(), op=f.bind({target:capture(pin())}); f.stage(op);
  activity.dispatchEvent(new Event('blur')); f.setFocused(true);
  const result = (await f.commit(op)).observation;
  assert.equal(result.preInputRetirement?.reason,'targetInvalidBeforeInput'); assert.equal(f.setters,0);
});

test('retained hidden, inert and overtaken original composers retire before their native input', async () => {
  for (const replacement of ['hidden','inert','strictlyPreferred','ambiguous']) {
    const {f,pin,capture}=witnessed(), op=f.bind({target:capture(pin())}); f.stage(op);
    const next=f.body.append(new f.Node('form'));
    next.append(new f.Node('div',{id:'prompt-textarea',contenteditable:'true'}));
    next.append(new f.context.HTMLInputElement());
    f.document.activeElement=f.body;
    if (replacement==='hidden') { f.form.hidden=true; f.form.setAttribute('hidden',''); }
    if (replacement==='inert') f.form.setAttribute('inert','');
    if (replacement==='strictlyPreferred') next.setAttribute('data-composer-placement','bottom');
    const result=(await f.commit(op)).observation;
    assert.equal(result.preInputRetirement?.reason,'targetInvalidBeforeInput',replacement);
    assert.equal(f.setters,0); assert.equal(f.changes,0); assert.equal(f.sends,0);
  }
});
