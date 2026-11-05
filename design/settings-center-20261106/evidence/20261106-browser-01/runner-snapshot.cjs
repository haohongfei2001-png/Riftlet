'use strict';
// Real headless-browser DOM regression of the inherited, immutable HTML.
// No AppKit, production config, installed App, user Chrome, or upload access.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {pathToFileURL} = require('node:url');
const {execFileSync} = require('node:child_process');
const playwright = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const html = path.join(root, 'Riftlet-Settings-Prototype.html');
const inheritedSHA = 'e1a7286d7eb14ff47686804718f61a2515a8fd12';
const expectedHTML = 'aded9ed13cd5ff54c0f0a2172bbe78c720c2f03f41f16ed11a864a09ef45fabf';
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const hashFile = file => digest(fs.readFileSync(file));
const runID = process.env.RUN_ID || new Date().toISOString().replace(/[:.]/g, '-');
if (!/^[a-zA-Z0-9_-]+$/.test(runID)) throw Error('RUN_ID must be a simple new directory name');
const output = path.join(root, 'evidence', runID);
if (fs.existsSync(output)) throw Error('Refusing to overwrite a previous evidence run: ' + runID);
fs.mkdirSync(path.join(output, 'screenshots'), {recursive:true});
assert.equal(hashFile(html), expectedHTML, 'Run only against the reviewed inherited HTML');
const report = {
  schemaVersion:1, runID, startedAt:new Date().toISOString(),
  scope:'Real headless Chromium DOM interactions on saved standalone HTML; all data synthetic. Native AppKit, OS permissions, real displays, persistence and upload NOT_RUN.',
  inheritedCommit:inheritedSHA, baseMain:'b61fc46cf931bdbd14deec1b47d077e92db61e16',
  prototype:{file:'Riftlet-Settings-Prototype.html',sha256:hashFile(html),bytes:fs.statSync(html).size},
  script:{file:'tests/browser-regression.cjs',sha256:hashFile(__filename)},
  runtime:{node:process.version,platform:process.platform,arch:process.arch,playwright:require(path.join(path.dirname(require.resolve(process.env.PLAYWRIGHT_MODULE || 'playwright')), 'package.json')).version},
  viewport:{width:1440,height:1100,deviceScaleFactor:1}, cases:[], screenshots:[], pageErrors:[], externalRequests:[]
};
const baselineFiles = execFileSync('git',['ls-tree','-r','--name-only',inheritedSHA,'--','design/settings-center-20261106'],{cwd:root,encoding:'utf8'}).trim().split('\n').filter(Boolean);
const repo = execFileSync('git',['rev-parse','--show-toplevel'],{cwd:root,encoding:'utf8'}).trim();
report.inheritedFiles = baselineFiles.map(file => ({file,sha256:hashFile(path.join(repo,file))}));
const cases=[];
const add=(id,title,steps,fn,shot=false)=>cases.push({id,title,steps,fn,shot});
let page, browser, context, current;
const state=()=>page.evaluate(()=>window.RiftletDesign.getState());
const click=async action=>{await page.locator(`[data-action="${action}"]`).click();};
const nav=async name=>{await page.locator(`[data-page="${name}"]`).first().click();};
const view=async name=>{await page.locator(`[data-view="${name}"]`).click();};
const set=async(key,value)=>page.locator(`[data-setting="${key}"]`).selectOption(value);
const toggle=async(key,value)=>page.locator(`[data-setting="${key}"]`).setChecked(value);
const failure=async(value=true)=>page.locator('#save-failure').setChecked(value);
const reset=async fixture=>page.evaluate(f=>window.RiftletDesign.reset({fixture:f||'recommendation',theme:'light'}),fixture);
const detail=async id=>{const d=page.locator('#'+id);if(!await d.evaluate(e=>e.open))await d.locator('summary').first().click();};
const fill=async(key,value)=>page.locator(`[data-config="${key}"]`).fill(String(value));
const body=()=>page.locator('body').innerText();
const eq=(a,b,message)=>assert.deepEqual(a,b,message);
async function shot(name){
  const file=`screenshots/${name}.png`;
  await page.screenshot({path:path.join(output,file),fullPage:true});
  const s=await state();
  report.screenshots.push({file,sha256:hashFile(path.join(output,file)),caseID:current?.id,
    page:s.page,view:s.view,theme:s.theme,fixture:s.fixture,modal:s.modal,
    paused:s.paused,hidden:s.hidden,issue:s.issue,onboardingStep:s.onboardingStep,
    viewport:report.viewport,format:'raw Chromium PNG, no image editing'});
}
async function display(){await nav('display');await detail('custom-display');}
async function motion(){await nav('motion');await detail('fine-motion');}
async function archive(){await nav('history');await set('archivePreset','custom');}
async function writeError(key){await nav('general');await failure();await toggle(key,true);}
async function clearQueue(){await view('control');await click('clear-queue');await click('confirm-clear');}

