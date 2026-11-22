'use strict';
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const {createHash, randomUUID} = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const {setTimeout: delay} = require('node:timers/promises');
const {FixtureDriver} = require('../../../OriginalDocumentDelivery/renderer/driver.cjs');
const {cleanupOwnedChrome, closeLoopbackServer} = require('../../../WebPageProgram/native-chrome-cleanup.cjs');

const binary = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGPwmd72HwAFBQJppW30bwAAAABJRU5ErkJggg==', 'base64');
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const script = fs.readFileSync(path.join(__dirname, 'fixture.js'));
const html = '<!doctype html><meta charset="utf-8"><title>Loopback attachment control</title>' +
  '<form><textarea>original local draft</textarea><input type="file" accept="image/png">' +
  '<output></output><button type="submit">Send</button></form><script src="/fixture.js"></script>';
const cases = [
  {label: 'size limit', byteLimit: png.length - 1, unavailable: false, expected: 413},
  {label: 'service unavailable', byteLimit: png.length, unavailable: true, expected: 503},
  {label: 'accepted control', byteLimit: png.length, unavailable: false, expected: 201},
  {label: 'unexpired private loopback grant', byteLimit: png.length, grant: 'use-now', expected: 201},
  {label: 'naturally expired private loopback grant', byteLimit: png.length, grant: 'wait', expected: 403}
];

function loopbackSite() {
  const routes = new Map(cases.map(config => ['/case/' + randomUUID(), {config, received: [], issued: null, seenGrant: 0}]));
  const unexpected = [];
  const connections = new Set();
  const server = http.createServer((req, res) => {
    const reply = (status, contentType, body) => {
      res.writeHead(status, {'Content-Type': contentType, 'Cache-Control': 'no-store',
        'Content-Security-Policy': "default-src 'none'; script-src 'self'; connect-src 'self'; form-action 'none'"}).end(body);
    };
    if (req.headers.host !== '127.0.0.1:' + server.address().port) return reply(403, 'text/plain', 'wrong host');
    if (req.method === 'GET' && routes.has(req.url)) {
      const mode = routes.get(req.url).config.grant;
      const page = mode ? html.replace('<form>', '<form data-grant="' + mode + '">') : html;
      return reply(200, 'text/html; charset=utf-8', page);
    }
    const grant = req.url.endsWith('/grant') && routes.get(req.url.slice(0, -6));
    if (req.method === 'POST' && grant?.config.grant) {
      if (grant.issued) return reply(409, 'text/plain', 'already issued');
      const issuedAt = Date.now();
      grant.issued = {issuedAt, expiresAt: issuedAt + 1500, route: req.url.slice(0, -6) + '/png'};
      grant.seenGrant++;
      return reply(201, 'application/json', JSON.stringify(grant.issued));
    }
    if (req.method === 'GET' && req.url === '/fixture.js') return reply(200, 'text/javascript', script);
    if (req.method === 'GET' && req.url === '/favicon.ico') return reply(204, 'text/plain', '');
    const route = req.url.endsWith('/png') && routes.get(req.url.slice(0, -4));
    if (!route || req.method !== 'PUT') {
      unexpected.push(req.method);
      return reply(404, 'text/plain', 'unknown fixture route');
    }
    const arrivedAt = Date.now();
    let bytes = 0;
    const hash = createHash('sha256');
    req.on('data', chunk => { bytes += chunk.length; hash.update(chunk); });
    req.on('end', () => {
      const {byteLimit, unavailable} = route.config;
      const expired = route.config.grant && (!route.issued || arrivedAt >= route.issued.expiresAt);
      const status = expired ? 403 : bytes > byteLimit ? 413 : unavailable ? 503 : 201;
      if (route.issued) route.issued.arrivedAt = arrivedAt;
      const digest = hash.digest('hex');
      const receipt = {status, bytes, sha256: digest};
      route.received.push({...receipt, contentType: req.headers['content-type']});
      reply(status, 'application/json', JSON.stringify(receipt));
    });
  });
  server.on('connection', socket => { connections.add(socket); socket.once('close', () => connections.delete(socket)); });
  return {routes, server, connections, unexpected};
}

async function waitValue(driver, tab, expression) {
  const deadline = performance.now() + 6000;
  do {
    const {result, exceptionDetails} = await driver.call('Runtime.evaluate',
      {expression, returnByValue: true}, tab.sessionId);
    if (exceptionDetails) throw Error('loopback fixture evaluation failed');
    if (result.value) return result.value;
    await delay(25);
  } while (performance.now() < deadline);
  throw Error('loopback fixture did not reach expected state');
}

