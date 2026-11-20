const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const sha256 = async bytes => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)),
  n => n.toString(16).padStart(2, '0')).join('');

function asDataURL(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

async function preview(file, mode) {
  if (mode === 'original') return file;
  const bitmap = await createImageBitmap(file);
  try {
    const canvas = document.createElement('canvas');
    const divisor = mode === 'scaled' ? 2 : 1;
    canvas.width = Math.floor(bitmap.width / divisor);
    canvas.height = Math.floor(bitmap.height / divisor);
    canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    return await new Promise((resolve, reject) => canvas.toBlob(
      blob => blob ? resolve(blob) : reject(Error('PNG encoding failed')), 'image/png'));
  } finally {
    bitmap.close();
  }
}

export async function run(mode, programSource, source, stage) {
  const form = document.querySelector('form'), editor = form.querySelector('[contenteditable]');
  const input = form.querySelector('input'), priorCard = form.querySelector('[data-file-name]');
  const text = editor.textContent, node = editor.firstChild;
  editor.focus();
  const selection = getSelection();
  selection.setBaseAndExtent(node, 2, node, 7);

  const route = 'https://chatgpt.com/?temporary-chat=true';
  const program = new Function('location', 'return (' + programSource + ')')({href:route});
  const native = {applicationID:'com.microsoft.edgemac', sessionID:'isolated-local-fixture', windowID:'1', tabID:'1'};
  const call = command => program(command, native);
  const counts = {setters:0, changes:0, sendActions:0, productFetches:0, productEncodes:0};
  const rejectNetwork = () => { counts.productFetches++; throw Error('unavailable'); };
  globalThis.fetch = rejectNetwork;
  XMLHttpRequest.prototype.send = rejectNetwork;
  const files = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'files');
  Object.defineProperty(HTMLInputElement.prototype, 'files', {...files, set(value) {
    counts.setters++;
    return Reflect.apply(files.set, this, [value]);
  }});
  const encode = OffscreenCanvas.prototype.convertToBlob;
  let productEncodeMs = 0;
  OffscreenCanvas.prototype.convertToBlob = async function (...args) {
    counts.productEncodes++;
    const start = performance.now();
    try { return await Reflect.apply(encode, this, args); }
    finally { productEncodeMs += Math.round(performance.now() - start); }
  };
  form.addEventListener('submit', event => { event.preventDefault(); counts.sendActions++; });
  form.querySelector('[type=submit]').addEventListener('click', () => counts.sendActions++);

  stage('bind');
  const pin = crypto.randomUUID(), id = crypto.randomUUID(), invocationID = crypto.randomUUID();
  if (call({action:'pinTarget', clickWitnessID:pin, address:route.split('?')[0]}) !== 'bound') throw Error('pin');
  const target = call({action:'captureTarget', clickWitnessID:pin});
  if (!target?.documentID) throw Error('target');
  const bytes = new Uint8Array(source), digest = await sha256(bytes);
  const identity = {operationID:id, assetID:crypto.randomUUID(), attempt:1, assetSHA256:digest, target};
  const command = action => ({action, identity, target, invocationID});
  const name = 'riftlet-' + id + '.png';
  stage('stage-original');
  call({...command('begin'), uploadName:name, mediaType:'image/png', byteCount:bytes.length});
  let chunks = 0;
  for (let offset = 0; offset < bytes.length; offset += 48 * 1024) {
    const chunk = bytes.subarray(offset, offset + 48 * 1024);
    call({...command('chunk'), chunkIndex:chunks++, chunkBase64:btoa(String.fromCharCode(...chunk))});
  }

  let rendered, commitAt;
  input.addEventListener('change', () => {
    counts.changes++;
    const file = input.files[0];
    rendered = (async () => {
      if (file.name !== name || (await sha256(await file.arrayBuffer())) !== digest) throw Error('file');
      const blob = await preview(file, mode), card = document.createElement('div');
      card.className = 'composer-attachment-surface';
      card.setAttribute('role', 'button');
      card.setAttribute('aria-haspopup', 'dialog');
      card.setAttribute('aria-label', name);
      const visual = document.createElement('span'), img = document.createElement('img'), remove = document.createElement('button');
      img.alt = name;
      remove.type = 'button';
      remove.setAttribute('aria-label', 'Remove ' + name);
      remove.style.opacity = '0';
      visual.append(img);
      card.append(visual, remove);
      form.append(card);
      img.src = await asDataURL(blob);
      await img.decode();
      const previewReadyMs = Math.round(performance.now() - commitAt);
      return {previewSHA256:await sha256(await blob.arrayBuffer()), previewBytes:blob.size,
        width:img.naturalWidth, height:img.naturalHeight, previewReadyMs};
    })();
    rendered.catch(() => {});
  });

  stage('commit');
  commitAt = performance.now();
  const receipt = await call({...command('commit'), chunkIndex:chunks});
  const commitMs = Math.round(performance.now() - commitAt);
  if (!rendered) throw Error('missing change');
  let observation = receipt.observation;
  stage('preview');
  const image = await rendered;
  stage('observe');
  const deadline = performance.now() + (mode === 'scaled' ? 2200 : 10000);
  let observedAt = null;
  do {
    observation = call({...command('observe'), preferStartReceipt:true}).observation;
    if (observation.state === 'uploadStarted') {
      observedAt = Math.round(performance.now() - commitAt);
      break;
    }
    await sleep(20);
  } while (performance.now() < deadline);
  return {mode, ...counts, ...image, commitMs, productEncodeMs, observedAt,
    observedThroughMs:Math.round(performance.now() - commitAt), state:observation.state,
    belongsToOriginalDraft:observation.belongsToOriginalDraft === true,
    originalDraftPreserved:editor.textContent === text && selection.anchorNode === node && selection.focusNode === node &&
      selection.anchorOffset === 2 && selection.focusOffset === 7 && form.contains(priorCard)};
}
