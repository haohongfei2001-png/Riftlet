'use strict';
// Reads recorded receipts only. Supplying the private development PNG also verifies the server's prefix.
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const fs = require('node:fs');
const sha = data => createHash('sha256').update(data).digest('hex');

const [path, pngPath] = process.argv.slice(2);
const bytes = fs.readFileSync(path);
const report = JSON.parse(bytes);
const png = pngPath && fs.readFileSync(pngPath);
assert.equal(report.schemaVersion, 2);
assert.equal(report.caseSet, 'lifetime-controls');
assert.equal(report.status, 'PASS');
const modes = ['partial', 'expired', 'source-changed', 'request-released', 'pagehide'];
assert.deepEqual(report.rows.map(row => row.mode), modes);
if (png) {
  assert.equal(sha(png), report.source.sha256);
  assert.equal(png.length, report.source.bytes);
}
const ids = new Set(), urls = new Set(), summary = [];
for (const {mode, browser, server} of report.rows) {
  const d = browser.disposition;
  ids.add(server.requestID);
  urls.add(server.urlSHA256);
  assert.equal(server.requestID, browser.requestID);
  assert.equal(server.urlSHA256, browser.urlSHA256);
  assert.equal(browser.fileSHA256, report.source.sha256);
  assert.equal(browser.fileBytes, report.source.bytes);
  assert.equal(server.creates, 1);
  assert.equal(server.puts, 1);
  assert.equal(browser.counts.input, 1);
  assert.equal(browser.counts.change, 1);
  assert.equal(browser.counts.create, 1);
  assert.equal(browser.counts.sends, 1);
  assert.equal(server.pending, 0);
  assert.equal(browser.pendingCreates, 0);
  assert.equal(browser.pendingXHR, 0);
  assert.equal(browser.listenersRemaining, 0);
  assert.equal(d.observerListenersRemaining, 0);
  assert.equal(d.mutationObserverDisconnected, true);
  assert.ok(d.listenersRemoved > 0 && browser.normalCompletionHandlerRemoved);
  assert.ok(browser.nativeTerminal.originalInstance && browser.nativeTerminal.trusted);
  assert.equal(browser.nativeTerminal.type, 'loadend');
  assert.equal(server.bytesSHA256, server.originalPrefixSHA256);
  if (png) assert.equal(sha(png.subarray(0, server.bytesRead)), server.bytesSHA256);
  if (mode === 'partial') {
    assert.equal(d.reason, 'native-terminal');
    const t = browser.trigger;
    assert.ok(t.trusted && t.originalInstance && t.originalFile && t.sendReturned);
    assert.equal(t.fraction, t.loaded / t.total);
    assert.equal(t.total, report.source.bytes);
    assert.ok(t.fraction >= 0.10 && t.fraction <= 0.50);
    assert.equal(browser.counts.abortCalls, 1);
    assert.equal(browser.nativeTerminal.status, 0);
    assert.equal(server.httpStatus, null);
    assert.ok(server.aborted && !server.httpBodyComplete && server.bytesRead > 0 && server.bytesRead < t.total);
  } else {
    assert.equal(d.reason, mode === 'request-released' ? 'request-changed' : mode);
    assert.equal(d.pendingXHRAtWithdrawal, 1);
    assert.equal(d.pendingCreatesAtWithdrawal, 0);
    assert.equal(browser.trigger, null);
    assert.equal(browser.counts.abortCalls, 0);
    assert.equal(browser.abortReturned, false);
    assert.ok(!browser.events.some(event => event.type === 'loadend'));
    assert.equal(browser.nativeTerminal.status, 201);
    assert.equal(server.httpStatus, 201);
    assert.equal(server.httpBodyComplete, true);
    assert.equal(server.bytesRead, report.source.bytes);
    assert.equal(server.bytesSHA256, report.source.sha256);
    if (mode === 'expired') assert.ok(d.atMS >= d.deadlineMS);
    if (mode === 'pagehide') assert.equal(d.pagehideTrusted, false);
  }
  summary.push({mode, reason: d.reason, aborts: browser.counts.abortCalls,
    pendingAtWithdrawal: d.pendingXHRAtWithdrawal, pendingAfterNativeTerminal: browser.pendingXHR, serverHTTP: server.httpStatus});
}
assert.equal(ids.size, modes.length);
assert.equal(urls.size, modes.length);
assert.deepEqual(report.cleanup, {ownedHeadlessProcessGroupExited:true,disposableProfileRemoved:true,listenerClosed:true,pendingPUTs:0});
console.log(JSON.stringify({scope:'local development PNG, current lifetime controls', rawSHA256:sha(bytes),
  sourceAndPrefixesIndependentlyRecomputed: Boolean(png), summary}, null, 2));
