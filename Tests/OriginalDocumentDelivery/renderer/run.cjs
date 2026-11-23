'use strict';
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const {createHash,randomUUID} = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const {setTimeout:sleep} = require('node:timers/promises');
const {FixtureDriver} = require('./driver.cjs');
const {bounded,cleanupOwnedChrome,closeLoopbackServer} = require('../../WebPageProgram/native-chrome-cleanup.cjs');

const binaries = {chrome:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  edge:'/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'};
const html = `<!doctype html><meta charset="utf-8"><title>Riftlet isolated receiver</title>
<form id="draft"><textarea id="original"></textarea><input type="file" id="upload">
<img id="prior" alt="Existing fixture attachment" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="><button type="submit">Send</button></form>
<textarea id="other"></textarea><div id="parking"></div>
<iframe id="focusframe" srcdoc="<textarea></textarea>"></iframe>
<script src="receiver.js"></script><script src="page.js"></script>`;
const modes = ['positive','revoke','close','replaceEditor','moveReturn','focusABA','focusFrameABA',
  'historyABA','historyBack','hash','reentrant','interleave','switchInactive','switchABA','sameURL','reload','bfcache'];
const zero = {text:0,setter:0,input:0,change:0,send:0};
const success = {text:1,setter:1,input:1,change:1,send:0};
const accepted = {setter:true,input:true,change:true}, refused = {setter:false,input:false,change:false};
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

