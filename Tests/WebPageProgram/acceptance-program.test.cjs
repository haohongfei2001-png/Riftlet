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

function fixture({blockedDigest = false, blockedInputDigest = false, route = 'https://chatgpt.com/', mode = 'chat', thread = false} = {}) {
  const events = new Map(), globalEvents = new Map(), navigationEvents = new Map();
  let focused = true, releaseDigest, digestCalls = 0;
  const mutationObservers=[];
  const digestGate = blockedDigest || blockedInputDigest ? new Promise(resolve => { releaseDigest = resolve; }) : Promise.resolve();
  class Node {
    constructor(tag, attrs = {}) { this.nodeType=1;this.tagName = tag.toUpperCase(); this.attrs = {...attrs}; this.isConnected = true; this.children = []; this.parent = null; this.textContent = ''; }
    getAttribute(k) { return this.attrs[k] ?? null; }
    hasAttribute(k) { return Object.prototype.hasOwnProperty.call(this.attrs,k); }
    get parentElement() { return this.parent?.nodeType===1 ? this.parent : null; }
    get isContentEditable() { return this.attrs.contenteditable==='true'; }
    getClientRects() { return this.rendered===false ? [] : [{}]; }
    matches(selector) { return selector===':disabled' && (this.disabled===true || this.hasAttribute('disabled') || this.disabledByFieldset===true); }
    get parentNode() { return this.parent; }
    contains(n) { return n === this || this.children.some(c => c.contains(n)); }
    closest(selector) { if ((selector === 'form' && this.tagName === 'FORM') || (selector === 'header' && this.tagName === 'HEADER') || (selector === '[role=button]' && this.attrs.role === 'button')) return this; return this.parent?.closest(selector) || null; }
    append(n) { n.parent = this; this.children.push(n); return n; }
    querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
    querySelectorAll(selector) {
      const all = this.children.flatMap(c => [c, ...c.querySelectorAll('*')]);
      if (selector === '*') return all;
      if (selector === ':modal') return all.filter(n=>n.nativeModal===true);
      if (selector === '[role=dialog][aria-modal=true],[role=alertdialog][aria-modal=true]') return all.filter(n=>['dialog','alertdialog'].includes(n.attrs.role)&&n.attrs['aria-modal']==='true');
      if (selector === 'form[data-chatgpt-composer][data-composer-placement=thread][data-thread-find-composer=true]') return all.filter(n=>n.tagName==='FORM' && n.attrs['data-chatgpt-composer']!==undefined && n.attrs['data-composer-placement']==='thread' && n.attrs['data-thread-find-composer']==='true');
      if (selector === '[contenteditable=true][role=textbox][aria-label="询问 ChatGPT"]') return all.filter(n=>n.attrs.contenteditable==='true' && n.attrs.role==='textbox' && n.attrs['aria-label']==='询问 ChatGPT');
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
  const body = new Node('body'), form = body.append(new Node('form')), editor = form.append(new Node('div',{contenteditable:'true',role:'textbox'}));
  const businessID='local-chatgpt:12345678-1234-1234-1234-123456789ABC';
  const makeFibers=(id=businessID)=>{
    const leaf={stateNode:form,memoizedProps:{},return:null};
    const modeFiber={memoizedProps:{conversationId:id,isHome:false,isWork:false,readOnly:false},child:leaf};leaf.return=modeFiber;
    const draftFiber={memoizedProps:{conversationId:id,draftKey:id,isWorkConversation:false,isTemporaryChat:false,readOnly:false,surfacePlacement:{kind:'thread'}},child:modeFiber};modeFiber.return=draftFiber;
    const root={tag:3,child:draftFiber,return:null,stateNode:{}};draftFiber.return=root;root.stateNode.current=root;
    return {leaf,modeFiber,draftFiber,root};
  };
  let fibers;
  if(thread){
    if(route==='https://chatgpt.com/')route='https://chatgpt.com/c/url-is-not-business-id';
    Object.assign(form.attrs,{'data-chatgpt-composer':'','data-composer-placement':'thread','data-thread-find-composer':'true'});
    Object.assign(editor.attrs,{contenteditable:'true',role:'textbox','aria-label':'询问 ChatGPT'});
    fibers=makeFibers();form.__reactFiber$fixture=fibers.leaf;
  }
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
    visibilityState:'visible', hasFocus:() => focused, activeElement:body,
    querySelectorAll: selector => selector === '[contenteditable=true][role=textbox]' ? [currentEditor] : body.querySelectorAll(selector),
    addEventListener:(type,fn) => { if (!events.has(type)) events.set(type, []); events.get(type).push(fn); },
    getElementById:() => null
  };
  document.contains = node => node === document || body.contains(node);
  body.parent = document;
  // Native MutationRecord node collections are NodeLists, including empty
  // lists on attribute records. They are iterable, but have no Array.some.
  class NodeListLike {
    constructor(nodes) { this.nodes=Array.from(nodes);this.length=this.nodes.length;this.nodes.forEach((node,i)=>{this[i]=node;}); }
    item(index) { return this.nodes[index] ?? null; }
    [Symbol.iterator]() { return this.nodes[Symbol.iterator](); }
  }
  const mutation = (records, deferDelivery = false) => {
    if (!records.length) records=[{type:'childList',target:form,removedNodes:[],addedNodes:[]}];
    records=records.map(record=>({...record,removedNodes:new NodeListLike(record.removedNodes || []),addedNodes:new NodeListLike(record.addedNodes || [])}));
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
  const context = vm.createContext({console, Uint8Array, Map, Set, WeakMap, Promise, File, atob, queueMicrotask,
    getComputedStyle:node=>({display:node.display||'block',visibility:node.visibility||'visible'}),
    performance:{now:()=>performance.now()},
    crypto:{randomUUID:() => webcrypto.randomUUID(),subtle:{digest:async(...args) => { digestCalls++; if(blockedDigest || (blockedInputDigest && digestCalls===2)) await digestGate; return webcrypto.subtle.digest(...args); }}},
    navigation:{addEventListener:(type,fn)=>{if(!navigationEvents.has(type))navigationEvents.set(type,[]);navigationEvents.get(type).push(fn);}},
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
      const ops=[];for(let g=context.__riftletWebAcceptance20261027v12?.head;g;g=g.next) ops.push(...g.operations.values());
      if (ops.every(op=>!op.committed || op.invalid || (op.fileHashVerified && !op.proofPending))) return;
    } while(Date.now()<deadline);
    assert.fail('bounded synthetic async work did not settle');
  };
  const makeCard = (op, initialProgress = 20) => {
    const card = form.append(new Node('div',{role:'button','aria-label':op.name}));
    const image = card.append(new TestImage()); image.attrs.alt=op.name;image.src='blob:upload';
    const progress = card.append(new Node('div',{role:'progressbar','aria-label':'正在上传 '+op.name,'aria-valuenow':String(initialProgress)}));
    if(initialProgress===null)delete progress.attrs['aria-valuenow'];
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
  return {Node,Input,document,body,form,editor,input,businessID,makeFibers,fibers,modeHeader,modeGroup,chatMode,workMode,call,target,bind,stage,commit,observe,settle,makeCard,finish,
    mutate:records=>mutation(records),queueMutation:records=>mutation(records,true),
    navigationEvent:type=>{for(const fn of navigationEvents.get(type)||[])fn();},
    documentEvent:(type,target,isTrusted=true)=>{for(const fn of events.get(type)||[])fn({type,target,isTrusted});},
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
  assert.throws(()=>fixture({route:'https://chatgpt.com/c/example'}).target(),/UNOBSERVED_THREAD_COMPOSER/);
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
  const registry=f.context.__riftletWebAcceptance20261027v12;
  assert.equal(registry.count,1);
  assert.equal(f.observe(old).state,'inputTriggered');assert.equal(registry.count,1);
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
  assert.equal(f.observe(old).state,'inputTriggered');assert.equal(f.input.inputCount,2);
  assert.equal(registry.count,2);
});

test('lease generations are bounded and older state cannot bypass current admission', () => {
  for(const key of ['__riftletWebAcceptance20261027v1','__riftletWebAcceptance20261027v2','__riftletWebAcceptance20261027v3','__riftletWebAcceptance20261027v4','__riftletWebAcceptance20261027v5','__riftletWebAcceptance20261027v6','__riftletWebAcceptance20261027v7']) {
    const legacy=fixture({mode:'missing'});
    legacy.context[key]={valid:()=>true,target:{...native,surface:'webChat'}};
    assert.throws(()=>legacy.target(),/UNPROVEN_CHAT_MODE/);
    assert.equal(legacy.context.__riftletWebAcceptance20261027v12.count,0);
  }
  const f=fixture();let first;
  for(let i=0;i<32;i++) {
    const target=f.target();first ||= target;
    f.document.visibilityState='hidden';for(const fn of f.events.get('visibilitychange')||[]) fn();
    f.document.visibilityState='visible';
  }
  assert.throws(()=>f.target(),/LEASE_GENERATION_LIMIT/);
  const registry=f.context.__riftletWebAcceptance20261027v12;
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


test('current document focus is required even before blur notification is delivered', async () => {
  const f=fixture(),op=f.bind();f.stage(op);
  f.focus(false); // Do not deliver Window blur or visibilitychange.
  assert.equal(f.call({action:'validate',target:op.target}).valid,false);
  assert.throws(()=>f.commit(op),/TARGET_INVALID/);
  assert.equal(f.input.inputCount,0);
  const pending=fixture({blockedDigest:true}),later=pending.bind();pending.stage(later);pending.commit(later);
  pending.focus(false);pending.release();await pending.settle();
  assert.equal(pending.input.inputCount,0);assert.equal(pending.observe(later).state,'invalidated');
});

test('observed current thread fiber exposes logical identity independently from URL and other file inputs', async () => {
  const f=fixture({thread:true});
  for(let i=0;i<3;i++){const input=new f.Input();input.attrs['aria-label']='other '+i;f.form.append(input);}
  const t=f.target();assert.equal(t.logicalDraftIdentity.profileID,'chatgpt-composer-react-20261027-v1');
  assert.equal(t.logicalDraftIdentity.id,f.businessID);assert.ok(!f.context.location.href.includes(f.businessID));
  const op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);f.finish(view);await f.settle();
  assert.equal(f.observe(op).state,'attached');assert.equal(f.input.inputCount,1);
  assert.equal(fixture().target().logicalDraftIdentity,undefined);
});

test('observed persisted thread preserves its exact bare UUID under a separate profile', async () => {
  const f=fixture({thread:true}),id=f.businessID.slice('local-chatgpt:'.length);
  threadCommit(f,id);
  const op=f.bind();
  assert.equal(op.target.logicalDraftIdentity.profileID,'chatgpt-composer-react-persisted-20261027-v1');
  assert.equal(op.target.logicalDraftIdentity.id,id);assert.ok(!f.context.location.href.includes(id));
  threadCommit(f,id);assert.equal(f.call({action:'validate',target:op.target}).valid,true);
  f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);f.finish(view);await f.settle();
  assert.equal(f.observe(op).state,'attached');assert.equal(f.input.inputCount,1);
});

test('persisted identity refuses non-UUID formats and inconsistent complete property groups', () => {
  const id='12345678-1234-1234-1234-123456789ABC';
  for(const invalid of ['not-a-uuid',id+'x',' '+id,id+'\n','chatgpt:'+id,'LOCAL-CHATGPT:'+id,id.replaceAll('-','')]) {
    const f=fixture({thread:true});threadCommit(f,invalid);
    assert.throws(()=>f.target(),/UNPROVEN_THREAD_IDENTITY/);assert.equal(f.input.inputCount,0);
  }
  for(const change of [
    props=>{props.draftKey='local-chatgpt:'+id;},
    props=>{props.draftKey=id.toLowerCase();},
    props=>{props.conversationId='00000000-0000-0000-0000-000000000000';}
  ]) {
    const f=fixture({thread:true}),next=threadCommit(f,id);change(next.draftFiber.memoizedProps);
    assert.throws(()=>f.target(),/UNPROVEN_THREAD_IDENTITY/);assert.equal(f.input.inputCount,0);
  }
});

test('local and persisted profile transitions revoke original leases and cannot forge continuity', async () => {
  for(const startsPersisted of [false,true]) {
    const f=fixture({thread:true}),local=f.businessID,persisted=local.slice('local-chatgpt:'.length);
    const originalID=startsPersisted?persisted:local,nextID=startsPersisted?local:persisted;
    threadCommit(f,originalID);const op=f.bind();f.stage(op);f.commit(op);await f.settle();
    const view=f.makeCard(op);f.finish(view);await f.settle();assert.equal(f.observe(op).state,'attached');
    threadCommit(f,nextID);
    assert.equal(f.call({action:'validate',target:op.target}).valid,false);
    assert.equal(f.observe(op).state,'invalidated');assert.equal(f.observe(op).belongsToOriginalDraft,false);
    const next=f.target();assert.notEqual(next.logicalDraftIdentity.profileID,op.target.logicalDraftIdentity.profileID);
    assert.notEqual(next.draftGeneration,op.target.draftGeneration);
    const forged={...op.target,logicalDraftIdentity:next.logicalDraftIdentity};
    assert.equal(f.call({action:'validate',target:forged}).valid,false);
    assert.equal(f.call({action:'observe',target:forged,identity:{...op.identity,target:forged}}).observation.state,'invalidated');
    threadCommit(f,originalID);
    assert.equal(f.call({action:'validate',target:op.target}).valid,false);
    assert.equal(f.call({action:'validate',target:next}).valid,false);
    assert.equal(f.observe(op).state,'invalidated');assert.equal(f.input.inputCount,1);
  }
});

test('thread mode/identity is strict: absent, partial, inconsistent, Work, temporary and readonly refuse', () => {
  const changes=[
    f=>delete f.form.__reactFiber$fixture,
    f=>delete f.fibers.modeFiber.memoizedProps.isWork,
    f=>delete f.fibers.draftFiber.memoizedProps.draftKey,
    f=>{f.fibers.modeFiber.memoizedProps.isWork=true;},
    f=>{f.fibers.modeFiber.memoizedProps.isHome=true;},
    f=>{f.fibers.modeFiber.memoizedProps.readOnly=true;},
    f=>{f.fibers.draftFiber.memoizedProps.isWorkConversation=true;},
    f=>{f.fibers.draftFiber.memoizedProps.isTemporaryChat=true;},
    f=>{f.fibers.draftFiber.memoizedProps.readOnly=true;},
    f=>{f.fibers.draftFiber.memoizedProps.surfacePlacement.kind='home';},
    f=>{f.fibers.draftFiber.memoizedProps.draftKey='different';},
    f=>{f.fibers.modeFiber.memoizedProps.conversationId='local-chatgpt:00000000-0000-0000-0000-000000000000';},
    f=>{f.form.__reactFiber$other=f.fibers.leaf;}
  ];
  for(const change of changes){const f=fixture({thread:true});change(f);assert.throws(()=>f.target(),/UNPROVEN_THREAD_IDENTITY/);assert.equal(f.input.inputCount,0);}
});

test('current committed fiber is selected through alternate; stale or ambiguous roots and broken ancestry refuse', () => {
  const f=fixture({thread:true}), current=f.fibers, stale=f.makeFibers('local-chatgpt:00000000-0000-0000-0000-000000000000');
  stale.root.stateNode=current.root.stateNode;stale.leaf.alternate=current.leaf;current.leaf.alternate=stale.leaf;
  f.form.__reactFiber$fixture=stale.leaf;
  assert.equal(f.target().logicalDraftIdentity.id,f.businessID);
  stale.modeFiber.memoizedProps.isWork=true;assert.equal(f.target().logicalDraftIdentity.id,f.businessID);
  const invalids=[
    g=>{g.fibers.root.stateNode.current={};},
    g=>{g.fibers.modeFiber.child={};},
    g=>{g.fibers.leaf.stateNode={};},
    g=>{g.fibers.root.return=g.fibers.leaf;},
    g=>{g.fibers.leaf.alternate=g.makeFibers().leaf;}
  ];
  for(const change of invalids){const g=fixture({thread:true});change(g);assert.throws(()=>g.target(),/UNPROVEN_THREAD_IDENTITY/);}
});

test('thread business identity change permanently ends original observation and never relabels its operation', async () => {
  const f=fixture({thread:true}),old=f.bind();f.stage(old);f.commit(old);await f.settle();const view=f.makeCard(old);f.finish(view);await f.settle();
  assert.equal(f.observe(old).state,'attached');
  const freshFibers=f.makeFibers('local-chatgpt:00000000-0000-0000-0000-000000000000');f.form.__reactFiber$fixture=freshFibers.leaf;
  assert.equal(f.observe(old).state,'invalidated');assert.equal(f.observe(old).belongsToOriginalDraft,false);
  const fresh=f.target();assert.notEqual(fresh.logicalDraftIdentity.id,old.target.logicalDraftIdentity.id);
  f.form.__reactFiber$fixture=f.fibers.leaf;
  assert.equal(f.observe(old).state,'invalidated');assert.equal(f.input.inputCount,1);
  const forged={...old.target,logicalDraftIdentity:{...old.target.logicalDraftIdentity,id:fresh.logicalDraftIdentity.id}};
  const result=f.call({action:'observe',target:forged,identity:{...old.identity,target:forged}}).observation;
  assert.equal(result.state,'invalidated');assert.equal(result.belongsToOriginalDraft,false);
});

test('background observation retains proof and correlated late error across input epoch rearm', async () => {
  for(const thread of [false,true]) {
    const f=fixture({thread}),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);f.finish(view);await f.settle();
    const ready=f.observe(op);assert.equal(ready.state,'attached');
    f.focus(false);f.windowEvent('blur');f.document.visibilityState='hidden';for(const fn of f.events.get('visibilitychange')||[])fn();
    assert.equal(f.call({action:'validate',target:op.target}).valid,false);
    assert.equal(f.observe(op).state,'attached');assert.equal(f.observe(op).attachmentID,ready.attachmentID);
    f.focus(true);f.windowEvent('focus');f.document.visibilityState='visible';for(const fn of f.events.get('visibilitychange')||[])fn();
    const next=f.target();assert.notEqual(next.draftGeneration,op.target.draftGeneration);
    assert.equal(next.logicalDraftIdentity?.id,op.target.logicalDraftIdentity?.id);
    assert.equal(f.observe(op).state,'attached');assert.throws(()=>f.commit(op),/TARGET_INVALID/);
    view.card.attrs['data-state']='error';f.mutate([{type:'attributes',target:view.card,attributeName:'data-state'}]);
    const late=f.observe(op);assert.equal(late.hasError,true);assert.equal(late.belongsToOriginalDraft,true);
    assert.equal(late.attachmentID,ready.attachmentID);assert.equal(late.exactImageIdentity,true);assert.equal(f.input.inputCount,1);
  }
});

test('original upload can finish in background but new input cannot start there', async () => {
  const f=fixture({thread:true}),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);
  f.focus(false);f.windowEvent('blur');f.document.visibilityState='hidden';for(const fn of f.events.get('visibilitychange')||[])fn();
  f.finish(view);await f.settle();assert.equal(f.observe(op).state,'attached');
  assert.throws(()=>f.target(),/UNSUPPORTED_TEST_SURFACE/);assert.equal(f.input.inputCount,1);
  view.card.attrs['data-state']='error';f.mutate([{type:'attributes',target:view.card,attributeName:'data-state'}]);
  assert.equal(f.observe(op).hasError,true);assert.equal(f.observe(op).exactImageIdentity,true);
});

test('thread business identity changed during async hash prevents input even when DOM nodes remain', async () => {
  const f=fixture({thread:true,blockedDigest:true}),op=f.bind();f.stage(op);f.commit(op);
  f.form.__reactFiber$fixture=f.makeFibers('local-chatgpt:00000000-0000-0000-0000-000000000000').leaf;
  f.release();await f.settle();assert.equal(f.input.inputCount,0);assert.equal(f.observe(op).state,'invalidated');
});


test('observed 373-level current ancestry is accepted but chains above 512 remain refused', () => {
  for(const count of [373,513]) {
    const f=fixture({thread:true});let child=f.fibers.draftFiber;
    for(let i=0;i<count-4;i++){const parent={memoizedProps:{},child,return:null};child.return=parent;child=parent;}
    child.return=f.fibers.root;f.fibers.root.child=child;
    if(count===373)assert.equal(f.target().logicalDraftIdentity.id,f.businessID);
    else assert.throws(()=>f.target(),/UNPROVEN_THREAD_IDENTITY/);
  }
});


test('trusted composer-external interaction does not hide a committed business ABA', async () => {
  for(const type of ['pointerdown','click','keydown']) {
    const f=fixture({thread:true}),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);f.finish(view);await f.settle();
    const ready=f.observe(op), original=f.form.__reactFiber$fixture;
    f.documentEvent(type,f.body);
    threadCommit(f,'local-chatgpt:00000000-0000-0000-0000-000000000000');
    threadCommit(f);
    assert.equal(f.call({action:'validate',target:op.target}).valid,false);
    assert.equal(f.observe(op).state,'invalidated');
    assert.equal(f.context.__riftletWebAcceptance20261027v12.tail.continuityEvents.outsideInteraction,1);
    assert.equal(f.input.inputCount,1);
  }
});

