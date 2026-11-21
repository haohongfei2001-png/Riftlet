import assert from 'node:assert/strict';
import {test} from 'node:test';
import {resolveController,matchReference} from './controller.mjs';
const normal = {type:'extension',family:'chrome',id:'normal',metadata:{extensionInstanceId:'first'}};
const second = {type:'extension',family:'chrome',id:'other',metadata:{extensionInstanceId:'second'}};
const fixture = 'plugin://browser@openai-bundled?mention=tab-v1&source=extension&browserId=first&tabId=opaque&title=&url=about%3Ablank';
test('a family with two clients cannot choose either on display name or enumeration order', () => {
  for (const clients of [[normal,second],[second,normal]]) {
    assert.throws(() => resolveController(clients,'chrome',clients[0].id), /AMBIGUOUS_BROWSER_FAMILY/);
  }
  assert.deepEqual(resolveController([normal],'chrome',normal.id),{browserID:normal.id});
  assert.throws(() => resolveController([normal],'chrome','other'), /SELECTED_INSTANCE_CHANGED/);
});
test('a user-provided reference must match the exact instance and original blank metadata', () => {
  const chosen = resolveController([second,normal],'chrome','other',fixture);
  assert.equal(chosen.browserID,'normal');
  const row = {id:'native-looking-reference',providerTabId:'opaque',title:'',url:'about:blank'};
  assert.equal(matchReference([row],chosen.reference),row);
  for (const rows of [[{...row,providerTabId:row.id}],[{...row,title:'changed'}],[row,row]]) {
    assert.throws(() => matchReference(rows,chosen.reference),/MENTIONED_TAB_CHANGED/);
  }
  assert.throws(() => resolveController([second,normal],'chrome','other',fixture.replace('about%3Ablank','https%3A%2F%2Fexample.com')),/DEDICATED_BLANK_REQUIRED/);
  assert.throws(() => resolveController([second,normal],'chrome','other',fixture.replace('browserId=first','browserId=other')),/MENTIONED_INSTANCE_UNAVAILABLE/);
});
