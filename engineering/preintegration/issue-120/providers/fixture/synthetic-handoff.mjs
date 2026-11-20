// Controlled site ONLY. These label, lane, event and member contracts are
// properties of the local fixture, not Gemini's real file or evidence contract.
import {isOriginalObservation} from '../../contract/observation.mjs';
import {inspectLandingControls} from '../gemini-surface.mjs';

// Retain a bounded per-document identity fence even after a handle is closed.
// Only scalar IDs live here. The page epoch owns their lifetime, never a timer;
// neither pruning an old ID nor closing its original handle can reopen a write.
const operations = new Set(), invocations = new Set(), clicks = new Set();

export async function sha256(bytes) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)), n=>n.toString(16).padStart(2,'0')).join('');
}

export function pinSyntheticDraft(key) {
  if (location.protocol!=='http:' || location.hostname!=='127.0.0.1' || key.providerID!=='fixture-gemini-like' ||
      key.surface!=='ordinary-fixture' || key.mode!=='image-fixture' ||
      key.route!==location.pathname || !isOriginalObservation(key,key)) throw Error('fixture_origin_or_identity');
  if(operations.has(key.operation) || invocations.has(key.invocation) || clicks.has(key.clickGeneration) || operations.size>=256)
    throw Error('input_fenced');
  const surface=inspectLandingControls(document);
  if (surface.state!=='editor_and_upload_action') throw Error('original_draft_unavailable');
  const {editor,owner}=surface, form=owner.closest('form');
  const lanes=owner.querySelectorAll(':scope > [data-fixture-members]');
  function getPicker() {
    const labels=owner.querySelectorAll(':scope > label[data-fixture-linked-image-entry]');
    const el=labels.length===1 ? labels[0].control : null;
    return el instanceof HTMLInputElement && el.type==='file' && !el.matches(':disabled') &&
      el.form===form && owner.contains(el) ? el : null;
  }
  const input=getPicker(),lane=lanes[0];
  if (!form || !input || lanes.length!==1 || location.hash || location.search || form.dataset.fixtureMode!==key.mode)
    throw Error('owned_input_unavailable');
  const expected=Object.freeze({...key}), old=new WeakSet(lane.children), oldPreviews=new WeakSet(lane.querySelectorAll('img')), url=location.href;
  const name='riftlet-'+expected.operation+'.png', entry=navigation.currentEntry;
  if (!entry?.id) throw Error('navigation_epoch_unavailable');
  const retiredCandidates=new WeakSet();
  let spent=false, changeReturned=false, dead=false, accepted=null, retiredMember=false, reserved=false;
  const nodes=[editor,owner,lane,input,surface.action,form];
  function checkMutations(records) {
    for(const record of records) {
      if (record.type==='attributes') {
        if (record.target===form && record.attributeName==='data-fixture-mode') dead=true;
        if(record.attributeName==='data-fixture-name' && record.target.parentNode===lane) retiredCandidates.add(record.target);
        if (accepted && record.target===accepted && record.attributeName==='data-fixture-name') retiredMember=true;
      } else for(const lost of record.removedNodes) {
        if(record.target===lane) retiredCandidates.add(lost);
        if(nodes.some(node=>lost===node || lost.contains(node))) dead=true;
        if(accepted && (lost===accepted || lost.contains(accepted))) retiredMember=true;
      }
    }
  }
  const watcher=new MutationObserver(checkMutations);
  watcher.observe(document.documentElement,{subtree:true,childList:true,attributes:true,attributeFilter:['data-fixture-mode','data-fixture-name']});
  function original() {
    checkMutations(watcher.takeRecords());
    const current=inspectLandingControls(document);
    return !dead && location.href===url && navigation.currentEntry?.id===entry?.id && current.editor===editor &&
      current.owner===owner && current.action===surface.action && form.dataset.fixtureMode===expected.mode && lane.parentElement===owner;
  }
  function exactCard(card) {
    return card?.parentElement===lane && !old.has(card) && !retiredCandidates.has(card) && card.matches('article[data-fixture-name]') &&
      card.dataset.fixtureName===name && card.checkVisibility({opacityProperty:true,visibilityProperty:true}) &&
      !card.querySelector('article[data-fixture-name]');
  }
  const prefix='data:image/png;base64,';
  function originalPreview(card) {
    if(!exactCard(card) || card.querySelector('[data-fixture-failed]')) return null;
    const images=card.querySelectorAll('img'), image=images[0];
    if(images.length!==1 || oldPreviews.has(image) || image.parentElement!==card ||
       image.alt!==name || !image.complete || !image.naturalWidth || !image.naturalHeight ||
       !image.checkVisibility({opacityProperty:true,visibilityProperty:true}) ||
       image.closest('[hidden],[inert],[aria-hidden="true"]') || !image.getClientRects().length) return null;
    const src=image.getAttribute('src');
    // A responsive image can display different bytes than its fallback src.
    if(!src?.startsWith(prefix) || src.length>128*1024 || image.currentSrc!==src) return null;
    return {image,src};
  }
  async function observe(observed) {
    if(!isOriginalObservation(expected,observed) || !original() || retiredMember) return 'unavailable';
    if(!changeReturned) return 'unknown';
    if(accepted) {
      if(!exactCard(accepted)) return 'unavailable';
      const errors=accepted.querySelectorAll(':scope > output[data-fixture-failed]');
      if(errors.length===1 && errors[0].textContent===name && !accepted.querySelector('img') &&
        errors[0].checkVisibility({opacityProperty:true,visibilityProperty:true})) return 'original_card_failed';
      return 'previously_accepted';
    }
    const matches=[...lane.children].filter(exactCard);
    if(matches.length!==1) return 'unknown';
    const card=matches[0], preview=originalPreview(card);
    if(!preview) return 'unknown';
    // Verify both the loaded bytes and the stability of the observed card
    // while the browser's asynchronous digest is pending.
    let changed=false;
    const guard=new MutationObserver(()=>{changed=true;});
    guard.observe(card,{subtree:true,childList:true,attributes:true,characterData:true});
    try {
      const digest=await sha256(Uint8Array.from(atob(preview.src.slice(prefix.length)),c=>c.charCodeAt(0)));
      if(!original() || changed || guard.takeRecords().length || digest!==expected.payloadSHA256) return 'unknown';
      const current=originalPreview(card);
      if(current?.image!==preview.image || current.src!==preview.src || [...lane.children].filter(exactCard).length!==1)
        return 'unknown';
      if(accepted && accepted!==card) return 'unavailable';
      accepted=card;return 'accepted_into_draft';
    } catch {return 'unknown';}
    finally {guard.disconnect();}
  }
  async function commit(observed,file) {
    if(!isOriginalObservation(expected,observed) || !original() || getPicker()!==input) throw Error('target_changed');
    if(spent || reserved) throw Error('input_fenced');
    if(!(file instanceof File) || file.type!=='image/png' || file.name!==name || file.size===0 || file.size>65536) throw Error('wrong_fixture_file');
    // The reservation precedes the asynchronous digest, so concurrent commits
    // cannot both reach the native setter.
    reserved=true;
    const digest=await sha256(await file.arrayBuffer());
    if(digest!==expected.originalSHA256 || digest!==expected.payloadSHA256 || !original() || getPicker()!==input) throw Error('target_or_file_changed');
    const transfer=new DataTransfer();transfer.items.add(file);
    for(const member of lane.children) old.add(member);
    for(const previous of lane.querySelectorAll('img')) oldPreviews.add(previous);
    spent=true;
    Reflect.apply(Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'files').set,input,[transfer.files]);
    input.dispatchEvent(new Event('input',{bubbles:true,composed:true}));
    input.dispatchEvent(new Event('change',{bubbles:true}));
    changeReturned=true;
  }
  const handle=Object.freeze({commit, reader:Object.freeze({observe}), close(){dead=true;watcher.disconnect();}});
  operations.add(expected.operation);
  invocations.add(expected.invocation);
  clicks.add(expected.clickGeneration);
  return handle;
}
