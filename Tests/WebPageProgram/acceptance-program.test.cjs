'use strict';
// Runs the bundled production-candidate program against controlled DOM events.
// This is deterministic integration regression, never live ChatGPT/GUI evidence.
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const {webcrypto, createHash} = require('node:crypto');
const source = fs.readFileSync(path.join(__dirname, '../../Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js'), 'utf8');
const png = Buffer.from([137,80,78,71,13,10,26,10,1,2,3,4,5,6,7,8]);
const digest = b => createHash('sha256').update(b).digest('hex');
const native = {applicationID:'com.google.Chrome', sessionID:'4242:1', windowID:'17', tabID:'19'};

function fixture({blockedDigest = false, route = 'https://chatgpt.com/', mode = 'chat'} = {}) {
  const events = new Map(), globalEvents = new Map();
  let focused = true, releaseDigest;
  const mutationObservers=[];
  const digestGate = blockedDigest ? new Promise(resolve => { releaseDigest = resolve; }) : Promise.resolve();
  class Node {
    constructor(tag, attrs = {}) { this.tagName = tag.toUpperCase(); this.attrs = {...attrs}; this.isConnected = true; this.children = []; this.parent = null; this.textContent = ''; }
    getAttribute(k) { return this.attrs[k] ?? null; }
    get parentNode() { return this.parent; }
    contains(n) { return n === this || this.children.some(c => c.contains(n)); }
    closest(selector) { if ((selector === 'form' && this.tagName === 'FORM') || (selector === 'header' && this.tagName === 'HEADER') || (selector === '[role=button]' && this.attrs.role === 'button')) return this; return this.parent?.closest(selector) || null; }
    append(n) { n.parent = this; this.children.push(n); return n; }
    querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
    querySelectorAll(selector) {
      const all = this.children.flatMap(c => [c, ...c.querySelectorAll('*')]);
      if (selector === '*') return all;
      if (selector === '[role=group][aria-label="撰写器模式"]') return all.filter(n => n.attrs.role === 'group' && n.attrs['aria-label'] === '撰写器模式');
      if (selector === 'button[type=button]') return all.filter(n => n.tagName === 'BUTTON' && n.attrs.type === 'button');
      if (selector === 'img') return all.filter(n => n.tagName === 'IMG');
      if (selector === '[role=progressbar]') return all.filter(n => n.attrs.role === 'progressbar');
      if (selector === '[role=button][aria-label]') return all.filter(n => n.attrs.role === 'button' && n.attrs['aria-label'] != null);
      if (selector === 'input[type=file][aria-label="附加文件"]') return all.filter(n => n.tagName === 'INPUT' && n.attrs.type === 'file' && n.attrs['aria-label'] === '附加文件');
      if (selector === '[aria-describedby],[aria-labelledby]') return all.filter(n => n.attrs['aria-describedby'] || n.attrs['aria-labelledby']);
      if (selector === '[role=alert],[data-state],[aria-label]') return all.filter(n => n.attrs.role === 'alert' || n.attrs['data-state'] || n.attrs['aria-label']);
      return [];
    }
  }
  class Input extends Node {
    constructor() { super('input', {type:'file','aria-label':'附加文件'}); this._files = []; this.inputCount = 0; }
    get files() { return this._files; }
    set files(value) { this._files = value; }
    dispatchEvent(event) { this.inputCount++; for (const fn of events.get(event.type) || []) fn({target:this,type:event.type}); return true; }
    get form() { return this.formOverride || this.closest('form'); }
  }
  const body = new Node('body'), form = body.append(new Node('form')), editor = form.append(new Node('div'));
  const modeHeader = body.append(new Node('header'));
  const modeGroup = modeHeader.append(new Node('div', {role:'group', 'aria-label':'撰写器模式'}));
  const chatMode = modeGroup.append(new Node('button', {type:'button','aria-pressed':mode === 'work' ? 'false' : 'true'}));
  const workMode = modeGroup.append(new Node('button', {type:'button','aria-pressed':mode === 'work' ? 'true' : 'false'}));
  chatMode.textContent='聊天';workMode.textContent='工作';
  if (mode === 'missing') modeHeader.children=[];
  if (mode === 'ambiguous') modeHeader.append(new Node('div', {role:'group','aria-label':'撰写器模式'}));
  editor.textContent = 'Existing 中文 draft 👋';
  let currentEditor = editor;
  const input = form.append(new Input());
  const document = {
    visibilityState:'visible', hasFocus:() => focused,
    querySelectorAll: selector => selector === '[contenteditable=true][role=textbox]' ? [currentEditor] : body.querySelectorAll(selector),
    addEventListener:(type,fn) => { if (!events.has(type)) events.set(type, []); events.get(type).push(fn); },
    getElementById:() => null
  };
  document.contains = node => node === document || body.contains(node);
  body.parent = document;
  const mutation = (records, deferDelivery = false) => {
    if (!records.length) records=[{type:'childList',target:form,removedNodes:[],addedNodes:[]}];
    for (const observer of mutationObservers) {
      const delivered=records.filter(record=>observer.observations.some(({target,options})=>
        (target===record.target || (options.subtree && target.contains?.(record.target)))
        && (record.type==='childList' ? options.childList : record.type==='characterData' ? options.characterData : options.attributes)));
      if (deferDelivery) observer.pending.push(...delivered);
      else if(delivered.length) observer.fn([...observer.pending.splice(0), ...delivered]);
    }
  };
  const sharedPixels = new Uint8Array([12,20,30,255,40,50,60,255]);
  class TestImage extends Node {
    constructor() { super('img'); this.naturalWidth = 2; this.naturalHeight = 1; this.rgba = sharedPixels; this.complete = true; }
    set src(value) { this._src = value; if (value.startsWith('blob:')) queueMicrotask(() => this.onload?.()); }
    get src() { return this._src || ''; }
    get currentSrc() { return this.src; }
    get alt() { return this.attrs.alt || ''; }
  }
  const context = vm.createContext({console, Uint8Array, Map, Set, WeakMap, Promise, File, atob,
    crypto:{randomUUID:() => webcrypto.randomUUID(),subtle:{digest:async(...args) => { await digestGate; return webcrypto.subtle.digest(...args); }}},
    location:{href:route}, document, HTMLInputElement:Input, Image:TestImage,
    URL:{createObjectURL:()=>'blob:fixture',revokeObjectURL:()=>{}},
    OffscreenCanvas:class { constructor(w,h) { this.width=w;this.height=h; } getContext() { let selected; return {drawImage:i=>{selected=i;},getImageData:()=>({data:selected.rgba})}; } },
    MutationObserver:class {
      constructor(fn) { this.entry={fn,observations:[],pending:[]};mutationObservers.push(this.entry); }
      observe(target,options) {
        const prior=this.entry.observations.find(item=>item.target===target);
        if(prior) prior.options=options; else this.entry.observations.push({target,options});
      }
      takeRecords() { return this.entry.pending.splice(0); }
    },
    DataTransfer:class { constructor() { this.files=[];this.items={add:f=>this.files.push(f)}; } },
    Event:class { constructor(type) { this.type=type; } },
    addEventListener:(type,fn) => { if (!globalEvents.has(type)) globalEvents.set(type, []);globalEvents.get(type).push(fn); }
  });
  vm.runInContext('globalThis.top=globalThis', context);
  const pageWindow = vm.runInContext('globalThis', context);
  const program = vm.runInContext('(' + source + ')', context);
  const call = command => program(command, native);
  const target = () => call({action:'captureTarget'});
  const bind = (id = '11111111-1111-4111-8111-111111111111', bytes = png) => {
    const t = target(), identity = {operationID:id,assetID:'22222222-2222-4222-8222-222222222222',attempt:1,assetSHA256:digest(bytes),target:t};
    const name = 'riftlet-' + id + '.png';
    return {identity,target:t,name,bytes,command:action=>({action,identity,target:t})};
  };
  const stage = op => {
    call({...op.command('begin'),uploadName:op.name,mediaType:'image/png',byteCount:op.bytes.length});
    call({...op.command('chunk'),chunkIndex:0,chunkBase64:op.bytes.toString('base64')});
  };
  const commit = op => call({...op.command('commit'),chunkIndex:1});
  const observe = op => call(op.command('observe')).observation;
  const settle = async () => {
    const deadline=Date.now()+2000;
    do {
      await new Promise(resolve=>setTimeout(resolve,1));
      const ops=[];for(let g=context.__riftletWebAcceptance20261027v3?.head;g;g=g.next) ops.push(...g.operations.values());
      if (ops.every(op=>!op.committed || op.invalid || (op.fileHashVerified && !op.proofPending))) return;
    } while(Date.now()<deadline);
    assert.fail('bounded synthetic async work did not settle');
  };
  const makeCard = op => {
    const card = form.append(new Node('div',{role:'button','aria-label':op.name}));
    const image = card.append(new TestImage()); image.attrs.alt=op.name;image.src='blob:upload';
    const progress = card.append(new Node('div',{role:'progressbar','aria-label':'正在上传 '+op.name,'aria-valuenow':'20'}));
    mutation([]);
    return {card,image,progress};
  };
  const finish = (view, bytes = png) => {
    view.progress.attrs['aria-valuenow']='100'; mutation([]);
    view.card.children=view.card.children.filter(n=>n!==view.progress);view.progress.isConnected=false;
    mutation([{type:'childList',target:view.card,removedNodes:[view.progress],addedNodes:[]}]);
    view.image.src='data:image/png;base64,'+bytes.toString('base64');
    mutation([{type:'attributes',target:view.image,attributeName:'src'}]);
    for (const fn of events.get('load')||[]) fn({target:view.image,type:'load'});
  };
  return {Node,Input,document,body,form,editor,input,modeHeader,modeGroup,chatMode,workMode,call,target,bind,stage,commit,observe,settle,makeCard,finish,
    mutate:records=>mutation(records),queueMutation:records=>mutation(records,true),
    windowEvent:(type,target=pageWindow)=>{for(const fn of globalEvents.get(type)||[]) fn({type,target});},release:()=>releaseDigest?.(),focus:v=>{focused=v;},
    replaceEditor:n=>{currentEditor=n;},events,context};
}

