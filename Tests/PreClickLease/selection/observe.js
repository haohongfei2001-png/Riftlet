'use strict';
// Lexical helper for an already admitted, original dedicated QA page watcher.
// Call once at the seed START. The caller supplies product-derived identity
// and independent original-card/counter proofs. Never move focus or edit DOM.
function observeExactQADraft(editor, form, productProof) {
  const doc = editor.ownerDocument, root = doc.documentElement;
  const entry = navigation.currentEntry?.id, opened = performance.timeOrigin;
  const text = 'Riftlet QA: preserve this original draft while attaching images.';
  const phrase = 'preserve this original draft';
  let initial, witness, baseline;
  function state() {
    const proof = productProof();
    const observed = {documentID:proof.documentID, composerID:proof.composerID, draftEpoch:proof.draftEpoch};
    if (!entry || !Object.values(observed).every(x=>typeof x==='string' && x.length>0) ||
        !proof.original || (initial && Object.keys(initial).some(k=>initial[k]!==observed[k])) ||
        doc !== document || doc.documentElement!==root || performance.timeOrigin!==opened ||
        navigation.currentEntry?.id!==entry || location.href!=='https://chatgpt.com/?temporary-chat=true' ||
        !editor.isConnected || !editor.isContentEditable ||
        !form.contains(editor) || !proof.oldCardsIntact || !Number.isInteger(proof.priorCardCount) ||
        proof.priorCardCount<1 || proof.sendClicks!==0 || proof.formSubmits!==0) throw Error('ORIGINAL_QA_DRAFT_OR_CARD_CHANGED');
    initial ||= observed;
    const rect=editor.getBoundingClientRect(), vp=doc.defaultView.visualViewport;
    const geometry={x:rect.x,y:rect.y,width:rect.width,height:rect.height,
      vw:doc.defaultView.innerWidth,vh:doc.defaultView.innerHeight,
      screenLeft:doc.defaultView.screenX,screenTop:doc.defaultView.screenY,
      outerWidth:doc.defaultView.outerWidth,outerHeight:doc.defaultView.outerHeight};
    const usable=!vp || (vp.scale===1 && vp.offsetLeft===0 && vp.offsetTop===0);
    const hits=usable && rect.width>6 && rect.height>4 && [0.32,0.68].every(t=>{
      const n=doc.elementFromPoint(rect.x+t*rect.width,rect.y+0.5*rect.height);
      return n && editor.contains(n) && n.closest('[contenteditable=true]')===editor;
    });
    if (!hits) throw Error('ORIGINAL_EDITOR_VIEWPORT_GEOMETRY_UNAVAILABLE');
    return {...observed, geometry, original:true, oldCardsIntact:true, priorCardCount:proof.priorCardCount,
      sendClicks:0, formSubmits:0, activeOriginal:doc.activeElement===editor && doc.hasFocus(),
      textState:editor.innerText===text && editor.textContent===text?'expected':
        (editor.innerText==='' || editor.innerText==='\n') && editor.textContent===''?'empty':'other'};
  }
  return Object.freeze({state, before(){
    const s=state();
    if (witness || !s.activeOriginal || s.textState!=='expected') throw Error('ORIGINAL_SELECTED_DRAFT_REQUIRED_ONCE');
    const w=captureDraftSelection(editor,text,phrase);
    if (w.before.start!==12 || w.before.end!==40) throw Error('UNEXPECTED_ORIGINAL_SELECTION');
    witness=w;baseline=s;
    return {...s,...w.before};
  }, after(){
    const s=state();
    if (!witness || s.textState!=='expected' || s.priorCardCount!==baseline.priorCardCount) throw Error('ORIGINAL_SELECTION_BASELINE_MISSING');
    return {...s,...witness.after()};
  }});
}
