'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {randomUUID} = require('node:crypto');
const {fixture, native, png} = require('./independent-input-fixture.cjs');
const route = 'https://chatgpt.com/?temporary-chat=true';
const old = fs.readFileSync(path.join(__dirname,
  '../../Sources/RiftletAdapters/Resources/chatgpt-web-observe-v22.js'), 'utf8');
const encodedURL = last => 'data:image/png;base64,' + Buffer.concat([png, Buffer.from([last])]).toString('base64');

// Only the encoder is deterministic here. These are the actual input program,
// async SHA-256 comparison, operation registry, scoped card scan and progress observer.
function scenario({prior = false, before, render} = {}) {
  const f = fixture({route, accept:false, nativeContext:{...native, applicationID:'com.microsoft.edgemac',
    sessionID:'edge-kernel-v1:7:10:1'}, ...(prior ? {programSource:old} : {})});
  const nav = new EventTarget(), activity = new EventTarget();
  nav.currentEntry = {id:randomUUID()};
  Object.assign(f.context, {navigation:nav, HTMLImageElement:f.Node,
    addEventListener:activity.addEventListener.bind(activity), removeEventListener:activity.removeEventListener.bind(activity),
    setTimeout:(fn,ms) => setTimeout(fn,ms).unref(),
    createImageBitmap:async file => ({file,width:1,height:1,close(){}}),
    OffscreenCanvas:class {
      getContext() { return {drawImage:bitmap => { this.file=bitmap.file; }}; }
      async convertToBlob() { return new Blob([this.file, Uint8Array.of(0)], {type:'image/png'}); }
    }});
  vm.runInContext('globalThis.self=globalThis', f.context);
  const cards = [];
  f.setChange(file => {
    const card = f.addCard(file.name);
    const image = card.querySelector('img'), bar = card.querySelector('[role="progressbar"]');
    image.setAttribute('src', encodedURL(0));
    image.src = image.currentSrc = image.getAttribute('src');
    image.complete = true; image.naturalWidth = 1;
    const item = {card,image,bar,file};
    render?.(f, item); cards.push(item);
  });
  async function submit() {
    const witness = randomUUID();
    const id = randomUUID();
    before?.(f, 'riftlet-'+id+'.png');
    assert.equal(f.call({action:'pinTarget', clickWitnessID:witness, address:'https://chatgpt.com/'}),'bound');
    const op=f.bind({id, target:f.call({action:'captureTarget', clickWitnessID:witness})});
    f.stage(op,{edgeProgressCandidate:true});
    assert.equal((await f.commit(op)).observation.state,'inputTriggered');
    return op;
  }
  return {f,cards,submit,read:op=>f.call(op.command('observe'))};
}

async function sampleUntil(read, predicate) {
  const end = performance.now()+2000;
  let result;
  do {
    result=read();
    if(predicate(result)) return result;
    await new Promise(resolve=>setTimeout(resolve,2));
  } while(performance.now()<end);
  return result;
}
const decision = result => result.entryDiagnostics?.edgeCalibration?.progressDecision;
const pause = () => new Promise(resolve=>setTimeout(resolve,15));
function noStart(result) {
  assert.equal(result.observation.state,'inputTriggered');
  assert.equal(result.observation.uploadStart,undefined);
  assert.equal(result.observation.completionEvidence,undefined);
}
test('a matched newly named encoded PNG still needs the same bar to advance between two reads', async () => {
  const {f,cards,submit,read}=scenario(), op=await submit();
  const first=await sampleUntil(()=>read(op),r=>decision(r)==='firstProgress');
  assert.equal(decision(first),'firstProgress');
  noStart(first); noStart(read(op));
  cards[0].bar.setAttribute('aria-valuenow','24');
  const result=read(op).observation;
  assert.equal(result.state,'uploadStarted'); assert.equal(result.uploadStart.signal,'correlatedProgress');
  assert.equal(result.uploadStart.previousProgress,10); assert.equal(result.uploadStart.currentProgress,24);
  assert.equal(result.completionEvidence,undefined);
  assert.equal(f.setters,1);assert.equal(f.changes,1);assert.equal(f.sends,0);
});
test('matching pixels or an unrelated advancing bar cannot establish encoded START', async t => {
  for (const mode of ['no bar','different bytes','conflict','different operation','retained old card','historical v22']) {
    await t.test(mode,async () => {
      const {cards,submit,read} = scenario({prior:mode==='historical v22',
        before:(f,name)=>{if(mode==='retained old card') f.addCard(name);},
        render:(f,{image,card,bar})=>{
          if(mode==='no bar') bar.remove();
          if(mode==='different bytes') { image.setAttribute('src',encodedURL(1)); image.currentSrc=encodedURL(1); }
          if(mode==='conflict') card.append(new f.Node('span',{title:'other-upload.png'}));
          if(mode==='different operation') {
            card.setAttribute('data-file-name','other.png'); card.setAttribute('title','other.png');
            card.setAttribute('aria-label','other.png'); image.setAttribute('alt','other.png');
          }
        }});
      const op=await submit();
      const expected = {'no bar':'encodedPreviewWithoutProgress', 'different bytes':'previewMismatch',
        'historical v22':'fileBlobMissing', 'conflict':'conflictingFileLabel'};
      if (expected[mode]) {
        const settled = await sampleUntil(()=>read(op), r=>decision(r)===expected[mode]);
        assert.equal(decision(settled),expected[mode]); noStart(settled);
      } else {
        noStart(read(op)); await pause(); noStart(read(op));
      }
      cards[0].bar.setAttribute('aria-valuenow','41');
      noStart(read(op)); await pause(); noStart(read(op));
    });
  }
});
test('replacing the proven image or bar invalidates the first reading', async t => {
  for (const replacement of ['image','bar']) await t.test(replacement,async () => {
    const {f,cards,submit,read}=scenario(), op=await submit(), item=cards[0];
    assert.equal(decision(await sampleUntil(()=>read(op),r=>decision(r)==='firstProgress')),'firstProgress');
    if(replacement==='image') {
      const next=new f.Node('img',{alt:item.file.name,src:encodedURL(0)});
      next.src=next.currentSrc=encodedURL(0);next.complete=true;next.naturalWidth=1;
      item.image.remove();item.card.append(next);
      item.bar.setAttribute('aria-valuenow','23');
    } else {
      item.bar.remove();item.card.append(new f.Node('div',{role:'progressbar','aria-valuenow':'23'}));
    }
    noStart(read(op));await pause();noStart(read(op));
  });
});
test('two same-content screenshots cannot share their filename or bar', async () => {
  const {cards,submit,read}=scenario(), first=await submit();
  assert.equal(decision(await sampleUntil(()=>read(first),r=>decision(r)==='firstProgress')),'firstProgress');
  const second=await submit();
  assert.equal(decision(await sampleUntil(()=>read(second),r=>decision(r)==='firstProgress')),'firstProgress');
  cards[1].bar.setAttribute('aria-valuenow','31');
  noStart(read(first)); assert.equal(read(second).observation.state,'uploadStarted');
  cards[0].bar.setAttribute('aria-valuenow','27');
  assert.equal(read(first).observation.state,'uploadStarted');
});
