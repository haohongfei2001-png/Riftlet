'use strict';

const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const {createHash, randomBytes} = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const {bounded, cleanupOwnedChrome, closeLoopbackServer} = require('../WebPageProgram/native-chrome-cleanup.cjs');

const expectedAsset = 'c33e9a40c402e19f3362288cec50143369a28b57afa5b2c3a32366674210d24c';
const expectedProgram = '50b0d16d10f38c688ce33189df55ad3da6588b4c7006b710777f30340dc55ed7';
const hash = data => createHash('sha256').update(data).digest('hex');
const modes = ['original', 'reencoded', 'scaled'];
const numeric = ['setters','changes','sendActions','productFetches','productEncodes','previewBytes',
  'width','height','previewReadyMs','commitMs','productEncodeMs','observedThroughMs'];

async function replay() {
  const binary = '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge';
  assert.equal(process.platform, 'darwin', 'requires macOS process isolation');
  const assetPath = process.env.RIFTLET_EDGE_QA_PNG;
  assert.ok(assetPath && fs.existsSync(assetPath), 'provide the authorized QA PNG with RIFTLET_EDGE_QA_PNG');
  assert.equal(fs.statSync(assetPath).size, 687753, 'unexpected source length');
  const asset = fs.readFileSync(assetPath);
  assert.equal(hash(asset), expectedAsset, 'unexpected source digest');
  const program = fs.readFileSync(path.join(__dirname, '../../Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js'));
  assert.equal(hash(program), expectedProgram, 'requires frozen build 53 page resource');
  const nonce = '/' + randomBytes(32).toString('hex') + '/';
  const prefix = new Map([
    ['page.js', ['text/javascript', fs.readFileSync(path.join(__dirname, 'page.js'))]],
    ['scenario.js', ['text/javascript', fs.readFileSync(path.join(__dirname, 'scenario.js'))]],
    ['program', ['text/plain', program]], ['asset', ['image/png', asset]]
  ]);
  const reports = [], sockets = new Set();
  let resolve, reject, origin, child, exited;
  const finished = new Promise((ok, fail) => { resolve = ok; reject = fail; });
  finished.catch(() => {});
  const server = http.createServer((req, res) => {
    const headers = {'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff',
      'Referrer-Policy':'no-referrer', 'Cross-Origin-Resource-Policy':'same-origin',
      'Content-Security-Policy':"default-src 'none'; script-src 'self' 'unsafe-eval'; connect-src 'self'; img-src data:; style-src 'unsafe-inline'; form-action 'none'; frame-ancestors 'none'; base-uri 'none'"};
    const reply = (status, type, body) => { res.writeHead(status, {...headers,'Content-Type':type}); res.end(body); };
    if (req.socket.remoteAddress !== '127.0.0.1' || req.headers.host !== origin || !req.url.startsWith(nonce)) return reply(404, 'text/plain', '');
    const field = req.url.slice(nonce.length);
    if (req.method === 'GET' && prefix.has(field)) return reply(200, ...prefix.get(field));
    if (req.method === 'GET' && modes.includes(field)) {
      const html = '<!doctype html><meta charset="utf-8"><body data-mode="' + field + '"><form data-composer-layout>' +
        '<div id="prompt-textarea" contenteditable="true" role="textbox" style="width:500px;height:70px">Isolated draft only</div>' +
        '<input type="file" hidden accept="image/*"><div role="button" data-file-name="existing.png"><img alt="existing.png"></div>' +
        '<button type="submit">Send</button></form><script src="./page.js"></script></body>';
      return reply(200, 'text/html; charset=utf-8', html);
    }
    if (req.method !== 'POST' || field !== 'result' || req.headers.origin !== 'http://' + origin) return reply(404, 'text/plain', '');
    let body = '';
    req.on('data', chunk => { body += chunk; if (body.length > 4096) { req.destroy(); reject(Error('oversize report')); } });
    req.on('end', () => {
      try {
        const row = JSON.parse(body);
        if (row.failed && ['setup','bind','stage-original','commit','preview','observe'].includes(row.failed)) {
          throw Error('page failed during ' + row.failed);
        }
        assert.ok(row.mode === modes[reports.length], 'unexpected case');
        assert.ok(['inputTriggered','uploadStarted'].includes(row.state), 'unexpected state');
        assert.ok(/^[0-9a-f]{64}$/.test(row.previewSHA256), 'missing preview digest');
        assert.ok(row.observedAt === null || Number.isSafeInteger(row.observedAt), 'invalid time');
        const clean = {mode:row.mode, state:row.state, previewSHA256:row.previewSHA256, observedAt:row.observedAt};
        for (const key of numeric) {
          assert.ok(Number.isSafeInteger(row[key]) && row[key] >= 0, 'invalid metric');
          clean[key] = row[key];
        }
        for (const key of ['originalDraftPreserved','belongsToOriginalDraft']) {
          assert.equal(typeof row[key], 'boolean');
          clean[key] = row[key];
        }
        reports.push(clean);
        reply(200, 'text/plain', modes[reports.length] || 'done');
        if (reports.length === modes.length) resolve();
      } catch (err) { reply(400, 'text/plain', ''); reject(err); }
    });
  });
  server.on('connect', (_request, socket) => socket.destroy());
  server.on('upgrade', (_request, socket) => socket.destroy());
  server.on('connection', socket => { sockets.add(socket); socket.once('close', () => sockets.delete(socket)); });
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'riftlet-build53-headless-'));
  let cleaned = false;
  try {
    await bounded(new Promise((ok, fail) => {server.once('error', fail); server.listen(0, '127.0.0.1', ok);}),
      3000, 'loopback listen timeout');
    const port = server.address().port;
    origin = '127.0.0.1:' + port;
    // A fixed loopback deny-proxy handles non-fixture URLs. It has no forwarding
    // path. Only the fixture origin bypasses it. Keep Edge's native sandbox.
    child = spawn(binary, ['--headless=new','--disable-sync',
      '--disable-background-networking','--disable-extensions','--disable-component-update','--disable-crash-reporter',
      '--no-first-run','--no-default-browser-check','--disable-quic',
      '--proxy-server=http://' + origin,'--proxy-bypass-list=127.0.0.1:' + port,
      '--force-webrtc-ip-handling-policy=disable_non_proxied_udp',
      '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','--user-data-dir=' + profile,
      'http://' + origin + nonce + modes[0]], {detached:true,stdio:'ignore'});
    child.once('error', reject);
    exited = new Promise(ok => child.once('exit', () => {ok(); if (reports.length < modes.length) reject(Error('Edge exited before reporting'));}));
    await bounded(finished, 50000, 'bounded replay timed out after ' + reports.length + ' cases');
  } finally {
    try { await cleanupOwnedChrome(child, exited); cleaned = true; }
    finally {
      await closeLoopbackServer(server, sockets);
      if (cleaned) fs.rmSync(profile, {recursive:true});
    }
  }
  process.stdout.write(JSON.stringify({sourceSHA256:expectedAsset, sourceBytes:asset.length, programSHA256:expectedProgram,
    reports}, null, 2) + '\n');
  for (const row of reports) {
    assert.ok(row.setters === 1 && row.changes === 1 && !row.sendActions && !row.productFetches && row.originalDraftPreserved,
      'once-only input, draft or no-send invariant failed');
    assert.equal(row.previewSHA256 === expectedAsset, row.mode === 'original', 'unexpected preview identity');
    assert.equal(row.state, row.mode === 'scaled' ? 'inputTriggered' : 'uploadStarted', 'START differed from expected case');
    if (row.state === 'uploadStarted') assert.equal(row.belongsToOriginalDraft, true);
    assert.equal(row.productEncodes, row.mode === 'reencoded' ? 1 : 0);
  }
}
replay().catch(err => { console.error(err.message); process.exitCode = 1; });
