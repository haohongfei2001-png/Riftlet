'use strict';
// Behavioral regression of the shipped page program in a controlled application.
// Real native browser primitives are additionally checked by the Chrome suite.
const test=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const {fixture,png}=require('./independent-input-fixture.cjs');
require('./attachment-entry-handoff.test.cjs');
require('./original-image-transport.test.cjs');
require('./ordinary-composer.test.cjs');
require('./click-document-witness.test.cjs');

function accepted(f,op) {
 const observation=f.observe(op);
 assert.equal(observation.state,'uploadStarted');
 assert.equal(observation.identity.operationID,op.identity.operationID);
 assert.equal(observation.uploadStart.signal,'attachmentAccepted');
 assert.equal(observation.uploadStart.inputCount,1);
 assert.equal(observation.exactImageIdentity,true);
 assert.equal(observation.belongsToOriginalDraft,true);
 assert.ok(observation.attachmentID);
 return observation;
}

// The controlled application owns this interaction. Riftlet only invokes its
// ordinary attachment entry and supplies a real File through the picked input.
// It does not create an input/card or announce acceptance on the application's behalf.
function attachmentApplication(f,{dynamic=false,menu=false,pointerOnly=false,delay=0,method='click',externalForm=false,moveSelection=false,acceptAttribute='image/x-png',scheduler='timeout'}={}) {
 f.input.remove();
 const destination=externalForm?f.body.append(new f.Node('form',{'data-purpose':'portal-root'})):f.body;
 let picker=dynamic?null:destination.append(f.input),entryCount=0,uploadCount=0;
 const prepare=()=>{
  if(!picker){picker=destination.append(new f.context.HTMLInputElement());picker.rendered=false;}
  picker.setAttribute('accept',acceptAttribute);
  picker.applicationAccept=true;
  if(method!=='none')picker[method]();
 };
 const upload=()=>{
  uploadCount++;
  if(scheduler==='queueMicrotask')f.context.queueMicrotask(prepare);
  else if(scheduler==='animationFrame')f.context.requestAnimationFrame(prepare);
  else if(scheduler==='nested')f.context.queueMicrotask(()=>f.context.requestAnimationFrame(()=>f.context.setTimeout(prepare,delay)));
  else if(delay)f.context.setTimeout(prepare,delay);
  else prepare();
 };
 const entry=f.form.append(new f.Node('button',menu?{'aria-haspopup':'menu',type:'button'}:{'aria-label':'Attach files',type:'button'}));
 entry.textContent=menu?'+':'Attach files';
 entry.addEventListener(pointerOnly?'pointerdown':'click',()=>{
  entryCount++;
  if(!menu){upload();return;}
  const popup=f.body.append(new f.Node('div',{role:'menu'}));
  const choice=popup.append(new f.Node('button',{role:'menuitem',type:'button'}));choice.textContent='Upload from computer';
  choice.addEventListener('click',upload);
  popup.addEventListener('keydown',event=>{if(event.key==='Escape')popup.remove();});
  if(moveSelection){choice.focus();f.selection.setBaseAndExtent(choice,0,choice,0);}
 });
 return {entry,get picker(){return picker;},get entryCount(){return entryCount;},get uploadCount(){return uploadCount;}};
}

test('core regression: ordinary attachment button can upload PNG before Riftlet discovers an on-demand portalled input',async()=>{
 const manual=fixture(),normal=attachmentApplication(manual,{dynamic:true,menu:true,externalForm:true});
 normal.entry.click();manual.body.querySelector('[role="menuitem"]').click();
 assert.equal(manual.chooserOpens,1,'ordinary application entry reaches its native file picker');
 const manualFile=new File([png],'normal-attachment.png',{type:'image/png'}),transfer=new manual.context.DataTransfer();
 transfer.items.add(manualFile);normal.picker.files=transfer.files;normal.picker.dispatchEvent(new manual.context.Event('change',{bubbles:true}));
 assert.ok(manual.form.querySelectorAll('[data-file-name]').some(card=>card.getAttribute('data-file-name')===manualFile.name),'the same application accepts normal PNG input');

 const f=fixture(),app=attachmentApplication(f,{dynamic:true,menu:true,externalForm:true,delay:35,moveSelection:true});
 const text=f.editor.textContent,anchor=f.selection.anchorNode,focus=f.selection.focusNode;
 for(let index=0;index<5;index++){
  const op=f.bind();f.stage(op);const receipt=(await f.commit(op)).observation;
  assert.equal(receipt.state,'uploadStarted');accepted(f,op);
  assert.ok(app.picker.files[0] instanceof File);assert.equal(app.picker.files[0].name,op.name);
  assert.deepEqual(Buffer.from(await app.picker.files[0].arrayBuffer()),png,'exact original PNG reaches the application');
  assert.equal(f.setters,index+1);assert.equal(f.changes,index+1);
  assert.equal(f.form.querySelectorAll('[data-file-name]').length,index+2,'all earlier active attachments are retained');
 }
 assert.equal(app.entryCount,5,'external portalled picker is rediscovered through the actual entry each click');
 assert.equal(app.uploadCount,5);assert.equal(f.chooserOpens,0,'automation completes without opening an OS chooser');
 assert.equal(f.editor.textContent,text);assert.equal(f.selection.anchorNode,anchor);assert.equal(f.selection.focusNode,focus);
 assert.equal(f.selection.anchorOffset,2);assert.equal(f.selection.focusOffset,7);assert.equal(f.selection.isCollapsed,false);
 assert.ok(f.form.contains(f.oldCard));assert.equal(f.sends,0);
});

