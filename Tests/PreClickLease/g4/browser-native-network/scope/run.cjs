'use strict';

// There is no external address, executable, browser target, rule or script argument.
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const {createHash} = require('node:crypto');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {setTimeout: delay} = require('node:timers/promises');
const {FixtureDriver} = require('../../../../OriginalDocumentDelivery/renderer/driver.cjs');
const {cleanupOwnedChrome, closeLoopbackServer} = require('../../../../WebPageProgram/native-chrome-cleanup.cjs');

const families = {
  Chrome: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  Edge: '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'
};
const roles = ['target', 'peer', 'client'];
const phases = ['baseline', 'in-flight', 'offline-new', 'restored', 'blocked-new', 'unblocked'];
const fixture = fs.readFileSync(path.join(__dirname, 'fixture.js'));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const fixturePolicy = "default-src 'none'; connect-src 'self'; script-src 'sha256-" +
  createHash('sha256').update(fixture).digest('base64') + "'; form-action 'none'; base-uri 'none'";
const page = Buffer.concat([Buffer.from('<!doctype html><meta charset=utf-8><title>Owned network scope</title><script>'),
  fixture, Buffer.from('</script>')]);
const body = (role, phase) => Buffer.alloc(phase === 'in-flight' ? 6 * 1024 * 1024 : 64,
  1 + roles.indexOf(role) * phases.length + phases.indexOf(phase));
const key = (role, phase) => '/fixed/' + role + '/' + phase;
const expected = new Map(roles.flatMap(role => phases.map(phase => [key(role, phase), {role, phase}])));
const statusCode = 201;
const reply = Buffer.from('owned');
const source = (name) => fs.readFileSync(path.join(__dirname, name));
const fingerprint = value => sha(JSON.stringify(value));

async function until(read, description) {
  const end = performance.now() + 9000;
  do {
    if (await read()) return;
    await delay(15);
  } while (performance.now() < end);
  throw Error('bounded observation timed out: ' + description);
}

function createSite(log) {
  const received = new Map();
  const held = new Map();
  const sockets = new Set();
  const server = http.createServer((request, response) => {
    const address = '127.0.0.1:' + server.address().port;
    if (request.socket.remoteAddress !== '127.0.0.1' || request.headers.host !== address) {
      response.writeHead(403).end(); return;
    }
    if (request.method === 'GET' && ['/scope/target', '/scope/peer'].includes(request.url)) {
      response.writeHead(200, {'Content-Type':'text/html; charset=utf-8', 'Content-Security-Policy':fixturePolicy,
        'Cache-Control':'no-store'}).end(page);
      return;
    }
    const reqKey = request.url === '/fixed/exact-resource' ? '/fixed/' + request.headers['x-owned-case'] : request.url;
    const test = expected.get(reqKey);
    if (request.method !== 'POST' || !test || received.has(reqKey) ||
        Number(request.headers['content-length']) !== body(test.role, test.phase).length) {
      response.writeHead(404).end(); return;
    }
    const hash = createHash('sha256');
    const facts = {bytes:0, chunks:0, requestEnded:false, requestAborted:false,
      responseFinished:false, responseClosed:false, bytesSHA256:null, statusEmitted:null};
    received.set(reqKey, facts);
    log('server', 'request', test);
    request.on('data', bytes => {
      facts.bytes += bytes.length;
      ++facts.chunks;
      hash.update(bytes);
      log('server', 'body-chunk', {...test, chunkBytes:bytes.length, receivedBytes:facts.bytes});
      if (test.phase === 'in-flight' && facts.chunks === 1) {
        request.pause(); held.set(reqKey, request);
      }
    });
    request.once('end', () => {
      facts.requestEnded = true;
      facts.statusEmitted = statusCode;
      log('server', 'body-end', {...test, receivedBytes:facts.bytes});
      response.writeHead(statusCode, {'Content-Type':'text/plain', 'Cache-Control':'no-store',
        'Content-Length':reply.length}).end(reply);
    });
    request.once('aborted', () => {
      facts.requestAborted = true;
      log('server','request-aborted', {...test, receivedBytes:facts.bytes});
    });
    request.on('error', () => log('server','request-error', test));
    response.on('finish', () => {
      facts.responseFinished = true;
      log('server','response-finished', {...test, status:statusCode});
    });
    request.on('close', () => {
      held.delete(reqKey);
      facts.responseClosed = true;
      facts.bytesSHA256 = hash.copy().digest('hex');
      log('server','response-closed', {...test, receivedBytes:facts.bytes});
    });
  });
  server.on('connection', socket => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
  });
  return {server, received, held, sockets, release() {
    for (const request of held.values()) request.resume();
    held.clear();
  }};
}

