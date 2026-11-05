'use strict';
// Supplemental real headless DOM tests. Synthetic composition events are not OS IME acceptance.
// The only model writes are reset() for case preparation. No product/App/browser profile access.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {pathToFileURL} = require('node:url');
const {execFileSync} = require('node:child_process');
const playwright = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const html = path.join(root, 'Riftlet-Settings-Prototype.html');
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const runID = process.env.RUN_ID || 'editing-' + new Date().toISOString().replace(/[:.]/g, '-');
assert.match(runID, /^[a-zA-Z0-9_-]+$/);
const output = path.join(root, 'evidence', runID);
assert(!fs.existsSync(output), 'Refusing to overwrite evidence: ' + runID);
assert(fs.existsSync(html), 'Build the revision-2 standalone HTML before running');
if (process.env.EXPECTED_HTML_SHA) assert.equal(hash(html), process.env.EXPECTED_HTML_SHA);
const protectedFiles = [
  {file:'../Riftlet-Settings-Prototype.html', expected:'aded9ed13cd5ff54c0f0a2172bbe78c720c2f03f41f16ed11a864a09ef45fabf'},
  {file:'../tests/browser-regression.cjs', expected:'7ede4386923b2f2aa3a7f6f4b3ff8718d627578330e966a6469991acb135fc83'}
];
for (const item of protectedFiles) assert.equal(hash(path.resolve(root, item.file)), item.expected, 'Inherited v1 must remain unchanged');
fs.mkdirSync(path.join(output, 'screenshots'), {recursive:true});
fs.copyFileSync(__filename, path.join(output, 'runner-snapshot.cjs'));
const report = {
  schemaVersion:1, runID, startedAt:new Date().toISOString(),
  scope:'Actual headless Chromium DOM actions on revision-2 standalone HTML, using synthetic prototype data. Composition events are simulated DOM events, not a real OS input method. Native AppKit, disk persistence, permissions, displays, user Chrome and uploads NOT_RUN.',
  sourceHEAD:execFileSync('git', ['rev-parse', 'HEAD'], {cwd:root, encoding:'utf8'}).trim(),
  prototype:{file:'Riftlet-Settings-Prototype.html', sha256:hash(html), bytes:fs.statSync(html).size},
  script:{file:'tests/editing-stability.cjs', sha256:hash(__filename)}, protectedFiles,
  runtime:{node:process.version, platform:process.platform, arch:process.arch,
    playwright:require(path.join(path.dirname(require.resolve(process.env.PLAYWRIGHT_MODULE || 'playwright')), 'package.json')).version},
  viewport:{width:1440, height:1100, deviceScaleFactor:1},
  cases:[], screenshots:[], pageErrors:[], externalRequests:[]
};
const cases = [];
const add = (id, title, steps, fn) => cases.push({id, title, steps, fn});
let page, browser, current;
const state = () => page.evaluate(() => window.RiftletDesign.getState());
const read = (label, value) => current.observations.push({label, value});
const eq = (actual, expected, message='supplemental DOM contract assertion') => assert.deepEqual(actual, expected, message);
const click = action => page.locator(`[data-action="${action}"]`).click();
const nav = name => page.locator(`[data-page="${name}"]`).first().click();
const view = name => page.locator(`[data-view="${name}"]`).click();
const setting = name => page.locator(`[data-setting="${name}"]`);
const failure = value => page.locator('#save-failure').setChecked(value);
const detail = async id => {
  const item = page.locator('#' + id);
  if (!await item.evaluate(el => el.open)) await item.locator('summary').first().click();
};
const display = async () => { await nav('display'); await detail('custom-display'); };
const archive = async () => { await nav('history'); await setting('archivePreset').selectOption('custom'); };

async function prepareRealToastTimer() {
  // A normal DOM action schedules the production prototype's existing six-second timer.
  // No mocked timers, direct render calls or arbitrary writes to the model.
  await nav('general'); await click('open-feedback');
  await page.locator('#feedback-draft').fill('合成测试：启动现有提示到期刷新');
  await click('save-feedback');
  assert((await state()).toast, 'The normal action must have scheduled a live toast');
  eq(await page.locator('.toast').count(), 1);
}

