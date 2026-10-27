/* Synthetic desktop surface for the 485fa87 Riftlet UI reconstruction.
 * This is not a browser, OS compositor, live ChatGPT session or attachment backend.
 * Every message and attachment stays in this page. All styling is in desktop.css.
 */
(function () {
  'use strict';
  const NS = 'http://www.w3.org/2000/svg';
  const iconPaths = {
    sidebar: '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M9 4v16"/>',
    compose: '<path d="m15 4 5 5M13 6l5 5M7 17l4-1L21 6a2.8 2.8 0 0 0-4-4L7 12z"/><path d="M11 4H5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h13a2 2 0 0 0 2-2v-6"/>',
    search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
    plus: '<path d="M12 4v16M4 12h16"/>',
    down: '<path d="m7 10 5 5 5-5"/>',
    arrow: '<path d="M12 19V5m-6 6 6-6 6 6"/>',
    mic: '<rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3m-4 0h8"/>',
    voice: '<path d="M4 10v4m4-9v14m4-16v18m4-15v12m4-8v4"/>',
    share: '<path d="M12 16V3M7 8l5-5 5 5M5 12H3v9h18v-9h-2"/>',
    more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    copy: '<rect x="8" y="8" width="12" height="13" rx="2"/><path d="M16 8V3H3v14h5"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    thumb: '<path d="M8 10v11H3V10h5Zm0 0 5-7h2v7h6l-2 11H8"/>',
    retry: '<path d="M20 8A8 8 0 1 0 20 17M20 3v5h-5"/>',
    folder: '<path d="M3 6h7l2 3h9v11H3z"/>',
    image: '<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="1.5"/><path d="m3 17 6-6 5 5 3-3 4 4"/>',
    globe: '<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18"/>',
    back: '<path d="M18 12H5m6-6-6 6 6 6"/>',
    forward: '<path d="M6 12h13m-6-6 6 6-6 6"/>',
    reload: '<path d="M20 9a8 8 0 1 0-1 9M20 4v5h-5"/>',
    tune: '<path d="M3 7h18M3 17h18"/><circle cx="8" cy="7" r="3" fill="currentColor" stroke="none"/><circle cx="16" cy="17" r="3" fill="currentColor" stroke="none"/>',
    star: '<path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-3-5.6 3 1.1-6.2L3 9.6l6.2-.9z"/>',
    window: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18"/>',
    close: '<path d="m6 6 12 12M18 6 6 18"/>',
    wifi: '<path d="M2 8a16 16 0 0 1 20 0M5 11a11 11 0 0 1 14 0M8 14a6 6 0 0 1 8 0"/><circle cx="12" cy="18" r="1.5" fill="currentColor" stroke="none"/>',
    battery: '<rect x="2" y="7" width="17" height="10" rx="2"/><path d="M21 10v4"/><rect x="4" y="9" width="12" height="6" rx="1" fill="currentColor" stroke="none"/>',
    control: '<rect x="3" y="4" width="18" height="6" rx="3"/><rect x="3" y="14" width="18" height="6" rx="3"/><circle cx="8" cy="7" r="1.5" fill="currentColor"/><circle cx="16" cy="17" r="1.5" fill="currentColor"/>',
    bluetooth: '<path d="m7 7 10 10-5 4V3l5 4-10 10"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>',
    sound: '<path d="M4 9h4l5-5v16l-5-5H4zM17 8a6 6 0 0 1 0 8"/>',
  };
  function icon(name, cls = '', size = 18) {
    return `<svg class="desktop-icon ${cls}" viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.55" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${iconPaths[name] || iconPaths.window}</svg>`;
  }
  function text(value) { return String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function clamp(value, min, max) { return Math.min(max, Math.max(min, value)); }
  const threadData = {
    'thread-a': {
      title: '界面的比例与注意力',
      draft: '帮我看一下这张图里的细节。',
      user: '我想比较两种界面方案。先不决定哪一种更好，应该从什么地方开始观察？',
      response: `<p>先回到你真正使用它的时刻。把窗口摆在平时的位置，继续阅读、打字，再留意它进入视野的方式。</p><h3>可以从三个具体问题开始</h3><ol><li><strong>能否一眼认出内容？</strong><br>观察图片的整体结构，不必试图在微图里读完文字。</li><li><strong>动作有没有清楚的结果？</strong><br>点击之后先等待；只有附件完成，原来的图片才应离开。</li><li><strong>它会不会持续分散注意力？</strong><br>让它停在桌面上几分钟，看看阅读和输入是否仍然自然。</li></ol><p>先记录你实际看到和感受到的事情，再考虑调整尺寸、位置或动效。</p>`,
    },
    'thread-b': {
      title: '阅读笔记 · 空间与秩序',
      draft: '',
      user: '把这段阅读笔记整理成一个简短提纲。不要添加原文里没有的结论。',
      response: `<p>可以保留原来的思考顺序，整理成下面三部分。</p><h3>1. 空间如何被组织</h3><p>边缘、留白和排列关系，帮助我们理解哪些元素属于同一件事。</p><h3>2. 注意力如何移动</h3><p>正在操作的内容应该清楚，而暂时不需要的东西可以安静地留在外围。</p><h3>3. 变化如何被理解</h3><p>连续、可追踪的变化比突然的替换更容易解释。后续可以结合具体界面再讨论。</p>`,
    },
  };
  function wallpaper() {
    return `<svg class="mac-wallpaper" viewBox="0 0 1440 900" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><defs>
      <linearGradient id="rift-wall-sky" x2="0" y2="1"><stop stop-color="#96b8ca"/><stop offset=".65" stop-color="#cbd9dc"/><stop offset="1" stop-color="#e7ddd0"/></linearGradient>
      <linearGradient id="rift-wall-far" x2="0" y2="1"><stop stop-color="#748f9e"/><stop offset="1" stop-color="#afbdbe"/></linearGradient>
      <linearGradient id="rift-wall-mid" x2=".5" y2="1"><stop stop-color="#657e89"/><stop offset="1" stop-color="#3f616b"/></linearGradient>
      <linearGradient id="rift-wall-front" x2=".4" y2="1"><stop stop-color="#496c70"/><stop offset="1" stop-color="#233f45"/></linearGradient>
      <linearGradient id="rift-wall-water" x2="0" y2="1"><stop stop-color="#a9c1c7"/><stop offset=".52" stop-color="#7ca7b5"/><stop offset="1" stop-color="#638895"/></linearGradient>
      <linearGradient id="rift-wall-shade"><stop stop-color="#183f49" stop-opacity="0"/><stop offset="1" stop-color="#183f49" stop-opacity=".28"/></linearGradient>
      <filter id="rift-wall-noise"><feTurbulence baseFrequency=".48" numOctaves="3" seed="8" stitchTiles="stitch" type="fractalNoise"/><feColorMatrix type="saturate" values="0"/></filter>
    </defs><rect width="1440" height="900" fill="url(#rift-wall-sky)"/>
      <path d="M0 348 56 337 101 353 180 305 227 329 305 274 338 283 385 244 421 269 465 241 501 267 559 227 602 251 671 219 711 258 773 241 816 272 852 259 922 307 1000 298 1092 342 1150 319 1245 358 1342 336 1440 372V650H0Z" fill="url(#rift-wall-far)"/>
      <path d="M0 394 94 410 206 372 303 395 401 355 481 381 581 319 668 366 739 344 830 410 958 373 1068 434 1169 402 1298 442 1440 425V680H0Z" fill="#849d9e" opacity=".65"/>
      <rect y="465" width="1440" height="435" fill="url(#rift-wall-water)"/>
      <path d="M0 290C82 316 140 379 208 392 272 406 283 445 358 463 407 474 464 494 513 513 554 527 576 548 602 567 547 576 498 583 440 589 355 591 257 624 183 644 118 660 58 664 0 685Z" fill="url(#rift-wall-mid)"/>
      <path d="M1440 335C1375 375 1339 409 1282 431 1221 453 1228 472 1165 496 1109 517 1088 526 1055 551 1105 561 1132 586 1197 601 1294 625 1368 626 1440 651Z" fill="url(#rift-wall-mid)"/>
      <path d="M0 591C79 569 124 590 207 578 278 570 296 602 375 615 424 624 462 650 507 674 542 695 615 705 649 723 555 749 479 761 411 788 310 827 249 859 206 900H0Z" fill="url(#rift-wall-front)"/>
      <path d="M1440 625C1390 626 1365 646 1320 650 1279 651 1250 685 1196 693 1152 701 1120 730 1078 741 1121 756 1131 778 1190 795 1230 808 1262 849 1311 861 1350 873 1388 892 1440 900Z" fill="#355b64"/>
      <path d="M489 602c93 5 128 8 193 6m153-28c71 1 111 5 152 7M596 653c76 4 147 3 202 0m-107 70c95 2 142 1 209-2m-216 75c132 2 219 1 305-5m-545 54c71 0 133 4 219 0" fill="none" stroke="#dce5df" stroke-opacity=".2" stroke-width="2"/>
      <rect width="1440" height="900" fill="url(#rift-wall-shade)"/>
      <rect width="1440" height="900" filter="url(#rift-wall-noise)" opacity=".025" style="mix-blend-mode:soft-light"/>
    </svg>`;
  }
  function dockIcon(name) {
    if (name === 'finder') return '<svg viewBox="0 0 52 52"><defs><linearGradient id="finder-g" x2="0" y2="1"><stop stop-color="#7fc6ff"/><stop offset="1" stop-color="#4397eb"/></linearGradient></defs><rect x="3" y="3" width="46" height="46" rx="11" fill="url(#finder-g)"/><path d="M29 3h9q11 0 11 11v24q0 11-11 11H26V30h-7L25 3Z" fill="#c7e8ff"/><path d="M15 17v5m22-5v5M14 31q12 10 24 0" fill="none" stroke="#204674" stroke-width="2" stroke-linecap="round"/></svg>';
    if (name === 'chrome') return '<svg viewBox="0 0 52 52"><circle cx="26" cy="26" r="23" fill="#f7c84d"/><path d="M26 26 7 13a23 23 0 0 1 39 2H25Z" fill="#e9564d"/><path d="m26 26-9 21A23 23 0 0 1 7 13l13 23Z" fill="#4da866"/><path d="m26 26 20-11a23 23 0 0 1-29 32l14-24Z" fill="#f4c548"/><circle cx="26" cy="26" r="11" fill="#f8fafb"/><circle cx="26" cy="26" r="8.5" fill="#5b9ae5"/></svg>';
    if (name === 'notes') return '<svg viewBox="0 0 52 52"><rect x="3" y="3" width="46" height="46" rx="11" fill="#fffdf6"/><path d="M14 3h24q11 0 11 11v4H3v-4Q3 3 14 3Z" fill="#f3c643"/><path d="M10 25h32M10 33h32M10 41h25" stroke="#ddd9cb" stroke-width="1"/></svg>';
    if (name === 'preview') return '<svg viewBox="0 0 52 52"><rect x="3" y="3" width="46" height="46" rx="11" fill="#e9edf0"/><g transform="rotate(-7 26 26)"><rect x="9" y="10" width="34" height="33" rx="2" fill="#fff"/><rect x="12" y="13" width="28" height="24" fill="#80b4d2"/><path d="m12 32 8-12 9 10 5-7 6 14H12Z" fill="#487c72"/><circle cx="33" cy="19" r="3" fill="#ece9d7"/></g></svg>';
    if (name === 'settings') return '<svg viewBox="0 0 52 52"><rect x="3" y="3" width="46" height="46" rx="11" fill="#b6bdc2"/><circle cx="26" cy="26" r="17" fill="none" stroke="#646d74" stroke-width="6" stroke-dasharray="7 3"/><circle cx="26" cy="26" r="11" fill="none" stroke="#e8ebed" stroke-width="4"/><circle cx="26" cy="26" r="6" fill="#69757e"/></svg>';
    return '<svg viewBox="0 0 52 52"><path d="M16 13h20l-2 34H18Z" fill="#d2d8dc" stroke="#edf0f2" stroke-width="2"/><path d="M14 12h24M21 8h10M23 20v20m6-20v20" fill="none" stroke="#e7ecee" stroke-width="3" stroke-linecap="round"/></svg>';
  }

  class RiftDesktop {
    constructor({element, width = 1440, height = 900, onThreadChange = () => {}, onEvent = () => {}}) {
      if (!element) throw new Error('RiftDesktop requires an element');
      this.element = element;
      this.width = width; this.height = height;
      this.onThreadChange = onThreadChange; this.onEvent = onEvent;
      this.theme = 'light'; this.scene = 'chrome'; this.windowMode = 'normal'; this.thread = 'thread-a';
      this.insets = {top:25, bottom:76};
      this.threads = new Map(Object.entries(threadData).map(([id,t]) => [id, {...t, attachments:new Map(), turns:[]} ]));
      this.bounds = this.defaultBounds();
      this.normalBounds = {...this.bounds};
      this.pointer = null;
      this.element.classList.add('mac-desktop');
      this.element.dataset.theme=this.theme;this.element.dataset.scene=this.scene;
      this.build(); this.applyBounds(); this.renderThread();
      this.setSize(width, height);
    }
    defaultBounds() {
      const width = Math.min(1120, this.width - (this.width < 1300 ? 100 : 210));
      const height = Math.min(740, this.height - 150);
      return {x:Math.max(45, Math.round((this.width - width) * .43)), y:60, width, height};
    }
    emit(type, details = {}) { this.onEvent({type,...details,thread:this.thread}); }
    build() {
      this.element.innerHTML = `${wallpaper()}<div class="mac-wallpaper-night"></div>
        <div class="mac-menubar"><div class="mac-menu-left"><span class="mac-apple" aria-label="Apple"><svg viewBox="0 0 20 22" width="14" height="17"><path d="M13.7 3.8c1-.9 1.6-2.2 1.5-3.6-1.3.1-2.7.9-3.5 1.9-.8.9-1.4 2.3-1.3 3.6 1.3.1 2.6-.7 3.3-1.9ZM17.7 14.9c-.5 1.2-.8 1.7-1.5 2.8-1.1 1.6-2.7 3.5-4.6 3.5-1.7 0-2.1-1.1-4.4-1.1-2.2 0-2.7 1.1-4.4 1.1-1.9 0-3.4-1.8-4.5-3.4C-4.7 13.3-3 6.5.7 5.3c1.7-.6 3.2-.5 4.7.3 1.1.5 1.7.5 2.7 0 1.7-.8 3.4-.9 5-.3 1.3.5 2.3 1.3 2.9 2.4-3.9 2.1-3.3 6.8 1.7 7.2Z" transform="translate(3 0) scale(.85)" fill="currentColor"/></svg></span><b class="mac-app-name">Chrome</b><span>文件</span><span>编辑</span><span>显示</span><span>历史记录</span><span>书签</span><span>个人资料</span><span>窗口</span><span>帮助</span></div><div class="mac-menu-right"><span class="mac-menu-small">A</span>${icon('bluetooth','',14)}${icon('battery','',21)}${icon('wifi','',17)}${icon('search','',15)}${icon('control','',17)}<span class="mac-clock">10月27日 周二 11:24</span></div></div>
        <div class="desktop-file"><svg width="44" height="41" viewBox="0 0 44 41"><path d="M2 7h16l4 5h20v25H2Z" fill="#5cafe1"/><path d="M2 14h40v23H2Z" fill="#75c4f0"/><path d="M2 15h40" stroke="#abe1fa"/></svg><span>工作资料</span></div>
        <section class="notes-window" aria-label="备忘录背景窗口"><div class="notes-titlebar"><div class="traffic-lights decorative"><i></i><i></i><i></i></div><span>备忘录</span>${icon('compose','',16)}</div><div class="notes-body"><aside><strong>iCloud</strong><div class="notes-folder active">${icon('folder','',15)} 备忘录 <span>6</span></div><div class="notes-folder">${icon('folder','',15)} 工作 <span>3</span></div><div class="notes-folder">${icon('folder','',15)} 阅读 <span>8</span></div></aside><article><time>2026年10月27日 09:42</time><h2>今天的工作</h2><p>先完成一件事，再整理下一件事。</p><p class="note-check"><span>✓</span> 阅读界面研究笔记</p><p class="note-check"><span></span> 比较截图里的细节</p><p class="note-check"><span></span> 写下第一轮使用感受</p><div class="note-rule"></div><h3>随手记</h3><p>看得见的变化，比解释更直接。<br>让内容留在原来的上下文里。</p></article></div></section>
        <section class="chrome-window" aria-label="模拟 Chrome 中的 ChatGPT"><div class="chrome-tabstrip" data-window-drag><div class="traffic-lights"><button class="traffic-close" title="关闭模拟 Chrome 窗口" aria-label="关闭模拟 Chrome 窗口"></button><button class="traffic-minimize" title="最小化模拟 Chrome 窗口" aria-label="最小化模拟 Chrome 窗口"></button><button class="traffic-maximize" title="切换模拟窗口最大化" aria-label="切换模拟窗口最大化"></button></div><div class="chrome-tab"><span class="chrome-favicon">${icon('globe','',14)}</span><span class="chrome-tab-label">界面的比例与注意力 — ChatGPT</span><span class="tab-close">×</span></div><span class="tab-plus">+</span></div>
          <div class="chrome-toolbar"><span class="chrome-nav">${icon('back','',17)}${icon('forward','faded',17)}${icon('reload','',16)}</span><div class="chrome-address">${icon('tune','',14)}<span>chatgpt.com</span><span class="address-spacer"></span>${icon('star','',16)}</div><span class="chrome-profile">D</span>${icon('more','chrome-menu',18)}</div>
          <div class="chat-shell"><aside class="chat-sidebar"><div class="sidebar-top"><button class="icon-button sidebar-toggle" title="收起边栏" aria-label="收起边栏">${icon('sidebar','',20)}</button><button class="icon-button thread-new" title="切换到另一段模拟对话" aria-label="新聊天">${icon('compose','',20)}</button></div><div class="sidebar-nav"><button class="sidebar-item thread-new">${icon('compose')}<span>新聊天</span><small>⇧ ⌘ O</small></button><button class="sidebar-item chat-search">${icon('search')}<span>搜索聊天</span><small>⌘ K</small></button><div class="sidebar-item decorative">${icon('image')}<span>图片</span></div></div><input class="sidebar-search" placeholder="搜索这两段模拟对话" aria-label="搜索模拟聊天" hidden><div class="sidebar-heading">项目</div><div class="sidebar-item decorative project-row">${icon('folder')}<span>界面研究</span></div><div class="sidebar-heading recent-heading">聊天</div><button class="sidebar-thread" data-thread="thread-a">界面的比例与注意力</button><button class="sidebar-thread" data-thread="thread-b">阅读笔记 · 空间与秩序</button><div class="sidebar-bottom"><span class="chat-avatar">D</span><span><b>Demo</b><small>个人工作空间</small></span>${icon('more','',17)}</div></aside>
          <main class="chat-main"><header class="chat-header"><button class="icon-button sidebar-reopen" title="展开边栏" aria-label="展开边栏">${icon('sidebar','',20)}</button><div class="chat-model">ChatGPT ${icon('down','',16)}</div><div class="chat-header-right"><span class="share-label">${icon('share','',15)} 分享</span>${icon('more','',21)}</div></header><div class="chat-scroll"><div class="conversation"></div></div><div class="composer-region"><div class="chat-composer"><div class="attachment-tray" hidden></div><textarea class="chat-input" rows="1" aria-label="ChatGPT 模拟输入框" placeholder="询问任何问题" spellcheck="false"></textarea><div class="composer-actions"><span class="composer-add">${icon('plus','',21)}</span><div class="composer-right">${icon('mic','',19)}<button class="composer-send" disabled title="原型演示附件，不发送聊天消息" aria-label="原型不发送聊天消息">${icon('arrow','',19)}</button></div></div></div><div class="chat-footnote">ChatGPT 也可能会犯错。请核查重要信息。</div></div></main></div><div class="chrome-resize" role="separator" aria-label="拖动调整模拟窗口尺寸" tabindex="0"></div></section>
        <div class="mac-dock" aria-label="模拟 Dock"><button data-dock="finder" title="Finder">${dockIcon('finder')}</button><button data-dock="chrome" title="Chrome">${dockIcon('chrome')}<span class="dock-dot"></span></button><button data-dock="notes" title="备忘录">${dockIcon('notes')}<span class="dock-dot"></span></button><button data-dock="preview" title="预览">${dockIcon('preview')}</button><span class="dock-divider"></span><span class="dock-static" title="系统设置">${dockIcon('settings')}</span><span class="dock-static" title="废纸篓">${dockIcon('trash')}</span></div>`;
      this.window = this.element.querySelector('.chrome-window');
      this.input = this.element.querySelector('.chat-input');
      this.scroll = this.element.querySelector('.chat-scroll');
      this.bind();
    }
    bind() {
      this.input.addEventListener('input', () => { this.threads.get(this.thread).draft = this.input.value; this.adjustInput(); this.emit('draft-changed'); });
      this.element.querySelectorAll('[data-thread]').forEach(el => el.addEventListener('click', () => this.setThread(el.dataset.thread)));
      this.element.querySelectorAll('.thread-new').forEach(el => el.addEventListener('click', () => this.setThread(this.thread === 'thread-a' ? 'thread-b' : 'thread-a')));
      this.element.querySelectorAll('.sidebar-toggle,.sidebar-reopen').forEach(el => el.addEventListener('click', () => this.window.classList.toggle('sidebar-collapsed')));
      this.element.querySelector('.chat-search').addEventListener('click', () => {const input=this.element.querySelector('.sidebar-search');input.hidden=!input.hidden;if(!input.hidden)input.focus();});
      this.element.querySelector('.sidebar-search').addEventListener('input', e => {this.element.querySelectorAll('[data-thread]').forEach(el=>el.hidden=!el.textContent.includes(e.target.value));});
      this.element.querySelector('.traffic-maximize').addEventListener('click', () => this.setWindowMode(this.windowMode === 'maximized' ? 'normal' : 'maximized'));
      this.element.querySelector('.traffic-close').addEventListener('click', () => this.setScene('desktop'));
      this.element.querySelector('.traffic-minimize').addEventListener('click', () => this.setScene('desktop'));
      this.element.querySelector('[data-dock="chrome"]').addEventListener('click', () => this.setScene('chrome'));
      this.element.querySelector('[data-dock="notes"]').addEventListener('click', () => {this.setScene('workspace'); this.element.querySelector('.notes-window').classList.toggle('notes-front');});
      this.element.querySelector('[data-dock="finder"]').addEventListener('click', () => this.setScene('desktop'));
      this.element.querySelector('[data-dock="preview"]').addEventListener('click', () => this.setScene('workspace'));
      const drag = this.element.querySelector('[data-window-drag]');
      drag.addEventListener('dblclick', e => {if(!e.target.closest('button')) this.setWindowMode(this.windowMode==='maximized'?'normal':'maximized');});
      drag.addEventListener('pointerdown', e => this.beginPointer(e,'move'));
      const resize = this.element.querySelector('.chrome-resize');
      resize.addEventListener('pointerdown', e => this.beginPointer(e,'resize'));
      resize.addEventListener('keydown',e=>{if(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)){e.preventDefault();this.bounds.width=clamp(this.bounds.width+(e.key==='ArrowLeft'?-20:e.key==='ArrowRight'?20:0),620,this.width-this.bounds.x);this.bounds.height=clamp(this.bounds.height+(e.key==='ArrowUp'?-20:e.key==='ArrowDown'?20:0),430,this.height-this.insets.bottom-this.bounds.y);this.normalBounds={...this.bounds};this.applyBounds();}});
      this.element.addEventListener('pointermove', e => this.movePointer(e));
      this.element.addEventListener('pointerup', e => this.endPointer(e));
      this.element.addEventListener('pointercancel', e => this.endPointer(e));
    }
    beginPointer(e, kind) {
      if(e.button!==0||e.target.closest('button')||this.windowMode==='maximized')return;
      this.pointer={id:e.pointerId,x:e.clientX,y:e.clientY,kind,bounds:{...this.bounds}};
      e.currentTarget.setPointerCapture(e.pointerId); this.pointer.capture=e.currentTarget;
      this.window.classList.add('window-moving'); e.preventDefault();
    }
    movePointer(e) {
      if(!this.pointer||this.pointer.id!==e.pointerId)return;
      const scale=this.element.getBoundingClientRect().width/this.width||1;
      const dx=(e.clientX-this.pointer.x)/scale,dy=(e.clientY-this.pointer.y)/scale,b=this.pointer.bounds;
      if(this.pointer.kind==='move'){this.bounds.x=clamp(b.x+dx,0,this.width-180);this.bounds.y=clamp(b.y+dy,this.insets.top,this.height-this.insets.bottom-100);}
      else{this.bounds.width=clamp(b.width+dx,620,this.width-this.bounds.x);this.bounds.height=clamp(b.height+dy,430,this.height-this.insets.bottom-this.bounds.y);}
      this.normalBounds={...this.bounds}; this.applyBounds();
    }
    endPointer(e) { if(!this.pointer||e.pointerId!==this.pointer.id)return;this.window.classList.remove('window-moving');if(this.pointer.capture.hasPointerCapture(e.pointerId))this.pointer.capture.releasePointerCapture(e.pointerId);this.pointer=null;this.emit('window-changed',{bounds:{...this.bounds}}); }
    applyBounds() {
      Object.assign(this.window.style,{left:`${this.bounds.x}px`,top:`${this.bounds.y}px`,width:`${this.bounds.width}px`,height:`${this.bounds.height}px`});
      this.window.classList.toggle('chrome-narrow',this.bounds.width<900);
      this.window.classList.toggle('is-maximized',this.windowMode==='maximized');
    }
    setSize(width,height) {
      this.width=width;this.height=height;this.element.style.width=`${width}px`;this.element.style.height=`${height}px`;
      if(this.windowMode==='maximized')this.bounds={x:0,y:this.insets.top,width,height:height-this.insets.top-this.insets.bottom};
      else{this.bounds.width=Math.min(this.bounds.width,width-60);this.bounds.height=Math.min(this.bounds.height,height-140);this.bounds.x=clamp(this.bounds.x,0,width-this.bounds.width);this.bounds.y=clamp(this.bounds.y,this.insets.top,height-this.insets.bottom-this.bounds.height);this.normalBounds={...this.bounds};}
      this.applyBounds(); this.element.classList.toggle('desktop-compact',width<1300);return this.snapshot();
    }
    setTheme(theme) {this.theme=theme==='dark'?'dark':'light';this.element.dataset.theme=this.theme;this.emit('theme-changed',{theme:this.theme});}
    setScene(scene) {this.scene=['chrome','desktop','workspace'].includes(scene)?scene:'chrome';this.element.dataset.scene=this.scene;this.element.querySelector('.mac-app-name').textContent=this.scene==='desktop'?'Finder':'Chrome';if(this.scene!=='workspace')this.element.querySelector('.notes-window').classList.remove('notes-front');this.emit('scene-changed',{scene:this.scene});}
    setWindowMode(mode) {
      const next=mode==='maximized'?'maximized':'normal';if(next===this.windowMode)return;
      if(next==='maximized'){this.normalBounds={...this.bounds};this.bounds={x:0,y:this.insets.top,width:this.width,height:this.height-this.insets.top-this.insets.bottom};}
      else {
        this.bounds={...this.normalBounds};
        this.bounds.width=Math.min(this.bounds.width,this.width-30);
        this.bounds.height=Math.min(this.bounds.height,this.height-this.insets.top-this.insets.bottom);
        this.bounds.x=clamp(this.bounds.x,0,this.width-this.bounds.width);
        this.bounds.y=clamp(this.bounds.y,this.insets.top,this.height-this.insets.bottom-this.bounds.height);
      }
      this.windowMode=next;this.applyBounds();this.emit('window-changed',{mode:next,bounds:{...this.bounds}});
    }
    setWindowWidth(value) {if(this.windowMode==='maximized')this.setWindowMode('normal');const width=value<=1?this.width*value:value;this.bounds.width=clamp(width,620,this.width-30);this.bounds.x=Math.min(this.bounds.x,this.width-this.bounds.width);this.normalBounds={...this.bounds};this.applyBounds();this.emit('window-changed',{bounds:{...this.bounds}});}
    setThread(id) {if(!this.threads.has(id)||this.thread===id)return;const previous=this.thread;this.threads.get(previous).draft=this.input.value;this.thread=id;this.renderThread();this.onThreadChange(id,previous);this.emit('thread-changed',{target:id,previous});}
    getThread() {return this.thread;}
    setDraft(value) {this.threads.get(this.thread).draft=String(value);this.input.value=String(value);this.adjustInput();}
    getDraft() {return this.input.value;}
    adjustInput() {this.input.style.height='auto';this.input.style.height=`${Math.min(122,Math.max(42,this.input.scrollHeight))}px`;}
    renderThread() {
      const t=this.threads.get(this.thread);
      this.element.querySelector('.chrome-tab-label').textContent=`${t.title} — ChatGPT`;
      this.element.querySelectorAll('[data-thread]').forEach(el=>el.classList.toggle('active',el.dataset.thread===this.thread));
      this.element.querySelector('.conversation').innerHTML=`<div class="chat-user-message">${text(t.user)}</div><div class="chat-assistant-message">${t.response}<div class="response-actions"><span>${icon('copy','',16)}</span><span>${icon('thumb','',16)}</span><span class="thumb-down">${icon('thumb','',16)}</span><span>${icon('sound','',16)}</span><span>${icon('retry','',16)}</span><span>${icon('more','',17)}</span></div></div>`;
      this.input.value=t.draft;this.renderAttachments();this.adjustInput();this.scroll.scrollTop=0;
    }
    setAttachment(entry) {
      const target=this.threads.get(entry.target);if(!target)return false;
      const prior=target.attachments.get(entry.operationID)||{};
      target.attachments.set(entry.operationID,{...prior,...entry,asset:entry.asset||prior.asset,progress:clamp(Number(entry.progress??prior.progress??0),0,100)});
      if(entry.target===this.thread)this.renderAttachments();return true;
    }
    clearAttachments(target) {
      if(target){this.threads.get(target)?.attachments.clear();}
      else this.threads.forEach(t=>t.attachments.clear());
      this.renderAttachments();
    }
    renderAttachments() {
      const tray=this.element.querySelector('.attachment-tray'), attachments=[...this.threads.get(this.thread).attachments.values()];
      tray.hidden=attachments.length===0;tray.replaceChildren();
      for(const item of attachments){
        if(!item.asset)continue;
        const card=document.createElement('div');card.className=`chat-attachment attachment-${item.status}`;card.dataset.operation=item.operationID;card.dataset.status=item.status;card.dataset.asset=item.asset.id;
        const title={uploading:`上传中 ${Math.round(item.progress)}%`,confirming:'正在确认附件',ready:'附件已就绪，尚未发送',failed:'上传失败',unknown:'结果待确认'}[item.status]||item.status;
        card.title=`${item.asset.label} · ${title}`;card.setAttribute('aria-label',card.title);
        const img=document.createElement('img');img.src=item.asset.src;img.alt=item.asset.label;img.draggable=false;card.append(img);
        if(item.status==='uploading'||item.status==='confirming'){const status=document.createElement('span');status.className='attachment-loading';status.innerHTML='<i></i>';card.append(status);const progress=document.createElement('span');progress.className='attachment-progress';progress.style.width=`${item.progress}%`;card.append(progress);}
        if(item.status==='failed'||item.status==='unknown'){const status=document.createElement('span');status.className='attachment-question';status.textContent=item.status==='failed'?'!':'?';card.append(status);}
        const label=document.createElement('span');label.className='attachment-accessible';label.textContent=title;card.append(label);tray.append(card);
      }
    }
    snapshot() {return {width:this.width,height:this.height,theme:this.theme,scene:this.scene,windowMode:this.windowMode,bounds:{...this.bounds},insets:{...this.insets},thread:this.thread,draft:this.getDraft(),threads:[...this.threads].map(([id,t])=>({id,title:t.title,draft:t.draft,attachments:[...t.attachments.values()].map(a=>({operationID:a.operationID,assetID:a.asset?.id,status:a.status,progress:a.progress}))}))};}
  }
  window.RiftDesktop=RiftDesktop;
})();
