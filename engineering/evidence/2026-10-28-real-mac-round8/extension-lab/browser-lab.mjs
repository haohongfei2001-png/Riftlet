// ROOT runtime owner only. Launches one isolated, headless CfT; never installed Chrome.
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import {spawn} from 'node:child_process';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {publishedDocuments, hasNewDocumentPublication} from './publication-check.mjs';
const here = path.dirname(fileURLToPath(import.meta.url));
const options = Object.fromEntries(process.argv.slice(2).reduce((a,x,i,all) => i%2 ? a : [...a,[x,all[i+1]]],[]));
const browserPath = options['--browser'], pythonPath = options['--python'];
if (!browserPath?.endsWith('/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing')
    || !path.isAbsolute(pythonPath || '') || typeof WebSocket !== 'function') throw new Error('Explicit CfT, absolute Python and Node WebSocket required');
await fs.access(browserPath); await fs.access(pythonPath);
const lab = await fs.mkdtemp(path.join(os.tmpdir(), 'riftlet-extension-lab-'));
const profile = path.join(lab, 'user-data'), extension = path.join(lab, 'extension');
await fs.mkdir(profile); await fs.cp(path.join(here, 'extension'), extension, {recursive:true});
const publicKey = generateKeyPairSync('rsa', {modulusLength:1024}).publicKey.export({type:'spki',format:'der'});
const id = [...createHash('sha256').update(publicKey).digest().subarray(0,16)]
  .map(b => String.fromCharCode(97+(b>>4),97+(b&15))).join('');
const manifest = JSON.parse(await fs.readFile(path.join(extension,'manifest.json'),'utf8'));
manifest.key = publicKey.toString('base64');
await fs.writeFile(path.join(extension,'manifest.json'),JSON.stringify(manifest));
const quote = s => "'" + s.replaceAll("'", "'\\''") + "'";
const launcher = path.join(lab,'native-host');
await fs.writeFile(launcher, '#!/bin/sh\nexport RIFTLET_LAB_ORIGIN='+quote('chrome-extension://'+id+'/')+'\nexec '+quote(pythonPath)+' '+quote(path.join(here,'native_host.py'))+' "$@"\n',{mode:0o700});
await fs.mkdir(path.join(profile,'NativeMessagingHosts'));
await fs.writeFile(path.join(profile,'NativeMessagingHosts','org.riftlet.synthetic_cold_lab_r8.json'),JSON.stringify({
  name:'org.riftlet.synthetic_cold_lab_r8',description:'Synthetic metadata only',path:launcher,type:'stdio',
  allowed_origins:['chrome-extension://'+id+'/']
}));
const server = http.createServer((req,res) => {
  if (!/^\/riftlet-synthetic-cold-lab\/(one|two)$/.test(req.url || '')) { res.writeHead(404); res.end(); return; }
  res.writeHead(200,{'Content-Type':'text/html','Cache-Control':'no-store','Content-Security-Policy':"default-src 'none'"});
  res.end('<!doctype html><meta charset="utf-8"><title>Synthetic cold channel fixture</title><p>No login, composer, file input or network upload exists.</p>');
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const localPort = server.address().port;
let browser, browserCDP, workerCDP, inspectSnapshot, inspectPage;
const protocolDiagnostics = [];
const sleep = ms => new Promise(r=>setTimeout(r,ms));
async function until(fn,ms=12000) {
  const deadline=Date.now()+ms;
  while(Date.now()<deadline) { const value=await fn(); if(value) return value; await sleep(100); }
  throw new Error('bounded-wait-expired');
}
async function cdp(url, surface = "browser") {
  const socket=new WebSocket(url), pending=new Map(); let sequence=0;
  await new Promise((r,j)=>{socket.addEventListener('open',r,{once:true});socket.addEventListener('error',j,{once:true});});
  socket.addEventListener('message',e=>{const m=JSON.parse(e.data);if(!m.id) {
    if (m.method === 'Runtime.exceptionThrown' && protocolDiagnostics.length < 20) {
      const d=m.params?.exceptionDetails;
      // Intentionally omit source URL, message body, stack and evaluated values.
      protocolDiagnostics.push({surface,event:'exceptionThrown',line:d?.lineNumber ?? null,
        column:d?.columnNumber ?? null,uncaught:d?.text === 'Uncaught',
        exceptionClass:['Error','TypeError','ReferenceError','SyntaxError','DOMException'].includes(d?.exception?.className) ? d.exception.className : 'other',
        extensionSource:typeof d?.url === 'string' && d.url.startsWith('chrome-extension://')});
    }
    return;
  }const p=pending.get(m.id);if(!p)return;
    clearTimeout(p.timer);pending.delete(m.id);m.error?p.reject(new Error(m.error.message)):p.resolve(m.result);});
  return {close:()=>socket.close(),send:(method,params={})=>new Promise((resolve,reject)=>{
    const id=++sequence,timer=setTimeout(()=>{pending.delete(id);reject(new Error('cdp-timeout'));},5000);
    pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params}));})};
}
const report={scope:'isolated synthetic headless extension to native host',inputAuthority:false,uploadCount:0,
  provesNativeForegroundClick:false,provesBusinessDraft:false,privateTemporaryDirectory:lab};