function collect(child, origin, log) {
  const sessions = new Map();
  const observed = new Map();
  let tail = '';
  child.stdio[4].setEncoding('utf8');
  const consume = part => {
    const frames = (tail + part).split('\0');
    tail = frames.pop();
    for (const frame of frames) {
      if (!frame) continue;
      const event = JSON.parse(frame);
      const binding = sessions.get(event.sessionId);
      if (!binding || !event.method?.startsWith('Network.')) continue;
      const data = event.params;
      const lookup = binding.role + ':' + data.requestId;
      if (event.method === 'Network.requestWillBeSent') {
        if (data.request.method !== 'POST' || !data.request.url.startsWith(origin + '/fixed/')) continue;
        const isBlockProbe = data.request.url === origin + '/fixed/exact-resource';
        const plan = isBlockProbe ? {role:binding.role, phase:binding.blockPhase} : expected.get(data.request.url.slice(origin.length));
        assert.ok(plan && plan.role === binding.role);
        assert.equal(data.frameId, binding.frameID);
        assert.equal(data.loaderId, binding.loaderID);
        assert.ok(!observed.has(lookup), 'unexpected extra send');
        const record = {role:binding.role, phase:plan.phase, urlSHA256:fingerprint(data.request.url), sessionSHA256:fingerprint(event.sessionId),
          requestSHA256:fingerprint([event.sessionId,data.requestId]), originalFrame:true, originalLoader:true,
          status:null, terminal:null};
        observed.set(lookup, record);
        log('browser','requestWillBeSent', {...record, browserTime:data.timestamp});
      } else if (observed.has(lookup)) {
        const record = observed.get(lookup);
        if (event.method === 'Network.responseReceived') {
          assert.equal(data.frameId, binding.frameID);
          assert.equal(data.loaderId, binding.loaderID);
          record.status = data.response.status;
          log('browser','responseReceived', {role:record.role, phase:record.phase, requestSHA256:record.requestSHA256,
            status:record.status, browserTime:data.timestamp});
        } else if (event.method === 'Network.loadingFinished' || event.method === 'Network.loadingFailed') {
          assert.equal(record.terminal,null);
          record.terminal = event.method.slice(8);
          if (record.terminal === 'loadingFailed') {
            record.error = /^net::ERR_[A-Z_]+$/.test(data.errorText) ? data.errorText : 'unspecified';
            record.canceled = data.canceled === true;
            record.blockedReason = ['inspector','other','subresource-filter'].includes(data.blockedReason) ? data.blockedReason : null;
          }
          log('browser',record.terminal, {...record, browserTime:data.timestamp});
        }
      }
    }
  };
  child.stdio[4].on('data',consume);
  return {sessions, observed, stop() {child.stdio[4].off('data',consume);}};
}

function localClient(port, phase, log) {
  return new Promise((resolve, reject) => {
    const bytes = body('client',phase);
    log('client','request-start',{role:'client',phase,bodyBytes:bytes.length});
    const request = http.request({hostname:'127.0.0.1',port,method:'POST',path:phases.indexOf(phase)>=4?'/fixed/exact-resource':key('client',phase),agent:false,
      headers:{'content-length':bytes.length, 'x-owned-case':'client/'+phase}}, response => {
      let size = 0;
      response.on('data', chunk => { size += chunk.length; });
      response.once('error',reject);
      response.once('end', () => {
        log('client','response-end',{role:'client',phase,status:response.statusCode,responseBytes:size});
        resolve({kind:'response',status:response.statusCode,responseBytes:size});
      });
    });
    request.setTimeout(10000, () => request.destroy(Error('client deadline')));
    request.once('error',reject);
    request.end(bytes);
  });
}

