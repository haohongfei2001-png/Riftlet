'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const {randomUUID, createHash} = require('node:crypto');
const {fixture, native, png} = require('./independent-input-fixture.cjs');

const tick = () => new Promise(resolve => setImmediate(resolve));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const encoded = bytes => Buffer.concat([bytes, Buffer.from([0])]);
const dataURL = bytes => 'data:image/png;base64,' + bytes.toString('base64');

function setup({pauseEncoding = false} = {}) {
  const f = fixture({route:'https://chatgpt.com/?temporary-chat=true', accept:false,
    nativeContext:{...native, applicationID:'com.microsoft.edgemac',sessionID:'edge-kernel-v1:7:10:1'}});
  const navigation = new EventTarget(), activity = new EventTarget();
  navigation.currentEntry = {id:randomUUID()};
  let resume, encodes = 0;
  const gate = pauseEncoding ? new Promise(resolve => { resume = resolve; }) : Promise.resolve();
  Object.assign(f.context, {self:f.context, navigation, HTMLImageElement:f.Node,
    addEventListener:activity.addEventListener.bind(activity), removeEventListener:activity.removeEventListener.bind(activity),
    setTimeout:(fn,ms)=>setTimeout(fn,ms).unref(),
    createImageBitmap:async file => ({file,width:1,height:1,close(){}}),
    OffscreenCanvas:class {
      getContext() { return {drawImage:bitmap => { this.file=bitmap.file; }}; }
      async convertToBlob() { encodes++; await gate; return new Blob([this.file, Uint8Array.of(0)], {type:'image/png'}); }
    }});
  const cards=[];
  function namedRemove(name) { return new f.Node('button',{'aria-label':'Remove '+name}); }
  f.setChange(file => {
    const loading = new f.Node('span',{'aria-label':file.name});
    const bar = loading.append(new f.Node('span',{role:'progressbar'}));
    const root = f.form.append(new f.Node('div'));
    root.append(loading,namedRemove(file.name));
    cards.push({root,bar});
  });
  async function submit(bytes = png) {
    const pin=randomUUID();
    assert.equal(f.call({action:'pinTarget',clickWitnessID:pin,address:'https://chatgpt.com/'}),'bound');
    const op=f.bind({id:randomUUID().toUpperCase(),bytes,target:f.call({action:'captureTarget',clickWitnessID:pin})});
    f.stage(op,{edgeProgressCandidate:true});assert.equal((await f.commit(op)).observation.state,'inputTriggered');
    return {...cards.at(-1),op};
  }
  async function retireLoading(item) {
    for (const value of [5,19,100]) { item.bar.setAttribute('aria-valuenow',String(value)); await tick(); }
    item.bar.remove(); await tick();
    item.root.remove();
  }
  function mountedPreview(name, payload, owner = f.form) {
    const root=owner.append(new f.Node('div')), popup=new f.Node('div',{'aria-label':name,'aria-haspopup':'dialog'});
    const image=popup.append(new f.Node('span')).append(new f.Node('img',{alt:name,src:dataURL(payload)}));
    Object.assign(image,{currentSrc:dataURL(payload),complete:true,naturalWidth:1});
    root.append(popup,namedRemove(name));
    return {root,popup,image};
  }
  const read = item => f.call(item.op.command('observe'));
  return {f, navigation, submit, retireLoading, mountedPreview, read, resume, encodes:()=>encodes};
}

function noOutcome(r) {
  assert.equal(r.observation.state,'inputTriggered');
  for (const key of ['uploadStart','completionEvidence','attachmentID','terminationEvidence'])
    assert.equal(r.observation[key],undefined);
  assert.equal(r.observation.automaticRetryExcluded,false);
  assert.equal(r.observation.exactImageIdentity,false);
}
test('625-shaped full tile replacement independently records only the later original draft content',async()=>{
  const {f,submit,retireLoading,mountedPreview,read,encodes} = setup();
  const item=await submit(), privacyMarker='private-title-must-stay-in-page';
  await retireLoading(item);
  noOutcome(read(item)); assert.equal(read(item).observation.originalDraftContent,undefined);
  const payload=encoded(png);
  const card=mountedPreview(item.op.name,payload);
  card.image.setAttribute('title',privacyMarker);
  await f.waitFor(()=>!!read(item).observation.originalDraftContent,'original 625-shaped draft preview content');
  const result=read(item); noOutcome(result);
  const content=result.observation.originalDraftContent;
  assert.deepEqual(Object.keys(content).sort(),['version','encodedByteCount','encodedSHA256','inputSequence','observedSequence','invocationID','evidenceID'].sort());
  assert.equal(content.version,1);assert.equal(content.invocationID,item.op.invocationID);
  assert.equal(content.encodedByteCount,payload.length);assert.equal(content.encodedSHA256,digest(payload));
  assert.notEqual(content.encodedSHA256,item.op.identity.assetSHA256);
  assert.ok(content.inputSequence>0 && content.observedSequence>content.inputSequence);assert.match(content.evidenceID,/^[0-9a-f-]{36}$/);
  assert.equal(result.entryDiagnostics.edgeCalibration.originalDraftContentMatched,true);
  assert.deepEqual(read(item).observation.originalDraftContent,content);assert.equal(encodes(),1);
  const wire=JSON.stringify(result);assert.ok(!wire.includes(privacyMarker) && !wire.includes('data:image') && !wire.includes(item.op.name));
  assert.deepEqual([f.setters,f.changes,f.sends],[1,1,0]);
});

