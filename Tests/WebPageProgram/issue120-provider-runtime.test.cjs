'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {spawn,execFileSync} = require('node:child_process');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');

const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const resources = path.resolve(__dirname,'../../Sources/RiftletAdapters/Resources');
const program = fs.readFileSync(path.join(resources,'issue120-provider-runtime.js'),'utf8');
const profiles = JSON.parse(fs.readFileSync(path.join(resources,'issue120-provider-profiles.json')));
const gemini = profiles.find(p => p.id === 'gemini');

// This server owns the HTML, the only recipe and the test origin. No request
// is issued to an AI website, no production manifest contains this recipe.
const html = `<!doctype html><meta charset=utf-8><form><fieldset>
<rich-textarea><div role=textbox class=ql-editor contenteditable=true>original draft 原稿</div></rich-textarea>
<simplified-input-menu><gem-icon-button><button type=button aria-controls=picker aria-label="Upload image">Upload</button>
</gem-icon-button></simplified-input-menu><section aria-label=attachments><article aria-label=old></article></section>
<button type=submit>Send</button></fieldset></form><form><input type=file id=foreign></form>
<script src="/runtime.js"></script><script src="/cases.js"></script>`;

async function cases(catalogEntry) {
  const recipe = {events:'input-change',lane:'section[aria-label=attachments]',card:'article',maxBytes:65536,
    explicitFailure:'[role=alert][aria-label="Attachment failed"]'};
  const spec = {...catalogEntry,origin:location.origin,paths:['/app']};
  const compiled = typeof compiledProduction !== 'undefined';
  Object.defineProperty(Object.prototype,'recipe',{value:recipe,configurable:true,writable:true});
  const production = compiled ? compiledProduction() : createProvider(catalogEntry);
  const discovered = compiled ? compiledDiscovery() : createProvider(spec);
  delete Object.prototype.recipe;
  const writer = compiled ? compiledWriter : () => createProvider({...spec,recipe});
  const expect = (value,label) => {if(!value) throw Error(label);};
  const expectError = async (action,label) => {
    try {await action();} catch(e) {expect(e.message===label,'unexpected '+e.message);return;}
    throw Error('expected '+label);
  };
  const uid = () => crypto.randomUUID();
  const body = Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2ZsAAAAASUVORK5CYII='),c=>c.charCodeAt(0));
  const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',body)),b=>b.toString(16).padStart(2,'0')).join('');
  const ticket = () => ({click:uid(),operation:uid(),invocation:uid(),payloadSHA256:hash,originalSHA256:hash});
  const makeFile = t=>new File([body],'riftlet-'+t.operation+'.png',{type:'image/png'});
  const lane=document.querySelector('section'),owner=document.querySelector('fieldset'),editor=owner.querySelector('.ql-editor');
  const old=lane.firstElementChild, draft=editor.firstChild, selection=getSelection();
  editor.focus();
  selection.setBaseAndExtent(draft,1,draft,5);
  const selected=selection.toString();
  let inputs=0,changes=0,foreign=0,sends=0;
  owner.addEventListener('input',e=>{if(e.target.type==='file')inputs++});
  owner.addEventListener('change',e=>{if(e.target.type==='file')changes++});
  document.querySelector('#foreign').onchange=()=>foreign++;
  document.addEventListener('submit',e=>{e.preventDefault();sends++;});
  expect(production.inspect()==='other_route','production origin');
  expect(discovered.inspect()==='editor_and_upload_action','Gemini editor/control shape');
  const trigger=owner.querySelector('button'); trigger.id='original-opener';
  const menuPin=discovered.pin(uid());
  trigger.removeAttribute('aria-controls');
  expect(menuPin.inspectAttachmentEntry()==='menu_relation_unavailable','no arbitrary global input');
  const menu=document.createElement('div');menu.role='menu';menu.id='portal';
  const item=document.createElement('label');item.role='menuitem';item.htmlFor='menu-file';item.textContent='Upload image';
  const menuFile=document.createElement('input');menuFile.type='file';menuFile.hidden=true;menuFile.id='menu-file';
  menu.append(item,menuFile);document.body.append(menu);trigger.setAttribute('aria-controls',menu.id);
  expect(menuPin.inspectAttachmentEntry()==='menu_not_open','collapsed menu');
  trigger.setAttribute('aria-expanded','true');
  expect(menuPin.inspectAttachmentEntry()==='menu_owner_unproven','unowned portal');
  menu.setAttribute('aria-labelledby',trigger.id);
  expect(menuPin.inspectAttachmentEntry()==='menu_owned_input_observed','explicit portal input');
  const duplicate=item.cloneNode(true);menu.append(duplicate);
  expect(menuPin.inspectAttachmentEntry()==='menu_items_ambiguous','two matching items');duplicate.remove();
  const foreignForm=document.querySelector('#foreign').form;foreignForm.append(menuFile);
  expect(menuPin.inspectAttachmentEntry()==='menu_item_owner_unproven','foreign form owner of portal item');
  menu.append(menuFile);
  const twin=menuFile.cloneNode();menu.append(twin);
  expect(menuPin.inspectAttachmentEntry()==='menu_input_unproven','colliding input id');twin.remove();
  const other=document.createElement('button');other.setAttribute('aria-controls',menu.id);foreignForm.append(other);
  expect(menuPin.inspectAttachmentEntry()==='menu_relation_ambiguous','two portal controllers');other.remove();
  menu.remove();trigger.setAttribute('aria-controls','picker');trigger.removeAttribute('aria-expanded');
  menuPin.close();expect(menuPin.inspectAttachmentEntry()==='original_surface_changed','closed pin');
  const t=ticket(),first=writer().pin(t.click);
  const picker=document.createElement('input');picker.type='file';picker.id='picker';picker.hidden=true;
  owner.append(picker);
  expect(discovered.inspect()==='owned_input','explicit linked input appeared');
  const readOnly=discovered.pin(t.click);
  await expectError(()=>readOnly.commit(t,makeFile(t)),'unverified_event_recipe');
  readOnly.close();
  await expectError(()=>writer().pin(t.click),'input_fenced');
  expect(await first.commit(t,makeFile(t))==='input_returned','input result');
  expect(await first.observe(t)==='unknown','input alone is not acceptance');
  await expectError(()=>first.commit(t,makeFile(t)),'input_fenced');
  const extra=uid(),secondHandle=writer().pin(extra);
  await expectError(()=>secondHandle.commit({...t,click:extra},makeFile(t)),'input_fenced');
  secondHandle.close();
  const newPicker=picker.cloneNode(),newTrigger=trigger.cloneNode(true);
  picker.replaceWith(newPicker);trigger.replaceWith(newTrigger);
  expect(!first.current(),'original writer retired after controls rebuilt');
  const card=document.createElement('article'),image=new Image();
  image.alt=card.ariaLabel=makeFile(t).name;
  image.src='data:image/png;base64,'+btoa(String.fromCharCode(...body));
  card.append(image);lane.append(card);await image.decode();
  expect(await first.observe({...t,invocation:uid()})==='unavailable','foreign invocation');
  expect(await first.observe(t)==='accepted_into_draft','matching payload with prior original card retained');
  const error=document.createElement('div');error.role='alert';error.ariaLabel='Attachment failed';error.textContent='Upload failed';
  old.remove();
  card.replaceChildren(error);
  expect(await first.observe(t)==='original_card_failed','same original failed after controls rebuilt');
  expect(newPicker.files.length===0,'replacement input untouched');
  lane.prepend(old);
  newPicker.replaceWith(picker);newTrigger.replaceWith(trigger);
  card.remove();lane.append(card);
  expect(await first.observe(t)==='unavailable','removed/reinserted card');
  expect(selection.toString() === selected && selection.anchorNode === draft && selection.focusNode === draft &&
    selection.anchorOffset === 1 && selection.focusOffset === 5, 'original selection retained through handoff');
  const aba=ticket(),stale=writer().pin(aba.click);
  history.pushState({},'', '/another-draft');
  const returned=new Promise(resolve=>window.addEventListener('popstate',resolve,{once:true}));
  history.back();await returned;
  expect(location.pathname==='/app' && stale.current()===false,'navigation ABA retired');
  await expectError(()=>stale.commit(aba,makeFile(aba)),'target_or_payload_changed');
  stale.close();
  await expectError(()=>writer().pin(aba.click),'input_fenced');
  const replace=writer().pin(uid());
  history.replaceState({},'',location.href);
  expect(replace.current()===false,'same-URL replace retired'); replace.close();
  const t2=ticket(),second=writer().pin(t2.click);
  owner.remove();document.querySelector('form').append(owner);
  await expectError(()=>second.commit(t2,makeFile(t2)),'target_or_payload_changed');
  expect(picker.files.length===1 && picker.files[0].name===makeFile(t).name,'one input/file');
  expect(editor.textContent==='original draft 原稿' && old.parentNode===lane,'retained original data');
  // The deliberate owner removal above can itself reset a browser selection.
  expect(inputs===1 && changes===1 && foreign===0 && sends===0,'event counts');
  first.close();second.close();
  const priorCases={};
  const color = value => {
    const canvas=document.createElement('canvas');canvas.width=canvas.height=1;
    const context=canvas.getContext('2d');context.fillStyle=value;context.fillRect(0,0,1,1);
    return canvas.toDataURL();
  };
  const red=color('red'),blue=color('blue');
  for (const scenario of ['unchanged','same-attributes','label-aba','card-aba','image-aba','src-aba','responsive-source']) {
    const prior=document.createElement('article'),preview=new Image(),picture=document.createElement('picture');
    const source=document.createElement('source');
    prior.ariaLabel='existing';preview.src=red;
    if (scenario==='responsive-source') {source.srcset=red+' 1x';picture.append(source);}
    picture.append(preview);prior.append(picture);lane.replaceChildren(prior);
    await preview.decode();
    const request=ticket(),handle=writer().pin(request.click),initial=inputs;
    const write=await handle.commit(request,makeFile(request));
    const own=document.createElement('article'),ownImage=new Image();
    ownImage.alt=own.ariaLabel=makeFile(request).name;
    ownImage.src='data:image/png;base64,'+btoa(String.fromCharCode(...body));own.append(ownImage);lane.append(own);
    await ownImage.decode();
    if (scenario==='same-attributes') {
      prior.setAttribute('aria-label',prior.getAttribute('aria-label'));
      preview.setAttribute('src',preview.getAttribute('src'));
    }
    if (scenario==='label-aba') {prior.ariaLabel='renamed';prior.ariaLabel='existing';}
    if (scenario==='card-aba') {prior.remove();lane.prepend(prior);}
    if (scenario==='image-aba') {
      const other=preview.cloneNode();preview.replaceWith(other);other.replaceWith(preview);
    }
    if (scenario==='src-aba') {
      preview.src=blue;await preview.decode();preview.src=red;await preview.decode();
    }
    if (scenario==='responsive-source') {
      source.srcset=blue+' 1x';await preview.decode();
      expect(preview.src===red && preview.currentSrc===blue,'effective responsive resource changed');
    }
    const state=await handle.observe(request);
    expect(write==='input_returned' && inputs-initial===1 && changes===inputs,'independent single input '+scenario);
    const retained=scenario==='unchanged' || scenario==='same-attributes';
    expect(state===(retained?'accepted_into_draft':'unknown'),'old preview continuity '+scenario);
    expect(await handle.observe(request)===state,'read-only repeat '+scenario);
    await expectError(()=>handle.commit(request,makeFile(request)),'input_fenced');
    priorCases[scenario]=state;handle.close();
  }
  return {inputs,changes,foreign,sends,selected,priorCases};
}

