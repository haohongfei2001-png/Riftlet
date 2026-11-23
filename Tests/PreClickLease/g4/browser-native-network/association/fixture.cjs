'use strict';

const {createHash, randomUUID} = require('node:crypto');
const http = require('node:http');
const {deflateSync, crc32} = require('node:zlib');
const {closeLoopbackServer} = require('../../../../WebPageProgram/native-chrome-cleanup.cjs');

const sha = bytes => createHash('sha256').update(bytes).digest('hex');

// A valid, deterministic RGB PNG generated entirely by this fixture.
function makePNG() {
  const side = 192;
  const stride = 1 + side * 3;
  const pixels = Buffer.alloc(side * stride);
  let state = 121121;
  for (let y = 0; y < side; y++) {
    for (let x = 1; x < stride; x++) {
      state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
      pixels[y * stride + x] = state >>> 24;
    }
  }
  function chunk(kind, bytes) {
    const type = Buffer.from(kind, 'ascii');
    const length = Buffer.alloc(4), check = Buffer.alloc(4);
    length.writeUInt32BE(bytes.length);
    check.writeUInt32BE(crc32(Buffer.concat([type, bytes])));
    return Buffer.concat([length, type, bytes, check]);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(side, 0); ihdr.writeUInt32BE(side, 4);
  ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(pixels)), chunk('IEND', Buffer.alloc(0))]);
}

async function startFixture(png, filename) {
  const pageID = randomUUID(), objectID = randomUUID();
  const pagePath = '/fixture/' + pageID, createPath = '/local-create/' + pageID, putPath = '/public-object/' + objectID;
  let origin;
  const records = {creates: [], puts: []};
  const sockets = new Set();
  const server = http.createServer(async (req, res) => {
    function end(status, body, type = 'text/plain') {
      res.writeHead(status, {'Content-Type':type, 'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff'});
      res.end(body);
    }
    try {
      if (req.headers.host !== new URL(origin).host) return end(404, '');
      if (req.url === pagePath && req.method === 'GET') {
        res.setHeader('Content-Security-Policy', "default-src 'none'; script-src 'unsafe-inline'; connect-src 'self'; worker-src 'none'; form-action 'none'; frame-src 'none'; base-uri 'none'");
        return end(200, localPage(createPath, putPath), 'text/html; charset=utf-8');
      }
      const create = req.method === 'POST' && req.url === createPath;
      const put = req.method === 'PUT' && req.url === putPath;
      if (!create && !put) return end(404, '');
      const chunks = [];
      let bytes = 0;
      for await (const part of req) {
        bytes += part.length;
        if (bytes > Math.max(2048, png.length)) return end(413, '');
        chunks.push(part);
      }
      const body = Buffer.concat(chunks);
      if (create) {
        if (records.creates.length) return end(409, '');
        const metadata = JSON.parse(body);
        if (metadata.name !== filename || metadata.bytes !== png.length) return end(400, '');
        records.creates.push({bytes, bodySHA256:sha(body), originalNameMatches:true, originalSizeMatches:true});
        return end(200, JSON.stringify({upload_url:origin + putPath}), 'application/json');
      }
      if (records.creates.length !== 1 || records.puts.length) return end(409, '');
      const status = body.equals(png) ? 201 : 422;
      records.puts.push({status, bytes, bodySHA256:sha(body), requestContentLength:Number(req.headers['content-length'])});
      return end(status, '');
    } catch { return end(400, 'fixture refused'); }
  });
  server.on('connection', socket => { sockets.add(socket); socket.once('close', () => sockets.delete(socket)); });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  origin = 'http://127.0.0.1:' + server.address().port;
  return {origin, page:origin + pagePath, create:origin + createPath, put:origin + putPath, records,
    async close() { await closeLoopbackServer(server, sockets); }};
}

function localPage(createPath, putPath) {
  return '<!doctype html><meta charset="utf-8"><link rel="icon" href="data:,">' +
    '<title>Riftlet local request association</title><input id="file" type="file"><output id="result"></output><script>' +
    '(' + onLocalPage.toString() + ')(' + JSON.stringify(createPath) + ',' + JSON.stringify(putPath) + ')</script>';
}

// This is the authored page. No network method is replaced or intercepted.
function onLocalPage(createPath, putPath) {
  const input = document.getElementById('file'), out = document.getElementById('result');
  const facts = {input:0, change:0};
  const documentID = crypto.randomUUID();
  const encode = buffer => Array.from(new Uint8Array(buffer), b => b.toString(16).padStart(2, '0')).join('');
  out.dataset.documentId = documentID;
  input.addEventListener('input', () => { facts.input++; });
  input.addEventListener('change', async () => {
    facts.change++;
    try {
      if (facts.input !== 1 || facts.change !== 1 || input.files.length !== 1) throw Error();
      const file = input.files[0];
      facts.fileSHA256 = encode(await crypto.subtle.digest('SHA-256', await file.arrayBuffer()));
      const created = await fetch(createPath, {method:'POST', credentials:'omit',
        headers:{'Content-Type':'application/json'}, body:JSON.stringify({name:file.name, bytes:file.size})});
      const response = await created.json();
      if (!created.ok || response.upload_url !== location.origin + putPath) throw Error();
      const upload = new XMLHttpRequest();
      upload.open('PUT', response.upload_url);
      upload.onloadend = () => {
        facts.terminalStatus = upload.status;
        out.dataset.result = JSON.stringify(facts);
      };
      upload.send(file);
    } catch { out.dataset.result = JSON.stringify({error:'fixed fixture refused'}); }
  }, {once:true});
}

module.exports = {makePNG, sha, startFixture};
