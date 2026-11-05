'use strict';
// Small controlled DOM for command semantics. Native FileList/Selection behavior
// is separately exercised by chrome-input-resource.test.cjs.
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');
const {webcrypto,createHash}=require('node:crypto');
const source=fs.readFileSync(process.env.RIFTLET_PAGE_PROGRAM_SOURCE||path.join(__dirname,'../../Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js'),'utf8');
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==','base64');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const native={applicationID:'com.google.Chrome',sessionID:'synthetic-local-session',windowID:'17',tabID:'19'};
function fixture({route='https://chatgpt.com/c/ordinary-thread',accept=true,focused=true,visible=true,programSource=source,editorTag='div'}={}) {
 const observers=[],events=new Map();
 function queueMutation(record){
  for(const observer of observers){
   const {root,options}=observer;
   if(!root||!options[record.type]||(root!==record.target&&!(options.subtree&&root.contains(record.target))))continue;
   if(record.type==='attributes'&&options.attributeFilter&&!options.attributeFilter.includes(record.attributeName))continue;
   observer.records.push(record);
   if(observer.queued)continue;
   observer.queued=true;
   queueMicrotask(()=>{observer.queued=false;const batch=observer.takeRecords();if(batch.length)observer.fn(batch,observer);});
  }
 }
 let changes=0,setters=0,sends=0,chooserOpens=0,onChange=null,onSet=null;
 class Event {
  constructor(type,opts={}){this.type=type;this.defaultPrevented=false;this.isTrusted=false;Object.assign(this,opts);}
  preventDefault(){if(this.cancelable)this.defaultPrevented=true;}
  stopPropagation(){this.propagationStopped=true;}
  stopImmediatePropagation(){this.propagationStopped=true;this.immediateStopped=true;}
 }
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
  constructor(tag,attrs={}){this.nodeType=1;this.tagName=tag.toUpperCase();this.attrs={...attrs};this.children=[];this.parentElement=null;this._text='';this.disabled=false;this.listeners=new Map();}
  get isConnected(){return this===body||this.parentElement?.isConnected===true;}
  get textContent(){return this._text+this.children.map(node=>node.textContent).join('');}
  set textContent(value){for(const child of [...this.children])child.remove();this._text=String(value);queueMutation({type:'childList',target:this,addedNodes:[],removedNodes:[]});}
  get id(){return this.attrs.id||'';} get parentNode(){return this.parentElement;}
  get type(){return this.attrs.type||(this.tagName==='BUTTON'?'submit':'');} get accept(){return this.attrs.accept||'';} get form(){return this.closest('form');}
  get isContentEditable(){return this.attrs.contenteditable==='true';}
  getAttribute(key){return this.attrs[key]??null;} hasAttribute(key){return key in this.attrs;}
  setAttribute(key,value){this.attrs[key]=String(value);queueMutation({type:'attributes',target:this,attributeName:key});}
  removeAttribute(key){delete this.attrs[key];queueMutation({type:'attributes',target:this,attributeName:key});}
  matches(selector){return matches(this,selector);}
  closest(selector){return this.matches(selector)?this:this.parentElement?.closest?.(selector)||null;}
  contains(node){return this===node||this.children.some(child=>child.contains(node));}
  append(...nodes){for(const node of nodes){if(node.parentElement)node.remove();node.parentElement=this;this.children.push(node);queueMutation({type:'childList',target:this,addedNodes:[node],removedNodes:[]});}return nodes[0];}
  appendChild(node){return this.append(node);}
  remove(){const parent=this.parentElement;if(!parent)return;parent.children=parent.children.filter(node=>node!==this);this.parentElement=null;queueMutation({type:'childList',target:parent,addedNodes:[],removedNodes:[this]});}
  querySelectorAll(selector){return this.children.flatMap(node=>[node,...node.querySelectorAll('*')]).filter(node=>node.matches(selector));}
  querySelector(selector){return this.querySelectorAll(selector)[0]||null;}
  getClientRects(){for(let node=this;node;node=node.parentElement)if(node.rendered===false||node.hidden)return [];return this.isConnected?[{width:100,height:40}]:[];}
  getBoundingClientRect(){return {width:100,height:40,top:0,left:0,bottom:40,right:100};}
  addEventListener(type,fn,options=false){const list=this.listeners.get(type)||[];list.push({fn,capture:options===true||!!options.capture});this.listeners.set(type,list);}
  removeEventListener(type,fn){this.listeners.set(type,(this.listeners.get(type)||[]).filter(item=>item.fn!==fn));}
  dispatchEvent(event){
   event.target=this;
   const invoke=(list,capture)=>{for(const item of [...list]){if(event.immediateStopped)break;if(item.capture===capture){event.currentTarget=this;item.fn.call(this,event);}}};
   const reachesDocument=document.contains(this);
   if(reachesDocument)invoke(events.get(event.type)||[],true);
   const ancestors=[];for(let node=this.parentElement;node;node=node.parentElement)ancestors.push(node);
   for(const node of [...ancestors].reverse())invoke(node.listeners.get(event.type)||[],true);
   invoke(this.listeners.get(event.type)||[],true);invoke(this.listeners.get(event.type)||[],false);
   if(event.bubbles&&!event.propagationStopped)for(const node of ancestors)invoke(node.listeners.get(event.type)||[],false);
   if(reachesDocument&&!event.propagationStopped)invoke(events.get(event.type)||[],false);
   return !event.defaultPrevented;
  }
  click(){const allowed=this.dispatchEvent(new Event('click',{bubbles:true,cancelable:true}));if(allowed&&this.tagName==='LABEL')this.control?.click();if(allowed&&this.type==='file'){chooserOpens++;this.chooserOpens++;}if(allowed&&this.tagName==='BUTTON'&&this.type==='submit'&&this.form)this.form.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));}
  focus(){document.activeElement=this;}
  setSelectionRange(start,end,direction='none'){this.selectionStart=start;this.selectionEnd=end;this.selectionDirection=direction;}
  get control(){return this.tagName==='LABEL'?(document.getElementById(this.getAttribute('for'))||this.querySelector('input')):null;}
 }
 class Input extends Node {
  constructor(){super('input',{type:'file',accept:'image/*'});this._files=[];this.setterCount=0;this.changeCount=0;this.chooserOpens=0;}
  get files(){return this._files;}
  set files(value){setters++;this.setterCount++;onSet?.();this._files=value;}
  get form(){return this.closest('form');}
  get type(){return 'file';} get accept(){return this.attrs.accept||'';}
  get value(){return this._files.length?'C:\\fakepath\\'+this._files[0].name:'';}
  set value(value){if(value!=='')throw Error('InvalidStateError');this._files=[];}
  showPicker(){chooserOpens++;this.chooserOpens++;}
  dispatchEvent(event){if(event.type==='change'){changes++;this.changeCount++;onChange?.(this.files[0],this);if(this.applicationAccept??accept)addCard(this.files[0].name);}return super.dispatchEvent(event);}
 }
 const body=new Node('body'),form=body.append(new Node('form'));
 const editor=form.append(new Node(editorTag,editorTag==='textarea'?{id:'prompt-textarea',role:'textbox'}:{id:'prompt-textarea',contenteditable:'true',role:'textbox'}));
 editor.textContent='Existing 中文 draft 👋 and selection';
 if(editorTag==='textarea'){editor.value=editor.textContent;editor.setSelectionRange(2,7,'backward');}
 form.addEventListener('submit',()=>{sends++;});form.submit=()=>{sends++;};form.requestSubmit=()=>{sends++;};
 const input=form.append(new Input()),oldCard=form.append(new Node('div',{'data-file-name':'existing.png',role:'button',title:'existing.png'}));
 oldCard.append(new Node('img',{alt:'existing.png',src:'blob:old-image'}));
 const selection={anchorNode:editor,focusNode:editor,anchorOffset:2,focusOffset:7,isCollapsed:false,rangeCount:1,toString:()=>editor.textContent.slice(2,7),
  setBaseAndExtent(anchor,anchorOffset,focus,focusOffset){Object.assign(this,{anchorNode:anchor,anchorOffset,focusNode:focus,focusOffset,rangeCount:1,isCollapsed:anchor===focus&&anchorOffset===focusOffset});}};
 const document={body,documentElement:body,visibilityState:visible?'visible':'hidden',hasFocus:()=>focused,activeElement:editor,
  createElement:tag=>tag.toLowerCase()==='input'?new Input():new Node(tag),
  contains:node=>body.contains(node),querySelectorAll:selector=>body.querySelectorAll(selector),querySelector:selector=>body.querySelector(selector),
  getElementById:id=>body.querySelectorAll('*').find(node=>node.id===id)||null,getSelection:()=>selection,
  addEventListener:(type,fn,options=false)=>{const list=events.get(type)||[];list.push({fn,capture:options===true||!!options.capture});events.set(type,list);},
  removeEventListener:(type,fn)=>{events.set(type,(events.get(type)||[]).filter(item=>item.fn!==fn));}};
 const blobFiles=new Map();let blobID=0;
 class NativeURL extends URL {static createObjectURL(file){const url='blob:fixture-'+(++blobID);blobFiles.set(url,file);return url;}static revokeObjectURL() {}}
 const context=vm.createContext({console,Uint8Array,Map,Set,WeakMap,WeakSet,Promise,File,Blob,atob,btoa,ArrayBuffer,TextDecoder,URL:NativeURL,
  crypto:webcrypto,performance,setTimeout,clearTimeout,queueMicrotask,
  requestAnimationFrame:callback=>setTimeout(()=>callback(performance.now()),1),cancelAnimationFrame:clearTimeout,
  document,location:{href:route},HTMLInputElement:Input,HTMLElement:Node,Element:Node,Node,
  getSelection:()=>selection,getComputedStyle:node=>({display:node.rendered===false?'none':'block',visibility:'visible',pointerEvents:'auto'}),
  MutationObserver:class{
   constructor(fn){this.fn=fn;this.records=[];observers.push(this);}
   observe(root,options){this.root=root;this.options=options;}
   disconnect(){this.root=null;this.records=[];}
   takeRecords(){return this.records.splice(0);}
  },
  Event,PointerEvent:Event,KeyboardEvent:Event,
  DataTransfer:class{constructor(){this.files=[];this.items={add:file=>this.files.push(file)};}},
  addEventListener:()=>{},removeEventListener:()=>{},history:{pushState:()=>{}},CSS:{escape:value=>value},
  fetch:()=>{throw Error('network forbidden');}});
 vm.runInContext('globalThis.top=globalThis;globalThis.window=globalThis',context);
 const program=vm.runInContext('('+programSource+')',context);
 const call=command=>program(command,native);
 const notify=()=>queueMutation({type:'childList',target:form,addedNodes:[],removedNodes:[]});
 function addCard(name,{placeholder=false,progress=true}={}) {
  const card=form.append(new Node('div',{'data-file-name':name,title:name,'aria-label':name,role:'button'}));
  if(!placeholder){const img=card.append(new Node('img',{alt:name,src:'blob:current-'+name}));img.src=img.currentSrc=img.attrs.src;img.complete=false;img.naturalWidth=0;}
  if(progress)card.append(new Node('div',{role:'progressbar','aria-valuenow':'10'}));
  notify();return card;
 }
 function bind({bytes=png,target=call({action:'captureTarget'}),id=webcrypto.randomUUID()}={}) {
  const identity={operationID:id,assetID:webcrypto.randomUUID(),attempt:1,assetSHA256:sha(bytes),target},invocationID=webcrypto.randomUUID();
  return {identity,target,bytes,name:'riftlet-'+id+'.png',invocationID,command:action=>({action,target,identity,invocationID})};
 }
 function stage(op){call({...op.command('begin'),invocationID:op.invocationID,uploadName:op.name,mediaType:'image/png',byteCount:op.bytes.length});call({...op.command('chunk'),chunkIndex:0,chunkBase64:op.bytes.toString('base64')});}
 const commit=op=>call({...op.command('commit'),chunkIndex:1});
 const observe=op=>call(op.command('observe')).observation;
 const waitFor=async(fn,label='page result')=>{const deadline=Date.now()+2000;do{const value=fn();if(value)return value;await new Promise(r=>setTimeout(r,1));}while(Date.now()<deadline);throw Error('bounded wait expired: '+label);};
 return {call,bind,stage,commit,observe,waitFor,notify,addCard,body,form,editor,input,oldCard,selection,context,document,Node,
  setChange:fn=>{onChange=fn;},setSetter:fn=>{onSet=fn;},setAccept:value=>{accept=value;},
  get changes(){return changes;},get setters(){return setters;},get sends(){return sends;},get chooserOpens(){return chooserOpens;},
  setRoute:href=>{context.location.href=href;},setFocused:value=>{focused=value;}};
}
module.exports={fixture,png,sha,native};