for(const mode of ['hidden-external','showPicker','pointerdown-menu','unusual-accept'])test('actual attachment entry chooses its responsible input among unrelated controls: '+mode,async()=>{
 const f=fixture(),app=attachmentApplication(f,{externalForm:true,menu:mode==='pointerdown-menu',pointerOnly:mode==='pointerdown-menu',
  method:mode==='showPicker'?'showPicker':'click',acceptAttribute:mode==='unusual-accept'?'.PNG, application/octet-stream':'image/*'});
 app.picker.rendered=false;
 const unrelated=f.body.append(new f.Node('aside')).append(new f.context.HTMLInputElement());unrelated.applicationAccept=false;
 const op=f.bind();f.stage(op);await f.commit(op);accepted(f,op);
 assert.equal(app.picker.files[0].name,op.name);assert.equal(unrelated.files.length,0);
 assert.equal(f.setters,1);assert.equal(f.changes,1);assert.equal(f.chooserOpens,0);assert.equal(f.sends,0);
});

test('route change during dynamic discovery retires without input into the new chat',async()=>{
 const f=fixture();attachmentApplication(f,{dynamic:true,delay:80});
 const op=f.bind();f.stage(op);const pending=f.commit(op);
 f.setRoute('https://chatgpt.com/c/another-chat');
 const result=(await pending).observation;
 assert.equal(result.preInputRetirement.reason,'targetInvalidBeforeInput');
 assert.equal(result.preInputRetirement.inputCount,0);assert.equal(result.uploadStart,undefined);
 assert.equal(f.changes,0);assert.equal(f.setters,0);
});

test('a menu label activates its hidden portalled picker without opening the system chooser',async()=>{
 const f=fixture();f.input.remove();
 const picker=f.body.append(new f.Node('form')).append(f.input);let labelClicks=0;
 picker.setAttribute('id','portal-picker');picker.rendered=false;
 const entry=f.form.append(new f.Node('button',{'aria-label':'Attach files',type:'button'}));
 entry.addEventListener('click',()=>{
  const popup=f.body.append(new f.Node('div',{role:'menu'}));
  const label=popup.append(new f.Node('label',{for:'portal-picker',role:'menuitem'}));label.textContent='Upload from computer';
  label.addEventListener('click',()=>{labelClicks++;});
 });
 const op=f.bind();f.stage(op);await f.commit(op);accepted(f,op);
 assert.equal(labelClicks,1);assert.equal(picker.files[0].name,op.name);assert.equal(f.changes,1);assert.equal(f.setters,1);assert.equal(f.chooserOpens,0);
});

test('several local file inputs are resolved by the actual attachment button invocation',async()=>{
 const f=fixture(),unrelated=f.form.append(new f.context.HTMLInputElement());unrelated.applicationAccept=false;
 let clicks=0;
 const entry=f.form.append(new f.Node('button',{'aria-label':'Attach files',type:'button'}));
 entry.addEventListener('click',()=>{clicks++;f.input.click();});
 const op=f.bind();f.stage(op);await f.commit(op);accepted(f,op);
 assert.equal(clicks,1);assert.equal(unrelated.files.length,0);assert.equal(f.input.files[0].name,op.name);
 assert.equal(f.setters,1);assert.equal(f.changes,1);assert.equal(f.chooserOpens,0);
});

for(const decoyLocation of ['current-form','sole-global-avatar'])test('unrelated picker cannot preempt the executable chat attachment entry: '+decoyLocation,async()=>{
 const f=fixture(),app=attachmentApplication(f,{externalForm:true,dynamic:decoyLocation==='sole-global-avatar'});
 const decoy=(decoyLocation==='current-form'?f.form:f.body).append(new f.context.HTMLInputElement());
 decoy.applicationAccept=false;decoy.setAttribute('aria-label','Change profile photo');
 const op=f.bind();f.stage(op);await f.commit(op);
 assert.equal(decoy.setterCount,0,'an unrelated picker must receive no native setter');
 assert.equal(decoy.changeCount,0);assert.equal(decoy.files.length,0);
 assert.equal(app.entryCount,1,'the actual chat attachment entry must execute');
 assert.equal(app.picker.setterCount,1);assert.equal(app.picker.files[0].name,op.name);
 accepted(f,op);assert.equal(f.setters,1);assert.equal(f.changes,1);assert.equal(f.chooserOpens,0);
});