async function retainEditor(selector, text) {
  const locator = page.locator(selector);
  await locator.fill(text);
  if (text.length > 2) {
    await locator.press('Shift+ArrowLeft'); await locator.press('Shift+ArrowLeft');
  }
  const handle = await locator.elementHandle();
  assert(handle, 'Editor must exist');
  const before = await handle.evaluate(el => ({value:el.value, start:el.selectionStart,
    end:el.selectionEnd, direction:el.selectionDirection, focused:document.activeElement === el}));
  eq(before.value, text); eq(before.focused, true);
  if (text.length > 2) assert(before.start < before.end, 'Selection must be nonempty before the refresh');
  read('editor before', before);
  return {handle, selector, before};
}

async function assertSameEditor(editor) {
  const actual = await editor.handle.evaluate((el, selector) => ({connected:el.isConnected,
    same:document.querySelector(selector) === el, value:el.value, start:el.selectionStart,
    end:el.selectionEnd, direction:el.selectionDirection, focused:document.activeElement === el}), editor.selector);
  read('editor after', actual);
  eq(actual, {connected:true, same:true, ...editor.before}, 'Background refresh must preserve the original editable DOM node, raw text, selection and focus');
}

async function awaitRealToastExpiry(editor) {
  assert((await state()).toast, 'The refresh must happen after editing started, not before');
  await page.waitForFunction(() => window.RiftletDesign.getState().toast === null, null, {timeout:9000});
  eq(await page.locator('.toast').count(), 0, 'The background visual update must actually finish while editing');
  await assertSameEditor(editor);
}

async function compositionEvent(locator, type, data) {
  // Explicitly a synthetic DOM composition sequence; not native IME input or trusted events.
  await locator.evaluate((el, event) => el.dispatchEvent(new CompositionEvent(event.type,
    {bubbles:true, data:event.data})), {type, data});
}
async function composingEnter(locator) {
  await locator.dispatchEvent('keydown', {key:'Enter', code:'Enter', keyCode:229, which:229,
    isComposing:true, bubbles:true, cancelable:true});
}

const stopDomains = ['collection', 'visibility', 'entry'];
const desired = {collection:true, visibility:true, entry:false};
const confirmation = s => ({collection:s.persistedPaused, visibility:s.persistedHidden, entry:s.persistedEntryEnabled});
const effective = s => ({collection:s.paused, visibility:s.hidden, entry:s.preferences.entryEnabled});
function domain(s, key) {
  assert(s.persistence && s.persistence[key], 'Missing independent persistence domain: ' + key);
  return s.persistence[key];
}
function assertPending(s, names) {
  for (const key of names) {
    const d = domain(s, key);
    eq(d.status, 'unconfirmed', key + ' must still be unconfirmed');
    assert(d.error, key + ' must retain its own error');
    assert(d.pending !== null && d.pending !== undefined, key + ' must retain its requested target');
  }
}
function assertConfirmed(s, key) {
  const d = domain(s, key);
  eq(d.status, 'confirmed', key + ' must be confirmed only by a successful save');
  assert(d.error === null || d.error === undefined, key + ' must clear only its resolved error');
  assert(d.pending === null || d.pending === undefined, key + ' must clear its resolved pending intent');
  eq(confirmation(s)[key], desired[key], key + ' last confirmed value must now equal the stopped target');
}
function pendingSnapshot(s, names=stopDomains) {
  return Object.fromEntries(names.map(key => [key, structuredClone(domain(s, key))]));
}
async function createThreeStopFailures() {
  await failure(true); await nav('general');
  await setting('paused').check(); await setting('hidden').check();
  await nav('capture'); await setting('entryEnabled').uncheck();
  const s = await state();
  eq(effective(s), desired, 'All three stop directions must take effect immediately');
  eq(confirmation(s), {collection:false, visibility:false, entry:true});
  assertPending(s, stopDomains);
  read('three independent failed saves', pendingSnapshot(s));
  return s;
}
async function retry(key) {
  const buttons = page.locator(`[data-action="retry-save"][data-domain="${key}"]:visible`);
  assert(await buttons.count() > 0, 'A visible targeted retry must exist for ' + key);
  await buttons.first().click();
}
async function visitErrorActions() { await nav('general'); }

