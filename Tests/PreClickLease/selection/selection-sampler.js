// The read context holds the original website watcher. The signed App owns a separate product registry.
const selectionProbe = (() => {
  const claim = CLAIM_LITERAL;
  const owner = globalThis['__riftletDraftQA_'+claim.marker.toUpperCase().replaceAll('-','')];
  if (!owner || typeof owner.state !== 'function') throw Error('ORIGINAL_DRAFT_WATCHER_UNAVAILABLE');
  const key='__riftletSelectedDraftQA_'+claim.nonce;
  function currentEditor() {
    const hosts=[...document.querySelectorAll('#prompt-textarea,[contenteditable],[role="textbox"],textarea')].filter(e=>
      e.getClientRects().length && e.checkVisibility({checkOpacity:true,checkVisibilityCSS:true}) &&
      (e.isContentEditable || e.tagName==='TEXTAREA') && !e.closest('article,nav,aside,[role="search"],[data-message-author-role]'));
    const leaves=hosts.filter(a=>!hosts.some(b=>b!==a && a.contains(b)));
    const named=leaves.filter(e=>e.id==='prompt-textarea');
    return named.length===1 ? named[0] : leaves.length===1 ? leaves[0] : null;
  }
  if (claim.mode==='init') {
    if(Object.hasOwn(globalThis,key))throw Error('SELECTION_WATCH_EXISTS');
    const initial=JSON.parse(owner.state());
    // The mounted watcher independently requires currentEditor() === its original editor.
    const original=currentEditor();
    const scope=original?.closest('[data-composer-placement],[data-chatgpt-composer],[data-testid="composer"]') || original?.closest('form');
    if(!initial.originalDocument || !initial.originalEditor || !original || !original.isContentEditable ||
       !scope || !scope.isConnected || !scope.contains(original))throw Error('ORIGINAL_EDITOR_OR_DOCUMENT_MISSING');
    const images=[...scope.querySelectorAll('img')].filter(img=>/^riftlet-[a-f0-9-]{36}\.(png|webp)$/i.test(img.alt));
    const names=images.map(im=>im.alt.toLowerCase()).sort();
    if(names.length!==initial.rememberedCards || !initial.allRememberedNodesPreserved || !initial.allRememberedCardsPresent ||
       new Set(names).size!==names.length || !names.some(n=>n.startsWith('riftlet-'+claim.operation.toLowerCase()+'.')))throw Error('ORIGINAL_SEED_CARD_MISSING');
    function members(im) {
      const stem=im.alt.toLowerCase().replace(/\.(png|webp)$/,'');
      for(let p=im.parentElement;p && p!==scope;p=p.parentElement){
        const buttons=[...p.querySelectorAll('button[aria-label]')].filter(b=>/remove|移除|删除/i.test(b.getAttribute('aria-label')) &&
          b.getAttribute('aria-label').toLowerCase().includes(stem));
        if(buttons.length===1 && p.querySelectorAll('img').length===1)return {card:p,button:buttons[0]};
      }
      throw Error('OLD_CARD_MEMBERS_NOT_ATTRIBUTABLE');
    }
    const saved=images.map(im=>({im,alt:im.alt,src:im.currentSrc,w:im.naturalWidth,h:im.naturalHeight,...members(im)}));
    const witnessEpoch=crypto.randomUUID(), entry=navigation.currentEntry.id, origin=performance.timeOrigin;
    const liveProof=()=>{
      const raw=JSON.parse(owner.state());
      const retained=saved.every(({im,src,alt,w,h,card,button})=>im.complete && w>0 && h>0 && im.naturalWidth===w &&
        im.naturalHeight===h && im.currentSrc===src && im.alt===alt && im.isConnected && scope.contains(card) &&
        card.contains(im) && card.contains(button) && button.getAttribute('aria-label')?.toLowerCase().includes(alt.toLowerCase().replace(/\.(png|webp)$/,'')));
      return {entryID:entry,timeOrigin:origin,witnessEpoch,original:raw.originalDocument && raw.originalEditor &&
        navigation.currentEntry?.id===entry && performance.timeOrigin===origin && currentEditor()===original && scope.contains(original),
        oldCardsIntact:retained && raw.allRememberedCardsPresent && raw.allRememberedNodesPreserved && raw.rememberedCards>=saved.length,
        priorCardCount:saved.length,sendClicks:raw.counts.sendButtonClicks,formSubmits:raw.counts.formSubmit};
    };
    const w=observeExactQADraft(original,scope,liveProof);
    w.state();Object.defineProperty(globalThis,key,{value:w,configurable:true});
  }
  const w=globalThis[key];if(!w)throw Error('SELECTION_WATCH_LOST');
  return claim.mode==='before'?w.before():claim.mode==='after'?w.after():w.state();
})();