test('wrong bytes, owner, draft or view cannot yield original-content evidence',async t=>{
  for(const mode of ['different bytes','foreign name','outside draft','two cards','wrong remove','hidden','editor edited',
    'selection moved','prior attachment removed','mid-hash replacement','mid-hash src ABA','navigation during hashing']) {
    await t.test(mode,async()=>{
      const locked=mode.startsWith('mid-hash')||mode==='navigation during hashing';
      const {f,navigation,submit,retireLoading,mountedPreview,read,resume,encodes}=setup({pauseEncoding:locked});
      const item=await submit();await retireLoading(item);
      const bytes=mode==='different bytes'?Buffer.concat([png,Buffer.from([3])]):encoded(png);
      const name=mode==='foreign name'?'riftlet-'+randomUUID()+'.png':item.op.name;
      const card=mountedPreview(name,bytes,mode==='outside draft'?f.body:f.form);
      if(mode==='two cards')mountedPreview(name,bytes);
      if(mode==='wrong remove')card.root.children[1].setAttribute('aria-label','Remove another.png');
      if(mode==='hidden')card.image.rendered=false;
      if(mode==='editor edited')f.editor.textContent='neutral revised text';
      if(mode==='selection moved')f.selection.setBaseAndExtent(f.editor,0,f.editor,0);
      if(mode==='prior attachment removed')f.oldCard.remove();
      if(locked) {
        await f.waitFor(()=>encodes()===1,'pending independently gated digest');
        if(mode==='mid-hash replacement') {card.root.remove();mountedPreview(name,bytes);}
        if(mode==='mid-hash src ABA') {
          card.image.setAttribute('src',dataURL(Buffer.from('foreign')));
          card.image.setAttribute('src',dataURL(bytes));
        }
        if(mode==='navigation during hashing') {
          navigation.currentEntry={id:randomUUID()};navigation.dispatchEvent(new Event('currententrychange'));
        }
        resume();
      }
      for(let i=0;i<12;i++) {await tick();const r=read(item);
        assert.equal(r.observation.originalDraftContent,undefined);assert.equal(r.observation.uploadStart,undefined);
        assert.equal(r.observation.completionEvidence,undefined);}
      assert.deepEqual([f.setters,f.changes,f.sends],[1,1,0]);
    });
  }
});
test('rapid independent files with reversed previews retain only their own encoded hashes',async()=>{
  const {f,submit,retireLoading,mountedPreview,read}=setup();
  const first=await submit(), secondBytes=Buffer.concat([png,Buffer.from([9])]), second=await submit(secondBytes);
  await retireLoading(first);await retireLoading(second);
  mountedPreview(second.op.name,encoded(secondBytes));
  await f.waitFor(()=>!!read(second).observation.originalDraftContent,'second file content');
  assert.equal(read(first).observation.originalDraftContent,undefined);
  mountedPreview(first.op.name,encoded(png));
  await f.waitFor(()=>!!read(first).observation.originalDraftContent,'first file content');
  const a=read(first),b=read(second);noOutcome(a);noOutcome(b);
  assert.equal(a.observation.originalDraftContent.encodedSHA256,digest(encoded(png)));
  assert.equal(b.observation.originalDraftContent.encodedSHA256,digest(encoded(secondBytes)));
  assert.notEqual(a.observation.originalDraftContent.evidenceID,b.observation.originalDraftContent.evidenceID);
  assert.deepEqual([f.setters,f.changes,f.sends],[2,2,0]);
});

test('changes in a different form never read its files or their names', async()=>{
  const {f,submit,retireLoading,mountedPreview,read}=setup();
  const item=await submit();
  const privateForm=f.body.append(new f.Node('form')), other=privateForm.append(new f.context.HTMLInputElement());
  let privateListReads=0, nameReads=0;
  const privateFile={get name(){nameReads++;throw Error('unrelated name');}};
  Object.defineProperty(other,'files',{get(){privateListReads++;return [privateFile];}});
  // Exercise document event propagation only. The fixture's fake application
  // callback normally reads an input when its own upload handler is invoked.
  f.Node.prototype.dispatchEvent.call(other,new f.context.Event('change',{bubbles:true}));
  assert.deepEqual([privateListReads,nameReads],[0,0]);
  await retireLoading(item);mountedPreview(item.op.name,encoded(png));
  await f.waitFor(()=>!!read(item).observation.originalDraftContent,'unchanged original draft after unrelated file event');
  noOutcome(read(item));assert.deepEqual([f.setters,f.changes,f.sends],[1,1,0]);
});

test('an unowned change in the originating form stops only the preview observer without reading a filename',async()=>{
  const {f,submit,retireLoading,mountedPreview,read}=setup();
  const item=await submit(), other=f.form.append(new f.context.HTMLInputElement());
  let names=0;
  Object.defineProperty(other,'files',{get(){return [{get name(){names++;throw Error('foreign name');}}];}});
  f.Node.prototype.dispatchEvent.call(other,new f.context.Event('change',{bubbles:true}));
  await retireLoading(item);mountedPreview(item.op.name,encoded(png));
  for(let i=0;i<10;i++){await tick();assert.equal(read(item).observation.originalDraftContent,undefined);}
  assert.equal(names,0);noOutcome(read(item));assert.deepEqual([f.setters,f.changes,f.sends],[1,1,0]);
});
