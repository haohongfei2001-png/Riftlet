'use strict';
window.qa = (() => {
  const form = document.querySelector('form'), lane = document.querySelector('#lane');
  const field = form.querySelector('input');
  let editor = form.querySelector('textarea');
  let selectionWitness, savedCards, sendClicks = 0;
  form.querySelector('[type=submit]').addEventListener('click', () => sendClicks++);
  const prior = document.querySelector('#prior');
  const operations = [], bytesSeen = [], changeTimes = [];
  const counts = {setter: 0, input: 0, change: 0, send: 0};
  const files = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'files');
  Object.defineProperty(HTMLInputElement.prototype, 'files', {...files, set(value) {
    if (this !== field) throw Error('unexpected file input');
    counts.setter++;
    files.set.call(this, value);
    bytesSeen.push(files.get.call(this)[0]);
  }});
  form.addEventListener('submit', event => { counts.send++; event.preventDefault(); });
  field.addEventListener('input', () => counts.input++);
  field.addEventListener('change', event => {
    counts.change++; changeTimes.push(event.timeStamp);
    const file = field.files[0], op = operations.find(entry => entry.name === file.name);
    if (!op || op.placeholder) throw Error('unowned or repeated browser change');
    op.placeholder = placeholder(file.name);
  });
  const hash = async bytes => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)),
    x => x.toString(16).padStart(2, '0')).join('');
  const bits = base64 => Uint8Array.from(atob(base64), x => x.charCodeAt(0));
  const encode = bytes => btoa(String.fromCharCode(...bytes));
  let mode, call, callPin, decodeGate;
  function defer() { let resolve;const promise=new Promise(wake=>{resolve=wake;});return {promise,resolve}; }
  function failedNeighbor(alias) {
    const card=divShell(), label=visual(), retry=document.createElement('button');
    card.setAttribute('data-state','failed');label.textContent=alias;retry.type='button';
    retry.setAttribute('aria-label','Retry uploading '+alias);retry.textContent='Retry';
    card.append(label,retry);lane.append(card);
  }

  // A legal PNG tEXt chunk changes the encoding and preserves every RGBA pixel.
  function taggedPNG(original) {
    const data = new TextEncoder().encode('Fixture\0qa');
    const chunk = new Uint8Array(data.length + 12), dv = new DataView(chunk.buffer);
    dv.setUint32(0, data.length); chunk.set([116, 69, 88, 116], 4); chunk.set(data, 8);
    let crc = 0xffffffff;
    for (const byte of chunk.subarray(4, 8 + data.length)) {
      crc ^= byte;
      for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
    dv.setUint32(8 + data.length, (crc ^ 0xffffffff) >>> 0);
    const joined = new Uint8Array(original.length + chunk.length), at = original.length - 12;
    joined.set(original.subarray(0, at)); joined.set(chunk, at); joined.set(original.subarray(at), at + chunk.length);
    return joined;
  }

  function imageURL(index, corrupt = false) {
    const canvas = document.createElement('canvas'); canvas.width = 36; canvas.height = 24;
    const ctx = canvas.getContext('2d'), rgba = ctx.createImageData(36, 24);
    for (let y = 0; y < 24; y++) for (let x = 0; x < 36; x++) {
      const offset = (y * 36 + x) * 4;
      rgba.data.set([(x * 7 + index * 59) % 256, (y * 11) % 256, (x + y * 3) % 256,
        (x + y) % 3 === 0 ? 128 : 255], offset);
    }
    if (corrupt === 'onePixel') rgba.data[(19 * 36 + 29) * 4 + 1] ^= 128;
    if (corrupt === 'oneAlpha') rgba.data[(19 * 36 + 29) * 4 + 3] = 63;
    ctx.putImageData(rgba, 0, 0);
    return canvas.toDataURL('image/png');
  }
  async function comparePreview(file, image) {
    const original = await createImageBitmap(file);
    try {
      if (original.width !== image.naturalWidth || original.height !== image.naturalHeight) throw Error('preview dimensions changed');
      const canvas = document.createElement('canvas'); canvas.width = original.width; canvas.height = original.height;
      const context = canvas.getContext('2d', {willReadFrequently:true,colorSpace:'srgb'});
      function pixels(drawable) {
        context.clearRect(0,0,canvas.width,canvas.height); context.drawImage(drawable,0,0);
        return context.getImageData(0,0,canvas.width,canvas.height).data;
      }
      const a=pixels(original), b=pixels(image);
      let differentPixels=0, partialAlpha=0, differentAlpha=0;
      for (let i=0;i<a.length;i+=4) {
        if (a[i+3]>0 && a[i+3]<255) partialAlpha++;
        if (a[i+3]!==b[i+3]) differentAlpha++;
        if (a[i]!==b[i] || a[i+1]!==b[i+1] || a[i+2]!==b[i+2] || a[i+3]!==b[i+3]) differentPixels++;
      }
      return {pixels:original.width*original.height,differentPixels,partialAlpha,differentAlpha};
    } finally { original.close(); }
  }
  function divShell() {
    const card = document.createElement('div'); card.classList.add('group/composer-attachment', 'composer-attachment-surface');
    return card;
  }
  function visual() {
    const span = document.createElement('span'); span.className = 'composer-attachment-surface'; return span;
  }
  function removeFor(name) {
    const b = document.createElement('button'); b.type = 'button'; b.setAttribute('aria-label', '移除“' + name + '”'); return b;
  }
  function placeholder(name) {
    const shell = document.createElement('span'); shell.classList.add('group/composer-attachment');
    const surface = visual(), label = document.createElement('span');
    label.className = 'truncate'; label.textContent = name;
    surface.append(label); shell.append(surface, removeFor(name)); lane.append(shell); return shell;
  }

  function observe(op) { return call({...op.command('observe'), preferStartReceipt:true}).observation; }
  function receipt(value) {
    return {state:value.state, start:!!value.uploadStart, original:value.belongsToOriginalDraft,
      attachmentID:value.attachmentID || null, evidenceID:value.uploadStart?.evidenceID || null,
      exact:value.exactImageIdentity===true,inputCount:value.uploadStart?.inputCount ?? null,
      inputSequence:value.uploadStart?.inputSequence ?? null,startSequence:value.uploadStart?.startSequence ?? null};
  }
  async function prepare() {
    const index = operations.length, seedURL = imageURL(index);
    const original = taggedPNG(bits(seedURL.split(',')[1]));
    const id = crypto.randomUUID(), opID = crypto.randomUUID(), inv = crypto.randomUUID();
    const name = 'riftlet-' + opID + '.png', alias = 'riftlet-' + opID + '.webp';
    const pin = crypto.randomUUID();
    if (callPin({action:'pinTarget', address:'https://chatgpt.com/',clickWitnessID:pin}) !== 'bound') throw Error('pin failed');
    const target = call({action:'captureTarget',clickWitnessID:pin});
    if (!call({action:'validate',target}).valid) throw Error('original validation failed');
    const identity = {target,assetID:id,operationID:opID,assetSHA256:await hash(original),attempt:1};
    const op = {index, name, alias, seedURL, original, target, identity, inv, command:action=>({action,target,identity,invocationID:inv})};
    if (['oldCard','oldSurface','oldRemove'].includes(mode)) {
      const shell=divShell(), surface=visual(), button=removeFor(alias);
      shell.append(surface,button);lane.append(shell);
      if(mode==='oldCard')op.oldCard=shell;
      if(mode==='oldSurface')op.oldSurface=surface;
      if(mode==='oldRemove')op.oldRemove=button;
      op.oldShell=shell;
    }
    if (mode === 'oldImage') {
      op.oldImage=document.createElement('img');op.oldImage.alt='unrelated prior preview';op.oldImage.src=seedURL;
      lane.append(op.oldImage);await op.oldImage.decode();
    }
    operations.push(op);
    return index;
  }
  async function commit(index) {
    const op = operations[index], name = op.name, size = op.original.length;
    if (call({...op.command('begin'),uploadName:name,mediaType:'image/png',byteCount:size}).nextChunk !== 0) throw Error('begin failed');
    if (call({...op.command('chunk'),chunkIndex:0,chunkBase64:encode(op.original)}).nextChunk !== 1) throw Error('chunk failed');
    const cmd = {...op.command('commit'),chunkIndex:1};
    const committed = (await call(cmd)).observation;
    const file = bytesSeen[index];
    if (file.name !== name || file.type !== 'image/png' || await hash(await file.arrayBuffer()) !== op.identity.assetSHA256) throw Error('wrong input bytes');
    if (!op.placeholder?.isConnected) throw Error('original change did not create the named placeholder');
    const pending = receipt(observe(op));
    let repeat = 'ACCEPTED';
    try { await call(cmd); } catch (error) { repeat=error.message; }
    return {opID:op.identity.operationID,inv:op.inv,target:op.target.documentID+':'+op.target.composerID,
      sha:op.identity.assetSHA256,commit:committed.state,pending,repeat};
  }

  async function publish(index) {
    const op = operations[index], actualFile = bytesSeen[index];
    let alias = op.alias, src = op.seedURL, otherFileSHA = null;
    if (mode === 'otherFileSameBytes') {
      const other = new File([actualFile], 'riftlet-' + crypto.randomUUID() + '.png',{type:'image/png'});
      alias = other.name.replace(/\.png$/,'.webp'); otherFileSHA = await hash(await other.arrayBuffer());
    }
    if (mode === 'similarName') alias = alias.replace('.webp','-copy.webp');
    if (mode === 'onePixel' || mode === 'oneAlpha') src = imageURL(index,mode);
    if (mode === 'wrongMIME') src = src.replace('data:image/png;', 'data:image/webp;');
    const card = op.oldCard ?? divShell(), surface = op.oldSurface ?? visual();
    const image = op.oldImage ?? document.createElement('img');
    image.src = src; image.alt=alias;
    await image.decode();
    const pixelProof=await comparePreview(actualFile,image);
    surface.append(image);
    const remove = op.oldRemove ?? removeFor(mode === 'mismatchedRemove' ? 'riftlet-'+crypto.randomUUID()+'.webp' : alias);
    card.replaceChildren(surface,remove);
    if (op.oldShell && card!==op.oldShell) op.oldShell.remove();
    if (mode === 'errorCard') card.setAttribute('data-state','error');
    if (mode === 'competingRemove') lane.append(removeFor(alias));
    if (mode === 'sameAliasFailure' || mode === 'otherAliasFailure')
      failedNeighbor(mode==='sameAliasFailure'?op.alias:'riftlet-'+crypto.randomUUID()+'.webp');
    if (mode === 'cardReplacedDuringDecode') decodeGate={file:actualFile,entered:defer(),resume:defer()};
    if (mode === 'foreignDraft') {
      const foreign = document.createElement('form'); foreign.append(document.createElement('textarea'),card); document.body.append(foreign);
    } else { op.placeholder.replaceWith(card); }
    let competing;
    if (mode === 'competing' || mode==='competingThenRemoved') {
      competing=card.cloneNode(true);lane.append(competing);
    }
    if (mode === 'editorReplaced') editor.replaceWith(editor.cloneNode(true));
    const atPublish=receipt(observe(op));
    if (mode === 'competingThenRemoved') competing.remove();
    let replacedDuringDecode=false;
    if (mode === 'cardReplacedDuringDecode') {
      try {
        await Promise.race([decodeGate.entered.promise,new Promise((_,reject)=>setTimeout(()=>reject(Error('production comparison did not reach the real decoder')),1500))]);
        card.replaceWith(card.cloneNode(true));replacedDuringDecode=true;
      } finally { decodeGate.resume.resolve(); }
    }
    if (mode === 'cardReplaced') card.replaceWith(card.cloneNode(true));
    if (mode === 'cardRevoked') card.remove();
    op.image=image;op.card=card;op.previewSHA=await hash(bits(src.split(',')[1]));
    return {atPublish,decoded:[image.naturalWidth,image.naturalHeight],dataMime:src.split(';')[0],
      originalSHA:op.identity.assetSHA256,previewSHA:op.previewSHA,otherFileSHA,pixelProof,replacedDuringDecode};
  }

  async function settle(index, duration) {
    const op = operations[index], end = performance.now()+duration;
    let result;
    do {
      result = receipt(observe(op));
      if (result.start) break;
      await new Promise(resolve=>setTimeout(resolve,20));
    } while(performance.now()<end);
    return result;
  }
  return {init(name,source,applicationID) {
    mode=name;
    if(mode==='cardReplacedDuringDecode'){
      const nativeDecode=window.createImageBitmap.bind(window);
      window.createImageBitmap=async (...args)=>{
        const bitmap=await nativeDecode(...args);
        if(decodeGate && args[0]===decodeGate.file){ decodeGate.entered.resolve(); await decodeGate.resume.promise; }
        return bitmap;
      };
    }
    const location = {href:'https://chatgpt.com/?temporary-chat=true'};
    const parts=source.split('\n  // RIFTLET_CLICK_PIN_END\n');
    if(parts.length!==2)throw Error('missing compact pin boundary');
    const compact=parts[0].split('\n').map(x=>x.replace(/^ +/,'')).join('\n')+"\n  return 'refused';\n}";
    const native={applicationID,sessionID:'owned-fixture',windowID:'1',tabID:'1'};
    const load=js=>new Function('location','return ('+js+')')(location);
    const full=load(source), pin=load(compact);
    call=cmd=>full(cmd,native); callPin=cmd=>pin(cmd,native);
    if (mode === 'nonemptySelection') {
      const editable = document.createElement('div');
      editable.contentEditable = 'true';
      editable.id = editor.id;
      editor.replaceWith(editable);
      editor = editable;
      editor.focus();
    } else {
      editor.focus();
      editor.setSelectionRange(2,8);
    }
    return true;
  }, prepare,commit,publish,settle,
  editorReady(expected) {
    return document.activeElement === editor && editor.isConnected && editor.innerText === expected;
  },
  selectionBefore(text, phrase) {
    selectionWitness = captureDraftSelection(editor, text, phrase);
    savedCards = Array.from(lane.children, card => ({
      card, members:[...card.querySelectorAll('*')], markup:card.outerHTML,
      images:Array.from(card.querySelectorAll('img'), image => ({
        image, source:image.currentSrc, width:image.naturalWidth, height:image.naturalHeight
      }))
    }));
    return selectionWitness.before;
  },
  selectionAfter() {
    return selectionWitness.after();
  },
  selectionContext(index) {
    const {target} = operations[index];
    const seed = operations[0];
    return {documentID:target.documentID, composerID:target.composerID, draftEpoch:target.draftGeneration,
      cardsExact:lane.childElementCount === savedCards.length + Number(Boolean(operations[index].card)) &&
        (!operations[index].card || operations[index].card.parentElement === lane),
      priorCards:savedCards.length, oldCardsIntact:savedCards.every(({card,members,markup,images}) => {
        const current = [...card.querySelectorAll('*')];
        return card.parentElement === lane && card.outerHTML === markup && members.length === current.length &&
          current.every((node, i) => node === members[i]) &&
          images.every(({image,source,width,height}) => image.complete && width > 0 && height > 0 &&
            image.currentSrc === source && image.naturalWidth === width && image.naturalHeight === height);
      }),
      original:call({action:'validate',target,requireLiveOriginal:true}).valid,
      seedPresent:seed.card.isConnected && lane.contains(seed.card) && seed.card.contains(seed.image),
      counts:{...counts}, sendClicks};
  },
  reverseSelectionForControl() {
    const selection = document.getSelection();
    selection.setBaseAndExtent(selection.focusNode, selection.focusOffset, selection.anchorNode, selection.anchorOffset);
  },
  replacePriorForControl() { prior.replaceWith(prior.cloneNode(true)); },
  summary() {
    return {counts:{...counts},inputIntervalMS:changeTimes.length===2 ? changeTimes[1]-changeTimes[0]:null,originalText:editor.value==='Prior selected draft',originalEditor:editor.isConnected,
      selection:[editor.selectionStart,editor.selectionEnd],priorAttachment:prior.isConnected && prior.parentElement===lane &&
        prior.dataset.fileName==='prior.png' && prior.textContent==='prior.png'};
  }};
})();