test('Navigation API events permanently end observation and input despite final business ABA', async () => {
  for(const type of ['navigate','currententrychange']) {
    const f=fixture({thread:true}),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);f.finish(view);await f.settle();
    const original=f.form.__reactFiber$fixture;assert.equal(f.observe(op).state,'attached');
    f.navigationEvent(type);
    f.form.__reactFiber$fixture=f.makeFibers('local-chatgpt:00000000-0000-0000-0000-000000000000').leaf;
    f.form.__reactFiber$fixture=original;
    assert.equal(f.call({action:'validate',target:op.target}).valid,false);
    assert.equal(f.observe(op).state,'invalidated');assert.equal(f.observe(op).belongsToOriginalDraft,false);
    assert.equal(f.context.__riftletWebAcceptance20261027v12.tail.continuityEvents[type],1);
    assert.equal(f.input.inputCount,1);
  }
});

test('trusted editor typing and untrusted external events do not revoke the input epoch', () => {
  const f=fixture({thread:true}),t=f.target();
  for(const type of ['pointerdown','click','keydown']){f.documentEvent(type,f.editor);f.documentEvent(type,f.body,false);}
  assert.equal(f.call({action:'validate',target:t}).valid,true);
  assert.equal(f.context.__riftletWebAcceptance20261027v12.tail.continuityEvents.outsideInteraction,0);
});