const pages=[['general','通用'],['display','位置与显示'],['capture','截图'],['motion','动效'],['history','历史与存储'],['permissions','权限与帮助']];
for(const [i,[key,title]] of pages.entries()){
  add(`P${i+1}`,`浅色六页：${title}`,`点击侧栏 ${title}；核对唯一页面、标题和选择标记`,async()=>{
    await nav(key);eq(await page.locator(`[data-page-content="${key}"]`).count(),1);
    eq(await page.locator('h1').innerText(),title);eq(await page.locator(`[data-page="${key}"]`).first().getAttribute('aria-current'),'page');
  },true);
  add(`D${i+1}`,`深色六页：${title}`,`点击深色切换，再点击 ${title}；核对主题、可见内容及原始截图`,async()=>{
    await click('toggle-theme');await nav(key);eq((await state()).theme,'dark');
    eq(await page.locator('#riftlet-design').getAttribute('data-theme'),'dark');
    eq(await page.locator('h1').innerText(),title);
  },true);
}
for(const [i,[scenario,label]] of [['normal','正在收录截图'],['paused','收录已暂停'],['hidden','裂缝已隐藏'],['attention','截图位置需要重新连接']].entries()){
  add(`C${i+1}`,`控制中心：${scenario}`,`切换控制中心；选择评审状态 ${scenario}；核对主状态及保留的历史/设置入口`,async()=>{
    await view('control');await page.locator('#scenario').selectOption(scenario);
    eq(await page.locator('.popover-status strong').innerText(),label);
    assert(await page.locator('[data-action="open-history"]').isEnabled());
    assert(await page.locator('[data-action="control-settings"]').isEnabled());
  },true);
}
add('C5','暂停与隐藏相互独立','通用依次暂停和隐藏，再转控制中心核对两个开关及组合说明',async()=>{
  await nav('general');await toggle('paused',true);await toggle('hidden',true);await view('control');
  const s=await state();eq([s.paused,s.hidden,s.persistedPaused,s.persistedHidden],[true,true,true,true]);
  assert((await page.locator('.popover-status').innerText()).includes('裂缝也已隐藏'));
},true);
add('C6','控制中心点击开关后保持打开','控制中心暂停ON再OFF，不关闭浮层、不修改隐藏',async()=>{
  await view('control');await toggle('paused',true);eq((await state()).closed,false);
  await toggle('paused',false);eq([(await state()).paused,(await state()).hidden],[false,false]);
});
add('C7','外部点击关闭控制中心','点击合成桌面空白，然后菜单栏图标再次打开',async()=>{
  await view('control');await page.locator('.desktop-surface').click({position:{x:40,y:200}});eq((await state()).closed,true);
  await click('status-click');eq((await state()).closed,false);eq(await page.locator('.popover').count(),1);
});
add('C8','右键菜单同源状态','切右键菜单；暂停、隐藏；切回控制中心核对状态',async()=>{
  await view('context');await click('toggle-pause');await click('toggle-hidden');await view('control');
  eq([(await state()).paused,(await state()).hidden],[true,true]);
},true);
add('C9','打开历史关闭浮层','控制中心点击历史；核对历史对话框和浮层已关闭',async()=>{
  await view('control');await click('open-history');eq((await state()).modal,'history');eq((await state()).closed,true);
  eq(await page.locator('.popover').count(),0);
});
add('F1','新装建议与真实main默认明确区分','评审样本 current → recommendation，核对25%与0%，其余实际默认保留',async()=>{
  await page.locator('#fixture').selectOption('current');eq((await state()).config.hiddenFraction,.25);
  await page.locator('#fixture').selectOption('recommendation');eq((await state()).config.hiddenFraction,0);
  eq((await state()).config.outerInset,6);
});
add('F2','旧JSON布局兼容','选legacy；核对14pt、旧绝对位置、未自动迁移；主动选择右下才迁移',async()=>{
  await page.locator('#fixture').selectOption('legacy');let s=await state();eq([s.config.placement,s.config.placementSource,s.config.outerInset],[null,'legacy',14]);
  await detail('custom-display');await detail('fine-display');assert(await page.locator('[data-config="firstCenterFromTop"]').isVisible());
  await shot('F2-legacy-before');await page.locator('[data-placement="rightBottom"]').click();s=await state();
  eq([s.config.placement,s.config.placementSource,s.config.outerInset],['rightBottom','user',14]);
});
add('F3','六种位置全部可选','依次点击六个位置，每次核对config与aria-pressed，保留geometry',async()=>{
  for(const pos of ['leftTop','rightTop','leftMiddle','rightMiddle','leftBottom','rightBottom']){
    await page.locator(`[data-placement="${pos}"]`).click();eq((await state()).config.placement,pos);
    eq(await page.locator(`[data-placement="${pos}"]`).getAttribute('aria-pressed'),'true');
    eq((await state()).config.fitWidth,72);
  }
});
add('F4','数字草稿与生效值分开','宽度编辑成96，失焦；草稿预览更新而生效值仍72；应用后才改变',async()=>{
  await display();await fill('fitWidth','96');await page.locator('h1').click();
  eq([(await state()).draft.fitWidth,(await state()).config.fitWidth],[96,72]);await shot('F4-draft');
  await click('apply-config');eq((await state()).config.fitWidth,96);
});
add('F5','空串编辑不自动变零','清空宽度输入，失焦再应用；原值保持、原始文本保留、显示校验错误',async()=>{
  await display();await fill('fitWidth','');await page.locator('h1').click();eq(await page.locator('[data-config="fitWidth"]').inputValue(),'');
  await click('apply-config');eq((await state()).config.fitWidth,72);eq((await state()).messageKind,'error');
},true);
add('F6','拒绝非有限与非法数字','依次输入NaN/Infinity/-1/257到宽度；每次应用均拒绝且不改生效值',async()=>{
  await display();for(const v of ['NaN','Infinity','-1','257']){await fill('fitWidth',v);await click('apply-config');eq((await state()).config.fitWidth,72);eq((await state()).messageKind,'error');}
});
add('F7','计数整数约束','输入3.5再应用拒绝；输入10成功',async()=>{
  await fill('visibleCountPreference','3.5');await click('apply-config');eq((await state()).config.visibleCountPreference,3);
  await fill('visibleCountPreference','10');await click('apply-config');eq((await state()).config.visibleCountPreference,10);
});
add('F8','精确输入保留有效上界','遮挡90%、宽256、高256、距边256，应用不夹断；90.1%拒绝',async()=>{
  await display();for(const [k,v]of [['hiddenFraction',90],['fitWidth',256],['fitHeight',256],['outerInset',256]])await fill(k,v);
  await click('apply-config');eq([(await state()).config.hiddenFraction,(await state()).config.fitWidth,(await state()).config.outerInset],[.9,256,256]);
  await fill('hiddenFraction','90.1');await click('apply-config');eq((await state()).config.hiddenFraction,.9);
});
add('F9','跨页保留草稿并统一应用','display改宽96，motion改吞噬200ms；来回切页保留；全局应用两项',async()=>{
  await display();await fill('fitWidth','96');await motion();await fill('swallowDuration','200');await display();
  eq(await page.locator('[data-config="fitWidth"]').inputValue(),'96');await click('apply-config');
  eq([(await state()).config.fitWidth,(await state()).config.swallowDuration],[96,.2]);
});
add('F10','即时位置不被数字草稿覆盖','改宽度草稿后选右下/外接屏再应用；三个值都保留',async()=>{
  await display();await fill('fitWidth','96');await page.locator('[data-placement="rightBottom"]').click();await set('display','external');await click('apply-config');
  const s=await state();eq([s.config.fitWidth,s.config.placement,s.config.preferredDisplayID],[96,'rightBottom',21412]);
});
add('F11','无变更禁用应用','初始无dirty；应用按钮不可用；改值应用后再次禁用',async()=>{
  assert(await page.locator('[data-action="apply-config"]').isDisabled());await display();await fill('fitWidth',96);await click('apply-config');
  assert(await page.locator('[data-action="apply-config"]').isDisabled());
});
add('F12','恢复本页只修改本页草稿','显示宽96和motion吞噬200草稿；恢复显示页不碰motion/屏幕/文件；尚未应用',async()=>{
  await display();await fill('fitWidth',96);await set('display','external');await motion();await fill('swallowDuration',200);await nav('display');
  const before=await state();await click('reset-page');await click('confirm-reset');const s=await state();
  eq(s.draft.fitWidth,72);eq(s.draft.swallowDuration,.2);eq(s.config,before.config);eq(s.files,before.files);
});
add('F13','Return提交数字草稿','宽96，真实键盘Enter提交，焦点仍在原字段',async()=>{
  await display();await fill('fitWidth',96);await page.locator('[data-config="fitWidth"]').press('Enter');eq((await state()).config.fitWidth,96);
  eq(await page.locator('[data-config="fitWidth"]').evaluate(e=>document.activeElement===e),true);
});
add('S1','配置保存失败保留草稿','改宽96→注入保存失败→应用；生效72、草稿96、明确错误',async()=>{
  await display();await fill('fitWidth',96);await failure();await click('apply-config');const s=await state();
  eq([s.config.fitWidth,s.draft.fitWidth,s.issue],[72,96,'write']);assert(s.message.includes('原设置仍然生效'));
},true);
add('S2','配置保存失败后原意重试','同一宽96草稿失败，取消故障再点应用；无需改值即可成功',async()=>{
  await display();await fill('fitWidth',96);await failure();await click('apply-config');await failure(false);await click('apply-config');
  eq([(await state()).config.fitWidth,(await state()).issue],[96,null]);
});
for(const [key,label]of [['paused','暂停'],['hidden','隐藏']]){
  add(key==='paused'?'S3':'S4',`${label}写失败仍停止当前运行`,`${label}ON时注入失败；运行态true、持久态false，提示重启风险；反向恢复失败不得假恢复`,async()=>{
    await writeError(key);let s=await state();eq([s[key],s[key==='paused'?'persistedPaused':'persistedHidden'],s.issue],[true,false,'write']);
    assert(s.message.includes('重启可能恢复'));await shot(`${current.id}-stop-unsaved`);
    await toggle(key,false);s=await state();eq(s[key],true);eq(s.issue,'write');
  },true);
}
add('S5','关闭内置入口写失败仍关闭运行','截图页关闭入口时注入失败；入口有效OFF、系统截图权限不变；启用失败仍OFF',async()=>{
  await nav('capture');await failure();const before=await state();await toggle('entryEnabled',false);let s=await state();
  eq(s.preferences.entryEnabled,false);eq(s.permissions,before.permissions);assert(s.message.includes('重启可能恢复'));await shot('S5-disabled-unsaved');
  await toggle('entryEnabled',true);eq((await state()).preferences.entryEnabled,false);
},true);
add('S6','普通偏好写失败不换生效值','截图默认模式由window改region时保存失败；依旧window',async()=>{
  await nav('capture');await failure();await set('defaultCaptureMode','region');eq((await state()).preferences.defaultCaptureMode,'window');
});
add('S7','位置与显示器写失败保持原值','注入失败后选右下及外接屏；位置/显示器原样保留',async()=>{
  const before=(await state()).config;await failure();await page.locator('[data-placement="rightBottom"]').click();await set('display','external');
  eq((await state()).config,before);
});
add('W1','关闭草稿默认继续编辑','编辑宽96→关闭；三个动作齐全，默认焦点继续编辑；Escape后草稿保留',async()=>{
  await display();await fill('fitWidth',96);await click('close-window');eq((await state()).modal,'unsaved');
  for(const a of ['discard-changes','apply-and-close','cancel-modal'])assert(await page.locator(`[data-action="${a}"]`).isVisible());
  eq(await page.evaluate(()=>document.activeElement.dataset.action),'cancel-modal');await shot('W1-close-confirmation');
  await page.keyboard.press('Escape');eq([(await state()).modal,(await state()).closed,(await state()).draft.fitWidth],[null,false,96]);
});
add('W2','不保存丢弃草稿并关闭','改宽96→关闭→不保存→重新打开；宽度72',async()=>{
  await display();await fill('fitWidth',96);await click('close-window');await click('discard-changes');eq((await state()).closed,true);
  await click('reopen-settings');eq((await state()).draft.fitWidth,72);
});
add('W3','应用并关闭覆盖所有待存域','布局宽96、归档2.5h草稿→关闭→应用并关闭；均保存',async()=>{
  await display();await fill('fitWidth',96);await archive();await page.locator('[data-setting="archiveHours"]').fill('2.5');
  await click('close-window');await click('apply-and-close');const s=await state();eq([s.config.fitWidth,s.archiveHours,s.closed],[96,2.5,true]);
});
add('W4','保存失败不能关闭丢草稿','宽96→注入失败→关闭→应用并关闭；仍在sheet、草稿96、运行72',async()=>{
  await display();await fill('fitWidth',96);await failure();await click('close-window');await click('apply-and-close');const s=await state();
  eq([s.closed,s.modal,s.config.fitWidth,s.draft.fitWidth],[false,'unsaved',72,96]);
},true);
add('W5','关闭sheet键盘焦点循环','打开未保存sheet；末按钮Tab回首，首按钮Shift+Tab回末',async()=>{
  await display();await fill('fitWidth',96);await click('close-window');await page.keyboard.press('Tab');
  eq(await page.evaluate(()=>document.activeElement.dataset.action),'discard-changes');await page.keyboard.press('Shift+Tab');
  eq(await page.evaluate(()=>document.activeElement.dataset.action),'cancel-modal');
});
add('M1','显示器断开不清长期UUID','先选外接，再切断开；保留UUID和ID，仅使用临时落点',async()=>{
  await set('display','external');const before=(await state()).config;await page.locator('#missing-display').check();const s=await state();
  eq([s.config.preferredDisplayID,s.config.preferredDisplayUUID],[before.preferredDisplayID,before.preferredDisplayUUID]);
  eq([s.displayMissing,s.usingFallback],[true,true]);assert((await body()).includes('临时使用主屏'));
},true);
add('M2','重连需显式回到已选屏','外接断开→重连；仍临时落点，点击回到已选显示器后才返回',async()=>{
  await set('display','external');await page.locator('#missing-display').check();await page.locator('#missing-display').uncheck();
  eq([(await state()).usingFallback,(await state()).displayRestoreAvailable],[true,true]);await shot('M2-reconnected-awaiting-return');
  await click('restore-display');eq([(await state()).usingFallback,(await state()).displayRestored],[false,true]);
});
add('M3','断开后选择内建屏结束回退','外接断开→选内建屏；选中身份1、回退结束，但外接仍断开',async()=>{
  await set('display','external');await page.locator('#missing-display').check();await set('display','builtin');const s=await state();
  eq([s.config.preferredDisplayID,s.usingFallback,s.displayMissing,s.externalDisplayMissing],[1,false,false,true]);
});
add('A1','归档自定义小数并保留关闭语义','输入2.5h未自动保存，点击保存生效；选关闭仍需保存，最终null',async()=>{
  await archive();await page.locator('[data-setting="archiveHours"]').fill('2.5');eq((await state()).archiveHours,24);await click('save-archive');eq((await state()).archiveHours,2.5);
  await set('archivePreset','0');eq((await state()).archiveHours,2.5);await click('save-archive');eq((await state()).archiveHours,null);
});
add('A2','归档非法输入与写失败不改生效值','空串/-1/Infinity分别拒绝；有效8h注入保存失败仍24h',async()=>{
  await archive();for(const value of ['','-1','Infinity']){await page.locator('[data-setting="archiveHours"]').fill(value);await click('save-archive');eq((await state()).archiveHours,24);eq((await state()).messageKind,'error');}
  await page.locator('[data-setting="archiveHours"]').fill('8');await failure();await click('save-archive');eq((await state()).archiveHours,24);
});
add('A3','清空只收起可见队列','控制中心清空→说明范围→确认；记录仍6条，文件/附件完全相同，无可见裂缝',async()=>{
  const before=await state();await view('control');await click('clear-queue');assert((await page.locator('.dialog').innerText()).includes('原文件和 ChatGPT 中已有的附件会保留'));
  await click('confirm-clear');const s=await state();eq(s.visibleCount,0);eq(s.records.length,before.records.length);eq(s.files,before.files);eq(s.attachments,before.attachments);
  eq(s.records.filter(x=>x.visible).length,0);eq(await page.locator('.desktop-rift').count(),0);
},true);
add('A4','清空取消不改变数据','打开清空确认后取消；记录、文件和附件不变',async()=>{
  const before=await state();await view('control');await click('clear-queue');await click('cancel-modal');const s=await state();
  eq(s.records,before.records);eq(s.files,before.files);eq(s.attachments,before.attachments);
});
add('A5','历史按状态和真实时间戳筛选','历史展开→unknown只显示sample6；1天范围排除该旧记录；all显示当日三条',async()=>{
  await nav('history');await detail('history-detail');await set('historyFilter','unknown');eq(await page.locator('[data-record-id]').count(),1);
  eq(await page.locator('[data-record-id]').getAttribute('data-record-id'),'sample-6');await set('historyRange','1');eq(await page.locator('[data-record-id]').count(),0);
  await set('historyFilter','all');eq(await page.locator('[data-record-id]').count(),3);
});
add('A6','存储未检查不显示零','历史页初始尚未检查；点击检查后显示演示数据且不删除记录',async()=>{
  await nav('history');assert((await page.locator('.storage-card').innerText()).includes('尚未检查'));const before=await state();await click('check-storage');
  assert((await page.locator('.storage-card').innerText()).includes('演示数据'));eq((await state()).files,before.files);
});
add('T1','关闭内置截图保留系统收录','关闭入口→控制中心内置按钮禁用；暂停和文件访问状态不变',async()=>{
  await nav('capture');await toggle('entryEnabled',false);await view('control');assert(await page.locator('[data-action="begin-capture"]').isDisabled());
  eq([(await state()).paused,(await state()).permissions.folder],[false,true]);
});
add('T2','首次内置截图按需请求权限','控制中心点截图→先说明录屏权限；取消不新增数据，再点允许才出现合成截图确认',async()=>{
  const before=await state();await view('control');await click('begin-capture');eq((await state()).modal,'screen');await click('cancel-modal');eq((await state()).records,before.records);
  await click('status-click');await click('begin-capture');await click('permit-screen');eq((await state()).modal,'capture');eq((await state()).records,before.records);
  await click('simulate-capture');eq((await state()).records.length,before.records.length+1);eq((await state()).attachments,before.attachments);
});
add('T3','截图默认方式三种保留','依次选window/region/fullScreen；状态与控件一致',async()=>{
  await nav('capture');for(const value of ['region','fullScreen','window']){await set('defaultCaptureMode',value);eq((await state()).preferences.defaultCaptureMode,value);}
});
add('T4','隐藏不偷偷恢复截图入口','隐藏→控制中心截图禁用并说明；重新显示后恢复原开启入口，权限未被自动请求',async()=>{
  await nav('general');await toggle('hidden',true);await view('control');assert(await page.locator('[data-action="begin-capture"]').isDisabled());
  assert((await page.locator('.popover').innerText()).includes('显示裂缝后'));await toggle('hidden',false);
  assert(await page.locator('[data-action="begin-capture"]').isEnabled());eq((await state()).permissions.screen,false);
});
add('V1','动效仅无和磁力两种','motion核对两个radio；无入缝预览不播放，选择磁力有主动播放事件',async()=>{
  await nav('motion');eq(await page.locator('[data-setting="arrival"]').count(),2);await click('preview-arrival');
  await page.waitForFunction(()=>window.RiftletDesign.getState().lastAction==='motion-preview-none');
  await page.locator('[data-setting="arrival"][value="magnet"]').check();await click('preview-arrival');
  await page.waitForFunction(()=>window.RiftletDesign.getState().events.some(e=>e.action==='motion-preview'&&e.detail==='arrival'));
});
add('V2','减少动态不修改保存时长','motion→系统减少动态ON→预览吞噬；配置完全不变，动画≤80ms',async()=>{
  await nav('motion');const before=(await state()).config;await page.locator('#reduce-motion').check();await click('preview-swallow');
  eq((await state()).config,before);const duration=await page.locator('.motion-image').evaluate(e=>parseFloat(getComputedStyle(e).animationDuration));assert(duration<=.08);
},true);
add('V3','设置ms与源码秒单位转换','motion吞噬填写250ms→Enter；config .25秒，控件仍250',async()=>{
  await motion();await fill('swallowDuration',250);await page.locator('[data-config="swallowDuration"]').press('Enter');
  eq((await state()).config.swallowDuration,.25);eq(await page.locator('[data-config="swallowDuration"]').inputValue(),'250');
});
add('O1','引导第一步及稍后设置','首次使用step1→稍后设置；未完成、没有截图/附件变化',async()=>{
  const before=await state();await view('onboarding');eq((await state()).onboardingStep,0);assert((await body()).includes('点一下就够了'));
  await shot('O1-step1');await click('setup-later');const s=await state();eq(s.onboardingCompleted,false);eq(s.records,before.records);eq(s.attachments,before.attachments);
});
add('O2','引导第二步可跳过未完成权限','attention→首次使用→继续到step2；不自动授予folder/screen；可继续',async()=>{
  await page.locator('#scenario').selectOption('attention');await view('onboarding');await click('setup-next');eq((await state()).onboardingStep,1);
  eq([(await state()).permissions.folder,(await state()).permissions.screen],[false,false]);await shot('O2-step2-partial');
  await click('setup-next');eq((await state()).onboardingStep,2);
});
add('O3','引导第三步保存位置并无自动操作','预先暂停+隐藏→引导继续两步→右下/内建屏→开始；保持暂停隐藏和全部数据',async()=>{
  await nav('general');await toggle('paused',true);await toggle('hidden',true);const before=await state();await view('onboarding');await click('setup-next');await click('setup-next');
  await page.locator('[data-placement="rightBottom"]').click();await set('display','builtin');await shot('O3-step3');await click('setup-next');
  const s=await state();eq([s.onboardingCompleted,s.paused,s.hidden,s.config.placement,s.config.preferredDisplayID],[true,true,true,'rightBottom',1]);
  eq(s.records,before.records);eq(s.attachments,before.attachments);eq(s.permissions,before.permissions);
});
add('O4','引导上一步与重新查看','step2返回step1，再完成；通用重新查看从step1开始且保持配置',async()=>{
  await view('onboarding');await click('setup-next');await click('setup-back');eq((await state()).onboardingStep,0);
  await click('setup-next');await click('setup-next');await click('setup-next');await view('settings');await nav('general');await click('open-onboarding');eq((await state()).onboardingStep,0);
});
add('H1','权限仅主动按钮模拟','attention→权限页连接→取消不改变→再连接模拟允许才恢复',async()=>{
  await page.locator('#scenario').selectOption('attention');await nav('permissions');await click('authorize-folder');eq((await state()).permissions.folder,false);
  await click('cancel-modal');eq((await state()).permissions.folder,false);await click('authorize-folder');await click('permit-folder');eq((await state()).permissions.folder,true);
});
add('H2','反馈草稿与诊断明确未发送','通用反馈→填合成文字、勾本次诊断→预览→保存关闭→重开，草稿和勾选保留',async()=>{
  await nav('general');await click('open-feedback');await page.locator('#feedback-draft').fill('合成回归反馈：这不是用户数据');await page.locator('[data-setting="feedbackDiagnostics"]').check();
  await click('preview-feedback');assert((await page.locator('.dialog').innerText()).includes('不会访问系统'));await click('save-feedback');await click('open-feedback');
  eq(await page.locator('#feedback-draft').inputValue(),'合成回归反馈：这不是用户数据');eq((await state()).feedbackIncludeDiagnostics,true);
});