async function onePhysicalClick(action) {
  // One mouse down/up only, with a read-only DOM event observer. No locator retry after a lost click.
  const button = page.locator(`[data-action="${action}"]`);
  await button.scrollIntoViewIfNeeded();
  const box = await button.boundingBox(); assert(box);
  await page.evaluate(() => {
    window.__editingAuditClicks = [];
    if (!window.__editingAuditClickListener) {
      window.__editingAuditClickListener = event => window.__editingAuditClicks.push({type:event.type,
        action:event.target.closest('button')?.dataset.action || null, trusted:event.isTrusted});
      document.addEventListener('click', window.__editingAuditClickListener, true);
    }
  });
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  const events = await page.evaluate(() => window.__editingAuditClicks);
  read('single mouse click', events);
  eq(events.filter(event => event.action === action && event.trusted).length, 1, 'One normal click must reach the original action');
}

add('E1', '布局输入保留原节点、精确文本和选区', '正常保存反馈产生提示→编辑宽度96.250并选择末两位→等待真实提示到期', async () => {
  await prepareRealToastTimer(); await display();
  const editor = await retainEditor('[data-config="fitWidth"]', '96.250');
  await awaitRealToastExpiry(editor); eq((await state()).config.fitWidth, 72);
  eq((await state()).draft.fitWidth, 96.25);
});
add('E2', '未完成数字不被刷新归零或规范化', '宽度仅输入小数点→保持焦点等待真实提示到期→检查原节点/文本', async () => {
  await prepareRealToastTimer(); await display();
  const editor = await retainEditor('[data-config="fitWidth"]', '.');
  await awaitRealToastExpiry(editor); eq((await state()).config.fitWidth, 72);
  eq(await page.locator('[data-config="fitWidth"]').inputValue(), '.');
});
add('E3', '归档文本及选区跨后台刷新不变', '自定义归档输入2.750并选区→等待提示到期→尚未保存', async () => {
  await prepareRealToastTimer(); await archive();
  const editor = await retainEditor('[data-setting="archiveHours"]', '2.750');
  await awaitRealToastExpiry(editor); eq((await state()).archiveHours, 24);
});
add('E4', '反馈textarea跨后台刷新保持原节点', '正常保存产生提示→重开反馈→编辑合成文字并选区→等待提示到期', async () => {
  await prepareRealToastTimer(); await click('open-feedback');
  const editor = await retainEditor('#feedback-draft', '合成编辑稳定性：甲乙丙丁');
  await awaitRealToastExpiry(editor); eq((await state()).modal, 'feedback');
  eq((await state()).feedbackDraft, '合成编辑稳定性：甲乙丙丁');
});
for (const [id, kind, selector, text, expected] of [
  ['E5', '布局', '[data-config="fitWidth"]', '96.250', 96.25],
  ['E6', '归档', '[data-setting="archiveHours"]', '2.750', 2.75]
]) {
  add(id, kind + ' composition期间刷新和Enter不提前保存', '准备合法数字草稿→DOM compositionstart/update→组合态Enter→真实提示到期→compositionend→普通Enter', async () => {
    await prepareRealToastTimer(); if (id === 'E5') await display(); else await archive();
    const editor = await retainEditor(selector, text); const locator = page.locator(selector);
    await compositionEvent(locator, 'compositionstart', '');
    await compositionEvent(locator, 'compositionupdate', text);
    await composingEnter(locator);
    eq(id === 'E5' ? (await state()).config.fitWidth : (await state()).archiveHours, id === 'E5' ? 72 : 24, 'Composition Enter must not submit a valid draft');
    await awaitRealToastExpiry(editor);
    await compositionEvent(locator, 'compositionend', text);
    await assertSameEditor(editor);
    await locator.press('Enter');
    eq(id === 'E5' ? (await state()).config.fitWidth : (await state()).archiveHours, expected);
    read('composition scope', 'Synthetic CompositionEvent and composing KeyboardEvent only; real OS IME NOT_RUN');
  });
}
add('E7', '动画结束刷新不替换正在输入的节点', '选择磁力并预览→编辑按下时长→等待现有动画定时器结束', async () => {
  await nav('motion'); await detail('fine-motion');
  const originalDuration=(await state()).config.pressDuration;
  await page.locator('[data-setting="arrival"][value="magnet"]').check(); await click('preview-arrival');
  await page.waitForFunction(() => window.RiftletDesign.getState().motionPlaying === 'arrival');
  const editor = await retainEditor('[data-config="pressDuration"]', '125.750');
  eq((await state()).motionPlaying, 'arrival', 'Animation must still be pending when the editor snapshot is taken');
  await page.waitForFunction(() => window.RiftletDesign.getState().motionPlaying === null);
  await assertSameEditor(editor); eq((await state()).config.pressDuration, originalDuration);
});
add('E8', '减少动态不延长合法短时长', '实际保存40ms及0ms吞噬时长→开启减少动态→预览并读取计算后时长', async () => {
  await nav('motion'); await detail('fine-motion');
  for(const milliseconds of [40,0]) {
    await page.locator('[data-config="swallowDuration"]').fill(String(milliseconds));
    await page.locator('[data-config="swallowDuration"]').press('Enter');
    await page.locator('#reduce-motion').check(); const before=(await state()).config;
    await click('preview-swallow');
    await page.waitForFunction(()=>window.RiftletDesign.getState().motionPlaying==='swallow');
    const duration=await page.locator('.motion-image').evaluate(el=>parseFloat(getComputedStyle(el).animationDuration));
    eq(duration,Math.min(.08,milliseconds/1000),'Reduced motion must not lengthen an already shorter valid duration');
    eq((await state()).config,before);read('reduced duration',{milliseconds,seconds:duration});
  }
});

