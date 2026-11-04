'use strict';
// Real native Chrome File/FileList/DataTransfer/Selection; controlled app only.
// Isolated profile, loopback traffic, no real ChatGPT, CDP or Apple Events.
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const http=require('node:http');
const {spawn}=require('node:child_process');
const {bounded,cleanupOwnedChrome,closeLoopbackServer}=require('./native-chrome-cleanup.cjs');
require('./native-chrome-cleanup.test.cjs');
const binary=[process.env.RIFTLET_CHROME_BIN,
 '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
 '/usr/bin/google-chrome','/usr/bin/chromium','/usr/bin/chromium-browser'].find(p=>p&&fs.existsSync(p));
const required=process.env.RIFTLET_REQUIRE_CHROME==='1';
const source=fs.readFileSync(path.join(__dirname,'../../Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js'),'utf8');
function browserFixture(options){
 return String.raw`<!doctype html><meta charset="utf-8"><title>Riftlet independent native input regression</title>
<form><div id="prompt-textarea" contenteditable="true" role="textbox" style="width:500px;height:80px">Existing 中文 draft 👋 and selection</div><input type="file" accept="image/*" style="display:none"><div role="button" data-file-name="existing.png"><img alt="existing.png"></div><button type="submit">Send</button></form><pre id="result">RUNNING</pre>
<script>
(async()=>{
 const options=__OPTIONS__,report={scope:'real Chrome primitives; controlled local application; NOT live ChatGPT',passed:false};
 const harnessFetch=globalThis.fetch.bind(globalThis);
 const stage=async phase=>{report.phase=phase;await harnessFetch('/progress',{method:'POST',body:JSON.stringify({phase})});};
 const check=(ok,label)=>{if(!ok)throw Error(label);};
 const wait=async fn=>{for(let i=0;i<300;i++){if(fn())return;await new Promise(r=>setTimeout(r,10));}throw Error('bounded observation wait expired');};
 const hash=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),n=>n.toString(16).padStart(2,'0')).join('');
 try{
  check(location.protocol==='http:'&&location.hostname==='127.0.0.1','fixture must stay on loopback');
  await stage('initializing');
  const form=document.querySelector('form'),editor=document.querySelector('#prompt-textarea'),input=form.querySelector('input');
  const priorCard=form.querySelector('[data-file-name]'),priorImage=priorCard.querySelector('img');
  const canvas=document.createElement('canvas');canvas.width=canvas.height=2;
  canvas.getContext('2d').fillRect(0,0,2,2);priorImage.src=canvas.toDataURL('image/png');
  let applicationNetworkRequests=0;
  globalThis.fetch=()=>{applicationNetworkRequests++;throw Error('application network requests forbidden in local fixture');};
  XMLHttpRequest.prototype.send=function(){applicationNetworkRequests++;throw Error('application XHR forbidden in local fixture');};
  const mockLocation={href:options.route};
  const program=new Function('location','return ('+__SOURCE__+')')(mockLocation);
  const native={applicationID:'com.google.Chrome',sessionID:'synthetic-local-profile',windowID:'1',tabID:'1'};
  const call=command=>program(command,native);
  editor.focus();const selection=getSelection(),range=document.createRange();range.setStart(editor.firstChild,2);range.setEnd(editor.firstChild,7);selection.removeAllRanges();selection.addRange(range);
  const text=editor.textContent,anchor=selection.anchorNode,focus=selection.focusNode,anchorOffset=selection.anchorOffset,focusOffset=selection.focusOffset;
  let changes=0,sends=0,reentrant=null,reentrantRefused=false,firstPendingCard=null;
  const tasks=[],ops=[];
  form.addEventListener('submit',event=>{event.preventDefault();sends++;});
  input.addEventListener('change',()=>{
   changes++;
   const list=input.files,file=list[0];
   check(list instanceof FileList&&list.length===1&&file instanceof File,'one actual native FileList item');
   if(reentrant){
    const next=reentrant;reentrant=null;
    const refusal=call({...next.command('commit'),chunkIndex:1}).observation;
    reentrantRefused=refusal.preInputRetirement?.reason==='inputExecutionBusy'&&refusal.preInputRetirement.inputCount===0;
    check(reentrantRefused&&input.files[0]===file,'reentrant input cannot overwrite current native control');
   }
   const card=document.createElement('div');card.setAttribute('role','button');card.setAttribute('data-file-name',file.name);card.title=file.name;
   const image=document.createElement('img');image.alt=file.name;image.src=URL.createObjectURL(file);card.append(image);
   const progress=document.createElement('div');progress.setAttribute('role','progressbar');progress.setAttribute('aria-valuenow','10');card.append(progress);
   const task={file,list,card,image,progress,state:'uploading'};tasks.push(task);
   // The first acceptance is deliberately delayed; its input return is dropped.
   // A second input is allowed while A has no observed START yet.
   if(changes===1)firstPendingCard=card;else{form.append(card);if(changes===2)setTimeout(()=>form.append(firstPendingCard),0);}
   if(!options.retained)input.value='';
  });
  async function operation(index){
   const color='rgb('+(20+index*30)+',40,70)';canvas.getContext('2d').fillStyle=color;canvas.getContext('2d').fillRect(0,0,2,2);
   const png=await new Promise(resolve=>canvas.toBlob(resolve,'image/png'));
   const bytes=new Uint8Array(await png.arrayBuffer()),sha=await hash(bytes);
   const target=call({action:'captureTarget'}),id=crypto.randomUUID();
   const identity={operationID:id,assetID:crypto.randomUUID(),attempt:1,assetSHA256:sha,target},invocationID=crypto.randomUUID();
   const op={identity,target,name:'riftlet-'+id+'.png',sha,command:action=>({action,identity,target,invocationID})};
   call({...op.command('begin'),uploadName:op.name,mediaType:'image/png',byteCount:bytes.length});
   call({...op.command('chunk'),chunkIndex:0,chunkBase64:btoa(String.fromCharCode(...bytes))});return op;
  }
  for(let index=0;index<options.count;index++)ops.push(await operation(index));
  const busyProbe=await operation(50);
  for(let index=0;index<ops.length;index++){
   await stage('input-'+(index+1));const op=ops[index];
   if(index===0)reentrant=busyProbe;
   if(index===2)tasks[0].state='unknown'; // Synthetic app lifecycle; deliberately irrelevant to native permission.
   call({...op.command('commit'),chunkIndex:1}); // Simulate a lost transport receipt by ignoring every reply.
   check(changes===index+1,'one change per screenshot');
   if(index===0)check(call(op.command('observe')).observation.state==='inputTriggered','first input completed before START');
   if(index>0)await wait(()=>call(op.command('observe')).observation.state==='uploadStarted');
   check(editor.textContent===text&&selection.anchorNode===anchor&&selection.focusNode===focus&&selection.anchorOffset===anchorOffset&&selection.focusOffset===focusOffset,'draft text and selection preserved');
   check(form.contains(priorCard),'existing attachment preserved');
  }
  let busyRetired=false;try{call({...busyProbe.command('commit'),chunkIndex:1});}catch(error){busyRetired=error.message==='COMMIT_REFUSED';}
  check(busyRetired,'retired concurrent operation cannot later submit');
  await stage('observing-starts');
  for(const op of ops){
   await wait(()=>call(op.command('observe')).observation.state==='uploadStarted');
   const observation=call(op.command('observe')).observation;
   check(observation.identity.operationID===op.identity.operationID&&observation.uploadStart.signal==='attachmentAccepted'&&observation.uploadStart.inputCount===1,'current operation gets independent accepted START');
   let rejected=false;try{call({...op.command('commit'),chunkIndex:1});}catch(error){rejected=error.message==='COMMIT_REFUSED';}
   check(rejected&&changes===options.count,'duplicate commit never submits again');
  }
  for(let index=0;index<tasks.length;index++){
   const task=tasks[index];check(form.contains(task.card),'all app attachments appended');
   check(await hash(await task.file.arrayBuffer())===ops[index].sha,'accepted File bytes remain unchanged after later inputs');
   check(task.list instanceof FileList,'application observed actual native FileList');
   if(options.retained)check(task.list.length===1&&task.list[0]===task.file,'retained prior FileList independent from replacement');
  }
  const stale=await operation(99);mockLocation.href='https://chatgpt.com/c/different-chat';
  const refused=call({...stale.command('commit'),chunkIndex:1}).observation;
  const wrongTargetRefused=refused.state==='invalidated'&&refused.preInputRetirement?.reason==='targetInvalidBeforeInput'&&refused.preInputRetirement.inputCount===0;
  check(wrongTargetRefused&&changes===options.count,'changed target refuses before native input');
  check(sends===0,'no automatic message send');
  Object.assign(report,{passed:true,phase:'complete',nativeChanges:changes,networkRequests:applicationNetworkRequests,automaticSends:sends,
   observedStarts:ops.length,originalFileListsVerified:tasks.length,applicationIndependentTasksVerified:tasks.length,
   retainedNativeSelection:options.retained,reentrantInputRefused:reentrantRefused,wrongTargetRefused,
   lostReplyRecoveredWithoutReplay:true,textSelectionCardsPreserved:true,
   firstSyntheticUploadState:tasks[0].state,harnessTransport:'loopback-only'});
 }catch(error){report.error=String(error?.stack||error);}
 document.querySelector('#result').textContent=JSON.stringify(report);
 await harnessFetch('/result',{method:'POST',body:JSON.stringify(report)});
})();
</script>`.replace('__OPTIONS__',()=>JSON.stringify(options)).replace('__SOURCE__',()=>JSON.stringify(source).replace(/<\/script/gi,'<\\/script'));
}
for(const options of [
 ...[2,3,5].map(count=>({count,retained:true,route:'https://chatgpt.com/c/ordinary-thread'})),
 {count:3,retained:false,route:'https://chatgpt.com/'},
 {count:3,retained:true,route:'https://chatgpt.com/g/g-p-project/c/project-thread'},
 {count:2,retained:true,route:'https://chatgpt.com/g/g-p-project/project'}
])test('native Chrome independent append '+JSON.stringify(options),{
 skip:!binary&&!required?'CHROME_NOT_RUN: no native Chrome binary in this executor':false,timeout:60000
},async t=>{

  assert.ok(binary,'CHROME_REQUIRED_BUT_UNAVAILABLE: native Chrome must run in this CI job');
  assert.ok(['darwin','linux'].includes(process.platform),'isolated Chrome process-group cleanup requires POSIX');
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-native-input-'));
  let child,exit,stderr='',lastPhase='browser-not-started',completed=false,resolveReport,rejectReport;
  const failures=[],connections=new Set();
  const html=browserFixture(options),finished=new Promise((resolve,reject)=>{resolveReport=resolve;rejectReport=reject;});
  const server=http.createServer((request,response)=>{
    if(request.method==='GET'&&request.url==='/'){
      response.writeHead(200,{'content-type':'text/html; charset=utf-8','cache-control':'no-store'});response.end(html);return;
    }
    if(request.method!=='POST'||!['/progress','/result'].includes(request.url)){response.writeHead(404);response.end();return;}
    let body='',oversize=false;
    request.setEncoding('utf8');request.on('data',part=>{body+=part;if(body.length>65536){oversize=true;request.destroy();rejectReport(Error('oversized local fixture report'));}});
    request.on('end',()=>{
      if(oversize)return;
      try{
        const value=JSON.parse(body);response.writeHead(200,{'content-type':'text/plain'});response.end('ok');
        if(request.url==='/progress'){lastPhase=String(value.phase);return;}
        completed=true;resolveReport(value);
      }catch(error){response.writeHead(400);response.end();rejectReport(error);}
    });
    request.on('error',error=>rejectReport(error));
  });
  server.on('connection',socket=>{connections.add(socket);socket.once('close',()=>connections.delete(socket));});
  try{
    await bounded(new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);}),
      2000,'loopback server listen deadline',t.signal);
    const address=server.address();assert.equal(address.address,'127.0.0.1');
    child=spawn(binary,['--headless=new','--no-sandbox','--disable-gpu','--disable-background-networking',
      '--disable-component-update','--disable-sync','--no-first-run','--no-default-browser-check',
      '--user-data-dir='+path.join(temp,'isolated-profile'),'http://127.0.0.1:'+address.port+'/'],
      {detached:true,stdio:['ignore','ignore','pipe']});
    child.stderr.setEncoding('utf8');child.stderr.on('data',part=>{stderr=(stderr+part).slice(-8000);});
    child.once('error',rejectReport);
    exit=new Promise(resolve=>child.once('exit',(code,signal)=>{
      resolve();if(!completed)rejectReport(Error('Chrome exited before result; code='+code+' signal='+signal+' phase='+lastPhase+' stderr='+stderr));
    }));
    const report=await bounded(finished,30000,()=> 'CHROME_FIXTURE_TIMEOUT phase='+lastPhase+' stderr='+stderr,t.signal);
    assert.equal(report.passed,true,JSON.stringify(report));assert.equal(report.nativeChanges,options.count);assert.equal(report.networkRequests,0);
    assert.equal(report.applicationIndependentTasksVerified,options.count);assert.equal(report.automaticSends,0);
    assert.equal(report.originalFileListsVerified,options.count);assert.equal(report.observedStarts,options.count);
    assert.equal(report.reentrantInputRefused,true);assert.equal(report.wrongTargetRefused,true);
    assert.equal(report.lostReplyRecoveredWithoutReplay,true);
    assert.equal(report.harnessTransport,'loopback-only');
    console.log(JSON.stringify(report));
  }catch(error){failures.push(error);}
  finally{
    // detached:true creates a new session/process group owned solely by this
    // fixture. Chrome helpers can outlive the main process and still write the
    // profile, so wait for that exact group even after the main exit event.
    // Never enumerate, match names, or signal any other Chrome process/group.
    let groupClean=false;
    try{await cleanupOwnedChrome(child,exit);groupClean=true;}catch(error){failures.push(error);}
    try{await closeLoopbackServer(server,connections);}catch(error){failures.push(error);}
    // OS/helper final file writes may settle just after group exit. Retry only
    // this newly created profile root; exhausting the bounded retries fails.
    if(groupClean){
      try{await fs.promises.rm(temp,{recursive:true,force:true,maxRetries:8,retryDelay:150});}
      catch(error){failures.push(error);}
    }
  }
  if(failures.length)throw new AggregateError(failures,'native Chrome fixture or cleanup failed: '+failures.map(error=>error.message).join('; '));
});
