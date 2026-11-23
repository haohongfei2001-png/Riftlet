'use strict';
const assert = require('node:assert/strict');
const {createHash, randomUUID} = require('node:crypto');
const http = require('node:http');
const {setTimeout: delay} = require('node:timers/promises');
const sha = value => createHash('sha256').update(value).digest('hex');

function localSite(original, script, cases = ['complete', 'partial']) {
  const routes = new Map(cases.map(mode => [mode, {mode, creates: 0, puts: 0, pending: 0}]));
  const sockets = new Set(), unexpected = [];
  const headers = {'Cache-Control': 'no-store', 'Connection': 'close',
    'Content-Security-Policy': "default-src 'none'; script-src 'self'; connect-src 'self'; form-action 'none'; frame-ancestors 'none'"};
  const server = http.createServer(async (req, res) => {
    const reply = (code, type, body) => res.writeHead(code, {...headers, 'Content-Type': type}).end(body);
    try {
      if (req.headers.host !== '127.0.0.1:' + server.address().port || req.socket.remoteAddress !== '127.0.0.1') {
        unexpected.push('unexpected host'); return reply(403, 'text/plain', '');
      }
      if (req.url === '/page.js' && req.method === 'GET') return reply(200, 'text/javascript', script);
      if (req.url === '/favicon.ico' && req.method === 'GET') return reply(204, 'text/plain', '');
      const [, prefix, mode, action, id, ...extra] = req.url.split('/');
      const route = routes.get(mode);
      if (prefix !== 'case' || !route || extra.length) {unexpected.push('unknown route');return reply(404, 'text/plain', '');}
      if (!action && req.method === 'GET') {
        return reply(200, 'text/html; charset=utf-8', '<!doctype html><body data-case="' + mode +
          '"><form><input type="file" accept="image/png"><button type="submit">Send</button></form><script src="/page.js"></script>');
      }
      if (action === 'create' && !id && req.method === 'POST') {
        route.creates++;
        assert.equal(route.creates, 1);
        const length = Number(req.headers['content-length']); assert.ok(length > 0 && length < 300);
        const parts = []; for await (const part of req) parts.push(part);
        const submitted = JSON.parse(Buffer.concat(parts));
        assert.deepEqual(submitted, {fileSHA256: sha(original), bytes: original.length});
        route.requestID = randomUUID(); route.putPath = '/case/' + mode + '/png/' + route.requestID;
        route.urlSHA256 = sha('http://' + req.headers.host + route.putPath);
        return reply(201, 'application/json', JSON.stringify({requestID: route.requestID, putPath: route.putPath}));
      }
      if (req.method !== 'PUT' || action !== 'png' || !id || id !== route.requestID || req.url !== route.putPath) {
        unexpected.push('wrong request');return reply(404, 'text/plain', '');
      }
      route.puts++;assert.equal(route.puts, 1);assert.equal(req.headers['content-type'], 'image/png');
      assert.equal(Number(req.headers['content-length']), original.length);
      const measured = createHash('sha256');
      let bytes = 0, prefixMatches = true, ending;
      route.pending++;
      try {
        // Slow only this fixture's consumption. No browser or network policy is changed.
        for await (const chunk of req) {
          prefixMatches &&= chunk.equals(original.subarray(bytes, bytes + chunk.length));
          bytes += chunk.length;measured.update(chunk);
          await delay(10);
        }
        ending = req.complete ? 'complete' : 'incomplete-eof';
      } catch (err) {ending = err.code || err.name;}
      finally {route.pending--;}
      const digest = measured.digest('hex');
      route.evidence = {requestID: id, urlSHA256: route.urlSHA256, declaredBytes: original.length, bytesRead: bytes,
        bytesSHA256: digest, originalPrefixSHA256: sha(original.subarray(0, bytes)), prefixMatches, httpBodyComplete: req.complete,
        ending, aborted: req.aborted, httpStatus: null, requestClosed: req.destroyed};
      if (req.complete && bytes === original.length && digest === sha(original) && !res.destroyed) {
        route.evidence.httpStatus = 201;
        reply(201, 'application/json', JSON.stringify({requestID: id, bytes, sha256: digest}));
      }
    } catch (err) {
      unexpected.push(err.message);
      if (!res.destroyed && !res.headersSent) reply(400, 'text/plain', 'fixture rejected');
    }
  });
  server.on('connection', socket => {sockets.add(socket);socket.once('close',()=>sockets.delete(socket));});
  return {server, routes, sockets, unexpected};
}
module.exports = {localSite, sha};