// Contract failures are deliberately asserted, not xfailed or silently changed.
for(const [key,id] of [['paused','X1'],['hidden','X2']]){
  add(id,`${key}未保存事实不能被外观成功清除`,`${key}ON写失败→取消故障注入→外观深色成功；未保存告警必须继续保留`,async()=>{
    await writeError(key);await failure(false);await set('appearance','dark');const s=await state();
    eq(s[key],true);eq(s[key==='paused'?'persistedPaused':'persistedHidden'],false);
    eq(s.issue,'write','未保存的运行偏好仍与持久意图不一致，无关成功不得清除提示');
  });
}
add('X3','内置入口必须区分有效状态与持久意图','关闭入口保存失败；有效OFF，但必须可观察持久意图/未确认状态',async()=>{
  await nav('capture');await failure();await toggle('entryEnabled',false);const s=await state();eq(s.preferences.entryEnabled,false);
  assert('persistedEntryEnabled' in s || 'persistedEntryEnabled' in s.preferences || 'entryPersistence' in s,'原型未保存入口持久状态/保存结果域，无法独立核对运行与持久意图');
});
add('X4','文件授权成功不清除暂停保存失败','attention→暂停写失败→权限页允许访问→folder恢复；暂停未保存告警仍需存在',async()=>{
  await page.locator('#scenario').selectOption('attention');await writeError('paused');await nav('permissions');await click('authorize-folder');await click('permit-folder');const s=await state();
  eq([s.permissions.folder,s.paused,s.persistedPaused],[true,true,false]);eq(s.issue,'write','文件授权与偏好写入是独立错误域');
});
add('X5','布局保存失败不被无关偏好成功清除','宽96草稿应用失败→外观成功；草稿仍未保存，必须保留写失败域',async()=>{
  await display();await fill('fitWidth',96);await failure();await click('apply-config');await failure(false);await nav('general');await set('appearance','dark');const s=await state();
  eq([s.config.fitWidth,s.draft.fitWidth],[72,96]);eq(s.issue,'write','外观成功不能标记布局保存错误已解决');
});
add('X6','停止方向保存失败提供原意重试','暂停ON保存失败→取消注入→控制中心前往处理；必须可重试暂停ON保存，而非先恢复收录',async()=>{
  await writeError('paused');await failure(false);await view('control');await click('fix-issue');
  const retry=page.getByRole('button',{name:/重试保存|重新保存|保存当前状态/});
  assert(await retry.count()>0,'没有可见的同方向重试保存动作，不能要求先OFF再ON');
});
add('X7','兼容失效字段不能伪装有效旋钮','展开display和motion高级项；main未使用的兼容字段应保留数据但不提供有效编辑',async()=>{
  await display();await detail('fine-display');const exposed=[];
  for(const key of ['lineWidth','lineExtension','screenPadding'])if(await page.locator(`[data-config="${key}"]`).isVisible())exposed.push(key);
  await motion();for(const key of ['inwardDistance','reducedMotionDuration'])if(await page.locator(`[data-config="${key}"]`).isVisible())exposed.push(key);
  eq(exposed,[],'这些字段已由main其他机制替代；原型旋钮会误导实际效果');
});
add('X8','清空不得承诺不存在的批量撤销后端','清空确认后，核对未呈现main不具备的undo-clear命令',async()=>{
  await clearQueue();eq(await page.locator('[data-action="undo-clear"]').count(),0,'main clearVisible没有成组恢复命令；撤销toast仅为未对齐的原型能力');
});
add('X9','选择主显示器保存当时具体身份','选外接再选主显示器；应保存真实屏幕ID/UUID，不等于清空为动态跟随',async()=>{
  await set('display','external');await set('display','primary');const c=(await state()).config;
  assert(c.preferredDisplayID!==null&&c.preferredDisplayUUID!==null,'main选择主屏会解析当时NSScreen身份；原型存null不等价');
});
add('Z1','无脚本异常或外部网络','全部交互结束后，核对无pageerror且无外部HTTP(S)请求',async()=>{
  eq(report.pageErrors,[]);eq(report.externalRequests,[]);
});

