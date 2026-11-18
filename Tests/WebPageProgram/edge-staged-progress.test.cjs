'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {randomUUID} = require('node:crypto');
const {fixture, native, png} = require('./independent-input-fixture.cjs');
const resources = path.join(__dirname, '../../Sources/RiftletAdapters/Resources');
const route = 'https://chatgpt.com/?temporary-chat=true';
const tick = () => new Promise(resolve => setImmediate(resolve));
function scenario({historical = false, lower = false, watcher = true} = {}) {
  const resource = name => fs.readFileSync(path.join(resources, name), 'utf8');
  const version = historical ? '24' : '26';
  const helper = resource(historical ? 'edge-encoded-preview.js' : 'edge-encoded-preview-v26.js');
  const page = resource('chatgpt-web-edge-v' + version + '.js').replace('/*__RIFTLET_ENCODED_PREVIEW_WATCHER__*/', () => helper);
  const f = fixture({route,accept:false,programSource:page, nativeContext:{...native,applicationID:'com.microsoft.edgemac',sessionID:'edge-kernel-v1:7:10:1'}});
  const nav = new EventTarget(), activity = new EventTarget();
  nav.currentEntry={id:randomUUID()};
  Object.assign(f.context, {navigation:nav, HTMLImageElement:f.Node,
    addEventListener:activity.addEventListener.bind(activity),removeEventListener:activity.removeEventListener.bind(activity),
    setTimeout:(fn,ms)=>setTimeout(fn,ms).unref(),
    createImageBitmap:async file=>({file,width:1,height:1,close(){}}),
    OffscreenCanvas:watcher ? class {
      getContext() {return {drawImage:bitmap=>{this.file=bitmap.file;}};}
      async convertToBlob() {return new Blob([this.file,Uint8Array.of(0)],{type:'image/png'});}
    } : undefined});
  vm.runInContext('globalThis.self=globalThis',f.context);
  const entries=[];
  f.setChange(file=>{
    const scope=new f.Node('div'), remove=new f.Node('button',{'aria-label':'Remove '+file.name});
    const loading=new f.Node('span',{'aria-label':file.name}),bar=loading.append(new f.Node('span',{role:'progressbar'}));
    scope.append(loading,remove); f.form.append(scope); entries.push({scope,remove,bar,loading,file});
  });
  async function submit() {
    const pin=randomUUID(), id=lower ? randomUUID() : randomUUID().toUpperCase();
    assert.equal(f.call({action:'pinTarget',clickWitnessID:pin,address:'https://chatgpt.com/'}),'bound');
    const op=f.bind({id,target:f.call({action:'captureTarget',clickWitnessID:pin})});
    f.stage(op,{edgeProgressCandidate:true});
    assert.equal((await f.commit(op)).observation.state,'inputTriggered');
    return {...entries.at(-1),op};
  }
  function preview(item,lastByte=0) {
    const url='data:image/png;base64,'+Buffer.concat([png,Buffer.from([lastByte])]).toString('base64');
    const popup=new f.Node('div',{'aria-label':item.file.name,'aria-haspopup':'dialog'});
    const wrapper=popup.append(new f.Node('span')), image=wrapper.append(new f.Node('img',{src:url,alt:item.file.name}));
    Object.assign(image,{currentSrc:url,complete:true,naturalWidth:1});
    item.loading.remove();item.scope.append(popup);return {image,popup};
  }
  const read=item=>f.call(item.op.command('observe'));
  const advance=async(item,value)=>{item.bar.setAttribute('aria-valuenow',String(value));await tick();};
  const saved=item=>f.context.__riftletIndependentFileInput20261104.operations.get(item.op.identity.operationID);
  return {f,submit,preview,read,advance,saved};
}
function unknown(result) {
  assert.equal(result.observation.state,'inputTriggered');
  assert.equal(result.observation.uploadStart,undefined);
  assert.equal(result.observation.completionEvidence,undefined);
  assert.equal(result.observation.automaticRetryExcluded,false);
}
for(const lower of [false,true]) test('delayed encoded preview verifies earlier progress on a continuously owned '+(lower?'lowercase':'Swift uppercase')+' tile', async()=>{
  const {f,submit,preview,read,advance,saved}=scenario({lower}),item=await submit();
  // All numeric progress is gone before the native reader next asks for this operation.
  await advance(item,5);await advance(item,16);await advance(item,100);
  item.bar.setAttribute('role','status');await tick();
  const resident=saved(item);
  assert.equal(resident.edgeCalibration.progress.decision,'stagedProgressAwaitingPreview');
  assert.equal(resident.start,null);
  preview(item);
  await f.waitFor(()=>resident.start,'original observer retained the two samples and then verified the preview');
  const start=read(item).observation;
  assert.deepEqual([start.uploadStart.previousProgress,start.uploadStart.currentProgress],[5,16]);
  assert.equal(start.uploadStart.signal,'correlatedProgress');assert.equal(start.completionEvidence,undefined);
  assert.equal(start.automaticRetryExcluded,false);assert.equal(f.setters,1);assert.equal(f.changes,1);assert.equal(f.sends,0);
});
test('staged progress cannot be used by another operation, replacement or unverified image',async t=>{
  for (const mode of ['wrong bytes','other tile','new root','new Remove','new bar','foreign sibling bar','unrelated alert','ABA remove','duplicate named root','rollback','temporary foreign label',
      'unlabelled progress','competing name','terminal','one sample','status only','selection changed','earlier attachment removed','old watcher']) {
    await t.test(mode,async()=>{
      const {f,submit,preview,read,advance}=scenario({historical:mode==='old watcher'}), item=await submit();
      if(mode==='unlabelled progress')item.loading.removeAttribute('aria-label');
      if(mode==='foreign sibling bar'){
        const branch=new f.Node('div'),other=new f.Node('div');item.loading.remove();item.scope.append(branch);
        other.append(item.bar);branch.append(item.loading,other);
      }
      if(mode==='duplicate named root'){const duplicate=f.form.append(new f.Node('div')); duplicate.append(new f.Node('button',{'aria-label':'Remove '+item.file.name}));}
      if(mode==='competing name')item.loading.append(new f.Node('span',{title:'foreign.png'}));
      await advance(item,5);
      if(mode==='new bar'){item.bar.remove();item.bar=item.loading.append(new f.Node('span',{role:'progressbar','aria-valuenow':'5'}));}
      if(mode==='rollback')await advance(item,3);
      if(mode==='temporary foreign label'){item.loading.setAttribute('aria-label','other.png');item.loading.setAttribute('aria-label',item.file.name);}
      if(mode==='one sample')await tick();else await advance(item,19);
      if(mode==='new root'){const next=new f.Node('div');next.append(item.loading,item.remove);item.scope.remove();f.form.append(next);item.scope=next;}
      if(mode==='unrelated alert'){const alert=f.form.append(new f.Node('span',{role:'alert'}));alert.textContent='Upload failed';}
      if(mode==='ABA remove'){item.remove.remove();item.scope.append(item.remove);}
      if(mode==='new Remove'){item.remove.remove();item.scope.append(new f.Node('button',{'aria-label':'Remove '+item.file.name}));}
      if(mode==='terminal')item.loading.setAttribute('data-state','failed');
      if(mode==='selection changed')f.selection.setBaseAndExtent(f.editor,0,f.editor,0);
      if(mode==='earlier attachment removed')f.oldCard.remove();
      if(mode==='other tile'){const next=await submit();preview(next);unknown(read(next));}
      else if(mode==='status only')item.bar.setAttribute('role','status');
      else preview(item,mode==='wrong bytes'?1:0);
      await tick();await tick();unknown(read(item));await tick();unknown(read(item));
      assert.equal(f.setters,mode==='other tile'?2:1);assert.equal(f.sends,0);
    });
  }
});
test('the active adapter distinguishes an unavailable encoded watcher from absent or mismatched pixels',async()=>{
  const {submit,read}=scenario({watcher:false}),item=await submit();
  const result=read(item);unknown(result);assert.equal(result.entryDiagnostics.edgeCalibration.progressDecision,'previewWatcherUnavailable');
});
test('independent pending operations retain their own earlier progress while previews appear in reverse order',async()=>{
  const {f,submit,preview,read,advance,saved}=scenario(), first=await submit(), second=await submit();
  await advance(first,6);await advance(second,11);await advance(first,19);await advance(second,31);
  preview(second);await f.waitFor(()=>saved(second).start,'second preview');unknown(read(first));
  preview(first);await f.waitFor(()=>saved(first).start,'first preview');
  const a=read(first).observation,b=read(second).observation;
  assert.deepEqual([a.uploadStart.previousProgress,a.uploadStart.currentProgress],[6,19]);
  assert.deepEqual([b.uploadStart.previousProgress,b.uploadStart.currentProgress],[11,31]);
  assert.notEqual(a.attachmentID,b.attachmentID);assert.notEqual(a.uploadStart.evidenceID,b.uploadStart.evidenceID);
  assert.equal(a.completionEvidence,undefined);assert.equal(b.completionEvidence,undefined);
  assert.equal(f.setters,2);assert.equal(f.changes,2);assert.equal(f.sends,0);
});
