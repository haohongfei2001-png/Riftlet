'use strict';
// Owns its headless child, both generated local tabs, and the disposable native host.
const assert = require('node:assert/strict');
const {execFileSync,spawn} = require('node:child_process');
const {createHash,randomUUID} = require('node:crypto');
const fs = require('node:fs'), http = require('node:http'), net = require('node:net');
const os = require('node:os'), path = require('node:path');
const {DatabaseSync} = require('node:sqlite');
const {FixtureDriver} = require('../../OriginalDocumentDelivery/renderer/driver.cjs');
const experiment = path.resolve(__dirname,'../../../Experiments/PreClickDocumentStart');
const png='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2ZsAAAAASUVORK5CYII=';
const previous='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
const sha = bytes=>createHash('sha256').update(bytes).digest('hex');
const delay = ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function until(check, description) {
  const deadline=performance.now()+7000;
  do { const result=await check(); if(result) return result; await delay(40); } while(performance.now()<deadline);
  throw new Error('Unobserved: '+description);
}
function request(socketPath,command) {
  return new Promise((resolve,reject)=>{
    const socket=net.createConnection(socketPath); let text='';
    socket.setEncoding('utf8'); socket.setTimeout(1000,()=>socket.destroy(Error('owned socket timed out')));
    socket.on('connect',()=>socket.end(JSON.stringify(command)+'\n'));
    socket.on('data',part=>{text+=part}); socket.once('end',()=>{try {resolve(JSON.parse(text))} catch (e){reject(e)}});
    socket.on('error',reject);
  });
}
function hostPID(host) {
  const result=execFileSync('/usr/sbin/lsof',['-t',path.join(host,'host.lock')],{encoding:'utf8'}).trim();
  assert.match(result,/^[1-9]\d*$/);
  const pid=Number(result);
  const argv=execFileSync('/bin/ps',['-p',result,'-o','command='],{encoding:'utf8'});
  assert.ok(argv.includes(path.join(host,'native_host.py')+' '),'process must be this private native host');
  return pid;
}
function checkPreservation(state,expectedCount) {
  assert.equal(state.text,true); assert.equal(state.selection,true); assert.equal(state.previous,true);
  assert.equal(state.previousSHA,sha(Buffer.from(previous,'base64')));
  assert.equal(state.input,expectedCount); assert.equal(state.change,expectedCount); assert.equal(state.send,0);
  assert.equal(state.receivedSHA,expectedCount?sha(Buffer.from(png,'base64')):null);
}
async function run(browser,label) {
  assert.ok(path.isAbsolute(browser));
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'r108-tab-restart-'));
  const profile=path.join(root,'profile'),host=path.join(root,'host'),ext=path.join(root,'extension');
  const route='/riftlet-preclick-lab/'+randomUUID(), diagnostics=[];
  const html=fs.readFileSync(path.join(__dirname,'tab-restart-fixture.html'));
  const server=http.createServer((req,res)=>{
    if(req.method==='GET' && [route,route+'/away'].includes(req.url)) {
      res.writeHead(200,{'content-type':'text/html;charset=utf-8','cache-control':'no-store'});res.end(html);return;
    }
    if(req.method==='POST' && req.url===route+'/report') {
      let data='';req.setEncoding('utf8');
      req.on('data',chunk=>{data+=chunk;if(data.length>2048)req.destroy()});
      req.on('end',()=>{const report=JSON.parse(data);if(report.action==='diagnostic') diagnostics.push(report.stage);res.writeHead(204);res.end()});return;
    }
    res.writeHead(404);res.end();
  });
  let child,driver,exited;
  try {
    await new Promise((resolve,reject)=>server.once('error',reject).listen(0,'127.0.0.1',resolve));
    const url='http://127.0.0.1:'+server.address().port+route;
    fs.cpSync(path.join(experiment,'extension'),ext,{recursive:true});
    fs.writeFileSync(path.join(ext,'scope.js'),'globalThis.riftletLabURL='+JSON.stringify(url)+';\n');
    const key=Buffer.from(JSON.parse(fs.readFileSync(path.join(ext,'manifest.json'))).key,'base64');
    const extensionID=Array.from(sha(key).slice(0,32),x=>String.fromCharCode(97+parseInt(x,16))).join('');
    const origin='chrome-extension://'+extensionID+'/';
    fs.mkdirSync(host,{mode:0o700});
    const hostPath=path.join(host,'native_host.py');
    fs.copyFileSync(path.join(experiment,'native_host.py'),hostPath);fs.chmodSync(hostPath,0o700);
    fs.writeFileSync(path.join(host,'config.json'),JSON.stringify({extensionOrigin:origin,fixturePNG:png}));
    const manifests=path.join(profile,'NativeMessagingHosts');fs.mkdirSync(manifests,{recursive:true});
    const name='com.riftlet.preclick_lab';
    fs.writeFileSync(path.join(manifests,name+'.json'),JSON.stringify({name,description:'Disposable QA native host',path:hostPath,type:'stdio',allowed_origins:[origin]}));
    const eventTool=path.join(root,'event');
    execFileSync('swiftc',[path.join(__dirname,'event.swift'),'-o',eventTool]);
    child=spawn(browser,['--headless=new','--remote-debugging-pipe','--no-first-run','--no-default-browser-check',
      '--disable-sync','--disable-component-update','--disable-background-networking','--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1',
      '--user-data-dir='+profile,'--disable-extensions-except='+ext,'--load-extension='+ext,'about:blank'],
      {detached:true,stdio:['ignore','ignore','ignore','pipe','pipe']});
    exited=new Promise(resolve=>child.once('exit',resolve));driver=new FixtureDriver(child);
    const ipc=message=>request(path.join(host,'input.sock'),message);
    const current=()=>ipc({action:'current'});
    const pin=()=>until(async()=>{try{const value=await current();return value.ack && value}catch{return false}},'browser and host ACK');
    function click(p,op,dropReply=false) {
      const eventNS=Number(execFileSync(eventTool,{encoding:'utf8'}).trim());assert.ok(Number.isSafeInteger(eventNS));
      return ipc({action:'click',key:p.key,ack:p.ack,eventNS,op,dropReply});
    }
    async function state(op) {return (await ipc({action:'state',op})).state}
    const snapshot=tab=>driver.fixture(tab,'snapshot');
    async function shown(tab,vis) {return until(async()=>{const s=await snapshot(tab);return s.visibility===vis && s},vis+' in owned tab')}
    async function refused(old) {const op=randomUUID();assert.equal((await click(old,op)).state,'REFUSED');assert.equal(await state(op),'ABSENT')}
    const a=await driver.open(url),original=await pin();
    const host1=hostPID(host), claimed=randomUUID();
    assert.equal((await click(original,claimed,true)).state,'CLAIMED');
    await until(async()=>{const s=await snapshot(a);return s.change===1},'original image input');
    const db=new DatabaseSync(path.join(host,'claims.sqlite'),{readOnly:true});
    try {await until(()=>db.prepare('select observed_drop from op where id=?').get(claimed)?.observed_drop===1,'host recorded lost reply')}
    finally {db.close()}
    assert.equal(await state(claimed),'UNKNOWN');
    checkPreservation(await shown(a,'visible'),1);
    const b=await driver.open(url+'/away');
    assert.notEqual(a.targetId,b.targetId);
    await driver.call('Target.activateTarget',{targetId:b.targetId});
    checkPreservation(await shown(a,'hidden'),1);checkPreservation(await shown(b,'visible'),0);
    await until(async()=>!(await current()).ack,'revocation after A to B'); await refused(original);
    await driver.call('Target.activateTarget',{targetId:a.targetId});
    checkPreservation(await shown(a,'visible'),1);checkPreservation(await shown(b,'hidden'),0);
    const returned=await pin();
    assert.equal(returned.key.tabId,original.key.tabId);assert.equal(returned.key.windowId,original.key.windowId);
    assert.equal(returned.key.documentId,original.key.documentId);
    assert.notEqual(returned.key.ticket,original.key.ticket);assert.notEqual(returned.ack,original.ack);
    await refused(original);
    const closedBefore=diagnostics.filter(x=>x==='content_port_closed').length;
    assert.equal(hostPID(host),host1); process.kill(host1,'SIGTERM');
    await until(()=>diagnostics.filter(x=>x==='content_port_closed').length>closedBefore,'native disconnect delivered to original document');
    checkPreservation(await snapshot(a),1);
    const c=await driver.open(url),newDocument=await pin(),host2=hostPID(host);
    assert.notEqual(host2,host1);assert.notEqual(newDocument.key.documentId,original.key.documentId);
    assert.equal(await state(claimed),'UNKNOWN');
    assert.deepEqual(await click(newDocument,claimed),{state:'ALREADY_CLAIMED',previous:'UNKNOWN'});
    await refused(original);await refused(returned); checkPreservation(await snapshot(c),0);
    const newOp=randomUUID();assert.equal((await click(newDocument,newOp)).state,'CLAIMED');
    await until(async()=>await state(newOp)==='INPUT_RETURNED','fresh operation in new document');
    checkPreservation(await snapshot(c),1);checkPreservation(await snapshot(a),1);checkPreservation(await snapshot(b),0);
    return {browser:label,version:execFileSync(browser,['--version'],{encoding:'utf8'}).trim(),
      result:'PASS_CONTROLLED',realTabSwitches:['A visible','B visible; A hidden','A visible; B hidden'],
      sameOriginalTabWindowDocument:true,freshTicketAfterReturn:true,oldTicketOnB:'REFUSED_NO_CLAIM',
      oldTicketBackOnA:'REFUSED_NO_CLAIM',nativeProcessTerminated:true,originalDocumentObservedDisconnect:true,
      replacementNativeProcess:'BROWSER_LAUNCHED_ON_NEW_DOCUMENT',previousOperationAfterRestart:'UNKNOWN',
      sameOperationOnReplacementHost:'ALREADY_CLAIMED',bothOldTicketsOnReplacementHost:'REFUSED_NO_CLAIM',
      newExplicitOperation:'INPUT_RETURNED',inputs:{originalA:1,otherB:0,freshDocument:1},
      textSelectionAndOriginalAttachmentPreserved:true,bothNewFileHashesMatched:true,sends:0};
  } finally {
    if(child) {
      try {await driver.call('Browser.close')} catch {}
      if(child.exitCode===null && child.signalCode===null) {
        const done=await Promise.race([exited.then(()=>true),delay(2500).then(()=>false)]);
        if(!done){try{process.kill(-child.pid,'SIGKILL')}catch{} await exited}
      }
    }
    server.closeAllConnections();await new Promise(resolve=>server.close(resolve));
    fs.rmSync(root,{recursive:true,force:true,maxRetries:3});
  }
}
if(process.argv.length!==4) throw Error('Usage: node tab-restart.cjs /absolute/path/to/browser "label"');
run(process.argv[2],process.argv[3]).then(result=>console.log(JSON.stringify(result,null,2))).catch(error=>{console.error(error.message);process.exitCode=1});
