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
function attachmentApplication(f,{dynamic=false,menu=false,pointerOnly=false,delay=0,method='click',externalForm=false,moveSelection=false,acceptAttribute='image/x-png',scheduler='timeout',linksPicker=false}={}) {
 f.input.remove();
 const destination=externalForm?f.body.append(new f.Node('form',{'data-purpose':'portal-root'})):f.body;
 let picker=dynamic?null:destination.append(f.input),entryCount=0,uploadCount=0;
 const prepare=()=>{
  if(!picker){picker=destination.append(new f.context.HTMLInputElement());picker.rendered=false;}
  picker.setAttribute('accept',acceptAttribute);
  if (linksPicker) {
   picker.setAttribute('id','selected-local-picker');
   action.setAttribute('aria-controls',picker.id);
  }
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
 let action=entry;
 entry.textContent=menu?'+':'Attach files';
 entry.addEventListener(pointerOnly?'pointerdown':'click',()=>{
  entryCount++;
  if(!menu){upload();return;}
  const popup=f.body.append(new f.Node('div',{role:'menu'}));
  const choice=popup.append(new f.Node('button',{role:'menuitem',type:'button'}));choice.textContent='Upload from computer';
  action=choice;
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

 const f=fixture(),app=attachmentApplication(f,{dynamic:true,menu:true,externalForm:true,delay:35,moveSelection:true,linksPicker:true});
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
 const f=fixture(),app=attachmentApplication(f,{dynamic:true,externalForm:true,delay:100,linksPicker:true});
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
 const f=fixture(),app=attachmentApplication(f,{dynamic:true,externalForm:true,linksPicker:true,scheduler,delay:30,method:'showPicker'});
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
  this.setAttribute('aria-controls',picker.id);
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
 const f=fixture(),app=attachmentApplication(f,{dynamic:true,externalForm:true,delay:100,linksPicker:true});
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

test('a local failure belongs only to its accepted card in the original draft', async () => {
 const f=fixture(), a=f.bind(), b=f.bind();
 for(const op of [a,b]) { f.stage(op); await f.commit(op); }
 const start=accepted(f,a), card=f.document.querySelectorAll('[data-file-name]').find(n=>n.getAttribute('data-file-name')===a.name);
 card.setAttribute('data-state','failed');
 const failed=f.observe(a);
 assert.equal(failed.state,'failed'); assert.equal(failed.attachmentID,start.attachmentID);
 assert.equal(failed.hasError,true); assert.equal(failed.automaticRetryExcluded,false);
 assert.equal(failed.attachmentAbsent,false); assert.equal(failed.uploadStart,undefined);
 accepted(f,b);
 card.removeAttribute('data-state');
 f.form.append(new f.Node('div',{role:'alert','data-state':'error'}));
 accepted(f,a);
 card.setAttribute('data-state','failed'); card.setAttribute('data-file-name','other.png');
 accepted(f,a);
 card.setAttribute('data-file-name',a.name); f.setRoute('https://chatgpt.com/c/other');
 accepted(f,a);
 assert.equal(f.setters,2); assert.equal(f.changes,2); assert.equal(f.sends,0);
});

test('a portalled card can report failure only in its original draft and placement', () => {
 const f=fixture({accept:false}), op=f.bind();
 f.stage(op); f.commit(op);
 const portal=f.body.append(new f.Node('section'));
 const card=portal.append(f.addCard(op.name));
 const start=accepted(f,op);
 card.setAttribute('data-state','error');
 const failure=f.observe(op);
 assert.equal(failure.state,'failed'); assert.equal(failure.attachmentID,start.attachmentID);
 assert.equal(failure.automaticRetryExcluded,false); assert.equal(failure.attachmentAbsent,false);
 const otherForm=f.body.append(new f.Node('form'));
 otherForm.append(portal); accepted(f,op);
 f.body.append(portal);
 f.body.append(card); accepted(f,op);
 portal.append(card);
 f.setRoute('https://chatgpt.com/c/another'); accepted(f,op);
 assert.equal(f.setters,1); assert.equal(f.changes,1); assert.equal(f.sends,0);
});

test('START releases strong composer references and expired reads retain a replay fence', async () => {
 const f=fixture(), callbacks=[];
 f.context.setTimeout=(callback,ms)=>ms===600000 ? (callbacks.push(callback),0) : setTimeout(callback,ms);
 const first=f.bind();
 for(let i=0;i<101;i++) { const op=i===0?first:f.bind(); f.stage(op); await f.commit(op); }
 const registry=vm.runInContext('globalThis.__riftletIndependentFileInput20261104',f.context);
 f.input.remove();
 assert.ok(!Object.values(registry.current).includes(f.input), 'no retained detached file picker');
 for(const op of registry.operations.values()) {
   assert.equal(op.binding,null); assert.equal(op.chunks.length,0);
 }
 vm.runInContext('Date.now = () => Number.MAX_SAFE_INTEGER', f.context);
 for(const expire of callbacks) expire();
 assert.equal(registry.operations.size,101);
 for(const value of registry.operations.values()) assert.deepEqual(Object.keys(value),['committed']);
 assert.equal(f.observe(first).state,'invalidated');
 assert.throws(()=>f.stage(first),/BEGIN_REFUSED/);
 assert.throws(()=>f.commit(first),/ORIGINAL_OPERATION_REQUIRED/);
 assert.equal(f.setters,101); assert.equal(f.changes,101); assert.equal(f.sends,0);
});

test('history links use only the exact canonical saved conversation path', () => {
 const id='00000000-0000-4000-8000-000000000ABC';
 for (const [route,expected] of [
  ['https://chatgpt.com/c/'+id.toLowerCase()+'?x=1#z',id],
  ['https://chatgpt.com/',undefined],['https://chatgpt.com/c/other',undefined],
  ['https://chatgpt.com/g/other/c/'+id,id],['https://chatgpt.com/g/%2F/c/'+id,undefined],['https://chat.openai.com/c/'+id,undefined]]) {
  const target=fixture({route}).call({action:'captureTarget'});
  assert.equal(target.historyConversationID,expected);
  assert.equal(target.logicalDraftIdentity,undefined);
 }
});

for (const attribute of ['aria-label', 'title', 'alt']) test('post-START error on the originally labelled view: '+attribute, () => {
 const f=fixture({accept:false}), op=f.bind(); f.stage(op); f.commit(op);
 const card=f.addCard('placeholder'), image=card.querySelector('img');
 for(const key of ['data-file-name','aria-label','title']) card.removeAttribute(key);
 image.removeAttribute('alt');
 const witness=attribute==='alt' ? image : card, label='Uploading '+op.name+' (PNG)';
 witness.setAttribute(attribute,label);
 const start=accepted(f,op);
 card.setAttribute('data-state','failed');
 const error=f.observe(op);
 assert.equal(error.state,'failed'); assert.equal(error.attachmentID,start.attachmentID);
 assert.equal(error.automaticRetryExcluded,false); assert.equal(error.attachmentAbsent,false);
 witness.setAttribute(attribute,'other-'+op.name); accepted(f,op);
 witness.setAttribute(attribute,label); image.setAttribute('src','blob:replacement'); accepted(f,op);
 card.remove(); const replacement=f.addCard(op.name); replacement.setAttribute('data-state','failed'); accepted(f,op);
 assert.equal(f.setters,1); assert.equal(f.changes,1); assert.equal(f.sends,0);
});

test('a second START-time view needs the original File object URL to report a scoped error', () => {
 const f=fixture({accept:false}), op=f.bind(); f.stage(op); f.commit(op);
 const first=f.addCard(op.name), sameName=f.addCard(op.name), sameFile=f.addCard(op.name);
 const container=f.form.append(new f.Node('section')); container.append(sameFile);
 const fileURL=f.context.URL.createObjectURL(f.input.files[0]);
 sameFile.querySelector('img').setAttribute('src',fileURL);
 const start=accepted(f,op);
 sameName.setAttribute('data-state','error'); accepted(f,op);
 const after=f.addCard(op.name); after.querySelector('img').setAttribute('src',fileURL);
 after.setAttribute('data-state','failed'); accepted(f,op);
 first.append(new f.Node('span',{'role':'alert','data-file-name':op.name,'data-state':'failed'})); accepted(f,op);
 sameFile.setAttribute('data-state','failed');
 const error=f.observe(op);
 assert.equal(error.state,'failed'); assert.equal(error.attachmentID,start.attachmentID);
 assert.equal(error.automaticRetryExcluded,false); assert.equal(error.attachmentAbsent,false);
 const otherComposer=f.form.append(new f.Node('div',{'data-chatgpt-composer':'1'}));
 otherComposer.append(container); accepted(f,op); f.form.append(container);
 sameFile.querySelector('img').setAttribute('src','blob:other'); accepted(f,op);
 assert.equal(f.setters,1); assert.equal(f.changes,1); assert.equal(f.sends,0);
});

test('a nested error is limited to the original named preview, not a newly inserted same-name node', () => {
 const f=fixture(), op=f.bind(); f.stage(op); f.commit(op); const start=accepted(f,op);
 const card=f.document.querySelectorAll('[data-file-name]').find(n=>n.getAttribute('data-file-name')===op.name);
 const old=card.querySelector('img'), replacement=new f.Node('img',{...old.attrs,'data-state':'failed'});
 card.append(replacement); accepted(f,op);
 old.setAttribute('data-state','failed');
 const error=f.observe(op); assert.equal(error.state,'failed'); assert.equal(error.attachmentID,start.attachmentID);
 old.setAttribute('alt','another.png'); accepted(f,op);
 old.remove(); accepted(f,op);
 assert.equal(f.setters,1); assert.equal(f.changes,1); assert.equal(f.sends,0);
});

test('post-START watches retain neither inline pixels nor unbounded preview addresses', () => {
 const f=fixture({accept:false}), op=f.bind(); f.stage(op); f.commit(op);
 const large='x'.repeat(1024*1024);
 for(const src of ['data:image/png;base64,'+large,'blob:'+large,'https://example.invalid/preview?token=unused']) {
  const card=f.addCard(op.name); card.querySelector('img').setAttribute('src',src);
 }
 accepted(f,op);
 const registry=vm.runInContext('globalThis.__riftletIndependentFileInput20261104',f.context);
 const views=registry.operations.get(op.identity.operationID).failureWatch.views;
 assert.equal(views.length,1); assert.equal(views[0].src,undefined);
 assert.equal(views[0].preview,null);
});

test('an original blob left behind during a component rebind cannot borrow the new upload’s error', () => {
 const f=fixture({accept:false}), a=f.bind(), b=f.bind(); f.stage(a); f.commit(a);
 const card=f.addCard(a.name), image=card.querySelector('img');
 card.removeAttribute('data-file-name'); card.removeAttribute('title');
 image.setAttribute('src',f.context.URL.createObjectURL(f.input.files[0]));
 const start=accepted(f,a);
 card.setAttribute('data-state','failed');
 assert.equal(f.observe(a).state,'failed');
 for(const [node,attr] of [[card,'aria-label'],[card,'title'],[image,'alt']]) {
  const was=node.getAttribute(attr);
  node.setAttribute(attr,'Uploading '+b.name);
  accepted(f,a);
  if(was===null)node.removeAttribute(attr);else node.setAttribute(attr,was);
 }
 const message=card.append(new f.Node('span')); message.textContent=b.name;
 accepted(f,a); message.remove();
 const left=card.append(new f.Node('span')), right=card.append(new f.Node('span'));
 left.textContent=b.name.slice(0,18); right.textContent=b.name.slice(18);
 accepted(f,a); left.remove(); right.remove();
 const secondPreview=card.append(new f.Node('img',{alt:b.name}));
 accepted(f,a); secondPreview.remove();
 card.setAttribute('aria-label',b.name); image.setAttribute('alt',b.name);
 accepted(f,a);
 assert.equal(f.observe(a).attachmentID,start.attachmentID); assert.equal(f.setters,1); assert.equal(f.sends,0);
});

test('an unlabelled original File preview still supports its own explicit card failure', () => {
 const f=fixture({accept:false}), op=f.bind(); f.stage(op); f.commit(op);
 const card=f.addCard(op.name), image=card.querySelector('img');
 for(const key of ['data-file-name','title','aria-label'])card.removeAttribute(key);
 image.removeAttribute('alt'); image.setAttribute('src',f.context.URL.createObjectURL(f.input.files[0]));
 const start=accepted(f,op); card.setAttribute('data-state','failed');
 const error=f.observe(op); assert.equal(error.state,'failed'); assert.equal(error.attachmentID,start.attachmentID);
 assert.equal(error.automaticRetryExcluded,false); assert.equal(f.setters,1); assert.equal(f.sends,0);
});

test('a retained v18 watch can report its own error but conflicting labels veto that hint', () => {
 const f=fixture(), a=f.bind(), b=f.bind(); f.stage(a); f.commit(a);
 const card=f.document.querySelectorAll('[data-file-name]').find(n=>n.getAttribute('data-file-name')===a.name);
 const registry=vm.runInContext('globalThis.__riftletIndependentFileInput20261104',f.context);
 registry.operations.get(a.identity.operationID).failureWatch={binding:new WeakRef(registry.current),card:new WeakRef(card),portalParent:null};
 card.setAttribute('data-state','failed'); assert.equal(f.observe(a).state,'failed');
 card.querySelector('img').setAttribute('alt',b.name); accepted(f,a);
 card.querySelector('img').setAttribute('alt',a.name);
 const otherComposer=f.form.append(new f.Node('section'));
 otherComposer.setAttribute('data-chatgpt-composer','');
 otherComposer.append(card); accepted(f,a);
 assert.equal(f.setters,1); assert.equal(f.sends,0);
});

test('on-demand reconciliation binds the original invocation, draft and living attachment card', async () => {
 const f=fixture(), op=f.bind();
 f.stage(op); await f.commit(op);
 const original=op.command('observe');
 const inspect=extra=>f.call({...original,requireLiveOriginal:true,...extra}).observation;
 const card=f.document.querySelectorAll('[data-file-name]').find(n=>n.getAttribute('data-file-name')===op.name);
 assert.equal(inspect().state,'uploadStarted');
 assert.equal(inspect({invocationID:'00000000-0000-4000-8000-000000000000'}).state,'invalidated');
 card.setAttribute('data-state','failed');
 assert.equal(inspect().state,'failed');
 card.setAttribute('data-file-name','other.png');
 assert.equal(inspect().state,'invalidated');
 card.setAttribute('data-file-name',op.name);
 f.setRoute('https://chatgpt.com/c/other');
 assert.equal(inspect().state,'invalidated');
 assert.equal(f.observe(op).state,'uploadStarted');
 assert.equal(f.setters,1); assert.equal(f.changes,1); assert.equal(f.sends,0);
});


test('returning to an existing hidden temporary draft validates the same editor without input', () => {
 const f = fixture({route: 'https://chatgpt.com/?temporary-chat=true'});
 const target = f.call({action: 'captureTarget'});
 f.document.visibilityState = 'hidden';
 f.setFocused(false);
 assert.equal(f.call({action: 'validate', target}).valid, true);
 f.setRoute('https://chatgpt.com/c/9479e823-49e9-4d49-8822-b9ec96410c96');
 assert.equal(f.call({action: 'validate', target}).valid, false);
 assert.deepEqual([f.setters, f.changes, f.sends], [0, 0, 0]);
});

test('an existing meter starts only when the current file owns its visible advancing progress',()=>{
 const f=fixture({accept:false}),op=f.bind(),other=f.bind();
 const card=f.addCard(other.name,{placeholder:true,progress:true}), meter=card.querySelector('[role="progressbar"]');
 f.stage(op);f.commit(op);
 for(const key of ['data-file-name','aria-label','title'])card.setAttribute(key,op.name);
 assert.equal(f.observe(op).state,'inputTriggered');
 meter.setAttribute('aria-valuemax','50');
 meter.setAttribute('aria-valuenow','30');
 assert.equal(f.observe(op).state,'inputTriggered');
 meter.setAttribute('aria-valuemax','100');
 meter.setAttribute('aria-valuenow','5');
 assert.equal(f.observe(op).state,'inputTriggered');
 meter.setAttribute('aria-valuenow','40');meter.rendered=false;
 assert.equal(f.observe(op).state,'inputTriggered');
 meter.rendered=true;const start=accepted(f,op);
 meter.remove();
 const feedback=card.append(new f.Node('span'));
 feedback.textContent='上传未成功';feedback.rendered=false;
 accepted(f,op);feedback.rendered=true;
 const failure=f.observe(op);assert.equal(failure.state,'failed');assert.equal(failure.attachmentID,start.attachmentID);
 assert.equal(failure.automaticRetryExcluded,false);assert.equal(f.setters,1);assert.equal(f.sends,0);
});

test('visible failure belongs only to the original attachment, including a replaced shell retaining the exact File preview',()=>{
 const f=fixture({accept:false}), op=f.bind(), other=f.bind();
 f.stage(op);f.commit(op);
 const card=f.addCard(op.name), image=card.querySelector('img');
 image.setAttribute('src',f.context.URL.createObjectURL(f.input.files[0]));
 const start=accepted(f,op);
 const neighbor=f.addCard(other.name);
 neighbor.append(new f.Node('span')).textContent='上传未成功';
 const action=card.append(new f.Node('button'));action.textContent='上传未成功';
 accepted(f,op);action.remove();
 card.remove();
 const replacement=f.addCard(op.name);
 const message=replacement.append(new f.Node('span'));message.textContent='上传未成功';
 // A matching filename and status on another DOM card cannot replace the witness.
 accepted(f,op);
 replacement.querySelector('img').remove();replacement.append(image);
 const failure=f.observe(op);assert.equal(failure.state,'failed');assert.equal(failure.attachmentID,start.attachmentID);
 replacement.setAttribute('title',other.name);accepted(f,op);
 assert.equal(f.changes,1);assert.equal(f.sends,0);
});

test('a non-blob preview keeps the same local member across a named text-only failure',()=>{
 function mount() {
  const f=fixture({accept:false}), op=f.bind();
  f.stage(op);f.commit(op);
  const shell=f.form.append(new f.Node('div'));
  const image=shell.append(new f.Node('img',{alt:op.name,src:'/opaque-image'}));
  const start=accepted(f,op);
  return {f,op,shell,image,start};
 }
 const {f,op,shell,image,start}=mount();
 const sibling=f.form.append(new f.Node('div'));
 sibling.append(new f.Node('span')).textContent='上传未成功';
 sibling.append(new f.Node('span')).textContent=op.name;
 assert.equal(f.call({...op.command('observe'),requireLiveOriginal:true}).observation.state,'uploadStarted');
 accepted(f,op);
 image.remove();shell.append(new f.Node('span')).textContent='上传未成功';
 const file=shell.append(new f.Node('span')); file.textContent=op.name;
 const failed=f.observe(op);assert.equal(failed.state,'failed');assert.equal(failed.attachmentID,start.attachmentID);
 shell.remove();accepted(f,op);
 const reused=mount();
 reused.image.remove();reused.shell.append(new reused.f.Node('img',{alt:'other.png',src:'/other'})).remove();
 reused.shell.append(new reused.f.Node('span')).textContent=reused.op.name;
 reused.shell.append(new reused.f.Node('span')).textContent='上传未成功';
 accepted(reused.f,reused.op);
 for(const key of ['src','alt']) {
  const {f,op,shell,image}=mount();
  image.setAttribute(key,key==='alt'?'another.png':'/new-preview');
  image.remove();
  shell.append(new f.Node('span')).textContent=op.name;
  shell.append(new f.Node('span')).textContent='上传未成功';
  accepted(f,op);assert.equal(f.setters,1);assert.equal(f.sends,0);
 }
});

test('a stale named A card cannot claim B’s exact File URL or its failure',()=>{
 const f=fixture(), a=f.bind(), b=f.bind();
 f.stage(a);f.commit(a);
 const start=accepted(f,a);
 const card=f.form.querySelectorAll('[data-file-name]').find(n=>n.getAttribute('data-file-name')===a.name);
 f.stage(b);f.commit(b);
 card.querySelector('img').setAttribute('src',f.context.URL.createObjectURL(f.input.files[0]));
 card.append(new f.Node('span')).textContent='上传失败';
 accepted(f,a);accepted(f,b);
 assert.equal(f.observe(a).attachmentID,start.attachmentID);assert.equal(f.changes,2);assert.equal(f.sends,0);
});

test('a progress-only A member cannot borrow the later B preview under its old label',()=>{
 const f=fixture({accept:false}), a=f.bind(), b=f.bind();
 f.stage(a);f.commit(a);
 const card=f.addCard(a.name,{placeholder:true,progress:true});const start=accepted(f,a);
 f.stage(b);f.commit(b);
 const preview=card.append(new f.Node('img',{src:f.context.URL.createObjectURL(f.input.files[0])}));
 card.append(new f.Node('span')).textContent='上传失败';
 accepted(f,a);preview.remove();accepted(f,a);
 assert.equal(f.observe(a).attachmentID,start.attachmentID);assert.equal(f.setters,2);assert.equal(f.sends,0);
});

test('two render turns between native reads preserve positive original START and its current error',async()=>{
 const f=fixture({accept:false}),a=f.bind(),b=f.bind();
 for(const op of [a,b]){f.stage(op);assert.equal(f.commit(op).observation.state,'inputTriggered');}
 const first=f.addCard(a.name),second=f.addCard(b.name);
 await new Promise(done=>setImmediate(done));
 first.setAttribute('data-state','failed');
 const read=()=>f.call({...a.command('observe'),preferStartReceipt:true,requireLiveOriginal:true}).observation;
 const start=read(),afterLostReply=read(),error=f.observe(a);
 assert.equal(start.state,'uploadStarted');assert.equal(start.uploadStart.evidenceID,afterLostReply.uploadStart.evidenceID);
 assert.equal(error.state,'failed');assert.equal(start.attachmentID,error.attachmentID);
 assert.equal(error.automaticRetryExcluded,false);assert.equal(error.attachmentAbsent,false);
 assert.equal(f.observe(b).state,'uploadStarted');
 first.removeAttribute('data-state');assert.equal(f.observe(a).state,'uploadStarted');
 assert.notEqual(second,first);assert.equal(f.setters,2);assert.equal(f.changes,2);assert.equal(f.sends,0);
});

for(const mode of ['placeholder','hidden','already-failed','foreign-image','navigation','expiry']){
 test('background handoff sampling declines '+mode,async()=>{
  const f=fixture({accept:false}),op=f.bind();let expire;
  const nativeTimer=f.context.setTimeout;
  f.context.setTimeout=(fn,ms)=>ms===10000?(expire=fn,0):nativeTimer(fn,ms);
  f.stage(op);f.commit(op);
  if(mode==='expiry')expire();
  if(mode==='navigation')f.setRoute('https://chatgpt.com/c/different-draft');
  const card=f.addCard(op.name,{placeholder:mode==='placeholder',progress:false});
  if(mode==='hidden')card.rendered=false;
  if(mode==='foreign-image')card.querySelector('img').setAttribute('alt','riftlet-11111111-1111-1111-1111-111111111111.png');
  if(mode==='already-failed')card.setAttribute('data-state','failed');
  await new Promise(done=>setImmediate(done));
  card.setAttribute('data-state','failed');
  const result=f.call({...op.command('observe'),preferStartReceipt:true}).observation;
  assert.notEqual(result.state,'uploadStarted');assert.equal(result.uploadStart,undefined);
  assert.equal(f.setters,1);assert.equal(f.changes,1);assert.equal(f.sends,0);
 });
}

for(const path of ['commit','native-read','mutation']){
 test('START ownership in '+path+' excludes unrelated or ambiguous members',async()=>{
  for(const kind of ['hidden','foreign-label','zero','indeterminate','help','keyboard-action','foreign-blob','multiple-anonymous','wrong-composer','nested-only-name']){
   const f=fixture({accept:false}),b=f.bind(),a=f.bind();
   f.stage(b);f.commit(b);
   const foreign=f.context.URL.createObjectURL(f.input.files[0]);
   const add=()=>{
    const card=f.addCard(a.name,{placeholder:true,progress:false});
    const image=(parent,src,alt)=>parent.append(new f.Node('img',alt?{src,alt}:{src}));
    if(kind==='zero'||kind==='indeterminate')card.append(new f.Node('div',kind==='zero'?{role:'progressbar','aria-valuenow':'0'}:{role:'progressbar'}));
    else if(kind==='help')image(card.append(new f.Node('button',{'aria-label':'Help'})),'/help-icon','Help');
    else if(kind==='keyboard-action')image(card.append(new f.Node('span',{tabindex:'0','aria-label':'Help'})),'/help-icon');
    else if(kind==='multiple-anonymous'){image(card,'/one');image(card,'/two');}
    else if(kind==='nested-only-name'){
     for(const key of ['data-file-name','title','aria-label'])card.removeAttribute(key);
     card.append(new f.Node('button')).textContent=a.name;image(card,'/anonymous');
    }else {
     const img=image(card,kind==='foreign-blob'?foreign:'/preview',kind==='foreign-label'?b.name:a.name);
     if(kind==='hidden')img.rendered=false;
     if(kind==='wrong-composer')f.body.append(new f.Node('form')).append(card);
    }
    return card;
   };
   f.stage(a);let result;
   if(path==='commit'){f.setChange(add);result=f.commit(a).observation;}
   else {
    f.commit(a);const card=add();
    if(path==='mutation'){await new Promise(done=>setImmediate(done));card.setAttribute('data-state','failed');}
    result=f.call({...a.command('observe'),preferStartReceipt:true}).observation;
   }
   assert.equal(result.state,'inputTriggered',kind);assert.equal(result.uploadStart,undefined,kind);
   assert.deepEqual([f.setters,f.changes,f.sends],[2,2,0],kind);
  }
 });
}

test('nested decorative icons do not replace the independently named original preview',async()=>{
 const f=fixture({accept:false}),a=f.bind(),b=f.bind();f.stage(a);f.commit(a);
 const card=f.addCard(a.name,{placeholder:true,progress:false}),help=card.append(new f.Node('button',{'aria-label':'Help'}));
 help.append(new f.Node('img',{src:'/help-icon',alt:'Help'}));
 card.append(new f.Node('img',{src:'/decorative'}));
 const image=card.append(new f.Node('img',{src:f.context.URL.createObjectURL(f.input.files[0]),alt:a.name}));
 const start=accepted(f,a);image.setAttribute('data-state','failed');
 const error=f.observe(a);assert.equal(error.state,'failed');assert.equal(error.attachmentID,start.attachmentID);
 f.stage(b);f.commit(b);const portal=f.body.append(new f.Node('section'));portal.append(f.addCard(b.name));
 const next=accepted(f,b);assert.notEqual(next.attachmentID,start.attachmentID);
 assert.deepEqual([f.setters,f.changes,f.sends],[2,2,0]);
});

for(const count of [65,257,513,1025])test('current File and evicted foreign URL ownership at URL count '+count,()=>{
 const f=fixture({accept:false}),a=f.bind();f.stage(a);f.commit(a);
 let retainedForeign,last;
 for(let i=0;i<count;i++){
  last=f.context.URL.createObjectURL(f.input.files[0]);
  if(i===0)retainedForeign=last;
 }
 const card=f.addCard(a.name,{progress:false}),image=card.querySelector('img');
 for(const key of ['data-file-name','title','aria-label'])card.removeAttribute(key);
 image.removeAttribute('alt');image.setAttribute('src',last);
 const original=accepted(f,a);card.setAttribute('data-state','failed');
 assert.equal(f.observe(a).attachmentID,original.attachmentID);assert.equal(f.observe(a).state,'failed');
 const b=f.bind();f.stage(b);f.commit(b);const second=f.addCard(b.name,{progress:false}),next=second.querySelector('img');
 next.setAttribute('src',retainedForeign);assert.equal(f.observe(b).state,'inputTriggered');
 next.setAttribute('src','blob:unwitnessed-older-url');assert.equal(f.observe(b).state,'inputTriggered');
 next.setAttribute('src',f.context.URL.createObjectURL(new Blob(['derived B'])));accepted(f,b);
 assert.deepEqual([f.setters,f.changes,f.sends],[2,2,0]);
});

for(const [label,expected] of [['Image preview',true],['上传图片的预览',true],['Help',false],['Logo',false]]){
 test('single directly owned named member with image description '+label,()=>{
  const f=fixture({accept:false}),op=f.bind();f.stage(op);f.commit(op);
  const card=f.addCard(op.name,{progress:false});card.querySelector('img').setAttribute('alt',label);
  assert.equal(f.observe(op).state,expected?'uploadStarted':'inputTriggered');assert.equal(f.setters,1);
 });
}
