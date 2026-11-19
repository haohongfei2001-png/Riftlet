'use strict';
const assert = require('node:assert/strict');
const {createHash, randomUUID} = require('node:crypto');
const test = require('node:test');
const {fixture, native, png, edgeSource, previousEdgeSource, edgeAttachmentAcceptedSource} = require('./independent-input-fixture.cjs');

const encoded = bytes => Buffer.concat([bytes, Buffer.from([0])]);
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const turn = () => new Promise(resolve => setImmediate(resolve));

function setup(programSource) {
  const f = fixture({programSource, route:'https://chatgpt.com/?temporary-chat=true', accept:false,
    nativeContext:{...native, applicationID:'com.microsoft.edgemac', sessionID:'edge-kernel-v1:7:10:1'}});
  const navigation = new EventTarget();
  navigation.currentEntry = {id:randomUUID()};
  Object.assign(f.context, {self:f.context, navigation, HTMLImageElement:f.Node,
    setTimeout:(fn, ms) => setTimeout(fn, ms).unref(),
    createImageBitmap:async file => ({file, width:1, height:1, close(){}}),
    OffscreenCanvas:class {
      getContext() { return {drawImage:bitmap => { this.file = bitmap.file; }}; }
      convertToBlob() { return Promise.resolve(new Blob([this.file, Uint8Array.of(0)], {type:'image/png'})); }
    }});

  let loading;
  f.setChange(file => {
    loading = new f.Node('div');
    const named = loading.append(new f.Node('span', {'aria-label':file.name}));
    named.append(new f.Node('span', {role:'progressbar'}));
    loading.append(new f.Node('button', {'aria-label':'Remove ' + file.name}));
    f.form.append(loading);
  });

  async function submit(bytes) {
    const clickWitnessID = randomUUID();
    assert.equal(f.call({action:'pinTarget', clickWitnessID, address:'https://chatgpt.com/'}), 'bound');
    const op = f.bind({id:randomUUID().toUpperCase(), bytes, target:f.call({action:'captureTarget', clickWitnessID})});
    f.stage(op, {edgeProgressCandidate:true});
    assert.equal((await f.commit(op)).observation.state, 'inputTriggered');
    loading.remove();
    return op;
  }

  function preview(op, bytes, variant) {
    const name = op.name;
    const outside = variant === 'other form';
    const parent = outside ? f.body.append(new f.Node('form')) : f.form;
    const root = new f.Node('div', variant === 'unnamed' ? {} : {'aria-label':name});
    const visual = root.append(new f.Node(variant === 'wrong branch tag' ? 'div' : 'span'));
    const remove = root.append(new f.Node('button', {'aria-label':'Remove ' + name}));
    const icon = remove.append(new f.Node('svg'));
    icon.append(new f.Node('path'), new f.Node('path'));
    const source = 'data:image/png;base64,' + bytes.toString('base64');
    const branch = variant === 'image in Remove' ? remove : visual;
    const image = branch.append(new f.Node('img', {alt:name, src:source}));
    Object.assign(image, {currentSrc:source, complete:true, naturalWidth:1});
    if (variant === 'fourth label') visual.setAttribute('aria-label',name);
    if (variant === 'other name') root.setAttribute('aria-label', 'riftlet-' + randomUUID() + '.png');
    parent.append(root);
    return root;
  }
  const observe = op => f.call(op.command('observe')).observation;
  return {f, submit, preview, observe};
}

function inputOnly(observation) {
  assert.equal(observation.state, 'inputTriggered');
  for (const key of ['uploadStart','completionEvidence','attachmentID','terminationEvidence']) {
    assert.equal(observation[key], undefined);
  }
  assert.equal(observation.automaticRetryExcluded, false);
}

