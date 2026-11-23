'use strict';

// A site-owned fixture. It receives the picker events and draws the redacted
// original error tile; the production resource performs all input/observation.
async function runOriginalErrorCardCase({form,editor,input,operation,call,check,options,counts}) {
  const el=(tag,cls)=>{const node=document.createElement(tag);if(cls)node.className=cls;return node;};
  const style=el('style');style.textContent='.pointer-events-none{pointer-events:none}';document.head.append(style);
  const layout=el('div');layout.setAttribute('data-composer-layout','');
  const lane=el('div','ComposerLayoutAttachments-test'),row=el('div','flex');
  form.append(layout);layout.append(editor,lane);lane.append(row);
  const makeTile=name=>{
    const shell=el('span','group/composer-attachment'),surface=el('span','composer-attachment-surface');
    shell.style.display=surface.style.display='inline-block';
    const remove=el('button');remove.type='button';remove.setAttribute('aria-label','移除 '+name);
    remove.textContent='×';remove.style.cssText='opacity:0;pointer-events:none';
    shell.append(surface,remove);
    const preview=el('span','pointer-events-none'),status=el('span'),alert=el('span'),message=el('span'),retry=el('button');
    alert.setAttribute('role','alert');alert.setAttribute('aria-label',name);message.textContent='上传未成功';
    retry.type='button';retry.textContent='Retry';retry.setAttribute('aria-label','Retry uploading '+name);
    const bar=el('span'),filename=el('span','truncate');filename.textContent=name;
    status.append(alert,retry);alert.append(message);preview.append(status);bar.append(filename);surface.append(preview,bar);
    const ring=el('span','composer-attachment-surface pointer-events-none absolute inset-0 rounded-2xl ring-1 ring-inset ring-border');
    surface.append(ring);
    return {shell,surface,remove,preview,status,alert,message,retry,bar,filename,ring};
  };
  let inputs=0;input.addEventListener('input',()=>inputs++);
  const observe=(op,manual=false)=>call({...op.command('observe'),requireLiveOriginal:manual}).observation;
  const commit=op=>call({...op.command('commit'),chunkIndex:op.chunks});
  let index=0;
  // Each case is an independent fresh click and native input. Never use a
  // second commit to inspect the result of an uncertain input.
  async function begin(setup,attempt=1) {
    const op=await operation(index++,null,false,attempt),tile=makeTile(op.name);
    const install=setup(tile,op);
    input.addEventListener('change',()=>install?.(),{once:true});
    return {op,tile,item:(await commit(op)).observation};
  }
  // Without an enrolled PNG, a pending preparation must never carry a draft
  // generation across focus loss. Releasing all preparations also ends it.
  const pinOnly=await operation(0,null,true);
  window.dispatchEvent(new Event('blur'));
  const freshPin=await operation(0,null,true);
  check(pinOnly.target.draftGeneration!==freshPin.target.draftGeneration,'pending pin alone cannot retain epoch through blur');
  for(const pending of [pinOnly,freshPin])call({action:'releasePreparedTarget',target:pending.target});
  const afterRelease=await operation(0,null,true);
  check(freshPin.target.draftGeneration!==afterRelease.target.draftGeneration,'all pending preparations released');
  call({action:'releasePreparedTarget',target:afterRelease.target});

  // Run the real enrolled-pin expiry callbacks using the deterministic fixture
  // clock boundary. The original binding must be absent before another capture.
  const timeout=window.setTimeout, expiry=[];
  window.setTimeout=function(fn,ms,...args){
    const timer=timeout(fn,ms,...args);
    if(ms===600000)expiry.push(()=>{clearTimeout(timer);fn(...args);});
    return timer;
  };
  let expired;
  try {
    expired=await begin(t=>()=>{t.surface.replaceChildren(el('progress'));row.append(t.shell);});
  } finally {window.setTimeout=timeout;}
  expired.tile.shell.remove();
  check(expiry.length>0,'enrolled expiry was scheduled');
  for(const run of expiry)run();
  check(!call({action:'validate',target:expired.op.target,requireLiveOriginal:true}).valid,'expired original reader retired');
  const afterExpiry=await operation(0,null,true);
  check(afterExpiry.target.draftGeneration!==expired.op.target.draftGeneration,'expired source cannot restore draft epoch');
  call({action:'releasePreparedTarget',target:afterExpiry.target});
  const noPositive=(obs,label)=>check(!obs.uploadStart && !obs.hasError && !obs.originalCardFailureInvocationID &&
      !obs.safeToRetry && obs.state!=='originalCardFailed',label);
  const failures={
    explicitPointerBlock:t=>()=>{t.retry.style.pointerEvents='none';row.append(t.shell);},
    noKeyboardAction:t=>()=>{t.retry.tabIndex=-1;row.append(t.shell);},
    ringText:t=>()=>{t.ring.textContent='Retry';row.append(t.shell);},
    ringButton:t=>()=>{t.ring.append(el('button'));row.append(t.shell);},
    ringLabel:t=>()=>{t.ring.setAttribute('aria-label','Other');row.append(t.shell);},
    ringDuplicate:t=>()=>{t.surface.append(t.ring.cloneNode(true));row.append(t.shell);},
    ringOrder:t=>()=>{t.surface.prepend(t.ring);row.append(t.shell);},
    ringUnrelated:t=>()=>{t.ring.classList.remove('ring-inset');row.append(t.shell);},
    oldShell:t=>{row.append(t.shell);return ()=>{};},
    oldRemove:t=>{row.append(t.remove);return ()=>{t.shell.append(t.remove);row.append(t.shell);};},
    conflict:t=>()=>{const label=el('span');label.textContent='riftlet-'+crypto.randomUUID()+'.png';t.bar.append(label);row.append(t.shell);},
    wrongName:t=>()=>{t.filename.textContent='neighbor.png';row.append(t.shell);},
    neighboring:t=>()=>{row.append(t.shell,t.retry);},
    nested:t=>()=>{const outer=makeTile('neighbor.png');row.append(outer.shell);outer.surface.append(t.shell);},
    hidden:t=>()=>{t.alert.hidden=true;row.append(t.shell);},
    disabled:t=>()=>{t.retry.disabled=true;row.append(t.shell);},
    hiddenRetry:t=>()=>{t.retry.style.opacity='0';row.append(t.shell);},
    repeated:t=>()=>{row.append(t.shell,t.shell.cloneNode(true));},
    duplicateRemove:t=>()=>{row.append(t.shell,t.remove.cloneNode(true));},
    neighboringNamedPreview:(t,op)=>()=>{const other=el('div');other.dataset.fileName=op.name;row.append(t.shell,other);},
    duplicateRetry:t=>()=>{row.append(t.shell,t.retry.cloneNode(true));},
    withImage:t=>()=>{t.preview.append(el('img'));row.append(t.shell);},
    foreignDraft:t=>()=>{const other=el('form'),body=el('div'),otherLane=lane.cloneNode(false),otherRow=row.cloneNode(false);
      body.setAttribute('data-composer-layout','');otherRow.append(t.shell);otherLane.append(otherRow);body.append(otherLane);other.append(body);document.body.append(other);},
  };
  for(const [reason,prepare] of Object.entries(failures)) {
    const {op,item}=await begin(prepare);noPositive(item,reason);noPositive(observe(op,true),reason+' reread');
    row.replaceChildren();
  }
  const accept=(obs,op)=>check(obs.state==='originalCardFailed' && obs.exactImageIdentity && obs.hasError &&
    obs.belongsToOriginalDraft && !obs.inputExecutionPending && !obs.uploadStart && !obs.safeToRetry && !!obs.attachmentID &&
    obs.originalCardFailureInvocationID===op.command('observe').invocationID,'original explicit failure: '+obs.state);
  const noBorder=await begin(t=>()=>{t.ring.remove();row.append(t.shell);});
  accept(noBorder.item,noBorder.op);row.replaceChildren();
  for(const mutation of ['reparent','rename','replace','renderSuccess']) {
    const {op,tile,item}=await begin(t=>()=>row.append(t.shell));accept(item,op);
    const reread=observe(op,true);accept(reread,op);check(item.attachmentID===reread.attachmentID,'same original member');
    const wrong=call({...op.command('observe'),requireLiveOriginal:true,invocationID:crypto.randomUUID()}).observation;
    check(wrong.state==='invalidated','wrong invocation');
    if(mutation==='reparent'){tile.shell.remove();row.append(tile.shell);}
    if(mutation==='rename'){const key=tile.remove.getAttribute('aria-label');tile.remove.setAttribute('aria-label','Remove neighbor.png');tile.remove.setAttribute('aria-label',key);}
    if(mutation==='replace'){tile.shell.replaceWith(tile.shell.cloneNode(true));}
    if(mutation==='renderSuccess'){
      const card=el('button'),image=el('img');card.dataset.fileName=op.name;image.alt=op.name;
      image.src=URL.createObjectURL(input.files[0]);card.append(image);tile.surface.replaceChildren(card);
    }
    const unavailable=observe(op,true);check(unavailable.state==='invalidated',mutation+' original unavailable');
    noPositive(observe(op),mutation);row.replaceChildren();
  }
  for(const scenario of ['sameShell','replacedShell','oldShell']) {
    let image, errorContents;
    const {op,tile}=await begin((t,op)=>{
      errorContents=[...t.surface.children];t.surface.replaceChildren();
      if(scenario==='oldShell')row.append(t.shell);
      return ()=>{
        image=el('img');image.alt=op.name;image.width=image.height=16;
        image.src=URL.createObjectURL(input.files[0]);t.surface.append(image);row.append(t.shell);
      };
    });
    await image.decode();
    const start=observe(op);
    if(scenario==='oldShell'){noPositive(start,'existing shell with new positive image');row.replaceChildren();continue;}
    check(!!start.uploadStart && !!start.attachmentID, 'original strong positive start '+scenario+' '+start.state);
    if(scenario==='sameShell')tile.surface.replaceChildren(...errorContents);
    else tile.shell.replaceWith(makeTile(op.name).shell);
    const result=observe(op,true);
    if(scenario==='sameShell')check(result.state==='failed' && result.attachmentID===start.attachmentID && !result.originalCardFailureInvocationID,'only same accepted shell can fail');
    else check(result.state!=='failed' && result.state!=='originalCardFailed','replacement cannot claim historical start');
    row.replaceChildren();
  }
  // Keep an independently identified neighbour throughout every recovery case.
  const neighbour=form.querySelector('[data-file-name="existing.png"]');
  row.append(neighbour);
  let recoveryInputs=0;
  const initialIndex=index;
  for(const mode of ['still-present','gone','no-witness','late-card','ambiguous-new','wrong-source','prior-replaced','prior-relabeled','converted-competitor','unknown-progress','explicit-error','after-start-error','after-start-gone','attempt-order','mode-aba','editor-aba','replace-editor','navigation-aba']) {
    const originalIndex=index;
    let image, errorContents;
    const {op:old,tile,item}=await begin((tile,op)=>()=>{
      if(mode.startsWith('after-start')){
        errorContents=[...tile.surface.children];
        image=el('img');image.alt=op.name;image.width=image.height=16;
        image.src=URL.createObjectURL(input.files[0]);tile.surface.replaceChildren(image);row.append(tile.shell);return;
      }
      if(mode==='no-witness')return;
      if(mode!=='explicit-error')tile.surface.replaceChildren(el('progress'));
      row.append(tile.shell);
    },mode==='attempt-order'?5:1);
    const source={identity:old.identity,invocationID:old.command('observe').invocationID};
    if(mode.startsWith('after-start')){
      await image.decode();const start=observe(old);
      check(!!start.uploadStart,'positive original start');source.startEvidenceID=start.uploadStart.evidenceID;
      if(mode==='after-start-error'){
        tile.surface.replaceChildren(...errorContents);const error=observe(old,true);
        check(error.hasError && error.attachmentID===start.attachmentID,'exact original failed after start');
        source.failureAttachmentID=error.attachmentID;
      } else tile.shell.remove();
    } else if(mode==='explicit-error'){
      accept(item,old);source.failureAttachmentID=item.attachmentID;
    } else if(mode!=='still-present')tile.shell.remove();
    if(mode==='wrong-source')source.invocationID=crypto.randomUUID();
    if(mode==='ambiguous-new')row.append(el('div'));
    if(mode==='prior-replaced')neighbour.replaceWith(neighbour.cloneNode(true));
    if(mode==='prior-relabeled'){neighbour.setAttribute('data-file-name','new.png');neighbour.setAttribute('data-file-name','existing.png');}
    let outside;
    if(mode==='converted-competitor'){outside=el('img');outside.alt=old.name.replace(/\.png$/i,'.webp');document.body.append(outside);}
    if(mode==='unknown-progress'){outside=el('progress');form.append(outside);}
    if(mode==='attempt-order'){
      for(const attempt of [old.identity.attempt,old.identity.attempt-1]){
        const invalid=await operation(originalIndex,source,true,attempt);
        let rejected=false;try{invalid.stage();}catch{rejected=true;}
        check(rejected,'equal or reverse attempt rejected before staging');
        call({action:'releasePreparedTarget',target:invalid.target});
      }
    }
    let replacement;
    const invalidDraft=['mode-aba','editor-aba','replace-editor','navigation-aba'].includes(mode);
    if(invalidDraft){
      window.dispatchEvent(new Event('blur'));
      if(mode==='mode-aba'){
        const key='data-composer-mode', original=form.getAttribute(key);
        form.setAttribute(key,'another-draft');
        if(original===null)form.removeAttribute(key);else form.setAttribute(key,original);
      }
      if(mode==='editor-aba' || mode==='replace-editor'){
        replacement=editor.cloneNode(true);editor.replaceWith(replacement);
        if(mode==='editor-aba')replacement.replaceWith(editor);
      }
      if(mode==='navigation-aba'){
        const entry=navigation.currentEntry.id;
        history.pushState(null,'','#different-draft');
        check(navigation.currentEntry.id!==entry,'navigation changed actual browser entry');
        const restored=new Promise(done=>window.addEventListener('popstate',done,{once:true}));
        history.back();await restored;
        check(navigation.currentEntry.id===entry,'actual navigation returned to original entry');
      }
    }
    const returnsFromHistory=['gone','explicit-error','after-start-gone','after-start-error'].includes(mode);
    if(returnsFromHistory) {
      const stale=await operation(originalIndex,source,true);
      const before=counts().setters;
      let lostFocus=false, regainedFocus=false;
      const blur=e=>{lostFocus=e.isTrusted;}, focus=e=>{regainedFocus=e.isTrusted;};
      window.addEventListener('blur',blur,{once:true});
      window.addEventListener('focus',focus,{once:true});
      const history=window.open('/other-draft','_blank');
      check(!!history,'controlled second window opened');
      const until=async f=>{for(let i=0;i<100;i++){if(f())return;await new Promise(done=>setTimeout(done,20));}
        throw Error('controlled focus transition timed out');};
      history.focus();
      try {
        await until(()=>lostFocus && !document.hasFocus());
        check(!call({action:'validate',target:stale.target}).valid,'history permanently retired old write');
      } finally {history.close();window.focus();}
      await until(()=>regainedFocus && document.hasFocus() && document.visibilityState==='visible');
      check(!call({action:'validate',target:stale.target}).valid,'return to draft cannot revive old write');
      let staleRejected=false;try{stale.stage();}catch{staleRejected=true;}
      check(staleRejected,'old pin cannot stage a new input after History return');
      call({action:'releasePreparedTarget',target:stale.target});
      check(counts().setters===before,'focus round trip made no input');
    }
    const next=await operation(originalIndex,source,true);
    if(returnsFromHistory){
      check(next.target.documentID===old.target.documentID && next.target.composerID===old.target.composerID &&
        next.target.draftGeneration===old.target.draftGeneration,'History return lost the continuously observed original draft epoch');
      check(next.target.clickBindingID!==old.target.clickBindingID,'History return requires new write pin');
    }
    if(invalidDraft)check(next.target.draftGeneration!==old.target.draftGeneration,mode+' retired original epoch');
    const checkSource=value=>call({action:'validate',target:next.target,recoverySource:value});
    check(!checkSource({...source,invocationID:crypto.randomUUID()}).valid,'wrong persisted invocation');
    check(!checkSource({...source,identity:{...source.identity,assetSHA256:'0'.repeat(64)}}).valid,'wrong original hash');
    check(!checkSource({...source,identity:{...source.identity,target:{...source.identity.target,draftGeneration:crypto.randomUUID()}}}).valid,
      'different original epoch at same URL');
    const allowed=['gone','late-card','explicit-error','after-start-error','after-start-gone','attempt-order'].includes(mode);
    if(source.startEvidenceID)check(!checkSource({...source,startEvidenceID:crypto.randomUUID()}).valid,'wrong original START');
    const decision=checkSource(source);
    check(decision.recoveryChecked && decision.valid===allowed,'explicit recovery decision '+mode);
    if(allowed) {
      next.stage();
      if(mode==='late-card')row.append(tile.shell);
      const after=(await commit(next)).observation;
      if(mode==='late-card'){
        check(after.preInputRetirement?.inputCount===0,'returning original blocked at setter');
        tile.shell.remove();
        const third=await operation(originalIndex,source,true,next.identity.attempt+1);
        check(old.identity.attempt===1 && next.identity.attempt===2 && third.identity.attempt===3,
          'retired attempt remains in the immutable history');
        check(third.target.clickBindingID!==next.target.clickBindingID &&
          third.command('observe').invocationID!==next.command('observe').invocationID,'new click and invocation');
        check(call({action:'validate',target:third.target,recoverySource:source}).valid,'fresh selection rechecks original');
        third.stage();
        check((await commit(third)).observation.state==='inputTriggered','higher attempt enters original input once');
        recoveryInputs++;
      }
      else {recoveryInputs++;check(after.state==='inputTriggered','eligible replacement actually entered input');}
    } else {
      let refused=false;try{next.stage();}catch{refused=true;}
      check(refused,'new begin refused '+mode);
    }
    if(replacement?.isConnected)replacement.replaceWith(editor);
    outside?.remove();row.replaceChildren(neighbour);
    // Unconsumed pins are owned by this isolated fixture.
    call({action:'releasePreparedTarget',target:next.target});
  }
  check(index-initialIndex===18 && recoveryInputs===6,'recovery cases and explicitly authorized new inputs');
  check(inputs===index+recoveryInputs && counts().setters===inputs && counts().changes===inputs && counts().sends===0,'exactly one input per case; no send');
  return {passed:true,rejectedShapes:Object.keys(failures).length,retiredCases:4,historyRoundTrips:4,draftChangeRefusals:4,pendingReleaseAndExpiryChecked:true,nativeSetters:counts().setters,nativeChanges:inputs,automaticSends:counts().sends};
}
module.exports={runOriginalErrorCardCase};
