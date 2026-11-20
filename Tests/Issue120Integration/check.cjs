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

test('Swift provider and reopened SQLite observe one real headless fixture input',async()=>{
  const token=randomBytes(24).toString('hex');
  const chrome='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
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
  const server=http.createServer(async(req,res)=>{
    try {
      if (req.socket.remoteAddress!=='127.0.0.1') {res.writeHead(403);res.end();return}
      res.setHeader('Cache-Control','no-store');
      if(req.url==='/app' && program) {
        res.setHeader('Content-Security-Policy',"default-src 'none'; script-src 'self'; img-src data:; connect-src 'self'; form-action 'none'");
        send(res,'text/html; charset=utf-8','<!doctype html><form><fieldset><div role="textbox" contenteditable="true">original draft</div><label for="picker">Upload</label><input id="picker" type="file"><section><article>prior test attachment</article></section></fieldset></form><form><input type="file" id="foreign"></form><script src="/'+token+'/program.js"></script><script src="/'+token+'/case.js"></script>');
      } else if(req.url==='/'+token+'/program.js') {
        send(res,'text/javascript','const fixtureProvider = '+program+';\n');
      } else if(req.url==='/'+token+'/case.js') {
        send(res,'text/javascript',fs.readFileSync(path.join(__dirname,'page.js'),'utf8')+
          '\nrun('+JSON.stringify(token)+','+JSON.stringify(click)+');');
      } else if(req.url==='/'+token+'/next' && req.method==='GET' && !delivery) {
        delivery=res;deliver();
      } else if(req.url==='/'+token+'/reply' && req.method==='POST') {
        const chunks=[];for await(const chunk of req) chunks.push(chunk);
        const result=JSON.parse(Buffer.concat(chunks));
        assert.equal(result.action,command.action);assert.notEqual(result.result,'error',result.reason);
        if(result.action==='finish') last=result;
        if(result.action==='observe') observations.push(result.result);
        command=null;
        driver.stdin.write(JSON.stringify(result)+'\n');res.end('ok');
      } else {res.writeHead(404);res.end()}
    } catch(error){ res.end();fail(error) }
  });
  let reject;
  const failure=new Promise((_,r)=>{reject=r});
  const fail=e=>{if (!completed) reject(e)};
  try {
    server.listen(0,'127.0.0.1');await once(server,'listening');
    const origin='http://127.0.0.1:'+server.address().port;
    deadline=setTimeout(()=>fail(Error('fixture exchange deadline; last action '+actions.at(-1))),30000);
    driver=spawn(process.env.RIFTLET_CHAIN_DRIVER,[origin],{stdio:['pipe','pipe','inherit']});
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
            '--no-default-browser-check','--user-data-dir='+temp,origin+'/app'],{stdio:'ignore'});
          browser.once('error',fail);
          browser.once('exit',()=>fail(Error('fixture browser exited')));
        } else deliver();
      }catch(e){fail(e)}
    });
    const [code]=await Promise.race([once(driver,'exit'),failure]);
    assert.equal(code,0);assert.deepEqual(actions,['pin','validate','commit','observe','fail','observe','finish']);
    assert.deepEqual(last,{action:'finish',result:'checked',inputs:1,changes:1,foreign:0,sends:0,
      oldAttachmentsPreserved:true,textAndSelectionPreserved:true});
    assert.deepEqual(observations,['accepted_into_draft','original_card_failed']);
    const browserVersion=execFileSync('/usr/bin/plutil',['-extract','CFBundleShortVersionString','raw',
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
    server.closeAllConnections();await new Promise(resolve=>server.close(resolve));
    fs.rmSync(temp,{recursive:true,force:true,maxRetries:4});
  }
});