function threadCommit(f, id = f.businessID) {
  const next=f.makeFibers(id),root=f.fibers.root.stateNode;
  next.root.stateNode=root;f.form.__reactFiber$fixture=next.leaf;
  root.current=next.root;
  return next;
}

test('v7 root setter observes both real assignments in same-DOM business ABA and never revives old lease', () => {
  const f=fixture({thread:true}),old=f.target(),root=f.fibers.root.stateNode;
  const descriptor=Object.getOwnPropertyDescriptor(root,'current');assert.equal(typeof descriptor.set,'function');
  threadCommit(f,'local-chatgpt:00000000-0000-0000-0000-000000000000');
  threadCommit(f);
  const registry=f.context.__riftletWebAcceptance20261027v12;
  assert.equal([...registry.rootMonitors.values()][0].diagnostics.commits,2);
  assert.equal(f.call({action:'validate',target:old}).valid,false);
  const fresh=f.target();assert.notEqual(fresh.draftGeneration,old.draftGeneration);
  assert.equal(fresh.logicalDraftIdentity.id,old.logicalDraftIdentity.id);
  assert.equal(f.call({action:'validate',target:old}).valid,false);
});

test('v7 same-ID normal commits preserve input and perform one binding check per form across rearm', () => {
  const f=fixture({thread:true}),old=f.target();
  threadCommit(f);assert.equal(f.call({action:'validate',target:old}).valid,true);
  f.windowEvent('blur');f.windowEvent('focus');const fresh=f.target();
  const monitor=[...f.context.__riftletWebAcceptance20261027v12.rootMonitors.values()][0],before=monitor.diagnostics.checks;
  threadCommit(f);assert.equal(monitor.diagnostics.checks-before,1);
  assert.equal(f.call({action:'validate',target:fresh}).valid,true);
  assert.equal(f.call({action:'validate',target:old}).valid,false);
  assert.ok(monitor.diagnostics.elapsedMs>=0);assert.ok(monitor.diagnostics.maxElapsedMs>=0);
});