add('R1', '三停止域失败并存且无关成功不清错', '同时暂停/隐藏/关闭入口写失败→解除注入→外观与登录偏好成功', async () => {
  const before = await createThreeStopFailures(); await failure(false); await nav('general');
  await setting('appearance').selectOption('dark'); await setting('launchAtLogin').check();
  const after = await state(); eq(pendingSnapshot(after), pendingSnapshot(before));
  eq(effective(after), desired); eq(confirmation(after), confirmation(before)); eq(after.issue, 'write');
  eq(after.preferences.appearance, 'dark'); eq(after.preferences.launchAtLogin, true);
});
add('R2', '逐域同方向重试确实保存并依次清错', '三域失败→解除注入→依次重试collection/visibility/entry，每次检查确认值与剩余错误', async () => {
  await createThreeStopFailures(); await failure(false); await visitErrorActions();
  for (let i=0; i<stopDomains.length; i++) {
    const key=stopDomains[i]; const before=await state(); const remaining=stopDomains.slice(i+1);
    await retry(key); const after=await state();
    assertConfirmed(after, key); assertPending(after, remaining);
    eq(pendingSnapshot(after, remaining), pendingSnapshot(before, remaining), 'Retry must not erase another failed domain');
    eq(effective(after), desired, 'Retry must preserve the same stopped effective intent');
    read('confirmed ' + key, {confirmed:confirmation(after), persistence:after.persistence});
  }
  eq((await state()).issue, null);
  eq(await page.locator('[data-action="retry-save"]').count(), 0);
});
add('R3', '仍有故障时重试不伪造确认或反转目标', '三域失败→保持注入重试暂停→错误与确认值不变→解除注入再重试暂停', async () => {
  const before=await createThreeStopFailures(); await visitErrorActions(); await retry('collection');
  let after=await state(); assertPending(after, stopDomains); eq(confirmation(after), confirmation(before));
  eq(effective(after), desired); eq(domain(after, 'collection').pending, domain(before, 'collection').pending);
  await failure(false); await retry('collection'); after=await state();
  assertConfirmed(after, 'collection'); assertPending(after, ['visibility', 'entry']);
});
add('R4', '权限恢复不清三域保存错误', '先令文件夹未授权→三停止域失败→正常许可对话框恢复文件夹', async () => {
  await page.locator('#scenario').selectOption('attention');
  const before=await createThreeStopFailures(); await nav('permissions');
  await click('authorize-folder'); await click('permit-folder'); const after=await state();
  eq(after.permissions.folder, true); eq(after.issue, 'write');
  eq(pendingSnapshot(after), pendingSnapshot(before)); eq(confirmation(after), confirmation(before));
});
add('R5', '放弃失败布局只清本域不清三停止错误', '三域失败→宽度96保存失败→关闭并放弃→重新打开', async () => {
  const before=await createThreeStopFailures(); await display();
  await page.locator('[data-config="fitWidth"]').fill('96'); await click('apply-config');
  assertPending(await state(), ['layout']); await click('close-window'); await click('discard-changes');
  await click('reopen-settings'); const after=await state();
  eq(after.draft, after.config); assertPending(after, stopDomains);
  eq(pendingSnapshot(after), pendingSnapshot(before)); eq(after.issue, 'write');
  const layout=domain(after, 'layout'); assert(layout.error === null || layout.error === undefined);
  assert(layout.pending === null || layout.pending === undefined);
});
add('R6', '清一个错误后其余重试仍可见并可执行', '三域失败→先重试入口→页面切换→再重试隐藏及暂停', async () => {
  await createThreeStopFailures(); await failure(false); await visitErrorActions();
  await retry('entry'); assertConfirmed(await state(), 'entry');
  await nav('capture'); await nav('general');
  await retry('visibility'); assertConfirmed(await state(), 'visibility'); assertPending(await state(), ['collection']);
  await retry('collection'); eq((await state()).issue, null); eq(confirmation(await state()), desired);
});

