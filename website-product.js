/* Riftlet product homepage. Local demonstration only; no uploads or messages. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const edge = $('edge'), stage = $('edge-items'), attachments = $('attachments');
  const draft = $('draft'), status = $('status'), outcome = $('outcome');
  const translations = Array.from(document.querySelectorAll('[data-en]'), node => ({
    node, zh: node.innerHTML, en: node.getAttribute('data-en')
  }));
  const copy = {
    zh: {
      title: 'Riftlet — 不必找。就在那儿。',
      description: 'Riftlet 为刚刚截下的内容留一个熟悉的位置。截图留在屏幕边缘，轻点放入对话草稿。首个 macOS 版本正在准备中。',
      draft: '帮我比较这两张截图中的区别。',
      initial: '点一下右侧的任一截图。',
      queued: '截图 {id} 已排队，其他截图仍在原处。',
      pending: '正在准备截图 {id} 的附件…',
      success: '截图 {id} 已进入演示草稿。文字保留，没有发送。',
      failure: '截图 {id} 未能附加，已回到原处。可以再次点击。',
      unknown: '截图 {id} 的结果未确认，仍保留在原处，不会重复上传。',
      removed: '已移除演示草稿中的截图 {id}。',
      item: '将截图 {id} 放入演示草稿',
      retry: '截图 {id} 附加失败，点击重试',
      uncertain: '截图 {id} 的结果未确认，已保留',
      done: '截图 {id} 已进入演示草稿',
      name: '截图 {id}', ready: '已就绪', preparing: '准备中…',
      remove: '移除演示附件 {id}', dark: '深色桌面', light: '浅色桌面',
      edge: '屏幕边缘截图队列', attachments: '演示草稿的附件'
    },
    en: {
      title: 'Riftlet — No searching. Right there.',
      description: 'Riftlet keeps recent screenshots at the edge of your screen. Remember the place. Click it into your draft. The first macOS release is in the works.',
      draft: 'Help me compare these two screenshots.',
      initial: 'Click any screenshot at the right edge.',
      queued: 'Screenshot {id} is queued. The others stay in place.',
      pending: 'Preparing the attachment for screenshot {id}…',
      success: 'Screenshot {id} is in the demo draft. Your text is intact. Nothing was sent.',
      failure: 'Screenshot {id} could not be attached. It is back in place; click to retry.',
      unknown: 'Screenshot {id} is unconfirmed. It stays in place without another upload.',
      removed: 'Screenshot {id} was removed from the demo draft.',
      item: 'Add screenshot {id} to the demo draft',
      retry: 'Screenshot {id} failed. Click to retry',
      uncertain: 'Screenshot {id} is unconfirmed and preserved',
      done: 'Screenshot {id} is in the demo draft',
      name: 'Screenshot {id}', ready: 'Ready', preparing: 'Preparing…',
      remove: 'Remove demo attachment {id}', dark: 'Dark desktop', light: 'Light desktop',
      edge: 'Screen-edge screenshot queue', attachments: 'Demo draft attachments'
    }
  };
  const configs = [
    {id: 1, symbol: 'capture-a', view: '0 0 240 160', w: 48, h: 32},
    {id: 2, symbol: 'capture-b', view: '0 0 240 170', w: 48, h: 34},
    {id: 3, symbol: 'capture-c', view: '0 0 110 160', w: 33, h: 48}
  ];
  let language = 'zh', items = [], queue = [], running = false, generation = 0;
  let pointerInside = false, keyboardInside = false, keyboardMode = false;
  let needsCompact = false, draftEdited = false, lastStatus = {key: 'initial', id: ''};
  const text = (key, id = '') => copy[language][key].replaceAll('{id}', String(id));
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

  function say(key, id = '') {
    lastStatus = {key, id};
    status.textContent = text(key, id);
    status.dataset.status = key;
  }
  function thumbnail(item) {
    // Only these fixed synthetic symbols enter this markup; never user input.
    return `<svg viewBox="${item.view}" aria-hidden="true"><use href="#${item.symbol}"></use></svg>`;
  }
  function labelItem(item) {
    const key = {failed: 'retry', unknown: 'uncertain', done: 'done'}[item.state] || 'item';
    item.element.setAttribute('aria-label', text(key, item.id));
    item.element.dataset.state = item.state;
  }
  function refreshCard(card) {
    const id = card.dataset.id;
    card.querySelector('.attachment-name').textContent = text('name', id);
    card.querySelector('small').textContent = text(card.dataset.ready === 'true' ? 'ready' : 'preparing');
    const remove = card.querySelector('button');
    if (remove) remove.setAttribute('aria-label', text('remove', id));
  }
  function refreshThemeLabel() {
    const dark = $('desktop').classList.contains('dark');
    $('theme').textContent = text(dark ? 'light' : 'dark');
    $('theme').setAttribute('aria-pressed', String(dark));
  }
  function setLanguage(next, updateUrl = false) {
    language = next === 'en' ? 'en' : 'zh';
    document.documentElement.lang = language === 'en' ? 'en' : 'zh-CN';
    translations.forEach(entry => { entry.node.innerHTML = entry[language]; });
    document.title = text('title');
    document.querySelector('meta[name="description"]').content = text('description');
    document.querySelector('meta[property="og:title"]').content = text('title');
    document.querySelector('meta[property="og:description"]').content = text('description');
    $('language-toggle').textContent = language === 'en' ? '中文' : 'EN';
    $('language-toggle').setAttribute('aria-label', language === 'en' ? '切换为中文' : 'Switch to English');
    if (!draftEdited) draft.value = text('draft');
    edge.setAttribute('aria-label', text('edge'));
    attachments.setAttribute('aria-label', text('attachments'));
    items.forEach(labelItem);
    attachments.querySelectorAll('.attachment').forEach(refreshCard);
    refreshThemeLabel();
    say(lastStatus.key, lastStatus.id);
    if (updateUrl) {
      try {
        const url = new URL(window.location.href);
        if (language === 'en') url.searchParams.set('lang', 'en');
        else url.searchParams.delete('lang');
        window.history.replaceState(null, '', url);
      } catch { /* File previews need not support history replacement. */ }
    }
  }
  function compact() {
    if (pointerInside || keyboardInside || !needsCompact) return;
    items.filter(item => item.state !== 'done').forEach((item, index) => {
      item.slot = index;
      item.element.style.setProperty('--y', `${index * 55}px`);
    });
    needsCompact = false;
  }
  function reset() {
    generation += 1; // Invalidate any pending demo completion before rebuilding.
    items = configs.map((item, slot) => ({...item, slot, state: 'idle'}));
    queue = []; running = false; needsCompact = false;
    pointerInside = false; keyboardInside = false;
    attachments.replaceChildren(); stage.replaceChildren();
    items.forEach(item => {
      const button = document.createElement('button');
      button.type = 'button'; button.className = 'rift-item'; button.dataset.id = String(item.id);
      button.style.setProperty('--y', `${item.slot * 55}px`);
      button.style.setProperty('--w', `${item.w}px`);
      button.style.setProperty('--h', `${item.h}px`);
      button.innerHTML = `<span class="clip"><span class="thumb">${thumbnail(item)}</span></span><span class="number">${item.id}</span>`;
      item.element = button; labelItem(item);
      button.addEventListener('click', () => request(item));
      stage.appendChild(button);
    });
    // Reset the demonstration, not anything the visitor has written.
    say('initial');
  }
  function request(item) {
    if (item.state === 'unknown') { say('unknown', item.id); return; }
    if (['queued', 'pending', 'done'].includes(item.state)) return;
    item.state = 'queued'; labelItem(item);
    item.element.classList.remove('failed'); item.element.classList.add('pending');
    item.element.setAttribute('aria-busy', 'true');
    queue.push({item, outcome: outcome.value, epoch: generation});
    say('queued', item.id); void run();
  }
  async function run() {
    if (running || queue.length === 0) return;
    running = true;
    const task = queue.shift(), item = task.item;
    item.state = 'pending'; labelItem(item); say('pending', item.id);
    await sleep(450);
    if (task.epoch !== generation) return;
    let card;
    if (task.outcome === 'success') {
      card = document.createElement('div'); card.className = 'attachment';
      card.dataset.id = String(item.id); card.dataset.ready = 'false';
      card.innerHTML = thumbnail(item) + '<span><span class="attachment-name"></span><small></small></span>';
      refreshCard(card); attachments.appendChild(card);
    }
    await sleep(550);
    if (task.epoch !== generation) return;
    item.element.classList.remove('pending'); item.element.removeAttribute('aria-busy');
    if (task.outcome === 'success') {
      card.dataset.ready = 'true';
      const remove = document.createElement('button');
      remove.type = 'button'; remove.className = 'remove-attachment'; remove.textContent = '×';
      remove.addEventListener('click', () => { card.remove(); say('removed', item.id); });
      card.appendChild(remove); refreshCard(card);
      item.state = 'done'; item.element.classList.add('done'); item.element.tabIndex = -1;
      labelItem(item); say('success', item.id); needsCompact = true;
      await sleep(220);
      if (task.epoch !== generation) return;
      compact();
    } else {
      item.state = task.outcome === 'failure' ? 'failed' : 'unknown';
      item.element.classList.add(item.state); labelItem(item);
      say(task.outcome === 'failure' ? 'failure' : 'unknown', item.id);
    }
    running = false; void run();
  }
  edge.addEventListener('pointerenter', () => { pointerInside = true; });
  edge.addEventListener('pointerleave', () => { pointerInside = false; compact(); });
  document.addEventListener('pointerdown', () => { keyboardMode = false; keyboardInside = false; }, true);
  document.addEventListener('keydown', event => {
    if (['Tab', 'Enter', ' '].includes(event.key)) keyboardMode = true;
  }, true);
  edge.addEventListener('focusin', () => { keyboardInside = keyboardMode; });
  edge.addEventListener('focusout', () => {
    requestAnimationFrame(() => {
      keyboardInside = keyboardMode && edge.contains(document.activeElement);
      compact();
    });
  });
  draft.addEventListener('input', () => { draftEdited = true; });
  $('reset').addEventListener('click', reset);
  $('theme').addEventListener('click', () => { $('desktop').classList.toggle('dark'); refreshThemeLabel(); });
  $('language-toggle').addEventListener('click', () => setLanguage(language === 'en' ? 'zh' : 'en', true));
  let initial = 'zh';
  try { initial = new URL(window.location.href).searchParams.get('lang') === 'en' ? 'en' : 'zh'; } catch {}
  setLanguage(initial); reset();
})();
