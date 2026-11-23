'use strict';
// QA data only. The document and each editor get independent instance IDs.
// An undeleted parent holds pending callables across same-URL iframe reloads.
(() => {
  const instance = crypto.randomUUID(), slots = new Map(), events = [];
  const counts = {text:0,setter:0,input:0,change:0,send:0};
  const originalText = 'alpha beta gamma', oldCard = document.querySelector('#prior');
  let currentEditor = document.querySelector('#original');
  currentEditor.dataset.instance = crypto.randomUUID();
  currentEditor.value = originalText;
  currentEditor.setSelectionRange(6,10,'forward');
  function record(event) { events.push({type:event.type,trusted:event.isTrusted,persisted:event.persisted}); }
  addEventListener('pageshow',record); addEventListener('pagehide',record);
  document.addEventListener('visibilitychange',record);
  if(window.navigation) navigation.addEventListener('currententrychange',record);
  document.addEventListener('input', e => { if(e.target.type === 'file') counts.input++; },true);
  document.addEventListener('change', e => { if(e.target.type === 'file') counts.change++; },true);
  document.addEventListener('submit',e => { counts.send++; e.preventDefault(); },true);
  const files = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'files');
  // Actual native methods perform the mutations. Count every attempt on this
  // document's instrumented prototype, including calls from detached nodes.
  Object.defineProperty(HTMLInputElement.prototype,'files',{...files,set(value) {
    counts.setter++; return files.set.call(this,value);
  }});
  const setFiles = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'files').set;
  function insert(text) { counts.text++; this.setRangeText(text,0,0,'preserve'); }
  function state() {
    return {instance,editor:currentEditor.dataset.instance,text:currentEditor.value,
      range:[currentEditor.selectionStart,currentEditor.selectionEnd,currentEditor.selectionDirection],
      priorPreserved:oldCard===document.querySelector('#prior') && oldCard.isConnected,
      files:Array.from(files.get.call(document.querySelector('#upload')),f=>({name:f.name,size:f.size})),
      active:document.hasFocus(),visible:document.visibilityState,events:[...events],counts:{...counts},url:location.href};
  }
  function stage(id) {
    const editor=currentEditor, input=document.querySelector('#upload');
    const pageAuth = {allow:true};
    const permits = () => {
      const pending=pageAuth.duringPermit;
      pageAuth.duringPermit=null;
      if(pending) pending();
      return pageAuth.allow;
    };
    const textLease = window.bindOriginalReceiver(editor,permits,true);
    const draftForFile = window.bindOriginalReceiver(editor,permits,true);
    const fileLease = window.bindOriginalReceiver(input,() => permits() && draftForFile.current());
    const text = textLease.once(insert);
    const set = fileLease.once(setFiles);
    const sendInput = fileLease.once(EventTarget.prototype.dispatchEvent);
    const sendChange = fileLease.once(EventTarget.prototype.dispatchEvent);
    const image = Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='),c=>c.charCodeAt(0));
    const transfer = new DataTransfer();
    transfer.items.add(new File([image],id+'.png',{type:'image/png'}));
    const pending = {
      instance, editor:editor.dataset.instance,
      current:() => [textLease.current(),fileLease.current()],
      text:() => text(id),
      png:() => {
        const setter = set(transfer.files);
        if (!setter) return {setter,input:false,change:false};
        const input = sendInput(new Event('input',{bubbles:true}));
        const change = sendChange(new Event('change',{bubbles:true}));
        return {setter,input,change};
      },
      close:() => { textLease.close();fileLease.close();draftForFile.close(); },
      oldReceipt:() => ({instance,counts:{...counts},text:editor.value}),
      state,revoke:() => {pageAuth.allow=false;},duringPermit:fn => {pageAuth.duringPermit=fn;},
    };
    slots.set(id,pending);
    return pending;
  }
  function mutate(mode) {
    if(mode==='replaceEditor') {
      const old=currentEditor;
      currentEditor=old.cloneNode(true); currentEditor.dataset.instance=crypto.randomUUID();
      old.replaceWith(currentEditor);
    } else if(mode==='moveReturn') {
      const outer=document.querySelector('#draft'), original=outer.parentElement, next=outer.nextSibling;
      document.querySelector('#parking').appendChild(outer); original.insertBefore(outer,next);
    } else if(mode==='focusABA') {
      const other=document.querySelector('#other');
      other.focus(); if(document.activeElement!==other) throw Error('alternate editor was not focused');
      currentEditor.focus(); if(document.activeElement!==currentEditor) throw Error('focus did not return');
    } else if(mode==='focusFrameABA') {
      const frame=document.querySelector('#focusframe');
      const inside=frame.contentDocument.querySelector('textarea');inside.focus();
      if(document.activeElement!==frame||frame.contentDocument.activeElement!==inside) throw Error('iframe editor was not focused');
      currentEditor.focus();if(document.activeElement!==currentEditor) throw Error('focus did not return from iframe');
    } else if(mode==='historyABA') {
      history.pushState({},'',location.pathname+'?second');history.replaceState({},'',location.pathname);
    } else if(mode==='hash') location.hash='changed';
    else throw Error('unknown mutation');
  }
  window.qa = {
    state,focus:() => {currentEditor.focus();return state();},
    stage:id => {const p=stage(id);return {instance:p.instance,editor:p.editor,current:p.current()};},
    // open-only Web API objects stay inside this owned test page.
    hold:stage,
    deliver:id => {
      const p=slots.get(id), png=p.png(), afterPNG=state(), text=p.text();
      return {current:p.current(),png,afterPNG,text,state:state()};
    },
    fileHash:async () => {
      const nativeFile=files.get.call(document.querySelector('#upload'))[0];
      if(!nativeFile) return null;
      const bytes=await crypto.subtle.digest('SHA-256',await nativeFile.arrayBuffer());
      return Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,'0')).join('');
    },
    interleave:(first,second) => {
      const oldEditor=slots.get(first).editor;
      mutate('replaceEditor');currentEditor.focus();const fresh=stage(second);
      const old=window.qa.deliver(first), delivered=window.qa.deliver(second);
      return {oldEditor,freshEditor:fresh.editor,old,fresh:delivered,oldAgain:window.qa.deliver(first)};
    },
    reentrant:id => {
      let fired=0;
      slots.get(id).duringPermit(() => {fired++;mutate('moveReturn');});
      const delivery=window.qa.deliver(id);
      return {fired,delivery};
    },
    mutateAndDeliver:(mode,id) => {mutate(mode);return window.qa.deliver(id);},
    close:id => {slots.get(id).close();},revoke:id => {slots.get(id).revoke();},
    navigateBack:() => {history.back();},
    pushEntry:() => {
      if(!window.navigation) throw Error('Navigation API unavailable');
      const original=navigation.currentEntry.key; history.pushState({},'',location.pathname+'?new');
      return {original,changed:navigation.currentEntry.key};
    },
    entry:() => navigation.currentEntry.key,
    replaceFrame:async variant => {
      const frame=document.createElement('iframe');
      const loaded=() => new Promise((ok,fail)=>{frame.addEventListener('load',ok,{once:true});frame.addEventListener('error',fail,{once:true});});
      const firstLoad=loaded();frame.src='./frame';document.body.appendChild(frame);await firstLoad;
      frame.contentWindow.qa.focus();
      const a=frame.contentWindow.qa.hold('old'), before=a.state();
      const secondLoad=loaded();
      if(variant==='reload') frame.contentWindow.location.reload(); else frame.src=frame.src;
      await secondLoad;frame.contentWindow.qa.focus();
      const b=frame.contentWindow.qa.hold('fresh'), current=b.state();
      const old = {png:a.png(),text:a.text(),current:a.current()};
      const result = {before,current,old,afterOldA:a.oldReceipt(),afterOldB:b.state(),newCurrent:b.current()};
      result.fresh = {png:b.png(),text:b.text(),after:b.state()};
      return result;
    }
  };
})();
