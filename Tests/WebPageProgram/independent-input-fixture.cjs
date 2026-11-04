'use strict';
// Small controlled DOM for command semantics. Native FileList/Selection behavior
// is separately exercised by chrome-input-resource.test.cjs.
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');
const {webcrypto,createHash}=require('node:crypto');
const source=fs.readFileSync(path.join(__dirname,'../../Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js'),'utf8');
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==','base64');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const native={applicationID:'com.google.Chrome',sessionID:'synthetic-local-session',windowID:'17',tabID:'19'};
function fixture({route='https://chatgpt.com/c/ordinary-thread',accept=true,focused=true,visible=true}={}) {
 const observers=[],events=new Map();
 let changes=0,setters=0,sends=0,onChange=null,onSet=null;
 function matches(node,selector) {
  return selector.split(',').some(part=>{
   part=part.trim();
   if(part==='*')return true;
   if(part===':disabled')return !!node.disabled;
   if(part===':modal')return false;
   if(part.includes(':not('))part=part.replace(/:not\(([^)]+)\)/g,(_,inner)=>matches(node,inner)?'__never__':'');
   const tag=/^[\w-]+/.exec(part)?.[0];
   if(tag&&node.tagName!==tag.toUpperCase())return false;
   const id=/#([\w-]+)/.exec(part)?.[1];if(id&&node.id!==id)return false;
   for(const match of part.matchAll(/\[([\w-]+)(?:([*^$~|]?=)["']?([^\]"']*)["']?)?\]/g)) {
    const [,key,operator,value]=match,actual=node.getAttribute(key);
    if(actual===null)return false;
    if(operator==='='&&actual!==value)return false;
    if(operator==='*='&&!actual.includes(value))return false;
    if(operator==='^='&&!actual.startsWith(value))return false;
   }
   return !part.includes('__never__');
  });
 }
 class Node {
  constructor(tag,attrs={}){this.nodeType=1;this.tagName=tag.toUpperCase();this.attrs={...attrs};this.children=[];this.parentElement=null;this.isConnected=true;this.textContent='';this.disabled=false;this.listeners=new Map();}
  get id(){return this.attrs.id||'';} get parentNode(){return this.parentElement;}
  get type(){return this.attrs.type||'';} get accept(){return this.attrs.accept||'';} get form(){return this.closest('form');}
  get isContentEditable(){return this.attrs.contenteditable==='true';}
  getAttribute(key){return this.attrs[key]??null;} hasAttribute(key){return key in this.attrs;}
  setAttribute(key,value){this.attrs[key]=String(value);} removeAttribute(key){delete this.attrs[key];}
  matches(selector){return matches(this,selector);}
  closest(selector){return this.matches(selector)?this:this.parentElement?.closest?.(selector)||null;}
  contains(node){return this===node||this.children.some(child=>child.contains(node));}
  append(...nodes){for(const node of nodes){node.parentElement=this;node.isConnected=this.isConnected;this.children.push(node);}return nodes[0];}
  appendChild(node){return this.append(node);}
  remove(){if(this.parentElement)this.parentElement.children=this.parentElement.children.filter(node=>node!==this);this.isConnected=false;}
  querySelectorAll(selector){return this.children.flatMap(node=>[node,...node.querySelectorAll('*')]).filter(node=>node.matches(selector));}
  querySelector(selector){return this.querySelectorAll(selector)[0]||null;}
  getClientRects(){return this.rendered===false?[]:[{width:100,height:40}];}
  getBoundingClientRect(){return {width:100,height:40,top:0,left:0,bottom:40,right:100};}
  addEventListener(type,fn){const list=this.listeners.get(type)||[];list.push(fn);this.listeners.set(type,list);}
  removeEventListener(type,fn){this.listeners.set(type,(this.listeners.get(type)||[]).filter(f=>f!==fn));}
  dispatchEvent(event){event.target=this;for(const fn of this.listeners.get(event.type)||[])fn(event);for(const fn of events.get(event.type)||[])fn(event);return true;}
 }
 class Input extends Node {
  constructor(){super('input',{type:'file',accept:'image/*'});this._files=[];}
  get files(){return this._files;}
  set files(value){setters++;onSet?.();this._files=value;}
  get form(){return this.closest('form');}
  get type(){return 'file';} get accept(){return this.attrs.accept||'';}
  get value(){return this._files.length?'C:\\fakepath\\'+this._files[0].name:'';}
  set value(value){if(value!=='')throw Error('InvalidStateError');this._files=[];}
  dispatchEvent(event){if(event.type==='change'){changes++;onChange?.(this.files[0]);if(accept)addCard(this.files[0].name);}return super.dispatchEvent(event);}
 }
 const body=new Node('body'),form=body.append(new Node('form'));
 const editor=form.append(new Node('div',{id:'prompt-textarea',contenteditable:'true',role:'textbox'}));
 editor.textContent='Existing 中文 draft 👋 and selection';
 form.addEventListener('submit',()=>{sends++;});form.submit=()=>{sends++;};form.requestSubmit=()=>{sends++;};
 const input=form.append(new Input()),oldCard=form.append(new Node('div',{'data-file-name':'existing.png',role:'button',title:'existing.png'}));
 oldCard.append(new Node('img',{alt:'existing.png',src:'blob:old-image'}));
 const selection={anchorNode:editor,focusNode:editor,anchorOffset:2,focusOffset:7,isCollapsed:false,rangeCount:1,toString:()=>editor.textContent.slice(2,7)};
 const document={body,documentElement:body,visibilityState:visible?'visible':'hidden',hasFocus:()=>focused,activeElement:editor,
  contains:node=>body.contains(node),querySelectorAll:selector=>body.querySelectorAll(selector),querySelector:selector=>body.querySelector(selector),
  getElementById:id=>body.querySelector('#'+id),getSelection:()=>selection,
  addEventListener:(type,fn)=>{const list=events.get(type)||[];list.push(fn);events.set(type,list);},removeEventListener:()=>{}};
 const blobFiles=new Map();let blobID=0;
 class NativeURL extends URL {static createObjectURL(file){const url='blob:fixture-'+(++blobID);blobFiles.set(url,file);return url;}static revokeObjectURL() {}}
 const context=vm.createContext({console,Uint8Array,Map,Set,WeakMap,WeakSet,Promise,File,Blob,atob,btoa,ArrayBuffer,TextDecoder,URL:NativeURL,
  crypto:webcrypto,performance,setTimeout,clearTimeout,queueMicrotask,document,location:{href:route},HTMLInputElement:Input,HTMLElement:Node,Element:Node,Node,
  getSelection:()=>selection,getComputedStyle:node=>({display:node.rendered===false?'none':'block',visibility:'visible',pointerEvents:'auto'}),
  MutationObserver:class{constructor(fn){this.fn=fn;observers.push(this);}observe(){}disconnect(){}takeRecords(){return []; }},
  Event:class{constructor(type,opts={}){this.type=type;Object.assign(this,opts);}},
  DataTransfer:class{constructor(){this.files=[];this.items={add:file=>this.files.push(file)};}},
  addEventListener:()=>{},removeEventListener:()=>{},history:{pushState:()=>{}},CSS:{escape:value=>value},
  fetch:()=>{throw Error('network forbidden');}});
 vm.runInContext('globalThis.top=globalThis;globalThis.window=globalThis',context);
 const program=vm.runInContext('('+source+')',context);
 const call=command=>program(command,native);
 const notify=()=>{for(const observer of observers)observer.fn([{type:'childList',target:form,addedNodes:[],removedNodes:[]}]);};
 function addCard(name,{placeholder=false,progress=true}={}) {
  const card=form.append(new Node('div',{'data-file-name':name,title:name,'aria-label':name,role:'button'}));
  if(!placeholder){const img=card.append(new Node('img',{alt:name,src:'blob:current-'+name}));img.src=img.currentSrc=img.attrs.src;img.complete=false;img.naturalWidth=0;}
  if(progress)card.append(new Node('div',{role:'progressbar','aria-valuenow':'10'}));
  notify();return card;
 }
 function bind({bytes=png,target=call({action:'captureTarget'}),id=webcrypto.randomUUID(),pin=false}={}) {
  if(pin)target=call({action:'pinTarget',target,clickBindingID:webcrypto.randomUUID()});
  const identity={operationID:id,assetID:webcrypto.randomUUID(),attempt:1,assetSHA256:sha(bytes),target},invocationID=webcrypto.randomUUID();
  return {identity,target,bytes,name:'riftlet-'+id+'.png',invocationID,command:action=>({action,target,identity,invocationID})};
 }
 function stage(op){call({...op.command('begin'),invocationID:op.invocationID,uploadName:op.name,mediaType:'image/png',byteCount:op.bytes.length});call({...op.command('chunk'),chunkIndex:0,chunkBase64:op.bytes.toString('base64')});}
 const commit=op=>call({...op.command('commit'),chunkIndex:1});
 const observe=op=>call(op.command('observe')).observation;
 const waitFor=async(fn,label='page result')=>{const deadline=Date.now()+2000;do{const value=fn();if(value)return value;await new Promise(r=>setTimeout(r,1));}while(Date.now()<deadline);throw Error('bounded wait expired: '+label);};
 return {call,bind,stage,commit,observe,waitFor,notify,addCard,body,form,editor,input,oldCard,selection,context,document,Node,
  setChange:fn=>{onChange=fn;},setSetter:fn=>{onSet=fn;},setAccept:value=>{accept=value;},
  get changes(){return changes;},get setters(){return setters;},get sends(){return sends;},
  setRoute:href=>{context.location.href=href;},setFocused:value=>{focused=value;}};
}
module.exports={fixture,png,sha,native};
