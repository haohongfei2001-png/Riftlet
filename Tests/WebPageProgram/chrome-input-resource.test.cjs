'use strict';
// Real native Chrome File/FileList/DataTransfer/Selection; controlled app only.
// Isolated profile, loopback traffic, no real ChatGPT, CDP or Apple Events.
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const http=require('node:http');
const {spawn}=require('node:child_process');
const {mountAttachmentEntryCase,readResidentV15Source}=require('./attachment-entry-application.cjs');
const {bounded,cleanupOwnedChrome,closeLoopbackServer}=require('./native-chrome-cleanup.cjs');
require('./native-chrome-cleanup.test.cjs');
const binary=[process.env.RIFTLET_CHROME_BIN,
 '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
 '/usr/bin/google-chrome','/usr/bin/chromium','/usr/bin/chromium-browser'].find(p=>p&&fs.existsSync(p));
const required=process.env.RIFTLET_REQUIRE_CHROME==='1';
const sourcePath=process.env.RIFTLET_WEB_SOURCE_OVERRIDE||process.env.SOURCE_OVERRIDE||path.join(__dirname,'../../Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js');
const source=fs.readFileSync(sourcePath,'utf8');
function browserFixture(options){
 const previous=options.resident?readResidentV15Source():'';
 const container=options.noForm?'section':'form';
 return String.raw`<!doctype html><meta charset="utf-8"><title>Riftlet independent native input regression</title>
<${container} data-harness-composer><div id="prompt-textarea" contenteditable="true" role="textbox" style="width:500px;height:80px">Existing 中文 draft 👋 and selection</div><input type="file" accept="image/*" style="display:none"><div role="button" data-file-name="existing.png"><img alt="existing.png"></div><button type="submit">Send</button></${container}><pre id="result">RUNNING</pre>
<script>
(async()=>{
 const options=__OPTIONS__,report={scope:'real Chrome primitives; controlled local application; NOT live ChatGPT',passed:false};
 const harnessFetch=globalThis.fetch.bind(globalThis);
 const stage=async phase=>{report.phase=phase;await harnessFetch('/progress',{method:'POST',body:JSON.stringify({phase})});};
 const check=(ok,label)=>{if(!ok)throw Error(label);};
 const wait=async fn=>{for(let i=0;i<300;i++){if(fn())return;await new Promise(r=>setTimeout(r,10));}throw Error('bounded observation wait expired');};
 const hash=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),n=>n.toString(16).padStart(2,'0')).join('');
 try{
  check(location.protocol==='http:'&&location.hostname==='127.0.0.1','fixture must stay on loopback');
  await stage('initializing');
  const form=document.querySelector('[data-harness-composer]'),editor=document.querySelector('#prompt-textarea');
  let input=form.querySelector('input');
  if(options.unfamiliarAccept)input.accept='IMAGE/PNG; charset=binary,.PNG,image/x-png';
  if(options.portalPicker)document.body.append(input);
  const decoys=[];
  let wrongInputChanges=0,wrongInputSetters=0,entryPointerDowns=0,menuSelections=0,createdPickers=0,pickerClicks=0,pickerCalls=0,pickerErrors=0,nativeAwaitContinuations=0;
  let menusClosed=0,menuClosedBeforeInput=0,missingChooserCancellation=0;
  if(options.multipleInputs){
   for(let i=0;i<2;i++){
    const otherForm=document.createElement('form'),other=document.createElement('input');
    other.type='file';other.accept='image/*';other.hidden=true;other.addEventListener('change',()=>wrongInputChanges++);
    otherForm.append(other);document.body.prepend(otherForm);decoys.push(other);
   }
  }
  if(options.avatarPickers){
   for(let i=0;i<2;i++){
    const avatar=document.createElement('input');avatar.type='file';avatar.accept='image/*';avatar.hidden=true;
    avatar.setAttribute('aria-label','Profile avatar');avatar.addEventListener('change',()=>wrongInputChanges++);
    (i===0?form:document.body).append(avatar);decoys.push(avatar);
   }
  }
  if(options.entryMode)input.remove();
  const makePickerUnavailable=()=>{if(options.unavailablePicker==='disabled')input.disabled=true;else input.remove();};
  const restorePicker=()=>{input.disabled=false;if(!input.isConnected)(options.portalPicker?document.body:form).append(input);};
  const priorCard=form.querySelector('[data-file-name]'),priorImage=priorCard.querySelector('img');
  const canvas=document.createElement('canvas');canvas.width=canvas.height=2;
  canvas.getContext('2d').fillRect(0,0,2,2);priorImage.src=canvas.toDataURL('image/png');
  let applicationNetworkRequests=0;
  globalThis.fetch=()=>{applicationNetworkRequests++;throw Error('application network requests forbidden in local fixture');};
  XMLHttpRequest.prototype.send=function(){applicationNetworkRequests++;throw Error('application XHR forbidden in local fixture');};
  const mockLocation={href:options.route};
  const program=new Function('location','return ('+__SOURCE__+')')(mockLocation);
  const native={applicationID:'com.google.Chrome',sessionID:'synthetic-local-profile',windowID:'1',tabID:'1'};
  const call=command=>program(command,native);
  if(options.resident){
   const oldProgram=new Function('location','return ('+__PREVIOUS__+')')(mockLocation);
   const before=oldProgram({action:'captureTarget'},native);
   check(!!before.documentID&&oldProgram({action:'validate',target:before},native).valid,'old version actually resident in the same document');
   report.residentSourceVerified=true;
  }
  editor.focus();const selection=getSelection(),range=document.createRange();range.setStart(editor.firstChild,2);range.setEnd(editor.firstChild,7);selection.removeAllRanges();selection.addRange(range);
  const text=editor.textContent,anchor=selection.anchorNode,focus=selection.focusNode,anchorOffset=selection.anchorOffset,focusOffset=selection.focusOffset;
  let changes=0,setters=0,sends=0,reentrant=null,reentrantRefused=false,firstPendingCard=null;
  let startBeforePickerRestored=false,noInputStartRejected=false;
  const nativeFiles=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'files');
  Object.defineProperty(HTMLInputElement.prototype,'files',{...nativeFiles,set(value){
   setters++;if(decoys.includes(this))wrongInputSetters++;return Reflect.apply(nativeFiles.set,this,[value]);
  }});
  const tasks=[],ops=[],inputReceivers=new WeakSet();
  form.addEventListener('submit',event=>{event.preventDefault();sends++;});
  form.querySelector('button[type="submit"]').addEventListener('click',()=>sends++);
  const changed=event=>{
   changes++;
   const submittedInput=event.currentTarget,list=submittedInput.files,file=list[0];
   check(submittedInput===input,'the application receives its own chat picker, never another global input');
   check(list instanceof FileList&&list.length===1&&file instanceof File,'one actual native FileList item');
   inputReceivers.add(submittedInput);
   if(options.collapseSelectionInChange){editor.focus();selection.collapse(editor.firstChild,editor.firstChild.textContent.length);}
   if(options.replacePicker){
    const replacement=submittedInput.cloneNode();submittedInput.replaceWith(replacement);input=replacement;
    input.addEventListener('change',changed);
   }
   if(reentrant){
    const next=reentrant;reentrant=null;
    const refusal=call({...next.command('commit'),chunkIndex:1}).observation;
    reentrantRefused=refusal.preInputRetirement?.reason==='inputExecutionBusy'&&refusal.preInputRetirement.inputCount===0;
    check(reentrantRefused&&submittedInput.files[0]===file,'reentrant input cannot overwrite current native control');
   }
   const card=document.createElement('div');card.setAttribute('role','button');card.setAttribute('data-file-name',file.name);card.title=file.name;
   const image=document.createElement('img');image.alt=file.name;image.src=URL.createObjectURL(file);card.append(image);
   if(options.decoratedFilename){
    card.removeAttribute('data-file-name');card.title='正在上传 '+file.name+' (PNG image)';
    image.alt='Preview '+file.name+' (uploading)';image.src=canvas.toDataURL('image/png');
   }
   const progress=document.createElement('div');progress.setAttribute('role','progressbar');progress.setAttribute('aria-valuenow','10');card.append(progress);
   const task={file,list,card,image,progress,state:'uploading'};tasks.push(task);
   // The first acceptance is deliberately delayed; its input return is dropped.
   // A second input is allowed while A has no observed START yet.
   if(options.unavailablePicker){form.append(card);makePickerUnavailable();}
   else if(changes===1)firstPendingCard=card;else{form.append(card);if(changes===2)setTimeout(()=>form.append(firstPendingCard),0);}
   if(!options.retained)submittedInput.value='';
  };
  input.addEventListener('change',changed);
  const handoff=options.handoff?(__MOUNT__)(options.handoff,form,input):null;
  if(handoff)report.entryCounts=handoff.counts;
  if(handoff?.rival)decoys.push(handoff.rival);
  const nativeOrder=[],inputExecutionMS=[];
  if(handoff){
   input.addEventListener('input',event=>{
    check(event.target===input&&!event.isTrusted&&event.composed&&event.bubbles&&event.target.files.length===1,'native input event on its own picker');
    nativeOrder.push('input');
   });
   input.addEventListener('change',event=>{check(event.target===input,'change target');nativeOrder.push('change');});
  }
  let foreignAction=null,foreignCalls=0,unmodifiedForeignDefaults=0;
  if(options.foreignPickers){
   for(const label of ['Profile avatar','Project files']){
    const section=document.createElement('section'),picker=document.createElement('input'),button=document.createElement('button');
    section.setAttribute('aria-label',label);picker.type='file';picker.hidden=true;picker.id='foreign-picker-'+decoys.length;
    button.type='button';button.textContent=label;button.setAttribute('aria-controls',picker.id);
    let event;picker.addEventListener('click',value=>{event=value;});
    button.addEventListener('click',()=>{
     foreignCalls++;picker.click();
     if(event&&!event.defaultPrevented)unmodifiedForeignDefaults++;
    });
    section.append(button,picker);document.body.append(section);decoys.push(picker);
    picker.addEventListener('change',()=>wrongInputChanges++);
    const prior=foreignAction;foreignAction=()=>{prior?.();button.click();};
   }
  }
  if(!handoff&&(options.entryMode||options.linkedPicker||options.noForm||options.portalPicker)){
   const entry=document.createElement('button');entry.type='button';entry.setAttribute('aria-label','Add files and photos');
   entry.setAttribute('data-testid','composer-plus-button');entry.textContent='+';form.append(entry);
   if(!options.entryMode&&(options.linkedPicker||options.noForm||options.portalPicker)){
    input.id='current-chat-picker';entry.setAttribute('aria-controls',input.id);
   }
   if(!options.entryMode){entry.addEventListener('click',()=>input.click());}
   else{
    entry.setAttribute('aria-haspopup','menu');
    entry.addEventListener('pointerdown',event=>{
     if(event.button!==0||document.querySelector('[data-harness-attachment-menu]'))return;
     entryPointerDowns++;
     const menu=document.createElement('div');menu.setAttribute('role','menu');menu.setAttribute('data-harness-attachment-menu','');
     let externalPickerForm=null;
     const item=document.createElement('button');item.type='button';item.setAttribute('role','menuitem');item.textContent='Upload from computer';menu.append(item);
     document.body.append(menu);item.focus();selection.removeAllRanges();
     menu.addEventListener('keydown',key=>{
      if(key.key!=='Escape')return;
      if(input?.isConnected&&!inputReceivers.has(input))menuClosedBeforeInput++;
      menusClosed++;menu.remove();if(input?.isConnected)input.remove();externalPickerForm?.remove();
     });
     item.addEventListener('click',async()=>{
      menuSelections++;
      // Real application rendering delay, with no File supplied by the fixture.
      const createPicker=()=>{
       if(!menu.isConnected)return;
       const created=document.createElement('input');created.type='file';created.hidden=true;
       created.accept='IMAGE/PNG; charset=binary,.PNG,image/x-png';
       input=created;createdPickers++;created.addEventListener('change',changed);
       created.addEventListener('click',event=>{pickerClicks++;if(!event.defaultPrevented)missingChooserCancellation++;});
       if(options.nativeAwait){
        externalPickerForm=document.createElement('form');document.body.append(externalPickerForm);externalPickerForm.append(created);
       }else (options.menuOwnsInput?menu:document.body).append(created);
       pickerCalls++;
       try{if(options.entryMode==='showPicker')created.showPicker();else created.click();}
       catch{pickerErrors++;}
      };
      if(options.nativeAwait){
       // Native async/await continuation deliberately bypasses any replacement
       // of Promise.prototype.then; only Chrome's real await semantics run here.
       await Promise.resolve();
       await new Promise(resolve=>setTimeout(resolve,75));
       nativeAwaitContinuations++;createPicker();
      }else setTimeout(createPicker,75);
     });
    });
   }
  }
  async function operation(index){
   const color='rgb('+(20+index*30)+',40,70)';canvas.getContext('2d').fillStyle=color;canvas.getContext('2d').fillRect(0,0,2,2);
   const png=await new Promise(resolve=>canvas.toBlob(resolve,'image/png'));
   const bytes=new Uint8Array(await png.arrayBuffer()),sha=await hash(bytes);
   const target=call({action:'captureTarget'}),id=crypto.randomUUID();
   const identity={operationID:id,assetID:crypto.randomUUID(),attempt:1,assetSHA256:sha,target},invocationID=crypto.randomUUID();
   const op={identity,target,name:'riftlet-'+id+'.png',sha,command:action=>({action,identity,target,invocationID})};
   call({...op.command('begin'),uploadName:op.name,mediaType:'image/png',byteCount:bytes.length});
   call({...op.command('chunk'),chunkIndex:0,chunkBase64:btoa(String.fromCharCode(...bytes))});return op;
  }
  for(let index=0;index<options.count;index++)ops.push(await operation(index));
  const busyProbe=await operation(50);
  let otherTab;
  if(options.switchTabs){
   // Capture/stage operations in A, then switch the isolated Chromium browser
   // to a second real loopback document. A is the already-addressed JS realm.
   otherTab=window.open('/other-draft','_blank');
   check(!!otherTab,'headless Chrome opened tab B');
   await wait(()=>otherTab.document.getElementById('other-input'));
   otherTab.focus();
   await wait(()=>otherTab.document.hasFocus()&&!document.hasFocus());
   report.originalTabInBackground=true;
  }
  if(options.unavailablePicker){
   const unsubmitted=await operation(51),card=document.createElement('div');card.setAttribute('role','button');card.title=unsubmitted.name;
   const image=document.createElement('img');image.alt=unsubmitted.name;image.src=priorImage.src;card.append(image);form.append(card);
   makePickerUnavailable();
   const observed=call(unsubmitted.command('observe')).observation;
   noInputStartRejected=observed.state==='unknown'&&!observed.uploadStart&&setters===0&&changes===0;
   check(noInputStartRejected,'matching attachment without actual input never starts');
   restorePicker();card.remove();call(unsubmitted.command('discard'));
  }
  for(let index=0;index<ops.length;index++){
   await stage('input-'+(index+1));const op=ops[index];
   if(index===0)reentrant=busyProbe;
   if(index===2)tasks[0].state='unknown'; // Synthetic app lifecycle; deliberately irrelevant to native permission.
   if(foreignAction)setTimeout(foreignAction,0);
   const started=performance.now();
   const receipt=await call({...op.command('commit'),chunkIndex:1});
   inputExecutionMS.push(Math.round(performance.now()-started));
   // Only transport counters are inspected for diagnostics. Recover the product
   // receipt by observe, never by a second commit.
   if(handoff)report.lastInput={stage:receipt.entryDiagnostics?.stage,reason:receipt.observation.preInputRetirement?.reason,
    setters,changes,connected:input.isConnected};
   check(changes===index+1,'one change per screenshot');
   check(setters===index+1,'one native files setter per screenshot');
   if(options.unavailablePicker){
    const observed=call(op.command('observe')).observation;
    check(input.disabled||!input.isConnected,'picker remains unavailable while START is observed');
    check(observed.state==='uploadStarted'&&observed.belongsToOriginalDraft,'accepted START does not wait for picker restoration or COMPLETE');
    check(call({action:'validate',target:op.target}).valid===true,'draft validation does not require an already-mounted enabled picker');
    const unavailable=await operation(60+index);
    const failed=(await call({...unavailable.command('commit'),chunkIndex:1})).observation;
    check(failed.state==='invalidated'&&failed.preInputRetirement?.inputCount===0
     &&['attachmentEntryUnavailable','attachmentInputNotCreated'].includes(failed.preInputRetirement.reason)
     &&!failed.uploadStart&&setters===index+1&&changes===index+1,'actual unavailable execution is retained without input or START');
    startBeforePickerRestored=true;restorePicker();
   }else if(index===0)check(call(op.command('observe')).observation.state==='inputTriggered','first input completed before START');
   if(index>0)await wait(()=>call(op.command('observe')).observation.state==='uploadStarted');
   check(editor.textContent===text&&selection.anchorNode===anchor&&selection.focusNode===focus&&selection.anchorOffset===anchorOffset&&selection.focusOffset===focusOffset,'draft text and selection preserved');
   check(form.contains(priorCard),'existing attachment preserved');
  }
  let busyRetired=false;try{call({...busyProbe.command('commit'),chunkIndex:1});}catch(error){busyRetired=error.message==='COMMIT_REFUSED';}
  check(busyRetired,'retired concurrent operation cannot later submit');
  await stage('observing-starts');
  for(const op of ops){
   await wait(()=>call(op.command('observe')).observation.state==='uploadStarted');
   const observation=call(op.command('observe')).observation;
   check(observation.identity.operationID===op.identity.operationID&&observation.uploadStart.signal==='attachmentAccepted'&&observation.uploadStart.inputCount===1,'current operation gets independent accepted START');
   let rejected=false;try{call({...op.command('commit'),chunkIndex:1});}catch(error){rejected=error.message==='COMMIT_REFUSED';}
   check(rejected&&changes===options.count,'duplicate commit never submits again');
  }
  for(let index=0;index<tasks.length;index++){
   const task=tasks[index];check(form.contains(task.card),'all app attachments appended');
   check(await hash(await task.file.arrayBuffer())===ops[index].sha,'accepted File bytes remain unchanged after later inputs');
   check(task.list instanceof FileList,'application observed actual native FileList');
   if(options.retained)check(task.list.length===1&&task.list[0]===task.file,'retained prior FileList independent from replacement');
  }
  if(otherTab){
   check(otherTab.document.hasFocus()&&!document.hasFocus(),'input to A did not seize focus from B');
   check(otherTab.changed===0&&otherTab.document.getElementById('other-input').files.length===0,
    'tab B received no File');
   report.fixedTabAInputs=changes;report.tabBInputs=otherTab.changed;
   otherTab.close();
  }
  if(handoff){
   check(handoff.counts.linkDefaultAllowed===0&&handoff.counts.closeClicks===0&&handoff.counts.cloudClicks===0&&handoff.counts.chooserDefaultAllowed===0,'unrelated cloud and native chooser were untouched');
   check(nativeOrder.join(',')===Array(options.count).fill('input,change').join(','),'file event sequence after each setter');
   if(['forced-noun','forced-no-role','reused-content','nested','short-label','plain-action','pointer-open','focusable-menu','anchor-action','localized-opener'].includes(options.handoff))
    check(handoff.counts.menus===options.count,'the actual menu action executed per file');
   if(options.handoff==='ready-direct')check(handoff.counts.entry===0,'direct input avoids the inert entry');
   if(options.handoff==='nested')check(handoff.counts.submenus===options.count,'each submenu actually opened');
   if(options.handoff==='reused-open')check(handoff.counts.menus===options.count&&handoff.counts.entry<options.count,
    'already-open menu was used before any redundant trigger click');
   if(['detached','detached-showPicker','detached-stop','implicit-submit','await-existing','await-detached-with-rival'].includes(options.handoff))
    check(handoff.counts.pickerCalls===options.count,'the application actually invoked its picker for each file');
   if(options.handoff.startsWith('detached')||options.handoff==='await-detached-with-rival')check(!input.isConnected,'object-local receipt on still detached picker');
   if(options.foreignPickers)check(foreignCalls===options.count*2&&unmodifiedForeignDefaults===foreignCalls,
    'independent avatar and project picker invocations retain their default behavior');
   report.inputEventOrder=nativeOrder;report.unmodifiedForeignDefaults=unmodifiedForeignDefaults;
  }
  const stale=await operation(99);mockLocation.href='https://chatgpt.com/c/different-chat';
  const refused=call({...stale.command('commit'),chunkIndex:1}).observation;
  const wrongTargetRefused=refused.state==='invalidated'&&refused.preInputRetirement?.reason==='targetInvalidBeforeInput'&&refused.preInputRetirement.inputCount===0;
  check(wrongTargetRefused&&changes===options.count,'changed target refuses before native input');
  check(sends===0,'no automatic message send');
  check(wrongInputSetters===0&&wrongInputChanges===0&&decoys.every(picker=>picker.files.length===0),'unrelated file controls receive no setter/change and remain untouched');
  if(options.entryMode){
   // These fixtures actually invoke a newly created picker after choosing the
   // local menu action. In isolation the deliberate application delay is 75ms.
   // An unrelated idle file input must not cost the entire 3s discovery budget.
   check(inputExecutionMS.every(ms=>ms<2200),'identified menu picker waited for deadline: '+JSON.stringify(inputExecutionMS));
   check(entryPointerDowns===options.count&&menuSelections===options.count&&createdPickers===options.count,'each click autonomously opens its menu and receives a new dynamic picker');
   check(pickerCalls===options.count&&pickerErrors===0,'the actual input.click/showPicker path completes automatically');
   check(options.entryMode!=='click'||pickerClicks===options.count,'normal application input click handlers still run');
   check(missingChooserCancellation===0,'native chooser default is cancelled while input click handlers run');
   check(menusClosed===options.count&&menuClosedBeforeInput===0,'menu-owned picker stays mounted until after native input');
   if(options.nativeAwait)check(nativeAwaitContinuations===options.count,'every native await resumes and invokes its external-form picker');
  }
  Object.assign(report,{passed:true,phase:'complete',nativeChanges:changes,nativeSetters:setters,networkRequests:applicationNetworkRequests,automaticSends:sends,
   observedStarts:ops.length,inputExecutionMS,originalFileListsVerified:tasks.length,applicationIndependentTasksVerified:tasks.length,
   retainedNativeSelection:options.retained,reentrantInputRefused:reentrantRefused,wrongTargetRefused,
   lostReplyRecoveredWithoutReplay:true,textSelectionCardsPreserved:true,
   pickerReplacedEachChange:!!options.replacePicker,hiddenPortalPicker:!!options.portalPicker,
   decoratedFilenameAccepted:!!options.decoratedFilename,
   noForm:!!options.noForm,multipleInputs:!!options.multipleInputs,avatarPickers:!!options.avatarPickers,wrongInputChanges,wrongInputSetters,
   entryMode:options.entryMode||'direct',entryPointerDowns,menuSelections,createdPickers,pickerCalls,pickerClicks,pickerErrors,
   menuOwnsInput:!!options.menuOwnsInput,menusClosed,menuClosedBeforeInput,missingChooserCancellation,
   nativeAwaitContinuations,nativeAwait:!!options.nativeAwait,
   selectionCollapsedByApplication:!!options.collapseSelectionInChange,
   startBeforePickerRestored,noInputStartRejected,
   firstSyntheticUploadState:tasks[0].state,harnessTransport:'loopback-only'});
 }catch(error){report.error=String(error?.stack||error);}
 document.querySelector('#result').textContent=JSON.stringify(report);
 const response=await harnessFetch('/result',{method:'POST',body:JSON.stringify(report)});
 const next=await response.text();
 if(next.startsWith('/case/'))location.replace(next);
})();
</script>`.replace('__OPTIONS__',()=>JSON.stringify(options)).replace('__MOUNT__',()=>String(mountAttachmentEntryCase))
 .replace('__PREVIOUS__',()=>JSON.stringify(previous)).replace('__SOURCE__',()=>JSON.stringify(source).replace(/<\/script/gi,'<\\/script'));
}
const originalScenarios=[
 ...[2,3,5].map(count=>({count,retained:true,route:'https://chatgpt.com/c/ordinary-thread'})),
 {count:3,retained:false,route:'https://chatgpt.com/'},
 {count:3,retained:true,route:'https://chatgpt.com/g/g-p-project/c/project-thread'},
 {count:2,retained:true,route:'https://chatgpt.com/g/g-p-project/project'},
 {count:5,retained:true,replacePicker:true,portalPicker:true,decoratedFilename:true,route:'https://chatgpt.com/c/ordinary-thread'},
 ...['disabled','removed'].map(unavailablePicker=>({count:2,retained:true,unavailablePicker,route:'https://chatgpt.com/c/ordinary-thread'})),
 {name:'no-form-hidden-portal',count:5,retained:true,noForm:true,portalPicker:true,unfamiliarAccept:true,route:'https://chatgpt.com/'},
 {name:'linked-correct-picker-among-many',count:5,retained:true,portalPicker:true,multipleInputs:true,linkedPicker:true,route:'https://chatgpt.com/c/ordinary-thread'},
 {name:'dynamic-menu-click-portal',count:5,retained:true,noForm:true,multipleInputs:true,entryMode:'click',collapseSelectionInChange:true,route:'https://chatgpt.com/c/ordinary-thread'},
 {name:'dynamic-menu-showpicker-owned',count:5,retained:true,multipleInputs:true,entryMode:'showPicker',menuOwnsInput:true,collapseSelectionInChange:true,route:'https://chatgpt.com/g/g-p-project/c/project-thread'},
 {name:'dynamic-entry-ignores-local-and-global-avatar',count:5,retained:true,multipleInputs:true,avatarPickers:true,entryMode:'click',route:'https://chatgpt.com/c/ordinary-thread'},
 {name:'native-await-menu-external-form-picker',count:5,retained:true,multipleInputs:true,avatarPickers:true,entryMode:'click',nativeAwait:true,collapseSelectionInChange:true,route:'https://chatgpt.com/c/ordinary-thread'},
 {name:'direct-input-preserves-collapsed-selection',count:5,retained:true,collapseSelectionInChange:true,route:'https://chatgpt.com/c/ordinary-thread'}
];