test('bundled program executes one exact-byte attachment and leaves draft/old attachment intact', async () => {
  const f=fixture(), prior=f.form.append(new f.Node('div',{role:'button','aria-label':'existing.png'})); prior.append(new f.Node('img'));
  const op=f.bind();f.stage(op);f.commit(op);await f.settle();assert.equal(f.input.inputCount,1);
  const view=f.makeCard(op);f.finish(view);await f.settle();
  assert.equal(f.observe(op).state,'attached');assert.equal(f.observe(op).exactImageIdentity,true);
  assert.equal(f.editor.textContent,'Existing 中文 draft 👋');assert.ok(f.form.contains(prior));
  assert.throws(()=>f.commit(op),/COMMIT_REFUSED/);assert.equal(f.input.inputCount,1);
});

test('observed PNG re-encoding can match exact sRGB RGBA; a mismatched preview cannot', async () => {
  const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const v=f.makeCard(op);
  f.finish(v,Buffer.from([...png,99]));await f.settle();assert.equal(f.observe(op).state,'attached');
  const g=fixture(),bad=g.bind();g.stage(bad);g.commit(bad);await g.settle();const wrong=g.makeCard(bad);
  wrong.image.rgba=new Uint8Array([0,0,0,255,0,0,0,255]);g.finish(wrong,Buffer.from([...png,99]));await g.settle();
  assert.equal(g.observe(bad).state,'invalidated');
});

