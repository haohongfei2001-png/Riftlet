'use strict';
window.qa = (() => {
  const form = document.querySelector('form'), editor = form.querySelector('textarea');
  const prior = form.querySelector('[data-file-name]'), tray = document.querySelector('#tray');
  const holder = document.createElement('section'), field = document.createElement('input');
  field.type = 'file'; field.hidden = true;
  const counts = {setter:0,input:0,change:0,send:0,otherSetter:0,opened:0};
  const filesWritten = [];
  const descriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'files');
  Object.defineProperty(HTMLInputElement.prototype,'files',{...descriptor,set(value) {
    counts.setter++; if(this !== field) counts.otherSetter++;
    const result=Reflect.apply(descriptor.set,this,[value]);
    filesWritten.push(descriptor.get.call(this)[0]);return result;
  }});
  document.addEventListener('input', e=>{if(e.target.type==='file')counts.input++;},true);
  document.addEventListener('change',e=>{if(e.target.type==='file')counts.change++;},true);
  form.addEventListener('submit', e=>{counts.send++;e.preventDefault();});
  const base64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
  const targets = [], presses = [], samples = [], queued = [];
  const timers = new Map();
  let monotonic = 0, wall = 1700000000000;
  const digest=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),x=>x.toString(16).padStart(2,'0')).join('');
  let call, restart, pinCall, mode, opener, result, next = 0;
  function prepare() {
    const pin = crypto.randomUUID();
    if(pinCall({action:'pinTarget',address:'https://chatgpt.com/',clickWitnessID:pin}) !== 'bound') throw Error('pin was not bound');
    const target = call({action:'captureTarget',clickWitnessID:pin});
    if(!target.documentID || !target.composerID || !target.draftGeneration || target.clickBindingID !== pin) throw Error('no complete lease');
    targets.push(target);
    return target.draftGeneration;
  }
  const validate = (target,read=false) => call({action:'validate',target,requireLiveOriginal:read}).valid;
  function renew(target) {
    const reply=restart({action:'renewPreparedTarget',target:structuredClone(target)});
    if(JSON.stringify(reply.target)!==JSON.stringify(target))throw Error('renewal returned another target');
    return reply.valid;
  }
  function mutate() {
    switch(mode) {
    case 'replaceField': case 'invalidReclaim': case 'renewRetired': field.replaceWith(field.cloneNode()); break;
    case 'ancestorRoundTrip': case 'stagedAncestorRoundTrip': {
      const marker = holder.nextSibling;
      document.body.append(holder); form.insertBefore(holder,marker); break;
    }
    case 'modeRoundTrip': form.dataset.composerMode='edit';form.dataset.composerMode='normal';break;
    case 'sameEditorNewDraft': form.dataset.draftId='draft-B'; break;
    case 'replaceOpener': opener.replaceWith(opener.cloneNode(true)); break;
    case 'lateFieldAndOriginalMenu': form.append(field.cloneNode()); break;
    }
  }
  async function activate(target,sample) {
    if (!validate(target)) return {state:'preClickRejected'};
    const operationID = crypto.randomUUID(), invocationID=crypto.randomUUID();
    const identity={target,assetID:crypto.randomUUID(),operationID,assetSHA256:sample.hash,attempt:1};
    const cmd=action=>({action,target,identity,invocationID});
    const begin = call({...cmd('begin'),uploadName:'riftlet-'+operationID+'.png',byteCount:sample.length,mediaType:'image/png'});
    const chunk = call({...cmd('chunk'),chunkIndex:0,chunkBase64:sample.base64});
    if(begin.nextChunk!==0 || chunk.nextChunk!==1) throw Error('stage not acknowledged');
    if(mode==='stagedAncestorRoundTrip') mutate();
    const commit={...cmd('commit'),chunkIndex:1};
    const receipt=await call(commit);
    let repeated='accepted';
    try { await call(commit); } catch(error){repeated=error.message;}
    return {state:receipt.observation.state,reason:receipt.observation.preInputRetirement?.reason || null,
      operationID,invocationID,assetSHA256:sample.hash,repeated,renewAfterBegin:renew(target),releaseAfterBegin:restart({action:'releasePreparedTarget',target:structuredClone(target)}).released};
  }
  tray.addEventListener('mousedown',e=>{
    e.preventDefault();
    if(!e.isTrusted || e.button!==0 || !targets[next]) return;
    presses.push({trusted:e.isTrusted,time:e.timeStamp});
    const target=targets[next],sample=samples[next++];
    if(mode==='queuedPairNoEviction') queued.push(()=>activate(target,sample));
    else result=activate(target,sample);
  });
  return {
    async init(name,source,bundle) {
      mode=name;
      // Identical controlled route convention to the repository's other page-program suites.
      const fixtureLocation={href:'https://chatgpt.com/?temporary-chat=true'};
      const prefix=source.split('\n  // RIFTLET_CLICK_PIN_END\n');
      if(prefix.length!==2) throw Error('missing compact pin boundary');
      const compact=prefix[0].split('\n').map(line=>line.replace(/^ +/, '')).join('\n')+"\n  return 'refused';\n}";
      if(new TextEncoder().encode(compact).length>20480) throw Error('compact pin exceeds 20 KiB');
      const pinProgram=new Function('location','return ('+compact+')')(fixtureLocation);
      function load() {
        if (!['expiredPending','renewSameLease','renewRetired'].includes(name)) return new Function('location','return ('+source+')')(fixtureLocation);
        class FixtureDate extends Date { static now(){return wall;} }
        const schedule=(fn,delay)=>{const id={};timers.set(id,{fn,due:monotonic+delay});return id;};
        return new Function('location','performance','Date','setTimeout','clearTimeout','return ('+source+')')(
          fixtureLocation,{now:()=>monotonic},FixtureDate,schedule,id=>timers.delete(id));
      }
      const program=load();
      const native={applicationID:bundle,sessionID:'owned-fixture',windowID:'1',tabID:'1'};
      call=command=>program(command,native);
      restart=command=>load()(command,native);
      pinCall=command=>pinProgram(command,native);
      const canvas=document.createElement('canvas');canvas.width=2;canvas.height=3;
      const ctx=canvas.getContext('2d');ctx.fillStyle='blue';ctx.fillRect(0,0,2,3);
      for(const png of [base64,canvas.toDataURL('image/png').split(',')[1]]) {
        const bytes=Uint8Array.from(atob(png),s=>s.charCodeAt(0));
        samples.push({base64:png,hash:await digest(bytes),length:bytes.length});
      }
      if(name==='replaceOpener' || name==='lateFieldAndOriginalMenu') {
        opener=document.createElement('button'); opener.type='button';opener.setAttribute('aria-label','Add files');
        opener.setAttribute('data-testid','composer-plus-button');form.append(opener);
        opener.addEventListener('click',()=>{
          counts.opened++;const menu=document.createElement('div');menu.setAttribute('role','menu');
          const item=document.createElement('button');item.type='button';item.setAttribute('role','menuitem');item.textContent='Upload from computer';
          item.addEventListener('click',()=>{menu.append(field);field.click();});
          menu.append(item);document.body.append(menu);
        });
      } else if(name==='ambiguousBeforeACK') {
        holder.append(field,field.cloneNode());form.append(holder);
        for(let i=0;i<2;i++) {
          const button=document.createElement('button');button.type='button';button.setAttribute('aria-label','Attach file');form.append(button);
        }
      } else if(name!=='absentBeforeACK') {holder.append(field);form.append(holder);}
      editor.focus(); editor.setSelectionRange(2,8);
      const box=tray.getBoundingClientRect();
      return {x:box.x+box.width/2,y:box.y+box.height/2,assetSHA256:samples[0].hash};
    }, prepare, mutate, validation(index){return {write:validate(targets[index]),read:validate(targets[index],true)};},
    release(index){return restart({action:'releasePreparedTarget',target:structuredClone(targets[index])}).released;},
    renew(index){return renew(targets[index]);},
    tryPrepare(){try{prepare();return 'accepted';}catch(error){return error.message;}},
    async drain(){const results=[];for(const begin of queued.splice(0))results.push(await begin());return results;},
    advanceClock(monoDelta,wallDelta,runTimers=false){
      monotonic+=monoDelta;wall+=wallDelta;
      let fired=0;
      if(runTimers)for(const [id,timer] of [...timers])if(timer.due<=monotonic){timers.delete(id);timer.fn();fired++;}
      return {monotonic,wallOffset:wall-1700000000000,fired,remainingTimers:timers.size};
    },
    tryBegin(index){
      const target=targets[index],sample=samples[0],operationID=crypto.randomUUID();
      const identity={target,assetID:crypto.randomUUID(),operationID,assetSHA256:sample.hash,attempt:1};
      const command={action:'begin',target,identity,invocationID:crypto.randomUUID(),uploadName:'riftlet-'+operationID+'.png',byteCount:sample.length,mediaType:'image/png'};
      try{call(command);return 'accepted';}catch(error){return error.message;}
    },
    last(){return result;},
    async summary(){
      const deliveredHashes=await Promise.all(filesWritten.map(async file=>digest(await file.arrayBuffer())));
      return {counts:{...counts},presses:[...presses],deliveredHashes,stableDraft:editor.value==='Prior selected draft' &&
      editor.selectionStart===2 && editor.selectionEnd===8 && form.querySelector('[data-file-name]')===prior};}
  };
})();