test('an unrelated asynchronous avatar click cannot steal a delayed chat attachment invocation',async()=>{
 const f=fixture(),app=attachmentApplication(f,{dynamic:true,externalForm:true,delay:100});
 const external=f.body.append(new f.Node('form',{'data-purpose':'account-settings'}));
 const avatar=external.append(new f.context.HTMLInputElement()),other=external.append(new f.context.HTMLInputElement());
 avatar.applicationAccept=false;other.applicationAccept=false;
 avatar.setAttribute('aria-label','Profile photo');other.setAttribute('aria-label','Import account settings');
 // This callback belongs to the application's independent avatar action and
 // was queued before Riftlet activated the chat attachment entry.
 f.context.setTimeout(()=>avatar.click(),1);
 const op=f.bind();f.stage(op);await f.commit(op);
 assert.equal(avatar.setterCount,0,'an unrelated asynchronous click cannot take this PNG');
 assert.equal(other.setterCount,0);assert.equal(app.entryCount,1);
 assert.equal(app.picker.setterCount,1);assert.equal(app.picker.files[0].name,op.name);
 assert.equal(app.picker.chooserOpens,0,'the chat entry finishes without an OS chooser');
 assert.equal(avatar.chooserOpens,1,'the unrelated application action is neither captured nor cancelled');
 assert.deepEqual(Buffer.from(await app.picker.files[0].arrayBuffer()),png);
 accepted(f,op);assert.equal(f.changes,1);assert.equal(f.setters,1);
});

for(const scheduler of ['queueMicrotask','animationFrame','nested'])test('the selected entry retains its actual asynchronous picker invocation through '+scheduler,async()=>{
 const f=fixture(),app=attachmentApplication(f,{dynamic:true,externalForm:true,scheduler,delay:30,method:'showPicker'});
 const op=f.bind();f.stage(op);await f.commit(op);accepted(f,op);
 assert.equal(app.entryCount,1);assert.equal(app.picker.files[0].name,op.name);
 assert.equal(app.picker.setterCount,1);assert.equal(f.changes,1);assert.equal(app.picker.chooserOpens,0);
});

for(const mode of ['resolved-promise-click','timer-showPicker'])test('a same-realm native async attachment handler awaits then invokes its newly created picker: '+mode,async()=>{
 const f=fixture();f.input.remove();
 const entry=f.form.append(new f.Node('button',{'aria-label':'Attach files',type:'button'}));
 // Native await continuations do not call a patched Promise.prototype.then.
 // Construct the application's handler in the page realm so this is the exact
 // async behavior the shipped script must support, not a synthetic then chain.
 const handler=vm.runInContext(`(async function () {
  globalThis.entryInvocationCount=(globalThis.entryInvocationCount||0)+1;
  ${mode==='resolved-promise-click'?'await Promise.resolve();':'await new Promise(resolve=>setTimeout(resolve,35));'}
  const picker=new HTMLInputElement();
  picker.setAttribute('id','async-created-picker');
  document.body.append(picker);
  picker.${mode==='resolved-promise-click'?'click':'showPicker'}();
 })`,f.context);
 entry.addEventListener('click',handler);
 const op=f.bind();f.stage(op);await f.commit(op);accepted(f,op);
 const picker=f.document.getElementById('async-created-picker');
 assert.equal(f.context.entryInvocationCount,1);assert.ok(picker.files[0] instanceof File);
 assert.equal(picker.files[0].name,op.name);assert.deepEqual(Buffer.from(await picker.files[0].arrayBuffer()),png);
 assert.equal(picker.setterCount,1);assert.equal(picker.changeCount,1);assert.equal(picker.chooserOpens,0);
 assert.equal(f.setters,1);assert.equal(f.changes,1);assert.equal(f.sends,0);assert.ok(f.form.contains(f.oldCard));
});

test('textarea draft and backward noncollapsed selection survive automatic attachment menu input',async()=>{
 const f=fixture({editorTag:'textarea'}),app=attachmentApplication(f,{dynamic:true,externalForm:true,menu:true,moveSelection:true});
 const before={value:f.editor.value,start:f.editor.selectionStart,end:f.editor.selectionEnd,direction:f.editor.selectionDirection};
 // Native textarea selection is independent of document.getSelection().
 f.selection.setBaseAndExtent(f.body,0,f.body,0);
 app.entry.addEventListener('click',()=>f.editor.setSelectionRange(0,0,'none'));
 const op=f.bind();f.stage(op);await f.commit(op);accepted(f,op);
 assert.equal(f.editor.value,before.value);
 assert.equal(f.editor.selectionStart,before.start);assert.equal(f.editor.selectionEnd,before.end);
 assert.equal(f.editor.selectionDirection,before.direction);assert.equal(f.document.activeElement,f.editor);
 assert.equal(f.sends,0);assert.equal(f.chooserOpens,0);assert.ok(f.form.contains(f.oldCard));
});

