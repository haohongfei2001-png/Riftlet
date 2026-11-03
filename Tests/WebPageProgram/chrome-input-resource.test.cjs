'use strict';
// Hermetic native-Chrome/FileList/Blob/Request regression with a SYNTHETIC app.
// No ChatGPT page, signed-in profile, network request, CDP, Apple Events or real
// user screenshot is opened. This is not current-platform append acceptance.
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {pathToFileURL}=require('node:url');
const {spawnSync}=require('node:child_process');
const binary=[process.env.RIFTLET_CHROME_BIN,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome','/usr/bin/chromium','/usr/bin/chromium-browser'].find(p=>p&&fs.existsSync(p));
const required=process.env.RIFTLET_REQUIRE_CHROME==='1';
const source=fs.readFileSync(path.join(__dirname,'../../Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js'),'utf8');
function browserFixture() {
  return String.raw`<!doctype html><meta charset="utf-8"><title>Riftlet local synthetic input-resource fixture</title>
<header><div role="group" aria-label="撰写器模式"><button type="button" aria-pressed="true">聊天</button><button type="button" aria-pressed="false">工作</button></div></header>
<form><div contenteditable="true" role="textbox" style="width:500px;height:80px">Existing 中文 draft 👋 and selection</div><input type="file" aria-label="附加文件"></form><pre id="result">RUNNING</pre>
<script>
(async()=>{
 const result=document.getElementById('result'),report={scope:'real Chrome primitives; synthetic local application; NOT live ChatGPT',passed:false};
 const check=(ok,label)=>{if(!ok)throw Error(label);};
 const wait=async fn=>{for(let i=0;i<300;i++){if(fn())return;await new Promise(r=>setTimeout(r,10));}throw Error('bounded fixture wait expired');};
 const hash=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),n=>n.toString(16).padStart(2,'0')).join('');
 try {
  check(location.protocol==='file:','fixture must stay local');
  const form=document.querySelector('form'),editor=form.querySelector('[contenteditable]'),input=form.querySelector('input');
  // Only the route is injected. File, FileList, DataTransfer, Event, native
  // input descriptors, Selection, DOM, Blob, FormData, Request and WebCrypto
  // are the actual Chrome implementations. No app source is modified.
  const program=new Function('location','return ('+SOURCE+')')({href:'https://chatgpt.com/'});
  const native={applicationID:'com.google.Chrome',sessionID:'synthetic-local-profile',windowID:'1',tabID:'1'};
  const call=command=>program(command,native);
  editor.focus();const selection=getSelection(),range=document.createRange();range.setStart(editor.firstChild,2);range.setEnd(editor.firstChild,7);selection.removeAllRanges();selection.addRange(range);
  const text=editor.textContent,anchor=selection.anchorNode,anchorOffset=selection.anchorOffset,focus=selection.focusNode,focusOffset=selection.focusOffset;
  const canvas=document.createElement('canvas');canvas.width=2;canvas.height=1;canvas.getContext('2d').fillRect(0,0,2,1);
  const png=await new Promise(r=>canvas.toBlob(r,'image/png')),bytes=new Uint8Array(await png.arrayBuffer()),sha=await hash(bytes),base64=btoa(String.fromCharCode(...bytes));
  const pixelURL=canvas.toDataURL('image/png');
  const tasks=[];let changes=0;
  const cachedTransport=body=>new Request('https://fixture.invalid/never-requested',{method:'POST',body});
  call({action:'captureTarget'});
  input.addEventListener('change',event=>{
    changes++;const file=event.target.files[0],index=tasks.length;check(file instanceof File,'native File required');
    let body=file,kind='File';
    if(index===1){kind='FormData';body=new FormData();body.append('file',file);}
    if(index===2){kind='Blob';body=new Blob([file],{type:file.type});}
    if(index===3)kind='cached Request constructor';
    // Constructing a Request extracts a native body, but sends nothing.
    const request=cachedTransport(body);
    const card=document.createElement('div');card.setAttribute('role','button');card.setAttribute('aria-label',file.name);
    const image=new Image();image.alt=file.name;image.src=URL.createObjectURL(file);card.append(image);
    const progress=document.createElement('span');progress.setAttribute('role','progressbar');progress.setAttribute('aria-label','正在上传 '+file.name);progress.setAttribute('aria-valuenow','10');card.append(progress);form.append(card);
    tasks.push({file,body,request,kind,card,image,progress});
    input.value=''; // Application-owned reset; Riftlet never clears this picker.
  });
  const operations=[];
  for(let index=0;index<5;index++){
    const target=call({action:'captureTarget'}),pin=call({action:'pinTarget',target,clickBindingID:crypto.randomUUID()});
    const identity={operationID:crypto.randomUUID(),assetID:crypto.randomUUID(),attempt:1,assetSHA256:sha,target:pin};
    const invocationID=index===0?undefined:crypto.randomUUID(),name='riftlet-'+identity.operationID+'.png';
    const command=action=>({action,identity,target:pin,...(invocationID?{invocationID}:{})});
    let resource;
    if(index){resource=call(command('prepareInputResource'));check(resource.kind==='emptyNativeFileInput','fresh native resource');}
    const begin=call({...command('begin'),uploadName:name,mediaType:'image/png',byteCount:bytes.length,...(resource?{inputResourceID:resource.resourceID}:{})});
    check(begin.rejectedBeforeBegin!==true,'begin accepted');
    call({...command('chunk'),chunkIndex:0,chunkBase64:base64});call({...command('commit'),chunkIndex:1});
    const record=()=>globalThis.__riftletWebAcceptance20261027v13.tail.operations.get(identity.operationID);
    await wait(()=>record().commitWorkSettled&&record().fileHashVerified);check(changes===index+1,'one change per operation');check(input.files.length===0&&input.value==='','actual app emptied native picker');
    const task=tasks[index];await task.image.decode();call(command('observe'));task.progress.setAttribute('aria-valuenow','40');
    await new Promise(r=>setTimeout(r,0));let observation=call(command('observe')).observation;
    check(observation.state==='uploadStarted','own START '+index);check(!observation.requestEvidence,'no invented request observation');
    operations.push({identity,command,record:record(),start:record().uploadStart});
    if(index===0){
      // A real scaled preview in this synthetic app cannot prove the original
      // pixels. Exercise the normal observer, without changing its records.
      task.progress.setAttribute('aria-valuenow','100');call(command('observe'));task.progress.remove();
      await new Promise(r=>setTimeout(r,0));
      const small=document.createElement('canvas');small.width=1;small.height=1;small.getContext('2d').fillRect(0,0,1,1);
      task.image.src=small.toDataURL('image/png');await task.image.decode();
      await wait(()=>record().completionUnavailable);check(call(command('observe')).observation.state==='unknown','scaled original stays UNKNOWN');
    }
    for(const prior of tasks)check(form.contains(prior.card),'prior card retained');
    check(editor.textContent===text&&selection.anchorNode===anchor&&selection.anchorOffset===anchorOffset&&selection.focusNode===focus&&selection.focusOffset===focusOffset,'text/selection retained');
  }
  // The native body extractions and original immutable Files remain independent
  // after four later native FileList submissions and application-owned resets.
  for(const task of tasks){
    check(await hash(await task.file.arrayBuffer())===sha,'original File bytes retained');
    const extracted=task.kind==='FormData'?(await task.request.formData()).get('file'):await task.request.blob();
    check(await hash(await extracted.arrayBuffer())===sha,'native Request body retained '+task.kind);
  }
  let independentCompletions=0;
  for(let index=1;index<tasks.length;index++){
    const task=tasks[index],op=operations[index];
    task.progress.setAttribute('aria-valuenow','100');call(op.command('observe'));task.progress.remove();
    await new Promise(r=>setTimeout(r,0));task.image.src=pixelURL;await task.image.decode();
    await wait(()=>op.record.proof&&!op.record.proofPending);
    check(call(op.command('observe')).observation.state==='attached','independent exact completion '+index);independentCompletions++;
  }
  const a=operations[0];check(a.record.inputCount===1&&a.record.uploadStart===a.start&&a.record.invocationID===undefined,'legacy operation untouched');
  check(call(a.command('observe')).observation.state==='unknown','legacy final remains UNKNOWN');
  check(changes===5,'five inputs exactly; A never replayed');
  const nextTarget=call({action:'captureTarget'}),nextPin=call({action:'pinTarget',target:nextTarget,clickBindingID:crypto.randomUUID()});
  const next={operationID:crypto.randomUUID(),assetID:crypto.randomUUID(),attempt:1,assetSHA256:sha,target:nextPin};
  const occupied=new DataTransfer();occupied.items.add(new File([png],'user-selected.png',{type:'image/png'}));input.files=occupied.files;
  let refused=false;try{call({action:'prepareInputResource',identity:next,target:nextPin,invocationID:crypto.randomUUID()});}catch(e){refused=/INPUT_RESOURCE_UNAVAILABLE/.test(e.message);}
  check(refused&&changes===5&&input.files[0].name==='user-selected.png','nonempty input refusal preserves selected file');
  Object.assign(report,{passed:true,nativeChanges:changes,originalFileBodiesVerified:tasks.length,nativeRequestBodiesVerified:tasks.length,independentCompletions,legacyUnknownUnchanged:true,textSelectionCardsPreserved:true,occupiedPickerRefused:true,networkRequests:0});
 } catch(error){report.error=String(error?.stack||error);}
 result.textContent=JSON.stringify(report);
})();
</script>`.replace('SOURCE',()=>JSON.stringify(source).replace(/<\/script/gi,'<\\/script'));
}

test('native Chrome preserves independent File/request bodies across five synthetic legacy-UNKNOWN appends',{
  skip:!binary&&!required?'CHROME_NOT_RUN: no native Chrome binary in this executor':false,timeout:45000
},()=>{
  assert.ok(binary,'CHROME_REQUIRED_BUT_UNAVAILABLE: native Chrome must run in this CI job');
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-native-input-'));
  try{
    const html=path.join(temp,'fixture.html');fs.writeFileSync(html,browserFixture());
    const run=spawnSync(binary,['--headless=new','--no-sandbox','--disable-gpu','--disable-background-networking',
      '--disable-component-update','--disable-sync','--no-first-run','--no-default-browser-check',
      '--user-data-dir='+path.join(temp,'isolated-profile'),'--virtual-time-budget=15000','--dump-dom',pathToFileURL(html).href],
      {encoding:'utf8',timeout:35000,maxBuffer:8*1024*1024});
    assert.equal(run.error,undefined,run.error?.message);
    assert.equal(run.status,0,run.stderr.slice(-2000));
    const match=run.stdout.match(/<pre id="result">([\s\S]*?)<\/pre>/);
    assert.ok(match,'Chrome did not render the fixture report');
    const report=JSON.parse(match[1].replace(/&quot;/g,'"').replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>'));
    assert.equal(report.passed,true,JSON.stringify(report));assert.equal(report.nativeChanges,5);assert.equal(report.networkRequests,0);
    console.log(JSON.stringify(report));
  }finally{fs.rmSync(temp,{recursive:true,force:true});}
});
