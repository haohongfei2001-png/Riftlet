(() => {
  'use strict';

  // This is a wholly synthetic, browser-local illustration. It never accesses
  // local screenshots, clipboard, ChatGPT sessions, network uploads, or chat send.
  const copy = {
    zh: {
      skip: '跳转到正文', navExperience: '体验', navIdea: '设计理念', navFuture: '未来', navTry: '体验一下',
      heroEyebrow: '一个藏在屏幕边缘的小空间', heroTitle: '不必找。<br><em>就在那儿。</em>',
      heroDesc: '用系统原来的方式截图。那张图在屏幕边缘露出小小一角。记住它的位置，点一下，图片便进入正在使用的对话草稿。',
      heroButton: '亲手试一下', heroSecondary: '为什么要这么小', heroNote: '产品仍在设计中 · 下面是可操作的模拟体验',
      heroArtNote: '只露出一点。<br>就足以想起来。', heroBottom: '截图之后，它始终有一个位置。',
      manifestoTitle: '先记得<span class="serif-accent">位置。</span><br>再看见内容。',
      manifestoDesc: '刚刚截了什么，你本来就知道。你需要的不是另一张清晰的预览卡，也不是给每个东西取名字。它只要在熟悉的位置，就够了。',
      manifestoFoot: '空间记忆 ＞ 内容轮廓 ＞ 文件名称',
      experienceTitle: '这一点点空间，<br><em>真的能用。</em>',
      experienceDesc: '这是一段可点击的离线演示。先添加一张模拟截图，再点屏幕右侧的小片段；它会进入草稿。全过程不会发送任何消息。',
      frameTop: '一块普通的桌面 · 模拟', mockAppTitle: '聊天草稿', mockContent: '正在写的事情，不需要被打断。',
      draftLabel: '模拟草稿文字', draftNote: '文字保留 · 只附加不发送', demoTag: '一条边缘，几个位置。',
      addShot: '模拟截一张图', resetDemo: '重置', demoModeLabel: '下一次点击的结果', outcomeReady: '确认成功', outcomeFailed: '明确失败', outcomeUnknown: '结果未知',
      statusInitial: '点击右侧缩略图，或再添加一张模拟截图。',
      demoDisclaimer: '演示使用合成图像与本地脚本，不会读取系统截图、连接 ChatGPT 或上传真实文件。Riftlet 目前仍未发布。',
      twoTitle: '它需要你做的，<br><em>只有两件事。</em>',
      step1Title: '照常截图。', step1Desc: '使用系统原本的截图方式。不用学习新的快捷键，也不用打开另一个截图软件。',
      step2Title: '点击它。', step2Desc: '图片进入你正在使用的对话草稿；确认准备就绪后，才从裂缝中消失。不会替你发送消息。',
      futureTitle: '从截图开始。<br><em>不止于截图。</em>',
      futureDesc: '第一步是让 Mac 上的截图变得顺手。以后，这条熟悉的边缘也可能容纳复制的文字与图片，并走向 Windows 与更多应用。空间记忆，始终是第一位。',
      tagScreenshot: '截图 · 首先探索', tagClipboard: '剪贴板 · 未来方向', tagWindows: 'Windows · 未来方向',
      closingTitle: '有些好工具，<br>不需要占据你的注意。',
      closingDesc: 'Riftlet 目前处于设计和技术验证阶段。正式下载尚未开放。在发布之前，这里会继续展示它真正的样子。',
      githubButton: '查看开发进展', footerStatus: '独立桌面软件 · 设计中 · 尚未开放下载',
      initialDraft: '请帮我看看这几张截图。',
      statusAdded: (n) => `模拟截图 ${n} 已加入边缘。你可以直接点击它。`,
      statusFull: '演示区域已满；重置后可重新体验。',
      statusQueued: (n) => `截图 ${n} 已进入演示队列。其他位置暂时不变。`,
      statusBusy: (n) => `截图 ${n} 正在准备模拟附件；尚未确认就绪。`,
      statusReady: (n) => `截图 ${n} 已模拟进入草稿并确认就绪，现从裂缝中消失。没有发送消息。`,
      statusFailed: (n) => `截图 ${n} 模拟明确失败，回到原位置；可再次点击。`,
      statusUnknown: (n) => `截图 ${n} 的模拟结果未知，仍保留在原位；不会自动重试。`,
      statusUnknownRetry: (n) => `截图 ${n} 仍是未知状态；此演示不盲目重复附加。请重置。`,
      statusRemoved: (n) => `从模拟草稿移除了截图 ${n}。不会自动重复附加。`,
      statusReset: '模拟已重置。点击右侧缩略图开始。',
      attachmentName: (n) => `截图 ${n}`, attachmentReady: '已就绪 · 模拟', attachmentPending: '准备中 · 模拟',
      shotLabel: (n,s) => `模拟截图 ${n}，${s === 'unknown' ? '状态未知，不重复上传' : s === 'failed' ? '上次失败，点击重试' : '点击附加到模拟草稿'}`,
      removeLabel: (n) => `移除模拟草稿中的截图 ${n}`,
      title: 'Riftlet — 不必找。就在那儿。',
      description: 'Riftlet 是一个关于空间记忆的微小桌面工具。截图留在屏幕边缘，记住位置，轻点取用。设计中，尚未发布。'
    },
    en: {
      skip: 'Skip to content', navExperience: 'Experience', navIdea: 'The idea', navFuture: 'Beyond', navTry: 'Try it',
      heroEyebrow: 'A little space at the edge of your screen', heroTitle: 'No searching.<br><em>Just there.</em>',
      heroDesc: 'Take a screenshot the way you always do. A little piece stays at the edge of your screen. Remember where it is, click once, and it enters your current chat draft.',
      heroButton: 'Feel how it works', heroSecondary: 'Why so small?', heroNote: 'In design · The interactive experience below is a simulation',
      heroArtNote: 'Just a sliver.<br>Enough to remember.', heroBottom: 'Something you captured now has a place.',
      manifestoTitle: 'Remember <span class="serif-accent">where.</span><br>Then remember what.',
      manifestoDesc: 'You already know what you just captured. You don’t need another large preview, a filename, or a label. Just a familiar place where it quietly stays.',
      manifestoFoot: 'Spatial memory > content silhouette > filename',
      experienceTitle: 'A tiny place.<br><em>A real gesture.</em>',
      experienceDesc: 'Try this interactive, offline simulation. Add a sample screenshot, then click its tiny sliver at the right edge. It appears in the draft. Nothing is sent.',
      frameTop: 'An ordinary desktop · simulated', mockAppTitle: 'Chat draft', mockContent: 'Keep doing what you were doing.',
      draftLabel: 'Editable simulated draft', draftNote: 'Your text stays · nothing is sent', demoTag: 'One edge. A few familiar places.',
      addShot: 'Capture a sample', resetDemo: 'Reset', demoModeLabel: 'Next click outcome', outcomeReady: 'Ready', outcomeFailed: 'Fail', outcomeUnknown: 'Unknown',
      statusInitial: 'Click a tiny screenshot on the right, or add another sample.',
      demoDisclaimer: 'This demo uses synthetic art and local scripts only. It does not capture your screen, connect to ChatGPT, or upload files. Riftlet has not launched.',
      twoTitle: 'Two movements.<br><em>Nothing more.</em>',
      step1Title: 'Take your screenshot.', step1Desc: 'Keep using your computer’s own screenshot tools. No new shortcut to learn, no separate capture app to open.',
      step2Title: 'Click where it is.', step2Desc: 'It is added to the intended chat draft, then swallowed only when the attachment is confirmed ready. Your message is never sent for you.',
      futureTitle: 'It starts with<br><em>screenshots.</em>',
      futureDesc: 'First: a better way to reuse screenshots on Mac. Someday, the same familiar edge may hold copied text and images, and travel to Windows and more apps. Spatial memory comes first.',
      tagScreenshot: 'Screenshots · first focus', tagClipboard: 'Clipboard · future direction', tagWindows: 'Windows · future direction',
      closingTitle: 'Good tools don’t need<br>all your attention.',
      closingDesc: 'Riftlet is currently in design and technical validation. There is no app to download yet. This place will show the real thing as it takes shape.',
      githubButton: 'Follow the project', footerStatus: 'Independent desktop software · in design · not yet available',
      initialDraft: 'Can you compare these screenshots?',
      statusAdded: (n) => `Sample screenshot ${n} appeared at the edge. Click it directly.`,
      statusFull: 'The small demo edge is full. Reset to start again.',
      statusQueued: (n) => `Screenshot ${n} is queued in this demo. Positions remain steady.`,
      statusBusy: (n) => `Preparing simulated attachment ${n}; not confirmed ready yet.`,
      statusReady: (n) => `Screenshot ${n} is ready in the simulated draft and has been swallowed. Nothing was sent.`,
      statusFailed: (n) => `Screenshot ${n} failed in the simulation. It returned to its place; click to try again.`,
      statusUnknown: (n) => `Screenshot ${n} has an unknown simulated outcome. It stays in place and will not be sent again automatically.`,
      statusUnknownRetry: (n) => `Screenshot ${n} is unresolved. This demo does not blindly re-attach it. Reset to continue.`,
      statusRemoved: (n) => `Removed screenshot ${n} from the simulated draft. It will not be blindly attached again.`,
      statusReset: 'Demo reset. Click a tiny screenshot on the right.',
      attachmentName: (n) => `Image ${n}`, attachmentReady: 'Ready · demo', attachmentPending: 'Preparing · demo',
      shotLabel: (n,s) => `Sample screenshot ${n}; ${s === 'unknown' ? 'unknown result, no repeated attachment' : s === 'failed' ? 'previously failed, click to retry' : 'click to attach to sample draft'}`,
      removeLabel: (n) => `Remove image ${n} from the simulated draft`,
      title: 'Riftlet — No searching. Just there.',
      description: 'A tiny space at the edge of your screen, built around spatial memory. Screenshot, remember the place, and click to use. In design, not yet released.'
    }
  };
  const doc = document;
  const itemsRoot = doc.getElementById('seam-items');
  const seamZone = doc.getElementById('seam-zone');
  const attachmentsRoot = doc.getElementById('attachments');
  const statusEl = doc.getElementById('demo-status');
  const draft = doc.getElementById('draft');
  const modeEl = doc.getElementById('demo-mode');
  let lang = 'zh', images = [], attempts = [], active = false, hovered = false, needsCompact = false, epoch = 0, nextId = 4;
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  const art = [
    `<svg viewBox="0 0 70 48" aria-hidden="true"><rect width="70" height="48" fill="#91B9A9"/><circle cx="48" cy="13" r="11" fill="#E8D1A5"/><path d="M0 45 25 15 45 36 61 25 70 36v12H0" fill="#477B6B"/></svg>`,
    `<svg viewBox="0 0 70 48" aria-hidden="true"><rect width="70" height="48" fill="#E9B998"/><path d="M0 39Q23 6 47 30T70 12v36H0" fill="#AB6D65"/><circle cx="55" cy="12" r="6" fill="#F8E4C1"/></svg>`,
    `<svg viewBox="0 0 70 48" aria-hidden="true"><rect width="70" height="48" fill="#C3D3E6"/><rect x="9" y="7" width="52" height="34" rx="2" fill="#FCFAF2"/><path d="M15 15h28M15 22h39M15 29h20" stroke="#9BAFA5" stroke-width="3"/></svg>`,
    `<svg viewBox="0 0 70 48" aria-hidden="true"><rect width="70" height="48" fill="#D8D8B6"/><rect x="10" y="8" width="50" height="30" fill="#7BA08C"/><circle cx="30" cy="19" r="9" fill="#E2B08D"/><path d="M0 45 30 31 70 43v5H0" fill="#3C7266"/></svg>`
  ];
  function tr(k, ...args) { const val = copy[lang][k]; return typeof val === 'function' ? val(...args) : val; }
  function speak(message) { statusEl.textContent = message; }
  function applyLanguage(value) {
    const prev = tr('initialDraft');
    lang = value === 'en' ? 'en' : 'zh';
    doc.documentElement.lang = lang === 'en' ? 'en' : 'zh-CN';
    for (const el of doc.querySelectorAll('[data-t]')) el.textContent = tr(el.dataset.t);
    for (const el of doc.querySelectorAll('[data-t-html]')) el.innerHTML = tr(el.dataset.tHtml);
    const sw = doc.getElementById('lang-switch');
    sw.textContent = lang === 'zh' ? 'EN' : '中文';
    sw.setAttribute('aria-label', lang === 'zh' ? 'Switch to English' : '切换为中文');
    doc.title = tr('title');
    doc.querySelector('meta[name="description"]').content = tr('description');
    if (draft.value === prev || draft.dataset.untouched === 'true') { draft.value = tr('initialDraft'); draft.dataset.untouched = 'true'; }
    refreshShotLabels();
    speak(tr('statusInitial'));
  }
  function refreshShotLabels() {
    for (const s of images) s.node?.setAttribute('aria-label', tr('shotLabel', s.id, s.state));
  }
  function makeImage(id, slot) { return { id, slot, state: 'idle', node: null, art: art[(id - 1) % art.length] }; }
  function renderShots() {
    itemsRoot.replaceChildren();
    for (const s of images) {
      if (s.state === 'done') continue;
      const btn = doc.createElement('button');
      btn.className = `shot-button${s.state === 'pending' || s.state === 'queued' ? ' pending' : ''}${s.state === 'unknown' ? ' unknown' : ''}${s.state === 'failed' ? ' failed' : ''}`;
      btn.type = 'button';
      btn.style.setProperty('--row-top', `${s.slot * 53}px`);
      btn.style.setProperty('--thumb-width', `${s.id % 3 === 0 ? 28 : 47}px`);
      btn.style.setProperty('--thumb-height', `${s.id % 3 === 0 ? 42 : 31}px`);
      btn.setAttribute('aria-label', tr('shotLabel', s.id, s.state));
      btn.innerHTML = `<span class="shot-window"><span class="shot-art">${s.art}</span></span><span class="shot-number">${s.id}</span>`;
      btn.addEventListener('click', () => request(s));
      s.node = btn;
      itemsRoot.appendChild(btn);
    }
  }
  function reset() {
    epoch += 1;
    images = [makeImage(1,0),makeImage(2,1),makeImage(3,2)];
    attempts = []; active = false; hovered = false; needsCompact = false; nextId = 4;
    attachmentsRoot.replaceChildren();
    renderShots(); speak(tr('statusReset'));
  }
  function compact() {
    if (!needsCompact || hovered) return;
    images = images.filter(s => s.state !== 'done');
    images.forEach((s,i) => { s.slot = i; if (s.node) s.node.style.setProperty('--row-top', `${i * 53}px`); });
    needsCompact = false;
  }
  function addShot() {
    compact();
    const n = images.filter(s => s.state !== 'done').length;
    if (n >= 6) { speak(tr('statusFull')); return; }
    const nextSlot = images.reduce((max, item) => item.state === 'done' ? max : Math.max(max, item.slot + 1), 0);
    const s = makeImage(nextId++, nextSlot);
    images.push(s); renderShots(); speak(tr('statusAdded', s.id));
  }
  function request(s) {
    if (s.state === 'unknown') { speak(tr('statusUnknownRetry',s.id)); return; }
    if (['queued','pending','done'].includes(s.state)) return;
    const attempt = { s, outcome: modeEl.value, epoch };
    s.state = 'queued';
    s.node.className = 'shot-button pending';
    s.node.setAttribute('aria-busy','true');
    attempts.push(attempt);
    speak(tr('statusQueued',s.id));
    run();
  }
  function makeAttachment(s) {
    const chip = doc.createElement('div'); chip.className = 'attachment-card';
    const icon = doc.createElement('span'); icon.innerHTML = s.art; chip.appendChild(icon);
    const label = doc.createElement('span'); label.textContent = tr('attachmentPending'); chip.appendChild(label);
    const remove = doc.createElement('button'); remove.type = 'button'; remove.textContent = '×'; remove.setAttribute('aria-label', tr('removeLabel',s.id));
    remove.addEventListener('click', () => { chip.remove(); speak(tr('statusRemoved',s.id)); });
    chip.appendChild(remove); attachmentsRoot.appendChild(chip);
    return { chip, label };
  }
  async function run() {
    if (active || !attempts.length) return;
    active = true;
    const { s, outcome, epoch: startEpoch } = attempts.shift();
    s.state='pending'; speak(tr('statusBusy',s.id));
    await wait(650);
    if (startEpoch !== epoch) return;
    let result = null;
    if (outcome === 'ready') result = makeAttachment(s);
    await wait(800);
    if (startEpoch !== epoch) return;
    s.node?.removeAttribute('aria-busy');
    s.node?.classList.remove('pending');
    if (outcome === 'ready') {
      result.label.textContent = tr('attachmentReady');
      s.state='done'; s.node?.classList.add('swallowed');
      s.node?.setAttribute('aria-label', tr('shotLabel',s.id,s.state));
      s.node?.setAttribute('tabindex','-1');
      speak(tr('statusReady',s.id));
      needsCompact = true;
      await wait(290);
      if (startEpoch !== epoch) return;
      s.node?.remove();
      compact();
    } else if (outcome === 'failed') {
      s.state = 'failed'; s.node?.classList.add('failed');
      s.node?.setAttribute('aria-label',tr('shotLabel',s.id,s.state));
      speak(tr('statusFailed',s.id));
    } else {
      s.state = 'unknown'; s.node?.classList.add('unknown');
      s.node?.setAttribute('aria-label',tr('shotLabel',s.id,s.state));
      speak(tr('statusUnknown',s.id));
    }
    active = false; run();
  }
  seamZone.addEventListener('pointerenter', () => hovered = true);
  seamZone.addEventListener('pointerleave', () => { hovered = false; compact(); });
  seamZone.addEventListener('focusin', () => hovered = true);
  seamZone.addEventListener('focusout', () => {
    requestAnimationFrame(() => { if (!seamZone.contains(doc.activeElement)) { hovered = false; compact(); } });
  });
  doc.getElementById('add-shot').addEventListener('click',addShot);
  doc.getElementById('reset-demo').addEventListener('click',reset);
  doc.getElementById('lang-switch').addEventListener('click',() => applyLanguage(lang === 'zh' ? 'en' : 'zh'));
  draft.dataset.untouched = 'true';
  draft.addEventListener('input', () => draft.dataset.untouched = 'false');
  reset();
  // Language is deliberately not inferred from location, stored, or sent to any server.
  applyLanguage('zh');
})();