// Each new layout gets a fresh document. Run the batch in one owned headless
// Chrome process and temporary profile, including a separate real tab for A→B.
const handoffScenarios=['direct','connected','detached','verb-menu','noun-menu','no-role','await-existing',
 'forced-noun','forced-no-role','reused-open','reused-content','nested','short-label','plain-action','pointer-open','detached-showPicker',
 'renamed-action','ready-direct','implicit-submit','detached-stop','focusable-menu','anchor-action','localized-opener','await-detached-with-rival'].map(handoff=>({handoff,name:'handoff-'+handoff,count:handoff==='detached'?5:2,
   retained:true,route:'https://chatgpt.com/c/ordinary-thread',resident:handoff==='detached',
   foreignPickers:handoff==='await-existing',switchTabs:handoff==='direct'}));
const groups=[...originalScenarios.map(scenario=>[scenario]),handoffScenarios];
for(const unfiltered of groups){
 const group=unfiltered.filter(options=>!process.env.RIFTLET_NATIVE_CASE||JSON.stringify(options).includes(process.env.RIFTLET_NATIVE_CASE));
 if(!group.length)continue;
 test('native Chrome independent append '+(group.length===1?JSON.stringify(group[0]):group.map(item=>item.name).join(', ')),{
 skip:!binary&&!required?'CHROME_NOT_RUN: no native Chrome binary in this executor':false,timeout:60000+4000*group.length
},async t=>{

  assert.ok(binary,'CHROME_REQUIRED_BUT_UNAVAILABLE: native Chrome must run in this CI job');
  assert.ok(['darwin','linux'].includes(process.platform),'isolated Chrome process-group cleanup requires POSIX');
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-native-input-'));
  let child,exit,stderr='',lastPhase='browser-not-started',completed=false,resolveReport,rejectReport;
  const failures=[],connections=new Set();
  const reports=[],pages=group.map(browserFixture);
  const finished=new Promise((resolve,reject)=>{resolveReport=resolve;rejectReport=reject;});
  const server=http.createServer((request,response)=>{
    if(request.method==='GET'&&request.url==='/other-draft'){
      response.writeHead(200,{'content-type':'text/html; charset=utf-8'});
      response.end('<!doctype html><textarea autofocus>Other draft</textarea><input type="file" id="other-input"><script>window.changed=0;document.querySelector("input").onchange=()=>window.changed++;</script>');return;
    }
    const caseIndex=request.url==='/'?0:Number(/^\/case\/(\d+)$/.exec(request.url)?.[1]);
    if(request.method==='GET'&&pages[caseIndex]){
      response.writeHead(200,{'content-type':'text/html; charset=utf-8','cache-control':'no-store'});response.end(pages[caseIndex]);return;
    }
    if(request.method!=='POST'||!['/progress','/result'].includes(request.url)){response.writeHead(404);response.end();return;}
    let body='',oversize=false;
    request.setEncoding('utf8');request.on('data',part=>{body+=part;if(body.length>65536){oversize=true;request.destroy();rejectReport(Error('oversized local fixture report'));}});
    request.on('end',()=>{
      if(oversize)return;
      try{
        const value=JSON.parse(body);response.writeHead(200,{'content-type':'text/plain'});
        if(request.url==='/progress'){lastPhase=String(value.phase);response.end('ok');return;}
        reports.push(value);
        if(reports.length<pages.length){response.end('/case/'+reports.length);return;}
        response.end('ok');completed=true;resolveReport(reports);
      }catch(error){response.writeHead(400);response.end();rejectReport(error);}
    });
    request.on('error',error=>rejectReport(error));
  });
  server.on('connection',socket=>{connections.add(socket);socket.once('close',()=>connections.delete(socket));});
  try{
    await bounded(new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);}),
      2000,'loopback server listen deadline',t.signal);
    const address=server.address();assert.equal(address.address,'127.0.0.1');
    child=spawn(binary,['--headless=new','--no-sandbox','--disable-gpu','--disable-background-networking',
      '--disable-component-update','--disable-sync','--no-first-run','--no-default-browser-check',
      ...(group.some(options=>options.switchTabs)?['--disable-popup-blocking']:[]),
      '--user-data-dir='+path.join(temp,'isolated-profile'),'http://127.0.0.1:'+address.port+'/'],
      {detached:true,stdio:['ignore','ignore','pipe']});
    child.stderr.setEncoding('utf8');child.stderr.on('data',part=>{stderr=(stderr+part).slice(-8000);});
    child.once('error',rejectReport);
    exit=new Promise(resolve=>child.once('exit',(code,signal)=>{
      resolve();if(!completed)rejectReport(Error('Chrome exited before result; code='+code+' signal='+signal+' phase='+lastPhase+' stderr='+stderr));
    }));
    await bounded(finished,30000+4000*group.length,()=> 'CHROME_FIXTURE_TIMEOUT phase='+lastPhase+' stderr='+stderr,t.signal);
    for(const [index,report] of reports.entries()){
     const options=group[index];
     try{
      assert.equal(report.passed,true,JSON.stringify(report));assert.equal(report.nativeChanges,options.count);assert.equal(report.nativeSetters,options.count);assert.equal(report.networkRequests,0);
      assert.equal(report.applicationIndependentTasksVerified,options.count);assert.equal(report.automaticSends,0);
      assert.equal(report.originalFileListsVerified,options.count);assert.equal(report.observedStarts,options.count);
      assert.equal(report.reentrantInputRefused,true);assert.equal(report.wrongTargetRefused,true);
      assert.equal(report.lostReplyRecoveredWithoutReplay,true);
      if(options.unavailablePicker){assert.equal(report.startBeforePickerRestored,true);assert.equal(report.noInputStartRejected,true);}
      assert.equal(report.harnessTransport,'loopback-only');
      console.log(JSON.stringify({scenario:options.name||options.route,...report}));
     }catch(error){failures.push(Error((options.name||options.route)+': '+error.message));}
    }
  }catch(error){failures.push(error);}
  finally{
    // detached:true creates a new session/process group owned solely by this
    // fixture. Chrome helpers can outlive the main process and still write the
    // profile, so wait for that exact group even after the main exit event.
    // Never enumerate, match names, or signal any other Chrome process/group.
    let groupClean=false;
    try{await cleanupOwnedChrome(child,exit);groupClean=true;}catch(error){failures.push(error);}
    try{await closeLoopbackServer(server,connections);}catch(error){failures.push(error);}
    // OS/helper final file writes may settle just after group exit. Retry only
    // this newly created profile root; exhausting the bounded retries fails.
    if(groupClean){
      try{await fs.promises.rm(temp,{recursive:true,force:true,maxRetries:8,retryDelay:150});}
      catch(error){failures.push(error);}
    }
  }
  if(failures.length)throw new AggregateError(failures,'native Chrome fixture or cleanup failed: '+failures.map(error=>error.message).join('; '));
});
}