test('an inert first local attachment entry falls through to a working local entry and ignores cloud providers',async()=>{
 const f=fixture();f.input.remove();f.body.append(new f.Node('form')).append(f.input);
 let firstClicks=0,cloudClicks=0,workingClicks=0;
 const first=f.form.append(new f.Node('button',{'aria-label':'Attach files',type:'button'}));
 first.addEventListener('click',()=>{firstClicks++;});
 const cloud=f.form.append(new f.Node('button',{'aria-label':'Upload from Google Drive',type:'button'}));
 cloud.addEventListener('click',()=>{cloudClicks++;});
 const working=f.form.append(new f.Node('button',{'aria-label':'Upload file from computer',type:'button'}));
 working.addEventListener('click',()=>{workingClicks++;f.input.click();});
 const op=f.bind();f.stage(op);await f.commit(op);
 assert.equal(firstClicks,1);assert.equal(cloudClicks,0);assert.equal(workingClicks,1);
 accepted(f,op);assert.equal(f.input.setterCount,1);assert.equal(f.changes,1);assert.equal(f.chooserOpens,0);
});

test('an external project upload entry and its aria-controls cannot preempt the current chat input',async()=>{
 const f=fixture(),project=f.body.append(new f.Node('section',{'aria-label':'Project files'}));
 const projectPicker=project.append(new f.context.HTMLInputElement());projectPicker.setAttribute('id','project-upload');projectPicker.applicationAccept=false;
 const projectEntry=project.append(new f.Node('button',{'aria-label':'Upload files to project','aria-controls':'project-upload',type:'button'}));
 let projectClicks=0;projectEntry.addEventListener('click',()=>{projectClicks++;projectPicker.click();});
 const op=f.bind();f.stage(op);await f.commit(op);accepted(f,op);
 assert.equal(projectPicker.setterCount,0);assert.equal(projectPicker.changeCount,0);assert.equal(projectClicks,0);
 assert.equal(f.input.setterCount,1);assert.equal(f.input.files[0].name,op.name);assert.equal(f.changes,1);assert.equal(f.chooserOpens,0);
});

test('the activated entry can mount its input synchronously, or later in its own controlled portal',async()=>{
 for(const delay of [0,35]){
  const f=fixture(),app=attachmentApplication(f,{dynamic:true,externalForm:true,method:'none',delay});
  if(delay){
   const portal=f.document.querySelector('[data-purpose="portal-root"]');
   portal.setAttribute('id','attachment-portal');app.entry.setAttribute('aria-controls',portal.id);
  }
  const op=f.bind();f.stage(op);await f.commit(op);accepted(f,op);
  assert.equal(app.entryCount,1);assert.equal(app.uploadCount,1);assert.equal(app.picker.setterCount,1);
  assert.equal(app.picker.files[0].name,op.name);assert.deepEqual(Buffer.from(await app.picker.files[0].arrayBuffer()),png);
  assert.equal(f.changes,1);assert.equal(f.chooserOpens,0);
 }
});

test('a bare asynchronous mount in an unlinked form cannot select a file recipient',async()=>{
 const f=fixture(),app=attachmentApplication(f,{dynamic:true,externalForm:true,method:'none',delay:35});
 const op=f.bind();f.stage(op);const result=(await f.commit(op)).observation;
 assert.equal(app.entryCount,1);assert.equal(app.uploadCount,1);
 assert.equal(result.state,'invalidated');assert.equal(result.preInputRetirement.inputCount,0);
 assert.equal(result.uploadStart,undefined);assert.equal(app.picker.setterCount,0);
 assert.equal(app.picker.changeCount,0);assert.equal(f.setters,0);assert.equal(f.changes,0);
});

test('readonly or disabled text editing does not disable an available chat attachment input',async()=>{
 for(const condition of ['readOnly','disabled']){
  const f=fixture({editorTag:'textarea'});f.editor[condition]=true;
  const before=f.editor.value,op=f.bind();f.stage(op);await f.commit(op);accepted(f,op);
  assert.equal(f.input.setterCount,1);assert.equal(f.input.files[0].name,op.name);assert.equal(f.changes,1);
  assert.equal(f.editor.value,before);assert.ok(f.form.contains(f.oldCard));assert.equal(f.sends,0);
 }
});

