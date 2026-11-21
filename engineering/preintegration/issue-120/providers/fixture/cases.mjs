import {pinSyntheticDraft,sha256} from './synthetic-handoff.mjs';
import {inspectGeminiSurface,inspectLandingControls} from '../gemini-surface.mjs';

async function run() {
  const check=(ok,message)=>{if(!ok)throw Error(message);};
  const refused=async(op,reason)=>{let error;try{await op();}catch(e){error=e;}check(error?.message===reason,'expected '+reason+', got '+error?.message);};
  const canvas=document.createElement('canvas');canvas.width=canvas.height=3;
  const ctx=canvas.getContext('2d');
  async function png(color) {ctx.fillStyle=color;ctx.fillRect(0,0,3,3);const url=canvas.toDataURL();return {url,bytes:Uint8Array.from(atob(url.split(',')[1]),c=>c.charCodeAt(0))};}
  const a=await png('#216934'),b=await png('#f19226');
  const program=await (await fetch('/providers/fixture/synthetic-handoff.mjs')).arrayBuffer();
  const base={protocolRevision:1,providerRevision:1,attempt:1,hostBundle:'fixtureChrome',pid:101,processBirth:'fixture-birth',
    window:'fixture-window',tab:'fixture-tab',session:'fixture-session',route:location.pathname,surface:'ordinary-fixture',mode:'image-fixture',
    providerID:'fixture-gemini-like',programDigest:await sha256(program),document:crypto.randomUUID(),composer:crypto.randomUUID(),draftEpoch:crypto.randomUUID()};
  const field=document.querySelector('fieldset'), lane=field.querySelector('[data-fixture-members]'), input=field.querySelector('input'),
    foreign=document.querySelector('#fixture-foreign'), editor=field.querySelector('.ql-editor'),old=lane.firstElementChild;
  check(inspectGeminiSurface(document).state==='other_route','synthetic surface cannot be mistaken for live Gemini');
  const action=field.querySelector('simplified-input-menu button'),menu=action.closest('simplified-input-menu');
  const placeholder=document.createComment('menu slot');menu.before(placeholder);
  const nested=document.createElement('fieldset');field.append(nested);nested.append(menu);
  check(inspectLandingControls(document).state==='action_unavailable','nested owner loses action');
  placeholder.after(menu);nested.remove();foreign.form.id='foreign-form';
  action.setAttribute('form',foreign.form.id);
  check(inspectLandingControls(document).state==='action_unavailable','explicit foreign form loses action');
  action.removeAttribute('form');
  const dialog=document.createElement('div');dialog.setAttribute('role','dialog');field.append(dialog);dialog.append(menu);
  check(inspectLandingControls(document).state==='action_unavailable','dialog action excluded');
  placeholder.after(menu);dialog.remove();menu.inert=true;
  check(inspectLandingControls(document).state==='action_unavailable','inert action excluded');menu.inert=false;
  const actualEvents=[], commits=[], hits=[];let sends=0,foreignEvents=0;
  const native=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'files');
  Object.defineProperty(HTMLInputElement.prototype,'files',{...native,set(v){commits.push(this);return native.set.call(this,v);}});
  field.closest('form').addEventListener('submit',e=>{e.preventDefault();sends++;});
  for(const event of ['input','change']) {
    input.addEventListener(event,()=>actualEvents.push(event));
    foreign.addEventListener(event,()=>foreignEvents++);
  }
  editor.focus();const selection=getSelection();selection.setBaseAndExtent(editor.firstChild,2,editor.firstChild,5);
  const baselineText=editor.textContent,baselineSelection=selection.toString();
  function makeCard(name,image=null) {
    const tile=document.createElement('article');tile.className='member';tile.dataset.fixtureName=name;
    if(image){const preview=new Image();preview.alt=name;preview.src=image.url;tile.append(preview);}
    return tile;
  }
  async function fresh(sample=a) {
    const originalSHA256=await sha256(sample.bytes),k={...base,clickGeneration:crypto.randomUUID(),operation:crypto.randomUUID(),invocation:crypto.randomUUID(),originalSHA256,payloadSHA256:originalSHA256};
    const file=new File([sample.bytes],'riftlet-'+k.operation+'.png',{type:'image/png'});
    const h=pinSyntheticDraft(k);hits.push(h);return {k,file,h,read:(patch={})=>h.reader.observe({...k,...patch})};
  }
  const makeFailure=(card,name)=>{const out=document.createElement('output');out.dataset.fixtureFailed='';out.textContent=name;card.replaceChildren(out);};

  // The recipient sees a real FileList once. Simulate a lost reply by dropping
  // the resolved commit result. Both duplicate input and historical writes fail.
  const first=await fresh();const {k,file,h,read}=first;
  await refused(()=>pinSyntheticDraft(k),'input_fenced');
  await refused(()=>pinSyntheticDraft({...k,invocation:crypto.randomUUID(),clickGeneration:crypto.randomUUID()}),'input_fenced');
  await refused(()=>pinSyntheticDraft({...k,operation:crypto.randomUUID(),clickGeneration:crypto.randomUUID()}),'input_fenced');
  await refused(()=>pinSyntheticDraft({...k,operation:crypto.randomUUID(),invocation:crypto.randomUUID()}),'input_fenced');
  await Promise.all([h.commit(k,file),refused(()=>h.commit(k,file),'input_fenced')]);await refused(()=>h.commit(k,file),'input_fenced');
  check(input.files.length===1 && input.files[0]===file && !('commit' in h.reader),'one actual file and read-only history');
  check(await read()==='unknown','setter is not acceptance');
  const card=makeCard(file.name);lane.append(card);
  const spinner=document.createElement('progress');card.append(spinner);check(await read()==='unknown','name plus spinner');
  const other=makeCard(file.name,a);foreign.form.append(other);await other.firstChild.decode();
  check(await read()==='unknown','wrong composer exact image');
  let img=new Image();img.src=b.url;img.alt=file.name;card.replaceChildren(img);await img.decode();
  check(await read()==='unknown','wrong image under exact name');
  img.src=a.url;await img.decode();
  img.srcset=b.url+' 1x';await img.decode();
  check(img.currentSrc===b.url && await read()==='unknown','responsive preview displays other bytes');
  img.removeAttribute('srcset');await img.decode();
  async function duringDigest(change,reset,label) {
    const pending=read();change();check(await pending==='unknown',label);reset();await img.decode();
  }
  await duringDigest(()=>{img.hidden=true;},()=>{img.hidden=false;},'hidden while hashing');
  const conflictingError=document.createElement('output');conflictingError.dataset.fixtureFailed='';
  await duringDigest(()=>card.append(conflictingError),()=>conflictingError.remove(),'same card error while hashing');
  const extra=img.cloneNode();
  await duringDigest(()=>card.append(extra),()=>extra.remove(),'second image while hashing');
  await duringDigest(()=>{img.alt='another.png';},()=>{img.alt=file.name;},'renamed while hashing');
  await duringDigest(()=>{img.remove();card.append(img);},()=>{},'image moved away and back while hashing');
  const duplicate=makeCard(file.name,a);lane.append(duplicate);await duplicate.firstChild.decode();
  check(await read()==='unknown','two members cannot be disambiguated');duplicate.remove();
  check(await read()==='accepted_into_draft','one exact original image');
  const second=await fresh(b);
  await second.h.commit(second.k,second.file);const next=makeCard(second.file.name,b);lane.append(next);await next.firstChild.decode();
  check(await second.read()==='accepted_into_draft','independent later click');
  makeFailure(other,file.name);check(await read()==='previously_accepted','adjacent error cannot claim original');
  makeFailure(card,file.name);check(await read()==='original_card_failed','same original member error');
  check(await second.read()==='previously_accepted','other member unaffected');
  check(await read({invocation:crypto.randomUUID()})==='unavailable','wrong invocation');
  check(await read({mode:'other'})==='unavailable','wrong mode');
  const replacement=card.cloneNode(true);card.replaceWith(replacement);
  check(await read()==='unavailable','replacement cannot claim a past attachment');
  next.remove();lane.append(next);check(await second.read()==='unavailable','detached and reinserted original');
  const early=await fresh();await early.h.commit(early.k,early.file);const earlyError=makeCard(early.file.name);makeFailure(earlyError,early.file.name);lane.append(earlyError);
  check(await early.read()==='unknown','unverified error cannot fabricate an earlier positive acceptance');
  const staged=await fresh(),preexisting=makeCard(staged.file.name,a);lane.append(preexisting);await preexisting.firstChild.decode();
  await staged.h.commit(staged.k,staged.file);check(await staged.read()==='unknown','preexisting exact preview before setter');
  check(editor.textContent===baselineText && selection.anchorNode===editor.firstChild && selection.focusNode===editor.firstChild &&
    selection.anchorOffset===2 && selection.focusOffset===5 && selection.toString()===baselineSelection,'preserve actual draft text and selection after both clicks');
  const completedSetters=commits.length,completedChanges=actualEvents.filter(e=>e==='change').length;
  check(completedSetters===4 && completedChanges===4,'four successful dispatches');
  const movedImage=preexisting.firstChild,newShell=makeCard(staged.file.name);lane.append(newShell);newShell.append(movedImage);
  check(await staged.read()==='unknown','old preview rewrapped in a fresh shell');
  // The native files setter may have succeeded even when dispatch did not
  // return. An apparent preview cannot turn that ambiguity into permission.
  const interrupted=await fresh(), dispatch=input.dispatchEvent;
  input.dispatchEvent=function(e){if(e.type==='change')throw Error('lost_change');return dispatch.call(this,e);};
  try {await refused(()=>interrupted.h.commit(interrupted.k,interrupted.file),'lost_change');} finally {delete input.dispatchEvent;}
  const unconfirmed=makeCard(interrupted.file.name,a);lane.append(unconfirmed);await unconfirmed.firstChild.decode();
  const interruptedState=await interrupted.read();
  check(interruptedState==='unknown','unknown delivery cannot manufacture acceptance');
  await refused(()=>interrupted.h.commit(interrupted.k,interrupted.file),'input_fenced');
  const routeChange=await fresh();history.pushState({},'',location.pathname);
  await refused(()=>routeChange.h.commit(routeChange.k,routeChange.file),'target_changed');
  const changedMode=await fresh();field.closest('form').dataset.fixtureMode='document';field.closest('form').dataset.fixtureMode='image-fixture';
  await refused(()=>changedMode.h.commit(changedMode.k,changedMode.file),'target_changed');
  const rebound=await fresh();const label=field.querySelector('label');label.htmlFor=foreign.id;
  await refused(()=>rebound.h.commit(rebound.k,rebound.file),'target_changed');label.htmlFor=input.id;
  const obsolete=await fresh();field.remove();document.forms[0].append(field);
  await refused(()=>obsolete.h.commit(obsolete.k,obsolete.file),'target_changed');
  check(commits.length===5 && commits.every(node=>node===input) && foreignEvents===0 && sends===0,'exactly five explicit native setters, zero foreign events or sends');
  check(actualEvents.join(',')===[...Array(4).fill('input,change'),'input'].join(','),'fixture event recipe');
  check(editor.textContent===baselineText && old.textContent==='Older fixture attachment','draft text and old card preserved');
  for(const handle of hits) handle.close();
  await refused(()=>pinSyntheticDraft(k),'input_fenced');
  await refused(()=>h.commit(k,file),'target_changed');
  // Exhaustion closes the fixture to new identities for the rest of this page
  // lifetime. No eviction, timer, or file storage can resurrect an older key.
  let reachedLimit=false;
  for(let i=0;i<=256;i++) {
    try {pinSyntheticDraft({...k,operation:crypto.randomUUID(),invocation:crypto.randomUUID(),clickGeneration:crypto.randomUUID()}).close();}
    catch(e) {check(e.message==='input_fenced','unexpected exhaustion refusal');reachedLimit=true;break;}
  }
  check(reachedLimit,'bounded lifetime');await refused(()=>pinSyntheticDraft(k),'input_fenced');
  check(commits.length===5,'no new writer after close or lifetime limit');
  return {scope:'synthetic loopback only',completedDispatch:{setters:completedSetters,changes:completedChanges},interruptedDispatch:{setters:commits.length-completedSetters,changes:actualEvents.filter(e=>e==='change').length-completedChanges,observation:interruptedState},nativeSetters:commits.length,returnedChanges:actualEvents.filter(e=>e==='change').length,foreignEvents,sends,draftSelectionPreserved:true};
}
run().then(r=>{window.fixtureResult=r;},e=>{window.fixtureFailure=e.message;});
