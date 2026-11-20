'use strict';

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
async function connectedBrowser({browsers,browserID,bundle,readNative}) {
  try {
    const family = families.get(bundle);
    check(family && typeof browsers?.list === 'function', 'BROWSER_DISCOVERY_UNAVAILABLE');
    const matches = (await browsers.list()).filter(item => item.type === 'extension' &&
      item.family === family && (!browserID || item.id === browserID));
    check(matches.length === 1, 'EXACT_EXTENSION_BROWSER_UNAVAILABLE');
    const browser = await browsers.get(matches[0].id);
    check(browser?.browserId === matches[0].id, 'BROWSER_HANDLE_MISMATCH');
    check((await browser.capabilities.list()).some(c => c.id === 'management'), 'WINDOW_MANAGEMENT_UNAVAILABLE');
    const management = await browser.capabilities.get('management');
    check(typeof management.windows?.getAll === 'function' && typeof management.windows.create === 'function' &&
      typeof management.tabs?.query === 'function' && typeof browser.tabs?.list === 'function' &&
      typeof browser.user?.openTabs === 'function' && typeof browser.user.claimTab === 'function',
      'WINDOW_OR_TAB_API_UNAVAILABLE');
    const windowIDs = new Set((await management.windows.getAll({populate:false})).map(w => w.id));
    check([...windowIDs].every(numeric), 'WINDOW_IDENTITIES_UNAVAILABLE');
    // Keep IDs only. Existing drafts are never claimed or examined.
    const prior = new Set((await browser.tabs.list()).map(t => t.id));
    const oldProviderIDs = new Set((await browser.user.openTabs()).map(t => t.providerTabId).filter(Boolean));
    check(typeof readNative === 'function', 'NATIVE_FRONT_OBSERVER_UNAVAILABLE');
    return {status:'AVAILABLE',browser,management,windowIDs,prior,oldProviderIDs};
  } catch (error) { throw publicFailure(error,'BROWSER_HEALTH_UNAVAILABLE'); }
}

async function openVerifiedWindow(options) {
  const {browser,management,windowIDs,prior,oldProviderIDs} = await connectedBrowser(options);
  let created, providerID, tab, sessionID, creationAttempted = false, claimed = false;
  async function selected(requireBlank = false) {
    const rows = await management.tabs.query({windowId:created.id});
    const current = rows.length === 1 && rows[0];
    check(current && current.windowId === created.id && numeric(current.id) && current.active === true &&
      current.incognito === false && (!providerID || String(current.id) === providerID) &&
      (!requireBlank || blank(current.url)), 'QA_WINDOW_OR_TAB_CHANGED');
    check(blank(current.url) || current.url === 'https://chatgpt.com/' ||
      current.url === 'https://chatgpt.com/?temporary-chat=true', 'QA_ROUTE_CHANGED');
    return current;
  }
  async function nativeFront() {
    const native = await options.readNative(options.bundle);
    const prefix = families.get(options.bundle) + '-kernel-v1:';
    check(native && native.bundle === options.bundle && typeof native.sessionID === 'string' &&
      native.sessionID.startsWith(prefix) && /^[1-9]\d*:[1-9]\d*:\d{1,6}$/.test(native.sessionID.slice(prefix.length)) &&
      native.windowID === String(created.id) && native.tabID === providerID &&
      (!sessionID || sessionID === native.sessionID), 'NATIVE_FOREGROUND_IDENTITY_MISMATCH');
    return native;
  }
  async function guard(requireBlank = false) {
    await selected(requireBlank);
    const refs = (await browser.tabs.list()).filter(t => t.id === tab.id);
    check(refs.length === 1 && refs[0].providerTabId === providerID, 'CONTROLLED_TAB_IDENTITY_LOST');
    return nativeFront();
  }
  try {
    creationAttempted = true;
    created = await management.windows.create();
    check(created && numeric(created.id) && !windowIDs.has(created.id) && created.type === 'normal' &&
      created.incognito === false, 'FRESH_NORMAL_WINDOW_UNPROVEN');
    const row = await selected(true);
    providerID = String(row.id);
    check(!oldProviderIDs.has(providerID), 'TAB_PREEXISTED');
    sessionID = (await nativeFront()).sessionID;
    // Pass the actual fresh openTabs() object, so the extension also checks its
    // URL/title snapshot on claim. Never print or persist the enumeration.
    const refs = (await browser.user.openTabs()).filter(t => t.providerTabId === providerID && t.url === row.url);
    check(refs.length === 1 && !prior.has(refs[0].id), 'UNIQUE_BLANK_TAB_CLAIM_UNAVAILABLE');
    await selected(true);
    await nativeFront();
    tab = await browser.user.claimTab(refs[0]);
    check(typeof tab?.id === 'string' && tab.id && !prior.has(tab.id), 'NEW_CONTROLLED_TAB_UNPROVEN');
    await guard(true);
    claimed = true;
    check(typeof tab.cua?.keypress === 'function' && typeof tab.goto === 'function' &&
      typeof tab.close === 'function', 'DIRECTED_TAB_API_UNAVAILABLE');
    return {tab,windowID:String(created.id),guard};
  } catch (cause) {
    const error = publicFailure(cause,'QA_WINDOW_OR_CLAIM_REPLY_UNKNOWN',creationAttempted);
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