add('A1', '归档首个物理单击即保存当前文本', '输入2.500后不预先失焦，只发送一次鼠标down/up到保存按钮', async () => {
  await archive(); await setting('archiveHours').fill('2.500');
  eq(await setting('archiveHours').evaluate(el => document.activeElement === el), true);
  await onePhysicalClick('save-archive'); eq((await state()).archiveHours, 2.5);
  eq((await state()).modal, null);
});
add('A2', '归档首个物理关闭单击立即询问', '输入2.500后不预先失焦，只发送一次鼠标down/up到关闭按钮', async () => {
  await archive(); await setting('archiveHours').fill('2.500');
  eq(await setting('archiveHours').evaluate(el => document.activeElement === el), true);
  await onePhysicalClick('close-window'); const s=await state();
  eq([s.closed, s.modal, s.archiveHours], [false, 'unsaved', 24]);
  eq(await page.evaluate(() => document.activeElement.dataset.action), 'cancel-modal');
});
add('K1', '历史sheet正反Tab包含两个下拉框', '从初始原图按钮反向经过时间/状态/关闭，再正向完整返回', async () => {
  await view('control'); await click('open-history');
  eq(await page.evaluate(() => document.activeElement.dataset.action), 'view-original');
  const steps=[['Shift+Tab','setting','historyRange'],['Shift+Tab','setting','historyFilter'],
    ['Shift+Tab','action','cancel-modal'],['Tab','setting','historyFilter'],
    ['Tab','setting','historyRange'],['Tab','action','view-original']];
  for (const [key, attribute, value] of steps) {
    await page.keyboard.press(key);
    const active=await page.evaluate(attribute => ({value:document.activeElement.dataset[attribute],
      inside:!!document.activeElement.closest('.dialog')}), attribute);
    eq(active, {value, inside:true}); read(key, active);
  }
});
add('K2', '反馈sheet焦点循环包括textarea与checkbox', '从实际初始焦点正反各循环一周，四个控件均可达且不逃出sheet', async () => {
  await nav('general'); await click('open-feedback');
  const active=()=>page.evaluate(()=>({key:document.activeElement.id||document.activeElement.dataset.setting||document.activeElement.dataset.action,
    inside:!!document.activeElement.closest('.dialog')}));
  const first=await active();
  const expected=['feedback-draft','feedbackDiagnostics','save-feedback','preview-feedback'].sort();
  for(const direction of ['Tab','Shift+Tab']) {
    const seen=[];
    for(let i=0;i<4;i++) {const item=await active();eq(item.inside,true);seen.push(item.key);await page.keyboard.press(direction);}
    eq([...new Set(seen)].sort(),expected);eq(await active(),first);read(direction,seen);
  }
  eq((await state()).modal, 'feedback');
});
const personalizedCompatibility={lineWidth:1.25,lineExtension:13.5,emptyTraceLength:37,
  screenPadding:23,arrivalDuration:.33,inwardDistance:2.75,reducedMotionDuration:.19};
