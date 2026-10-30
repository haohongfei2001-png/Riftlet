(() => {
  'use strict';
  const $ = (s, root = document) => root.querySelector(s);
  const $$ = (s, root = document) => Array.from(root.querySelectorAll(s));
  const asset = name => window.RIFTLET_ASSETS?.[name] || 'website-assets/' + name;
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const sceneData = {
    design: { file: 'glass-study.png', width: 1448, height: 1086, label: ['色彩笔记', 'Colour notes'], title: 'A study in light.', alt: ['青绿弧形玻璃与珊瑚色玻璃球的原创静物', 'An original still life of teal glass and a coral glass sphere'], draft: ['这组颜色，为什么看起来这么轻盈？', 'What makes these colours feel so light?'] },
    code: { file: 'error.svg', width: 400, height: 270, label: ['一个小问题', 'A little problem'], title: 'One small fix.', alt: ['合成的 JavaScript 报错示例', 'An illustrative JavaScript error'], draft: ['这个报错，该从哪里开始排查？', 'Where should I start with this error?'] },
    reading: { file: 'reading.svg', width: 400, height: 520, label: ['阅读摘记', 'Reading notes'], title: 'A thought to keep.', alt: ['泰勒展开与导数的阅读摘记示例', 'Illustrative reading notes on Taylor expansion'], draft: ['这一行，为什么能推出下一行？', 'How does this line lead to the next?'] }
  };
  const copy = {
    idle: ['点一下右侧微图，试试这一小步。', 'Tap a little screenshot on the right.'],
    capturing: ['照常截下，接下来就在手边。', 'Capture a moment. Keep it close.'],
    captured: ['新截图在边缘了。点它，接着聊。', 'There it is. Tap it to keep going.'],
    checking: ['正在接入当前草稿…', 'Connecting to your current draft…'],
    uploading: ['已经开始接入，边缘轻轻收起。', 'The handoff has started. The edge clears.'],
    ready: ['图片放进草稿了，接着说你想说的。', 'Ready in your draft. Keep the thought going.'],
    full: ['演示同时展示最多三张图。先点一张，再试截图。', 'This demo shows up to three screenshots. Tap one to make room.'],
    empty: ['这一步完成了。再截一张，或重新体验。', 'All done. Capture another, or start again.'],
    paused: ['演示已暂停，截图和文字留在这里。', 'Demo paused. Your screenshots and words stay here.']
  };
  const shortCopy = {
    idle: ['等你轻点', 'Ready to tap'], capturing: ['收录中', 'Capturing'],
    captured: ['已收在边缘', 'At the edge'], checking: ['接入中', 'Connecting'],
    uploading: ['接入中', 'Attaching'], ready: ['已加入草稿', 'In your draft'],
    full: ['先试用一张', 'Try a screenshot'], empty: ['这一小步完成', 'All done'],
    paused: ['已暂停', 'Paused']
  };
  const stage = $('#demo-stage'), shots = $('#edge-shots'), edge = $('#edge-zone');
  const draft = $('#draft'), attachments = $('#attachments');
  const sourceImage = $('#source-image');
  const translateNodes = $$('[data-en]').filter(el => !el.matches('#demo-state-label, #demo-status, #edge-switch-note'));
  const chineseContent = new Map(translateNodes.map(el => [el, el.innerHTML]));
  const initialAria = new Map($$('[aria-label]').map(el => [el, el.getAttribute('aria-label')]));
  let language = 'zh', scene = 'design', queue = [], serial = 0, busy = false;
  let draftEdited = false, generation = 0, statusKey = 'idle', emptyDetail = false;
  let pendingAttachment = null;
  const timers = new Map(), animations = new Set(), travellers = new Set();
  const langIndex = () => language === 'zh' ? 0 : 1;
  const tr = pair => pair[langIndex()];
  const wait = (ms, token = generation) => new Promise(resolve => {
    const id = setTimeout(() => { timers.delete(id); resolve(token === generation); }, ms);
    timers.set(id, resolve);
  });
  const cancel = () => {
    generation += 1;
    for (const [id, resolve] of timers) { clearTimeout(id); resolve(false); }
    timers.clear();
    for (const animation of animations) animation.cancel();
    animations.clear();
    for (const traveller of travellers) traveller.remove();
    travellers.clear();
    // Cancelling a synthetic upload restores its image instead of losing it.
    if (pendingAttachment) {
      const { shot, index } = pendingAttachment;
      if (!queue.some(item => item.id === shot.id)) queue.splice(Math.min(index, queue.length), 0, shot);
      pendingAttachment = null;
    }
    $$('.image-attachment.pending', attachments).forEach(item => item.remove());
  };
  const setStatus = key => {
    statusKey = key; $('#demo-status').textContent = tr(copy[key]);
    const label = $('#demo-state-label');
    if (label) { label.textContent = tr(shortCopy[key]); label.dataset.en = shortCopy[key][1]; }
  };
  const setPhase = phase => {
    $$('.demo-step').forEach(step => {
      const current = step.dataset.step === phase;
      step.classList.toggle('is-current', current);
      if (current) step.setAttribute('aria-current', 'step');
      else step.removeAttribute('aria-current');
    });
  };
  const setBusy = value => {
    busy = value;
    $('#play-demo').disabled = value;
    $('#capture').disabled = value;
    $$('.edge-shot').forEach(b => b.disabled = value);
    stage.setAttribute('aria-busy', String(value));
    // Scene, language and replay controls stay available to stop the illustration.
  };
  function stopDemo(status = 'idle') {
    cancel(); setBusy(false); stage.dataset.state = 'idle'; renderShots();
    setPhase(queue.length ? 'collect' : 'capture');
    setStatus(status === 'idle' && !queue.length ? 'empty' : status);
  }
  const makeShot = kind => ({ id: ++serial, kind, file: sceneData[kind].file, portrait: kind === 'reading' });
  function renderShots(hiddenId = null) {
    shots.replaceChildren();
    queue.forEach((shot, index) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'edge-shot' + (shot.portrait ? ' portrait' : '');
      button.dataset.shotId = shot.id;
      button.disabled = busy;
      button.setAttribute('aria-label', tr(['把截图 ' + (index + 1) + ' 放入演示草稿', 'Attach screenshot ' + (index + 1) + ' to the example draft']));
      const img = document.createElement('img');
      img.src = asset(shot.file); img.alt = ''; img.draggable = false;
      img.width = sceneData[shot.kind].width; img.height = sceneData[shot.kind].height;
      const number = document.createElement('span');
      number.className = 'shot-number'; number.textContent = String(index + 1); number.setAttribute('aria-hidden', 'true');
      button.append(img, number);
      if (shot.id === hiddenId) button.style.visibility = 'hidden';
      button.addEventListener('click', () => attachShot(shot.id));
      shots.append(button);
    });
    edge.classList.toggle('empty', queue.length === 0);
    edge.setAttribute('aria-hidden', String(queue.length === 0));
    stage.dataset.empty = String(queue.length === 0);
  }
  function updateScene() {
    const info = sceneData[scene];
    stage.dataset.scene = scene;
    sourceImage.src = asset(info.file); sourceImage.alt = tr(info.alt);
    sourceImage.width = info.width; sourceImage.height = info.height;
    $('#source-label').textContent = tr(info.label);
    $('#source-title').textContent = info.title;
    if (!draftEdited) draft.value = tr(info.draft);
    $$('.moment-card, .scene-tab').forEach(button => {
      const active = button.dataset.scene === scene;
      button.setAttribute('aria-pressed', String(active)); button.classList.toggle('is-active', active);
    });
  }
  function reset(status = 'idle') {
    cancel();
    queue = [makeShot(scene), makeShot(scene === 'reading' ? 'design' : 'reading')];
    // Reset only the illustrative image attachments, never typed words or the existing note.
    $$('.image-attachment', attachments).forEach(el => el.remove());
    stage.dataset.state = 'idle';
    setBusy(false);
    renderShots();
    updateScene();
    setPhase('collect');
    setStatus(status);
  }
  function createAttachment(shot) {
    const item = document.createElement('div');
    item.className = 'image-attachment pending' + (shot.portrait ? ' portrait' : '');
    item.dataset.kind = shot.kind;
    item.dataset.shotId = String(shot.id);
    const img = document.createElement('img'); img.src = asset(shot.file); img.alt = tr(sceneData[shot.kind].alt);
    const text = document.createElement('span'), title = document.createElement('b'), status = document.createElement('small');
    title.textContent = tr(['截图', 'Screenshot']); status.textContent = tr(['接入中', 'Attaching']);
    text.append(title, status); item.append(img, text); attachments.append(item);
    return item;
  }
  async function attachShot(id, ownedBusy = false) {
    if (busy && !ownedBusy) return;
    const index = queue.findIndex(item => item.id === id), shot = queue[index];
    if (!shot) return;
    const token = generation;
    setBusy(true); setPhase('attach'); stage.dataset.state = 'checking'; setStatus('checking');
    if (!await wait(240, token)) return;
    // This is a local, synthetic positive-start signal, not native upload evidence.
    const attachment = createAttachment(shot);
    pendingAttachment = { shot, index };
    stage.dataset.state = 'uploading'; setStatus('uploading');
    const button = $('[data-shot-id="' + id + '"]', shots);
    if (button) {
      button.classList.add('swallowing');
    }
    if (!await wait(reduceMotion.matches ? 20 : 190, token)) return;
    queue = queue.filter(item => item.id !== id);
    renderShots();
    if (!await wait(700, token)) return;
    attachment.classList.remove('pending');
    $('small', attachment).textContent = tr(['已就绪', 'Ready']);
    pendingAttachment = null;
    stage.dataset.state = 'ready'; setStatus('ready'); setBusy(false);
  }
  // Fit the whole asset into its measured image box, including portrait examples.
  function imageRect(image, info) {
    const rect = image.getBoundingClientRect(), ratio = info.width / info.height;
    const width = Math.min(rect.width, rect.height * ratio), height = width / ratio;
    return { left: rect.left + (rect.width - width) / 2, top: rect.top + (rect.height - height) / 2, width, height };
  }
  async function flyToEdge(shot, token) {
    const button = $('[data-shot-id="' + shot.id + '"]', shots);
    if (!button || reduceMotion.matches || typeof button.animate !== 'function') return token === generation;
    const info = sceneData[shot.kind];
    const start = imageRect(sourceImage, info), end = imageRect($('img', button), info);
    const base = stage.getBoundingClientRect();
    if (!start.width || !end.width) return token === generation;
    const traveller = document.createElement('img');
    traveller.className = 'capture-traveller';
    traveller.src = asset(shot.file); traveller.alt = ''; traveller.draggable = false;
    traveller.setAttribute('aria-hidden', 'true');
    Object.assign(traveller.style, {
      position: 'absolute', left: '0', top: '0', width: start.width + 'px', height: start.height + 'px',
      objectFit: 'contain', pointerEvents: 'none', transformOrigin: '0 0'
    });
    stage.append(traveller); travellers.add(traveller);
    const x0 = start.left - base.left, y0 = start.top - base.top;
    const x1 = end.left - base.left, y1 = end.top - base.top;
    const scale = end.width / start.width;
    const clipped = Math.max(0, end.left + end.width - edge.getBoundingClientRect().right) / end.width * 100;
    const animation = traveller.animate([
      { transform: `translate(${x0}px, ${y0}px) scale(1)`, opacity: .94, clipPath: 'inset(0 0 0 0 round 7px)', offset: 0 },
      { transform: `translate(${x0 + (x1 - x0) * .56}px, ${y0 + (y1 - y0) * .35 - 17}px) scale(${scale + (1 - scale) * .32})`, opacity: 1, clipPath: 'inset(0 0 0 0 round 7px)', offset: .6 },
      { transform: `translate(${x1}px, ${y1}px) scale(${scale})`, opacity: 1, clipPath: `inset(0 ${clipped}% 0 0 round 7px)`, offset: 1 }
    ], { duration: 560, easing: 'cubic-bezier(.25,.65,.2,1)', fill: 'both' });
    animations.add(animation);
    try { await animation.finished; }
    catch { return false; }
    finally { animations.delete(animation); travellers.delete(traveller); traveller.remove(); }
    return token === generation;
  }
  async function capture(ownedBusy = false) {
    if (busy && !ownedBusy) return null;
    if (queue.length >= 3) { setPhase('collect'); setStatus('full'); return null; }
    // Finish any opening presentation before measuring the source image.
    for (const animation of animations) animation.cancel();
    animations.clear();
    const token = generation;
    setBusy(true); setPhase('capture'); stage.dataset.state = 'capturing'; setStatus('capturing');
    if (!await wait(reduceMotion.matches ? 40 : 160, token)) return null;
    const shot = makeShot(scene);
    queue.push(shot); // Oldest at the top; new screenshots join the end.
    const moving = !reduceMotion.matches && typeof stage.animate === 'function';
    renderShots(moving ? shot.id : null); setPhase('collect');
    if (moving && !await flyToEdge(shot, token)) return null;
    if (token !== generation) return null;
    const button = $('[data-shot-id="' + shot.id + '"]', shots);
    if (button) button.style.removeProperty('visibility');
    stage.dataset.state = 'idle'; setStatus('captured');
    if (!ownedBusy) setBusy(false);
    return shot;
  }
  async function playDemo() {
    reset();
    const token = generation;
    setBusy(true);
    const shot = await capture(true);
    if (!shot || token !== generation) return;
    if (!await wait(reduceMotion.matches ? 140 : 520, token)) return;
    await attachShot(shot.id, true);
  }
  function setDetailEmpty(value) {
    emptyDetail = value;
    $('#detail-visual').dataset.empty = String(value);
    $('#detail-edge').setAttribute('aria-hidden', String(value));
    $('#edge-full').classList.toggle('active', !value); $('#edge-full').setAttribute('aria-pressed', String(!value));
    $('#edge-empty').classList.toggle('active', value); $('#edge-empty').setAttribute('aria-pressed', String(value));
    $('#edge-switch-note').textContent = value ? tr(['没有要用的图，边缘也不留下来。', 'No screenshots. No edge left behind.']) : tr(['想用的内容，安静地在这里。', 'Just what you need, quietly close at hand.']);
  }
  function translate() {
    const isEnglish = language === 'en';
    document.documentElement.lang = isEnglish ? 'en' : 'zh-CN';
    document.title = isEnglish ? 'Riftlet — A screenshot. A thought continued.' : 'Riftlet — 截图之后，思路继续。';
    translateNodes.forEach(el => { el.innerHTML = isEnglish ? el.dataset.en.replace(/<br>/g, '<br> ') : chineseContent.get(el); });
    const button = $('#language-toggle');
    button.textContent = isEnglish ? '中文' : 'EN';
    button.setAttribute('aria-label', isEnglish ? '切换至中文' : 'Switch to English');
    const aria = {
      '.main-nav': 'Main navigation',
      '#demo-stage': 'Interactive illustration of a screenshot joining a draft',
      '#capture': 'Capture an example screenshot',
      '#edge-zone': 'Example screenshots at the edge',
      '#draft-card': 'Illustrated current conversation draft',
      '#attachments': 'Example draft attachments',
      '.send-symbol': 'Illustrative send icon. Does not send.',
      '#restart': 'Restart the demo',
      '.scene-tabs': 'Choose an example scene',
      '.demo-steps': 'Illustrated screenshot flow',
      '.edge-switch': 'Choose the edge state',
      '#detail-visual': 'A close-up illustration of the screenshot edge',
      '#dialog-close': 'Close'
    };
    Object.entries(aria).forEach(([selector, text]) => {
      const el = $(selector);
      if (!el) return;
      const label = isEnglish ? text : initialAria.get(el);
      if (label) el.setAttribute('aria-label', label); else el.removeAttribute('aria-label');
    });
    $$('.brand').forEach(el => el.setAttribute('aria-label', isEnglish ? 'Riftlet home' : 'Riftlet 首页'));
    $$('.image-attachment', attachments).forEach(el => {
      $('b', el).textContent = tr(['截图', 'Screenshot']);
      $('small', el).textContent = el.classList.contains('pending') ? tr(['接入中', 'Attaching']) : tr(['已就绪', 'Ready']);
      $('img', el).alt = tr(sceneData[el.dataset.kind].alt);
    });
    updateScene(); renderShots(); setDetailEmpty(emptyDetail); setStatus(statusKey);
  }
  $('#play-demo').addEventListener('click', playDemo);
  $('#capture').addEventListener('click', () => capture());
  $('#restart').addEventListener('click', () => reset());
  draft.addEventListener('input', () => { draftEdited = true; });
  $('#language-toggle').addEventListener('click', () => {
    if (busy) stopDemo();
    language = language === 'zh' ? 'en' : 'zh'; translate();
  });
  $('#edge-full').addEventListener('click', () => setDetailEmpty(false));
  $('#edge-empty').addEventListener('click', () => setDetailEmpty(true));
  $$('.moment-card, .scene-tab').forEach(button => button.addEventListener('click', () => {
    if (!sceneData[button.dataset.scene]) return;
    scene = button.dataset.scene; reset();
    if (button.classList.contains('moment-card')) $('.hero').scrollIntoView({ behavior: reduceMotion.matches ? 'auto' : 'smooth', block: 'start' });
  }));
  const dialog = $('#release-dialog');
  $$('[data-release]').forEach(button => button.addEventListener('click', () => {
    if (busy) stopDemo();
    if (!dialog.open) dialog.showModal();
  }));
  $('#dialog-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => {
    const rect = dialog.getBoundingClientRect();
    if (event.target === dialog && (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom)) dialog.close();
  });
  window.addEventListener('scroll', () => $('#site-header').classList.toggle('scrolled', window.scrollY > 20), { passive: true });
  window.addEventListener('resize', () => { if (busy || animations.size) stopDemo(); }, { passive: true });
  document.addEventListener('visibilitychange', () => { if (document.hidden && (busy || animations.size)) stopDemo('paused'); });
  reduceMotion.addEventListener('change', () => { if (busy || animations.size) stopDemo(); });
  reset();
  if (!reduceMotion.matches && typeof stage.animate === 'function') {
    const token = generation;
    document.fonts.ready.then(() => {
      if (token !== generation || busy || document.hidden || reduceMotion.matches) return;
      const entrances = [
        $('#source-card').animate([{ opacity: .3, transform: 'translateY(12px) rotate(-5deg)' }, { opacity: 1, transform: 'translateY(0) rotate(-3deg)' }], { duration: 650, easing: 'cubic-bezier(.2,.75,.2,1)' }),
        $('#draft-card').animate([{ opacity: .3, transform: 'translateY(15px)' }, { opacity: 1, transform: 'translateY(0)' }], { duration: 700, easing: 'cubic-bezier(.2,.75,.2,1)', delay: 70 })
      ];
      entrances.forEach(animation => {
        animations.add(animation);
        animation.finished.catch(() => {}).finally(() => animations.delete(animation));
      });
    });
  }
})();