test('a late timer from the cancelled chat entry cannot open an OS chooser after navigation',async()=>{
 const f=fixture(),app=attachmentApplication(f,{dynamic:true,externalForm:true,delay:100});
 const op=f.bind();f.stage(op);const pending=f.commit(op);
 f.setRoute('https://chatgpt.com/c/new-destination');
 const result=(await pending).observation;
 assert.equal(result.preInputRetirement.reason,'targetInvalidBeforeInput');
 await new Promise(resolve=>setTimeout(resolve,125));
 assert.equal(f.chooserOpens,0,'the delayed callback was initiated by this cancelled attachment action');
 assert.equal(f.changes,0);assert.equal(f.setters,0);assert.equal(result.uploadStart,undefined);
 if(app.picker)assert.equal(app.picker.files.length,0);
});

test('a setter exception is uncertain and never causes a second attachment path',async()=>{
 const f=fixture(),app=attachmentApplication(f,{externalForm:true});
 f.setSetter(()=>{throw Error('setter may already have side effects');});
 const op=f.bind();f.stage(op);const result=(await f.commit(op)).observation;
 assert.equal(result.state,'unknown');assert.equal(result.uploadStart,undefined);
 assert.equal(result.preInputRetirement,undefined);assert.equal(f.setters,1);assert.equal(f.changes,0);
 assert.equal(app.entryCount,1);assert.equal(app.uploadCount,1);
 assert.throws(()=>f.commit(op),/COMMIT_REFUSED/);f.observe(op);f.observe(op);
 assert.equal(app.entryCount,1);assert.equal(f.setters,1,'uncertain setter must never be replayed');
});

for(const count of [2,3,5])test(`clicking ${count} screenshots appends each exactly once while earlier uploads remain active`,()=>{
 const f=fixture(),ops=[],beforeText=f.editor.textContent,beforeSelection={...f.selection};
 for(let index=0;index<count;index++){
  const op=f.bind();f.stage(op);f.commit(op);ops.push(op);
  accepted(f,op);
  assert.equal(f.changes,index+1);
  assert.equal(f.setters,index+1);
  assert.equal(f.input.files.length,1,'native control intentionally retains the most recent File');
  assert.equal(f.input.files[0].name,op.name);
  for(const prior of ops)assert.ok(f.form.querySelectorAll('[data-file-name]').some(node=>node.getAttribute('data-file-name')===prior.name));
 }
 assert.equal(f.form.querySelectorAll('[data-file-name]').length,count+1,'all old and new attachment cards retained');
 assert.equal(f.editor.textContent,beforeText);
 assert.deepEqual(f.selection,beforeSelection);
 assert.ok(f.form.contains(f.oldCard));
 assert.equal(f.sends,0);
});

test('an operation without START stays observe-only and cannot block the next screenshot',()=>{
 const f=fixture({accept:false}),first=f.bind();f.stage(first);f.commit(first);
 assert.equal(f.observe(first).state,'inputTriggered');
 f.setAccept(true);
 const second=f.bind();f.stage(second);f.commit(second);accepted(f,second);
 assert.equal(f.observe(first).state,'inputTriggered','later input cannot relabel the uncertain previous submission');
 const third=f.bind();f.stage(third);f.commit(third);accepted(f,third);
 assert.equal(f.changes,3);assert.equal(f.setters,3);
 assert.throws(()=>f.commit(first),/COMMIT_REFUSED|already.*committ/i);
 assert.equal(f.changes,3,'observing or retrying a receipt never repeats the native input');
});

test('a lost commit reply is recovered only by observing the original operation',()=>{
 const f=fixture({accept:false}),op=f.bind();f.stage(op);
 // Deliberately drop the transport result after the native input has happened.
 f.commit(op);
 assert.equal(f.changes,1);assert.equal(f.observe(op).state,'inputTriggered');
 f.addCard(op.name);
 accepted(f,op);
 for(let index=0;index<4;index++)accepted(f,op);
 assert.throws(()=>f.commit(op),/COMMIT_REFUSED|already.*committ/i);
 assert.equal(f.setters,1);assert.equal(f.changes,1);
});

test('START requires a current new accepted attachment, not setter, change, old card or filename placeholder',()=>{
 const f=fixture({accept:false}),op=f.bind();f.stage(op);f.commit(op);
 assert.equal(f.observe(op).state,'inputTriggered');
 f.addCard('unrelated.png');
 assert.equal(f.observe(op).state,'inputTriggered');
 const placeholder=f.addCard(op.name,{placeholder:true,progress:false});
 assert.equal(f.observe(op).state,'inputTriggered');
 placeholder.remove();f.addCard(op.name,{progress:false});
 accepted(f,op);
});

