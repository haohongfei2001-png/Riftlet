'use strict';

const { randomBytes } = require('node:crypto');

// Only a Tab returned by new({newWindow:true}) can be used for this run.
// The trusted native observer must resolve that exact handle, independently
// sample the front process/window/tab, and retain the original page/editor.
const BUNDLES = new Set(['com.google.Chrome', 'com.microsoft.edgemac']);
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
  const url = new URL(route);
  return url.origin === 'https://chatgpt.com' && url.pathname === '/' &&
    !url.username && !url.password && !url.hash &&
    (url.search === '' || url.search === '?temporary-chat=true');
}

// read(tab) is read-only. The fallback when native focus or an exact page
// generation cannot be observed is to stop before a keyboard command.
async function createLockedDraft({ browser, bundle, read, locateNewChat, locateEditor }) {
  requireFact(BUNDLES.has(bundle), 'unsupported receiver');
  const tab = await browser.tabs.new({newWindow: true, windowName: 'Riftlet QA'});
  const tabID = tab.id, windowID = tab.windowId;
  requireFact(typeof tabID === 'string' && tabID && typeof windowID === 'string' && windowID,
    'browser supplied no dedicated window identity');
  let native, target, seedProof, invalid = false, keyboardUsed = false;
  const pending = new WeakSet();

  async function checked(requireDraft = true) {
    requireFact(!invalid, 'run retired');
    try {
      const s = await read(tab);
      requireFact(s.tabHandle === tabID && s.windowHandle === windowID && s.bundle === bundle &&
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
  native = Object.freeze({...await checked(false)});
  requireFact(['about:blank','chrome://newtab/','edge://newtab/'].includes(native.route),
    'backend did not create a blank test tab');
  await tab.goto('https://chatgpt.com/');
  const landed = await checked(false);
  requireFact(fresh(landed.route) && landed.signedIn === true && landed.messageCount === 0 &&
    landed.text === '' && landed.cards?.length === 0, 'dedicated window opened existing content');
  const control = await locateNewChat(tab);
  requireFact(await control.count() === 1 && await control.isVisible(), 'missing genuine New chat control');
  const previous = await checked(false);
  requireFact(same(landed, previous, DRAFT) && previous.text === '' && previous.messageCount === 0 &&
    previous.cards?.length === 0, 'new chat entry changed');
  await control.click({timeout:1500});
  target = Object.freeze({...await checked(false)});
  const first = await checked();
  requireFact(first.text === '' && first.cards?.length === 0, 'new chat was not empty');

  async function seed() {
    requireFact(!keyboardUsed, 'keyboard phase consumed');
    keyboardUsed = true; // A lost keyboard reply is never retried.
    const text = 'riftletqa' + randomBytes(8).toString('hex');
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
    pending.delete(before);
    return {outcome:'OBSERVED_NEW_CARD_ONLY', member:[...current.keys()][0], payload:input};
  }
  // When a preview appears but START is absent, record just its original-form
  // geometry. This never promotes a visible preview to product acceptance.
  async function edgePreviewShape(generatedName) {
    requireFact(bundle === 'com.microsoft.edgemac' &&
      /^riftlet-[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.(?:png|jpe?g)$/i.test(generatedName),
      'need exact QA operation filename');
    const before = await checked();
    requireFact(before.focusedOriginalEditor === true, 'no original focused editor');
    const shape = await tab.playwright.evaluate(name => {
      const editor = document.activeElement;
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
  return {tab,seed,beforeClick,afterClick,edgePreviewShape};
}

module.exports = {createLockedDraft};