test('v7 checker exceptions and reentrant commits cannot escape into React or roll back its new tree', () => {
  for(const reentrant of [false,true]) {
    const f=fixture({thread:true}),old=f.target(),root=f.fibers.root.stateNode,next=f.makeFibers();
    next.root.stateNode=root;f.form.__reactFiber$fixture=next.leaf;
    const last={tag:3,stateNode:root,return:null};
    Object.defineProperty(next.modeFiber.memoizedProps,'isWork',{get(){
      if(reentrant){root.current=last;return false;}
      throw Error('private-text-must-not-escape');
    }});
    assert.doesNotThrow(()=>{root.current=next.root;});
    assert.equal(root.current,reentrant?last:next.root);
    const monitor=[...f.context.__riftletWebAcceptance20261027v12.rootMonitors.values()][0];
    assert.equal(monitor.diagnostics.reason,reentrant?'REENTRANT_COMMIT':'CHECK_FAILED');
    assert.equal(monitor.diagnostics.stopped,true);
    delete f.form.__reactFiber$fixture;
    assert.equal(f.call({action:'validate',target:old}).valid,false);
  }
});

test('v7 replaced or frozen root descriptor is permanently disqualified and cannot be reinstalled by capture', () => {
  for(const freeze of [false,true]) {
    const f=fixture({thread:true}),old=f.target(),root=f.fibers.root.stateNode,value=root.current;
    if(freeze)Object.freeze(root);
    else Object.defineProperty(root,'current',{value,writable:true,configurable:true,enumerable:true});
    assert.equal(f.call({action:'validate',target:old}).valid,false);
    assert.throws(()=>f.target(),/ROOT_MONITOR_LOST/);
    const result=f.context.__riftletWebAcceptance20261027v12.stopRootMonitors();
    assert.equal(result[0].restored,false);
    assert.equal(root.current,value);
  }
});

test('v7 explicit stop restores only its own descriptor with the latest committed value and cannot rearm old leases', () => {
  const f=fixture({thread:true}),root=f.fibers.root.stateNode,original=Object.getOwnPropertyDescriptor(root,'current'),old=f.target();
  const next=threadCommit(f);const result=f.context.__riftletWebAcceptance20261027v12.stopRootMonitors();
  const restored=Object.getOwnPropertyDescriptor(root,'current');
  assert.equal(result[0].restored,true);assert.equal(restored.value,next.root);
  for(const key of ['enumerable','writable','configurable'])assert.equal(restored[key],original[key]);
  assert.equal(restored.get,undefined);assert.equal(restored.set,undefined);
  assert.equal(f.call({action:'validate',target:old}).valid,false);assert.throws(()=>f.target(),/ROOT_MONITOR_LOST/);
});

test('v7 ambiguous or replaced original form binding at commit revokes the original lease', () => {
  for(const change of [f=>{f.fibers.modeFiber.memoizedProps.isWork=true;},
    f=>{f.input.formOverride=new f.Node('form');},f=>{f.form.isConnected=false;},
    f=>{f.fibers.draftFiber.memoizedProps.draftKey='ambiguous';}]) {
    const f=fixture({thread:true}),old=f.target(),root=f.fibers.root.stateNode;change(f);
    assert.doesNotThrow(()=>{root.current=root.current;});
    assert.equal(f.call({action:'validate',target:old}).valid,false);
  }
});

test('v7 Home does not instrument React roots; unmodifiable thread descriptors refuse before observer registration', () => {
  const home=fixture();home.target();assert.equal(home.context.__riftletWebAcceptance20261027v12.rootMonitors.size,0);
  const f=fixture({thread:true}),root=f.fibers.root.stateNode;
  Object.defineProperty(root,'current',{value:root.current,writable:false,configurable:false});
  assert.throws(()=>f.target(),/UNOBSERVED_ROOT_DESCRIPTOR/);
  assert.equal(f.events.size,0);assert.equal(f.context.__riftletWebAcceptance20261027v12.count,0);
});

test('R01 body/sidebar interactions keep the original usable composer without focusing its editor', async () => {
  for(const thread of [false,true]) for(const kind of ['body','sidebar']) {
    const f=fixture({thread}),outside=kind==='body'?f.body:f.body.append(new f.Node('aside'));
    const op=f.bind(),beforeText=f.editor.textContent;
    f.document.activeElement=outside;
    for(const type of ['pointerdown','click','keydown'])f.documentEvent(type,outside);
    await Promise.resolve();
    assert.equal(f.call({action:'validate',target:op.target}).valid,true);
    assert.equal(f.target().draftGeneration,op.target.draftGeneration);
    f.stage(op);f.commit(op);await f.settle();
    assert.equal(f.input.inputCount,1);assert.equal(f.document.activeElement,outside);
    assert.equal(f.editor.textContent,beforeText);
    const view=f.makeCard(op);f.finish(view);await f.settle();assert.equal(f.observe(op).state,'attached');
  }
});