async function run(family, executable, privateDir) {
  const events = [];
  const start = performance.now();
  const journal = path.join(privateDir, family.toLowerCase() + '-journal.ndjson');
  fs.writeFileSync(journal, '', {flag:'wx',mode:0o600});
  const log = (source, event, fields = {}) => {
    const row = {number:events.length+1,elapsedMs:Number((performance.now()-start).toFixed(3)),source,event,...fields};
    events.push(row);
    fs.appendFileSync(journal, JSON.stringify(row)+'\n');
  };
  const site = createSite(log);
  const profile = fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-owned-network-scope-'));
  const tabs = {};
  let child, exit, driver, wire, restoreNeeded = false, blockSet = false, data, status;
  const cleanup = {};
  async function verifyTab(role) {
    const tab=tabs[role], info=await driver.call('Target.getTargetInfo',{targetId:tab.targetId});
    assert.equal(info.targetInfo.targetId,tab.targetId);
    assert.equal(info.targetInfo.url,tab.file);
    const {frameTree} = await driver.call('Page.getFrameTree',{},tab.sessionId);
    assert.ok(!frameTree.childFrames?.length);
    assert.equal(frameTree.frame.url,tab.file);
    const doc = await driver.fixture(tab,'identity');
    assert.equal(doc.original,true); assert.equal(doc.role,role);
    assert.ok(typeof doc.documentID==='string' && doc.documentID.length===36 && doc.timeOrigin>0);
    const proof={target:fingerprint(tab.targetId),session:fingerprint(tab.sessionId),frame:fingerprint(frameTree.frame.id),
      loader:fingerprint(frameTree.frame.loaderId),document:fingerprint(doc),originalURL:true};
    if (tab.proof) assert.deepEqual(tab.proof,proof,'original document changed');
    tab.proof=proof;
    wire.sessions.set(tab.sessionId,{role,frameID:frameTree.frame.id,loaderID:frameTree.frame.loaderId});
    return proof;
  }
  async function condition(offline) {
    const tab=tabs.target;
    await verifyTab('target');
    await driver.call('Network.emulateNetworkConditions',{offline,latency:0,downloadThroughput:-1,uploadThroughput:-1},tab.sessionId);
    restoreNeeded=offline;
    log('condition',offline?'offline-applied':'online-restored',{session:tab.proof.session,target:tab.proof.target});
  }
  try {
    await new Promise((resolve,reject)=>{site.server.once('error',reject);site.server.listen(0,'127.0.0.1',resolve);});
    const port=site.server.address().port;
    const origin='http://127.0.0.1:'+port;
    child=spawn(executable,['--headless=new','--remote-debugging-pipe','--user-data-dir='+profile,
      '--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-component-update',
      '--disable-sync','--disable-extensions','--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','about:blank'],
      {detached:true,stdio:['ignore','ignore','ignore','pipe','pipe']});
    exit=new Promise(resolve=>{child.once('exit',resolve);child.once('error',resolve);});
    driver=new FixtureDriver(child); wire=collect(child,origin,log);
    const version=await driver.call('Browser.getVersion');
    const userAgent=version.userAgent;
    assert.equal(/Edg\//.test(userAgent),family==='Edge');
    const procBirth=fingerprint([child.pid,performance.timeOrigin,start]);
    for (const role of ['target','peer']) {
      const file=origin+'/scope/'+role;
      tabs[role]={...await driver.open('about:blank'),file};
      const tab=tabs[role];
      await driver.call('Page.enable',{},tab.sessionId);
      await driver.call('Network.enable',{maxPostDataSize:0},tab.sessionId);
      await driver.call('Page.navigate',{url:file},tab.sessionId);
      await until(async()=>{
        try {return (await driver.fixture(tab,'identity')).role===role;} catch {return false;}
      },'own page '+role);
      await verifyTab(role);
    }
    assert.notEqual(tabs.target.targetId,tabs.peer.targetId);
    assert.notEqual(tabs.target.proof.document,tabs.peer.proof.document);
    await driver.call('Target.activateTarget',{targetId:tabs.target.targetId});
    log('binding','two-owned-tabs',{sameBrowserProcess:true,ownedSpawnSHA256:procBirth,
      target:tabs.target.proof,peer:tabs.peer.proof});
    const results={};
    const launch=(role,phase)=>role==='client'?localClient(port,phase,log):driver.fixture(tabs[role],'request',phase);
    async function group(phase) {
      const values=await Promise.all(roles.map(role=>launch(role,phase)));
      results[phase]=Object.fromEntries(roles.map((role,index)=>[role,values[index]]));
    }
    await group('baseline');
    const inFlight=group('in-flight');
    // All three servers have actually received a nonempty prefix. No response has been issued.
    await until(()=>roles.every(role=>site.held.has(key(role,'in-flight'))),'three owned in-flight requests');
    const prefix=Object.fromEntries(roles.map(role=>{
      const f=site.received.get(key(role,'in-flight'));
      assert.ok(f.bytes>0 && f.bytes<body(role,'in-flight').length && !f.requestEnded && !f.responseFinished);
      return [role,f.bytes];
    }));
    log('condition','before-offline',{serverReceivedBytes:prefix,allRepliesWithheld:true});
    await condition(true);
    await group('offline-new');
    log('server','release-in-flight-readers');
    site.release();
    await inFlight;
    await condition(false);
    await verifyTab('peer');
    await group('restored');
    const measuredPhases=phases.slice(0,4);
    // Only if Offline leaves the original in-flight request successful, test the separate
    // browser-native pre-request block for one exact fixed resource in this private session.
    if (results['in-flight'].target.kind==='response') {
      const fixedURL=origin+'/fixed/exact-resource';
      await verifyTab('target');
      await verifyTab('peer');
      await driver.call('Network.setBlockedURLs',{urls:[fixedURL]},tabs.target.sessionId);
      blockSet=true; log('condition','single-exact-resource-block-enabled',{urlSHA256:fingerprint(fixedURL),target:tabs.target.proof.target});
      for (const role of ['target','peer']) wire.sessions.get(tabs[role].sessionId).blockPhase='blocked-new';
      await group('blocked-new');
      await driver.call('Network.setBlockedURLs',{urls:[]},tabs.target.sessionId);
      blockSet=false; log('condition','single-exact-resource-block-cleared',{target:tabs.target.proof.target});
      for (const role of ['target','peer']) wire.sessions.get(tabs[role].sessionId).blockPhase='unblocked';
      await group('unblocked');
      measuredPhases.push('blocked-new','unblocked');
    }
    await until(()=>wire.observed.size===measuredPhases.length*2 && [...wire.observed.values()].every(r=>r.terminal),'eight browser terminal events');
    await until(()=>[...site.received.values()].every(r=>r.responseClosed),'original server responses terminal');
    const cases=[];
    for (const phase of measuredPhases) for (const role of roles) {
      const label=key(role,phase), f=site.received.get(label);
      const observed=[...wire.observed.values()].filter(r=>r.role===role && r.phase===phase);
      assert.equal(observed.length,role==='client'?0:1);
      const bytes=body(role,phase), end=results[phase][role];
      if (end.kind==='response') {
        assert.equal(end.status,statusCode);assert.equal(end.responseBytes,reply.length);
        assert.ok(f?.requestEnded && f.responseFinished);
        assert.equal(f.bytesSHA256,sha(bytes));assert.equal(f.bytes,bytes.length);
        if (role!=='client') {assert.equal(observed[0].terminal,'loadingFinished');assert.equal(observed[0].status,statusCode);}
      } else {
        assert.ok(['in-flight','offline-new','blocked-new'].includes(phase));
        assert.equal(observed[0].terminal,'loadingFailed');
      }
      cases.push({role,phase,expectedBodyBytes:bytes.length,expectedBodySHA256:sha(bytes),caller:end,
        browser:observed[0]||null,server:f||{requestObserved:false,bytes:0},
        completedBodyMatched:!!f?.requestEnded && f?.bytesSHA256===sha(bytes)});
    }
    data={family,product:version.product,productVersion:(family==='Edge'?/Edg\/([0-9.]+)/:/Chrome\/([0-9.]+)/).exec(userAgent)?.[1],
      browserCondition:'Network.emulateNetworkConditions',sameOwnedBrowserProcess:true,rendererPIDMeasured:false,
      visibleDevToolsPanelOperated:false,conditionOnlySentToTarget:true,baselineWasFreshProfileDefault:true,
      exactResourceBlockingMeasured:measuredPhases.includes('blocked-new'),originalTargets:{target:await verifyTab('target'),peer:await verifyTab('peer')},bytesBeforeOffline:prefix,cases};
    status='MEASURED';
  } finally {
    site.release();
    try {
      if (restoreNeeded && driver && tabs.target) await condition(false);
      cleanup.conditionRestoredOrNeverSet=!restoreNeeded;
      if(blockSet) {await driver.call('Network.setBlockedURLs',{urls:[]},tabs.target.sessionId);blockSet=false;}
      cleanup.exactResourceBlockClearedOrNeverSet=!blockSet;
      if (wire) wire.stop();
      if (driver) for(const role of Object.keys(tabs)) {
        const r=await driver.call('Target.closeTarget',{targetId:tabs[role].targetId});
        assert.equal(r.success,true);
      }
      cleanup.ownedTabsCloseAcknowledged=Object.keys(tabs).length;
    } finally {
      try {
        if (child?.pid) await cleanupOwnedChrome(child,exit);
        cleanup.ownedProcessGroupExited=true;
        fs.rmSync(profile,{recursive:true,force:true});
        cleanup.freshProfileRemoved=!fs.existsSync(profile);
      } finally {
        if (site.server.listening) await closeLoopbackServer(site.server,site.sockets);
      }
      await until(()=>site.sockets.size===0,'owned sockets closed');
      cleanup.serverListening=site.server.listening;
      cleanup.serverSockets=site.sockets.size;
      cleanup.issuedServerRequestsStillOpen=[...site.received.values()].filter(x=>!x.responseClosed).length;
      log('cleanup','completed',cleanup);
    }
  }
  return {status,data,cleanup,events};
}

async function main() {
  assert.equal(process.argv.length,2,'No arguments accepted');
  const privateDir=fs.mkdtempSync(path.join('/private/tmp','riftlet61-local-condition-scope-'));
  const results=[],artifacts={};
  for(const [family,binary] of Object.entries(families)) {
    const result=await run(family,binary,privateDir);
    const name=family.toLowerCase()+'-events.json';
    const raw=JSON.stringify(result.events,null,2)+'\n';
    fs.writeFileSync(path.join(privateDir,name),raw,{flag:'wx',mode:0o600});
    artifacts[name]=sha(raw);
    const journal=family.toLowerCase()+'-journal.ndjson';
    artifacts[journal]=sha(fs.readFileSync(path.join(privateDir,journal)));
    results.push({status:result.status,...result.data,cleanup:result.cleanup,eventCount:result.events.length});
  }
  const receipt={schema:1,scope:'Fixed HTTP loopback POSTs in two disposable native headless browser instances',
    sources:Object.fromEntries(['fixture.js','run.cjs'].map(file=>[file,sha(source(file))])),
    bodyKind:'fixed synthetic bytes, no File or screenshot',wholeBrowserTrafficObserved:false,artifacts,results};
  fs.writeFileSync(path.join(privateDir,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{flag:'wx',mode:0o600});
  console.log(privateDir);
}
main().catch(e=>{console.error(e.stack);process.exitCode=1;});
