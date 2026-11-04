'use strict';
// Behavioral regression of the shipped page program in a controlled application.
// Real native browser primitives are additionally checked by the Chrome suite.
const test=require('node:test');
const assert=require('node:assert/strict');
const {fixture,png}=require('./independent-input-fixture.cjs');

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

test('a sole hidden portal picker belongs to the sole composer without requiring editor focus',()=>{
 const f=fixture({focused:false});f.input.remove();f.body.append(f.input);f.input.rendered=false;
 const first=f.bind();f.stage(first);f.commit(first);accepted(f,first);
 const second=f.bind();f.stage(second);f.commit(second);accepted(f,second);
 assert.equal(f.changes,2);assert.equal(f.setters,2);
});

test('a portal picker in another form or ambiguous global pickers cannot receive the screenshot',()=>{
 const f=fixture();f.input.remove();f.body.append(new f.Node('form')).append(f.input);
 assert.throws(()=>f.bind(),/ATTACHMENT_INPUT_UNAVAILABLE/);assert.equal(f.changes,0);
 const g=fixture();g.input.remove();g.body.append(g.input,new g.context.HTMLInputElement());
 assert.throws(()=>g.bind(),/ATTACHMENT_INPUT_UNAVAILABLE/);assert.equal(g.changes,0);
});

for(const state of ['disabled','removed'])test('accepted attachment starts immediately while change leaves its picker '+state,()=>{
 const f=fixture(),op=f.bind();f.stage(op);
 f.setChange(()=>{if(state==='disabled')f.input.disabled=true;else f.input.remove();});
 const receipt=f.commit(op).observation;
 assert.equal(receipt.state,'uploadStarted','START must not wait for the next input slot or upload completion');
 accepted(f,op);assert.equal(f.setters,1);assert.equal(f.changes,1);
 assert.equal(f.call({action:'validate',target:op.target}).valid,false,'a new input still requires a usable picker');
 assert.ok(f.form.contains(f.oldCard));assert.equal(f.sends,0);
});

for(const state of ['disabled','removed'])test('an unsubmitted operation never starts from a matching card with its picker '+state,()=>{
 const f=fixture(),op=f.bind();f.stage(op);f.addCard(op.name);
 if(state==='disabled')f.input.disabled=true;else f.input.remove();
 const observed=f.observe(op);assert.equal(observed.state,'unknown');assert.equal(observed.uploadStart,undefined);
 const refused=f.commit(op).observation;
 assert.equal(refused.preInputRetirement.reason,'targetInvalidBeforeInput');
 assert.equal(refused.uploadStart,undefined);assert.equal(f.setters,0);assert.equal(f.changes,0);
});

test('a new attachment in a replaced editor cannot start the original unconfirmed operation',()=>{
 const f=fixture({accept:false}),op=f.bind();f.stage(op);f.commit(op);
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

test('a replacement editor cannot silently inherit an older captured target',()=>{
 const f=fixture(),op=f.bind();f.stage(op);f.editor.remove();
 f.form.append(new f.Node('div',{id:'prompt-textarea',contenteditable:'true',role:'textbox'}));
 const refused=f.commit(op).observation;
 assert.equal(refused.state,'invalidated');
 assert.equal(refused.preInputRetirement.reason,'targetInvalidBeforeInput');
 assert.equal(f.changes,0);
});

test('two eligible file inputs or two usable composers refuse before any input',()=>{
 const f=fixture();f.form.append(new f.Node('input',{type:'file',accept:'image/*'}));
 assert.throws(()=>f.call({action:'captureTarget'}),/INPUT|COMPOSER|AMBIGUOUS|TARGET/);
 assert.equal(f.changes,0);
 const g=fixture(),other=g.body.append(new g.Node('form'));
 other.append(new g.Node('div',{contenteditable:'true',role:'textbox'}));
 other.append(new g.Node('input',{type:'file',accept:'image/*'}));
 assert.throws(()=>g.call({action:'captureTarget'}),/INPUT|COMPOSER|AMBIGUOUS|TARGET/);
 assert.equal(g.changes,0);
});

test('disabled input and non-ChatGPT host refuse instead of selecting another chat',()=>{
 const f=fixture();f.input.disabled=true;
 assert.throws(()=>f.call({action:'captureTarget'}),/INPUT|COMPOSER|TARGET/);assert.equal(f.changes,0);
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
 else if(field==='text')card.textContent=label;
 else card.setAttribute(field,label);
 accepted(f,op);assert.equal(f.changes,1);
});

test('filename substrings and unrelated previews cannot falsely consume a screenshot',()=>{
 const f=fixture({accept:false}),op=f.bind();f.stage(op);f.commit(op);
 f.addCard('other-'+op.name);f.addCard(op.name+'.other');
 const unrelated=f.addCard('another-file.png');unrelated.textContent='Attachment preview';
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
