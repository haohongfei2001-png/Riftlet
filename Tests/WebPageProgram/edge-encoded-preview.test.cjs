'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const {webcrypto} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const {File} = require('node:buffer');
const source = fs.readFileSync(path.join(__dirname,
  '../../Sources/RiftletAdapters/Resources/edge-encoded-preview-v26.js'), 'utf8');
const name = 'riftlet-11111111-1111-4111-8111-111111111111.png';
const original = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==', 'base64');
function fixture(hold) {
  const counters = {decoded:0, encoded:0, closed:0};
  class Image {
    constructor(bytes = original) {
      this.src = 'data:image/png;base64,' + bytes.toString('base64');
      this.currentSrc = this.src;
      this.isConnected = this.complete = true;
      this.naturalWidth = 1;
    }
    getAttribute(key) { assert.equal(key, 'src'); return this.src; }
  }
  class Canvas {
    getContext(type, opts) { assert.equal(type, '2d'); assert.equal(opts.colorSpace, 'srgb'); return {drawImage(){}}; }
    async convertToBlob(opts) {
      assert.equal(opts.type,'image/png'); counters.encoded++;
      if (hold) await hold;
      return new Blob([original], {type:'image/png'});
    }
  }
  const page = {documentElement:{}}, nav = {currentEntry:{id:'entry'}};
  const sandbox = {self:page, top:page, document:page, location:{href:'https://chatgpt.com/?temporary-chat=true'},
    navigation:nav, File, OffscreenCanvas:Canvas, HTMLImageElement:Image, crypto:webcrypto, atob,
    setTimeout:() => 99, clearTimeout:() => {}, createImageBitmap: async () => {
      counters.decoded++; return {width:1,height:1,close(){counters.closed++;}};
    }};
  const watch = vm.runInNewContext('('+source+')', sandbox);
  const file = new File([original], name, {type:'image/png'});
  return {counters, Image, sandbox, watch, file, getWatcher:() => watch(file,name)};
}
function settled(watcher, image, expectedInitial) {
  return new Promise(resolve => {
    const initial = watcher.inspect(image, () => resolve(watcher.inspect(image)));
    if (expectedInitial !== undefined) assert.equal(initial, expectedInitial);
    if (initial !== 'encoding') resolve(initial);
  });
}

test('exact bytes, not a same-size different image; no duplicate encoding or START', async () => {
  for (const equal of [true,false]) {
    const f=fixture(), watcher=f.getWatcher(), bytes=Buffer.from(original);
    if(!equal) bytes[50]^=4;
    const image=new f.Image(bytes);
    assert.equal(await settled(watcher,image,'encoding'),equal?'matched':'mismatch');
    assert.deepEqual(f.counters,{decoded:1,encoded:1,closed:1});
    assert.deepEqual(Object.keys(watcher).sort(),['close','inspect']);
    assert.equal(watcher.inspect(new f.Image(bytes)),'mismatch');
    assert.equal(watcher.inspect(image),'unavailable');
  }
});
test('unsupported schemes are not fetched and detached, stale and swapped previews fail closed', async () => {
  const f=fixture(), watcher=f.getWatcher(), image=new f.Image();
  assert.equal(watcher.inspect(null),'unavailable');
  image.currentSrc=image.src='https://example.invalid/image';
  assert.equal(watcher.inspect(image),'unavailable');
  assert.equal(f.counters.decoded,0);
  const local=new f.Image();
  local.isConnected=false;
  assert.equal(watcher.inspect(local),'unavailable');
  local.isConnected=true;
  assert.equal(await settled(watcher,local),'matched');
  f.sandbox.navigation.currentEntry={id:'another'};
  assert.equal(watcher.inspect(local),'unavailable');
});
test('closing during pending work cannot restore a match', async () => {
  let resume;
  const f=fixture(new Promise(ok=>resume=ok)), watcher=f.getWatcher(), image=new f.Image();
  assert.equal(watcher.inspect(image),'encoding');
  watcher.close(); resume();
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(watcher.inspect(image),'unavailable');
});
test('invalid original PNG header/dimensions are refused before decoder; operation filename is exact', async () => {
  const f=fixture(), image=new f.Image();
  assert.equal(f.watch(f.file,name.replace('1111','2222')),null);
  for (const blob of [Buffer.alloc(24),Buffer.from(original)]) {
    blob.writeUInt32BE(0xffffffff,16);
    const watch=f.watch(new File([blob],name,{type:'image/png'}),name);
    assert.equal(await settled(watch,image),'mismatch');
    watch.close();
  }
  assert.equal(f.counters.decoded,0);
  f.sandbox.location.href='https://chatgpt.com/';
  assert.equal(f.getWatcher(),null);
});

test('Swift UUID and lowercase UUID forms retain exact case-sensitive File and operation equality', () => {
  const f=fixture(), id='abcdef01-2345-4abc-8def-abcdef012345';
  const file=n=>new File([original],n,{type:'image/png'});
  for(const uuid of [id,id.toUpperCase()]) {
    const exact='riftlet-'+uuid+'.png';
    assert.ok(f.watch(file(exact),exact));
  }
  const upper='riftlet-'+id.toUpperCase()+'.png', lower='riftlet-'+id+'.png';
  assert.equal(f.watch(file(lower),upper),null);
  for(const invalid of [upper.toUpperCase(),upper.replace('.png','.PNG'),upper.replace('riftlet','Riftlet'),upper+'.png']) {
    assert.equal(f.watch(file(invalid),invalid),null);
  }
});
