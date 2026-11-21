'use strict';

const {randomUUID} = require('node:crypto');

const families = new Map([['com.google.Chrome','chrome'], ['com.microsoft.edgemac','edge']]);
const blank = url => ['about:blank','chrome://newtab/','edge://newtab/'].includes(url);
const numeric = value => Number.isSafeInteger(value) && value > 0;

class PreflightError extends Error {
  constructor(code, status = 'BLOCKED') { super(code); this.status = status; this.code = code; }
}
function check(condition, code) { if (!condition) throw new PreflightError(code); }
function publicFailure(error, code, uncertain = false) {
  if (error instanceof PreflightError) return error;
  const rpc = String(error?.message || '').includes('Trusted RPC service is not configured: browser');
  return new PreflightError(rpc ? 'BROWSER_RPC_UNCONFIGURED' : code, uncertain ? 'UNKNOWN' : 'BLOCKED');
}

// Only read advertised identity and capabilities until a real normal-profile
// extension client and an independent native observer are both available.
async function connectedBrowser({browsers,browser,browserID,bundle,readNative,connectionError}) {
  try {
    // Selection and the mandatory complete documentation read belong to the
    // official client's bootstrap. Reuse the selected handle for this family.
    if (connectionError) throw connectionError;
    const family = families.get(bundle);
    check(family && typeof browsers?.list === 'function', 'BROWSER_DISCOVERY_UNAVAILABLE');
    check(typeof browser?.browserId === 'string' && browser.browserId.length, 'DOCUMENTED_BROWSER_HANDLE_REQUIRED');
    const matches = (await browsers.list()).filter(item => item.id === browser.browserId &&
      item.type === 'extension' && item.family === family && (!browserID || item.id === browserID));
    check(matches.length === 1, 'EXACT_EXTENSION_BROWSER_UNAVAILABLE');
    check((await browser.capabilities.list()).some(c => c.id === 'management'), 'WINDOW_MANAGEMENT_UNAVAILABLE');
    const management = await browser.capabilities.get('management');
    check(typeof management.windows?.getAll === 'function' && typeof management.windows.create === 'function' &&
      typeof management.tabs?.query === 'function' && typeof management.tabs.group === 'function' &&
      typeof management.tabGroups?.update === 'function' && typeof management.tabGroups.query === 'function' &&
      typeof browser.tabs?.list === 'function' &&
      typeof browser.user?.openTabs === 'function' && typeof browser.user.claimTab === 'function',
      'WINDOW_OR_TAB_API_UNAVAILABLE');
    check(typeof readNative === 'function', 'NATIVE_FRONT_OBSERVER_UNAVAILABLE');
    return {browser,management};
  } catch (error) { throw publicFailure(error,'BROWSER_HEALTH_UNAVAILABLE'); }
}