test('missing progress, hundred-percent only and another card completion cannot prove ATTACHED', async () => {
  const f=fixture(),a=f.bind();f.stage(a);f.commit(a);await f.settle();const av=f.makeCard(a);
  av.progress.attrs['aria-valuenow']='100';f.mutate([]);assert.notEqual(f.observe(a).state,'attached');
  const b=f.bind('33333333-3333-4333-8333-333333333333');f.stage(b);f.commit(b);await f.settle();const bv=f.makeCard(b);
  f.finish(bv);await f.settle();assert.equal(f.observe(b).state,'attached');assert.notEqual(f.observe(a).state,'attached');
  assert.equal(f.input.inputCount,2);
});

test('changed draft before asynchronous byte verification prevents any input and observe never retries', async () => {
  const f=fixture({blockedDigest:true}),op=f.bind();f.stage(op);f.commit(op);
  f.context.location.href='https://chatgpt.com/?temporary-chat=true';f.release();await f.settle();
  assert.equal(f.input.inputCount,0);assert.equal(f.observe(op).state,'invalidated');
  f.observe(op);assert.equal(f.input.inputCount,0);
});

test('hidden tab before hash completion and lost foreground focus cannot receive input', async () => {
  for (const change of [f=>{f.document.visibilityState='hidden';},f=>f.focus(false)]) {
    const f=fixture({blockedDigest:true}),op=f.bind();f.stage(op);f.commit(op);change(f);f.release();await f.settle();
    assert.equal(f.input.inputCount,0);assert.equal(f.observe(op).state,'invalidated');
  }
});

