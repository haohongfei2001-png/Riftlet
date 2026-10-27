(() => {
 const o=globalThis.__riftletBoundReady,q=o?.query();
 if(!q?.snapshot.valid||q.binding.documentNonce!==__EXPECTED_DOCUMENT_NONCE__||q.snapshot.exactNamedCards!==1||!q.snapshot.hashVerified)return JSON.stringify({state:'UNKNOWN',reason:'BOUND_ATTACHMENT_UNAVAILABLE'});
 if(globalThis.__riftletAttachedPreview)return JSON.stringify({state:'EXISTING_RECEIPT_NO_RESTART'});
 const cs=[...document.querySelectorAll('[role=button][aria-label="Riftlet_READY_C.png"]')];
 if(cs.length!==1)return JSON.stringify({state:'UNKNOWN',reason:'DUPLICATE_CARD'});
 const c=cs[0],imgs=[...c.querySelectorAll('img')];
 if(imgs.length!==1)return JSON.stringify({state:'UNKNOWN',reason:'AMBIGUOUS_IMAGE'});
 const img=imgs[0],src=img.currentSrc||img.src;
 if(!/^data:image\/png;base64,/.test(src)||src.length>1000000||!img.complete)return JSON.stringify({state:'UNKNOWN',reason:'INLINE_PREVIEW_PROFILE_MISMATCH'});
 const bytes=Uint8Array.from(atob(src.slice(src.indexOf(',')+1)),x=>x.charCodeAt(0));
 globalThis.__riftletAttachedPreview={state:'PENDING'};
 crypto.subtle.digest('SHA-256',bytes).then(h=>{
  const after=o.query(),digest=[...new Uint8Array(h)].map(x=>x.toString(16).padStart(2,'0')).join('');
  globalThis.__riftletAttachedPreview={state:'VERIFIED',...q.binding,filename:'Riftlet_READY_C.png',cardNode:q.snapshot.cards[0].nodeId,previewBytes:bytes.length,previewSha256:digest,expectedSha256:q.fixture.sha256,previewBytesMatchSelectedFile:digest===q.fixture.sha256&&bytes.length===q.fixture.bytes,currentLeaseValid:after.snapshot.valid,sameCardAndSource:c.isConnected&&c.contains(img)&&img.src===src&&after.snapshot.cards?.[0]?.nodeId===q.snapshot.cards[0].nodeId,hashCompletedMonotonicMs:performance.now(),requestsMade:0,scope:'post-upload preview verification, not retroactive network confirmation'};
 }).catch(()=>{globalThis.__riftletAttachedPreview={state:'UNKNOWN',reason:'HASH_FAILED'};});
 return JSON.stringify({state:'PENDING',cardNode:q.snapshot.cards[0].nodeId,requestsMade:0});
})();
