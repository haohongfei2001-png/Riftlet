'use strict';
// Offline, headless real Chromium PNG/Canvas/DOM regression. Progress and React
// ancestry are fixtures. This is NOT ChatGPT/network/macOS upload acceptance.
// Install playwright@1.62.1 outside the checkout and set NODE_PATH to its modules.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const {deflateSync} = require('node:zlib');
const {createHash, randomUUID} = require('node:crypto');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, '../Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js'), 'utf8');
const sha = b => createHash('sha256').update(b).digest('hex');
const native = {applicationID:'com.google.Chrome',sessionID:'4242:1',windowID:'17',tabID:'19'};
const url = 'https://chatgpt.com/c/11111111-1111-4111-8111-111111111111';
function crc32(bytes) {
  let crc=0xffffffff;
  for(const byte of bytes){crc^=byte;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}
  return (crc^0xffffffff)>>>0;
}
function chunk(type, bytes) {
  const data=Buffer.concat([Buffer.from(type),bytes]),size=Buffer.alloc(4),crc=Buffer.alloc(4);
  size.writeUInt32BE(bytes.length);crc.writeUInt32BE(crc32(data));return Buffer.concat([size,data,crc]);
}
function png(width,height,level,changed=false) {
  const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(width);ihdr.writeUInt32BE(height,4);ihdr[8]=8;ihdr[9]=6;
  const raw=Buffer.alloc((width*4+1)*height);
  for(let y=0;y<height;y++)for(let x=0;x<width;x++){
    const p=y*(width*4+1)+1+x*4;raw[p]=x%256;raw[p+1]=y%256;raw[p+2]=43;raw[p+3]=x<width/2?255:128;
  }
  if(changed)raw[1]^=1;
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ihdr),
    chunk('IDAT',deflateSync(raw,{level})),chunk('IEND',Buffer.alloc(0))]);
}
const original=png(1800,1400,9);
assert.ok(original.length<=8*1024*1024);
async function run(browser, name, preview, expected, program=source, pinnedSwitch=false) {
  const context=await browser.newContext({serviceWorkers:'block'});
  const requests=[];
  await context.route('**/*',route=>{
    requests.push(route.request().url());
    return route.request().url()===url ? route.fulfill({contentType:'text/html',body:`<!doctype html><html lang="zh"><meta charset="utf-8"><body>
      <form data-chatgpt-composer data-composer-placement="thread" data-thread-find-composer="true">
      <div contenteditable="true" role="textbox" aria-label="询问 ChatGPT">Synthetic draft only</div>
      <input type="file" aria-label="附加文件"></form></body></html>`}) : route.abort();
  });
  try {
    const page=await context.newPage();page.setDefaultTimeout(10000);await page.goto(url);
    await page.evaluate(()=>{
      const form=document.querySelector('form'),id='11111111-1111-4111-8111-111111111111';
      const leaf={stateNode:form,memoizedProps:{}};
      const mode={child:leaf,memoizedProps:{conversationId:id,isHome:false,isWork:false,readOnly:false}};
      const draft={child:mode,memoizedProps:{conversationId:id,draftKey:id,isWorkConversation:false,isTemporaryChat:false,readOnly:false,surfacePlacement:{kind:'thread'}}};
      const root={tag:3,child:draft,stateNode:{},return:null};root.stateNode.current=root;
      leaf.return=mode;mode.return=draft;draft.return=root;form.__reactFiber$fixture=leaf;
      window.counts={change:0,send:0,oversizedDecode:0};
      document.querySelector('input').addEventListener('change',()=>counts.change++);
      form.addEventListener('submit',e=>{counts.send++;e.preventDefault();});
      const decode=window.atob;window.atob=s=>{if(s.length>Math.floor(8*1024*1024/3)*4){counts.oversizedDecode++;throw Error('oversized atob');}return decode(s);};
    });
    await page.evaluate(program);
    const identity=await page.evaluate(({native,op,asset,hash,pin})=>{
      let target=riftletWebAcceptance({action:'captureTarget'},native);
      if(pin)target=riftletWebAcceptance({action:'pinTarget',target,clickBindingID:pin},native);
      return {operationID:op,assetID:asset,attempt:1,assetSHA256:hash,target};
    },{native,op:randomUUID(),asset:randomUUID(),hash:sha(original),pin:pinnedSwitch?randomUUID():null});
    const call=command=>page.evaluate(({command,native})=>riftletWebAcceptance(command,native),{command,native});
    let switchedState=null, other=null;
    if(pinnedSwitch){
      other=await context.newPage();await other.goto(url);await other.bringToFront();
      switchedState=await page.evaluate(()=>({visibility:document.visibilityState,focus:document.hasFocus()}));
    }
    const base={identity,target:identity.target},filename='riftlet-'+identity.operationID+'.png';
    await call({...base,action:'begin',uploadName:filename,byteCount:original.length,mediaType:'image/png'});
    let index=0;for(let offset=0;offset<original.length;offset+=65536)
      await call({...base,action:'chunk',chunkIndex:index++,chunkBase64:original.subarray(offset,offset+65536).toString('base64')});
    await call({...base,action:'commit',chunkIndex:index});
    await page.waitForFunction(()=>counts.change===1&&[...__riftletWebAcceptance20261027v13.head.operations.values()][0].fileHashVerified);
    await page.evaluate(filename=>{
      const card=document.createElement('div');card.setAttribute('role','button');card.setAttribute('aria-label',filename);
      const image=document.createElement('img');image.alt=filename;card.append(image);
      const progress=document.createElement('div');progress.setAttribute('role','progressbar');progress.setAttribute('aria-label','正在上传 '+filename);progress.setAttribute('aria-valuenow','20');card.append(progress);
      document.querySelector('form').append(card);window.view={card,image,progress};
    },filename);
    await call({...base,action:'observe'});
    await page.evaluate(()=>view.progress.setAttribute('aria-valuenow','100'));
    await call({...base,action:'observe'});
    await page.evaluate(()=>view.progress.remove());await call({...base,action:'observe'});
    await page.evaluate(uri=>{view.image.src=uri;},'data:image/png;base64,'+preview.toString('base64'));
    await page.waitForFunction(()=>{
      const op=[...__riftletWebAcceptance20261027v13.head.operations.values()][0];return op.loaded&&!op.proofPending;
    });
    const response=await call({...base,action:'observe'}),counts=await page.evaluate(()=>window.counts);
    assert.equal(response.observation.state,expected);assert.equal(counts.change,1);assert.equal(counts.send,0);assert.equal(counts.oversizedDecode,0);
    assert.ok(requests.every(request=>request===url));
    if(other)assert.equal(await other.locator('input[type=file]').evaluate(e=>e.files.length),0);
    return {switchedState,backgroundExercised:pinnedSwitch?(switchedState.visibility==='hidden'||!switchedState.focus):null,name,result:'PASS',observation:expected,originalBytes:original.length,previewBytes:preview.length,counts,network:'intercepted synthetic document only'};
  }finally{await context.close();}
}
(async()=>{
  const browser=await chromium.launch({headless:true});
  try {
    const expanded=png(1800,1400,0);assert.ok(expanded.length>8*1024*1024);
    const oldGuard=source.replace('if (!/^data:image\\/png;base64,/.test(source)) return;',
      'if (!/^data:image\\/png;base64,/.test(source) || source.length > Math.ceil(MAX_BYTES*4/3)+64) return;');
    assert.notEqual(oldGuard,source);
    const cases=[];
    cases.push(await run(browser,'old encoding gate reproduces missing proof',expanded,'inputTriggered',oldGuard));
    cases.push(await run(browser,'expanded PNG exact same dimensions and pixels',expanded,'attached'));
    cases.push(await run(browser,'pinned A after bringToFront B (inspect actual focus)',expanded,'attached',source,true));
    cases.push(await run(browser,'one visible channel changed',png(1800,1400,0,true),'invalidated'));
    cases.push(await run(browser,'smaller preview cannot prove original',png(900,700,0),'invalidated'));
    console.log(JSON.stringify({sourceSHA256:sha(source),browser:browser.version(),driver:require('playwright/package.json').version,
      scope:'headless synthetic DOM with real PNG decoder and sRGB canvas; not live ChatGPT, transport or original server bytes',cases},null,2));
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
