'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const readline = require('node:readline');
const {randomBytes}=require('node:crypto');
const {spawn,execFileSync}=require('node:child_process');
const {createHash}=require('node:crypto');
const {once}=require('node:events');

const geminiPage = '<fieldset><div role="textbox" contenteditable="true">original draft</div><label for="picker">Upload</label><input id="picker" type="file"><section data-fixture-lane><article>prior test attachment</article></section></fieldset>';
// All selectors and card states here are owned by this loopback test.
const claudePage = '<div data-fixture-editor contenteditable="true">original draft</div><button type="button" data-fixture-upload aria-controls="picker">Attach PNG</button><input id="picker" type="file" hidden><ul data-fixture-lane><li>prior test attachment</li></ul>';

for (const [profileID, route, composer, dropReply] of [
  ['fixture-gemini-like', '/app', geminiPage, false],
  ['fixture-claude-like', '/fixture-claude-like', claudePage, false],
  ['fixture-claude-like', '/fixture-claude-like', claudePage, true]
]) test(profileID+(dropReply ? ' lost reply' : ' original-card failure')+' across SQLite reopen',async()=>{
  const token=randomBytes(24).toString('hex');
  const chrome=process.env.RIFTLET_HEADLESS_SHELL || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-chain-'));
  let browser, driver, command=null, delivery, program, click, last, deadline, completed=false;
  const observations=[];
  const actions=[];
  const send=(reply,kind,body)=>{reply.setHeader('Content-Type',kind);reply.end(body)};
  function deliver() {
    if (!command || !delivery || command.action==='pin' || command.dispatched) return;
    command.dispatched=true;
    send(delivery,'application/json',JSON.stringify(command));delivery=null;
  }
  let origin, otherOrigin;
  const serve=async(req,res)=>{
    try {
      if (req.socket.remoteAddress!=='127.0.0.1') {res.writeHead(403);res.end();return}
      res.setHeader('Cache-Control','no-store');
      if((req.url===route || req.url==='/wrong-path') && program) {
        res.setHeader('Content-Security-Policy',"default-src 'none'; script-src 'self'; img-src data:; connect-src 'self'; frame-src 'self' "+otherOrigin+"; form-action 'none'");
        send(res,'text/html; charset=utf-8','<!doctype html><form>'+composer+'<button type="submit">Send</button></form><form><input type="file" id="foreign"></form><script src="/'+token+'/program.js"></script><script src="/'+token+'/case.js"></script>');
      } else if(req.url==='/'+token+'/program.js') {
        send(res,'text/javascript','const fixtureProvider = '+program+';\n');
      } else if(req.url==='/'+token+'/case.js') {
        const extra = profileID==='fixture-claude-like' ? fs.readFileSync(path.join(__dirname,'claude-like.js'),'utf8') : '';
        send(res,'text/javascript',fs.readFileSync(path.join(__dirname,'page.js'),'utf8')+'\n'+extra+
          '\nif (self === top) run('+[token,click,otherOrigin,dropReply].map(v=>JSON.stringify(v)).join(',')+');'+
          '\nelse if (location.origin === '+JSON.stringify(origin)+') window.localProvider = fixtureProvider;'+
          '\nelse parent.postMessage({state:fixtureProvider.inspect(), refused:refusesPin(fixtureProvider)},'+JSON.stringify(origin)+');');
      } else if(req.url==='/'+token+'/next' && req.method==='GET' && !delivery) {
        delivery=res;deliver();
      } else if(req.url==='/'+token+'/reply' && req.method==='POST') {
        const chunks=[];for await(const chunk of req) chunks.push(chunk);
        const result=JSON.parse(Buffer.concat(chunks));
        assert.equal(result.action,command.action);assert.notEqual(result.result,'error',result.reason);
        if(result.action==='finish') last=result;
        if(result.action==='observe') observations.push(result.result);
        command=null;
        // Drop the otherwise valid commit acknowledgement after the page has
        // returned. Only the transport sees a missing reply. Keep the real DOM.
        const reply = dropReply && result.action==='commit' ? {action:'commit',result:'reply-lost'} : result;
        driver.stdin.write(JSON.stringify(reply)+'\n');res.end('ok');
      } else {res.writeHead(404);res.end()}
    } catch(error){ res.end();fail(error) }
  };
  const server=http.createServer(serve);
  // The other origin only serves static fixture pages. It cannot use the Swift bridge.
  const alternate=http.createServer((req,res)=>{
    if (![route, '/'+token+'/program.js', '/'+token+'/case.js'].includes(req.url)) { res.writeHead(404).end(); return; }
    void serve(req,res);
  });
  let reject;
  const failure=new Promise((_,r)=>{reject=r});
  const fail=e=>{if (!completed) reject(e)};
  try {
    server.listen(0,'127.0.0.1');await once(server,'listening');
    origin='http://127.0.0.1:'+server.address().port;
    alternate.listen(0,'127.0.0.1');await once(alternate,'listening');
    otherOrigin='http://127.0.0.1:'+alternate.address().port;
    deadline=setTimeout(()=>fail(Error('fixture exchange deadline; last action '+actions.at(-1))),30000);
    driver=spawn(process.env.RIFTLET_CHAIN_DRIVER,[origin,profileID,dropReply?'lost':'accepted'],{stdio:['pipe','pipe','inherit']});
    driver.once('error',fail);
    driver.stdin.on('error',fail);
    readline.createInterface({input:driver.stdout}).on('line',line=>{
      try {
        assert.equal(command,null);
        command=JSON.parse(line);actions.push(command.action);
        if(command.action==='pin'){
          assert.equal(browser,undefined);program=command.program;click=command.click;
          browser=spawn(chrome,['--headless',
            '--disable-extensions','--disable-background-networking','--no-proxy-server',
            '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','--disable-sync','--no-first-run',
            '--no-default-browser-check','--user-data-dir='+temp,origin+route],{stdio:'ignore'});
          browser.once('error',fail);
          browser.once('exit',()=>fail(Error('fixture browser exited')));
        } else deliver();
      }catch(e){fail(e)}
    });
    const [code]=await Promise.race([once(driver,'exit'),failure]);
    assert.equal(code,0,'driver exited after '+actions.join(', ')+'; observations '+observations.join(', '));
    assert.deepEqual(actions,dropReply ? ['pin','validate','commit','observe','observe','finish']
      : ['pin','validate','commit','observe','fail','observe','finish']);
    const {counterexamples,...counts}=last;
    if(profileID==='fixture-claude-like' && !dropReply) assert.deepEqual(counterexamples,[
      'cross-origin','wrong-path','ambiguous-action','foreign-picker','wrong-editor',
      'wrong-invocation','foreign-draft-card','adjacent-card','duplicate-card','wrong-bytes','responsive-source','prior-card-removed',
      'navigation','same-url-new-document','draft-edit-before-input','draft-edit-before-receipt'
    ]);
    assert.deepEqual(counts,{action:'finish',result:'checked',setters:1,inputs:1,changes:1,foreign:0,sends:0,
      oldAttachmentsPreserved:true,textAndSelectionPreserved:true});
    assert.deepEqual(observations,dropReply ? ['unknown','unknown'] : ['accepted_into_draft','original_card_failed']);
    const browserVersion=process.env.RIFTLET_HEADLESS_SHELL ? execFileSync(chrome,['--version'],{encoding:'utf8'}).trim()
      : execFileSync('/usr/bin/plutil',['-extract','CFBundleShortVersionString','raw',
        '/Applications/Google Chrome.app/Contents/Info.plist'],{encoding:'utf8'}).trim();
    console.log(JSON.stringify({scope:'development-loopback',browserVersion,actions,observations,
      boundProgramSHA256:createHash('sha256').update(program).digest('hex'),page:last}));
  } finally {
    completed=true;clearTimeout(deadline);
    for(const child of [driver,browser]){
      if(child && child.exitCode===null && child.signalCode===null){
        const exit=once(child,'exit');child.kill('SIGTERM');await exit;
      }
    }
    for(const host of [server,alternate]) {
      host.closeAllConnections();await new Promise(resolve=>host.close(resolve));
    }
    fs.rmSync(temp,{recursive:true,force:true,maxRetries:4});
  }
});