test('R01 unavailable composer or attachment capability refuses capture without input', () => {
  const changes=[
    f=>{f.form.inert=true;}, f=>{f.body.attrs.inert='';}, f=>{f.editor.attrs['aria-hidden']='true';},
    f=>{f.body.attrs.hidden='';}, f=>{f.editor.attrs['aria-disabled']='true';},
    f=>{f.editor.attrs.contenteditable='false';},f=>{f.editor.rendered=false;},f=>{f.form.display='none';},
    f=>{f.editor.visibility='hidden';},f=>{f.input.disabled=true;},f=>{f.input.disabledByFieldset=true;},
    f=>{f.input.inert=true;},f=>{f.input.attrs['aria-disabled']='true';}
  ];
  for(const thread of [false,true])for(const change of changes){
    const f=fixture({thread});change(f);assert.throws(()=>f.target(),/COMPOSER_UNAVAILABLE|AMBIGUOUS_COMPOSER/);assert.equal(f.input.inputCount,0);
  }
});

test('R01 native modal and visible semantic blocking dialog refuse while hidden nonblocking dialogs do not', () => {
  for(const nativeModal of [false,true]){
    const f=fixture(),dialog=f.body.append(new f.Node('dialog',{role:'dialog','aria-modal':'true'}));
    dialog.nativeModal=nativeModal;
    assert.throws(()=>f.target(),/COMPOSER_UNAVAILABLE/);
    dialog.attrs.hidden='';dialog.rendered=false;
    if(nativeModal)assert.throws(()=>f.target(),/COMPOSER_UNAVAILABLE/);
    else assert.equal(f.target().surface,'webChat');
  }
  const f=fixture();f.body.append(new f.Node('dialog',{open:'',role:'dialog'}));
  assert.equal(f.target().surface,'webChat');
  const within=fixture();within.form.nativeModal=true;
  assert.equal(within.target().surface,'webChat'); // A top-layer ancestor does not block its own composer.
});

test('R01 intentionally hidden unique file input stays usable but duplicate attachment entry refuses', async () => {
  const f=fixture();f.input.attrs.hidden='';f.input.attrs['aria-hidden']='true';f.input.rendered=false;f.input.display='none';
  const op=f.bind();f.stage(op);f.commit(op);await f.settle();assert.equal(f.input.inputCount,1);
  const other=fixture();other.form.append(new other.Input());
  assert.throws(()=>other.target(),/UNOBSERVED_INPUT_STRUCTURE/);assert.equal(other.input.inputCount,0);
});

test('R01 final asynchronous commit rechecks blockers and focus without redirecting the frozen target', async () => {
  const changes=[f=>{f.form.inert=true;},f=>{f.input.disabled=true;},f=>{f.editor.rendered=false;},
    f=>{f.body.append(new f.Node('div',{role:'alertdialog','aria-modal':'true'}));},f=>f.focus(false)];
  for(const change of changes){
    const f=fixture({blockedDigest:true}),op=f.bind();f.stage(op);f.commit(op);change(f);f.release();await f.settle();
    assert.equal(f.input.inputCount,0);assert.equal(f.observe(op).state,'invalidated');
  }
});

test('R01 interaction that actually opens a blocking dialog revokes only input, preserving committed observation', async () => {
  const f=fixture({thread:true}),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);f.finish(view);await f.settle();
  const original=f.observe(op);assert.equal(original.state,'attached');
  f.documentEvent('click',f.body);
  const modal=f.body.append(new f.Node('div',{role:'dialog','aria-modal':'true'}));await Promise.resolve();
  assert.equal(f.call({action:'validate',target:op.target}).valid,false);
  assert.equal(f.observe(op).state,'attached');assert.equal(f.observe(op).attachmentID,original.attachmentID);
  modal.attrs.hidden='';modal.rendered=false;
  assert.equal(f.call({action:'validate',target:op.target}).valid,false);
  const fresh=f.target();assert.notEqual(fresh.draftGeneration,op.target.draftGeneration);
  assert.equal(fresh.logicalDraftIdentity.id,op.target.logicalDraftIdentity.id);assert.equal(f.input.inputCount,1);
});

test('unsupported unobserved business ABA: assert current limitation after ordinary outside interaction', async () => {
  // Explicit counterexample, NOT fail-closed acceptance. A transient business
  // change that bypasses the root.current setter, DOM mutation and Navigation
  // events is indistinguishable from inert interaction at the final snapshot.
  // Keep this limitation visible alongside the observed-commit ABA rejection.
  for(const type of ['pointerdown','click','keydown']) {
    const f=fixture({thread:true}),target=f.target(),original=f.form.__reactFiber$fixture;
    const monitor=[...f.context.__riftletWebAcceptance20261027v12.rootMonitors.values()][0];
    f.documentEvent(type,f.body);
    f.form.__reactFiber$fixture=f.makeFibers('local-chatgpt:00000000-0000-0000-0000-000000000000').leaf;
    f.form.__reactFiber$fixture=original;
    await Promise.resolve(); // The outside-interaction recheck sees only final A.
    assert.equal(monitor.diagnostics.commits,0);
    assert.equal(f.call({action:'validate',target}).valid,true); // Known unsupported transition class.
    assert.equal(f.context.__riftletWebAcceptance20261027v12.tail.continuityEvents.outsideInteraction,1);
    assert.equal(f.input.inputCount,0); // The fixture does not perform an upload.
  }
});


function setProgress(f, view, value) {
  const oldValue=view.progress.getAttribute('aria-valuenow');
  if(value===null)delete view.progress.attrs['aria-valuenow'];
  else view.progress.attrs['aria-valuenow']=String(value);
  f.mutate([{type:'attributes',target:view.progress,attributeName:'aria-valuenow',oldValue}]);
}

async function startedFixture(options={}) {
  const f=fixture(options),op=f.bind();f.stage(op);f.commit(op);await f.settle();
  const view=f.makeCard(op);setProgress(f,view,40);
  assert.equal(f.observe(op).state,'uploadStarted');
  return {f,op,view};
}