test('one synchronous input execution excludes reentrant setter/change without holding an upload lock',()=>{
 const f=fixture(),first=f.bind(),second=f.bind();f.stage(first);f.stage(second);
 let busyCount=0;
 f.setSetter(()=>{
  if(busyCount)return;
  const refusal=f.commit(second).observation;
  assert.equal(refusal.preInputRetirement.reason,'inputExecutionBusy');
  assert.equal(refusal.preInputRetirement.inputCount,0);
  busyCount++;
 });
 f.commit(first);assert.equal(busyCount,1);assert.equal(f.changes,1);
 f.setSetter(null);assert.throws(()=>f.commit(second),/COMMIT_REFUSED/);
 const next=f.bind();f.stage(next);f.commit(next);accepted(f,first);accepted(f,next);
 assert.equal(f.changes,2);assert.equal(f.setters,2);
});

test('change-handler reentry cannot overwrite the executing FileList',()=>{
 const f=fixture(),first=f.bind(),second=f.bind();f.stage(first);f.stage(second);
 let checked=false;
 f.setChange(file=>{
  if(checked)return;checked=true;
  assert.equal(file.name,first.name);
  const refusal=f.commit(second).observation;
  assert.equal(refusal.preInputRetirement.reason,'inputExecutionBusy');
  assert.equal(refusal.preInputRetirement.inputCount,0);
  assert.equal(f.input.files[0].name,first.name);
 });
 f.commit(first);f.setChange(null);assert.throws(()=>f.commit(second),/COMMIT_REFUSED/);
 const next=f.bind();f.stage(next);f.commit(next);
 assert.equal(f.changes,2);accepted(f,first);accepted(f,next);
});

test('rebuilding a hidden picker keeps both pre-captured clicks and delayed START on the same composer',()=>{
 const f=fixture({accept:false}),first=f.bind(),second=f.bind();f.stage(first);f.stage(second);
 const replacement=new f.context.HTMLInputElement();replacement.rendered=false;
 f.setChange(()=>{f.input.remove();f.form.append(replacement);f.setChange(null);});
 f.commit(first);assert.equal(f.observe(first).state,'inputTriggered');
 f.setAccept(true);f.commit(second);accepted(f,second);
 f.addCard(first.name);accepted(f,first);
 assert.equal(f.setters,2);assert.equal(f.changes,2);
 assert.equal(replacement.files[0].name,second.name);
 assert.ok(f.form.contains(f.oldCard));assert.equal(f.sends,0);
});

test('rebuilding the picker inside change cannot evade the same-composer synchronous input mutex',()=>{
 const f=fixture(),first=f.bind(),nested=f.bind();f.stage(first);f.stage(nested);
 const replacement=new f.context.HTMLInputElement();
 f.setChange(()=>{
  f.input.remove();f.form.append(replacement);f.setChange(null);
  const refusal=f.commit(nested).observation;
  assert.equal(refusal.preInputRetirement.reason,'inputExecutionBusy');
  assert.equal(refusal.preInputRetirement.inputCount,0);
 });
 f.commit(first);accepted(f,first);
 const second=f.bind();f.stage(second);f.commit(second);accepted(f,second);
 assert.equal(f.setters,2);assert.equal(f.changes,2);
 assert.equal(replacement.files[0].name,second.name);
});

test('a hidden portal picker linked by the chat attachment entry works without requiring editor focus',()=>{
 const f=fixture({focused:false});f.input.remove();f.body.append(f.input);f.input.rendered=false;
 f.input.setAttribute('id','chat-upload');
 const entry=f.form.append(new f.Node('button',{'aria-label':'Attach files','aria-controls':'chat-upload',type:'button'}));
 entry.addEventListener('click',()=>f.input.click());
 const first=f.bind();f.stage(first);f.commit(first);accepted(f,first);
 const second=f.bind();f.stage(second);f.commit(second);accepted(f,second);
 assert.equal(f.changes,2);assert.equal(f.setters,2);
});

test('ambiguous or externally owned pickers bind the chat and retire only after actual discovery fails',async()=>{
 for(const layout of ['other-form','multiple-global']){
  const f=fixture();f.input.remove();
  if(layout==='other-form')f.body.append(new f.Node('form')).append(f.input);
  else f.body.append(f.input,new f.context.HTMLInputElement());
  const op=f.bind();f.stage(op);
  assert.equal(f.call({action:'validate',target:op.target}).valid,true);
  const refused=(await f.commit(op)).observation;
  assert.equal(refused.preInputRetirement.reason,'attachmentEntryUnavailable');
  assert.equal(refused.preInputRetirement.inputCount,0);
  assert.equal(f.changes,0);assert.equal(f.setters,0);assert.equal(refused.uploadStart,undefined);
 }
});

for(const state of ['disabled','removed'])test('accepted attachment starts immediately while change leaves its picker '+state,()=>{
 const f=fixture(),op=f.bind();f.stage(op);
 f.setChange(()=>{if(state==='disabled')f.input.disabled=true;else f.input.remove();});
 const receipt=f.commit(op).observation;
 assert.equal(receipt.state,'uploadStarted','START must not wait for the next input slot or upload completion');
 accepted(f,op);assert.equal(f.setters,1);assert.equal(f.changes,1);
 assert.equal(f.call({action:'validate',target:op.target}).valid,true,'target binding does not depend on the previous picker');
 assert.ok(f.form.contains(f.oldCard));assert.equal(f.sends,0);
});

