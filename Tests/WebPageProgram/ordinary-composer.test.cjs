'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {fixture} = require('./independent-input-fixture.cjs');

test('unfocused marked composer with the ordinary four Chinese file controls receives each PNG on its general attachment input', async () => {
  const f = fixture({focused: false});
  f.form.setAttribute('data-composer-placement', 'bottom');
  f.editor.removeAttribute('id'); f.editor.removeAttribute('role');
  f.editor.setAttribute('aria-label', '询问 ChatGPT');
  f.editor.setAttribute('class','ProseMirror');
  const extra = f.body.append(new f.Node('div', {contenteditable: 'true', 'aria-label': '询问 ChatGPT'}));
  f.document.activeElement = f.body;
  f.input.remove();
  const decoys = [['image/*','拍照'], ['image/*,video/*','附加照片或视频'], ['image/*','添加照片']].map(([accept,label])=>{
    const field=f.form.append(new f.context.HTMLInputElement());
    field.setAttribute('accept',accept); field.setAttribute('aria-label',label); field.rendered=false;
    if(label==='拍照')field.setAttribute('capture','environment');else field.setAttribute('multiple','');
    field.applicationAccept=false;
    return field;
  });
  f.form.append(f.input);
  f.input.setAttribute('accept',''); f.input.setAttribute('multiple','');
  f.input.setAttribute('aria-label','附加文件'); f.input.rendered=false;
  const plus=f.form.append(new f.Node('button', {type:'button','aria-label':'添加文件等内容'}));
  let opens=0; plus.addEventListener('click',()=>opens++);
  for(let n=1;n<=5;n++){
    const op=f.bind(); f.stage(op); const result=await f.commit(op);
    assert.equal(result.observation.state,'uploadStarted');
    assert.equal(f.input.files[0].name,op.name);
    assert.deepEqual(Buffer.from(await f.input.files[0].arrayBuffer()),op.bytes);
    assert.equal(f.input.setterCount,n); assert.equal(f.changes,n);
  }
  assert.equal(opens,0); assert.equal(f.sends,0);
  assert.ok(f.body.contains(extra)); assert.ok(f.form.contains(f.oldCard));
  assert.ok(decoys.every(field=>field.setterCount===0&&field.changeCount===0));
});

test('a wrapper textbox does not hide the actual nested editing host and its form-free sibling picker', async () => {
  const f=fixture();
  const composer=f.body.append(new f.Node('section'));
  const wrapper=composer.append(new f.Node('div',{role:'textbox'}));
  wrapper.append(f.editor); composer.append(f.input); f.form.remove();
  f.input.addEventListener('change',()=>{
    const name=f.input.files[0].name;
    const card=composer.append(new f.Node('div',{'data-file-name':name}));
    card.append(new f.Node('img',{alt:name,src:'blob:synthetic'}));
  });
  const op=f.bind(); f.stage(op);
  assert.equal((await f.commit(op)).observation.state,'uploadStarted');
  assert.equal(f.input.setterCount,1);
});

test('two independent equally plausible composers do not write a file',()=>{
  const f=fixture();f.editor.removeAttribute('id');f.document.activeElement=f.body;
  const other=f.body.append(new f.Node('form'));
  other.append(new f.Node('div',{contenteditable:'true',role:'textbox'}));
  other.append(new f.context.HTMLInputElement());
  assert.throws(()=>f.call({action:'captureTarget'}),/AMBIGUOUS_COMPOSER/);
  assert.equal(f.setters,0);
});

test('a replaced editor in the same persisted chat and composer still accepts its clicked screenshot', async () => {
  const f=fixture(),op=f.bind();f.stage(op);
  f.editor.remove();f.form.append(new f.Node('div',{id:'prompt-textarea',contenteditable:'true',role:'textbox'}));
  assert.equal((await f.commit(op)).observation.state,'uploadStarted');
  assert.equal(f.setters,1);assert.equal(f.changes,1);
});

test('ordinary clicks arriving together during async picker discovery are both delivered, in order, before either upload completes', async ()=>{
  const f=fixture({accept:false});
  f.input.remove();const portal=f.body.append(new f.Node('section',{id:'files-panel'}));portal.hidden=true;
  const entry=f.form.append(new f.Node('button',{type:'button','aria-label':'Attach files','aria-controls':'files-panel'}));
  entry.addEventListener('click',()=>{portal.hidden=false;setTimeout(()=>portal.append(f.input),15);});
  const received=[];f.input.addEventListener('change',()=>{
    received.push(f.input.files[0].name);f.input.remove();portal.hidden=true;
  });
  const ops=[f.bind(),f.bind()];for(const op of ops)f.stage(op);
  const results=await Promise.all(ops.map(op=>f.commit(op)));
  assert.deepEqual(received,ops.map(op=>op.name));
  assert.deepEqual(results.map(r=>r.observation.state),['inputTriggered','inputTriggered']);
  assert.equal(f.setters,2);assert.equal(f.changes,2);
  for(const op of ops){f.addCard(op.name);assert.equal(f.observe(op).state,'uploadStarted');}
});