test('v9 correlated progress timeline proves start before independent final ready with exact original identity', async () => {
  const f=fixture({thread:true}),op=f.bind();f.stage(op);
  const pending=f.commit(op);assert.equal(pending.schemaVersion,2);assert.equal(pending.observation.uploadStart,undefined);
  await f.settle();assert.equal(f.observe(op).state,'inputTriggered');
  const view=f.makeCard(op);assert.equal(f.observe(op).uploadStart,undefined);
  setProgress(f,view,40);
  const start=f.observe(op),e=start.uploadStart;
  assert.equal(start.state,'uploadStarted');assert.equal(start.exactImageIdentity,true);
  assert.equal(start.belongsToOriginalDraft,true);assert.equal(start.hasError,false);assert.equal(start.isUploading,true);
  assert.deepEqual(start.identity,op.identity);assert.ok(start.attachmentID);
  assert.deepEqual(Object.keys(e).sort(),['version','signal','evidenceID','inputCount','inputSequence','startSequence','previousProgress','currentProgress','inputObservedAtMS','startObservedAtMS'].sort());
  assert.equal(e.version,1);assert.equal(e.signal,'correlatedProgress');assert.equal(e.inputCount,1);
  assert.match(e.evidenceID,/^[a-f0-9-]{36}$/i);assert.equal(e.previousProgress,20);assert.equal(e.currentProgress,40);
  assert.ok(e.inputSequence>0 && e.startSequence>e.inputSequence);
  assert.ok(Number.isFinite(e.inputObservedAtMS) && e.inputObservedAtMS>=0 && e.startObservedAtMS>e.inputObservedAtMS);
  assert.equal(e.profileID,undefined);assert.equal(e.safeToRetry,undefined);
  const repeated=f.observe(op);assert.deepEqual(repeated.uploadStart,e);
  setProgress(f,view,60);assert.deepEqual(f.observe(op).uploadStart,e);
  setProgress(f,view,100);assert.equal(f.observe(op).uploadStart,undefined);assert.notEqual(f.observe(op).state,'uploadStarted');
  f.finish(view);await f.settle();const ready=f.observe(op);
  assert.equal(ready.state,'attached');assert.equal(ready.attachmentID,start.attachmentID);assert.equal(ready.uploadStart,undefined);
  const internal=f.context.__riftletWebAcceptance20261027v12.tail.operations.get(op.identity.operationID);
  assert.ok(internal.proof.completed>e.startSequence);assert.equal(f.input.inputCount,1);
});

test('v9 files/change, placeholder, identical samples and a lone hundred percent never establish start', async () => {
  const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();
  assert.equal(f.input.files.length,1);assert.equal(f.observe(op).uploadStart,undefined);
  const view=f.makeCard(op);
  for(let i=0;i<5;i++){f.mutate([]);assert.equal(f.observe(op).state,'inputTriggered');assert.equal(f.observe(op).uploadStart,undefined);}
  setProgress(f,view,100);assert.equal(f.observe(op).uploadStart,undefined);
  f.finish(view);await f.settle();assert.equal(f.observe(op).state,'attached');assert.equal(f.observe(op).uploadStart,undefined);
  const hundredOnly=fixture(),hundred=hundredOnly.bind();hundredOnly.stage(hundred);hundredOnly.commit(hundred);await hundredOnly.settle();
  hundredOnly.makeCard(hundred,100);assert.equal(hundredOnly.observe(hundred).uploadStart,undefined);
  const g=fixture(),other=g.bind();g.stage(other);g.commit(other);await g.settle();const placeholder=g.makeCard(other);
  placeholder.card.children=placeholder.card.children.filter(n=>n!==placeholder.progress);placeholder.progress.isConnected=false;
  g.mutate([]);assert.equal(g.observe(other).uploadStart,undefined);
});

test('v9 both progress samples must follow the original input and exact file hash must already verify', async () => {
  const before=fixture(),op=before.bind();before.stage(op);const premature=before.makeCard(op);setProgress(before,premature,40);
  before.commit(op);await before.settle();assert.equal(before.input.inputCount,0);assert.equal(before.observe(op).uploadStart,undefined);
  const f=fixture({blockedInputDigest:true}),later=f.bind();f.stage(later);f.commit(later);
  const deadline=Date.now()+1000;
  while(!f.input.inputCount && Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,1));
  assert.equal(f.input.inputCount,1);
  const view=f.makeCard(later);setProgress(f,view,40);assert.equal(f.observe(later).uploadStart,undefined);
  f.release();await f.settle();assert.equal(f.observe(later).uploadStart,undefined);
  setProgress(f,view,60);assert.equal(f.observe(later).state,'uploadStarted');
});

test('v9 invalid numeric progress or regression permanently disqualifies start without fabricating failure', async () => {
  for(const value of [null,'','NaN','Infinity','-1','101',' 30','30 ','1e2','0x20',10,100]) {
    const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);
    setProgress(f,view,value);assert.equal(f.observe(op).uploadStart,undefined);
    setProgress(f,view,40);const result=f.observe(op);
    assert.equal(result.uploadStart,undefined);assert.equal(result.hasError,false);assert.equal(f.input.inputCount,1);
  }
});

test('v9 progress node replacement, transient detach and changed label cannot inherit start evidence', async () => {
  for(const change of [
    (f,v)=>{const replacement=new f.Node('div',{...v.progress.attrs,'aria-valuenow':'40'});v.card.children=v.card.children.filter(n=>n!==v.progress);v.progress.isConnected=false;v.card.append(replacement);v.progress=replacement;f.mutate([]);},
    (f,v)=>f.mutate([{type:'childList',target:v.card,removedNodes:[v.progress],addedNodes:[v.progress]}]),
    (f,v)=>f.mutate([{type:'attributes',target:v.progress,attributeName:'aria-label',oldValue:'unrelated'}]),
    (f,v)=>{v.card.append(new f.Node('div',{...v.progress.attrs}));f.mutate([]);},
    (f,v)=>{v.progress.attrs['aria-label']='正在上传 another.png';f.mutate([]);}
  ]) {
    const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);
    change(f,view);setProgress(f,view,60);assert.equal(f.observe(op).uploadStart,undefined);assert.equal(f.input.inputCount,1);
  }
});

test('v9 start disappears on original error, missing progress, navigation, card replacement or repeated input', async () => {
  for(const change of [
    (f,o,v)=>{v.card.attrs['data-state']='error';f.mutate([]);},
    (f,o,v)=>{v.card.children=v.card.children.filter(n=>n!==v.progress);v.progress.isConnected=false;f.mutate([]);},
    (f,o,v)=>{f.context.location.href='https://chatgpt.com/c/changed';},
    (f,o,v)=>{f.form.children=f.form.children.filter(n=>n!==v.card);v.card.isConnected=false;f.makeCard(o);},
    (f,o,v)=>f.documentEvent('change',f.input)
  ]) {
    const {f,op,view}=await startedFixture();change(f,op,view);
    const result=f.observe(op);assert.notEqual(result.state,'uploadStarted');assert.equal(result.uploadStart,undefined);
    assert.equal(result.automaticRetryExcluded,false);
  }
});

test('v9 evidence is bound to full operation/attempt/asset/target and remains observation-only after blur', async () => {
  const {f,op}=await startedFixture({thread:true});
  for(const identity of [
    {...op.identity,attempt:2}, {...op.identity,assetID:'33333333-3333-4333-8333-333333333333'},
    {...op.identity,assetSHA256:'a'.repeat(64)}, {...op.identity,operationID:'33333333-3333-4333-8333-333333333333'},
    {...op.identity,target:{...op.target,draftGeneration:'other'}}
  ])assert.equal(f.call({action:'observe',target:identity.target,identity}).observation.uploadStart,undefined);
  const start=f.observe(op);f.windowEvent('blur');f.focus(false);
  assert.equal(f.call({action:'validate',target:op.target}).valid,false);
  assert.deepEqual(f.observe(op).uploadStart,start.uploadStart);assert.equal(f.input.inputCount,1);
});

test('v9 registry does not inspect, mutate or stop an existing v8 observer', () => {
  const f=fixture();let touched=0;
  const legacy=new Proxy({}, {get(){touched++;throw Error('legacy observer accessed');},set(){touched++;throw Error('legacy observer mutated');}});
  Object.defineProperty(f.context,'__riftletWebAcceptance20261027v8',{value:legacy,configurable:false,writable:false});
  assert.ok(f.target());assert.ok(f.context.__riftletWebAcceptance20261027v12);assert.equal(touched,0);
});


