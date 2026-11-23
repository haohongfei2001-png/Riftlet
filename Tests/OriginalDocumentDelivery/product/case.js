'use strict';
async function runOperationCase(mode, bundle, programSource) {
  const form = document.querySelector('form'), editor = form.querySelector('[contenteditable]');
  const oldCard = form.querySelector('[data-file-name]'), oldImage = oldCard.querySelector('img');
  const draftText = editor.textContent;
  const field = document.createElement('input');
  field.type = 'file'; field.hidden = true;
  const counts = {setter:0,input:0,change:0,send:0};
  const files = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'files');
  Object.defineProperty(HTMLInputElement.prototype,'files',{...files,set(value) {
    counts.setter++; return Reflect.apply(files.set,this,[value]);
  }});
  field.addEventListener('input',()=>counts.input++);
  field.addEventListener('change',()=>counts.change++);
  form.addEventListener('submit',e=>{ e.preventDefault(); counts.send++; });
  form.querySelector('[type=submit]').addEventListener('click',()=>counts.send++);
  let app,portal,parent,otherParent,anchor,originalLineage;
  let returnedToSameLineage = false, actualPortalFocus = false;
  let capturedShadowFocus = false, capturedShadowBlur = false, shadowRetargeted = false;
  if(mode==='menu') {
    app = mountAttachmentEntryCase('noun-menu',form,field);
  } else if (mode==='unlinkedFocusMenu') {
    const counters = {entry:0, menus:0, pickerCalls:0, chooserDefaultAllowed:0};
    app = {counts:counters};
    const entry = document.createElement('button');
    entry.type='button'; entry.setAttribute('data-testid','composer-plus-button');
    entry.setAttribute('aria-label','Add files and photos'); entry.setAttribute('aria-haspopup','menu');
    form.append(entry);
    entry.addEventListener('pointerdown',event=>{
      if(event.button!==0 || counters.entry>0)return;
      counters.entry++;
      const panel=document.createElement('div'), item=document.createElement('button');
      panel.setAttribute('role','menu'); item.setAttribute('role','menuitem');
      item.type='button'; item.textContent='Upload from computer'; panel.append(item);
      document.body.append(panel);
      item.addEventListener('focus',e=>{ actualPortalFocus=e.isTrusted && document.activeElement===item; },{once:true});
      item.focus(); getSelection().removeAllRanges();
      item.addEventListener('click',()=>{
        counters.menus++; panel.append(field); counters.pickerCalls++; field.click();
      });
      field.addEventListener('click',e=>{ if(!e.defaultPrevented)counters.chooserDefaultAllowed++; });
      panel.addEventListener('keydown',e=>{ if(e.key==='Escape')panel.remove(); });
    });
  } else {
    parent = document.createElement('div');
    otherParent = document.createElement('div');
    portal = document.createElement('section');
    anchor = document.createElement('span');
    document.body.append(otherParent);
    form.append(parent); parent.append(portal,anchor); portal.append(field);
    if(mode==='portalABA') {
      originalLineage = [field.parentNode,portal.parentNode,parent.parentNode];
      field.addEventListener('input',()=>{
        otherParent.append(portal);
        if(field.parentNode!==portal || portal.parentNode!==otherParent) throw Error('portal did not move');
        parent.insertBefore(portal,anchor);
        returnedToSameLineage =
          field.parentNode===originalLineage[0] && portal.parentNode===originalLineage[1] &&
          parent.parentNode===originalLineage[2] && portal.nextSibling===anchor;
      },{once:true});
    }
  }
  editor.focus();
  const sel = getSelection(), text = editor.firstChild;
  sel.setBaseAndExtent(text,2,text,7);
  const fixtureHref = 'https://chatgpt.com/?temporary-chat=true';
  // Keep the repository's lexical route fixture at this boundary. No site is contacted.
  const product = new Function('location','return ('+programSource+')')({href:fixtureHref});
  const native = {applicationID:bundle,sessionID:'owned-loopback',windowID:'1',tabID:'1'};
  const call = command => product(command,native);
  const pin = crypto.randomUUID();
  if(call({action:'pinTarget',clickWitnessID:pin,address:'https://chatgpt.com/'})!=='bound')throw Error('pin refused');
  const target=call({action:'captureTarget',clickWitnessID:pin});
  if(target?.clickBindingID!==pin || !target.documentID)throw Error('target not captured');
  const canvas = document.createElement('canvas');
  canvas.width=2; canvas.height=2;
  const base64 = canvas.toDataURL('image/png').split(',')[1];
  const bytes = Uint8Array.from(atob(base64), s=>s.charCodeAt(0));
  const assetSHA256=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),
    n=>n.toString(16).padStart(2,'0')).join('');
  const id=crypto.randomUUID(), invocationID=crypto.randomUUID();
  const identity={operationID:id,assetID:crypto.randomUUID(),assetSHA256,target,attempt:1};
  const command = action=>({action,target,identity,invocationID});
  const begin=call({...command('begin'),uploadName:'riftlet-'+id+'.png',mediaType:'image/png',byteCount:bytes.length});
  const chunk=call({...command('chunk'),chunkIndex:0,chunkBase64:base64});
  if(begin.nextChunk!==0 || chunk.nextChunk!==1)throw Error('stage incomplete');
  let focusRoundTrip = false;
  if(mode==='focusABA' || mode==='closedShadowFocus') {
    const other=document.createElement('textarea');
    let host, shadow;
    if(mode==='closedShadowFocus'){
      host=document.createElement('div'); editor.append(host);
      shadow=host.attachShadow({mode:'closed'}); shadow.append(other);
      other.addEventListener('focus',e=>{ capturedShadowFocus=e.isTrusted && shadow.activeElement===other; },{once:true});
      other.addEventListener('blur',e=>{ capturedShadowBlur=e.isTrusted; },{once:true});
    } else form.after(other);
    const visited=[];
    const witness=event=>{ if(event.isTrusted) visited.push(event.target); };
    document.addEventListener('focusin',witness,true);
    other.focus();
    const atOther=shadow ? document.activeElement===host && shadow.activeElement===other : document.activeElement===other;
    if(shadow) shadowRetargeted=host.shadowRoot===null && visited[0]===host;
    editor.focus();
    focusRoundTrip=atOther && document.activeElement===editor && visited.length===2 &&
      visited[0]===(host || other) && visited[1]===editor && document.hasFocus() && document.visibilityState==='visible';
    document.removeEventListener('focusin',witness,true);
  }
  const validBefore=call({action:'validate',target}).valid;
  const receipt=await call({...command('commit'),chunkIndex:1});
  const observed=call({...command('observe'),requireLiveOriginal:true}).observation.state;
  let repeat='UNEXPECTED_ACCEPT';
  try {await call({...command('commit'),chunkIndex:1});} catch(error) {repeat=error.message;}
  return {mode, counts, state:receipt.observation.state,
    retirement:receipt.observation.preInputRetirement?.reason || null, observed, repeat, validBefore,
    returnedToSameLineage,focusRoundTrip,capturedShadowFocus,capturedShadowBlur,shadowRetargeted,actualPortalFocus,assetSHA256,
    draftPreserved:editor.textContent===draftText && sel.anchorNode===text && sel.focusNode===text && sel.anchorOffset===2 && sel.focusOffset===7,
    priorCardPreserved:form.querySelector('[data-file-name]')===oldCard && oldCard.firstElementChild===oldImage,
    menu:app ? {opened:app.counts.entry,selected:app.counts.menus,invoked:app.counts.pickerCalls,defaultChooserAllowed:app.counts.chooserDefaultAllowed}:null};
}