test('both named outer tiles in the same draft retain independent correct content hashes', async () => {
  const {f, submit, preview, observe} = setup(edgeSource);
  const firstBytes = png, secondBytes = Buffer.concat([png, Buffer.from([42])]);
  const first = await submit(firstBytes), second = await submit(secondBytes);
  preview(second, encoded(secondBytes));
  await f.waitFor(() => !!observe(second).originalDraftContent, 'second named root proof');
  assert.equal(observe(first).originalDraftContent, undefined);
  preview(first, encoded(firstBytes));
  await f.waitFor(() => !!observe(first).originalDraftContent, 'first named root proof');
  for (const [op, bytes] of [[first, firstBytes], [second, secondBytes]]) {
    const observation = observe(op), proof = observation.originalDraftContent;
    inputOnly(observation);
    assert.equal(proof.invocationID, op.invocationID);
    assert.equal(proof.encodedSHA256, digest(encoded(bytes)));
    assert.equal(proof.encodedByteCount, encoded(bytes).length);
    assert.deepEqual(observe(op).originalDraftContent, proof);
  }
  assert.notEqual(observe(first).originalDraftContent.evidenceID, observe(second).originalDraftContent.evidenceID);
  assert.deepEqual([f.setters, f.changes, f.sends], [2,2,0]);
});

test('frozen v27 refuses the observed outer-root template; v28 refuses ambiguous or changed content', async t => {
  for (const variant of ['v27','other form','unnamed','other name','wrong branch tag','image in Remove',
    'fourth label','duplicate roots','different bytes']) {
    await t.test(variant, async () => {
      const {f, submit, preview, observe} = setup(variant === 'v27' ? previousEdgeSource : edgeSource);
      const op = await submit(png);
      preview(op, variant === 'different bytes' ? png : encoded(png), variant);
      if (variant === 'duplicate roots') preview(op, encoded(png));
      for (let step = 0; step < 16; step++) {
        await turn();
        const observation = observe(op);
        inputOnly(observation);
        assert.equal(observation.originalDraftContent, undefined);
      }
      assert.deepEqual([f.setters, f.changes, f.sends], [1,1,0]);
    });
  }
});

test('v29 executes the frozen v28 content predicate in a distinct resident registry', async () => {
  assert.equal(Buffer.byteLength(edgeSource),125372);
  assert.equal(digest(Buffer.from(edgeSource)),'7401f5bb27b084fd0602a316fbeab9c6baf4bad731baf4328fecc796c0837f16');
  assert.equal(edgeAttachmentAcceptedSource.replace('__riftletEdgeFileInput20261119v29','__riftletEdgeFileInput20261119v28')
    .replace('click-document-witness-20261119-v29','click-document-witness-20261119-v28'),edgeSource);
  const {f, submit, preview, observe} = setup(edgeAttachmentAcceptedSource);
  const first = await submit(png), other = Buffer.concat([png,Buffer.from([71])]), second = await submit(other);
  preview(second,encoded(other));
  await f.waitFor(() => !!observe(second).originalDraftContent,'v29 second original content');
  assert.equal(observe(first).originalDraftContent,undefined);
  preview(first,encoded(png));
  await f.waitFor(() => !!observe(first).originalDraftContent,'v29 first original content');
  for (const [op,bytes] of [[first,png],[second,other]]) {
    const packet = f.call(op.command('observe'));
    assert.equal(packet.provenance.evidenceID,'click-document-witness-20261119-v29');
    inputOnly(packet.observation); // Native mapping is separate; no invented server status.
    assert.equal(packet.observation.originalDraftContent.invocationID,op.invocationID);
    assert.equal(packet.observation.originalDraftContent.encodedSHA256,digest(encoded(bytes)));
  }
  assert.ok(f.context.__riftletEdgeFileInput20261119v29);
  assert.equal(f.context.__riftletEdgeFileInput20261119v28,undefined);
  assert.deepEqual([f.setters,f.changes,f.sends],[2,2,0]);
});

test('v29 keeps mismatched original content, ownership and duplicate-card refusals', async t => {
  for (const variant of ['other form','unnamed','other name','wrong branch tag','image in Remove',
    'fourth label','duplicate roots','different bytes']) {
    await t.test(variant,async () => {
      const {f,submit,preview,observe}=setup(edgeAttachmentAcceptedSource),op=await submit(png);
      preview(op,variant==='different bytes'?png:encoded(png),variant);
      if(variant==='duplicate roots')preview(op,encoded(png));
      for(let i=0;i<16;i++){await turn();inputOnly(observe(op));assert.equal(observe(op).originalDraftContent,undefined);}
      assert.deepEqual([f.setters,f.changes,f.sends],[1,1,0]);
    });
  }
});