for(const state of ['disabled','removed'])test('an unsubmitted operation never starts from a matching card with its picker '+state,async()=>{
 const f=fixture(),op=f.bind();f.stage(op);f.addCard(op.name);
 if(state==='disabled')f.input.disabled=true;else f.input.remove();
 const observed=f.observe(op);assert.equal(observed.state,'unknown');assert.equal(observed.uploadStart,undefined);
 const refused=(await f.commit(op)).observation;
 assert.equal(refused.preInputRetirement.reason,'attachmentEntryUnavailable');
 assert.equal(refused.uploadStart,undefined);assert.equal(f.setters,0);assert.equal(f.changes,0);
});

test('a replacement in an untracked Home draft cannot start the original unconfirmed operation',()=>{
 const f=fixture({accept:false,route:'https://chatgpt.com/'}),op=f.bind();f.stage(op);f.commit(op);
 f.editor.remove();f.form.append(new f.Node('div',{id:'prompt-textarea',contenteditable:'true',role:'textbox'}));
 f.addCard(op.name);
 const observed=f.observe(op);assert.equal(observed.state,'inputTriggered');
 assert.equal(observed.belongsToOriginalDraft,false);assert.equal(observed.uploadStart,undefined);
 assert.equal(f.changes,1);
});

for(const route of [
 'https://chatgpt.com/',
 'https://chatgpt.com/c/ordinary-thread',
 'https://chatgpt.com/g/g-p-local-project/c/thread',
 'https://chatgpt.com/g/g-p-local-project/project',
 'https://chatgpt.com/a-valid-future-chat-path?model=example'
])test(`usable composer accepts PNG at ${new URL(route).pathname}`,()=>{
 const f=fixture({route}),op=f.bind();
 assert.equal(op.target.logicalDraftIdentity,undefined,'no React identity required');
 f.stage(op);f.commit(op);accepted(f,op);assert.equal(f.changes,1);
});

test('a first click initializes its fixed target after Chrome loses focus without any prior page capture',()=>{
 const f=fixture({focused:false,visible:false});
 const op=f.bind();f.stage(op);f.commit(op);accepted(f,op);
 assert.equal(op.target.clickBindingID,undefined,'no earlier click proof or pin is required');
 assert.equal(f.changes,1);
});

test('a changed route cannot receive the screenshot pinned to the previous chat',()=>{
 const f=fixture(),op=f.bind();f.stage(op);
 f.setRoute('https://chatgpt.com/c/different-chat');
 const refused=f.commit(op).observation;
 assert.equal(refused.state,'invalidated');
 assert.equal(refused.preInputRetirement.reason,'targetInvalidBeforeInput');
 assert.equal(f.changes,0);assert.equal(f.setters,0);
 const newOp=f.bind();f.stage(newOp);f.commit(newOp);accepted(f,newOp);
 assert.equal(f.changes,1);
});

test('a replacement Home editor cannot silently inherit an older captured target',()=>{
 const f=fixture({route:'https://chatgpt.com/'}),op=f.bind();f.stage(op);f.editor.remove();
 f.form.append(new f.Node('div',{id:'prompt-textarea',contenteditable:'true',role:'textbox'}));
 const refused=f.commit(op).observation;
 assert.equal(refused.state,'invalidated');
 assert.equal(refused.preInputRetirement.reason,'targetInvalidBeforeInput');
 assert.equal(f.changes,0);
});

test('multiple inputs do not invalidate the chat and discovery never picks an arbitrary tied input',async()=>{
 const f=fixture();f.form.append(new f.context.HTMLInputElement());
 const op=f.bind();f.stage(op);
 const refused=(await f.commit(op)).observation;
 assert.equal(refused.preInputRetirement.reason,'attachmentEntryUnavailable');assert.equal(f.changes,0);
});

test('a preferred current composer is independent of another unrelated editable region',()=>{
 const g=fixture(),other=g.body.append(new g.Node('form'));
 other.append(new g.Node('div',{contenteditable:'true',role:'textbox'}));
 const unrelated=other.append(new g.context.HTMLInputElement());unrelated.applicationAccept=false;
 const op=g.bind();g.stage(op);g.commit(op);accepted(g,op);
 assert.equal(g.changes,1);assert.equal(unrelated.files.length,0);
});

test('disabled input permits discovery while non-ChatGPT host remains invalid',async()=>{
 const f=fixture();f.input.disabled=true;
 const op=f.bind();f.stage(op);const refused=(await f.commit(op)).observation;
 assert.equal(refused.preInputRetirement.reason,'attachmentEntryUnavailable');assert.equal(f.changes,0);
 const g=fixture({route:'https://example.invalid/c/ordinary-thread'});
 assert.throws(()=>g.call({action:'captureTarget'}),/HOST|ROUTE|PAGE|TARGET/);assert.equal(g.changes,0);
});