test('v9 finite zero-to-fractional progress is valid and later regression cancels start permanently', async () => {
  const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op,0);
  setProgress(f,view,0.5);const start=f.observe(op);
  assert.equal(start.state,'uploadStarted');assert.equal(start.uploadStart.previousProgress,0);assert.equal(start.uploadStart.currentProgress,0.5);
  setProgress(f,view,0.25);assert.equal(f.observe(op).uploadStart,undefined);
  setProgress(f,view,50);assert.equal(f.observe(op).uploadStart,undefined);assert.equal(f.input.inputCount,1);
});


test('v9 equal input/start monotonic timestamps refuse start under the strict chronology contract', async () => {
  const f=fixture();f.context.performance.now=()=>42;
  const op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);
  setProgress(f,view,40);const result=f.observe(op);
  assert.equal(result.state,'inputTriggered');assert.equal(result.uploadStart,undefined);
  assert.equal(result.hasError,false);assert.equal(f.input.inputCount,1);
  f.context.performance.now=()=>43;setProgress(f,view,60);
  assert.equal(f.observe(op).uploadStart,undefined);
  f.finish(view);await f.settle();assert.equal(f.observe(op).state,'attached');
});


function queueProgressBatch(f, view, values) {
  const records=[];
  for(const value of values) {
    const oldValue=view.progress.getAttribute('aria-valuenow');
    if(value===null)delete view.progress.attrs['aria-valuenow'];
    else view.progress.attrs['aria-valuenow']=String(value);
    records.push({type:'attributes',target:view.progress,attributeName:'aria-valuenow',oldValue});
  }
  f.queueMutation(records);
}

test('v9 queued progress rollback, hundred-to-lower and illegal intermediate values permanently cancel start', async () => {
  for(const alreadyStarted of [false,true])for(const values of [[80,10,40],[80,10,90],[100,40],['broken',40],[null,40]]) {
    const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);
    if(alreadyStarted){setProgress(f,view,30);assert.equal(f.observe(op).state,'uploadStarted');}
    queueProgressBatch(f,view,values); // Final DOM snapshot alone is above the original 20/30.
    const result=f.observe(op); // Must drain all oldValue records before publishing.
    assert.equal(result.uploadStart,undefined);assert.notEqual(result.state,'uploadStarted');
    assert.equal(result.hasError,false);assert.equal(f.input.inputCount,1);
    setProgress(f,view,95);assert.equal(f.observe(op).uploadStart,undefined);
    f.finish(view);await f.settle();assert.equal(f.observe(op).state,'attached');
  }
});

test('v9 a monotonic coalesced progress batch retains start eligibility without inventing extra samples', async () => {
  const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);
  queueProgressBatch(f,view,[20,30,40,60]);const result=f.observe(op);
  assert.equal(result.state,'uploadStarted');assert.equal(result.uploadStart.previousProgress,20);
  assert.equal(result.uploadStart.currentProgress,60);assert.equal(result.uploadStart.inputCount,1);
});


test('v9 final proof keeps an internal diagnostic timestamp without adding receipt fields or a new completion gate', async () => {
  const f=fixture();let clock=10;f.context.performance.now=()=>clock;
  const op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op);
  clock=20;setProgress(f,view,40);const start=f.observe(op);
  assert.equal(start.uploadStart.inputObservedAtMS,10);assert.equal(start.uploadStart.startObservedAtMS,20);
  clock=30;f.finish(view);await f.settle();
  const envelope=f.call(op.command('observe')),proof=f.context.__riftletWebAcceptance20261027v12.tail.operations.get(op.identity.operationID).proof;
  assert.equal(envelope.observation.state,'attached');assert.equal(proof.completedAtMS,30);
  assert.ok(proof.completedAtMS>start.uploadStart.startObservedAtMS);
  assert.equal(envelope.completedAtMS,undefined);assert.equal(envelope.observation.completedAtMS,undefined);
  assert.equal(envelope.observation.uploadStart,undefined);assert.equal(JSON.stringify(envelope).includes('completedAtMS'),false);
  // Diagnostic data is deliberately not an additional ready criterion.
  proof.completedAtMS=NaN;assert.equal(f.observe(op).state,'attached');
});


test('v10 real initial missing progress waits on its original node and two observed decimals establish start', async () => {
  const f=fixture();let clock=10;f.context.performance.now=()=>clock;
  const op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op,null);
  const internal=f.context.__riftletWebAcceptance20261027v12.tail.operations.get(op.identity.operationID);
  assert.equal(internal.progressNode,view.progress);assert.equal(internal.progressValue,null);assert.equal(internal.startDisqualified,false);
  for(let i=0;i<3;i++){f.mutate([]);assert.equal(f.observe(op).uploadStart,undefined);}
  clock=20;setProgress(f,view,4.5378966329499795);
  assert.equal(f.observe(op).uploadStart,undefined);assert.equal(internal.progressValue,4.5378966329499795);
  clock=30;setProgress(f,view,9.075793265899959);const start=f.observe(op);
  assert.equal(start.state,'uploadStarted');assert.equal(start.uploadStart.previousProgress,4.5378966329499795);
  assert.equal(start.uploadStart.currentProgress,9.075793265899959);
  assert.equal(start.uploadStart.inputObservedAtMS,10);assert.equal(start.uploadStart.startObservedAtMS,30);
  assert.equal(f.input.inputCount,1);f.finish(view);await f.settle();assert.equal(f.observe(op).state,'attached');
});

test('v10 finite-then-missing and coalesced missing round trips permanently disqualify start', async () => {
  for(const initial of [null,4.5378966329499795])for(const values of [[4.5378966329499795,null,9.075793265899959],[4.5378966329499795,null],[100,null,9.075793265899959],['',9.075793265899959]]) {
    const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op,initial);
    queueProgressBatch(f,view,values);assert.equal(f.observe(op).uploadStart,undefined);
    const internal=f.context.__riftletWebAcceptance20261027v12.tail.operations.get(op.identity.operationID);
    assert.equal(internal.startDisqualified,true);
    setProgress(f,view,20);setProgress(f,view,40);assert.equal(f.observe(op).uploadStart,undefined);assert.equal(f.input.inputCount,1);
    f.finish(view);await f.settle();assert.equal(f.observe(op).state,'attached');
  }
  const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op,null);
  setProgress(f,view,4.5378966329499795);setProgress(f,view,null);setProgress(f,view,9.075793265899959);
  assert.equal(f.observe(op).uploadStart,undefined);
});

test('v10 initial missing progress cannot survive replacement or transient removal', async () => {
  for(const replace of [false,true]) {
    const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op,null),old=view.progress;
    if(replace){view.card.children=view.card.children.filter(n=>n!==old);old.isConnected=false;view.progress=view.card.append(new f.Node('div',{role:'progressbar','aria-label':'正在上传 '+op.name}));}
    f.mutate([{type:'childList',target:view.card,removedNodes:[old],addedNodes:[view.progress]}]);
    setProgress(f,view,4.5378966329499795);setProgress(f,view,9.075793265899959);
    assert.equal(f.observe(op).uploadStart,undefined);
    assert.equal(f.context.__riftletWebAcceptance20261027v12.tail.operations.get(op.identity.operationID).startDisqualified,true);
  }
});