function check(row, received, expected) {
  assert.deepEqual(row.counts, {input: 1, change: 1, sendButton: 0, submit: 0});
  assert.equal(row.fileCount, 1);
  assert.equal(row.textUnchanged, true);
  assert.equal(row.card, expected >= 400 ? 'refused' : 'accepted');
  const response = {status: expected, bytes: png.length, sha256: sha256(png)};
  assert.deepEqual(JSON.parse(row.response), response);
  assert.deepEqual(received, [{...response, contentType: 'image/png'}]);
  assert.ok(row.events.every(e => e.trusted));
  const names = row.events.map(e => e.event);
  assert.deepEqual(names.slice(0, 2), ['input', 'change']);
  assert.deepEqual(names.filter(name => name !== 'readystatechange'),
    ['input', 'change', 'loadstart', 'load', 'loadend']);
  const states = row.events.filter(e => e.event === 'readystatechange');
  assert.deepEqual(states.map(e => e.readyState), [1, 2, 3, 4]);
  assert.deepEqual(states.map(e => e.status), [0, expected, expected, expected]);
  assert.deepEqual(names.slice(-3), ['readystatechange', 'load', 'loadend']);
  assert.ok(row.events.slice(-3).every(e => e.status === expected && e.readyState === 4));
}

async function run() {
  const site = loopbackSite();
  await new Promise((resolve, reject) => {
    site.server.once('error', reject);
    site.server.listen(0, '127.0.0.1', resolve);
  });
  let child, exited, root;
  const rows = [];
  try {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'riftlet-http-control-'));
    const filename = path.join(root, 'control.png');
    fs.writeFileSync(filename, png);
    child = spawn(binary, ['--headless=new', '--remote-debugging-pipe', '--user-data-dir=' + path.join(root, 'profile'),
      '--no-first-run', '--no-default-browser-check', '--disable-extensions', '--disable-sync', '--disable-background-networking',
      '--disable-component-update', '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1', 'about:blank'],
      {detached: true, stdio: ['ignore', 'ignore', 'ignore', 'pipe', 'pipe']});
    exited = new Promise(resolve => { child.once('exit', resolve); child.once('error', resolve); });
    const driver = new FixtureDriver(child);
    const version = (await driver.call('Browser.getVersion')).product;
    for (const [url, route] of site.routes) {
      const {config, received} = route;
      const tab = await driver.open('http://127.0.0.1:' + site.server.address().port + url);
      try {
        await waitValue(driver, tab, 'window.ready === true');
        const {root: doc} = await driver.call('DOM.getDocument', {}, tab.sessionId);
        const {nodeId} = await driver.call('DOM.querySelector', {nodeId: doc.nodeId, selector: 'input[type=file]'}, tab.sessionId);
        assert.ok(nodeId);
        await driver.call('DOM.setFileInputFiles', {nodeId, files: [filename]}, tab.sessionId);
        const row = await waitValue(driver, tab, 'window.control');
        check(row, received, config.expected);
        let grantEvidence;
        if (config.grant) {
          const {issuedAt, expiresAt, arrivedAt} = route.issued;
          assert.equal(route.seenGrant, 1);
          assert.equal(row.grant.expiresAt, expiresAt);
          assert.equal(row.grant.issuedAt, issuedAt);
          assert.ok(issuedAt <= row.grant.receivedAt && row.grant.receivedAt < expiresAt);
          assert.ok(row.grant.receivedAt <= row.grant.sentAt && row.grant.sentAt <= arrivedAt);
          assert.equal(arrivedAt >= expiresAt, config.grant === 'wait');
          grantEvidence = {scope: 'owner-issued loopback grant', issuedAt, expiresAt, arrivedAt,
            issuedGrants: route.seenGrant, receivedPUTs: received.length, ...row.grant};
        }
        rows.push({case: config.label, server: received[0], selection: row.counts, fileCount: row.fileCount, grantEvidence,
          card: row.card, textUnchanged: row.textUnchanged, events: row.events});
      } finally {
        await driver.call('Target.closeTarget', {targetId: tab.targetId});
      }
    }
    assert.deepEqual(site.unexpected, []);
    return {scope: 'loopback-native-xhr', browser: version, result: 'PASS', rows};
  } finally {
    try {
      if (child) await cleanupOwnedChrome(child, exited);
      if (root) fs.rmSync(root, {recursive: true, force: true});
    } finally {
      await closeLoopbackServer(site.server, site.connections);
    }
  }
}
run().then(result => console.log(JSON.stringify(result, null, 2)),
  error => { console.error(error.message); process.exitCode = 1; });