test('candidate provider resolves a Gemini-shaped local draft and proves its own single attachment in Chrome',
  {skip:!fs.existsSync(chrome),timeout:30000},async()=>{
    const profile=fs.mkdtempSync(path.join(os.tmpdir(),'riftlet-provider-chrome-'));
    let deliver,rejectResult,child,timer;
    const result=new Promise((a,b)=>{deliver=a;rejectResult=b;});
    let bundledProgram=program;
    const script=`(${cases.toString()})(${JSON.stringify(gemini)}).then(result=>fetch('/result',{method:'POST',body:JSON.stringify(result)})).catch(e=>fetch('/result',{method:'POST',body:JSON.stringify({error:e.message})}));`;
    const server=http.createServer((req,res)=>{
      if(req.url==='/result' && req.method==='POST'){
        let s='';req.setEncoding('utf8');req.on('data',d=>s+=d);req.on('end',()=>{
          res.end();try{deliver(JSON.parse(s));}catch(e){rejectResult(e);}
        });return;
      }
      const pages={'/app':['text/html',html],'/runtime.js':['text/javascript',bundledProgram],'/cases.js':['text/javascript',script]};
      const doc=pages[req.url];if(!doc){res.writeHead(404).end();return;}
      res.writeHead(200,{'Content-Type':doc[0]+'; charset=utf-8','Cache-Control':'no-store',
        'Content-Security-Policy':"default-src 'none'; script-src 'self'; img-src data:; connect-src 'self'; form-action 'none'"}).end(doc[1]);
    });
    try {
      await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
      if(process.env.RIFTLET_TEST_PROVIDER_EXPORTER) {
        bundledProgram=execFileSync(process.env.RIFTLET_TEST_PROVIDER_EXPORTER,
          ['http://127.0.0.1:'+server.address().port],{encoding:'utf8'});
      }
      child=spawn(chrome,['--headless','--disable-background-networking','--disable-sync','--disable-extensions',
        '--no-first-run','--no-default-browser-check','--user-data-dir='+profile,
        'http://127.0.0.1:'+server.address().port+'/app'],{stdio:'ignore'});
      child.once('error',rejectResult);
      child.once('exit',()=>rejectResult(Error('controlled Chrome exited before report')));
      timer=setTimeout(()=>rejectResult(Error('no controlled Chrome report')),22000);
      const receipt=await result;
      assert.deepEqual(receipt,{inputs:8,changes:8,foreign:0,sends:0,selected:'rigi',
        priorCases:{unchanged:'accepted_into_draft','same-attributes':'accepted_into_draft','label-aba':'unknown','card-aba':'unknown','image-aba':'unknown',
          'src-aba':'unknown','responsive-source':'unknown'}});
    } finally {
      clearTimeout(timer);
      if(child && child.exitCode===null && child.signalCode===null){
        const closed=new Promise(resolve=>child.once('exit',resolve));child.kill('SIGTERM');await closed;
      }
      server.closeAllConnections();await new Promise(resolve=>server.close(resolve));
      fs.rmSync(profile,{recursive:true,force:true,maxRetries:3});
    }
  });
