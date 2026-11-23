'use strict';
const fs = require('node:fs'), path = require('node:path'), http = require('node:http');
const {randomBytes} = require('node:crypto'), {spawn} = require('node:child_process');
const {bounded, cleanupOwnedChrome, closeLoopbackServer} = require('../../../WebPageProgram/native-chrome-cleanup.cjs');
const page = require('./controlled-page.cjs');
async function main() {
  const [root] = process.argv.slice(2);
  if (!root || !fs.existsSync(path.join(root,'controlled-copy-only'))) throw Error('Private controlled copy required');
  const c = JSON.parse(fs.readFileSync(path.join(root, 'browser-request.json')));
  if (path.basename(c.filename) !== c.filename) throw Error('Unexpected PNG path');
  c.png = fs.readFileSync(path.join(root, c.filename)).toString('base64');
  const source = fs.readFileSync(path.join(__dirname,'../../../../Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js'),'utf8');
  const nonce = '/' + randomBytes(24).toString('hex');
  const html = '<meta charset="utf-8"><form><div data-composer-layout><div id="prompt-textarea" contenteditable="true" role="textbox">Local draft</div><div class="ComposerLayoutAttachments-test"><div class="flex"><div role="button" data-file-name="existing.png">existing.png</div></div></div></div><input type=file accept="image/*" hidden><button type=submit>Send</button></form><script>('+page.toString()+')('+JSON.stringify(c)+','+JSON.stringify(source).replace(/<\/script/gi,'<\\/script')+').then(r=>fetch(location.pathname+"/result",{method:"POST",body:JSON.stringify(r)}),e=>fetch(location.pathname+"/result",{method:"POST",body:JSON.stringify({error:String(e)})}));</script>';
  const connections = new Set();
  let resolve, reject, child, exit;
  const result = new Promise((good,bad) => { resolve=good; reject=bad; }); result.catch(()=>{});
  const server = http.createServer((req,res) => {
    if (req.url===nonce && req.method==='GET') {
      res.writeHead(200,{'content-type':'text/html;charset=utf-8','content-security-policy':"default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; connect-src 'self'; img-src blob: data:; style-src 'unsafe-inline'; form-action 'none'"}); res.end(html); return;
    }
    if (req.url!==nonce+'/result' || req.method!=='POST' || req.headers.origin!=='http://127.0.0.1:'+server.address().port) { res.writeHead(404);res.end();return; }
    let body='';req.on('data',d=>{body+=d;if(body.length>8192){req.destroy();reject(Error('Oversize local report'));}});
    req.on('end',()=>{try{const v=JSON.parse(body);res.end('ok');v.error?reject(Error(v.error)):resolve(v);}catch(e){reject(e);}});
  });
  server.on('connection',s=>{connections.add(s);s.once('close',()=>connections.delete(s));});
  const profile = path.join(root,'isolated-headless-profile');
  fs.mkdirSync(profile,{mode:0o700});
  try {
    await bounded(new Promise((done,err)=>{server.once('error',err);server.listen(0,'127.0.0.1',done);}),3000,'Loopback startup');
    const chrome='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
    child=spawn(chrome,['--headless=new','--no-sandbox','--disable-gpu','--disable-background-networking','--disable-sync',
      '--disable-component-update','--no-first-run','--no-default-browser-check','--host-resolver-rules=MAP * ~NOTFOUND,EXCLUDE 127.0.0.1',
      '--user-data-dir='+profile,'http://127.0.0.1:'+server.address().port+nonce],{detached:true,stdio:['ignore','ignore','pipe']});
    child.stderr.resume();child.once('error',reject);
    exit=new Promise(done=>child.once('exit',(code,signal)=>{done();reject(Error('Headless Chrome exited '+[code,signal]));}));
    const evidence=await bounded(result,15000,'Local recovery timed out');
    fs.writeFileSync(path.join(root,'browser-receipt.json'),JSON.stringify(evidence,null,2),{flag:'wx',mode:0o600});
  } finally {
    try { if(child) await cleanupOwnedChrome(child,exit); }
    finally {await closeLoopbackServer(server,connections);}
  }
  // Remove only the fresh disposable profile after its process group is certified empty.
  await fs.promises.rm(profile,{recursive:true,maxRetries:8,retryDelay:150});
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
