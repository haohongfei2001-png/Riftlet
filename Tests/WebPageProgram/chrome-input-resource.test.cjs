'use strict';
// Hermetic native-Chrome/FileList/Blob/Request regression with a SYNTHETIC app.
// No ChatGPT page, signed-in profile, external request, CDP, Apple Events or real
// user screenshot is opened. Test status goes only to the temporary loopback
// harness, separately from the synthetic application's zero network uploads.
// This is not current-platform append acceptance.
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const http=require('node:http');
const {spawn}=require('node:child_process');
const {bounded,cleanupOwnedChrome,closeLoopbackServer}=require('./native-chrome-cleanup.cjs');
// Keep cleanup fault regressions in the existing required CI entry point.
require('./native-chrome-cleanup.test.cjs');
const binary=[process.env.RIFTLET_CHROME_BIN,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome','/usr/bin/chromium','/usr/bin/chromium-browser'].find(p=>p&&fs.existsSync(p));
const required=process.env.RIFTLET_REQUIRE_CHROME==='1';
const source=fs.readFileSync(path.join(__dirname,'../../Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js'),'utf8');
const baselineSource=fs.readFileSync(path.join(__dirname,'fixtures/chatgpt-web-main-6c677f55.js'),'utf8');
function browserFixture(options) {
  return String.raw`<!doctype html><meta charset="utf-8"><title>Riftlet local synthetic input-resource fixture</title>
<header><div role="group" aria-label="撰写器模式"><button type="button" aria-pressed="true">聊天</button><button type="button" aria-pressed="false">工作</button></div></header>
<form><div contenteditable="true" role="textbox" style="width:500px;height:80px">Existing 中文 draft 👋 and selection</div><input type="file" aria-label="附加文件"></form><pre id="result">RUNNING</pre>
<script>
(async()=>{
 const options=__FIXTURE_OPTIONS__;
 const result=document.getElementById('result'),report={scope:'real Chrome primitives; synthetic local application; NOT live ChatGPT',passed:false};
 const harnessFetch=globalThis.fetch.bind(globalThis);
 const stage=async phase=>{report.phase=phase;await harnessFetch('/progress',{method:'POST',body:JSON.stringify({phase})});};
 const check=(ok,label)=>{if(!ok)throw Error(label);};
 const wait=async fn=>{for(let i=0;i<300;i++){if(fn())return;await new Promise(r=>setTimeout(r,10));}throw Error('bounded fixture wait expired');};
 const hash=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),n=>n.toString(16).padStart(2,'0')).join('');
 try {
  check(location.protocol==='http:'&&location.hostname==='127.0.0.1','fixture must stay on loopback');
  await stage('initializing');
  const form=document.querySelector('form'),editor=form.querySelector('[contenteditable]'),input=form.querySelector('input');
  // A controlled application model owns immutable per-attachment Files and
  // request bodies. Retained mode models a persisted thread, without opening
  // ChatGPT or claiming that this model is its current application handler.
  let route='https://chatgpt.com/';
  if(options.retained||options.businessHome){
    const home=!!options.businessHome,placement=home?'home':'thread';
    const id=(home?'local-chatgpt:':'')+'12345678-1234-4234-8234-123456789abc';
    if(!home)route='https://chatgpt.com/c/'+id;
    form.setAttribute('data-chatgpt-composer','');form.setAttribute('data-composer-placement',placement);form.setAttribute('data-thread-find-composer','true');
    editor.setAttribute('aria-label','询问 ChatGPT');
    const leaf={stateNode:form,memoizedProps:{},return:null};
    const mode={memoizedProps:{conversationId:id,isHome:home,isWork:false,readOnly:false},child:leaf};leaf.return=mode;
    const draft={memoizedProps:{conversationId:id,draftKey:id,isWorkConversation:false,isTemporaryChat:false,readOnly:false,surfacePlacement:{kind:placement}},child:mode};mode.return=draft;
    const root={tag:3,child:draft,return:null,stateNode:{}};draft.return=root;root.stateNode.current=root;
    form.__reactFiber$fixture=leaf;
  }
  // Candidate route forms are injected into a controlled, identity-proven
  // composer. They do not assert that today's live Project DOM was inspected.
  if(options.routeFlavor==='home-query')route='https://chatgpt.com/?model=synthetic-model';
  if(options.routeFlavor==='project-thread')route='https://chatgpt.com/g/g-p-1234567890abcdef-fixture/c/12345678-1234-4234-8234-123456789abc';
  if(options.routeFlavor==='project-home')route='https://chatgpt.com/g/g-p-1234567890abcdef-fixture/project';
  // The route and optional explicitly modeled focus read are injected.
  // File, FileList, DataTransfer, Event, native
  // input descriptors, Selection, DOM, Blob, FormData, Request and WebCrypto
  // are the actual Chrome implementations. No app source is modified.
  const installProgram=source=>new Function('location','return ('+source+')')({href:route});
  let program=installProgram(options.hotUpgrade?__BASELINE_SOURCE__:__CURRENT_SOURCE__);
  const native={applicationID:'com.google.Chrome',sessionID:'synthetic-local-profile',windowID:'1',tabID:'1'};
  const call=command=>program(command,native);
  const prepare=async command=>{
    for(let poll=0;poll<16;poll++){
      const reply=call(command);
      if(reply.pending!==true)return reply;
      check(reply.version===1&&reply.invocationID===command.invocationID
        &&JSON.stringify(reply.identity)===JSON.stringify(command.identity)
        &&reply.resourceID===undefined,'read-only pending qualification is bound and grants no token');
      await new Promise(resolve=>setTimeout(resolve,20));
    }
    throw Error('bounded native selection qualification expired');
  };
  editor.focus();const selection=getSelection(),range=document.createRange();range.setStart(editor.firstChild,2);range.setEnd(editor.firstChild,7);selection.removeAllRanges();selection.addRange(range);
  const text=editor.textContent,anchor=selection.anchorNode,anchorOffset=selection.anchorOffset,focus=selection.focusNode,focusOffset=selection.focusOffset;
  const sources=[];
  for(let index=0;index<options.count;index++){
    const canvas=document.createElement('canvas');canvas.width=2;canvas.height=1;
    const ctx=canvas.getContext('2d');ctx.fillStyle='rgb('+(12+index*40)+','+(25+index*15)+','+(35+index*10)+')';ctx.fillRect(0,0,2,1);
    const pixelURL=canvas.toDataURL('image/png'),base64=pixelURL.split(',')[1],bytes=Uint8Array.from(atob(base64),c=>c.charCodeAt(0));
    const png=new Blob([bytes],{type:'image/png'});
    sources.push({png,bytes,sha:await hash(bytes),base64,pixelURL});
  }
  check(new Set(sources.map(value=>value.sha)).size===options.count,'each operation has distinct image bytes');
  const tasks=[],applicationAttachments=new Map();let changes=0,sends=0;
  form.addEventListener('submit',event=>{sends++;event.preventDefault();});
  const cachedTransport=body=>new Request('https://fixture.invalid/never-requested',{method:'POST',body});
  const prePressTarget=call({action:'captureTarget'});
  if(options.modeledFocusLoss){
    // Model the native nonactivating click's focus ordering without pretending
    // a loopback headless fixture is a physical macOS/Chrome focus experiment.
    Object.defineProperty(document,'hasFocus',{value:()=>false,configurable:true});
    globalThis.dispatchEvent(new Event('blur'));
    let rejected=false;try{call({action:'captureTarget'});}catch(error){rejected=error.message==='PAGE_UNFOCUSED';}
    check(rejected,'unfocused discovery still refuses and must not poison the prior capture');
  }
  const captureForClick=()=>options.modeledFocusLoss?prePressTarget:call({action:'captureTarget'});
  const pinForClick=target=>{
    const clickBindingID=crypto.randomUUID();
    return call({action:'pinTarget',target,clickBindingID,...(options.modeledFocusLoss?
      {nativePressProof:{kind:'observed-target-before-press',clickBindingID}}:{})});
  };
  input.addEventListener('change',event=>{
    changes++;const files=event.target.files,file=files[0],index=tasks.length;check(file instanceof File,'native File required');
    let body=file,kind='File';
    if(index===1){kind='FormData';body=new FormData();body.append('file',file);}
    if(index===2){kind='Blob';body=new Blob([file],{type:file.type});}
    if(index===3)kind='cached Request constructor';
    // Constructing a Request extracts a native body, but sends nothing.
    const request=cachedTransport(body);
    const card=document.createElement('div');card.setAttribute('role','button');card.setAttribute('aria-label',file.name);
    const image=new Image();image.alt=file.name;image.src=URL.createObjectURL(file);card.append(image);
    const progress=document.createElement('span');progress.setAttribute('role','progressbar');progress.setAttribute('aria-label','正在上传 '+file.name);progress.setAttribute('aria-valuenow','10');card.append(progress);form.append(card);
    const task={files,file,body,request,kind,card,image,progress,sha:sources[index].sha,pixelURL:sources[index].pixelURL};
    check(!applicationAttachments.has(file.name),'one application task per file');
    applicationAttachments.set(file.name,task);tasks.push(task);
    if(!options.retained)input.value=''; // Application-owned reset only in the empty-picker case.
  });
  const operations=[];
  for(let index=0;index<options.count;index++){
    await stage('input-'+index);
    const {bytes,sha,base64}=sources[index];
    if(options.hotUpgrade&&index===1)program=installProgram(__CURRENT_SOURCE__);
    if(options.renewDocument&&index)globalThis.dispatchEvent(new Event('blur'));
    const target=captureForClick(),pin=pinForClick(target);
    if(options.retained){
      check(!!target.logicalDraftIdentity,'persisted logical draft required');
      if(index)check(JSON.stringify(target.logicalDraftIdentity)===JSON.stringify(operations[0].identity.target.logicalDraftIdentity),'same logical draft');
      if(options.renewDocument&&index)check(target.documentID!==operations[index-1].identity.target.documentID,'document identity actually renewed');
    }
    const identity={operationID:crypto.randomUUID(),assetID:crypto.randomUUID(),attempt:1,assetSHA256:sha,target:pin};
    const invocationID=index===0?undefined:crypto.randomUUID(),name='riftlet-'+identity.operationID+'.png';
    const command=action=>({action,identity,target:pin,...(invocationID?{invocationID}:{})});
    let resource;
    if(index){resource=await prepare(command('prepareInputResource'));check(resource.kind===(options.retained?'settledOwnedNativeFileInput':'emptyNativeFileInput'),'fresh native resource kind');}
    const begin=call({...command('begin'),uploadName:name,mediaType:'image/png',byteCount:bytes.length,...(resource?{inputResourceID:resource.resourceID}:{})});
    check(begin.rejectedBeforeBegin!==true,'begin accepted');
    call({...command('chunk'),chunkIndex:0,chunkBase64:base64});call({...command('commit'),chunkIndex:1});
    const record=()=>globalThis.__riftletWebAcceptance20261027v13.tail.operations.get(identity.operationID);
    await wait(()=>record().commitWorkSettled&&record().fileHashVerified);check(changes===index+1,'one change per operation');
    const task=tasks[index];await task.image.decode();call(command('observe'));task.progress.setAttribute('aria-valuenow','40');
    if(options.retained)check(input.files.length===1&&input.files[0]===task.file&&input.value!=='','native picker retains the exact most recent File');
    else check(input.files.length===0&&input.value==='','actual app emptied native picker');
    await wait(()=>call(command('observe')).observation.state==='uploadStarted');let observation=call(command('observe')).observation;
    check(observation.state==='uploadStarted','own START '+index);check(!observation.requestEvidence,'no invented request observation');
    await stage('started-'+index);
    operations.push({identity,command,record:record(),start:record().uploadStart});
    if(index===0&&(!options.retained||options.hotUpgradeAfterUnknown)){
      // A real scaled preview in this synthetic app cannot prove the original
      // pixels. Exercise the normal observer, without changing its records.
      task.progress.setAttribute('aria-valuenow','100');call(command('observe'));task.progress.remove();
      await new Promise(r=>setTimeout(r,0));
      const small=document.createElement('canvas');small.width=1;small.height=1;small.getContext('2d').fillRect(0,0,1,1);
      task.image.src=small.toDataURL('image/png');await task.image.decode();
      await wait(()=>record().completionUnavailable);check(call(command('observe')).observation.state==='unknown','scaled original stays UNKNOWN');
      if(options.hotUpgradeAfterUnknown)check(record().file===null,'baseline UNKNOWN has released its original File reference');
      await stage('legacy-unknown');
    }
    for(const prior of tasks)check(form.contains(prior.card),'prior card retained');
    for(const prior of tasks)check(applicationAttachments.get(prior.file.name)===prior,'application independently retains every accepted task');
    if(options.retained)for(const op of operations)check(!op.record.proof&&!!op.record.uploadStart,'later input occurs after START before COMPLETE');
    check(editor.textContent===text&&selection.anchorNode===anchor&&selection.anchorOffset===anchorOffset&&selection.focusNode===focus&&selection.focusOffset===focusOffset,'text/selection retained');
  }
  // The native body extractions and original immutable Files remain independent
  // after four later native FileList submissions and application-owned resets.
  await stage('verifying-independent-bodies');
  for(const task of tasks){
    check(task.files instanceof FileList,'native FileList object retained by application');
    if(options.retained)check(task.files.length===1&&task.files[0]===task.file,'subsequent native setter does not mutate prior FileList');
    else check(task.files.length===0,'application value reset clears its prior native FileList');
    check(await hash(await task.file.arrayBuffer())===task.sha,'original File keeps its own distinct bytes');
    const extracted=task.kind==='FormData'?(await task.request.formData()).get('file'):await task.request.blob();
    check(await hash(await extracted.arrayBuffer())===task.sha,'native Request body keeps its own distinct bytes '+task.kind);
  }
  // Only after every retained-picker append do we move A to UNKNOWN. This
  // specifically proves that the next input never needed A's COMPLETE/UNKNOWN.
  if(options.retained&&!options.hotUpgradeAfterUnknown){
    const task=tasks[0],op=operations[0];
    task.progress.setAttribute('aria-valuenow','100');call(op.command('observe'));task.progress.remove();
    await new Promise(r=>setTimeout(r,0));
    const small=document.createElement('canvas');small.width=1;small.height=1;small.getContext('2d').fillRect(0,0,1,1);
    task.image.src=small.toDataURL('image/png');await task.image.decode();
    await wait(()=>op.record.completionUnavailable);check(call(op.command('observe')).observation.state==='unknown','A becomes UNKNOWN only after later submissions');
  }
  let independentCompletions=0;
  for(let index=1;index<tasks.length;index++){
    await stage('completing-'+index);
    const task=tasks[index],op=operations[index];
    task.progress.setAttribute('aria-valuenow','100');call(op.command('observe'));task.progress.remove();
    await new Promise(r=>setTimeout(r,0));task.image.src=task.pixelURL;await task.image.decode();
    await wait(()=>op.record.proof&&!op.record.proofPending);
    check(call(op.command('observe')).observation.state==='attached','independent exact completion '+index);independentCompletions++;
  }
  const a=operations[0];check(a.record.inputCount===1&&a.record.uploadStart===a.start&&a.record.invocationID===undefined,'legacy operation untouched');
  check(call(a.command('observe')).observation.state==='unknown','legacy final remains UNKNOWN');
  check(changes===options.count,'one input per click; A never replayed');
  const nextTarget=captureForClick(),nextPin=pinForClick(nextTarget);
  const next={operationID:crypto.randomUUID(),assetID:crypto.randomUUID(),attempt:1,assetSHA256:sources[0].sha,target:nextPin};
  const occupied=new DataTransfer();occupied.items.add(new File([sources[0].png],'user-selected.png',{type:'image/png'}));input.files=occupied.files;
  let refused=false;try{call({action:'prepareInputResource',identity:next,target:nextPin,invocationID:crypto.randomUUID()});}catch(e){refused=/^INPUT_RESOURCE_(UNAVAILABLE|NATIVE_FILES_RETAINED)$/.test(e.message);}
  check(refused&&changes===options.count&&input.files[0].name==='user-selected.png','unowned nonempty input refusal preserves selected file');
  check(sends===0,'no automatic send');
  Object.assign(report,{passed:true,phase:'complete',routeFlavor:options.routeFlavor||'ordinary',modeledFocusLoss:!!options.modeledFocusLoss,physicalFocusAcceptance:false,retainedNativeSelection:options.retained,nativeFileListBehavior:options.retained?'prior-list-unchanged':'app-reset-cleared-prior-list',renewedDocumentIdentity:options.renewDocument,hotUpgradedFromMain:!!options.hotUpgrade,baselineUnknownRecovered:!!options.hotUpgradeAfterUnknown,nativeChanges:changes,originalFileListsVerified:tasks.length,originalFileBodiesVerified:tasks.length,nativeRequestBodiesVerified:tasks.length,applicationIndependentTasksVerified:applicationAttachments.size,independentCompletions,legacyUnknownUnchanged:true,textSelectionCardsPreserved:true,occupiedPickerRefused:true,automaticSends:sends,networkRequests:0,harnessTransport:'loopback-only'});
 } catch(error){report.error=String(error?.stack||error);}
 result.textContent=JSON.stringify(report);
 await harnessFetch('/result',{method:'POST',body:JSON.stringify(report)});
})();
</script>`.replace('__FIXTURE_OPTIONS__',()=>JSON.stringify(options))
    .replaceAll('__CURRENT_SOURCE__',()=>JSON.stringify(source).replace(/<\/script/gi,'<\\/script'))
    .replace('__BASELINE_SOURCE__',()=>JSON.stringify(baselineSource).replace(/<\/script/gi,'<\\/script'));
}

for(const options of [{retained:false,count:5,renewDocument:false},
  ...[2,3,5].map(count=>({retained:true,count,renewDocument:false})),
  {retained:true,count:5,renewDocument:true},
  {retained:true,count:3,renewDocument:true,hotUpgrade:true},
  {retained:true,count:3,renewDocument:true,hotUpgrade:true,hotUpgradeAfterUnknown:true},
  {retained:false,count:2,renewDocument:false,routeFlavor:'home-query'},
  {retained:true,count:2,renewDocument:false,routeFlavor:'project-thread'},
  {retained:false,count:2,renewDocument:false,routeFlavor:'project-home',businessHome:true},
  {retained:true,count:2,renewDocument:false,modeledFocusLoss:true},
  {retained:true,count:2,renewDocument:false,routeFlavor:'project-thread',modeledFocusLoss:true}])test('native Chrome '+JSON.stringify(options)+' preserves independent application File/request bodies',{
  // The 30-second report limit is unchanged. Allow the separately bounded
  // listen, group/root cleanup, server close and profile-removal retries to
  // finish (about 50 seconds combined) before the outer test aborts them.
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
    assert.equal(report.originalFileListsVerified,options.count);assert.equal(report.hotUpgradedFromMain,!!options.hotUpgrade);
    assert.equal(report.baselineUnknownRecovered,!!options.hotUpgradeAfterUnknown);
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