test('sole matching replacement editor/input and changed native form association are rejected', async () => {
  for (const change of [f=>f.replaceEditor(f.form.append(new f.Node('div'))),f=>{f.input.attrs['aria-label']='old';f.form.append(new f.Input());},f=>{f.input.formOverride=new f.Node('form');}]) {
    const f=fixture({blockedDigest:true}),op=f.bind();f.stage(op);f.commit(op);change(f);f.release();await f.settle();
    assert.equal(f.input.inputCount,0);assert.equal(f.observe(op).state,'invalidated');
  }
});

test('transient card/form detach and final src restore cannot reuse an earlier proof', async () => {
  for (const mutate of [(f,v)=>f.mutate([{type:'childList',target:f.form,removedNodes:[v.card],addedNodes:[v.card]}]),
    f=>f.mutate([{type:'childList',target:f.body,removedNodes:[f.form],addedNodes:[f.form]}]),
    f=>f.mutate([{type:'childList',target:f.document,removedNodes:[f.body],addedNodes:[f.body]}]),
    (f,v)=>f.mutate([{type:'attributes',target:v.image,attributeName:'src',oldValue:v.image.src}])]) {
    const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);f.finish(view);await f.settle();
    assert.equal(f.observe(op).state,'attached');mutate(f,view);assert.equal(f.observe(op).state,'invalidated');
  }
});

test('own error and repeated file input veto completion without safe-retry admission', async () => {
  for (const mutate of [(f,v)=>{v.card.attrs['data-state']='error';f.mutate([]);},(f)=>f.input.dispatchEvent({type:'change'})]) {
    const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);f.finish(view);await f.settle();
    mutate(f,view);const result=f.observe(op);assert.equal(result.state,'invalidated');assert.equal(result.automaticRetryExcluded,false);
  }
});

test('wrong operation identity, file bytes, route or an absent original observer never inputs', async () => {
  const f=fixture(),op=f.bind();f.stage(op);
  assert.throws(()=>f.call({...op.command('commit'),identity:{...op.identity,attempt:2},chunkIndex:1}),/ORIGINAL_OPERATION_REQUIRED/);
  assert.equal(f.input.inputCount,0);
  const other=fixture();const missing=other.call(op.command('observe'));assert.equal(missing.observation.state,'invalidated');assert.equal(other.input.inputCount,0);
  assert.throws(()=>fixture({route:'https://chatgpt.com/c/example'}).target(),/UNSUPPORTED_TEST_SURFACE/);
  const corrupt=fixture(),bad=corrupt.bind();bad.identity.assetSHA256='0'.repeat(64);corrupt.stage(bad);corrupt.commit(bad);await corrupt.settle();
  assert.equal(corrupt.input.inputCount,0);assert.equal(corrupt.observe(bad).state,'invalidated');
});

test('proved attachment keeps its independent identity on a correlated late error, without retry', async () => {
  const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();
  const view=f.makeCard(op);f.finish(view);await f.settle();
  const success=f.observe(op);assert.equal(success.state,'attached');assert.ok(success.attachmentID);
  view.card.attrs['data-state']='error';
  f.mutate([{type:'attributes',target:view.card,attributeName:'data-state'}]);
  const failed=f.observe(op);
  assert.equal(failed.state,'invalidated');assert.equal(failed.hasError,true);
  assert.equal(failed.belongsToOriginalDraft,true);assert.equal(failed.exactImageIdentity,true);
  assert.equal(failed.attachmentID,success.attachmentID);assert.equal(failed.automaticRetryExcluded,false);
  assert.equal(f.observe(op).attachmentID,success.attachmentID);assert.equal(f.input.inputCount,1);
});

