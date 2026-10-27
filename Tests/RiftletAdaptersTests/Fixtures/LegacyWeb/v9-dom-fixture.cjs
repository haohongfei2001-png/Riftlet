// Frozen synthetic DOM helper for original v9 closures. No network or GUI.
module.exports = function legacyFixture(source, version, options) {
'use strict';
// Runs the bundled production-candidate program against controlled DOM events.
// This is deterministic integration regression, never live ChatGPT/GUI evidence.
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const {webcrypto, createHash} = require('node:crypto');
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
      const ops=[];for(let g=context.__riftletWebAcceptance20261027v9?.head;g;g=g.next) ops.push(...g.operations.values());
      if (ops.every(op=>!op.committed || op.invalid || (op.fileHashVerified && !op.proofPending))) return;
    } while(Date.now()<deadline);
    assert.fail('bounded synthetic async work did not settle');
  };
  const makeCard = (op, initialProgress = 20) => {
    const card = form.append(new Node('div',{role:'button','aria-label':op.name}));
    const image = card.append(new TestImage()); image.attrs.alt=op.name;image.src='blob:upload';
    const progress = card.append(new Node('div',{role:'progressbar','aria-label':'正在上传 '+op.name,'aria-valuenow':String(initialProgress)}));
    if (initialProgress === null) delete progress.attrs['aria-valuenow'];
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
return fixture(options);
};
