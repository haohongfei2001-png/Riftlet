'use strict';

const {beginDraft,withCleanup} = require('../internal/draft-workflow.cjs');

// No Browser imports or external keyboard actions. This adapter belongs to
// the in-memory fixture and is never registered with the live entry point.
function fixtureEntry(e) {
  const {s,tab,keys,options} = e;
  const adapter = {bind:async (_,identity) => {
    function match(target) {
      const pinned = ['bundle','sessionID','windowID','tabID','documentID','composerID',
        'draftGeneration','navigationID','route'];
      if (identity.claimedTabHandleID !== tab.id || identity.nativeWindowID !== s.frontWindowID ||
          identity.nativeTabID !== s.selectedTabID || s.frontSessionID !== target.sessionID ||
          pinned.some(field => target[field] !== s[field])) {
        throw Error('fixture rejected target at delivery');
      }
    }
    async function click(locate, target, action) {
      const locator = await locate(tab);
      if (await locator.count() !== 1 || !await locator.isVisible()) throw Error('missing unique visible control');
      e.beforeAction?.(action);
      match(target);
      return locator.click();
    }
    return {
      read:() => options.read(tab),
      openHome:native => {
        if (native.sessionID !== s.frontSessionID || native.windowID !== s.frontWindowID ||
            native.tabID !== s.selectedTabID || s.route !== 'about:blank') throw Error('original blank lost');
        return tab.goto('https://chatgpt.com/');
      },
      clickNewChat:target => click(options.locateNewChat,target,'newChat'),
      focusEditor:target => click(options.locateEditor,target,'focusEditor'),
      deliverKey:(target,before,key) => {
        e.beforeDelivery?.();
        e.beforeAction?.(key === 'shift+Left' ? 'select' : 'key');
        match(target);
        if (!s.focusedOriginalEditor || before.text !== s.text || before.selection !== s.selection ||
            s.cards.length !== 0) throw Error('fixture rejected editor at delivery');
        const chord = key === 'shift+Left' ? ['SHIFT','LEFT'] : [key];
        keys.push(chord);
        if (chord.length === 1) s.text += key;
        else s.selection = s.text.slice(-1);
        e.afterDelivery?.();
      },
      closeOriginal:target => { match(target); return tab.close(); },
      locateOriginalEditor:options.locateOriginalEditor && (target => options.locateOriginalEditor(tab,target)),
    };
  }};
  const start = () => beginDraft(options,adapter);
  return {start,withRun:async execute => withCleanup(await start(),execute)};
}

module.exports = {fixtureEntry};
