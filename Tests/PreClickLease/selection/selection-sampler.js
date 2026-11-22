// Uses fixed per-run identifiers encoded by the native route observer.
const claim=CLAIM_LITERAL;
const registry=globalThis.__riftletIndependentFileInput20261104;
const observerKey='__riftletSelectedDraftQA_'+claim.nonce;
const rawWatcher=globalThis['__riftletDraftQA_'+claim.marker.toUpperCase().replaceAll('-','')];
if (!rawWatcher || !registry || registry.root!==document.documentElement || !own ||
    !gen || !editor || !gen.form.contains(editor) || editor!==gen.editor ||
    registry.documentID!==claim.documentID || composerID!==claim.composerID) throw Error('ORIGINAL_DRAFT_REQUIRED');
const ops=registry.operations;
const seed=ops?.get(claim.operation) || ops?.get(claim.operation.toUpperCase()) || ops?.get(claim.operation.toLowerCase());
if (!seed || seed.start?.signal!=='attachmentAccepted' || seed.start.inputCount!==1 ||
    seed.start.evidenceID?.toLowerCase()!==claim.evidence.toLowerCase() ||
    seed.invocationID?.toLowerCase()!==claim.invocation.toLowerCase() ||
    seed.identity.target.documentID!==claim.documentID || seed.identity.target.composerID!==claim.composerID)
  throw Error('SEED_START_MISMATCH');
if (claim.mode==='init') {
  if(Object.hasOwn(globalThis,observerKey))throw Error('SELECTION_WATCH_EXISTS');
  const seedImages=images.slice();
  if(!seedImages.length || !seedImages.some(im=>im.alt.toLowerCase().startsWith('riftlet-'+claim.operation.toLowerCase()+'.')))throw Error('ORIGINAL_SEED_IMAGE_MISSING');
  function cardMembers(im) {
    const match=im.alt.toLowerCase().replace(/\.(png|webp)$/,'');
    for(let p=im.parentElement;p && p!==gen.form;p=p.parentElement) {
      const buttons=[...p.querySelectorAll('button[aria-label]')].filter(b=>/remove|移除|删除/i.test(b.getAttribute('aria-label')) &&
        b.getAttribute('aria-label').toLowerCase().includes(match));
      if(buttons.length===1 && p.querySelectorAll('img').length===1)return [p,buttons[0]];
    }
    throw Error('OLD_CARD_MEMBERS_NOT_ATTRIBUTABLE');
  }
  const saved=seedImages.map(im=>({im,alt:im.alt,src:im.currentSrc,w:im.naturalWidth,h:im.naturalHeight,pair:cardMembers(im)}));
  const epoch=gen.id;
  const liveProof=()=>{
    const raw=JSON.parse(rawWatcher.state());
    const g=registry.witnessGeneration;
    const retained=saved.every(({im,src,alt,w,h,pair:[card,button]})=>im.complete && w>0 && h>0 && im.naturalWidth===w && im.naturalHeight===h && im.currentSrc===src && im.alt===alt && im.isConnected && gen.form.contains(card) && card.contains(im) && card.contains(button) && button.getAttribute('aria-label').toLowerCase().includes(alt.toLowerCase().replace(/\.(png|webp)$/,'')));
    return {documentID:registry.documentID,composerID,draftEpoch:epoch,original:gen.form.contains(editor) && editor.isConnected &&
      g?.id===epoch && g?.editor===editor && g.form===gen.form && raw.originalDocument===true && raw.originalEditor===true,
      oldCardsIntact:retained && raw.allRememberedCardsPresent && raw.allRememberedNodesPreserved && raw.rememberedCards>=saved.length,
      priorCardCount:saved.length,sendClicks:raw.counts.sendButtonClicks,formSubmits:raw.counts.formSubmit};
  };
  const witness=observeExactQADraft(editor,gen.form,liveProof);
  witness.state();
  Object.defineProperty(globalThis,observerKey,{value:witness,configurable:true});
}
const w=globalThis[observerKey];
if(!w)throw Error('SELECTION_WATCH_LOST');
const selectionProbe = claim.mode==='before'?w.before():claim.mode==='after'?w.after():w.state();
