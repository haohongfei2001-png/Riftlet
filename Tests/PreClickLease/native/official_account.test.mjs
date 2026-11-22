import assert from 'node:assert/strict';
import {test} from 'node:test';
import {accountReceipt} from './official_account.mjs';

function fixture({plan = false, manage = false, guest = false, duplicate = false,
                  hidden = false, changed = false, denied = false, personalAction, looseAction, disabled = false} = {}) {
  const profile = {role: 'button', name: 'Open profile menu', children: [{text: 'Pro'}]};
  if (plan) profile.children.push({role: 'status', name: 'Current plan', children: [{text: 'Pro', hidden}]});
  const tree = [profile];
  if (duplicate) tree.push(profile);
  if (guest) tree.push({role: 'link', name: 'Log in'});
  if (personalAction) tree.push({role:'navigation', name:'Account', children:[{role:'button', name:personalAction, disabled}]});
  if (looseAction) tree.push({role:'link', name:looseAction});
  if (manage) tree.push({role: 'navigation', name: 'Account', children: [{role: 'link', name: 'Manage subscription'}]});
  const flatten = list => list.flatMap(item => [item, ...flatten(item.children ?? [])]);
  const locator = items => ({
    count: async () => items.length,
    isVisible: async () => items.length === 1 && !items[0].hidden,
    isEnabled: async () => items.length === 1 && !items[0].disabled,
    nth: index => locator([items[index]]),
    getByRole: (role, {name}) => locator(flatten(items.flatMap(i => i.children ?? []))
      .filter(i => i.role === role && name.test(i.name))),
    getByText: text => locator(flatten(items.flatMap(i => i.children ?? [])).filter(i => i.text && text.test(i.text))),
  });
  const temporary = 'https://chatgpt.com/?temporary-chat=true';
  const tab = {id: 'controller-qa', url: async () => temporary, playwright: {
    getByRole(...args) {
      if (denied) throw new Error('Debugger unattached');
      return locator([{children: tree}]).getByRole(...args);
    }
  }};
  const claim = {controllerTabID: tab.id, challengeDocument: 'f63d59aa-a256-4d80-a9b0-48a26f46b03f',
    pid: 101, sessionID: 'signed-process-birth', tabID: 'native-qa', windowID: 'native-window', bundle: 'com.google.Chrome'};
  let reads = 0;
  return {tab, claim, family:'chrome', nativeScope: async () => ({...claim, originalSelection: !changed || reads++ === 0,
    originalSoleTab: true, exactTemporaryURL: true, systemForeground: true, dynamicSignature: true})};
}
test('read-only subscription evidence', async () => {
  for (const params of [{plan:true}, {manage:true}]) assert.equal((await accountReceipt(fixture(params))).menuActions, 0);
});
test('guest profile, standalone tier text, hidden and duplicate UI', async () => {
  for (const params of [{}, {plan:true, hidden:true}, {guest:true, plan:true}, {duplicate:true, plan:true}]) {
    await assert.rejects(accountReceipt(fixture(params)));
  }
});
test('original route changed or official controller denied', async () => {
  await assert.rejects(accountReceipt(fixture({plan:true, changed:true})), /INACTIVE/);
  await assert.rejects(accountReceipt(fixture({plan:true, denied:true})), /Debugger unattached/);
});

test('free account needs a visible enabled action scoped to the account navigation', async () => {
  for (const name of ['退出登录', 'Manage account']) {
    assert.equal((await accountReceipt(fixture({personalAction:name}))).observed, 'visibleAccountNavigationAction');
    for (const params of [{looseAction:name}, {personalAction:name, guest:true}, {personalAction:name, disabled:true}]) {
      await assert.rejects(accountReceipt(fixture(params)));
    }
  }
});
