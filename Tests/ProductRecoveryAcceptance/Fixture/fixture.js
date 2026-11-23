(() => {
  'use strict';
  if (!window.ownedProductPage || top !== self || document.title !== 'CONTROLLED_PRODUCT_RECOVERY_FIXTURE') return;
  const form = document.querySelector('form'), editor = document.querySelector('#prompt-textarea');
  const row = form.querySelector('.flex'), baselineCard = row.firstElementChild;
  const input = form.querySelector('input[type=file]'), originalText = editor.textContent;
  const documentID = crypto.randomUUID(), originalRoot = document.documentElement;
  const files = new Map(), events = [], pending = new Set();
  let nextMode = 'preview', sends = 0, submits = 0, inputs = 0, changes = 0, duplicates = 0;
  let setterEntries = 0, setterReturns = 0, foreignSetters = 0;
  const desc = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'files');
  Object.defineProperty(HTMLInputElement.prototype,'files',{...desc,set(value) {
    if (this !== input) foreignSetters++;
    setterEntries++;
    const result=Reflect.apply(desc.set,this,[value]);
    setterReturns++;return result;
  }});
  const selected = 'preserve this original draft';
  const selectable = editor.firstChild, start = originalText.indexOf(selected);
  editor.focus();
  const selection = document.getSelection();
  selection.setBaseAndExtent(selectable,start,selectable,start+selected.length);

  function leaf(tag, text) {
    const node = document.createElement(tag);
    if (text) node.textContent = text;
    return node;
  }
  function button(label, text) {
    const node = leaf('button',text); node.type = 'button'; node.setAttribute('aria-label',label); return node;
  }
  function shell(file) {
    const tile = leaf('span'), surface = leaf('span');
    tile.className = 'group/composer-attachment group-card';
    surface.className = 'composer-attachment-surface';
    surface.dataset.fileName = file.name;
    tile.append(surface,button('Remove '+file.name,'×')); row.append(tile);
    return {tile,surface};
  }
  function render(record, mode) {
    const {tile,surface,file} = record;
    if (mode === 'ambiguous') {
      if (!tile.isConnected || !surface.querySelector('img[src]')) throw Error('Active original preview required');
      surface.dataset.state = 'failed';
      surface.append(leaf('span','Attachment unavailable'));
      record.state=mode;events.push({event:'card',operationID:record.id,state:mode});return;
    }
    delete surface.dataset.state;
    surface.replaceChildren();
    if (mode === 'unknown') {
      tile.remove();
    } else {
      if (!tile.isConnected) row.append(tile);
      if (mode === 'preview') {
        const image=leaf('img'); image.alt=file.name;
        record.blob ||= URL.createObjectURL(file);
        image.src=record.blob; surface.append(image);
      } else if (mode === 'pending') {
        surface.append(leaf('progress'));
      } else if (mode === 'failed') {
        const visual=leaf('span'), status=leaf('span'), alert=leaf('span'), names=leaf('span'), filename=leaf('span',file.name);
        alert.setAttribute('role','alert'); alert.setAttribute('aria-label',file.name);
        alert.append(leaf('span','Upload failed'));
        status.append(alert,button('Retry uploading '+file.name,'Retry')); visual.append(status);
        filename.className='truncate'; names.append(filename); surface.append(visual,names);
      }
    }
    record.state=mode;
    events.push({event:'card',operationID:record.id,state:mode});
  }
  form.addEventListener('submit',e=>{e.preventDefault();submits++;});
  form.querySelector('button[type=submit]').addEventListener('click',()=>{sends++;});
  input.addEventListener('input',()=>{
    inputs++;
    const file=input.files?.[0], match=/^riftlet-([0-9a-f-]{36})\.png$/i.exec(file?.name||'');
    if (!match || input.files.length!==1) throw Error('One operation-named PNG required');
    const id=match[1].toLowerCase();
    events.push({event:'input',operationID:id,bytes:file.size});
    if (files.has(id)) {duplicates++;return;}
    const record={id,file,hash:null,state:'input',blob:null,changeCount:0};
    files.set(id,record);
    const task=file.arrayBuffer().then(b=>crypto.subtle.digest('SHA-256',b)).then(b=>{
      record.hash=Array.from(new Uint8Array(b),v=>v.toString(16).padStart(2,'0')).join('');
    });
    pending.add(task);task.then(()=>pending.delete(task),()=>pending.delete(task));
  });
  input.addEventListener('change',()=>{
    changes++;
    const file=input.files?.[0];
    const record=[...files.values()].find(r=>r.file===file);
    if (!record) throw Error('No corresponding input');
    events.push({event:'change',operationID:record.id});
    if (++record.changeCount!==1) {duplicates++;return;}
    if (nextMode === 'silent') {
      record.state='input-without-card';nextMode='preview';return;
    }
    Object.assign(record,shell(file));
    const mode=nextMode==='pending'?'pending':'preview';
    nextMode='preview';render(record,mode);
  });
  function transition(id, mode) {
    if (!['preview','unknown','failed','ambiguous'].includes(mode)) throw Error('Unsupported card transition');
    const record=files.get(id.toLowerCase());
    if (!record?.tile || form.dataset.draftId!=='original') throw Error('No original file in this draft');
    render(record,mode);
    return true;
  }
  function setNext(mode) {
    if (!['preview','pending','silent','pre-input-failure'].includes(mode)) throw Error('Unsupported fixture mode');
    nextMode=mode;input.disabled=false;return true;
  }
  async function snapshot() {
    await Promise.all(pending);
    const s=document.getSelection();
    return {source:document.title,documentID,originalDocument:originalRoot===document.documentElement,
      originalComposer:editor.isConnected && form.contains(editor),originalDraft:form.dataset.draftId==='original',
      previousAttachmentPreserved:row.firstElementChild===baselineCard && baselineCard.textContent==='previous.png',
      text:editor.textContent,selection:s.toString(),anchor:s.anchorOffset,focus:s.focusOffset,
      selectionInOriginalEditor:editor.contains(s.anchorNode)&&editor.contains(s.focusNode),setterEntries,setterReturns,foreignSetters,inputs,changes,sends,submits,duplicates,
      files:[...files.values()].map(r=>({operationID:r.id,sha256:r.hash,bytes:r.file.size,state:r.state,
        changeCount:r.changeCount,present:r.tile?.isConnected===true})),events:[...events],adapterSHA256:ownedProductPage.sha};
  }
  function command(command,native) {
    if (command.action==='commit' && nextMode==='pre-input-failure') {
      nextMode='preview';input.disabled=true;
    }
    return ownedProductPage.program(command,native);
  }
  function navigate() {
    if (form.dataset.draftId!=='original') return false;
    const next=editor.cloneNode(false); next.textContent='Different controlled draft';editor.replaceWith(next);
    form.dataset.draftId='different';return true;
  }
  Object.defineProperty(window,'recoveryFixture',{value:Object.freeze({command,snapshot,setNext,transition,navigate})});
})();