(async()=>{
  try {
    browser=await playwright.chromium.launch({headless:true,...(process.env.BROWSER_EXECUTABLE?{executablePath:process.env.BROWSER_EXECUTABLE}:{})});
    report.runtime.browser=browser.version();
    if(process.env.BROWSER_EXECUTABLE){report.runtime.browserExecutable=path.basename(process.env.BROWSER_EXECUTABLE);report.runtime.browserExecutableSHA256=hashFile(process.env.BROWSER_EXECUTABLE);}
    context=await browser.newContext({viewport:{width:1440,height:1100},deviceScaleFactor:1,locale:'zh-CN',timezoneId:'Asia/Shanghai',colorScheme:'light',reducedMotion:'no-preference'});
    await context.route(/^https?:/,async route=>{report.externalRequests.push(route.request().url());await route.abort();});
    page=await context.newPage();page.setDefaultTimeout(4000);
    page.on('pageerror',error=>report.pageErrors.push(String(error)));
    await page.goto(pathToFileURL(html).href);await page.waitForFunction(()=>!!window.RiftletDesign);
    for(const c of cases){
      current=c;await reset();const started=Date.now();const result={id:c.id,title:c.title,steps:c.steps,status:'RUNNING',assertion:null};
      try{await c.fn();result.status='PASS';if(c.shot)await shot(c.id);}
      catch(error){result.status='FAIL';result.assertion=error.message;result.stack=String(error.stack).split('\n').slice(0,7).join('\n').replaceAll(root,'<design-root>');await shot(c.id+'-FAIL');
        fs.writeFileSync(path.join(output,c.id+'-failure.json'),JSON.stringify({caseID:c.id,title:c.title,steps:c.steps,error:result.assertion,state:await state(),visibleText:await body()},null,2)+'\n');}
      result.durationMs=Date.now()-started;report.cases.push(result);console.log(`${result.status} ${c.id} ${c.title}`);
      fs.writeFileSync(path.join(output,'results.json'),JSON.stringify(report,null,2)+'\n');
    }
  }catch(error){report.infrastructureError=String(error.stack);console.error(error);}
  finally{
    if(browser)await browser.close();report.finishedAt=new Date().toISOString();
    report.summary={total:report.cases.length,pass:report.cases.filter(x=>x.status==='PASS').length,fail:report.cases.filter(x=>x.status==='FAIL').length};
    report.prototypeUnchanged=hashFile(html)===expectedHTML;
    report.inheritedFilesUnchanged=report.inheritedFiles.every(x=>hashFile(path.join(repo,x.file))===x.sha256);
    fs.writeFileSync(path.join(output,'results.json'),JSON.stringify(report,null,2)+'\n');
    fs.writeFileSync(path.join(output,'screenshots.json'),JSON.stringify(report.screenshots,null,2)+'\n');
    const md=['# 本轮真实浏览器回归结果','',`运行：\`${runID}\``, '',`结果：${report.summary.pass} PASS / ${report.summary.fail} FAIL / ${report.summary.total} 项。`, '',
      `HTML SHA-256：\`${report.prototype.sha256}\``, '',report.scope,'','FAIL 为实际合同差异，未改写为预期成功；每项失败有原始 PNG 与状态记录。历史遗失的 41 PASS 未引用。','',
      '| ID | 结果 | 验证目标 | 可复验操作 |','| --- | --- | --- | --- |',...report.cases.map(c=>`| ${c.id} | ${c.status} | ${c.title} | ${c.steps.replaceAll('|',' / ')} |`),'',
      '## 失败记录','',...report.cases.filter(c=>c.status==='FAIL').map(c=>`- **${c.id}**：${c.assertion.replaceAll('\n',' ')}。 [状态记录](${c.id}-failure.json) · [原始画面](screenshots/${c.id}-FAIL.png)`),'',
      `原型保持：${report.prototypeUnchanged}；运行前后继承文件保持：${report.inheritedFilesUnchanged}。`,report.infrastructureError?'基础设施异常：'+report.infrastructureError:'浏览器进程已由脚本关闭。',''];
    fs.writeFileSync(path.join(output,'RESULTS.md'),md.join('\n'));
    console.log(JSON.stringify({output,summary:report.summary,infrastructureError:report.infrastructureError||null}));
    process.exitCode=report.infrastructureError||report.summary.fail||!report.prototypeUnchanged?1:0;
  }
})();
