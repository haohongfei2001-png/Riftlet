(ref,action,plan,rows)=>{
"use strict";
const f=ref.f,e=ref.e;
const bound=()=>ref.document===document && ref.n===navigation.currentEntry?.id && e.isConnected &&
 e.closest("form")===f && e.textContent==="Riftlet PR 69 fresh pair 619 and 620. Preserve this text and selected words. Keep this dedicated draft unsent." &&
 ref.interactions()===0 && location.href==="https://chatgpt.com/?temporary-chat=true";
if(!bound())return {status:"STOP",reason:"originalDraftChanged"};
const key=Symbol.for("riftlet.qa.private.bound.v26.shortProgress."+plan.ticket);
const known=globalThis[key];
if(action==="arm"){
 if(known)return {status:"STOP",reason:"alreadyObserved"};
 const ids=new WeakMap(), records={}, cards=new Map(),start=performance.now();let seq=0,expired=false,scans=0;
 const legal=["true","false","uploading","processing","upload","complete","completed","ready","file_ready","failed","error","loading","pending","succeeded"];
 const elapsed=()=>Math.round((performance.now()-start)*10)/10;
 const nodeid=n=>{if(!ids.has(n))ids.set(n,++seq);return ids.get(n);};
 const attrs=["alt","data-file-name","aria-label","title"];
 const textName=(a,n)=>{if(!a || a.length>300)return false;const i=a.indexOf(n);return i>=0&&(!i||!/[-.\w]/.test(a[i-1]))&&(i+n.length===a.length||!/[-.\w]/.test(a[i+n.length]));};
 const hasName=(el,name)=>attrs.some(k=>textName(el.getAttribute(k),name)) || (!el.children.length && el.textContent.trim()===name);
 function nodeList(card){return [card,...card.querySelectorAll("*")];}
 function record(seed,field,value){
   const row=records[seed];
   const recent=row.last[field];
   if(recent===value)return;
   row.last[field]=value;
   if(row.events.length<80)row.events.push([elapsed(),field,value]);else row.truncated=true;
 }
 function inspect(seed,name){
   const r=records[seed];
   const safe=n=>!e.contains(n) && !n.closest("aside,header,nav,article,[data-message-author-role],[contenteditable],textarea");
   const names=[...f.querySelectorAll("[alt],[data-file-name],[aria-label],[title],span")].filter(safe);
   if(names.length>220)return;
   const matches=names.filter(n=>hasName(n,name));if(!matches.length){if(r.seen)record(seed,"cardPresent",false);return;}
   let box=matches[0];while(box && box!==f && !matches.every(n=>box.contains(n)))box=box.parentElement;
   if(box && box.tagName==="IMG")box=box.parentElement;
   const hostOK=n=>{
     if(!n||n===f||n.contains(e)||!f.contains(n))return false;
     const inside=nodeList(n);
     return inside.length<=130 && !inside.some(m=>plan.baseline.some(k=>hasName(m,k))||
       Object.values(records).some(o=>o.name!==name && hasName(m,o.name)));
   };
   if(!hostOK(box))return;
   const parent=box.parentElement;
   if(hostOK(parent) && nodeList(parent).some(n=>n.matches("button,[role=button]")&&attrs.some(k=>{const v=n.getAttribute(k);return textName(v,name)&&/remove|移除|删除/i.test(v);})))box=parent;
   if(!hostOK(box))return;
   r.seen=true;cards.set(seed,box);record(seed,"cardPresent",true);
   const ns=nodeList(box), shapeTag=n=>(n?.tagName||'').toUpperCase().slice(0,15);
   const img=ns.find(n=>n.tagName==='IMG'&&hasName(n,name))||ns.find(n=>n.tagName==='IMG');
   const bar=ns.find(n=>n.matches('[role=progressbar],progress'));
   const remove=ns.find(n=>n.matches('button,[role=button]')&&attrs.some(k=>{const v=n.getAttribute(k);return textName(v,name)&&/remove|移除|删除/i.test(v);}));
   const projection=JSON.stringify({root:shapeTag(box),stableRoot:nodeid(box),stableRemove:remove?nodeid(remove):null,stableRemoveParent:remove?.parentElement?nodeid(remove.parentElement):null,stableImage:img?nodeid(img):null,stableBar:bar?nodeid(bar):null,names:matches.slice(0,5).map(n=>[shapeTag(n),attrs.filter(k=>textName(n.getAttribute(k),name))]),
     img:shapeTag(img),bar:shapeTag(bar),barRole:bar?.matches('[role=progressbar]')||false,imgAndBarSiblings:!!img&&!!bar&&img.parentElement===bar.parentElement,
     imageContainsBar:!!img&&!!bar&&img.contains(bar),barContainsImage:!!img&&!!bar&&bar.contains(img),
     imgParent:shapeTag(img?.parentElement),barParent:shapeTag(bar?.parentElement),removeParent:shapeTag(remove?.parentElement),
     removeParentChildCount:remove?.parentElement?.childElementCount??null,rootChildren:box.childElementCount});
   record(seed,"neutralCardShape",projection);

   const all=nodeList(box);
   const sem=all.filter(n=>n.matches("progress,[role=progressbar],[role=status],[role=alert],[aria-busy],[data-status],[data-state],[data-upload-status]"));
   const roles=sem.map(n=>{const label=n.getAttribute("role")||n.tagName.toLowerCase();return (["progress","progressbar","status","alert"].includes(label)?label:"semantic")+"#"+nodeid(n);}).sort();
   record(seed,"controls",roles.join(","));
   const svg=all.filter(n=>n.namespaceURI==="http://www.w3.org/2000/svg" && n.localName==="svg");
   record(seed,"svgCount",svg.length);record(seed,"svgProgressRole",svg.some(n=>n.getAttribute("role")==="progressbar"));
   for(const n of sem){
     const id=nodeid(n);
     for(const k of ["aria-busy","data-state","data-upload-status","data-status"]){
       const v=(n.getAttribute(k)||"").toLowerCase();if(legal.includes(v))record(seed,k+"#"+id,v);
     }
     if(n.matches("progress,[role=progressbar]")){
       const attr=n.localName==="progress"?"value":"aria-valuenow";const value=n.getAttribute(attr);
       const numeric=(value!==null&&/^(?:0|[1-9]\d{0,4})(?:\.\d{1,5})?$/.test(value))?Number(value):null;
       record(seed,"numeric#"+id,numeric);
     }
   }
 }
 function sample(){if(expired||!bound()){observer.disconnect();return;}
   if(++scans>2200){observer.disconnect();expired=true;return;}
   for(const [s,r] of Object.entries(records))inspect(s,r.name);
 }
 const observer=new MutationObserver(sample);
 observer.observe(f,{subtree:true,childList:true,attributes:true,attributeFilter:["alt","aria-label","title","data-file-name","role","aria-busy","aria-valuenow","data-status","data-state","data-upload-status","value"]});
 const finish=()=>{sample();observer.disconnect();expired=true;};
 const config={add:rs=>{for(const [seed,name] of rs){if(!plan.seeds.includes(seed)||!/^riftlet-[A-F0-9]{8}(?:-[A-F0-9]{4}){3}-[A-F0-9]{12}\.png$/.test(name)||plan.baseline.includes(name))throw Error("unknownAsset");
     if(records[seed]){if(records[seed].name!==name)throw Error("differentOperation");continue;}
     if(Object.values(records).some(v=>v.name===name))throw Error("duplicateOperation");
     records[seed]={name,addedAt:elapsed(),last:{},events:[],seen:false,truncated:false};}sample();},
   result:()=>Object.entries(records).map(([seed,r])=>({seed:Number(seed),boundAtMs:r.addedAt,seen:r.seen,events:r.events,truncated:r.truncated})),finish};
 Object.defineProperty(globalThis,key,{value:config,configurable:true});
 setTimeout(finish,105000);setTimeout(()=>{if(globalThis[key]===config)delete globalThis[key];},160000);
 return {status:"ARMED",semanticInput:0};
}
if(!known)return {status:"STOP",reason:"observerExpiredOrChanged"};
if(action==="bind"){known.add(rows);return {status:"BOUND",count:rows.length};}
if(action==="close"){known.finish();const data=known.result();delete globalThis[key];return {status:"OBSERVED",files:data};}
return {status:"STOP",reason:"unknownAction"};
}