test('malformed PNG fails before native input and cannot hold the next screenshot',()=>{
 const f=fixture(),bad=f.bind({bytes:Buffer.from('not png')});
 let failed=false;try{f.stage(bad);f.commit(bad);}catch{failed=true;}
 assert.equal(failed,true);assert.equal(f.changes,0);
 const good=f.bind({bytes:png});f.stage(good);f.commit(good);accepted(f,good);assert.equal(f.changes,1);
});

test('current File-derived preview starts even when the application omits visible filenames',()=>{
 const f=fixture({accept:false}),op=f.bind();f.stage(op);f.commit(op);
 const url=f.context.URL.createObjectURL(f.input.files[0]);
 const card=f.addCard('application-preview-without-a-filename',{progress:false}),image=card.querySelector('img');
 image.setAttribute('src',url);image.src=image.currentSrc=url;
 accepted(f,op);assert.equal(f.changes,1);
});

for(const field of ['aria-label','title','alt','text'])test('new attachment can label the complete unique filename with surrounding text: '+field,()=>{
 const f=fixture({accept:false}),op=f.bind();f.stage(op);f.commit(op);
 const card=f.addCard('unrelated-placeholder',{progress:false}),image=card.querySelector('img');
 for(const name of ['data-file-name','title','aria-label'])card.removeAttribute(name);
 image.removeAttribute('alt');
 const label='正在上传 '+op.name+' (PNG image)';
 if(field==='alt')image.setAttribute('alt',label);
 else if(field==='text')card.append(new f.Node('span')).textContent=label;
 else card.setAttribute(field,label);
 accepted(f,op);assert.equal(f.changes,1);
});

test('filename substrings and unrelated previews cannot falsely consume a screenshot',()=>{
 const f=fixture({accept:false}),op=f.bind();f.stage(op);f.commit(op);
 f.addCard('other-'+op.name);f.addCard(op.name+'.other');
 const unrelated=f.addCard('another-file.png');unrelated.append(new f.Node('span')).textContent='Attachment preview';
 assert.equal(f.observe(op).state,'inputTriggered');assert.equal(f.observe(op).uploadStart,undefined);
 assert.equal(f.changes,1);
});

test('staging and discarding an unsubmitted click never dispatch an input',()=>{
 const f=fixture(),op=f.bind();f.stage(op);
 assert.equal(f.setters,0);assert.equal(f.changes,0);
 const result=f.call(op.command('discard'));
 assert.equal(result.discarded,true);assert.equal(result.inputCount,0);
 assert.throws(()=>f.commit(op),/COMMIT_REFUSED/);assert.equal(f.changes,0);
 const next=f.bind();f.stage(next);f.commit(next);accepted(f,next);assert.equal(f.changes,1);
});

for(const attrs of [{role:'alert'},{'data-state':'error'},{'data-state':'failed'}])test('an error attachment cannot masquerade as accepted START '+JSON.stringify(attrs),()=>{
 const f=fixture({accept:false}),op=f.bind();f.stage(op);f.commit(op);
 const card=f.addCard(op.name);card.remove();
 const error=f.form.append(new f.Node('div',attrs));error.append(card);
 assert.equal(f.observe(op).state,'inputTriggered');
 assert.equal(f.observe(op).uploadStart,undefined);
 assert.equal(f.changes,1);
});

test('an error beside a preview cannot bypass START rejection through the nested image',()=>{
 const f=fixture({accept:false}),op=f.bind();f.stage(op);f.commit(op);
 const card=f.addCard(op.name);
 card.append(new f.Node('div',{role:'alert'})).textContent='Upload failed';
 assert.equal(f.observe(op).state,'inputTriggered');
 assert.equal(f.observe(op).uploadStart,undefined);
 assert.equal(f.changes,1);
});

test('an error on an older attachment cannot suppress the new independent attachment START',()=>{
 const f=fixture();
 f.oldCard.append(new f.Node('div',{role:'alert'})).textContent='Previous upload failed';
 const op=f.bind();f.stage(op);f.commit(op);accepted(f,op);
 assert.ok(f.form.contains(f.oldCard));assert.equal(f.changes,1);
});

test('an empty img src is still a placeholder and cannot start the attachment',()=>{
 const f=fixture({accept:false}),op=f.bind();f.stage(op);f.commit(op);
 const card=f.addCard(op.name,{progress:false}),image=card.querySelector('img');
 image.setAttribute('src','');image.src=image.currentSrc='';
 assert.equal(f.observe(op).state,'inputTriggered');
 assert.equal(f.observe(op).uploadStart,undefined);assert.equal(f.changes,1);
});