test('navigation, unproved errors and unrelated cards cannot create late-failure identity', async () => {
  const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);
  view.card.attrs['data-state']='error';f.mutate([{type:'attributes',target:view.card,attributeName:'data-state'}]);
  assert.equal(f.observe(op).attachmentID,undefined);
  const g=fixture(),good=g.bind();g.stage(good);g.commit(good);await g.settle();const ready=g.makeCard(good);
  g.finish(ready);await g.settle();assert.equal(g.observe(good).state,'attached');
  const other=g.form.append(new g.Node('div',{role:'button','aria-label':'other.png','data-state':'error'}));
  other.append(new g.Node('img'));g.mutate([]);assert.equal(g.observe(good).state,'attached');
  g.context.location.href='https://chatgpt.com/c/different';
  const lost=g.observe(good);assert.equal(lost.state,'invalidated');assert.equal(lost.attachmentID,undefined);
  assert.equal(lost.hasError,false);assert.equal(g.input.inputCount,1);
});

test('only the observed unambiguous Chinese Home Chat mode is admitted', () => {
  assert.equal(fixture().target().surface,'webChat');
  for(const mode of ['work','missing','ambiguous']) {
    const f=fixture({mode});assert.throws(()=>f.target(),/UNPROVEN_CHAT_MODE/);assert.equal(f.input.inputCount,0);
  }
  const f=fixture();f.workMode.attrs['aria-pressed']='true';assert.throws(()=>f.target(),/UNPROVEN_CHAT_MODE/);
});

test('mode switching and replacement permanently revoke the original draft lease', async () => {
  const mutations = [
    f=>{ f.chatMode.attrs['aria-pressed']='false';f.workMode.attrs['aria-pressed']='true';
      f.mutate([{type:'attributes',target:f.chatMode,attributeName:'aria-pressed',oldValue:'true'}]); },
    f=>{ // Final snapshot says Chat again, but the recorded intermediate state says Work.
      f.mutate([{type:'attributes',target:f.chatMode,attributeName:'aria-pressed',oldValue:'true'},
        {type:'attributes',target:f.chatMode,attributeName:'aria-pressed',oldValue:'false'}]); },
    f=>f.mutate([{type:'childList',target:f.modeHeader,removedNodes:[f.modeGroup],addedNodes:[f.modeGroup]}]),
    f=>f.mutate([{type:'childList',target:f.body,removedNodes:[f.modeHeader],addedNodes:[f.modeHeader]}]),
    f=>f.mutate([{type:'childList',target:f.modeGroup,removedNodes:[f.chatMode],addedNodes:[f.chatMode]}])
  ];
  for(const change of mutations) {
    const f=fixture({blockedDigest:true}),op=f.bind();f.stage(op);f.commit(op);change(f);
    f.chatMode.attrs['aria-pressed']='true';f.workMode.attrs['aria-pressed']='false';
    f.release();await f.settle();assert.equal(f.input.inputCount,0);
    assert.equal(f.observe(op).state,'invalidated');
    const fresh=f.target();assert.notEqual(fresh.documentID,op.target.documentID);
    assert.equal(f.call({action:'validate',target:op.target}).valid,false);
  }
});

test('returning to a tab can bind a fresh lease while original UNKNOWN stays observation-only', async () => {
  const f=fixture(),old=f.bind();f.stage(old);f.commit(old);await f.settle();
  assert.equal(f.input.inputCount,1);
  f.document.visibilityState='hidden';
  for(const fn of f.events.get('visibilitychange')||[]) fn();
  f.document.visibilityState='visible';
  for(const fn of f.events.get('visibilitychange')||[]) fn();
  const registry=f.context.__riftletWebAcceptance20261027v3;
  assert.equal(registry.count,1);
  assert.equal(f.observe(old).state,'invalidated');assert.equal(registry.count,1);
  const fresh=f.bind('33333333-3333-4333-8333-333333333333');
  assert.notEqual(fresh.target.documentID,old.target.documentID);
  assert.notEqual(fresh.target.draftGeneration,old.target.draftGeneration);
  assert.equal(registry.count,2);assert.equal(registry.head.next,registry.tail);
  assert.equal(registry.head.operations.size,1);
  assert.equal(f.call({action:'validate',target:old.target}).valid,false);
  assert.throws(()=>f.stage(old),/TARGET_INVALID/);assert.throws(()=>f.commit(old),/TARGET_INVALID/);
  // Even a caller attempting to transplant the old operation ID into a fresh
  // lease cannot evade the original page input tombstone.
  const transplanted=f.bind(old.identity.operationID);
  assert.throws(()=>f.stage(transplanted),/BEGIN_REFUSED/);
  f.stage(fresh);f.commit(fresh);await f.settle();assert.equal(f.input.inputCount,2);
  const view=f.makeCard(fresh);f.finish(view);await f.settle();assert.equal(f.observe(fresh).state,'attached');
  assert.equal(f.observe(old).state,'invalidated');assert.equal(f.input.inputCount,2);
  assert.equal(registry.count,2);
});