test('v10 monotonic coalesced initial missing history cannot invent two sampled finite values', async () => {
  const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op,null);
  queueProgressBatch(f,view,[4.5378966329499795,9.075793265899959]);
  assert.equal(f.observe(op).uploadStart,undefined);
  setProgress(f,view,13.61368989884994);const start=f.observe(op);
  assert.equal(start.state,'uploadStarted');assert.equal(start.uploadStart.previousProgress,9.075793265899959);
});

test('v10 initial missing exception does not admit malformed numeric placeholders or access the old v9 registry', async () => {
  for(const invalid of ['', 'NaN', 'Infinity', '-1', '101']) {
    const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();const view=f.makeCard(op,invalid);
    setProgress(f,view,4.5378966329499795);setProgress(f,view,9.075793265899959);assert.equal(f.observe(op).uploadStart,undefined);
  }
  const f=fixture();let touched=0;
  Object.defineProperty(f.context,'__riftletWebAcceptance20261027v9',{value:new Proxy({}, {get(){touched++;throw Error('old v9 accessed');},set(){touched++;throw Error('old v9 mutated');}})});
  assert.ok(f.target());assert.equal(touched,0);
});


test('v11 real NodeList-like callbacks finish original upload without any native observe after start', async () => {
  const f=fixture(),op=f.bind();f.stage(op);f.commit(op);await f.settle();
  const internal=f.context.__riftletWebAcceptance20261027v12.tail.operations.get(op.identity.operationID);
  const view=f.makeCard(op,null);
  setProgress(f,view,4.5378966329499795);assert.equal(internal.uploadStart,null);
  setProgress(f,view,9.075793265899959);assert.ok(internal.uploadStart);
  // No f.observe(), captureTarget(), drain(), or query drives progress below.
  const startSequence=internal.uploadStart.startSequence;
  setProgress(f,view,100);assert.ok(internal.hundred>startSequence);
  view.card.children=view.card.children.filter(node=>node!==view.progress);view.progress.isConnected=false;
  f.mutate([{type:'childList',target:view.card,removedNodes:[view.progress],addedNodes:[]}]);
  assert.ok(internal.ended>internal.hundred);
  view.image.src='data:image/png;base64,'+op.bytes.toString('base64');
  f.mutate([{type:'attributes',target:view.image,attributeName:'src'}]);
  for(const listener of f.events.get('load')||[])listener({type:'load',target:view.image});
  await f.settle();assert.ok(internal.loaded>internal.hundred);assert.ok(internal.proof);
  assert.ok(internal.proof.completed>internal.loaded);assert.equal(f.input.inputCount,1);
  assert.equal(f.observe(op).state,'attached');
});


test('v11 never mutates or stops a historical v10 observer when installing a new registry', () => {
  const f=fixture();let touched=0;
  Object.defineProperty(f.context,'__riftletWebAcceptance20261027v10',{value:new Proxy({}, {get(){touched++;throw Error('old v10 accessed');},set(){touched++;throw Error('old v10 mutated');}})});
  assert.ok(f.target());assert.equal(touched,0);assert.ok(f.context.__riftletWebAcceptance20261027v12);
});


test('v12 256 KiB chunks retain exact per-index ACK and one commit for the real-size fixture', async () => {
  const bytes=Buffer.alloc(3147775,77);png.copy(bytes,0,0,8);
  const f=fixture(),op=f.bind('11111111-1111-4111-8111-111111111111',bytes);
  const begin=f.call({...op.command('begin'),uploadName:op.name,mediaType:'image/png',byteCount:bytes.length});
  assert.equal(begin.nextChunk,0);
  let index=0;
  for(let offset=0;offset<bytes.length;offset+=256*1024,index++) {
    const command={...op.command('chunk'),chunkIndex:index,chunkBase64:bytes.subarray(offset,offset+256*1024).toString('base64')};
    const ack=f.call(command);assert.equal(ack.operationID,op.identity.operationID);assert.equal(ack.attempt,1);assert.equal(ack.nextChunk,index+1);
    if(index===0)assert.throws(()=>f.call(command),/CHUNK_REFUSED/);
  }
  assert.equal(index,13);
  f.call({...op.command('commit'),chunkIndex:index});await f.settle();assert.equal(f.input.inputCount,1);
  assert.throws(()=>f.call({...op.command('commit'),chunkIndex:index}),/COMMIT_REFUSED/);
  assert.throws(()=>f.call({...op.command('begin'),uploadName:op.name,mediaType:'image/png',byteCount:bytes.length}),/BEGIN_REFUSED/);
  f.observe(op);f.observe(op);assert.equal(f.input.inputCount,1);
});

test('v12 decoded and encoded chunk bounds independently reject capacity overflow without input', () => {
  for(const size of [256*1024+1,256*1024+3]) {
    const bytes=Buffer.alloc(size,7);png.copy(bytes,0,0,8);
    const f=fixture(),op=f.bind('11111111-1111-4111-8111-111111111111',bytes);
    f.call({...op.command('begin'),uploadName:op.name,mediaType:'image/png',byteCount:size});
    const expected=size===256*1024+1?/CHUNK_SIZE/:/CHUNK_REFUSED/;
    assert.throws(()=>f.call({...op.command('chunk'),chunkIndex:0,chunkBase64:bytes.toString('base64')}),expected);
    assert.equal(f.input.inputCount,0);
  }
  const f=fixture(),op=f.bind();
  assert.throws(()=>f.call({...op.command('begin'),uploadName:op.name,mediaType:'image/png',byteCount:8*1024*1024+1}),/BEGIN_REFUSED/);
  assert.equal(f.call({...op.command('begin'),uploadName:op.name,mediaType:'image/png',byteCount:8*1024*1024}).nextChunk,0);
  assert.equal(f.input.inputCount,0);
});

test('v12 enlarged chunks still refuse changed full identity and fail a complete-hash mismatch before input', async () => {
  const bytes=Buffer.alloc(256*1024,7);png.copy(bytes,0,0,8);
  const f=fixture(),op=f.bind('11111111-1111-4111-8111-111111111111',bytes);
  f.call({...op.command('begin'),uploadName:op.name,mediaType:'image/png',byteCount:bytes.length});
  const command={...op.command('chunk'),chunkIndex:0,chunkBase64:bytes.toString('base64')};
  assert.throws(()=>f.call({...command,identity:{...op.identity,attempt:2}}),/ORIGINAL_OPERATION_REQUIRED/);
  const wrong=Buffer.from(bytes);wrong[wrong.length-1]^=1;
  f.call({...command,chunkBase64:wrong.toString('base64')});f.commit(op);await f.settle();
  assert.equal(f.input.inputCount,0);assert.equal(f.observe(op).state,'invalidated');
  assert.throws(()=>f.commit(op),/COMMIT_REFUSED/);
});

test('v12 cannot acquire a new input lease for an old v11 operation or touch its registry', () => {
  const f=fixture();let touched=0;
  Object.defineProperty(f.context,'__riftletWebAcceptance20261027v11',{value:new Proxy({}, {get(){touched++;throw Error('old v11 accessed');},set(){touched++;throw Error('old v11 mutated');}})});
  const op=f.bind(),old={...op.target,documentID:'original-v11-document'};
  assert.equal(f.call({action:'validate',target:old}).valid,false);
  assert.throws(()=>f.call({action:'commit',target:old,identity:{...op.identity,target:old},chunkIndex:1}),/TARGET_INVALID/);
  assert.equal(touched,0);assert.equal(f.input.inputCount,0);
});
