/* Quiet edge auxiliary-window design. Synthetic UI only; no native capabilities. */
(function (root) {
  'use strict';
  const escape = value => String(value == null ? '' : value).replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
  const attr = escape;
  const checked = value => value ? ' checked' : '';
  const selected = (a, b) => a === b ? ' selected' : '';
  const disabled = value => value ? ' disabled' : '';
  const icons = {
    general: '<path d="M3 6h14M3 14h14M7 3v6M13 11v6"/>',
    capture: '<path d="M3 6h4l2-2h4l2 2h2v11H3z"/><circle cx="10" cy="11" r="3"/>',
    display: '<path d="M4 2v16M7 4h10v11H7z"/>',
    privacy: '<path d="M10 2 3 5v5c0 4 7 8 7 8s7-4 7-8V5z"/><path d="m7 10 2 2 4-5"/>',
    about: '<circle cx="10" cy="10" r="8"/><path d="M10 9v6M10 5v1"/>',
    folder: '<path d="M2 5h6l2 2h8v10H2z"/>',
    chrome: '<circle cx="10" cy="10" r="8"/><circle cx="10" cy="10" r="3"/><path d="m10 7 7 0M7 10 4 4M12 13 8 18"/>',
    check: '<path d="m4 10 4 4 8-9"/>',
    history: '<path d="M3 6a8 8 0 1 1-1 7M2 2v5h5M10 6v5l3 2"/>',
    image: '<rect x="2" y="3" width="16" height="14" rx="2"/><circle cx="7" cy="8" r="1"/><path d="m3 15 5-4 3 2 3-5 3 7"/>',
    clock: '<circle cx="10" cy="10" r="8"/><path d="M10 5v6l4 2"/>',
    archive: '<path d="M3 6h14v12H3zM2 2h16v4H2zM8 10h4"/>',
    removed: '<path d="M3 5h14M8 2h4M5 5l1 13h8l1-13M8 8v7M12 8v7"/>',
    message: '<path d="M3 3h14v11H8l-5 4z"/>',
    arrow: '<path d="M4 10h12m-5-5 5 5-5 5"/>',
    chevron: '<path d="m8 5 5 5-5 5"/>',
    dot: '<circle cx="10" cy="10" r="3"/>'
  };
  function glyph(name) {
    return '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (icons[name] || icons.dot) + '</svg>';
  }
  function button(label, action, opts = {}) {
    return `<button class="button${opts.primary ? ' primary' : ''}${opts.quiet ? ' quiet' : ''}${opts.danger ? ' destructive' : ''}" data-action="${attr(action)}"${opts.id ? ` data-id="${attr(opts.id)}"` : ''}${disabled(opts.disabled)}>${escape(label)}</button>`;
  }
  function toggle(key, value, label) {
    return `<label class="native-switch"><input type="checkbox" data-setting="${attr(key)}" aria-label="${attr(label)}"${checked(value)}><span aria-hidden="true"></span></label>`;
  }
  function settingRow(title, description, control) {
    return `<div class="setting-row"><div class="setting-description"><div class="setting-name">${escape(title)}</div>${description ? `<p>${escape(description)}</p>` : ''}</div><div class="setting-control">${control}</div></div>`;
  }
  function titlebar(title, label) {
    return `<header class="native-titlebar"><div class="traffic"><button data-action="close-window" aria-label="关闭${attr(title)}" title="关闭"></button><i aria-hidden="true"></i><i aria-hidden="true"></i></div><span id="native-window-title">${escape(title)}</span><span class="native-build-label">${escape(label || 'Riftlet')}</span></header>`;
  }
  function frame(kind, title, body, label) {
    return `<section class="native-window ${attr(kind)}" role="dialog" aria-modal="false" aria-labelledby="native-window-title">${titlebar(title, label)}${body}</section>`;
  }
  function setup(state) {
    const step = Math.min(2, Math.max(0, Number(state.onboardingStep) || 0));
    const p = state.permissions || {};
    const steps = ['认识 Riftlet', '连接与权限', '开始使用'];
    const progress = `<div class="setup-progress" aria-label="第${step + 1}步，共3步">${steps.map((s, i) => `<span class="${i === step ? 'current' : i < step ? 'done' : ''}"><b>${i < step ? '✓' : i + 1}</b>${s}</span>`).join('')}</div>`;
    let content;
    if (step === 0) {
      content = `<div class="setup-intro"><span class="eyebrow">RIFTLET · 内部候选</span><h1>截图一次，点击一次</h1><p>截图自然地停在桌面边缘。<br>需要时，点一下，进入当前聊天草稿。</p></div><div class="setup-illustration" aria-hidden="true"><div class="setup-paper"><span>关于今天的一个想法</span><i></i><i></i><i></i></div><div class="setup-arrow">${glyph('arrow')}</div><div class="setup-rift"><span>1</span><i></i><b></b></div></div><div class="setup-principles"><div>${glyph('capture')}继续使用熟悉的系统截图</div><div>${glyph('message')}只附加图片，不替你发送消息</div><div>${glyph('privacy')}原截图保留，随时查看本地历史</div></div>`;
    } else if (step === 1) {
      content = `<div class="setup-intro"><h1>连接你已经在用的工具</h1><p>只在你主动操作时请求权限。</p></div><div class="permission-card"><span class="permission-icon">${glyph('folder')}</span><div><h2>系统截图位置</h2><p>${p.folder ? '已连接当前截图位置（模拟）' : '允许 Riftlet 收录系统保存的新截图。'}</p><small>桌面 · 本机保存</small></div>${button(p.folder ? '已连接' : '允许访问…', 'authorize-folder', { disabled: !!p.folder })}</div><div class="permission-card"><span class="permission-icon">${glyph('chrome')}</span><div><h2>Chrome 中的当前草稿</h2><p>${p.chrome ? '连接已允许（模拟）' : '允许自动化连接，再由原点击核实目标。'}</p><small>还需允许来自 Apple 事件的 JavaScript</small></div>${button(p.chrome ? '已允许' : '连接 Chrome…', 'authorize-chrome', { disabled: !!p.chrome })}</div><div class="soft-note">${glyph('about')}<span>权限允许不等于页面已经可用。没有可验证的当前草稿时，图片会留在原处。</span></div>`;
    } else {
      content = `<div class="setup-intro"><h1>下一张截图，从这里开始</h1><p>打开 Chrome 中的普通已有对话，<br>拍下一张新的截图，再点击边缘微图。</p></div><div class="setup-final"><div>${glyph('capture')}<strong>出现</strong><span>截图来到桌面边缘</span></div><div>${glyph('image')}<strong>点击</strong><span>附加到当前草稿</span></div><div>${glyph('check')}<strong>继续</strong><span>开始上传后迅速收起</span></div></div><div class="setup-support"><h2>这一版的支持范围</h2><p>Chrome · 中文 ChatGPT · 普通已有对话 · 符合范围的原始 PNG。</p><p>其他模式和安全重试仍未开放。旧的待核实截图不会再次附加。</p></div>`;
    }
    const next = step === 2 ? button('开始使用', 'close-window', { primary: true }) : button(step === 0 ? '继续' : '下一步', 'setup-next', { primary: true });
    return frame('setup', '开始使用', `<div class="native-body setup-body">${progress}${content}</div><footer class="native-footer"><span class="note">${step === 1 ? '权限在此原型中仅作模拟。' : '不发送消息，不删除原截图。'}</span><div class="row">${button('稍后设置', 'close-window', { quiet: true })}${next}</div></footer>`, '内部候选');
  }
  function settings(state) {
    const tab = state.settingsTab || 'general';
    const definitions = [['general', '运行状态'], ['capture', '截图入口'], ['display', '显示与动效'], ['privacy', '隐私与存储'], ['about', '关于与支持']];
    const nav = `<nav class="sidebar settings-sidebar" aria-label="设置页面"><div class="sidebar-product">Riftlet<span>让截图停在手边</span></div>${definitions.map(([id, title]) => `<button class="sidebar-item${tab === id ? ' selected' : ''}" data-action="settings-tab" data-tab="${id}"${tab === id ? ' aria-current="page"' : ''}>${glyph(id)}<span>${title}</span></button>`).join('')}<div class="sidebar-bottom"><span class="small-status-dot"></span>内部候选 · 设计模拟</div></nav>`;
    const visible = (state.assets || []).filter(a => a.visible).length;
    const unknown = (state.assets || []).filter(a => a.status === 'unknown').length;
    let content;
    if (tab === 'capture') {
      content = `<h1>截图入口</h1><p class="section-intro">熟悉的系统截图始终保留。靠近边缘，也可以直接开始。</p><div class="settings-group">${settingRow('默认截图模式', '只影响下一次展开；当前会话的槽位保持固定。', `<select data-setting="defaultMode" aria-label="默认截图模式"><option value="window"${selected(state.defaultMode, 'window')}>窗口</option><option value="region"${selected(state.defaultMode, 'region')}>区域</option><option value="full"${selected(state.defaultMode, 'full')}>全屏</option></select>`)}</div><div class="settings-entry-diagram" aria-hidden="true"><span class="entry-diagram-caption">固定的模式，移动的取消盖片</span><div><i>···</i><i>▣</i><i>⌗</i><i class="active">×</i></div></div><div class="soft-note">${glyph('about')}<span>相机线条会先于玻璃显现。截图后保持展开，点击当前模式的取消按钮，或按 Escape 退出。</span></div>`;
    } else if (tab === 'display') {
      content = `<h1>显示与动效</h1><p class="section-intro">动效只解释物体去哪里，不抢走注意力。</p><h2 class="settings-section-heading">截图入缝</h2><div class="arrival-choices" role="radiogroup" aria-label="截图入缝动效"><label class="arrival-option${state.arrival === 'none' ? ' selected' : ''}"><input type="radio" name="arrival" data-setting="arrival" value="none"${checked(state.arrival === 'none')}><span class="arrival-mini none" aria-hidden="true"><i></i><b></b></span><strong>无</strong><small>直接出现在裂缝中</small></label><label class="arrival-option${state.arrival !== 'none' ? ' selected' : ''}"><input type="radio" name="arrival" data-setting="arrival" value="magnet"${checked(state.arrival !== 'none')}><span class="arrival-mini magnet" aria-hidden="true"><i></i><b></b></span><strong>磁力吸引</strong><small>从源头收束，轻轻入缝</small></label></div><p class="note arrival-note">仅影响截图来到裂缝的过程。上传开始后的快速吞噬独立保留。</p><div class="settings-group">${settingRow('外观', '与桌面和窗口保持一致。', `<select data-setting="theme" aria-label="外观"><option value="light"${selected(state.theme, 'light')}>浅色</option><option value="dark"${selected(state.theme, 'dark')}>深色</option></select>`)}${settingRow('减少动态效果', '取消空间位移，以短淡变表达状态。', toggle('reduceMotion', state.reduceMotion, '减少动态效果'))}${settingRow('减少透明度', '使用清晰、不透明的表面。', toggle('reduceTransparency', state.reduceTransparency, '减少透明度'))}${settingRow('提高对比度', '强化边界与文字。', toggle('highContrast', state.highContrast, '提高对比度'))}</div>`;
    } else if (tab === 'privacy') {
      content = `<h1>隐私与存储</h1><p class="section-intro">图片留在你的 Mac。收起、移除和归档，都不等于删除。</p><div class="settings-group">${settingRow('闲置截图归档', '归档到内部历史；悬停、按下和操作中不会被移走。', `<select data-setting="archiveHours" aria-label="闲置截图归档"><option value="24"${selected(String(state.archiveHours == null ? 24 : state.archiveHours), '24')}>24 小时</option><option value="0"${selected(String(state.archiveHours), '0')}>关闭</option></select>`)}</div><div class="privacy-facts"><div>${glyph('folder')}<span><strong>原始系统截图保留</strong><small>不会因为附加、移除或隐藏而删除原文件。</small></span></div><div>${glyph('privacy')}<span><strong>待核实记录不重传</strong><small>原图、原操作和审计继续保留。</small></span></div><div>${glyph('message')}<span><strong>反馈由你主动提交</strong><small>不会自动附带截图、聊天或浏览器资料。</small></span></div></div><div class="settings-local-storage"><span>本机存储</span><strong>尚未检查</strong><p class="note">原型不读取磁盘。正式 App 按需检查逻辑文件用量，不自动清理数据。</p></div>`;
    } else if (tab === 'about') {
      content = `<h1>关于 Riftlet</h1><p class="section-intro">让截图自然地停留在桌面边缘，<br>通过一次点击进入当前聊天草稿。</p><div class="about-version"><span>内部候选</span><strong>产品设计预览</strong><small>依据正式工程 1920e056 · 新视觉待批准</small></div><h2 class="settings-section-heading">准确的当前范围</h2><p class="about-scope">Chrome 中文 ChatGPT 的普通已有对话；原始单帧、非交错 RGBA8 PNG，≤8 MiB，≤16,777,216 像素。</p><p class="note">普通生产上传、安全失败与重试、反馈云端仍未开放。无 ACK 冷首击和人工物理鼠标完整验收尚未完成。</p><div class="about-links">${button('反馈与建议…', 'open-feedback')}${button('查看内部历史', 'open-history', { quiet: true })}</div>`;
    } else {
      content = `<h1>运行状态</h1><p class="section-intro">一眼知道正在发生什么，也知道什么还没有发生。</p><div class="status-summary"><span class="status-glyph${state.paused ? ' paused' : ''}">${glyph(state.paused ? 'clock' : 'check')}</span><div><strong>${state.paused ? '收录已暂停' : '正在收录新截图'}</strong><span>${state.hidden ? '裂缝已隐藏' : visible ? `边缘有 ${visible} 张截图` : '没有可见截图，裂缝已退场'}</span></div><span class="candidate-tag">内部候选</span></div><div class="settings-group">${settingRow('暂停收录', '只暂停新截图，已有图片保留。', toggle('paused', state.paused, '暂停收录'))}${settingRow('隐藏裂缝', '只影响显示，收录可继续。', toggle('hidden', state.hidden, '隐藏裂缝'))}</div><div class="status-detail-row"><span>截图位置</span><strong>桌面</strong><small>模拟来源</small></div><div class="status-detail-row"><span>附件能力</span><strong>Chrome · 普通已有对话</strong></div><div class="status-detail-row"><span>待核实</span><strong>${unknown ? `${unknown} 张 · 不会自动再次附加` : '暂无待核实截图'}</strong></div><div class="settings-bottom-actions">${button('打开内部历史', 'open-history')}${button('反馈与建议…', 'open-feedback', { quiet: true })}</div><p class="note">这是设计原型，状态不代表这台 Mac 的真实权限或连接。</p>`;
    }
    return frame('settings', '设置与运行状态', `<div class="native-body split-body">${nav}<section class="settings-content">${content}</section></div>`);
  }
  const labels = { available: '待附加', waiting: '等待附加', uploading: '正在附加', unknown: '结果待核实', succeeded: '已附加', archived: '已归档', removed: '已移除' };
  function date(value) {
    const d = new Date(value || Date.now());
    return Number.isNaN(d.getTime()) ? '合成截图' : new Intl.DateTimeFormat('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false }).format(d);
  }
  function history(state, artURI) {
    const assets = state.assets || [];
    const filter = state.historyFilter || 'all';
    const q = String(state.historyQuery || '').trim().toLocaleLowerCase();
    const match = (a, f) => f === 'all' || (f === 'unknown' ? ['unknown', 'waiting', 'uploading'].includes(a.status) : a.status === f);
    const list = assets.filter(a => match(a, filter) && (!q || `${a.id} ${a.number} ${labels[a.status] || a.status} ${date(a.createdAt)}`.toLocaleLowerCase().includes(q))).slice().reverse();
    const chosen = list.find(a => a.id === state.selectedHistoryId) || list[0];
    const filters = [['all', '全部截图', 'image'], ['unknown', '待核实', 'clock'], ['succeeded', '已附加', 'check'], ['archived', '已归档', 'archive'], ['removed', '已移除', 'removed']];
    const sidebar = `<nav class="sidebar history-sidebar" aria-label="历史分类"><span class="sidebar-heading">本机截图</span>${filters.map(([id, name, ic]) => `<button class="sidebar-item${filter === id ? ' selected' : ''}" data-action="history-filter" data-filter="${id}"${filter === id ? ' aria-current="page"' : ''}>${glyph(ic)}<span>${name}</span><small>${assets.filter(a => match(a, id)).length}</small></button>`).join('')}<div class="sidebar-bottom">原图始终保留</div></nav>`;
    const listHTML = `<section class="history-list-pane"><div class="history-search"><input type="search" id="history-search" placeholder="搜索本页" aria-label="搜索当前历史页" value="${attr(state.historyQuery || '')}"></div><div class="history-list" role="listbox" aria-label="本机截图记录">${list.length ? list.map(a => `<button class="history-list-item${chosen && chosen.id === a.id ? ' selected' : ''}" role="option" aria-selected="${chosen && chosen.id === a.id ? 'true' : 'false'}" data-action="history-select" data-id="${attr(a.id)}"><span class="history-thumb"><img src="${attr(artURI(a.kind))}" alt=""></span><span class="history-list-copy"><strong>截图 ${escape(a.number)}</strong><small>${escape(date(a.createdAt))}</small><span class="history-state ${attr(a.status)}">${escape(labels[a.status] || '本地记录')}</span></span></button>`).join('') : '<div class="history-empty">没有符合条件的截图。<span>换个筛选条件，或拍一张新的。</span></div>'}</div><div class="history-list-foot">${list.length} 条 · 本页最多 200 条</div></section>`;
    let detail = '<section class="history-detail empty-detail">' + glyph('image') + '<h2>截图会留在这里</h2><p>附加、归档或移除后，<br>仍可回到本地历史查看。</p></section>';
    if (chosen) {
      const a = chosen;
      const canRestore = ['archived', 'removed'].includes(a.status) && !a.started;
      const reason = a.status === 'unknown' ? '附加结果暂不能确认。图片与原操作保留，不会自动再次附加，也不能从这里解锁重传。' : a.status === 'succeeded' ? '已记录独立完成结果。Riftlet 不会发送聊天消息；附件保留在原来的草稿中。' : a.status === 'waiting' ? '原选择已接收，仍在等待。这张图片尚未开始上传。' : a.status === 'uploading' ? '已开始附加，正在后台等待独立完成结果。图片离开边缘不等于已经上传成功。' : a.status === 'archived' ? '这张截图已从边缘归档。原图保留，放回裂缝不会立即上传。' : a.status === 'removed' ? '只从可见队列移除了这张图。原图和已有聊天附件没有删除。' : '这张截图在本机等待使用。点击边缘微图，才会尝试附加到当前草稿。';
      detail = `<section class="history-detail"><div class="history-preview"><img src="${attr(artURI(a.kind))}" alt="截图${attr(a.number)}完整合成预览"></div><div class="history-detail-heading"><h2>截图 ${escape(a.number)}</h2><span class="history-state ${attr(a.status)}">${escape(labels[a.status] || '本地记录')}</span></div><p class="history-detail-reason">${escape(reason)}</p><dl class="image-metadata"><div><dt>尺寸</dt><dd>${escape(a.width)} × ${escape(a.height)}</dd></div><div><dt>时间</dt><dd>${escape(date(a.createdAt))}</dd></div><div><dt>格式</dt><dd>PNG · 合成样本</dd></div></dl><div class="history-detail-actions">${button('在 Finder 中显示', 'history-reveal', { id: a.id })}${canRestore ? button('放回裂缝', 'history-restore', { id: a.id, primary: true }) : ''}</div><p class="note history-simulation-note">原型只展示合成数据；不会访问 Finder。</p></section>`;
    }
    return frame('history', '截图历史', `<div class="native-body history-body">${sidebar}${listHTML}${detail}</div>`);
  }
  function feedback(state) {
    const draft = String(state.feedbackDraft || '');
    const reports = state.feedbackReports || [];
    const count = Array.from(draft).length;
    const recordHTML = reports.map(r => `<article class="feedback-record"><div class="feedback-record-head"><strong>RF-${escape(String(r.id).replace(/^RF-/, ''))}</strong><span class="feedback-record-status">${r.status === 'cancelled' ? '已取消待发送' : '待发送 · 仅保存在本机'}</span></div><p>${escape(r.text)}</p><div class="feedback-record-actions">${r.status === 'cancelled' ? button('移除本机正文…', 'feedback-delete', { id: r.id, quiet: true }) : button('取消待发送', 'feedback-cancel', { id: r.id, quiet: true })}</div></article>`).join('');
    const body = `<div class="native-body feedback-body"><div class="feedback-heading"><div><h1>哪里不顺手？</h1><p>也欢迎告诉我们，你希望它变得怎样。</p></div><span class="local-only-badge">${glyph('privacy')}仅保存在本机</span></div><div class="feedback-editor"><div class="feedback-editor-labelrow"><label class="feedback-input-label" for="feedback-draft">发生了什么？你原本希望怎样？</label><select data-setting="feedbackKind" aria-label="反馈类型"><option value="problem"${selected(state.feedbackKind || 'problem', 'problem')}>遇到问题</option><option value="suggestion"${selected(state.feedbackKind, 'suggestion')}>改进建议</option></select></div><textarea id="feedback-draft" rows="6" placeholder="例如：点了第三张截图，我没有看清它是否开始附加……" spellcheck="false">${escape(draft)}</textarea><div class="feedback-editor-foot"><span id="feedback-save-status">草稿会自动保存，关闭不会发送。</span><span id="feedback-char-count"${count > 4000 ? ' class="character-limit"' : ''}>${count.toLocaleString('zh-CN')} / 4,000</span></div></div><div class="feedback-consent"><label><input id="feedback-diagnostics" type="checkbox"${checked(state.feedbackIncludeDiagnostics)}>附带技术诊断<span>仅本次</span></label><details class="diagnostic-preview"><summary>预览诊断</summary><p>${state.feedbackIncludeDiagnostics ? '模拟白名单：应用版本、收录/队列状态数量和有限错误类型。未包含截图、聊天、剪贴板、完整路径或浏览器资料。' : '尚未勾选，不附带诊断。勾选后冻结当时的白名单快照，不追加后来的事件。'}</p></details></div><div class="feedback-local-status">${glyph('clock')}<span><strong>接收服务尚未配置</strong><small>可以保存待发送；当前不会上传或创建云端记录。</small></span></div><details class="feedback-records"><summary><span>本机反馈记录</span><span>${reports.length} 条${glyph('chevron')}</span></summary><div>${recordHTML || '<p class="note feedback-empty">尚无待发送记录。保存草稿不会自动生成提交。</p>'}</div></details><p class="feedback-privacy note">仅提交你填写的文字及主动勾选的诊断。不会自动附带图片或聊天内容；请勿填写密码等秘密。</p></div><footer class="native-footer feedback-footer"><div class="row">${button('清空草稿', 'feedback-clear-draft', { quiet: true, disabled: !draft })}</div><div class="row">${button('保存并关闭', 'close-window')}${button('保存待发送', 'feedback-save', { primary: true, disabled: !draft.trim() || count > 4000 })}</div></footer>`;
    return frame('feedback', '反馈与建议', body);
  }
  root.RiftletWindows = {
    render: function (kind, state, icon, artURI) {
      state = state || {};
      const art = typeof artURI === 'function' ? artURI : () => '';
      if (kind === 'setup') return setup(state);
      if (kind === 'settings') return settings(state);
      if (kind === 'history') return history(state, art);
      if (kind === 'feedback') return feedback(state);
      return '';
    }
  };
})(window);