function extract(bytes) {
  const js=bytes.toString('utf8');
  const begin='// RIFTLET_ORIGINAL_RECEIVER_BEGIN',end='// RIFTLET_ORIGINAL_RECEIVER_END';
  assert.equal(js.split(begin).length,2,'missing or duplicate receiver begin');
  assert.equal(js.split(end).length,2,'missing or duplicate receiver end');
  const a=js.indexOf(begin)+begin.length,b=js.indexOf(end);
  assert.ok(b>a,'reversed boundaries');
  const body=js.slice(a,b);assert.match(body,/\bfunction bindOriginalReceiver\(/);
  return body;
}

async function until(sample,reason) {
  const deadline=performance.now()+5000;let error;
  do {
    try { const v=await sample();if(v) return v; } catch(e) { error=e; }
    await sleep(25);
  } while(performance.now()<deadline);
  throw Error(reason+(error?' '+error.message:''));
}
function checkRefusal(reply) {
  assert.deepEqual(reply.current,[false,false]);assert.deepEqual(reply.png,refused);
  assert.equal(reply.text,false);assert.deepEqual(reply.state.counts,zero);
}
async function check(driver,base,mode) {
  const url=base+mode+'/draft';
  const tab=await driver.open(url);let sibling;
  const call=(target,method,...args)=>driver.fixture(target,method,...args);
  const qa=(method,...args)=>call(tab,method,...args);
  const activate=t=>driver.call('Target.activateTarget',{targetId:t.targetId});
  const close=t=>driver.call('Target.closeTarget',{targetId:t.targetId});
  const row={mode,status:'FAIL'};
  try {
    await activate(tab);
    const before=await until(async()=>{const s=await qa('focus');return s.active&&s.visible==='visible'&&s;},'focus A');
    row.original={instance:before.instance,editor:before.editor};
    const op=randomUUID();
    if(mode==='sameURL'||mode==='reload') {
      const r=await qa('replaceFrame',mode); row.frame=r;
      assert.equal(r.before.url,r.current.url);
      assert.notEqual(r.before.instance,r.current.instance);
      assert.notEqual(r.before.editor,r.current.editor);
      assert.deepEqual(r.old,{current:[false,false],png:refused,text:false});
      assert.deepEqual(r.afterOldA.counts,zero);assert.deepEqual(r.afterOldB.counts,zero);
      assert.deepEqual(r.newCurrent,[true,true]);assert.deepEqual(r.fresh.png,accepted);
      assert.equal(r.fresh.text,true);assert.deepEqual(r.fresh.after.counts,success);
    } else {
      row.bound=await qa('stage',op);assert.deepEqual(row.bound.current,[true,true]);
      if(mode==='positive') {
        row.delivery=await qa('deliver',op); const s=row.delivery.state;
        assert.deepEqual(row.delivery.png,accepted);assert.equal(row.delivery.text,true);
        assert.equal(row.delivery.afterPNG.text,before.text);assert.deepEqual(row.delivery.afterPNG.range,before.range);
        assert.ok(row.delivery.afterPNG.priorPreserved);row.fileSHA256=await qa('fileHash');
        assert.equal(row.fileSHA256,digest(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=','base64')));
        assert.deepEqual(s.counts,success);assert.equal(s.text,op+before.text);
        assert.equal(s.text.slice(s.range[0],s.range[1]),'beta');assert.ok(s.priorPreserved);
        assert.equal(s.files.length,1);assert.equal(s.files[0].name,op+'.png');
        const replay=await qa('deliver',op);row.replay=replay;
        assert.deepEqual(replay.png,refused);assert.equal(replay.text,false);assert.deepEqual(replay.state.counts,success);
      } else if(mode==='switchInactive'||mode==='switchABA') {
        sibling=await driver.open(base+mode+'/other');await activate(sibling);
        row.switched=await until(async()=>{
          const a=await qa('state'),b=await call(sibling,'focus');
          return !a.active&&a.visible==='hidden'&&b.active&&{a:a.instance,b:b.instance};
        },'original was not hidden');
        if(mode==='switchABA') {
          await activate(tab);
          await until(async()=>{const s=await qa('state');return s.active&&s.visible==='visible';},'A reactivated');
        }
        row.delivery=await qa('deliver',op);checkRefusal(row.delivery);
        row.sibling=await call(sibling,'state');assert.deepEqual(row.sibling.counts,zero);
      } else if(mode==='historyBack') {
        row.entries=await qa('pushEntry');assert.notEqual(row.entries.original,row.entries.changed);
        await qa('navigateBack');await until(async()=>await qa('entry')===row.entries.original,'history entry did not return');
        row.delivery=await qa('deliver',op);assert.equal(row.delivery.state.instance,before.instance);
        assert.equal(row.delivery.state.url,before.url);
        assert.ok(row.delivery.state.events.filter(e=>e.type==='currententrychange'&&e.trusted).length>=2);
        checkRefusal(row.delivery);
      } else if(mode==='bfcache') {
        await driver.call('Page.navigate',{url:base+mode+'/away'},tab.sessionId);
        const away=await until(async()=>{const s=await qa('state');return s.instance!==before.instance&&s;},'away navigation');
        row.away=away;assert.deepEqual(away.counts,zero);await qa('navigateBack');
        const back=await until(async()=>{const s=await qa('state');return s.url===url&&s;},'original history entry');
        if(back.instance!==before.instance||!back.events.some(e=>e.type==='pageshow'&&e.trusted&&e.persisted)) {
          row.status='NOT_RUN';row.reason='browser created a new document instead of restoring BFCache';return row;
        }
        row.delivery=await qa('deliver',op);checkRefusal(row.delivery);
      } else if(mode==='reentrant') {
        row.insidePermit=await qa('reentrant',op);
        assert.equal(row.insidePermit.fired,1);
        checkRefusal(row.insidePermit.delivery);
      } else if(mode==='interleave') {
        const fresh=randomUUID(), replacement=await qa('interleave',op,fresh);
        row.interleaved=replacement;
        checkRefusal(replacement.old);assert.notEqual(replacement.oldEditor,replacement.freshEditor);
        assert.deepEqual(replacement.fresh.png,accepted);assert.equal(replacement.fresh.text,true);
        assert.deepEqual(replacement.fresh.state.counts,success);assert.equal(replacement.fresh.state.files[0].name,fresh+'.png');
        assert.deepEqual(replacement.oldAgain.png,refused);assert.equal(replacement.oldAgain.text,false);
        assert.deepEqual(replacement.oldAgain.state.counts,success);
      } else {
        if(mode==='close'||mode==='revoke') {await qa(mode,op);row.delivery=await qa('deliver',op);}
        else row.delivery=await qa('mutateAndDeliver',mode,op);
        checkRefusal(row.delivery);
      }
    }
    row.status='PASS';return row;
  } catch(e) { row.error=e.message;return row; }
  finally {if(sibling) await close(sibling);await close(tab);}
}

async function main() {
  const [family,resource]=process.argv.slice(2);
  assert.ok(binaries[family]&&resource&&path.isAbsolute(resource),'usage: node run.cjs chrome|edge <absolute product JS>');
  const visible=process.env.RIFTLET_CI_VISIBLE==='1';
  assert.ok(!visible||process.env.GITHUB_ACTIONS==='true','normal window mode is for isolated GitHub runners only');
  const buf=fs.readFileSync(resource),body=extract(buf),fixture=fs.readFileSync(path.join(__dirname,'page.js'));
  const prefix='/'+randomUUID()+'/',profile=fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-receiver-'));
  const server=http.createServer((req,res)=>{
    const pathname=(req.url||'').split('?')[0];
    if(!pathname.startsWith(prefix)){res.writeHead(404);res.end();return;}
    const file=pathname.split('/').at(-1);
    const responses={'receiver.js':['text/javascript',body+'\nwindow.bindOriginalReceiver=bindOriginalReceiver;'],
      'page.js':['text/javascript',fixture],draft:['text/html',html],frame:['text/html',html],other:['text/html',html],away:['text/html',html]};
    if(!Object.hasOwn(responses,file)) {res.writeHead(404);res.end();return;}
    const [type,content]=responses[file];res.writeHead(200,{'content-type':type+'; charset=utf-8'});res.end(content);
  });
  server.on('connect',(_,s)=>s.destroy());server.on('upgrade',(_,s)=>s.destroy());
  const sockets=new Set();server.on('connection',s=>{sockets.add(s);s.once('close',()=>sockets.delete(s));});
  let child,exited,cleaned=false;
  try {
    await bounded(new Promise((ok,fail)=>{server.once('error',fail);server.listen(0,'127.0.0.1',ok);}),3000,'listen');
    const origin='127.0.0.1:'+server.address().port;
    const args=[...(visible?[]:['--headless=new']),'--remote-debugging-pipe','--user-data-dir='+profile,
      '--disable-sync','--disable-extensions','--disable-background-networking','--disable-component-update',
      '--no-first-run','--no-default-browser-check','--disable-quic','--disable-crash-reporter',
      '--proxy-server=http://'+origin,'--proxy-bypass-list='+origin,'--force-webrtc-ip-handling-policy=disable_non_proxied_udp',
      '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','about:blank'];
    child=spawn(binaries[family],args,{detached:true,stdio:['ignore','ignore','ignore','pipe','pipe']});
    exited=new Promise(resolve=>child.once('exit',resolve));
    const driver=new FixtureDriver(child);
    const version=(await driver.call('Browser.getVersion')).product;
    const cases=[];
    for(const mode of modes) cases.push(await check(driver,'http://'+origin+prefix,mode));
    return {family,version,arch:process.arch,visible,mode:visible?'isolated-ci-normal-window':'owned-headless',
      ciRunId:process.env.GITHUB_RUN_ID||null,sourceSHA256:digest(buf),receiverSHA256:digest(body),
      scope:'Isolated loopback renderer, production receiver excerpt, semantic text and real PNG file setter',cases};
  } finally {
    try{await cleanupOwnedChrome(child,exited);cleaned=true;}finally{await closeLoopbackServer(server,sockets);if(cleaned)fs.rmSync(profile,{recursive:true});}
  }
}
main().then(result=>{
  console.log(JSON.stringify(result,null,2));
  if(result.cases.some(c=>c.status!=='PASS'))process.exitCode=1;
}).catch(e=>{console.error(e.message);process.exitCode=1;});