const originalCompatibility={lineWidth:.5,lineExtension:8,emptyTraceLength:24,
  screenPadding:12,arrivalDuration:.22,inwardDistance:1.5,reducedMotionDuration:.08};
const compatibilityValues=config=>Object.fromEntries(Object.keys(personalizedCompatibility).map(key=>[key,config[key]]));
async function preparePersonalizedLegacy() {
  // Simulates decoding a legitimate old configuration only. It is case preparation,
  // not a direct state edit used to achieve a post-action assertion; no disk access.
  await page.evaluate(()=>window.RiftletDesign.reset({fixture:'legacyPersonalized',theme:'light'}));
  const s=await state();
  eq(compatibilityValues(s.config),personalizedCompatibility,'All seven fixture values must be the agreed non-default historical values');
  for(const key of Object.keys(personalizedCompatibility)) assert.notEqual(s.config[key],originalCompatibility[key]);
  eq([s.config.placement,s.config.placementSource,s.config.outerInset],[null,'legacy',14]);
  read('simulated legacy read',compatibilityValues(s.config));
  return s;
}
function assertCompatibility(s) {
  eq(compatibilityValues(s.config),personalizedCompatibility,'Applying settings must preserve all seven personalized compatibility values');
  eq(compatibilityValues(s.draft),personalizedCompatibility,'Draft/reset must preserve compatibility values too');
}
add('L1','七个非默认兼容字段跨实际应用保留','读取legacyPersonalized合成旧配置→改宽96和返回240ms→统一应用',async()=>{
  const before=await preparePersonalizedLegacy(); await display();
  await page.locator('[data-config="fitWidth"]').fill('96');
  await nav('motion'); await detail('fine-motion'); await page.locator('[data-config="returnDuration"]').fill('240');
  await click('apply-config'); const s=await state(); assertCompatibility(s);
  eq([s.config.fitWidth,s.config.returnDuration],[96,.24]);
  eq([s.config.placement,s.config.placementSource,s.config.outerInset],[null,'legacy',14]);
  eq(s.files,before.files); eq(s.attachments,before.attachments);
});
add('L2','恢复两页不会重置七个非默认兼容值','旧配置→选择屏幕/位置→修改并应用有效字段→两页分别恢复本页并应用',async()=>{
  await preparePersonalizedLegacy(); await display();
  await setting('display').selectOption('external'); await page.locator('button[data-placement="rightBottom"]').click();
  await page.locator('[data-config="fitWidth"]').fill('96'); await click('apply-config');
  await nav('motion'); await detail('fine-motion'); await page.locator('[data-config="returnDuration"]').fill('240'); await click('apply-config');
  const metadata=(await state()).config;
  for(const pageName of ['display','motion']) {
    await nav(pageName); await click('reset-page'); await click('confirm-reset');
    assertCompatibility(await state()); await click('apply-config'); const s=await state(); assertCompatibility(s);
    for(const key of ['preferredDisplayID','preferredDisplayUUID','placement','placementSource']) eq(s.config[key],metadata[key]);
    read('after reset/apply '+pageName,compatibilityValues(s.config));
  }
  eq([(await state()).config.fitWidth,(await state()).config.returnDuration],[72,.18]);
});
add('Z1', '无页面异常及外部请求', '检查全部独立用例运行期间的浏览器错误与网络拦截记录', async () => {
  eq(report.pageErrors, []); eq(report.externalRequests, []);
});

