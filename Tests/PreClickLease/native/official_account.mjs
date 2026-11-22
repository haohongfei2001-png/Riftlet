// Read-only admission. The caller supplies the already claimed official browser tab.
// nativeScope() may inspect native identity and selection only. A numeric tab handle
// by itself does not bind a controller tab to a native window.
const temporaryURL = 'https://chatgpt.com/?temporary-chat=true';
const profiles = /^(Open profile menu|打开个人资料菜单)$/i;
const signedOut = /^(Log in|Sign in|Sign up|登录|注册)$/i;
const tier = /^(?:ChatGPT\s+)?(?:Plus|Pro|Business|Enterprise)$/i;
const membershipActions = /^(Manage subscription|Manage plan|管理订阅|我的订阅)$/i;

function check(value, code) {
  if (!value) throw new Error(code);
}

async function visibleCount(locator, requireEnabled = false) {
  const count = await locator.count();
  let visible = 0;
  for (let i = 0; i < count; i++) {
    const candidate = locator.nth(i);
    if (await candidate.isVisible() && (!requireEnabled || await candidate.isEnabled())) visible++;
  }
  return visible;
}

function sameScope(current, claim, family) {
  const bundle = {chrome: 'com.google.Chrome', edge: 'com.microsoft.edgemac'}[family];
  check(bundle && current.bundle === bundle && claim.bundle === bundle, 'WRONG_BROWSER');
  for (const key of ['windowID', 'tabID', 'sessionID', 'pid']) {
    check(current[key] && current[key] === claim[key], 'ORIGINAL_NATIVE_ROUTE_CHANGED');
  }
  for (const key of ['exactTemporaryURL', 'originalSelection', 'originalSoleTab', 'systemForeground', 'dynamicSignature']) {
    check(current[key] === true, 'INACTIVE_OR_UNVERIFIED_QA_ROUTE');
  }
}

// The claim must come from the prior joint native/controller loopback challenge.
// UI strings are limited to the account control. Draft content and identity text
// never leave the site. A paid plan name alone is insufficient.
export async function accountReceipt({tab, family, claim, nativeScope}) {
  check(typeof claim.controllerTabID === 'string' && String(tab.id) === claim.controllerTabID &&
    typeof claim.challengeDocument === 'string' &&
    /^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/i.test(claim.challengeDocument),
    'NO_ORIGINAL_CONTROLLER_CLAIM');
  const before = await nativeScope();
  sameScope(before, claim, family);
  check(await tab.url() === temporaryURL, 'WRONG_TEMPORARY_PAGE');

  const page = tab.playwright;
  const account = page.getByRole('button', {name: profiles});
  check(await account.count() === 1 && await account.isVisible(), 'AMBIGUOUS_ACCOUNT_CONTROL');
  for (const role of ['link', 'button']) {
    check(await visibleCount(page.getByRole(role, {name: signedOut})) === 0, 'GUEST_OR_SIGN_IN_UI_PRESENT');
  }
  // Check semantic, site-owned account UI inside the unique profile control.
  // Do not use the account's user-editable display name or its initials as proof.
  const plan = account.getByRole('status', {name: /^(Current plan|Current subscription|当前套餐|当前订阅)$/i});
  const planCount = await visibleCount(plan.getByText(tier, {exact: true}));
  // When the site exposes a standalone subscription management link, accept it
  // only if it is inside the authenticated account navigation landmark.
  const accountNav = page.getByRole('navigation', {name: /^(Account|账户|帐户)$/i});
  let manageCount = 0;
  let personalAccountActions = 0;
  if (await accountNav.count() === 1 && await accountNav.isVisible()) {
    manageCount = await visibleCount(accountNav.getByRole('link', {name: membershipActions}), true);
    const accountAction = /^(Log out|Sign out|退出登录|登出|注销账户登录|Manage (?:my )?account|管理账户|管理帐户)$/i;
    for (const role of ['button', 'link', 'menuitem']) {
      personalAccountActions += await visibleCount(accountNav.getByRole(role, {name: accountAction}), true);
    }
  }
  let observed;
  if (personalAccountActions > 0) observed = 'visibleAccountNavigationAction';
  else if (manageCount === 1) observed = 'accountNavigationSubscriptionManagement';
  else if (planCount === 1) observed = 'profileExplicitCurrentPlan';
  check(observed, 'NO_VISIBLE_ACCOUNT_PROOF');

  const after = await nativeScope();
  sameScope(after, claim, family);
  check(await tab.url() === temporaryURL, 'ORIGINAL_URL_CHANGED');
  return {family, sessionID: after.sessionID, pid: after.pid, windowID: after.windowID,
    tabID: after.tabID, controllerTabID: claim.controllerTabID, challengeDocument: claim.challengeDocument,
    observed,
    observedAtMS: Date.now(), menuActions: 0};
}

// Called on the owned, newly created local challenge page before its one
// navigation to Temporary Chat. This links the opaque controller handle to
// the native window/tab using the independently generated document challenge.
export async function bindAccountTab({tab, family, localURL, nativeChallenge}) {
  const local = new URL(localURL);
  check(local.protocol === 'http:' && local.hostname === '127.0.0.1' && local.port &&
    !local.username && !local.password && !local.search && !local.hash &&
    /^\/[\da-f]{48}\/$/.test(local.pathname) && await tab.url() === localURL, 'WRONG_QA_CHALLENGE_URL');
  check(nativeChallenge.dynamicSignature === true && nativeChallenge.renderer?.sameDocument === true &&
    nativeChallenge.family === family && nativeChallenge.bundle === {chrome:'com.google.Chrome',edge:'com.microsoft.edgemac'}[family],
    'WRONG_NATIVE_CHALLENGE');
  const expected = nativeChallenge.doc;
  const doc = tab.playwright.locator('output#doc');
  check(await doc.count() === 1 && await doc.isVisible() && (await doc.innerText({timeoutMs:2000})).trim() === expected &&
    await tab.url() === localURL, 'CONTROLLER_AND_NATIVE_DOCUMENT_MISMATCH');
  return {family, controllerTabID:String(tab.id), challengeDocument:expected, bundle:nativeChallenge.bundle,
    sessionID:nativeChallenge.sessionID, pid:nativeChallenge.pid, tabID:nativeChallenge.tabID, windowID:nativeChallenge.windowID};
}
