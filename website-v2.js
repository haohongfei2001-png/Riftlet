(() => {
  'use strict';
  const $ = (s, root = document) => root.querySelector(s);
  const $$ = (s, root = document) => Array.from(root.querySelectorAll(s));
  const asset = name => window.RIFTLET_ASSETS?.[name] || 'website-assets/' + name;
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const sceneData = {
    design: { file: 'glass-study.png', label: ['色彩笔记', 'Colour notes'], title: 'A study in light.', alt: ['青绿弧形玻璃与珊瑚色玻璃球的原创静物', 'An original still life of teal glass and a coral glass sphere'], draft: ['这组颜色，为什么看起来这么轻盈？', 'What makes these colours feel so light?'] },
    code: { file: 'error.svg', label: ['一个小问题', 'A little problem'], title: 'One small fix.', alt: ['合成的 JavaScript 报错示例', 'An illustrative JavaScript error'], draft: ['这个报错，该从哪里开始排查？', 'Where should I start with this error?'] },
    reading: { file: 'reading.svg', label: ['阅读摘记', 'Reading notes'], title: 'A thought to keep.', alt: ['泰勒展开与导数的阅读摘记示例', 'Illustrative reading notes on Taylor expansion'], draft: ['这一行，为什么能推出下一行？', 'How does this line lead to the next?'] }
  };
  const copy = {
    idle: ['点一下右侧微图，试试这一小步。', 'Tap a little screenshot on the right.'],
    capturing: ['照常截下，接下来就在手边。', 'Capture a moment. Keep it close.'],
    captured: ['新截图在边缘了。点它，接着聊。', 'There it is. Tap it to keep going.'],
    checking: ['正在接入当前草稿…', 'Connecting to your current draft…'],
    uploading: ['已经开始接入，边缘轻轻收起。', 'The handoff has started. The edge clears.'],
    ready: ['', ''],
    full: ['边缘已有三张图。先用一张，再截新的。', 'Three screenshots are close at hand. Use one first.'],
    empty: ['这一步完成了。再截一张，或重新体验。', 'All done. Capture another, or start again.'],
    paused: ['演示已暂停。回来后可以重新体验。', 'The demo is paused. Play it again when you’re ready.']
  };
  const stage = $('#demo-stage'), shots = $('#edge-shots'), edge = $('#edge-zone');
  const draft = $('#draft'), attachments = $('#attachments');
  const translateNodes = $$('[data-en]');
  const chineseContent = new Map(translateNodes.map(el => [el, el.innerHTML]));
  const initialAria = new Map($$('[aria-label]').map(el => [el, el.getAttribute('aria-label')]));
  let language = 'zh', scene = 'design', queue = [], serial = 0, busy = false;
  let draftEdited = false, generation = 0, statusKey = 'idle', emptyDetail = false;
  const timers = new Map();
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
  };
  const setStatus = key => { statusKey = key; $('#demo-status').textContent = tr(copy[key]); };
  const setBusy = value => {
    busy = value;
    $('#play-demo').disabled = value;
    $('#capture').disabled = value;
    $$('.edge-shot').forEach(b => b.disabled = value);
    stage.setAttribute('aria-busy', String(value));
  };
  const makeShot = kind => ({ id: ++serial, kind, file: sceneData[kind].file, portrait: kind === 'reading' });
  function renderShots(arrivingId) {
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
      const number = document.createElement('span');
      number.className = 'shot-number'; number.textContent = String(index + 1); number.setAttribute('aria-hidden', 'true');
      button.append(img, number);
      if (shot.id === arrivingId && !reduceMotion.matches) {
        button.classList.add('arriving');
        button.addEventListener('animationend', () => button.classList.remove('arriving'), { once: true });
      }
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
    $('#source-image').src = asset(info.file);
    $('#source-image').alt = tr(info.alt);
    $('#source-label').textContent = tr(info.label);
    $('#source-title').textContent = info.title;
    if (!draftEdited) draft.value = tr(info.draft);
    $$('.moment-card').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.scene === scene)));
  }
  function reset(status = 'idle') {
    cancel();
    queue = [makeShot(scene), makeShot(scene === 'reading' ? 'design' : 'reading')];
    $$('.image-attachment', attachments).forEach(el => el.remove());
    stage.dataset.state = 'idle';
    setBusy(false);
    renderShots();
    updateScene();
    setStatus(status);
  }
  function createAttachment(shot) {
    const item = document.createElement('div');
    item.className = 'image-attachment pending' + (shot.portrait ? ' portrait' : '');
    item.dataset.kind = shot.kind;
    const img = document.createElement('img'); img.src = asset(shot.file); img.alt = tr(sceneData[shot.kind].alt);
    const text = document.createElement('span'), title = document.createElement('b'), status = document.createElement('small');
    title.textContent = tr(['截图', 'Screenshot']); status.textContent = tr(['接入中', 'Attaching']);
    text.append(title, status); item.append(img, text); attachments.append(item);
    return item;
  }
  async function attachShot(id, ownedBusy = false) {
    if (busy && !ownedBusy) return;
    const shot = queue.find(item => item.id === id);
    if (!shot) return;
    const token = generation;
    setBusy(true); stage.dataset.state = 'checking'; setStatus('checking');
    if (!await wait(240, token)) return;
    // This is a local, synthetic positive-start signal, not native upload evidence.
    const attachment = createAttachment(shot);
    stage.dataset.state = 'uploading'; setStatus('uploading');
    const button = $('[data-shot-id="' + id + '"]', shots);
    if (button) {
      button.classList.remove('arriving');
      button.classList.add('swallowing');
    }
    if (!await wait(reduceMotion.matches ? 20 : 190, token)) return;
    queue = queue.filter(item => item.id !== id);
    renderShots();
    if (!await wait(700, token)) return;
    attachment.classList.remove('pending');
    $('small', attachment).textContent = tr(['已就绪', 'Ready']);
    stage.dataset.state = 'ready'; setStatus('ready'); setBusy(false);
  }
  async function capture(ownedBusy = false) {
    if (busy && !ownedBusy) return null;
    if (queue.length >= 3) { setStatus('full'); return null; }
    const token = generation;
    setBusy(true); stage.dataset.state = 'capturing'; setStatus('capturing');
    if (!await wait(reduceMotion.matches ? 40 : 430, token)) return null;
    const shot = makeShot(scene);
    queue.unshift(shot); renderShots(shot.id);
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
    if (!await wait(reduceMotion.matches ? 140 : 650, token)) return;
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
    document.title = 'Riftlet';
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
      '.edge-switch': 'Choose the edge state',
      '#detail-visual': 'A close-up illustration of the screenshot edge',
      '#dialog-close': 'Close'
    };
    Object.entries(aria).forEach(([selector, text]) => { const el = $(selector); if (el) el.setAttribute('aria-label', isEnglish ? text : initialAria.get(el)); });
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
  $('#language-toggle').addEventListener('click', () => { language = language === 'zh' ? 'en' : 'zh'; translate(); });
  $('#edge-full').addEventListener('click', () => setDetailEmpty(false));
  $('#edge-empty').addEventListener('click', () => setDetailEmpty(true));
  $$('.moment-card').forEach(button => button.addEventListener('click', () => {
    scene = button.dataset.scene; reset();
    $('.hero').scrollIntoView({ behavior: reduceMotion.matches ? 'auto' : 'smooth', block: 'start' });
  }));
  const dialog = $('#release-dialog');
  $$('[data-release]').forEach(button => button.addEventListener('click', () => dialog.showModal()));
  $('#dialog-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => {
    const rect = dialog.getBoundingClientRect();
    if (event.target === dialog && (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom)) dialog.close();
  });
  window.addEventListener('scroll', () => $('#site-header').classList.toggle('scrolled', window.scrollY > 20), { passive: true });
  document.addEventListener('visibilitychange', () => { if (document.hidden && busy) reset('paused'); });
  reset();
  if (!reduceMotion.matches) {
    document.fonts.ready.then(() => {
      $('#source-card').animate([{ opacity: .3, transform: 'translateY(12px) rotate(-5deg)' }, { opacity: 1, transform: 'translateY(0) rotate(-3deg)' }], { duration: 650, easing: 'cubic-bezier(.2,.75,.2,1)' });
      $('#draft-card').animate([{ opacity: .3, transform: 'translateY(15px)' }, { opacity: 1, transform: 'translateY(0)' }], { duration: 700, easing: 'cubic-bezier(.2,.75,.2,1)', delay: 70 });
    });
  }
})();
