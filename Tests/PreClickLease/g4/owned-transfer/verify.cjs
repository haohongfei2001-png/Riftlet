'use strict';
// Offline verification with the privately retained PNG and public receipt. No listener or browser is used.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {createHash} = require('node:crypto');
const sha = v => createHash('sha256').update(v).digest('hex');

const [receiptPath, originalPath] = process.argv.slice(2);
assert.ok(receiptPath && originalPath, 'provide a receipt and the same original PNG');
const bytes = fs.readFileSync(originalPath), raw = fs.readFileSync(receiptPath), receipt = JSON.parse(raw);
assert.equal(receipt.status, 'PASS');
assert.deepEqual(receipt.source.dimensions, [bytes.readUInt32BE(16), bytes.readUInt32BE(20)]);
assert.equal(sha(bytes),receipt.source.sha256);assert.equal(bytes.length,receipt.source.bytes);
assert.deepEqual(receipt.rows.map(r=>r.mode),['complete','partial']);
const ids = new Set(), hashes = new Set(), evidence = [];
// The original public receipt includes only URL digests. Reconstruct the single ephemeral loopback
// port offline and require that both exact fixed case paths reproduce both transport endpoint digests.
const ports = [];
for (let p=1;p<=65535;p++) {
  if (receipt.rows.every(({mode,server})=>sha('http://127.0.0.1:'+p+'/case/'+mode+'/png/'+server.requestID)===server.urlSHA256)) ports.push(p);
}
assert.equal(ports.length,1);
for (const {mode,browser,server} of receipt.rows) {
  const good = mode === 'complete';
  assert.equal(browser.requestID,server.requestID);assert.equal(browser.urlSHA256,server.urlSHA256);
  ids.add(server.requestID);hashes.add(server.urlSHA256);
  assert.equal(browser.fileSHA256,sha(bytes));assert.equal(browser.fileBytes,bytes.length);
  assert.equal(server.declaredBytes,bytes.length);assert.equal(server.prefixMatches,true);
  assert.equal(sha(bytes.subarray(0,server.bytesRead)),server.bytesSHA256);assert.equal(server.bytesSHA256,server.originalPrefixSHA256);
  assert.equal(server.creates,1);assert.equal(server.puts,1);assert.equal(server.pending,0);
  assert.equal(browser.createStatus,201);assert.equal(browser.pendingXHR,0);assert.equal(browser.listenersRemaining,0);
  assert.ok(browser.listenersRemoved>0 && browser.sendReturned);
  assert.deepEqual(browser.counts,{input:1,change:1,create:1,sends:1,abortCalls:good?0:1,formSubmit:0,sendButton:0});
  assert.deepEqual(browser.inputEvents,[{type:'input',trusted:true},{type:'change',trusted:true}]);
  const terminal={};
  for (const phase of ['request','upload']) {
    const events=browser.events.filter(e=>e.phase===phase);
    assert.ok(events.every(e=>e.trusted && e.sameTarget));assert.equal(events.at(-1).type,'loadend');
    const summary=Object.fromEntries(['loadstart','load','abort','error','timeout','loadend'].map(type=>[type,events.filter(e=>e.type===type).length]));
    assert.deepEqual(summary,{loadstart:1,load:good?1:0,abort:good?0:1,error:0,timeout:0,loadend:1});terminal[phase]=summary;
  }
  if (good) {
    assert.equal(browser.trigger,null);assert.equal(server.httpStatus,201);assert.equal(server.bytesRead,bytes.length);
    assert.ok(server.httpBodyComplete && !server.aborted && server.ending==='complete');
    assert.equal(browser.events.find(e=>e.phase==='request'&&e.type==='load').status,201);
  } else {
    const t=browser.trigger, sameProgress=browser.events.filter(e=>e.phase==='upload'&&e.type==='progress'&&e.loaded===t.loaded&&e.total===t.total);
    assert.equal(sameProgress.length,1);
    assert.ok(t.trusted && t.sameTarget && t.originalFile && t.originalInstance && t.sendReturned &&
      t.status===0 && t.readyState===1 && t.total===bytes.length && t.loaded>0 && t.loaded<t.total &&
      t.fraction===t.loaded/t.total && t.fraction>=0.10 && t.fraction<=0.50 && browser.abortReturned);
    assert.ok(server.bytesRead>0 && server.bytesRead<bytes.length && !server.httpBodyComplete && server.aborted && server.httpStatus===null);
    assert.ok(browser.events.every(e=>e.status===0 && e.readyState!==2 && e.readyState!==3));
  }
  evidence.push({mode,serverBytes:server.bytesRead,serverDigest:server.bytesSHA256,endpointDigestVerified:true,terminal});
}
assert.equal(ids.size,2);assert.equal(hashes.size,2);
assert.deepEqual(receipt.cleanup,{ownedHeadlessProcessGroupExited:true,disposableProfileRemoved:true,listenerClosed:true,pendingPUTs:0});
console.log(JSON.stringify({scope:'offline recomputation of original file and distinct local request receipts',
  rawReceiptSHA256:sha(raw),pngSHA256:sha(bytes),singleLoopbackOriginMatchesBothDigests:true,evidence},null,2));
