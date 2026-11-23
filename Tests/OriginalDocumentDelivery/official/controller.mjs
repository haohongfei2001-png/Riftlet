// Input comes from the documented browser inventory and, optionally, a real
// tab mention attached by the user to the current request. A page or a test
// cannot manufacture a mention to choose a different connected instance.
export function resolveController(inventory, family, familyHandleID, userTabMention) {
  if (!['chrome', 'edge'].includes(family)) throw Error('BROWSER_FAMILY_UNSUPPORTED');
  const members = inventory.filter(item => item.type === 'extension' && item.family === family);
  if (!userTabMention) {
    if (members.length !== 1) throw Error(members.length ? 'AMBIGUOUS_BROWSER_FAMILY' : 'BROWSER_UNAVAILABLE');
    if (members[0].id !== familyHandleID) throw Error('SELECTED_INSTANCE_CHANGED');
    return {browserID: members[0].id};
  }
  const uri = new URL(userTabMention);
  if (uri.protocol !== 'plugin:' || !['browser','chrome','chrome-internal','chrome-dev'].includes(uri.username) ||
      !['openai-bundled','openai-curated-remote'].includes(uri.hostname) || uri.password || uri.port || uri.hash ||
      !['', '/'].includes(uri.pathname) ||
      (uri.username !== 'browser' && family !== 'chrome')) throw Error('INVALID_TAB_MENTION');
  function one(key) {
    const values = uri.searchParams.getAll(key);
    if (values.length !== 1 || (!values[0] && key !== 'title')) throw Error('INVALID_TAB_MENTION');
    return values[0];
  }
  if (one('mention') !== 'tab-v1') throw Error('INVALID_TAB_MENTION');
  const instance = one('browserId');
  const matches = members.filter(item => item.metadata?.extensionInstanceId === instance);
  if (matches.length !== 1) throw Error('MENTIONED_INSTANCE_UNAVAILABLE');
  const address = one('url');
  if (!['about:blank', family+'://newtab/'].includes(address)) throw Error('DEDICATED_BLANK_REQUIRED');
  return {browserID: matches[0].id, reference: {providerTabId: one('tabId'), title: one('title'), url: address}};
}

export function matchReference(openTabs, reference) {
  const rows = openTabs.filter(item => item.providerTabId === reference.providerTabId);
  if (rows.length !== 1 || !rows[0].id || rows[0].title !== reference.title ||
      rows[0].url !== reference.url) throw Error('MENTIONED_TAB_CHANGED');
  return rows[0];
}