async function openVerifiedWindow(options) {
  const {browser,management} = await connectedBrowser(options);
  let created, nativeTab, groupID, tab, target, sessionID, creationAttempted = false, claimed = false;
  const groupTitle = 'Riftlet QA ' + randomUUID();
  async function selected(requireBlank = false) {
    const rows = await management.tabs.query({windowId:created.id});
    const current = rows.length === 1 && rows[0];
    check(current && current.windowId === created.id && numeric(current.id) && current.active === true &&
      current.incognito === false && (nativeTab === undefined || current.id === nativeTab) &&
      (groupID === undefined || current.groupId === groupID) &&
      (!requireBlank || blank(current.url)), 'QA_WINDOW_OR_TAB_CHANGED');
    check(!current.pendingUrl || current.pendingUrl === current.url, 'QA_NAVIGATION_PENDING');
    check(blank(current.url) || current.url === 'https://chatgpt.com/' ||
      current.url === 'https://chatgpt.com/?temporary-chat=true', 'QA_ROUTE_CHANGED');
    return current;
  }
  async function nativeFront() {
    const native = await options.readNative(options.bundle);
    const prefix = families.get(options.bundle) + '-kernel-v1:';
    // The Apple Event helper serializes the same native Chromium IDs as
    // decimal strings. Never apply this serialization to a Browser API ID.
    check(native && native.bundle === options.bundle && typeof native.sessionID === 'string' &&
      native.sessionID.startsWith(prefix) && /^[1-9]\d*:[1-9]\d*:\d{1,6}$/.test(native.sessionID.slice(prefix.length)) &&
      native.windowID === created.id.toString(10) && native.tabID === nativeTab.toString(10) &&
      (!sessionID || sessionID === native.sessionID), 'NATIVE_FOREGROUND_IDENTITY_MISMATCH');
    return native;
  }
  async function verifyGroup() {
    const groups = await management.tabGroups.query({windowId:created.id});
    check(groups.length === 1 && groups[0].id === groupID && groups[0].windowId === created.id &&
      groups[0].title === groupTitle, 'QA_GROUP_CHANGED');
  }
  async function verifyClaim(requireBlank) {
    const row = await selected(requireBlank);
    await verifyGroup();
    // tabs.list() describes controlled tabs. Match both sides of the claim
    // in their own namespaces. Do not read titles or URLs of unrelated tabs.
    const matches = (await browser.tabs.list()).filter(t =>
      t.id === target.claimedTabHandleID || t.providerTabId === target.providerTabID);
    check(tab.id === target.claimedTabHandleID && matches.length === 1 &&
      matches[0].id === target.claimedTabHandleID && matches[0].providerTabId === target.providerTabID &&
      matches[0].url === row.url, 'CONTROLLED_TAB_IDENTITY_LOST');
    return nativeFront();
  }
  let retired = false;
  async function guard(requireBlank = false) {
    check(!retired, 'CONTROLLED_TAB_RETIRED');
    try {
      const native = await verifyClaim(requireBlank);
      check(!retired, 'CONTROLLED_TAB_RETIRED');
      return native;
    } catch (error) {
      retired = true;
      throw error;
    }
  }
  try {
    const windowIDs = new Set((await management.windows.getAll({populate:false})).map(w => w.id));
    check([...windowIDs].every(numeric), 'WINDOW_IDENTITIES_UNAVAILABLE');
    const prior = new Set(), oldProviderIDs = new Set();
    for (const t of await browser.user.openTabs()) {
      prior.add(t.id);
      if (t.providerTabId) oldProviderIDs.add(t.providerTabId);
    }
    const oldHandles = new Set((await browser.tabs.list()).map(t => t.id));
    creationAttempted = true;
    created = await management.windows.create();
    check(created && numeric(created.id) && !windowIDs.has(created.id) && (created.type === undefined || created.type === 'normal') &&
      (created.incognito === undefined || created.incognito === false), 'FRESH_NORMAL_WINDOW_UNPROVEN');
    const row = await selected(true);
    nativeTab = row.id;
    if (created.tabs) check(created.tabs.length === 1 && created.tabs[0].id === nativeTab, 'CREATED_TAB_MISMATCH');
    const native = await nativeFront();
    sessionID = native.sessionID;

    // Both openTabs().id and providerTabId are opaque in the public API.
    // A named group on this one fresh, native-verified blank is an explicit
    // cross-API witness even if the visible reference ID looks numeric.
    groupID = await management.tabs.group({tabIds:[nativeTab],createProperties:{windowId:created.id}});
    check(Number.isSafeInteger(groupID) && groupID >= 0, 'QA_GROUP_UNAVAILABLE');
    await selected(true);
    await nativeFront();
    await management.tabGroups.update(groupID,{title:groupTitle});
    await verifyGroup();
    const refs = await browser.user.openTabs();
    const members = refs.filter(t => t.tabGroup === groupTitle);
    check(members.length === 1, 'UNIQUE_BLANK_TAB_CLAIM_UNAVAILABLE');
    const ref = members[0];
    const browserReferenceID = ref.id, providerTabID = ref.providerTabId;
    check(typeof browserReferenceID === 'string' && browserReferenceID.length > 0 &&
      typeof providerTabID === 'string' && providerTabID.length > 0 &&
      refs.filter(t => t.id === browserReferenceID || t.providerTabId === providerTabID).length === 1 &&
      !prior.has(browserReferenceID) && !oldProviderIDs.has(providerTabID) &&
      ref.url === row.url, 'UNIQUE_BLANK_TAB_CLAIM_UNAVAILABLE');
    await selected(true);
    await nativeFront();
    tab = await browser.user.claimTab(ref);
    check(typeof tab?.id === 'string' && tab.id && !oldHandles.has(tab.id), 'NEW_CONTROLLED_TAB_UNPROVEN');
    target = Object.freeze({nativeWindowID:native.windowID,nativeTabID:native.tabID,
      browserReferenceID,providerTabID,claimedTabHandleID:tab.id});
    await guard(true);
    claimed = true;
    let dispatch;
    if (typeof tab.ax?.pressKey === 'function') {
      dispatch = key => tab.ax.pressKey(null, key);
    } else if (typeof tab.cua?.keypress === 'function') {
      dispatch = key => tab.cua.keypress({keys: key === 'shift+Left' ? ['SHIFT', 'LEFT'] : [key]});
    }
    check(dispatch && typeof tab.goto === 'function' && typeof tab.close === 'function',
      'DIRECTED_TAB_API_UNAVAILABLE');
    async function pressKey(key) {
      await guard();
      return dispatch(key);
    }
    return {tab,windowID:target.nativeWindowID,identity:target,guard,pressKey};
  } catch (cause) {
    const error = publicFailure(cause,creationAttempted ? 'QA_WINDOW_OR_CLAIM_REPLY_UNKNOWN' : 'BROWSER_HEALTH_UNAVAILABLE',creationAttempted);
    error.cleanup = creationAttempted ? 'retainedUnverified' : 'none';
    if (claimed) {
      try {
        await guard(true);
        if (typeof tab.close === 'function') {
          error.cleanup = 'closeUnconfirmed';
          await tab.close();
          error.cleanup = 'closed';
        }
      } catch { /* Preserve uncertainty. Never reissue the close. */ }
    }
    throw error;
  }
}

async function browserHealth(options) {
  try {
    await connectedBrowser(options);
    return {status:'AVAILABLE',windowCreation:'NOT_RUN',keyboardDelivery:'NOT_RUN'};
  } catch (error) {
    return {status:error.status,code:error.code};
  }
}

module.exports = {browserHealth,openVerifiedWindow};