test('an accepted preview in a reused slot can start, but renaming an unchanged old preview cannot',()=>{
  const f=fixture({accept:false}),op=f.bind();
  const slot=f.addCard('previous-slot.png'), image=slot.querySelector('img');
  f.stage(op);f.commit(op);
  slot.setAttribute('data-file-name',op.name);image.setAttribute('alt',op.name);
  assert.equal(f.observe(op).state,'inputTriggered');
  image.setAttribute('src',f.context.URL.createObjectURL(f.input.files[0]));
  assert.equal(f.observe(op).state,'uploadStarted');
  assert.equal(f.setters,1);
});

test('two real previews of the same exact submitted File require only one START',()=>{
  const f=fixture({accept:false}),op=f.bind();f.stage(op);f.commit(op);
  f.addCard(op.name);f.addCard(op.name);
  const one=f.observe(op);
  assert.equal(one.state,'uploadStarted');
  assert.equal(f.observe(op).uploadStart.evidenceID,one.uploadStart.evidenceID);
  assert.equal(f.setters,1);
});

test('only the actually displayed editor wins a tie between distinct mounted composer forms',()=>{
  const f=fixture();
  f.editor.removeAttribute('id');f.document.activeElement=f.body;
  const other=f.body.append(new f.Node('form')), mirror=other.append(new f.Node('div',{contenteditable:'true',role:'textbox'}));
  const otherInput=other.append(new f.context.HTMLInputElement());
  f.context.innerWidth=600;f.context.innerHeight=400;
  f.document.elementFromPoint=()=>f.editor;
  const op=f.bind();f.stage(op);assert.equal(f.commit(op).observation.state,'uploadStarted');
  assert.equal(f.input.setterCount,1);assert.equal(otherInput.setterCount,0);assert.ok(other.contains(mirror));
});

test('several editor representations of one marked composer share its same real attachment field',()=>{
  const f=fixture();f.editor.removeAttribute('id');f.document.activeElement=f.body;
  f.form.setAttribute('data-composer-placement','bottom');
  f.form.append(new f.Node('div',{contenteditable:'true',role:'textbox'}));
  const op=f.bind();f.stage(op);
  assert.equal(f.commit(op).observation.state,'uploadStarted');assert.equal(f.input.setterCount,1);
});

test('an error for the same submitted file in the second attachment view cannot appear as START',()=>{
  const f=fixture({accept:false}),op=f.bind();f.stage(op);f.commit(op);
  f.addCard(op.name);const failed=f.addCard(op.name);
  failed.setAttribute('data-state','error');
  assert.equal(f.observe(op).state,'inputTriggered');assert.equal(f.observe(op).uploadStart,undefined);
});

for(const canonicalAside of [false,true]){
  test('a focused independent search cannot borrow upload capability from another real composer: '+canonicalAside,()=>{
    const f=fixture(), main=f.body.append(new f.Node(canonicalAside?'aside':'main'));
    main.append(f.form);
    if(!canonicalAside){f.editor.removeAttribute('id');f.editor.removeAttribute('role');}
    const plus=f.form.append(new f.Node('button',{type:'button','data-testid':'composer-plus-button','aria-label':'Add files'}));
    let opens=0;plus.addEventListener('click',()=>opens++);
    const search=f.body.append(new f.Node('form')).append(new f.Node('textarea',{role:'textbox','aria-label':'Search history'}));
    search.focus();
    const op=f.bind();f.stage(op);const got=f.commit(op).observation;
    assert.equal(got.state,'uploadStarted');assert.equal(f.input.setterCount,1);assert.equal(opens,0);
    assert.equal(f.document.activeElement,search);
  });
}

test('revalidation during a synchronous wrapper rebuild releases the original lock and preserves later clicks',()=>{
  const f=fixture(),original=f.form,op=f.bind();f.stage(op);
  f.setChange(()=>{
    f.setChange(null);
    const replacement=f.body.append(new f.Node('form'));
    replacement.append(f.editor,f.input);original.remove();
    assert.equal(f.call({action:'validate',target:op.target}).valid,true);
  });
  // The first receipt can stay pending across this application render.
  f.commit(op);assert.equal(f.setters,1);
  f.body.append(original);original.append(f.editor,f.input);
  const next=f.bind();f.stage(next);
  assert.equal(f.commit(next).observation.state,'uploadStarted');assert.equal(f.setters,2);
});
