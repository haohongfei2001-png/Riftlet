'use strict';
const http=require('node:http');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const puppeteer=require(process.env.RIFTLET_PUPPETEER||'puppeteer-core');
async function main() {
  const files=new Map([
    ['/draft', ['text/html', 'fixture/index.html']],
    ['/providers/fixture/cases.mjs',['text/javascript','fixture/cases.mjs']],
    ['/providers/fixture/synthetic-handoff.mjs',['text/javascript','fixture/synthetic-handoff.mjs']],
    ['/providers/gemini-surface.mjs',['text/javascript','gemini-surface.mjs']],
    ['/contract/observation.mjs',['text/javascript','../contract/observation.mjs']]
  ]);
  const server=http.createServer((req,res)=>{
    const file=files.get(req.url);
    if(!file || req.method!=='GET'){res.writeHead(404).end();return;}
    res.writeHead(200,{'Content-Type':file[0]+'; charset=utf-8','Cache-Control':'no-store',
      'Content-Security-Policy':"default-src 'self'; script-src 'self'; img-src data:; style-src 'unsafe-inline'; connect-src 'self'; form-action 'none'; object-src 'none'"});
    res.end(fs.readFileSync(path.join(__dirname,file[1])));
  });
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-provider-fixture-'));
  let browser;
  try {
    await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
    const origin='http://127.0.0.1:'+server.address().port;
    browser=await puppeteer.launch({headless:true,pipe:true,userDataDir:dir,executablePath:process.env.RIFTLET_CHROME_BIN||
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
    const page=await browser.newPage();
    const unexpected=[];
    page.on('request',request=>{const u=new URL(request.url());if(!['data:','blob:'].includes(u.protocol) && u.origin!==origin) unexpected.push(u.protocol);});
    await page.goto(origin+'/draft');
    await page.waitForFunction(()=>window.fixtureResult || window.fixtureFailure,{timeout:10000});
    const result=await page.evaluate(()=>window.fixtureFailure || window.fixtureResult);
    if(typeof result==='string') throw Error(result);
    assert.equal(result.nativeSetters,5);assert.equal(result.returnedChanges,4);assert.equal(result.sends,0);assert.equal(result.foreignEvents,0);
    assert.equal(result.draftSelectionPreserved,true);assert.deepEqual(unexpected,[]);
    const sourceSHA256={};
    for(const file of ['run-fixture.cjs',...Array.from(files.values(),entry=>entry[1])]) {
      const bytes=fs.readFileSync(path.join(__dirname,file));
      sourceSHA256[file]=crypto.createHash('sha256').update(bytes).digest('hex');
    }
    console.log(JSON.stringify({recordedAt:new Date().toISOString(),browser:await browser.version(),...result,
      unexpectedNetworkRequests:unexpected.length,sourceSHA256},null,2));
  } finally {
    try {if(browser)await browser.close();}
    finally {server.closeAllConnections();await new Promise(done=>server.close(done));fs.rmSync(dir,{recursive:true,force:true});}
  }
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
