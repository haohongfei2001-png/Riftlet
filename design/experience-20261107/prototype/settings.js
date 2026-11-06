/* Riftlet experience study · settings only · synthetic, in-memory interaction. */
(() => {
  'use strict';

  const layoutDefaults = {
    fitWidth: 72, fitHeight: 56, hiddenFraction: 25, rowPitch: 60,
    outerInset: 6, numberFontSize: 11, numberGap: 8, leftPadding: 4,
    minimumHitWidth: 44, minimumHitHeight: 44, firstCenterFromTop: 202,
    visibleCountPreference: 3, pressDuration: 60, swallowDuration: 120,
    shiftDuration: 160, returnDuration: 180
  };
  const defaults = {
    appearance: 'system', paused: false, hidden: false,
    display: 'main', displayDisconnected: false, placement: 'leftMiddle',
    entryEnabled: true, captureMode: 'window', arrival: 'magnet',
    reduceMotion: false, reduceTransparency: false, increaseContrast: false,
    archiveHours: 0, archiveDraft: null, archiveCustom: false,
    sourcePermission: 'granted', automationPermission: 'granted',
    javascriptAllowed: true, screenPermission: 'granted',
    storageMeasured: false, saveError: false,
    layout: layoutDefaults, draft: {}, openGroups: []
  };
  const pageNames = {
    general: ['通用', '安静待命，照顾每一次截图。'],
    display: ['位置与显示', '在顺手的地方，为截图留一点空间。'],
    capture: ['截图', '继续用熟悉的方式，也可以从这里开始。'],
    motion: ['动效', '有回应，不打扰。'],
    history: ['历史与存储', '用过的画面，依然找得到。'],
    help: ['权限与帮助', '每项权限，都有清楚的用途。']
  };
  const fieldInfo = {
    visibleCountPreference: ['显示数量', '张', 1, 10, 1],
    hiddenFraction: ['藏入边缘', '%', 0, 90, 1],
    outerInset: ['边缘内缩', 'pt', 0, 256, 1],
    fitWidth: ['微图最大宽度', 'pt', 0, 256, 'any'],
    fitHeight: ['微图最大高度', 'pt', 0, 256, 'any'],
    rowPitch: ['微图排列间距', 'pt', 0, null, 'any'],
    numberFontSize: ['编号字号', 'pt', 0, 32, 'any'],
    numberGap: ['编号与微图间距', 'pt', 0, null, 'any'],
    leftPadding: ['行左侧留白', 'pt', 0, null, 'any'],
    minimumHitWidth: ['最小行宽', 'pt', 0, 256, 'any'],
    minimumHitHeight: ['最小行高', 'pt', 0, 256, 'any'],
    firstCenterFromTop: ['旧版距顶部位置', 'pt', 0, null, 'any'],
    pressDuration: ['轻按反馈', 'ms', 0, 3000, 10],
    swallowDuration: ['快速吞噬', 'ms', 0, 3000, 10],
    shiftDuration: ['队列补位', 'ms', 0, 3000, 10],
    returnDuration: ['失败回归', 'ms', 0, 3000, 10]
  };
  const positiveFields = new Set(['fitWidth','fitHeight','rowPitch','numberFontSize','minimumHitWidth','minimumHitHeight']);
  const motionFields = ['pressDuration', 'swallowDuration', 'shiftDuration', 'returnDuration'];
  const displayFields = Object.keys(layoutDefaults).filter(k => !motionFields.includes(k));
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const icon = (name, size = 16) => window.icon ? window.icon(name, size) : '<span class="st-icon-fallback" aria-hidden="true"></span>';
  const settings = state => ({
    ...defaults, ...(state.settings || {}),
    layout: {...layoutDefaults, ...(state.settings?.layout || {})},
    draft: {...(state.settings?.draft || {})},
    openGroups: [...(state.settings?.openGroups || [])]
  });
  const value = (s, key) => Object.hasOwn(s.draft, key) ? s.draft[key] : s.layout[key];
  const num = (s, key) => {
    const n = Number(value(s, key));
    return Number.isFinite(n) ? n : s.layout[key];
  };
  const row = (title, detail, control, cls = '') => `<div class="st-row ${cls}"><div class="st-row-copy"><div class="st-label">${title}</div>${detail ? `<div class="st-detail">${detail}</div>` : ''}</div><div class="st-row-control">${control}</div></div>`;
  const toggle = (key, label, on, disabled = false) => `<label class="st-switch"><input type="checkbox" data-st-key="${key}" aria-label="${esc(label)}" ${on ? 'checked' : ''} ${disabled ? 'disabled' : ''}><span class="st-switch-track" aria-hidden="true"></span></label>`;
  const select = (key, label, current, entries, disabled = false) => `<div class="st-select-wrap"><select data-st-key="${key}" aria-label="${esc(label)}" ${disabled ? 'disabled' : ''}>${entries.map(([v, text]) => `<option value="${esc(v)}" ${String(current) === String(v) ? 'selected' : ''}>${esc(text)}</option>`).join('')}</select><span aria-hidden="true">${icon('chevron-down', 13)}</span></div>`;
  const action = (label, key, opts = '') => `<button type="button" class="st-text-button" data-st-action="${key}" ${opts}>${label}</button>`;
  const section = (title, body, cls = '') => `<section class="st-section ${cls}">${title ? `<h3 class="st-section-title">${title}</h3>` : ''}${body}</section>`;
  const disclosure = (id, title, detail, body, s) => `<details class="st-disclosure" data-st-group="${id}" ${s.openGroups.includes(id) ? 'open' : ''}><summary><span class="st-disclosure-chevron" aria-hidden="true">${icon('chevron-right', 13)}</span><span><span class="st-label">${title}</span>${detail ? `<span class="st-detail">${detail}</span>` : ''}</span></summary><div class="st-disclosure-body">${body}</div></details>`;
  const numeric = (key, s, slider = false, detail = '') => {
    const [label, unit, min, max, step] = fieldInfo[key];
    const id = `st-number-${key}`;
    return row(`<label for="${id}">${label}</label>`, detail, `<div class="st-number-controls">${slider ? `<input class="st-range" type="range" data-st-range="${key}" min="${min}" max="${max}" step="${step}" value="${esc(num(s, key))}" aria-label="${label}">` : ''}<span class="st-number-wrap"><input id="${id}" type="number" inputmode="decimal" data-st-field="${key}" min="${min}" ${max===null?'':`max="${max}"`} step="${step}" value="${esc(value(s, key))}" aria-label="${label}，${unit}"><span>${unit}</span></span></div>`);
  };
  function sample(index = 0, cls = '') {
    const kind = ['article', 'plant', 'chart'][index % 3];
    return `<div class="st-sample st-sample-${kind} ${cls}" aria-hidden="true">${kind === 'article' ? '<span class="st-paper-title"></span><span class="st-paper-line"></span><span class="st-paper-line"></span><span class="st-paper-line st-short"></span><span class="st-paper-block"></span>' : kind === 'plant' ? '<span class="st-plant-stem"></span><span class="st-plant-leaf st-leaf-1"></span><span class="st-plant-leaf st-leaf-2"></span><span class="st-plant-leaf st-leaf-3"></span><span class="st-plant-leaf st-leaf-4"></span>' : '<span class="st-chart-grid"></span><span class="st-chart-bar st-bar-1"></span><span class="st-chart-bar st-bar-2"></span><span class="st-chart-bar st-bar-3"></span><span class="st-chart-bar st-bar-4"></span><span class="st-chart-bar st-bar-5"></span>'}</div>`;
  }
  function saveArea(s, page) {
    const fields = page === 'motion' ? motionFields : displayFields;
    const dirty = fields.some(key => Object.hasOwn(s.draft, key));
    return `<div class="st-save-area ${dirty || s.saveError ? 'st-is-dirty' : ''}" data-st-save-area><div class="st-save-copy"><span class="st-save-message" aria-live="polite">${s.saveError ? '这次更改尚未保存' : dirty ? '预览已更新，参数尚未应用' : '参数更改会先在这里预览'}</span><span class="st-validation" role="alert"></span></div><div class="st-save-buttons">${action('恢复默认', 'defaults')}<button type="button" class="st-discard" data-st-action="discard" ${!dirty && !s.saveError ? 'hidden' : ''}>放弃</button><button type="button" class="st-apply" data-st-action="apply" ${!dirty && !s.saveError ? 'disabled' : ''}>${s.saveError ? '重试保存' : '应用参数'}</button></div></div>`;
  }
  function general(s) {
    const title = s.paused ? '收录已暂停' : s.hidden ? '在后台安静收录' : '随时待命';
    const detail = s.paused ? '已有截图仍然保留。' : s.hidden ? '截图会收录，边缘暂不显示。' : '截图后，点一下边缘微图。';
    const themes = [['system', '跟随系统'], ['light', '浅色'], ['dark', '深色']];
    return `<div class="st-status-line"><span class="st-status-symbol ${s.paused ? 'st-muted-symbol' : ''}">${icon(s.paused ? 'pause' : s.hidden ? 'eye' : 'check', 18)}</span><div><div class="st-status-title">${title}</div><p>${detail}</p></div></div>
      ${section('外观', `<div class="st-themes" role="group" aria-label="外观">${themes.map(([key,label]) => `<button type="button" class="st-theme-choice ${s.appearance === key ? 'st-selected' : ''}" data-st-appearance="${key}" aria-pressed="${s.appearance === key}"><span class="st-theme-window st-theme-${key}" aria-hidden="true"><span class="st-theme-sidebar"><i></i><i></i><i></i></span><span class="st-theme-body"><i></i><i></i><i></i></span></span><span class="st-theme-caption">${label}<span class="st-choice-check">${s.appearance === key ? icon('check', 12) : ''}</span></span></button>`).join('')}</div>`)}
      ${section('收录与显示', row('暂停收录', '不收录新截图，已有图片保留。', toggle('paused','暂停收录',s.paused)) + row('暂时隐藏裂缝', '只隐藏边缘微图，继续按当前设置收录。', toggle('hidden','暂时隐藏裂缝',s.hidden)))}
      ${section('', row('登录时启动', '当前 Beta 尚不能注册登录项。', toggle('login','登录时启动',false,true), 'st-disabled-row'))}
      <div class="st-subtle-note">${icon('info',14)}<span>遵循 macOS 的动态效果、透明度与对比度设置。</span></div>
      <div class="st-page-links">${action('使用引导', 'onboarding')}${action('反馈与建议', 'feedback')}</div>`;
  }
  function display(s) {
    const positions = [['leftTop','左上'], ['rightTop','右上'], ['leftMiddle','左中'], ['rightMiddle','右中'], ['leftBottom','左下'], ['rightBottom','右下']];
    const placement = s.placement || 'rightMiddle';
    const count = Math.max(1, Math.min(10, Math.round(num(s,'visibleCountPreference'))));
    const monitor = `<div class="st-placement-stage"><div class="st-monitor" role="img" aria-label="边缘位置预览，${positions.find(p=>p[0]===placement)?.[1] || '旧版位置'}，${count}张微图"><div class="st-monitor-top"><i></i><span></span><span></span></div><div class="st-monitor-content"><div class="st-monitor-document"><span class="st-doc-heading"></span><span></span><span></span><span class="st-doc-short"></span><div class="st-doc-chart"><i></i><i></i><i></i><i></i><i></i></div></div></div><div class="st-mini-queue st-${placement}" data-st-mini-queue style="--st-hidden:${num(s,'hiddenFraction') / 100};--st-row-gap:${Math.max(1,Math.min(12,(num(s,'rowPitch')-42)*.18))}px">${Array.from({length:Math.min(count,5)},(_,i)=>sample(i)).join('')}</div></div><div class="st-placement-options" role="group" aria-label="边缘位置">${positions.map(([key,label])=>`<button type="button" class="st-position st-position-${key} ${placement===key?'st-selected':''}" data-st-placement="${key}" aria-pressed="${placement===key}"><span class="st-position-mark" aria-hidden="true"></span><span>${label}</span></button>`).join('')}</div></div>`;
    const displayOptions = [['main','主显示器'],['external','外接显示器']];
    if (s.displayDisconnected) displayOptions.push(['disconnected','已选显示器 · 未连接']);
    return `${row('显示器', '', select('display','显示器',s.display,displayOptions))}${s.displayDisconnected ? `<div class="st-inline-notice">${icon('info',14)}<span>当前临时显示在主屏，保留原来的选择。</span>${action('回到已选屏幕','restoreDisplay')}</div>`:''}
      ${monitor}
      <p class="st-preview-caption"><span data-st-placement-caption>${positions.find(p=>p[0]===placement)?.[1] || '旧版位置'}</span> · 示意图，实际微图保持原始比例</p>
      ${section('', numeric('visibleCountPreference',s,true) + numeric('hiddenFraction',s,true, '0% 时完整显示，不裁去画面。'))}
      ${disclosure('display-details','尺寸与留白','调整微图、排列与编号。',numeric('outerInset',s)+numeric('fitWidth',s)+numeric('fitHeight',s)+numeric('rowPitch',s)+numeric('numberFontSize',s),s)}
      ${disclosure('display-fine','精细参数','保留更细的个性化控制。',numeric('numberGap',s)+numeric('leftPadding',s)+numeric('minimumHitWidth',s)+numeric('minimumHitHeight',s)+(s.placement===null ? numeric('firstCenterFromTop',s) : '')+'<p class="st-footnote">最小行尺寸用于排列；点击区域仍只属于对应的截图。旧版绝对位置仅在尚未选择六点位置时可编辑。</p><p class="st-footnote">旧版兼容参数保留原值，可在配置文件中查看。</p>'+action('查看配置说明','configuration'),s)}
      ${saveArea(s,'display')}`;
  }
  function capture(s) {
    return `<div class="st-shortcut-strip"><div><span class="st-shortcut-label">区域截图</span><span class="st-keys"><kbd>⇧</kbd><kbd>⌘</kbd><kbd>4</kbd></span></div><div><span class="st-shortcut-label">全屏截图</span><span class="st-keys"><kbd>⇧</kbd><kbd>⌘</kbd><kbd>3</kbd></span></div><div><span class="st-shortcut-label">截图工具栏</span><span class="st-keys"><kbd>⇧</kbd><kbd>⌘</kbd><kbd>5</kbd></span></div></div>
      ${section('截图保存位置', `<div class="st-location-row"><span class="st-folder-icon">${icon('folder',25)}</span><div class="st-location-copy"><div class="st-label">系统截图位置</div><div class="st-detail">${s.sourcePermission==='granted'?'已允许读取新保存的截图':'尚未允许访问此位置'}</div></div>${action('打开', 'source', `aria-label="打开系统截图位置"`)}</div>${s.sourcePermission!=='granted'?`<div class="st-inline-notice">${icon('info',14)}<span>已有截图保留，允许后继续收录。</span>${action('允许访问','sourceAccess')}</div>`:''}<p class="st-footnote">保存成文件的截图会进入 Riftlet。复制到剪贴板的画面不会被收录。</p>`)}
      ${section('内置截图', row('启用截图入口', '从菜单栏或独立截图按钮开始。', toggle('entryEnabled','启用内置截图',s.entryEnabled)) + row('默认方式', '', select('captureMode','默认截图方式',s.captureMode,[['window','窗口'],['region','区域'],['fullScreen','全屏']],!s.entryEnabled)) + `<div class="st-capture-start"><button type="button" class="st-action-button" data-st-action="capture" ${!s.entryEnabled?'disabled':''}>${icon('camera',16)}<span>开始截图</span></button><span class="st-detail">延迟与指针，可在每次截图时选择。</span></div>`)}
      <div class="st-subtle-note">${icon('info',14)}<span>关闭内置入口，不影响 macOS 截图与文件收录。</span></div><div class="st-page-links">${action('查看截图权限', 'help')}</div>`;
  }
  function motion(s) {
    return `${section('',row('截图到达边缘时','',`<div class="st-segmented" role="group" aria-label="入缝动效"><button type="button" data-st-arrival="none" aria-pressed="${s.arrival==='none'}" class="${s.arrival==='none'?'st-selected':''}">无</button><button type="button" data-st-arrival="magnet" aria-pressed="${s.arrival==='magnet'}" class="${s.arrival==='magnet'?'st-selected':''}">磁力吸引</button></div>`))}
      <div class="st-motion-preview" data-st-motion-preview role="img" aria-label="截图入缝和点击后吞噬的动态示意"><div class="st-motion-canvas"><div class="st-motion-edge"></div><div class="st-motion-queue">${sample(0,'st-motion-first')}${sample(1,'st-motion-second')}${sample(2,'st-motion-third')}</div><div class="st-motion-origin">${sample(0)}<span>系统截图</span></div><div class="st-motion-copy"><span class="st-motion-state" data-st-motion-state>轻轻收进工作边缘</span><span class="st-motion-support">只在你需要时出现</span></div></div><div class="st-motion-toolbar"><button type="button" data-st-action="playArrival">${icon('play',13)}<span>预览入缝</span></button><button type="button" data-st-action="playSwallow">${icon('play',13)}<span>预览吞噬</span></button></div></div>
      <p class="st-footnote st-motion-explanation">图片开始进入聊天附件后，微图立即收起；其余截图自然补位。</p>
      <div class="st-reduced-note">${icon('motion',16)}<div><div class="st-label">${s.reduceMotion?'已减少动态效果':'跟随系统的动态效果设置'}</div><div class="st-detail">${s.reduceMotion?'以静态替换和短淡出呈现，保留你选择的入缝偏好。':'开启“减少动态效果”后，取消飞行与空间位移。'}</div></div></div>
      ${disclosure('motion-fine','时间与节奏','按下、收起、补位与回归分别调整。',motionFields.map(key=>numeric(key,s)).join('')+'<p class="st-footnote">0–3000 ms，只调整视觉呈现。附加开始和失败的判断仍由原有流程决定。</p>',s)}
      ${saveArea(s,'motion')}`;
  }
  function history(s) {
    const hours = s.archiveDraft !== null ? s.archiveDraft : s.archiveHours;
    const presets = [['0','不自动归档'],['1','1 小时'],['8','8 小时'],['24','24 小时'],['72','72 小时'],['custom','自定义…']];
    const custom = s.archiveCustom || !['0','1','8','24','72'].includes(String(hours));
    const dirty = s.archiveDraft !== null;
    return `<div class="st-history-intro"><div class="st-history-stack" aria-hidden="true">${sample(0)}${sample(1)}${sample(2)}</div><div><h3>用过，也留着</h3><p>已收起和归档的截图，都能在历史中浏览。</p><button type="button" class="st-action-button" data-st-action="history">${icon('history',15)}<span>打开截图历史</span></button></div></div>
      ${section('边缘整理',row('自动归档', '一段时间未使用后，收入历史。',select('archivePreset','自动归档时限',custom?'custom':hours,presets)) + `<div class="st-archive-custom" ${custom?'':'hidden'}>${row('<label for="st-archive-hours">自定义时限</label>','支持小数小时；0 表示关闭。',`<span class="st-number-wrap"><input id="st-archive-hours" type="number" inputmode="decimal" min="0" step="0.25" data-st-archive value="${esc(hours)}" aria-label="自定义归档小时数"><span>小时</span></span>`)}</div><p class="st-footnote">鼠标悬停、按住或动画进行时，会等交互结束再整理。</p><div class="st-archive-save" ${dirty?'':'hidden'}><span class="st-detail" aria-live="polite">归档时限尚未保存</span><button type="button" class="st-discard" data-st-action="discardArchive">放弃</button><button type="button" class="st-apply" data-st-action="applyArchive">保存时限</button></div>`)}
      ${section('本机存储',row(s.storageMeasured?'已使用 18.6 MB':'存储用量',s.storageMeasured?'演示中的本地图片与记录':'按需检查，不打扰日常使用。',action(s.storageMeasured?'重新检查':'检查用量','storage')) + '<p class="st-footnote">收起与归档不会删除系统原图、本地副本或聊天附件。</p>')}
      <div class="st-clear-row"><div><div class="st-label">收起边缘的全部微图</div><div class="st-detail">只整理当前边缘，图片仍可在历史中找到。</div></div>${action('收起全部…', 'clearVisible')}</div>`;
  }
  function help(s) {
    const permission = (glyph, title, detail, good, actionLabel, key) => `<div class="st-permission-row"><span class="st-permission-icon">${icon(glyph,18)}</span><div class="st-permission-copy"><div class="st-label">${title}</div><div class="st-detail">${detail}</div></div><div class="st-permission-end"><span class="st-permission-state ${good?'st-granted':'st-needs-action'}">${good?icon('check',12):icon('info',12)}${good?'已允许':'待设置'}</span>${action(actionLabel,key)}</div></div>`;
    return `<div class="st-permissions">${permission('folder','截图位置','收录系统新保存的截图。',s.sourcePermission==='granted','查看','sourceAccess')}${permission('shield','Chrome 自动化','将点击的截图放进当前聊天附件。',s.automationPermission==='granted','检查','automation')}${permission('camera','屏幕录制','仅用于 Riftlet 内置截图。',s.screenPermission==='granted','设置','screenPermission')}</div>
      ${disclosure('chrome-detail','Chrome 连接说明',s.javascriptAllowed?'Apple 事件的 JavaScript 已在演示状态中开启。':'还需要允许 Apple 事件的 JavaScript。','<p class="st-footnote">在 Chrome「视图 → 开发者」中开启「允许来自 Apple 事件的 JavaScript」。macOS 自动化授权与这个选项是两项独立设置。</p><p class="st-footnote">请保持需要附加图片的聊天为 Chrome 当前标签页。Riftlet 不会猜测或切换到其他聊天。</p>'+action('重新检查连接','recheck'),s)}
      ${section('关于', `<div class="st-about"><span class="st-about-wordmark">Riftlet<span class="st-about-dot"></span></span><span class="st-version">个人 Beta 2 · 0.2.0 (2)</span></div><p class="st-about-line">从截图到输入，点一下就够了。</p><div class="st-page-links">${action('使用引导','onboarding')}${action('反馈与建议','feedback')}</div>`)}
      ${disclosure('diagnostics','诊断与配置','仅在排查问题时查看。','<p class="st-footnote">这里汇总设置和能力状态，不读取图片、聊天内容或浏览器会话。反馈是否附带诊断，由你主动选择。</p><dl class="st-diagnostics"><div><dt>截图收录</dt><dd>'+ (s.paused?'已暂停':'运行中') +'</dd></div><div><dt>边缘显示</dt><dd>'+ (s.hidden?'已隐藏':'开启') +'</dd></div><div><dt>配置</dt><dd>'+ (s.saveError?'有更改未保存':'已读取') +'</dd></div></dl><div class="st-page-links">'+action('重新读取配置','reloadConfiguration')+action('打开配置文件…','configuration')+'</div>',s)}`;
  }

  function render(page, state = {}) {
    page = pageNames[page] ? page : 'general';
    const s = settings(state);
    if (state.scenario === 'save-error') s.saveError = true;
    const [title, subtitle] = pageNames[page];
    const builders = {general, display, capture, motion, history, help};
    return `<div class="st-page" data-st-page="${page}"><header class="st-page-heading"><h2>${title}</h2><p>${subtitle}</p></header>${s.saveError && !['display','motion'].includes(page) ? '<div class="st-inline-notice st-save-error" role="status">'+icon('info',14)+'<span>这次更改尚未保存，原设置仍然保留。</span>'+action('重试','retry')+'</div>':''}${builders[page](s)}<div class="st-local-feedback" aria-live="polite" hidden></div></div>`;
  }

  const activeBindings = new WeakMap();

  function bind(container, state = {}, onChange = () => {}) {
    if (!container) return () => {};
    activeBindings.get(container)?.();
    const controller = new AbortController();
    const running = new Set();
    let s = settings(state);
    if (state.scenario === 'save-error') s.saveError = true;
    state.settings = s;
    const page = container.querySelector('[data-st-page]')?.dataset.stPage || 'general';
    const listen = (type, handler, opts = {}) => container.addEventListener(type,handler,{...opts,signal:controller.signal});
    const cleanup = () => {
      controller.abort();
      running.forEach(animation => animation.cancel());
      running.clear();
    };
    activeBindings.set(container, cleanup);
    const notify = extra => {
      state.settings = s;
      onChange({settings:s,...(extra || {})});
    };
    const redraw = extra => {
      state.settings = s;
      let scrollable = container;
      while (scrollable.parentElement && scrollable.scrollHeight <= scrollable.clientHeight) scrollable = scrollable.parentElement;
      const scrollTop = scrollable.scrollTop;
      container.innerHTML = render(page,state);
      bind(container,state,onChange);
      scrollable.scrollTop = scrollTop;
      onChange({settings:s,...(extra || {})});
    };
    const showNote = text => {
      const feedback = container.querySelector('.st-local-feedback');
      if (!feedback) return;
      feedback.textContent = text;
      feedback.hidden = false;
    };
    const refreshDraft = () => {
      const area = container.querySelector('[data-st-save-area]');
      if (area) {
        const dirty = Object.keys(s.draft).length > 0;
        area.classList.toggle('st-is-dirty',dirty || s.saveError);
        const label = area.querySelector('.st-save-message');
        if (label) label.textContent = s.saveError ? '这次更改尚未保存' : dirty ? '预览已更新，参数尚未应用' : '参数更改会先在这里预览';
        const apply = area.querySelector('[data-st-action="apply"]');
        const discard = area.querySelector('[data-st-action="discard"]');
        if (apply) apply.disabled = !dirty && !s.saveError;
        if (discard) discard.hidden = !dirty && !s.saveError;
      }
      const queue = container.querySelector('[data-st-mini-queue]');
      if (queue) {
        const count = Math.max(1,Math.min(10,Math.round(num(s,'visibleCountPreference'))));
        queue.innerHTML = Array.from({length:Math.min(count,5)},(_,i)=>sample(i)).join('');
        queue.style.setProperty('--st-hidden',Math.max(0,Math.min(.9,num(s,'hiddenFraction') / 100)));
        queue.style.setProperty('--st-row-gap',`${Math.max(1,Math.min(12,(num(s,'rowPitch')-42)*.18))}px`);
        const monitor = container.querySelector('.st-monitor');
        if (monitor) monitor.setAttribute('aria-label',`边缘位置预览，显示数量 ${count} 张`);
      }
      state.settings = s;
    };
    const editNumber = (key, raw, isSlider = false) => {
      s.draft[key] = raw;
      const number = container.querySelector(`[data-st-field="${key}"]`);
      const range = container.querySelector(`[data-st-range="${key}"]`);
      if (isSlider && number) number.value = raw;
      if (!isSlider && range && raw !== '' && Number.isFinite(Number(raw))) range.value = raw;
      refreshDraft();
    };
    const animate = async (element,keyframes,options) => {
      if (!element || controller.signal.aborted) return;
      const animation = element.animate(keyframes,options);
      running.add(animation);
      await animation.finished.catch(()=>{});
      running.delete(animation);
      return animation;
    };
    const play = async kind => {
      const preview = container.querySelector('[data-st-motion-preview]');
      if (!preview || preview.dataset.playing === 'true') return;
      preview.dataset.playing = 'true';
      const buttons = [...preview.querySelectorAll('button')];
      buttons.forEach(button=>button.disabled=true);
      const canvas = preview.querySelector('.st-motion-canvas');
      const queue = preview.querySelector('.st-motion-queue');
      const cards = [...queue.querySelectorAll('.st-sample')];
      const origin = preview.querySelector('.st-motion-origin');
      const status = preview.querySelector('[data-st-motion-state]');
      const reduced = s.reduceMotion || window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      cards.forEach(card=>{card.getAnimations().forEach(animation=>animation.cancel());card.style.opacity='1';card.style.visibility='visible';card.style.transform='';});
      queue.style.clipPath = '';
      status.textContent = kind==='arrival' ? '截图，自然来到边缘' : '开始附加，迅速收起';
      let flyer;
      try {
        if (kind==='arrival') {
          if (reduced || s.arrival==='none') {
            cards[0].style.opacity='0';
            await animate(cards[0],[{opacity:0},{opacity:1}],{duration:reduced?80:0,easing:'linear',fill:'forwards'});
          } else {
            const from = {x:canvas.clientWidth-90,y:canvas.clientHeight-69};
            const to = {x:34,y:31};
            cards[0].style.opacity='0';
            flyer = cards[0].cloneNode(true);
            flyer.style.cssText = `position:absolute;left:${from.x}px;top:${from.y}px;width:48px;height:34px;z-index:4;transform-origin:left center;pointer-events:none;`;
            canvas.appendChild(flyer);
            await animate(flyer,[
              {transform:'translate(0,0) scale(1.16) rotate(-2deg)',opacity:1,clipPath:'inset(0)',offset:0},
              {transform:`translate(${(to.x-from.x)*.55}px,${(to.y-from.y)*.74}px) scale(1.04) rotate(-1deg)`,opacity:1,clipPath:'inset(0)',offset:.52},
              {transform:`translate(${to.x-from.x}px,${to.y-from.y}px) scale(1) rotate(0deg)`,opacity:1,clipPath:'inset(0 0 0 25%)',offset:1}
            ],{duration:560,easing:'cubic-bezier(.22,.75,.28,1)',fill:'forwards'});
            if (!controller.signal.aborted) cards[0].style.opacity='1';
          }
          if (!controller.signal.aborted) status.textContent = reduced ? '静态呈现，保留原偏好' : s.arrival==='none' ? '立即出现，不播放飞行' : '收进边缘，随手可用';
        } else {
          if (reduced) {
            await animate(cards[0],[{opacity:1},{opacity:0}],{duration:Math.min(80,num(s,'swallowDuration')),easing:'linear',fill:'forwards'});
            if (!controller.signal.aborted) { cards[0].style.visibility='hidden'; cards[1].style.transform='translateY(-42px)'; cards[2].style.transform='translateY(-42px)'; }
          } else {
            await animate(cards[0],[{transform:'scale(1)'},{transform:'scale(.975)'}],{duration:num(s,'pressDuration'),easing:'ease-out',fill:'forwards'});
            if (controller.signal.aborted) return;
            await animate(cards[0],[{transform:'translateX(0) scale(.975)',opacity:1},{transform:'translateX(-52px) scale(.975)',opacity:1}],{duration:num(s,'swallowDuration'),easing:'cubic-bezier(.3,.85,.45,1)',fill:'forwards'});
            if (controller.signal.aborted) return;
            cards[0].style.visibility='hidden';
            await Promise.all(cards.slice(1).map(card=>animate(card,[{transform:'translateY(0)'},{transform:'translateY(-42px)'}],{duration:num(s,'shiftDuration'),easing:'cubic-bezier(.2,.75,.3,1)',fill:'forwards'})));
          }
          if (!controller.signal.aborted) status.textContent = '其余截图，安静补位';
        }
      } finally {
        flyer?.remove();
        if (origin) origin.style.display='none';
        if (!controller.signal.aborted) {
          preview.dataset.playing='false';
          buttons.forEach(button=>button.disabled=false);
        }
      }
    };

    listen('input',event=>{
      const input = event.target;
      if (!(input instanceof HTMLInputElement)) return;
      if (input.dataset.stField) editNumber(input.dataset.stField,input.value);
      if (input.dataset.stRange) editNumber(input.dataset.stRange,input.value,true);
      if (input.hasAttribute('data-st-archive')) {
        s.archiveDraft = input.value;
        state.settings = s;
        const bar = container.querySelector('.st-archive-save');
        if (bar) bar.hidden=false;
      }
    });
    listen('change',event=>{
      const input = event.target;
      if (!(input instanceof HTMLInputElement || input instanceof HTMLSelectElement)) return;
      if (input.dataset.stField || input.dataset.stRange || input.hasAttribute('data-st-archive')) { notify(); return; }
      const key = input.dataset.stKey;
      if (!key) return;
      if (key==='archivePreset') {
        s.archiveCustom = input.value==='custom';
        s.archiveDraft = s.archiveCustom ? String(s.archiveDraft ?? (s.archiveHours || 1.5)) : input.value;
        redraw(); return;
      }
      s[key] = input.type==='checkbox' ? input.checked : input.value;
      if (key==='display' && s.display!=='disconnected') s.displayDisconnected=false;
      redraw();
    });
    listen('toggle',event=>{
      const details = event.target;
      if (!(details instanceof HTMLDetailsElement) || !details.dataset.stGroup) return;
      const groups = new Set(s.openGroups);
      details.open ? groups.add(details.dataset.stGroup) : groups.delete(details.dataset.stGroup);
      s.openGroups = [...groups];
      state.settings = s;
    },{capture:true});
    listen('click',event=>{
      const button = event.target.closest('button');
      if (!button || !container.contains(button) || button.disabled) return;
      if (button.dataset.stAppearance) {
        s.appearance = button.dataset.stAppearance;
        state.appearance = s.appearance;
        redraw({appearance:s.appearance}); return;
      }
      if (button.dataset.stPlacement) { s.placement = button.dataset.stPlacement; redraw(); return; }
      if (button.dataset.stArrival) { s.arrival = button.dataset.stArrival; redraw(); return; }
      const command = button.dataset.stAction;
      if (!command) return;
      if (command==='playArrival' || command==='playSwallow') { void play(command==='playArrival'?'arrival':'swallow'); return; }
      if (command==='defaults') {
        const fields = page==='motion' ? motionFields : displayFields;
        fields.forEach(key=>{if(key!=='firstCenterFromTop' || s.placement===null)s.draft[key]=String(layoutDefaults[key]);});
        redraw(); return;
      }
      if (command==='discard') { s.draft={}; s.saveError=false; state.scenario=state.scenario==='save-error'?'default':state.scenario; redraw(); return; }
      if (command==='apply') {
        let invalid;
        for (const [key,raw] of Object.entries(s.draft)) {
          const spec = fieldInfo[key];
          if (!spec) continue;
          const number = Number(String(raw).replace(',','.'));
          if (String(raw).trim()==='' || !Number.isFinite(number) || number<spec[2] || (spec[3]!==null && number>spec[3]) || (positiveFields.has(key) && number<=0) || (key==='visibleCountPreference' && !Number.isInteger(number))) {invalid=key; break;}
        }
        if (invalid) {
          const spec = fieldInfo[invalid];
          const error = container.querySelector('.st-validation');
          if(error) error.textContent=positiveFields.has(invalid) ? `${spec[0]}应大于 0${spec[3]===null?'':`，且不超过 ${spec[3]}`} ${spec[1]}。` : `${spec[0]}应${spec[3]===null?'不小于 0':`为 ${spec[2]}–${spec[3]}`} ${spec[1]}${invalid==='visibleCountPreference'?'的整数':''}。`;
          container.querySelector(`[data-st-field="${invalid}"]`)?.focus();
          return;
        }
        Object.entries(s.draft).forEach(([key,raw])=>{if(fieldInfo[key])s.layout[key]=Number(String(raw).replace(',','.'));});
        s.draft={};s.saveError=false;
        if (state.scenario==='save-error') state.scenario='default';
        redraw({settingsSaved:true}); return;
      }
      if (command==='discardArchive') {s.archiveDraft=null;s.archiveCustom=!['0','1','8','24','72'].includes(String(s.archiveHours));redraw();return;}
      if (command==='applyArchive') {
        const hours=Number(String(s.archiveDraft ?? s.archiveHours).replace(',','.'));
        if (!Number.isFinite(hours) || hours<0 || String(s.archiveDraft ?? s.archiveHours).trim()==='') {showNote('请输入不小于 0 的小时数。');container.querySelector('[data-st-archive]')?.focus();return;}
        s.archiveHours=hours;s.archiveDraft=null;redraw({settingsSaved:true});return;
      }
      if (command==='retry') {s.saveError=false;if(state.scenario==='save-error')state.scenario='default';redraw({settingsSaved:true});return;}
      if (command==='storage') {s.storageMeasured=true;redraw();return;}
      if (command==='restoreDisplay') {s.displayDisconnected=false;s.display='external';redraw();return;}
      if (command==='recheck' || command==='reloadConfiguration') {
        showNote(command==='recheck'?'连接状态已在演示中重新检查。':'当前设置已重新读取；尚未应用的参数保持原样。');
        notify({settingsAction:command});return;
      }
      const details = {
        source:'在原生 App 中，此处打开系统截图保存位置。',
        sourceAccess:'允许 Riftlet 访问系统截图保存位置后，才会收录新截图。',
        automation:'在 macOS「隐私与安全性 → 自动化」中允许 Riftlet 控制 Chrome。',
        screenPermission:'在 macOS「隐私与安全性 → 屏幕与系统音频录制」中允许 Riftlet。',
        configuration:'兼容参数保留原值；原生 App 会打开当前配置文件。'
      };
      if(details[command])showNote(details[command]);
      notify({settingsAction:command});
    });
    refreshDraft();
    return cleanup;
  }
  window.RiftSettings = {render, bind, defaults, layoutDefaults, pageNames};
})();
