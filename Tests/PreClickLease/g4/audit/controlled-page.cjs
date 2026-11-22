'use strict';

// This renderer is exclusively served on a random local URL to a fresh headless
// profile. Only the site's response (progress/rejection/card) is a fixture.
// The unmodified shipping page program owns leases, Files, setters and STARTs.
module.exports = async function controlledPage(c, source) {
  function need(value, label) { if (!value) throw Error(label); }
  const hash = async data => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', data)),
    byte => byte.toString(16).padStart(2, '0')).join('');
  need(location.hostname === '127.0.0.1', 'Expected loopback');
  const route = 'https://chatgpt.com/?temporary-chat=true';
  const native = {applicationID:'com.microsoft.edgemac', sessionID:'synthetic-local-profile', windowID:'1', tabID:'1'};
  const run = new Function('location', 'return (' + source + ')')({href:route});
  const call = command => run(command, native);
  const form = document.querySelector('form'), editor = form.querySelector('[contenteditable]');
  const row = form.querySelector('.flex'), input = form.querySelector('input'), neighbour = row.firstElementChild;
  const decoded = Uint8Array.from(atob(c.png), b => b.charCodeAt(0));
  need(await hash(decoded) === c.sha, 'Original PNG mismatch');
  const counts = {setters:0, inputs:0, changes:0, submits:0, sends:0};
  const prop = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'files');
  Object.defineProperty(HTMLInputElement.prototype, 'files', {...prop, set(value) {
    need(this === input, 'Wrong picker'); counts.setters++; return prop.set.call(this, value);
  }});
  form.addEventListener('submit', e => { e.preventDefault(); counts.submits++; });
  form.querySelector('[type=submit]').addEventListener('click', () => counts.sends++);
  const files = [];
  input.addEventListener('input', () => { counts.inputs++; files.push(input.files[0]); });
  let oldShell, newImage;
  input.addEventListener('change', () => {
    counts.changes++;
    const file = input.files[0], shell = document.createElement('span'), surface = document.createElement('span');
    const remove = document.createElement('button');
    shell.className = 'group/composer-attachment'; surface.className = 'composer-attachment-surface';
    shell.style.display = surface.style.display = 'inline-block';
    remove.type = 'button'; remove.textContent = '×';
    remove.setAttribute('aria-label', '移除 ' + file.name); remove.style.cssText = 'opacity:0;pointer-events:none';
    if (counts.changes === 1) {
      surface.append(document.createElement('progress')); oldShell = shell;
    } else {
      newImage = document.createElement('img'); newImage.alt = file.name;
      newImage.width = newImage.height = 16; newImage.src = URL.createObjectURL(file); surface.append(newImage);
    }
    shell.append(surface, remove); row.append(shell);
  });
  function operation(record) {
    const pin = record.clickBindingID;
    need(call({action:'pinTarget', clickWitnessID:pin, address:route.split('?')[0]}) === 'bound', 'Local pin refused');
    const target = call({action:'captureTarget',clickWitnessID:pin});
    const identity = {operationID:record.id, assetID:c.asset, assetSHA256:c.sha, attempt:record.attempt, target};
    return {identity, target, invocationID:record.invocation, name:'riftlet-' + record.id + '.png'};
  }
  async function commit(op, recoverySource) {
    const command = {identity:op.identity, target:op.target, invocationID:op.invocationID};
    const begin = call({...command, action:'begin', uploadName:op.name, mediaType:'image/png', byteCount:decoded.length, recoverySource});
    if (recoverySource) need(begin.recoveryBoundInvocationID === recoverySource.invocationID, 'Wrong original invocation');
    let chunks = 0;
    for (let i = 0; i < decoded.length; i += 48*1024) {
      call({...command, action:'chunk', chunkIndex:chunks++, chunkBase64:btoa(String.fromCharCode(...decoded.subarray(i,i+48*1024)))});
    }
    return (await call({...command, action:'commit',chunkIndex:chunks})).observation;
  }
  const original = operation(c.old), first = await commit(original);
  const observe = op => call({action:'observe',identity:op.identity,target:op.target,invocationID:op.invocationID}).observation;
  need(first.state === 'inputTriggered' && !observe(original).uploadStart && oldShell.isConnected, 'Missing original progress witness');
  const next = operation(c.next);
  const predecessor = {identity:original.identity, invocationID:original.invocationID};
  const eligible = () => call({action:'validate', target:next.target, recoverySource:predecessor}).valid;
  need(!eligible(), 'Visible old member authorized a duplicate');
  oldShell.remove();
  await new Promise(resolve => setTimeout(resolve, 0));
  need(eligible(), 'Disappeared original progress member unavailable');
  await commit(next, predecessor);
  await newImage.decode();
  let observed;
  for (let i = 0; i < 150; i++) {
    observed = observe(next); if (observed.uploadStart) break;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  need(observed.uploadStart?.signal === 'attachmentAccepted' && !!observed.attachmentID, 'Missing local accepted START');
  need(files.length===2 && files[0]!==files[1] && files[0].name===original.name && files[1].name===next.name, 'Foreign File');
  for (const f of files) need(await hash(await f.arrayBuffer())===c.sha && f.size===decoded.length,'Wrong file bytes');
  need(row.firstElementChild===neighbour && editor.isConnected && counts.setters===2 && counts.inputs===2 &&
       counts.changes===2 && !counts.sends && !counts.submits,'Duplicate input, send, or replaced baseline');
  return {scope:'loopback product resource, fixture native route; original site absent', counts,
    originalOperationID:c.old.id, newOperationID:c.next.id, newInvocationID:c.next.invocation,
    localOriginalDocument:original.target.documentID, localNewDocument:next.target.documentID,
    localOriginalComposer:original.target.composerID, localNewComposer:next.target.composerID,
    historicalCardLifecycleSimulated:true, sameBytes:true, priorMemberPreserved:true,
    attachmentID:observed.attachmentID, evidenceID:observed.uploadStart.evidenceID};
};