async function screenshot(name) {
  const file='screenshots/' + name + '.png';
  await page.screenshot({path:path.join(output, file), fullPage:true});
  report.screenshots.push({file, caseID:current.id, sha256:hash(path.join(output, file)),
    format:'raw Chromium PNG, no editing', viewport:report.viewport});
}
const writeJSON = (name, value) => fs.writeFileSync(path.join(output, name), JSON.stringify(value, null, 2) + '\n');
(async () => {
  try {
    browser=await playwright.chromium.launch({headless:true,
      ...(process.env.BROWSER_EXECUTABLE ? {executablePath:process.env.BROWSER_EXECUTABLE} : {})});
    report.runtime.browser=browser.version();
    if (process.env.BROWSER_EXECUTABLE) {
      report.runtime.browserExecutable=path.basename(process.env.BROWSER_EXECUTABLE);
      report.runtime.browserExecutableSHA256=hash(process.env.BROWSER_EXECUTABLE);
    }
    const context=await browser.newContext({viewport:{width:1440,height:1100},deviceScaleFactor:1,
      locale:'zh-CN',timezoneId:'Asia/Shanghai',colorScheme:'light',reducedMotion:'no-preference'});
    await context.route(/^https?:/, async route => {report.externalRequests.push(route.request().url());await route.abort();});
    page=await context.newPage(); page.setDefaultTimeout(5000);
    page.on('pageerror', error => report.pageErrors.push(String(error)));
    await page.goto(pathToFileURL(html).href); await page.waitForFunction(() => !!window.RiftletDesign);
    for (const test of cases) {
      current={id:test.id,title:test.title,steps:test.steps,status:'RUNNING',observations:[]};
      const started=Date.now();
      try {
        await page.evaluate(() => window.RiftletDesign.reset({fixture:'recommendation',theme:'light'}));
        await test.fn(); await screenshot(test.id); current.status='PASS';
      } catch (error) {
        current.status='FAIL'; current.assertion=error.message;
        current.stack=String(error.stack).split('\n').slice(0,8).join('\n').replaceAll(root,'<revision-2>');
        try {await screenshot(test.id+'-FAIL');} catch (shotError) {current.screenshotError=String(shotError);}
        writeJSON(test.id+'-failure.json',{...current,state:await state().catch(() => null),
          visibleText:await page.locator('body').innerText().catch(() => null)});
      }
      current.durationMs=Date.now()-started; report.cases.push(current);
      writeJSON('results.json', report); console.log(`${current.status} ${current.id} ${current.title}`);
    }
  } catch (error) {report.infrastructureError=String(error.stack).replaceAll(root,'<revision-2>');}
  finally {
    try {if (browser) await browser.close();} catch (error) {report.closeError=String(error);}
    report.finishedAt=new Date().toISOString(); report.expectedCaseCount=cases.length;
    report.summary={total:report.cases.length,pass:report.cases.filter(c=>c.status==='PASS').length,
      fail:report.cases.filter(c=>c.status==='FAIL').length};
    report.prototypeUnchanged=hash(html)===report.prototype.sha256;
    report.scriptUnchanged=hash(__filename)===report.script.sha256;
    report.protectedFilesUnchanged=protectedFiles.every(item=>hash(path.resolve(root,item.file))===item.expected);
    report.success=!report.infrastructureError&&!report.closeError&&report.summary.total===cases.length&&
      report.summary.fail===0&&report.prototypeUnchanged&&report.scriptUnchanged&&report.protectedFilesUnchanged&&
      report.pageErrors.length===0&&report.externalRequests.length===0;
    writeJSON('results.json',report); writeJSON('screenshots.json',report.screenshots);
    const md=['# 编辑稳定性与独立错误域补充回归','',`运行：\`${runID}\`。`,
      `结果：${report.summary.pass} PASS / ${report.summary.fail} FAIL / ${report.summary.total} 已执行（计划 ${cases.length}）。`,
      '',report.scope,'',`HTML SHA-256：\`${report.prototype.sha256}\`。`,
      `脚本 SHA-256：\`${report.script.sha256}\`。`,'',
      '| ID | 结果 | 目标 | 实际操作 |','| --- | --- | --- | --- |',
      ...report.cases.map(c=>`| ${c.id} | ${c.status} | ${c.title} | ${c.steps.replaceAll('|',' / ')} |`),'',
      ...report.cases.filter(c=>c.status==='FAIL').map(c=>`- ${c.id}：${c.assertion.replaceAll('\n',' ')}。[失败状态](${c.id}-failure.json) · [原始截图](screenshots/${c.id}-FAIL.png)`),'',
      `HTML保持：${report.prototypeUnchanged}；脚本保持：${report.scriptUnchanged}；v1原件保持：${report.protectedFilesUnchanged}。`,
      report.infrastructureError?'基础设施异常：'+report.infrastructureError:'所有已执行用例均记录终态；不以未执行项充当通过。',''];
    fs.writeFileSync(path.join(output,'RESULTS.md'),md.join('\n'));
    console.log(JSON.stringify({output,summary:report.summary,success:report.success}));
    process.exitCode=report.success?0:1;
  }
})();