try {
  browser=spawn(browserPath,['--headless=new','--no-first-run','--no-default-browser-check','--disable-sync',
    '--disable-background-networking','--disable-component-update','--disable-default-apps',
    '--remote-debugging-port=0','--user-data-dir='+profile,'--disable-extensions-except='+extension,
    '--load-extension='+extension,'--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','about:blank'],
    {stdio:['ignore','ignore','pipe']});
  let stderr='';browser.stderr.on('data',b=>{if(stderr.length<4000)stderr+=b.toString();});
  const data=await until(async()=>{try{return await fs.readFile(path.join(profile,'DevToolsActivePort'),'utf8');}catch{return null;}});
  const [port,endpoint]=data.trim().split('\n');
  browserCDP=await cdp('ws://127.0.0.1:'+port+endpoint);
  const list=async()=>JSON.parse(await (await fetch('http://127.0.0.1:'+port+'/json/list')).text());
  const worker=await until(async()=>(await list()).find(t=>t.type==='service_worker'&&t.url==='chrome-extension://'+id+'/worker.js'));
  workerCDP=await cdp(worker.webSocketDebuggerUrl, "worker");
  await workerCDP.send("Runtime.enable");
  const snapshot=async()=>{
    const result=await workerCDP.send('Runtime.evaluate',{expression:'typeof globalThis.labSnapshot === "function" ? JSON.stringify(globalThis.labSnapshot()) : null',returnByValue:true});
    if(result.exceptionDetails)throw new Error('worker-inspection-failed');
    return result.result.value == null ? null : JSON.parse(result.result.value);
  };
  inspectSnapshot = snapshot;
  report.beforeDocument=await until(snapshot);
  const target=await browserCDP.send('Target.createTarget',{url:'about:blank'});
  const page=await until(async()=>(await list()).find(t=>t.id===target.targetId));
  const pageCDP=await cdp(page.webSocketDebuggerUrl, 'syntheticPage');
  inspectPage=async()=>{
    const result=await pageCDP.send('Runtime.evaluate',{expression:
      '({readyState:document.readyState,syntheticScope:location.hostname === "127.0.0.1" && location.pathname.startsWith("/riftlet-synthetic-cold-lab/"),hasFixtureTitle:document.title === "Synthetic cold channel fixture",isSecondFixture:location.pathname === "/riftlet-synthetic-cold-lab/two",secureContext:isSecureContext})',returnByValue:true});
    return result.result?.value ?? null;
  };
  try {
    await pageCDP.send('Runtime.enable');
    await pageCDP.send('Page.enable');
    await pageCDP.send('Page.navigate',{url:'http://127.0.0.1:'+localPort+'/riftlet-synthetic-cold-lab/one'});
    report.firstPublication=await until(async()=>{const s=await snapshot();return s?.events.some(e=>e.event==='publishAck')?s:null;});
    const initialDocuments=publishedDocuments(report.firstPublication);
    await pageCDP.send('Page.navigate',{url:'http://127.0.0.1:'+localPort+'/riftlet-synthetic-cold-lab/two'});
    report.secondDocument=await until(async()=>{const s=await snapshot();return hasNewDocumentPublication(s,initialDocuments)?s:null;});
  } finally {
    try { report.pageState=await inspectPage(); } catch {}
    pageCDP.close();
  }
  if (!report.pageState?.syntheticScope || !report.pageState?.isSecondFixture) throw new Error('second-fixture-not-verified');
  report.result='browser-native-publication-observed';
} catch(error) {
  report.result='blocked';report.reason=String(error.message).slice(0,200);
  try { if (inspectSnapshot) report.lastSnapshot=await inspectSnapshot(); } catch {}
} finally {
  workerCDP?.close();browserCDP?.close();
  if(browser && browser.exitCode===null) { browser.kill('SIGTERM'); await Promise.race([new Promise(r=>browser.once('exit',r)),sleep(3000)]); }
  if(browser && browser.exitCode===null) browser.kill('SIGKILL'); // Only this owned child PID.
  await new Promise(resolve=>server.close(resolve));
}
report.protocolDiagnostics=protocolDiagnostics;
const output=JSON.stringify(report,null,2)+'\n';
if(options['--out']) await fs.writeFile(options['--out'],output,{mode:0o600});
process.stdout.write(output);
process.exitCode=report.result==='blocked'?2:0;
