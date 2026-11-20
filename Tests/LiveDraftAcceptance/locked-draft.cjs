'use strict';

const { createHash, randomBytes } = require('node:crypto');

const {openVerifiedWindow} = require('./browser-preflight.cjs');

const NATIVE = ['bundle', 'sessionID', 'windowID', 'tabID'];
const DRAFT = ['documentID', 'composerID', 'draftGeneration', 'navigationID', 'route'];
const hash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);

function requireFact(ok, reason) {
  if (!ok) throw new Error(reason);
}

function same(a, b, keys) {
  return keys.every(k => typeof a[k] === 'string' && a[k].length > 0 && a[k] === b[k]);
}

function fresh(route) {
  let url;
  try { url = new URL(route); } catch { return false; }
  return url.origin === 'https://chatgpt.com' && url.pathname === '/' &&
    !url.username && !url.password && !url.hash &&
    (url.search === '' || url.search === '?temporary-chat=true');
}

// read(tab) is read-only. The fallback when native focus or an exact page
// generation cannot be observed is to stop before a keyboard command.
async function createLockedDraft(options) {
  const {bundle, read, locateNewChat, locateEditor, locateOriginalEditor} = options;
  requireFact([read,locateNewChat,locateEditor].every(f => typeof f === 'function'), 'missing draft observer or locators');
  const {tab,windowID,guard} = await openVerifiedWindow(options);
  const tabID = tab.id;
  let native, target, seedProof, invalid = false, keyboardUsed = false;
  const pending = new WeakSet(), qaCards = new Map();
  let closeRequest, allowedText, landed;

  async function releaseOwned() {
    invalid = true;
    if (!landed && !target) {
      // Browser-internal new-tab pages cannot be scripted. Reconfirm the
      // owned blank using the management/native witnesses alone.
      try { await guard(true); } catch { return 'retainedUnverified'; }
      try { await tab.close(); return 'closed'; } catch { return 'closeUnconfirmed'; }
    }
    let current;
    try { await guard(); current = await read(tab); } catch { return 'retainedUnverified'; }
    if (!current || current.tabHandle !== tabID || current.windowHandle !== windowID || current.nativeHandleMatched !== true ||
        !same(current,native,NATIVE)) return 'retainedUnverified';
    const permitted = target || landed;
    const sameEmptyOrSeeded = permitted && same(current,permitted,DRAFT) && fresh(current.route) &&
      current.signedIn === true && current.messageCount === 0 &&
      (current.text === '' || (allowedText && allowedText === current.text)) && Array.isArray(current.cards) &&
      current.cards.every(c => qaCards.has(c.member) && qaCards.get(c.member) === c.payload);
    if (!sameEmptyOrSeeded) return 'retainedUnverified';
    try { await guard(); } catch { return 'retainedUnverified'; }
    try { await tab.close(); return 'closed'; } catch { return 'closeUnconfirmed'; }
  }

  // A lost close reply is not retried. Never switch to another tab or close a window.
  function close() { return closeRequest ||= releaseOwned(); }

  async function checked(requireDraft = true) {
    requireFact(!invalid, 'run retired');
    try {
      const front = await guard();
      const s = await read(tab);
      requireFact(same(s,front,NATIVE) && s.tabHandle === tabID && s.windowHandle === windowID && s.bundle === bundle &&
        s.frontSessionID === s.sessionID && s.frontWindowID === s.windowID &&
        s.selectedTabID === s.tabID && s.nativeHandleMatched === true &&
        same(s, native || s, NATIVE), 'focus or native destination changed');
      if (requireDraft) {
        requireFact(target && same(s, target, DRAFT) && fresh(s.route) && s.signedIn === true &&
          s.messageCount === 0 && s.editorCount === 1, 'original fresh signed-in composer lost');
      }
      return s;
    } catch (error) {
      invalid = true;
      throw error;
    }
  }

  // Freeze the process/window/tab while it is still the new blank page.
  try {
    native = Object.freeze({...await guard(true)});
    await tab.goto('https://chatgpt.com/');
    landed = await checked(false);
    requireFact(fresh(landed.route) && landed.signedIn === true && landed.messageCount === 0 &&
      landed.text === '' && landed.cards?.length === 0, 'dedicated window opened existing content');
    const control = await locateNewChat(tab);
    requireFact(await control.count() === 1 && await control.isVisible(), 'missing genuine New chat control');
    const previous = await checked(false);
    requireFact(same(landed, previous, DRAFT) && previous.text === '' && previous.messageCount === 0 &&
      previous.cards?.length === 0, 'new chat entry changed');
    await control.click({timeout:1500});
    const nextDraft = await checked(false);
    requireFact(!same(previous,nextDraft,DRAFT), 'New chat produced no observable fresh draft identity');
    target = Object.freeze({...nextDraft});
    const first = await checked();
    requireFact(first.text === '' && first.cards?.length === 0, 'new chat was not empty');
  } catch (error) {
    error.cleanup = await close();
    throw error;
  }

  async function seed() {
    requireFact(!keyboardUsed, 'keyboard phase consumed');
    keyboardUsed = true; // A lost keyboard reply is never retried.
    const text = 'riftletqa' + randomBytes(8).toString('hex');
    await checked();
    const editor = await locateEditor(tab);
    requireFact(await editor.count() === 1 && await editor.isVisible(), 'editor not unique');
    await checked();
    await editor.click();
    try {
      // Key actions remain scoped to the original browser tab. Never issue
      // a global keyboard event, press Enter, paste, or assign DOM text.
      let prefix = '';
      for (const key of text) {
        const before = await checked();
        requireFact(before.focusedOriginalEditor === true && before.text === prefix &&
          before.cards.length === 0, 'keyboard origin or text changed');
        await tab.cua.keypress({keys:[key]});
        prefix += key;
        allowedText = prefix;
      }
      const complete = await checked();
      requireFact(complete.text === text && complete.focusedOriginalEditor === true, 'keyboard text missing');
      await tab.cua.keypress({keys:['SHIFT','LEFT']});
      const selected = await checked();
      requireFact(selected.text === text && selected.selection === text.slice(-1) &&
        selected.focusedOriginalEditor === true, 'real selection missing');
      seedProof = Object.freeze({text,selection:selected.selection});
      return seedProof;
    } catch (error) {
      invalid = true;
      throw error;
    }
  }

  // Keep old card identity, operation and image bytes distinct. A previously
  // existing card with new contents is not proof of a newly attached file.
  function cards(snapshot) {
    requireFact(Array.isArray(snapshot.cards) && snapshot.cards.every(c =>
      hash(c.member) && hash(c.payload)) && new Set(snapshot.cards.map(c => c.member)).size === snapshot.cards.length,
      'unproven or duplicate original card');
    return new Map(snapshot.cards.map(c => [c.member, c.payload]));
  }

  async function beforeClick(requiredPriorCard) {
    requireFact(seedProof, 'keyboard seed not observed');
    const s = await checked();
    const prior = cards(s);
    requireFact(s.text === seedProof.text && s.selection === seedProof.selection &&
      hash(requiredPriorCard?.member) && prior.get(requiredPriorCard.member) === requiredPriorCard.payload,
      'prior selection or original test attachment missing');
    const receipt = Object.freeze({text:s.text,selection:s.selection,prior:Object.freeze(
      [...prior].map(entry => Object.freeze(entry)))});
    qaCards.set(requiredPriorCard.member, requiredPriorCard.payload);
    pending.add(receipt);
    return receipt;
  }

  async function afterClick(before, input) {
    requireFact(pending.has(before), 'not an outstanding original click observation');
    const s = await checked();
    requireFact(s.text === before.text && s.selection === before.selection, 'text or selection changed');
    const current = cards(s);
    for (const [member,payload] of before.prior) {
      requireFact(current.get(member) === payload, 'prior card changed');
      current.delete(member);
    }
    requireFact(current.size === 1 && hash(input) && [...current.values()][0] === input,
      'original composer has no single new matching card');
    for (const [member,payload] of current) qaCards.set(member,payload);
    pending.delete(before);
    return {outcome:'OBSERVED_NEW_CARD_ONLY', member:[...current.keys()][0], payload:input};
  }
  // When a preview appears but START is absent, record just its original-form
  // geometry. This never promotes a visible preview to product acceptance.
  async function edgePreviewShape(generatedName) {
    requireFact(bundle === 'com.microsoft.edgemac' &&
      /^riftlet-[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.(?:png|jpe?g)$/i.test(generatedName),
      'need exact QA operation filename');
    await checked();
    requireFact(typeof locateOriginalEditor === 'function', 'no original editor locator');
    const pinned = await locateOriginalEditor(tab,target);
    requireFact(pinned && same(pinned,target,DRAFT) && same(pinned,native,NATIVE) &&
      pinned.tabHandle === tabID && pinned.windowHandle === windowID &&
      await pinned.locator.count() === 1 && await pinned.locator.isVisible(), 'original editor unavailable');
    await checked();
    const shape = await pinned.locator.evaluate((editor,name) => {
      if (!editor?.matches('[contenteditable="true"],textarea') || !editor.closest('form')) return null;
      const form = editor.closest('form');
      const candidates = [...form.querySelectorAll('img[alt]')].filter(i => i.alt.includes(name) &&
        i.getBoundingClientRect().width > 0 && i.getBoundingClientRect().height > 0);
      if (candidates.length !== 1) return {matchingPreviewCount:candidates.length};
      const image = candidates[0], src = image.getAttribute('src') || '';
      const kind = src.startsWith('blob:') ? 'blob' : src.startsWith('data:image/png;') ? 'inline-png' :
        src.startsWith('data:image/jpeg;') ? 'inline-jpeg' : /^https?:/.test(src) ? 'remote' : 'other';
      const ancestors = [];
      for (let e = image.parentElement; e && e !== form && ancestors.length < 8; e = e.parentElement) {
        const buttons = [...e.children].filter(c => c.matches('button,[role="button"]'));
        ancestors.push({tag:e.tagName,children:e.children.length,images:e.querySelectorAll('img').length,
          named:e.getAttribute('aria-label') === name, directButtons:buttons.length,
          namedRemove:buttons.some(b => ['aria-label','title'].some(k => {
            const v=b.getAttribute(k)||''; return v.includes(name) && /remove|移除|删除/i.test(v);
          })), opensDialog:e.getAttribute('aria-haspopup') === 'dialog'});
      }
      return {matchingPreviewCount:1,exactAlt:image.alt === name,sourceKind:kind,
        currentEqualsAttribute:image.currentSrc === src,hasSrcset:image.hasAttribute('srcset'),
        complete:image.complete,pixelWidth:image.naturalWidth,pixelHeight:image.naturalHeight,ancestors};
    },generatedName);
    await checked();
    requireFact(shape !== null, 'original editor/form unavailable');
    return shape;
  }
  async function edgePreviewSample(generatedName) {
    const shape = await edgePreviewShape(generatedName);
    // Match the signed App's independent receipt without exposing window,
    // process, tab or draft identifiers in the exported timeline.
    const identity = [target.bundle, target.sessionID, target.windowID, target.tabID,
      target.documentID, target.composerID, target.draftGeneration];
    const lockedDraftSHA256 = createHash('sha256').update(JSON.stringify(identity)).digest('hex');
    return {shape,lockedDraftSHA256};
  }
  return {tab,seed,beforeClick,afterClick,edgePreviewShape,edgePreviewSample,close};
}

async function withLockedDraft(options, execute) {
  const run = await createLockedDraft(options);
  let result, failure, cleanup;
  try { result = await execute(run); }
  catch (error) { failure = error; }
  finally { cleanup = await run.close(); }
  if (failure) { failure.cleanup = cleanup; throw failure; }
  return {result,cleanup};
}

module.exports = {createLockedDraft,withLockedDraft};