test('lease generations are bounded and older state cannot bypass current admission', () => {
  for(const key of ['__riftletWebAcceptance20261027v1','__riftletWebAcceptance20261027v2']) {
    const legacy=fixture({mode:'missing'});
    legacy.context[key]={valid:()=>true,target:{...native,surface:'webChat'}};
    assert.throws(()=>legacy.target(),/UNPROVEN_CHAT_MODE/);
    assert.equal(legacy.context.__riftletWebAcceptance20261027v3.count,0);
  }
  const f=fixture();let first;
  for(let i=0;i<32;i++) {
    const target=f.target();first ||= target;
    f.document.visibilityState='hidden';for(const fn of f.events.get('visibilitychange')||[]) fn();
    f.document.visibilityState='visible';
  }
  assert.throws(()=>f.target(),/LEASE_GENERATION_LIMIT/);
  const registry=f.context.__riftletWebAcceptance20261027v3;
  assert.equal(registry.count,32);assert.equal(registry.head.target.documentID,first.documentID);
  assert.equal(f.call({action:'validate',target:first}).valid,false);assert.equal(f.input.inputCount,0);
});

test('Window focus/blur, pageshow and every visibility transition revoke the epoch', async () => {
  const triggers=[f=>f.windowEvent('blur'),f=>f.windowEvent('focus'),f=>f.windowEvent('pageshow'),
    f=>{for(const fn of f.events.get('visibilitychange')||[]) fn();}];
  for(const trigger of triggers) {
    const f=fixture({blockedDigest:true}),op=f.bind();f.stage(op);f.commit(op);
    trigger(f);f.release();await f.settle();
    assert.equal(f.input.inputCount,0);assert.equal(f.observe(op).state,'invalidated');
    assert.equal(f.call({action:'validate',target:op.target}).valid,false);
    assert.notEqual(f.target().draftGeneration,op.target.draftGeneration);
  }
});

test('ordinary draft typing and descendant focus events do not revoke the Window epoch', async () => {
  const f=fixture(),op=f.bind();
  f.editor.textContent+=' continued typing';
  f.queueMutation([{type:'characterData',target:f.editor,oldValue:'Existing 中文 draft 👋'}]);
  f.windowEvent('blur',f.editor);f.windowEvent('focus',f.input);
  assert.equal(f.call({action:'validate',target:op.target}).valid,true);
  assert.equal(f.target().draftGeneration,op.target.draftGeneration);
  f.stage(op);f.commit(op);await f.settle();assert.equal(f.input.inputCount,1);
  assert.ok(f.editor.textContent.endsWith(' continued typing'));
});

test('queued transient mutation records are drained before validation and capture reuse', () => {
  for(const method of ['validate','captureTarget']) {
    const f=fixture(),old=f.target();
    f.queueMutation([{type:'attributes',target:f.chatMode,attributeName:'aria-pressed',oldValue:'true'},
      {type:'attributes',target:f.chatMode,attributeName:'aria-pressed',oldValue:'false'}]);
    if(method==='validate') assert.equal(f.call({action:method,target:old}).valid,false);
    else assert.notEqual(f.target().draftGeneration,old.draftGeneration);
    assert.equal(f.input.inputCount,0);
  }
});

test('final input drains pending mode or node round-trips after asynchronous hashing', async () => {
  const changes=[f=>[{type:'attributes',target:f.chatMode,attributeName:'aria-pressed',oldValue:'true'},
      {type:'attributes',target:f.chatMode,attributeName:'aria-pressed',oldValue:'false'}],
    f=>[{type:'childList',target:f.body,removedNodes:[f.form],addedNodes:[f.form]}]];
  for(const records of changes) {
    const f=fixture({blockedDigest:true}),op=f.bind();f.stage(op);f.commit(op);
    // Deliberately withhold the observer callback until the program itself
    // drains takeRecords. The final DOM snapshot looks completely unchanged.
    f.queueMutation(records(f));f.release();await f.settle();
    assert.equal(f.input.inputCount,0);assert.equal(f.observe(op).state,'invalidated');
  }
});
